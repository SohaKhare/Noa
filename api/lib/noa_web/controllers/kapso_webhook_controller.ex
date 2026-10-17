defmodule NoaWeb.KapsoWebhookController do
  @moduledoc """
  Kapso's WhatsApp webhook (1.15). Checks `X-Webhook-Signature` (HMAC-SHA256 hex of the
  raw body with `KAPSO_WEBHOOK_SECRET`), skips messages already handled, queues each
  inbound message for `Noa.WhatsApp.Inbound` and answers 200 at once (Kapso wants it
  within 10 seconds and retries otherwise).
  """
  use NoaWeb, :controller

  def receive(conn, params) do
    secret = Application.get_env(:noa, Noa.WhatsApp, [])[:webhook_secret]

    cond do
      is_nil(secret) ->
        send_resp(conn, 503, "WhatsApp is not configured")

      not valid?(conn, secret) ->
        send_resp(conn, 401, "bad signature")

      get_req_header(conn, "x-webhook-event") != ["whatsapp.message.received"] ->
        send_resp(conn, 200, "ignored")

      true ->
        items = if params["batch"] == true, do: params["data"] || [], else: [params]

        for item <- items,
            id = get_in(item, ["message", "id"]),
            not Noa.WhatsApp.seen?(id) do
          %{payload: Map.take(item, ["message", "conversation", "phone_number_id"])}
          |> Noa.WhatsApp.Inbound.new(unique: [period: 3600, keys: [:payload]])
          |> Oban.insert()
        end

        send_resp(conn, 200, "ok")
    end
  end

  defp valid?(conn, secret) do
    with [signature] <- get_req_header(conn, "x-webhook-signature"),
         raw when is_binary(raw) <- conn.assigns[:raw_body] do
      expected = :crypto.mac(:hmac, :sha256, secret, raw) |> Base.encode16(case: :lower)
      Plug.Crypto.secure_compare(expected, String.downcase(String.trim(signature)))
    else
      _ -> false
    end
  end
end
