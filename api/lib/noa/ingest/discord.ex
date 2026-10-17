defmodule Noa.Ingest.Discord do
  @moduledoc """
  Discord's boundary for Noa (1.13).

  The gateway consumer and backfill both pass raw Discord message payloads through
  this module. It deliberately does not write to the database itself: accepted
  messages are handed to `Noa.Work.record_message/2`, which owns the mapped-channel
  privacy gate, identity resolution, idempotency and event-log write.
  """

  alias Noa.Work

  @discord_api "https://discord.com/api/v10"
  @default_limit 100
  @max_limit 100

  @type reason :: :direct_message | :bot | :system_message | :empty | :wrong_guild | :invalid

  @doc "Normalizes a Discord MESSAGE_CREATE or backfill payload into Work's message shape."
  @spec normalize(map()) :: {:ok, map()} | {:ignore, reason()}
  def normalize(payload) when is_map(payload) do
    author = payload["author"] || %{}
    guild_id = payload["guild_id"]
    content = payload["content"] |> to_string() |> String.trim()

    cond do
      is_nil(guild_id) or guild_id == "" -> {:ignore, :direct_message}
      author["bot"] == true or author["system"] == true -> {:ignore, :bot}
      payload["webhook_id"] -> {:ignore, :bot}
      payload["type"] in ["CHANNEL_PINNED_MESSAGE", 6] -> {:ignore, :system_message}
      content == "" -> {:ignore, :empty}
      not present?(payload["id"]) or not present?(payload["channel_id"]) -> {:ignore, :invalid}
      not present?(author["id"]) -> {:ignore, :invalid}
      not allowed_guild?(guild_id) -> {:ignore, :wrong_guild}
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

  @doc "Backfills mapped Discord channel messages, oldest first, with Discord's REST API."
  @spec backfill(String.t(), String.t(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def backfill(org_id, channel_id, opts \ []) do
    token = opts[:token] || token()
    limit = opts |> Keyword.get(:limit, @default_limit) |> min(@max_limit) |> max(1)
    max_pages = Keyword.get(opts, :max_pages, :infinity)

    if present?(token) do
      do_backfill(org_id, channel_id, token, limit, max_pages, nil, 0)
    else
      {:error, :missing_discord_bot_token}
    end
  end

  defp do_backfill(_org_id, _channel_id, _token, _limit, 0, _before, count), do: {:ok, count}

  defp do_backfill(org_id, channel_id, token, limit, max_pages, before, count) do
    params = [limit: limit] |> maybe_before(before)

    case Req.get("#{@discord_api}/channels/#{channel_id}/messages",
           headers: [{"authorization", "Bot #{token}"}],
           params: params
         ) do
      {:ok, %{status: 200, body: messages}} when is_list(messages) ->
        # Discord returns newest-first; replay oldest-first so the event log and
        # extraction windows follow the conversation's natural order.
        results = messages |> Enum.reverse() |> Enum.map(&ingest(org_id, &1))
        next_before = messages |> List.last() |> then(&if &1, do: &1["id"], else: nil)
        pages = if max_pages == :infinity, do: :infinity, else: max_pages - 1

        if length(messages) < limit or is_nil(next_before) do
          {:ok, count + Enum.count(results, &accepted_result?/1)}
        else
          do_backfill(org_id, channel_id, token, limit, pages, next_before,
            count + Enum.count(results, &accepted_result?/1))
        end

      {:ok, %{status: status, body: body}} -> {:error, {:discord_api, status, body}}
      {:error, reason} -> {:error, {:discord_api, reason}}
    end
  end

  defp maybe_before(params, nil), do: params
  defp maybe_before(params, before), do: Keyword.put(params, :before, before)

  defp accepted_result?({:ok, _}), do: true
  defp accepted_result?({:duplicate, _}), do: true
  defp accepted_result?(_), do: false

  defp allowed_guild?(guild_id) do
    case Application.get_env(:noa, :discord_guild_id) || System.get_env("DISCORD_GUILD_ID") do
      nil -> true
      "" -> true
      configured -> to_string(configured) == to_string(guild_id)
    end
  end

  defp token, do: Application.get_env(:noa, :discord_bot_token) || System.get_env("DISCORD_BOT_TOKEN")

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp timestamp(nil), do: DateTime.utc_now()

  defp timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> at
      _ -> DateTime.utc_now()
    end
  end

  defp timestamp(_), do: DateTime.utc_now()
end
