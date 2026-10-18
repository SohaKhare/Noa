defmodule NoaWeb.JoinController do
  @moduledoc "Joining from a shared link (1.5): the public join page, and the org admins' approvals."
  use NoaWeb, :controller

  alias Noa.Orgs.Join

  def show(conn, %{"slug" => slug}) do
    with {:ok, info} <- Join.info(slug), do: json(conn, %{org: info})
  end

  def create(conn, %{"slug" => slug} = params) do
    with {:ok, :requested} <- Join.request(slug, params), do: conn |> put_status(202) |> json(%{ok: true})
  end

  def index(conn, %{"org_id" => org_id}) do
    with {:ok, requests} <- Join.pending(org_id, conn.assigns.current_user), do: json(conn, %{requests: requests})
  end

  def approve(conn, %{"org_id" => org_id, "id" => id} = params) do
    role =
      if params["role"] in ~w(org_admin pm member guest), do: String.to_existing_atom(params["role"]), else: :member

    with {:ok, url} <- Join.approve(org_id, id, role, conn.assigns.current_user), do: json(conn, %{url: url})
  end

  def reject(conn, %{"org_id" => org_id, "id" => id}) do
    with :ok <- Join.reject(org_id, id, conn.assigns.current_user), do: json(conn, %{ok: true})
  end
end
