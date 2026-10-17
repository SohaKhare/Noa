defmodule Noa.Mailer.Resend do
  @moduledoc """
  Swoosh adapter for Resend's email API.

  It uses the existing `Req` dependency and keeps the provider credential in
  runtime configuration. The three application senders remain provider-neutral.
  """

  use Swoosh.Adapter, required_config: [:api_key]

  @endpoint "https://api.resend.com/emails"

  @impl true
  def deliver(email, config) do
    api_key = Keyword.fetch!(config, :api_key)
    endpoint = Keyword.get(config, :endpoint, @endpoint)

    case Req.post(endpoint,
           headers: [{"authorization", "Bearer #{api_key}"}],
           json: build_payload(email)
         ) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:resend, status, body}}

      {:error, reason} ->
        {:error, {:resend, reason}}
    end
  end

  @doc false
  def build_payload(email) do
    %{
      from: address(email.from),
      to: Enum.map(email.to, &address/1),
      subject: email.subject,
      text: email.text_body,
      html: email.html_body
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
  end

  defp address({name, email}) when is_binary(name) and name != "", do: "#{name} <#{email}>"
  defp address({_, email}), do: to_string(email)
  defp address(email), do: to_string(email)
end
