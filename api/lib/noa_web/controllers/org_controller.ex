defmodule NoaWeb.OrgController do
  @moduledoc "People in a workspace and invites to it. Ash policies decide who may do what."
  use NoaWeb, :controller
  alias Noa.Orgs

  def members(conn, %{"org_id" => org_id}) do
    actor = conn.assigns.current_user

    with {:ok, org} <- Orgs.get_org(org_id, actor),
         {:ok, members} <- Orgs.members(org.id, actor) do
      json(conn, %{org: Payload.org(org), members: Enum.map(members, &Payload.member/1)})
    end
  end

  def update_member(conn, %{"org_id" => org_id, "id" => id} = params) do
    actor = conn.assigns.current_user
    attrs = params |> Map.take(["role", "title", "reports_to_id"]) |> atomize()

    with :ok <- in_org(Noa.Orgs.Membership, id, org_id, actor),
         {:ok, member} <- Orgs.update_member(id, attrs, actor),
         {:ok, member} <- Ash.load(member, [:user, reports_to: :user], actor: actor) do
      json(conn, %{member: Payload.member(member)})
    end
  end

  def remove_member(conn, %{"org_id" => org_id, "id" => id}) do
    actor = conn.assigns.current_user

    with :ok <- in_org(Noa.Orgs.Membership, id, org_id, actor),
         :ok <- Orgs.remove_member(id, actor) do
      json(conn, %{ok: true})
    end
  end

  def invites(conn, %{"org_id" => org_id}) do
    with {:ok, invites} <- Orgs.pending_invites(org_id, conn.assigns.current_user) do
      json(conn, %{invites: Enum.map(invites, &Payload.invite/1)})
    end
  end

  def create_invite(conn, %{"org_id" => org_id, "email" => email} = params) do
    actor = conn.assigns.current_user

    with {:ok, org} <- Orgs.get_org(org_id, actor),
         {:ok, role} <- role(params["role"] || "member"),
         {:ok, invite, url} <- Orgs.invite(org, email, role, actor, title: params["title"]) do
      conn |> put_status(201) |> json(%{invite: Payload.invite(invite), url: url})
    end
  end

  def revoke_invite(conn, %{"org_id" => org_id, "id" => id}) do
    actor = conn.assigns.current_user

    with :ok <- in_org(Noa.Orgs.Invite, id, org_id, actor),
         {:ok, _} <- Orgs.revoke_invite(id, actor) do
      json(conn, %{ok: true})
    end
  end

  defp role(value) do
    case Enum.find(Noa.Orgs.Membership.roles(), &(Atom.to_string(&1) == value)) do
      nil -> {:error, :not_found}
      role -> {:ok, role}
    end
  end

  defp atomize(params) do
    Map.new(params, fn
      {"role", v} -> {:role, v}
      {k, v} -> {String.to_existing_atom(k), v}
    end)
  end

  # Ids in the path must belong to the org in the path.
  defp in_org(resource, id, org_id, actor) do
    case Ash.get(resource, id, actor: actor) do
      {:ok, %{org_id: ^org_id}} -> :ok
      {:ok, _} -> {:error, :not_found}
      error -> error
    end
  end
end
