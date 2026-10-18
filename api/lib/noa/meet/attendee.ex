defmodule Noa.Meet.Attendee do
  @moduledoc """
  Hosted Attendee transport for the meeting-provider spike (0.7).

  This module does not start meetings on its own, store transcripts, or write to the
  graph. The later Noa meeting session layer will own consent, auth, idempotency,
  event-log storage and project approval. API credentials are server-side only.
  """
  @behaviour Noa.Meet.Provider

  @base_url "https://app.attendee.dev"
  @bot_name "Noa Notetaker"

  @impl true
  def join(meeting_url, opts \\ []) do
    payload = %{meeting_url: meeting_url, bot_name: @bot_name}

    payload =
      if opts[:deduplication_key], do: Map.put(payload, :deduplication_key, opts[:deduplication_key]), else: payload

    with :ok <- valid_meet_url(meeting_url),
         {:ok, body} <- request(:post, "/api/v1/bots", payload, opts),
         %{"id" => id} when is_binary(id) <- body do
      {:ok, id}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_response}
    end
  end

  @impl true
  def leave(bot_id, opts \\ []) do
    with :ok <- valid_bot_id(bot_id),
         {:ok, _} <- request(:post, "/api/v1/bots/#{bot_id}/leave", %{}, opts) do
      :ok
    end
  end

  @doc "Attendee's current lifecycle state; only a completed transcript may be imported."
  @impl true
  def status(bot_id, opts \\ []) do
    with :ok <- valid_bot_id(bot_id),
         {:ok, %{"state" => state, "transcription_state" => transcription}} <-
           request(:get, "/api/v1/bots/#{bot_id}", nil, opts) do
      {:ok, %{state: state, transcription: transcription}}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_response}
    end
  end

  @impl true
  def transcript(bot_id, opts \\ []) do
    with :ok <- valid_bot_id(bot_id),
         {:ok, lines} when is_list(lines) <- request(:get, "/api/v1/bots/#{bot_id}/transcript", nil, opts),
         {:ok, normalized} <- normalize(lines) do
      {:ok, normalized}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_response}
    end
  end

  # Preserve the provider's utterance ID (when present), speaker and time range.
  # Reject malformed lines rather than creating a source citation with made-up timing.
  defp normalize(lines) do
    Enum.reduce_while(lines, {:ok, []}, fn line, {:ok, acc} ->
      # Attendee nests the text as %{"transcript" => text}; older payloads send a string.
      text =
        case line do
          %{"transcription" => %{"transcript" => text}} -> text
          %{"transcription" => text} -> text
          _ -> nil
        end

      case line do
        %{"timestamp_ms" => at, "duration_ms" => duration}
        when is_integer(at) and at >= 0 and is_integer(duration) and duration >= 0 and is_binary(text) ->
          normalized = %{
            provider_utterance_id: line["id"],
            speaker: line["speaker_name"],
            speaker_id: line["speaker_uuid"],
            start_ms: at,
            end_ms: at + duration,
            text: text
          }

          {:cont, {:ok, [normalized | acc]}}

        _ ->
          {:halt, {:error, :invalid_transcript}}
      end
    end)
    |> case do
      {:ok, lines} -> {:ok, Enum.reverse(lines)}
      error -> error
    end
  end

  @doc "Reject arbitrary URLs before storing a session or sending the provider key."
  def valid_meet_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: "meet.google.com", path: path, userinfo: nil, port: 443, fragment: nil}
      when is_binary(path) ->
        if Regex.match?(~r|^/[a-z]{3}-[a-z]{4}-[a-z]{3}$|, path), do: :ok, else: {:error, :invalid_meet_url}

      _ ->
        {:error, :invalid_meet_url}
    end
  end

  def valid_meet_url(_), do: {:error, :invalid_meet_url}

  defp valid_bot_id("bot_" <> suffix) when byte_size(suffix) > 0 do
    if Regex.match?(~r/^[A-Za-z0-9_-]+$/, suffix), do: :ok, else: {:error, :invalid_bot_id}
  end

  defp valid_bot_id(_), do: {:error, :invalid_bot_id}

  defp request(method, path, payload, opts) do
    config = Application.get_env(:noa, __MODULE__, [])
    key = Keyword.get(opts, :api_key, config[:api_key])

    if not (is_binary(key) and key != "") do
      {:error, :not_configured}
    else
      req_opts =
        [
          url: Keyword.get(opts, :base_url, @base_url) <> path,
          headers: [{"authorization", "Token " <> key}],
          receive_timeout: 15_000
        ] ++ Keyword.get(opts, :req_options, [])

      req_opts = if payload, do: Keyword.put(req_opts, :json, payload), else: req_opts

      case Req.request([method: method] ++ req_opts) do
        {:ok, %{status: status, body: body}} when status in 200..299 -> {:ok, body}
        {:ok, %{status: status}} -> {:error, {:provider_http, status}}
        {:error, _} -> {:error, :provider_unavailable}
      end
    end
  end
end
