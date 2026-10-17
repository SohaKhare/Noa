defmodule NoaWeb.Plugs.EnsureInOrg do
  @moduledoc """
  Every `/api/orgs/:org_id` route: answers 404 unless the signed-in person belongs to
  that workspace (or is a superadmin), so an outsider can't even tell it exists (2.16).
  Policies still decide everything inside.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(%{path_params: %{"org_id" => org_id}} = conn, _opts) do
    user = conn.assigns.current_user

    allowed =
      match?({:ok, _}, Ecto.UUID.cast(org_id)) and (user.is_superadmin or Noa.Orgs.role(user.id, org_id) != nil)

    if allowed,
      do: conn,
      else:
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, ~s({"error":"not_found","message":"Not found."}))
        |> halt()
  end

  def call(conn, _opts), do: conn
end
