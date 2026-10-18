defmodule Noa.GitHub.App do
  @moduledoc """
  Noa's GitHub App (3.7). The Noa admin registers it once (`GITHUB_APP_ID`,
  `GITHUB_APP_SLUG`, `GITHUB_APP_PRIVATE_KEY`, `GITHUB_APP_WEBHOOK_SECRET`); each
  company's org admin installs it on their GitHub organization from Settings →
  Connectors and picks the repos. GitHub then sends that installation's pushes, pull
  requests and CI runs to `/webhooks/github`, and Noa reads history with short-lived
  installation tokens instead of anyone's personal token.
  """

  @api "https://api.github.com"

  def configured?, do: present?(config(:app_id)) and present?(config(:private_key)) and present?(config(:slug))
  def webhook_secret, do: config(:app_webhook_secret)

  @doc "Where an org admin installs the app; `state` brings them back to the right workspace."
  def install_url(state),
    do: "https://github.com/apps/#{config(:slug)}/installations/new?state=#{URI.encode_www_form(state)}"

  @doc "A JWT that authenticates as the app itself (RS256, valid 9 minutes)."
  def jwt(now \\ System.system_time(:second)) do
    jwk = JOSE.JWK.from_pem(pem())
    claims = %{"iat" => now - 60, "exp" => now + 540, "iss" => to_string(config(:app_id))}
    {_, token} = jwk |> JOSE.JWT.sign(%{"alg" => "RS256"}, claims) |> JOSE.JWS.compact()
    token
  end

  @doc "An installation access token, cached until five minutes before GitHub's expiry."
  def installation_token(installation_id) do
    key = {__MODULE__, :token, installation_id}
    now = DateTime.utc_now()

    case :persistent_term.get(key, nil) do
      {token, expires} when is_binary(token) ->
        if DateTime.compare(DateTime.add(now, 300, :second), expires) == :lt,
          do: {:ok, token},
          else: fetch_token(installation_id, key)

      _ ->
        fetch_token(installation_id, key)
    end
  end

  defp fetch_token(installation_id, key) do
    case Req.post(
           "#{base()}/app/installations/#{installation_id}/access_tokens",
           [headers: headers(jwt()), retry: false] ++ req()
         ) do
      {:ok, %{status: 201, body: %{"token" => token, "expires_at" => expires}}} ->
        {:ok, expires, _} = DateTime.from_iso8601(expires)
        :persistent_term.put(key, {token, expires})
        {:ok, token}

      {:ok, %{status: status, body: body}} ->
        {:error, {:github, status, body["message"]}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "The repositories the installation can see: `[\"Owner/name\"]`."
  def repositories(installation_id) do
    with {:ok, token} <- installation_token(installation_id),
         {:ok, %{status: 200, body: %{"repositories" => repos}}} <-
           Req.get(
             "#{base()}/installation/repositories",
             [headers: headers(token), params: [per_page: 100], retry: false] ++ req()
           ) do
      {:ok, Enum.map(repos, & &1["full_name"])}
    else
      {:ok, %{status: status, body: body}} -> {:error, {:github, status, body["message"]}}
      error -> error
    end
  end

  defp headers(token), do: [{"authorization", "Bearer #{token}"}, {"accept", "application/vnd.github+json"}]

  # The key may be pasted with literal "\n" (Fly secrets are one line).
  defp pem, do: config(:private_key) |> to_string() |> String.replace("\\n", "\n")

  defp base, do: config(:api_url) || @api
  defp req, do: config(:req_options) || []
  defp config(key), do: Application.get_env(:noa, Noa.GitHub, [])[key]
  defp present?(v), do: is_binary(v) and v != ""
end
