defmodule Noa.WhatsApp.Kapso do
  @moduledoc """
  Kapso's WhatsApp API (Meta Cloud API format): `POST {base}/{phone_number_id}/messages`
  with `X-API-Key`. Text or interactive reply buttons; outside the 24-hour window, the
  approved template for that button set, with the text as its one body parameter and the
  button ids as quick-reply payloads.
  """
  @base "https://api.kapso.ai/meta/whatsapp/v24.0"
  # Meta: "Re-engagement message" — more than 24 hours since the person last wrote.
  @outside_window [131_047, 470]

  def send(phone, text, buttons) do
    case post(message(phone, text, buttons)) do
      {:error, {:meta, code, _}} = error when code in @outside_window ->
        case template(buttons) do
          nil -> error
          name -> post(template_message(name, phone, text, buttons))
        end

      other ->
        other
    end
  end

  defp message(phone, text, []), do: %{messaging_product: "whatsapp", to: phone, type: "text", text: %{body: text}}

  defp message(phone, text, buttons) do
    %{
      messaging_product: "whatsapp",
      to: phone,
      type: "interactive",
      interactive: %{
        type: "button",
        body: %{text: String.slice(text, 0, 1024)},
        action: %{
          buttons:
            Enum.map(buttons, fn {id, title} ->
              %{type: "reply", reply: %{id: id, title: String.slice(title, 0, 20)}}
            end)
        }
      }
    }
  end

  defp template_message(name, phone, text, buttons) do
    lang = (Application.get_env(:noa, Noa.WhatsApp, [])[:templates] || %{})[:language] || "en_US"

    %{
      messaging_product: "whatsapp",
      to: phone,
      type: "template",
      template: %{
        name: name,
        language: %{code: lang},
        components:
          [%{type: "body", parameters: [%{type: "text", text: String.slice(text, 0, 1000)}]}] ++
            (buttons
             |> Enum.with_index()
             |> Enum.map(fn {{id, _title}, i} ->
               %{
                 type: "button",
                 sub_type: "quick_reply",
                 index: Integer.to_string(i),
                 parameters: [%{type: "payload", payload: id}]
               }
             end))
      }
    }
  end

  defp post(body) do
    config = Application.get_env(:noa, Noa.WhatsApp, [])
    url = "#{config[:base_url] || @base}/#{config[:phone_number_id]}/messages"

    opts = [json: body, headers: [{"x-api-key", config[:api_key]}], receive_timeout: 15_000, retry: false]

    case Req.post(url, opts ++ (config[:req_options] || [])) do
      {:ok, %{status: status, body: %{"messages" => [%{"id" => id} | _]}}} when status in 200..299 ->
        {:ok, id}

      {:ok, %{body: %{"error" => %{"code" => code, "message" => msg}}}} ->
        {:error, {:meta, code, msg}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Templates have fixed buttons, so each button set has its own (docs/whatsapp.md):
  # update (none), task (Start now / Done / Need help), approval (Approve / Reject).
  defp template(buttons) do
    templates = Application.get_env(:noa, Noa.WhatsApp, [])[:templates] || %{}

    case buttons do
      [] -> templates[:update]
      [{"approve_change:" <> _, _} | _] -> templates[:approval]
      _ -> templates[:task]
    end
  end
end
