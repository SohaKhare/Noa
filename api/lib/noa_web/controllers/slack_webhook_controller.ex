defmodule NoaWeb.SlackWebhookController do
  @moduledoc "Verifies and acknowledges Slack Events API requests, then processes them in Oban."
  use NoaWeb, :controller

  alias Noa.Ingest.Slack.Event

  @five_minutes 300

  def receive(conn, params) do
    secret = Noa.Ingest.Slack.Client.signing_secret()

    cond do
      not present?(secret) ->
        send_resp(conn, 503, "Slack is not configured")

      not valid_signature?(conn, secret) ->
        send_resp(conn, 401, "bad signature")

      params["type"] == "url_verification" and is_binary(params["challenge"]) ->
        json(conn, %{challenge: params["challenge"]})

      Event.supported?(params) ->
        enqueue(conn, params)

      true ->
        json(conn, %{ignored: "unsupported"})
    end
  end

  def valid_signature?(conn, secret, now \\ System.system_time(:second)) do
    with [timestamp] <- get_req_header(conn, "x-slack-request-timestamp"),
         {sent_at, ""} <- Integer.parse(timestamp),
         true <- abs(now - sent_at) <= @five_minutes,
         [signature] <- get_req_header(conn, "x-slack-signature"),
         raw when is_binary(raw) <- conn.assigns[:raw_body] do
      expected = "v0=" <> (:crypto.mac(:hmac, :sha256, secret, "v0:#{timestamp}:#{raw}") |> Base.encode16(case: :lower))
      byte_size(expected) == byte_size(signature) and Plug.Crypto.secure_compare(expected, String.downcase(signature))
    else
      _ -> false
    end
  end

  defp enqueue(conn, %{"event_id" => event_id} = payload) when is_binary(event_id) do
    case %{"event_id" => event_id, "payload" => payload} |> Event.new() |> Oban.insert() do
      {:ok, _job} -> json(conn, %{ok: true})
      {:error, _reason} -> send_resp(conn, 503, "queue unavailable")
    end
  end

  defp enqueue(conn, _payload), do: json(conn, %{ignored: "missing_event_id"})
  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
