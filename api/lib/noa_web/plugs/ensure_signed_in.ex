defmodule NoaWeb.Plugs.EnsureSignedIn do
  @moduledoc false
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.assigns[:current_user],
      do: conn,
      else: conn |> put_resp_content_type("application/json") |> send_resp(401, ~s({"error":"signed_out"})) |> halt()
  end
end
