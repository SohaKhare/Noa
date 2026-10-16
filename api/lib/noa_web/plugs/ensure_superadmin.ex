defmodule NoaWeb.Plugs.EnsureSuperadmin do
  @moduledoc "Gate for /api/platform. Ash policies check again; this keeps the routes themselves private."
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if match?(%{is_superadmin: true}, conn.assigns[:current_user]),
      do: conn,
      else: conn |> put_resp_content_type("application/json") |> send_resp(403, ~s({"error":"forbidden"})) |> halt()
  end
end
