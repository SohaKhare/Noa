defmodule Noa.Ingest.Discord do
  @moduledoc """
  Discord's boundary for Noa (1.13).

  The gateway consumer and backfill both pass raw Discord message payloads through
  this module. It deliberately does not write to the database itself: accepted
  messages are handed to `Noa.Work.record_message/2`, which owns the mapped-channel
  privacy gate, identity resolution, idempotency and event-log write.
  """

  require Ash.Query

  alias Noa.Work
  alias Noa.Work.Channel

  @discord_api "https://discord.com/api/v10"
  @default_limit 100
  @max_limit 100

  @type reason ::
          :direct_message
          | :bot
          | :system_message
          | :empty
          | :wrong_guild
          | :invalid
          | :unknown_workspace

  @doc "Normalizes a Discord MESSAGE_CREATE or backfill payload into Work's message shape."
  @spec normalize(map()) :: {:ok, map()} | {:ignore, reason()}
  def normalize(payload) when is_map(payload) do
    payload = normalize_payload(payload)
    author = payload["author"] || %{}
    guild_id = payload["guild_id"]
    content = payload["content"] |> to_string() |> String.trim()

    cond do
      is_nil(guild_id) or guild_id == "" ->
        {:ignore, :direct_message}

      author["bot"] == true or author["system"] == true ->
        {:ignore, :bot}

      payload["webhook_id"] ->
        {:ignore, :bot}

      payload["type"] in ["CHANNEL_PINNED_MESSAGE", 6] ->
        {:ignore, :system_message}

      content == "" ->
        {:ignore, :empty}

      not present?(payload["id"]) or not present?(payload["channel_id"]) ->
        {:ignore, :invalid}

      not present?(author["id"]) ->
        {:ignore, :invalid}

      not allowed_guild?(guild_id) ->
        {:ignore, :wrong_guild}

      true ->
        {:ok,
         %{
           platform: :discord,
           guild_id: guild_id,
           channel: payload["channel_name"] || payload["channel_id"],
           channel_id: payload["channel_id"],
           message_id: payload["id"],
           author_id: author["id"],
           author: author["global_name"] || author["display_name"] || author["username"],
           text: content,
           at: timestamp(payload["timestamp"])
         }}
    end
  end

  def normalize(_payload), do: {:ignore, :invalid}

  @doc "Forwards one accepted Discord message through the event-log-backed Work API."
  @spec ingest(String.t(), map()) :: {:ok, term()} | {:duplicate, term()} | {:ignore, reason()} | {:error, term()}
  def ingest(org_id, payload) do
    with {:ok, message} <- normalize(payload) do
      Work.record_message(org_id, message)
    end
  end

  @doc "Resolves a Discord gateway message to the workspace mapped to its channel."
  @spec ingest(map()) :: term()
  def ingest(payload) do
    payload = payload |> normalize_payload() |> with_channel_name()

    with {:ok, org_id} <- org_id_for(payload), do: ingest(org_id, payload)
  end

  # Gateway messages carry only the channel id, and channels are mapped by name, so
  # ask Discord once per channel and remember the answer.
  defp with_channel_name(%{"channel_name" => name} = payload) when is_binary(name), do: payload

  defp with_channel_name(%{"channel_id" => id} = payload) when is_binary(id) do
    case channel_name(id) do
      nil -> payload
      name -> Map.put(payload, "channel_name", name)
    end
  end

  defp with_channel_name(payload), do: payload

  defp channel_name(id) do
    case :persistent_term.get({__MODULE__, :channel, id}, :unknown) do
      :unknown ->
        name =
          case Nostrum.Api.Channel.get(String.to_integer(id)) do
            {:ok, %{name: name}} when is_binary(name) -> name
            _ -> nil
          end

        if name, do: :persistent_term.put({__MODULE__, :channel, id}, name)
        name

      name ->
        name
    end
  rescue
    _ -> nil
  end

  @doc "A MESSAGE_UPDATE: the message's new text replaces the old (2.10)."
  def edit(payload) do
    payload = payload |> normalize_payload() |> with_channel_name()

    with {:ok, message} <- normalize(payload),
         {:ok, org_id} <- org_id_for(payload),
         do: Work.edit_message(org_id, message)
  end

  @doc "A MESSAGE_DELETE: the message's text is erased from Noa (2.10)."
  def delete(payload) do
    payload = normalize_payload(payload)

    cond do
      not present?(payload["id"]) -> {:ignore, :invalid}
      not allowed_guild?(payload["guild_id"]) -> {:ignore, :wrong_guild}
      true -> with {:ok, org_id} <- org_id_for(payload), do: Work.delete_message(org_id, :discord, payload["id"])
    end
  end

  @doc "Links a Discord guild member to a Noa identity without ingesting a message."
  @spec ingest_member(String.t(), map()) :: {:ok, term()} | {:ignore, reason()} | {:error, term()}
  def ingest_member(org_id, payload) do
    payload = normalize_payload(payload)
    user = payload["user"] || payload["author"] || %{}

    cond do
      not allowed_guild?(payload["guild_id"]) -> {:ignore, :wrong_guild}
      user["bot"] == true -> {:ignore, :bot}
      not present?(user["id"]) -> {:ignore, :invalid}
      true -> Work.identify(org_id, :discord, user["id"], display_name(user))
    end
  end

  @doc "Text channels in the workspace's connected server, for mapping in onboarding: `{:ok, [%{id, name}]}`."
  def guild_channels(org_id \\ nil) do
    guild =
      (org_id && Noa.Connectors.guild_for(org_id)) || Application.get_env(:noa, :discord_guild_id) ||
        System.get_env("DISCORD_GUILD_ID")

    if enabled?() and present?(guild) do
      case Nostrum.Api.Guild.channels(String.to_integer(guild)) do
        {:ok, channels} ->
          {:ok,
           channels
           |> Enum.filter(&(&1.type in [0, 5]))
           |> Enum.sort_by(&(&1.position || 0))
           |> Enum.map(&%{id: Integer.to_string(&1.id), name: &1.name})}

        error ->
          error
      end
    else
      {:error, :not_connected}
    end
  rescue
    e -> {:error, e}
  end

  @doc """
  Sends a direct message from Noa's bot to the person's Discord account (the identity
  Noa linked when they first wrote in a mapped channel). `{:ok, message}`, or
  `{:error, :no_discord_account}` / `{:error, :not_connected}`.
  """
  def dm(%Noa.Work.Person{id: person_id}, text) do
    identity =
      Noa.Work.Identity
      |> Ash.Query.filter(person_id == ^person_id and platform == :discord)
      |> Ash.read!(authorize?: false)
      |> Enum.find(&Regex.match?(~r/^\d+$/, &1.external_id))

    cond do
      not enabled?() ->
        {:error, :not_connected}

      is_nil(identity) ->
        {:error, :no_discord_account}

      true ->
        with {:ok, channel} <- Nostrum.Api.User.create_dm(String.to_integer(identity.external_id)),
             do: Nostrum.Api.Message.create(channel.id, String.slice(text, 0, 2000))
    end
  rescue
    e -> {:error, e}
  end

  @doc "The workspace a server belongs to: connected in Settings, or the platform setting."
  def org_for_guild(guild_id) do
    configured = Application.get_env(:noa, :discord_org_id) || System.get_env("DISCORD_ORG_ID")

    cond do
      org = Noa.Connectors.org_for_guild(guild_id) -> {:ok, org}
      present?(configured) and allowed_by_env?(guild_id) -> {:ok, configured}
      true -> {:ignore, :unknown_workspace}
    end
  end

  @doc "Returns whether the Discord gateway should be started in this environment."
  def enabled?, do: present?(Application.get_env(:noa, :discord_bot_token) || System.get_env("DISCORD_BOT_TOKEN"))

  @doc false
  def guild_allowed?(guild_id), do: allowed_guild?(guild_id)

  @doc false
  def normalize_payload(%{__struct__: _} = payload), do: payload |> Map.from_struct() |> normalize_payload()

  def normalize_payload(payload) when is_map(payload) do
    Map.new(payload, fn {key, value} -> {to_string(key), normalize_value(to_string(key), value)} end)
  end

  def normalize_payload(payload), do: payload

  # Nostrum gives snowflakes as integers and timestamps as DateTime structs.
  defp normalize_value(key, value)
       when is_integer(value) and (key == "id" or binary_part(key, byte_size(key), -3) == "_id"),
       do: Integer.to_string(value)

  defp normalize_value(_key, value), do: normalize_value(value)

  defp normalize_value(%DateTime{} = value), do: value
  defp normalize_value(%{__struct__: _} = value), do: value |> Map.from_struct() |> normalize_payload()
  defp normalize_value(value) when is_map(value), do: normalize_payload(value)
  defp normalize_value(value) when is_list(value), do: Enum.map(value, &normalize_value/1)
  defp normalize_value(value), do: value

  # The workspace whose org admin connected this server (Settings → Connectors), then the
  # platform's single-server setting, then a channel mapped by its Discord id.
  defp org_id_for(payload) do
    configured_org = Application.get_env(:noa, :discord_org_id) || System.get_env("DISCORD_ORG_ID")
    connected_org = Noa.Connectors.org_for_guild(payload["guild_id"])

    cond do
      connected_org -> {:ok, connected_org}
      present?(configured_org) and allowed_guild?(payload["guild_id"]) -> {:ok, configured_org}
      present?(payload["channel_id"]) -> org_id_for_channel(payload["channel_id"])
      true -> {:ignore, :unknown_workspace}
    end
  end

  defp org_id_for_channel(channel_id) do
    Channel
    |> Ash.Query.filter(platform == :discord and external_id == ^to_string(channel_id) and read == true)
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, [%{org_id: org_id} | _]} -> {:ok, org_id}
      {:ok, []} -> {:ignore, :unknown_workspace}
      {:error, error} -> {:error, error}
    end
  end

  defp display_name(user), do: user["global_name"] || user["display_name"] || user["username"]

  @doc """
  Backfills a mapped channel's recent messages (up to `:max_pages` of 100, default 5)
  with Discord's REST API, recorded oldest first. Runs when an org admin maps a channel.
  """
  @spec backfill(String.t(), String.t(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def backfill(org_id, channel_id, opts \\ []) do
    token = opts[:token] || token()
    limit = opts |> Keyword.get(:limit, @default_limit) |> min(@max_limit) |> max(1)
    max_pages = Keyword.get(opts, :max_pages, 5)

    guild =
      Noa.Connectors.guild_for(org_id) || Application.get_env(:noa, :discord_guild_id) ||
        System.get_env("DISCORD_GUILD_ID")

    if present?(token) do
      with {:ok, messages} <- fetch_pages(channel_id, token, limit, max_pages, nil, [], opts[:req_options] || []) do
        # Discord pages newest-first; record oldest-first so the log and extraction
        # windows follow the conversation. REST messages carry no guild_id, so add it.
        results =
          messages
          |> Enum.sort_by(&String.to_integer(to_string(&1["id"])))
          |> Enum.map(&ingest(org_id, Map.put_new(&1, "guild_id", guild)))

        {:ok, Enum.count(results, &accepted_result?/1)}
      end
    else
      {:error, :missing_discord_bot_token}
    end
  end

  defp fetch_pages(_channel_id, _token, _limit, 0, _before, acc, _req), do: {:ok, acc}

  defp fetch_pages(channel_id, token, limit, pages, before, acc, req) do
    params = [limit: limit] |> maybe_before(before)

    case Req.get(
           "#{@discord_api}/channels/#{channel_id}/messages",
           [headers: [{"authorization", "Bot #{token}"}], params: params, retry: false] ++ req
         ) do
      {:ok, %{status: 200, body: messages}} when is_list(messages) ->
        acc = acc ++ messages
        oldest = messages |> List.last() |> then(&(&1 && &1["id"]))

        if length(messages) < limit or is_nil(oldest),
          do: {:ok, acc},
          else: fetch_pages(channel_id, token, limit, pages - 1, oldest, acc, req)

      {:ok, %{status: status, body: body}} ->
        {:error, {:discord_api, status, body}}

      {:error, reason} ->
        {:error, {:discord_api, reason}}
    end
  end

  defp maybe_before(params, nil), do: params
  defp maybe_before(params, before), do: Keyword.put(params, :before, before)

  defp accepted_result?({:ok, _}), do: true
  defp accepted_result?({:duplicate, _}), do: true
  defp accepted_result?(_), do: false

  defp allowed_guild?(guild_id) do
    if Noa.Connectors.org_for_guild(guild_id), do: true, else: allowed_by_env?(guild_id)
  end

  defp allowed_by_env?(guild_id) do
    case Application.get_env(:noa, :discord_guild_id) || System.get_env("DISCORD_GUILD_ID") do
      nil -> true
      "" -> true
      configured -> to_string(configured) == to_string(guild_id)
    end
  end

  defp token, do: Application.get_env(:noa, :discord_bot_token) || System.get_env("DISCORD_BOT_TOKEN")

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp timestamp(nil), do: DateTime.utc_now()
  defp timestamp(%DateTime{} = at), do: at

  defp timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> at
      _ -> DateTime.utc_now()
    end
  end

  defp timestamp(_), do: DateTime.utc_now()

  defmodule Backfill do
    @moduledoc "Loads a newly mapped Discord channel's recent history (2.10, 1.18)."
    use Oban.Worker, queue: :extraction, max_attempts: 3, unique: [period: 3600, keys: [:org_id, :channel_id]]

    @impl Oban.Worker
    def perform(%Oban.Job{args: %{"org_id" => org_id, "channel_id" => channel_id}}) do
      case Noa.Ingest.Discord.backfill(org_id, channel_id) do
        {:ok, _n} -> :ok
        {:error, :missing_discord_bot_token} -> :ok
        error -> error
      end
    end
  end
end
