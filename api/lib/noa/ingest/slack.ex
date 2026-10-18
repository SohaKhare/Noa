defmodule Noa.Ingest.Slack do
  @moduledoc """
  Slack's ingest boundary (1.14).

  Only messages from mapped, readable public or private channels reach `Noa.Work`.
  Direct messages, multi-person DMs, Slack Connect, bot messages and message subtypes
  other than edits/deletes are rejected before identities or events are written.
  """

  require Ash.Query

  alias Noa.Ingest.Slack.Client
  alias Noa.Work
  alias Noa.Work.{Channel, Identity}

  @default_history_limit 15
  @max_history_limit 200

  @type reason ::
          :direct_message
          | :shared_channel
          | :bot
          | :system_message
          | :empty
          | :invalid
          | :unknown_workspace

  @doc "Normalizes one ordinary Slack message event or history item for `Noa.Work`."
  def normalize(payload) when is_map(payload) do
    payload = stringify(payload)
    channel_type = payload["channel_type"]
    text = payload["text"] |> to_string() |> String.trim()

    cond do
      channel_type in ["im", "mpim"] ->
        {:ignore, :direct_message}

      payload["is_ext_shared_channel"] == true or payload["is_shared"] == true ->
        {:ignore, :shared_channel}

      present?(payload["bot_id"]) or is_map(payload["bot_profile"]) or payload["subtype"] == "bot_message" ->
        {:ignore, :bot}

      present?(payload["subtype"]) ->
        {:ignore, :system_message}

      text == "" ->
        {:ignore, :empty}

      not present?(payload["channel"]) or not present?(payload["ts"]) or not present?(payload["user"]) ->
        {:ignore, :invalid}

      true ->
        {:ok,
         %{
           platform: :slack,
           channel: payload["channel_name"] || payload["channel"],
           channel_id: payload["channel"],
           message_id: payload["channel"] <> ":" <> payload["ts"],
           author_id: payload["user"],
           author: payload["author"],
           text: text,
           at: slack_timestamp(payload["ts"])
         }}
    end
  end

  def normalize(_payload), do: {:ignore, :invalid}

  @doc "Ingests an event envelope by resolving its Slack workspace."
  def ingest(%{"team_id" => team_id, "event" => event} = envelope) do
    event = Map.put(event, "is_ext_shared_channel", envelope["is_ext_shared_channel"] == true)

    with {:ok, org_id} <- org_id_for(team_id), do: ingest(org_id, event)
  end

  def ingest(payload) when is_map(payload) do
    payload = stringify(payload)

    case payload do
      %{"team_id" => _, "event" => _} -> ingest(payload)
      _ -> {:ignore, :invalid}
    end
  end

  @doc "Ingests one message into a known workspace through the event log."
  def ingest(org_id, payload) do
    payload = stringify(payload)

    with {:ok, message} <- normalize(payload),
         :ok <- readable_channel(org_id, message.channel_id),
         {:ok, author} <- author_name(org_id, message.author_id),
         do: Work.record_message(org_id, %{message | author: author})
  end

  @doc "Applies a Slack `message_changed` event to an existing episode."
  def edit(%{"team_id" => team_id, "event" => event}) do
    with {:ok, org_id} <- org_id_for(team_id), do: edit(org_id, event)
  end

  def edit(org_id, payload) do
    payload = stringify(payload)
    message = payload["message"] || payload
    message = Map.put_new(message, "channel", payload["channel"])

    with {:ok, normalized} <- normalize(Map.delete(message, "subtype")),
         :ok <- readable_channel(org_id, normalized.channel_id),
         do: Work.edit_message(org_id, normalized)
  end

  @doc "Applies a Slack `message_deleted` event to an existing episode."
  def delete(%{"team_id" => team_id, "event" => event}) do
    with {:ok, org_id} <- org_id_for(team_id), do: delete(org_id, event)
  end

  def delete(org_id, payload) do
    payload = stringify(payload)
    channel_id = payload["channel"]
    ts = payload["deleted_ts"] || get_in(payload, ["previous_message", "ts"])

    cond do
      not present?(channel_id) or not present?(ts) ->
        {:ignore, :invalid}

      true ->
        with :ok <- readable_channel(org_id, channel_id),
             do: Work.delete_message(org_id, :slack, channel_id <> ":" <> ts)
    end
  end

  @doc "Creates or refreshes a Slack identity without ingesting a message."
  def ingest_member(org_id, user) do
    user = stringify(user)

    cond do
      user["is_bot"] == true or user["id"] == "USLACKBOT" -> {:ignore, :bot}
      user["deleted"] == true -> {:ignore, :deleted}
      not present?(user["id"]) -> {:ignore, :invalid}
      true -> Work.identify(org_id, :slack, user["id"], display_name(user))
    end
  end

  @doc "Synchronizes all human Slack users into Noa identities."
  def sync_users(org_id, opts \\ []) do
    with token when is_binary(token) <- opts[:token] || Noa.Connectors.slack_token(org_id),
         {:ok, users} <- Client.users(token, opts) do
      results = Enum.map(users, &ingest_member(org_id, &1))
      {:ok, Enum.count(results, &match?({:ok, _}, &1))}
    else
      nil -> {:error, :not_connected}
      error -> error
    end
  end

  @doc "Lists member public/private channels that may be mapped for this workspace."
  def workspace_channels(org_id, opts \\ []) do
    with token when is_binary(token) <- opts[:token] || Noa.Connectors.slack_token(org_id),
         {:ok, channels} <- Client.channels(token, opts) do
      {:ok,
       channels
       |> Enum.filter(fn channel ->
         channel["is_member"] == true and channel["is_archived"] != true and channel["is_shared"] != true and
           channel["is_ext_shared"] != true and channel["is_org_shared"] != true
       end)
       |> Enum.map(&%{id: &1["id"], name: &1["name"], private: &1["is_private"] == true})
       |> Enum.sort_by(& &1.name)}
    else
      nil -> {:error, :not_connected}
      error -> error
    end
  end

  @doc "Backfills the newest Slack history page and records it oldest first."
  def backfill(org_id, channel_id, opts \\ []) do
    limit = opts |> Keyword.get(:limit, history_limit()) |> min(@max_history_limit) |> max(1)

    with token when is_binary(token) <- opts[:token] || Noa.Connectors.slack_token(org_id),
         {:ok, body} <- Client.history(token, channel_id, limit, opts) do
      results =
        (body["messages"] || [])
        |> Enum.reverse()
        |> Enum.map(&ingest(org_id, Map.put(&1, "channel", channel_id)))

      {:ok, Enum.count(results, &accepted?/1)}
    else
      nil -> {:error, :not_connected}
      error -> error
    end
  end

  @doc "Sends a direct Slack message to the person's linked Slack identity."
  def dm(%Work.Person{id: person_id, org_id: org_id}, text, opts \\ []) do
    identity =
      Identity
      |> Ash.Query.filter(person_id == ^person_id and platform == :slack)
      |> Ash.read!(authorize?: false)
      |> List.first()

    token = opts[:token] || Noa.Connectors.slack_token(org_id)

    cond do
      not is_binary(token) ->
        {:error, :not_connected}

      is_nil(identity) ->
        {:error, :no_slack_account}

      true ->
        with {:ok, opened} <- Client.open_dm(token, identity.external_id, opts),
             channel when is_binary(channel) <- get_in(opened, ["channel", "id"]) || {:error, :invalid_response},
             {:ok, sent} <- Client.post_message(token, channel, text, opts),
             do: {:ok, sent}
    end
  end

  @doc "Whether the Slack app has OAuth credentials and a webhook signing secret."
  def configured?, do: Client.configured?()

  defp author_name(org_id, user_id) do
    existing =
      Identity
      |> Ash.Query.filter(org_id == ^org_id and platform == :slack and external_id == ^user_id)
      |> Ash.read_one!(authorize?: false)

    cond do
      existing && present?(existing.display_name) ->
        {:ok, existing.display_name}

      token = Noa.Connectors.slack_token(org_id) ->
        case Client.user(token, user_id) do
          {:ok, %{"user" => user}} ->
            case ingest_member(org_id, user) do
              {:ok, identity} -> {:ok, identity.display_name}
              {:ignore, reason} -> {:ignore, reason}
              error -> error
            end

          _unavailable ->
            # A transient users.info failure must not discard a valid mapped-channel
            # message. Store the stable Slack id now; a later sync enriches its name.
            {:ok, user_id}
        end

      true ->
        {:error, :not_connected}
    end
  end

  defp readable_channel(org_id, external_id) do
    Channel
    |> Ash.Query.filter(org_id == ^org_id and platform == :slack and external_id == ^external_id and read == true)
    |> Ash.exists?(authorize?: false)
    |> case do
      true -> :ok
      false -> {:error, :not_read}
    end
  end

  defp org_id_for(team_id) do
    case Noa.Connectors.org_for_slack_team(team_id) do
      nil -> {:ignore, :unknown_workspace}
      org_id -> {:ok, org_id}
    end
  end

  defp display_name(user) do
    profile = user["profile"] || %{}

    profile["display_name"]
    |> present_or(profile["real_name"])
    |> present_or(user["real_name"])
    |> present_or(user["name"])
  end

  defp present_or(value, fallback), do: if(present?(value), do: value, else: fallback)
  defp accepted?({:ok, _}), do: true
  defp accepted?({:duplicate, _}), do: true
  defp accepted?(_), do: false

  defp history_limit do
    Application.get_env(:noa, __MODULE__, [])[:history_limit] || @default_history_limit
  end

  defp slack_timestamp(value) when is_binary(value) do
    case Float.parse(value) do
      {seconds, _} -> DateTime.from_unix!(trunc(seconds * 1_000_000), :microsecond)
      :error -> DateTime.utc_now()
    end
  rescue
    _ -> DateTime.utc_now()
  end

  defp slack_timestamp(_), do: DateTime.utc_now()
  defp stringify(map) when is_map(map), do: Map.new(map, fn {key, value} -> {to_string(key), stringify(value)} end)
  defp stringify(list) when is_list(list), do: Enum.map(list, &stringify/1)
  defp stringify(value), do: value
  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
