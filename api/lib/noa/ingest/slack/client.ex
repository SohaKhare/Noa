defmodule Noa.Ingest.Slack.Client do
  @moduledoc """
  Small, testable boundary around Slack OAuth and Web API calls.

  Slack returns application errors as HTTP 200 responses with `ok: false`; callers
  therefore receive only `{:ok, body}` or a typed `{:error, reason}`. Rate limits are
  returned with their `Retry-After` delay so Oban workers can snooze without sleeping.
  """

  @default_base_url "https://slack.com/api"

  def configured? do
    present?(config(:client_id)) and present?(config(:client_secret)) and present?(config(:signing_secret))
  end

  def oauth_configured?, do: present?(config(:client_id)) and present?(config(:client_secret))
  def signing_secret, do: config(:signing_secret)

  def oauth_exchange(code) do
    request(:post, "/oauth.v2.access",
      form: [
        client_id: config(:client_id),
        client_secret: config(:client_secret),
        code: code,
        redirect_uri: redirect_uri()
      ]
    )
  end

  def revoke(token), do: request(:post, "/auth.revoke", token: token)

  def channels(token, opts \\ []) do
    paginate(token, "/conversations.list", "channels",
      params: [types: "public_channel,private_channel", exclude_archived: true, limit: 200],
      req_options: opts[:req_options]
    )
  end

  def users(token, opts \\ []) do
    paginate(token, "/users.list", "members", params: [limit: 200], req_options: opts[:req_options])
  end

  def user(token, user_id, opts \\ []) do
    request(:get, "/users.info", token: token, params: [user: user_id], req_options: opts[:req_options])
  end

  def history(token, channel_id, limit, opts \\ []) do
    request(:get, "/conversations.history",
      token: token,
      params: [channel: channel_id, limit: limit, inclusive: true],
      req_options: opts[:req_options]
    )
  end

  def open_dm(token, user_id, opts \\ []) do
    request(:post, "/conversations.open", token: token, json: %{users: user_id}, req_options: opts[:req_options])
  end

  def post_message(token, channel_id, text, opts \\ []) do
    request(:post, "/chat.postMessage",
      token: token,
      json: %{channel: channel_id, text: String.slice(text, 0, 40_000)},
      req_options: opts[:req_options]
    )
  end

  defp paginate(token, path, key, opts, cursor \\ nil, acc \\ []) do
    params = if present?(cursor), do: Keyword.put(opts[:params] || [], :cursor, cursor), else: opts[:params] || []

    case request(:get, path, token: token, params: params, req_options: opts[:req_options]) do
      {:ok, body} ->
        items = body[key] || []
        next = get_in(body, ["response_metadata", "next_cursor"])

        if present?(next),
          do: paginate(token, path, key, opts, next, acc ++ items),
          else: {:ok, acc ++ items}

      error ->
        error
    end
  end

  defp request(method, path, opts) do
    token = opts[:token]

    headers =
      [{"accept", "application/json"}]
      |> maybe_authorization(token)

    request =
      [method: method, url: base_url() <> path, headers: headers, retry: false]
      |> maybe_put(:params, opts[:params])
      |> maybe_put(:form, opts[:form])
      |> maybe_put(:json, opts[:json])
      |> Keyword.merge(config(:req_options) || [])
      |> Keyword.merge(opts[:req_options] || [])

    case Req.request(request) do
      {:ok, %{status: 429} = response} ->
        {:error, {:rate_limited, retry_after(response)}}

      {:ok, %{status: status, body: %{"ok" => true} = body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: %{"ok" => false} = body}} when status in 200..299 ->
        {:error, {:slack_api, body["error"] || "unknown_error", body}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:slack_http, status, body}}

      {:error, reason} ->
        {:error, {:slack_http, reason}}
    end
  end

  defp maybe_authorization(headers, token) when is_binary(token) and token != "",
    do: [{"authorization", "Bearer " <> token} | headers]

  defp maybe_authorization(headers, _token), do: headers

  defp maybe_put(keyword, _key, nil), do: keyword
  defp maybe_put(keyword, key, value), do: Keyword.put(keyword, key, value)

  defp retry_after(response) do
    response.headers
    |> Map.get("retry-after", ["60"])
    |> List.first()
    |> to_string()
    |> Integer.parse()
    |> case do
      {seconds, _} -> max(seconds, 1)
      :error -> 60
    end
  end

  defp redirect_uri, do: Application.fetch_env!(:noa, :api_base_url) <> "/slack/oauth/callback"
  defp base_url, do: String.trim_trailing(config(:base_url) || @default_base_url, "/")
  defp config(key), do: Application.get_env(:noa, __MODULE__, [])[key]
  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
