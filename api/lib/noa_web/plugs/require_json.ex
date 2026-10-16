defmodule NoaWeb.Plugs.RequireJson do
  @moduledoc """
  Writes must be `application/json`. A cross-site page cannot send that without a CORS
  preflight, and CORS only allows the web app's origin, so cookie-authenticated writes
  cannot be forged from another site.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(%{method: method} = conn, _opts) when method in ~w(POST PUT PATCH DELETE) do
    case get_req_header(conn, "content-type") do
      ["application/json" <> _ | _] -> conn
      _ -> conn |> put_resp_content_type("application/json") |> send_resp(415, ~s({"error":"json_required"})) |> halt()
    end
  end

  def call(conn, _opts), do: conn
end
