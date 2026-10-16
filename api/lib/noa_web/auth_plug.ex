defmodule NoaWeb.AuthPlug do
  @moduledoc """
  AshAuthentication routes under /auth. JSON callers (the web app's sign-in form) get
  the signed-in user back; a browser following an emailed magic link is redirected
  into the web app. Either way the session cookie is set.
  """
  use AshAuthentication.Plug, otp_app: :noa

  import Plug.Conn
  alias AshAuthentication.Plug.Helpers

  # Magic-link and reset requests: never reveal whether the email has an account.
  @impl true
  def handle_success(conn, _activity, nil, _token) do
    if json?(conn), do: json(conn, 200, %{ok: true}), else: redirect_to(conn, "/login?sent=1")
  end

  def handle_success(conn, _activity, user, _token) do
    conn = conn |> Helpers.store_in_session(user) |> configure_session(renew: true)
    if json?(conn), do: json(conn, 200, %{user: NoaWeb.Payload.user(user)}), else: redirect_to(conn, "/")
  end

  @impl true
  def handle_failure(conn, _activity, _reason) do
    if json?(conn),
      do: json(conn, 401, %{error: "invalid_credentials", message: "That email and password don't match."}),
      else: redirect_to(conn, "/login?error=link_expired")
  end

  defp json?(conn), do: conn |> get_req_header("accept") |> List.first("") |> String.contains?("application/json")

  defp json(conn, status, body) do
    conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(body)) |> halt()
  end

  defp redirect_to(conn, path) do
    conn |> Phoenix.Controller.redirect(external: Noa.Mailer.web_url(path)) |> halt()
  end
end
