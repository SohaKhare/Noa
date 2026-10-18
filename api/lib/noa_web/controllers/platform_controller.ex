defmodule NoaWeb.PlatformController do
  @moduledoc "Superadmin console: workspaces (create one and invite its first admin in one step) and system status."
  use NoaWeb, :controller
  alias Noa.Orgs

  @doc "Services, background jobs and event-log readers (3.14)."
  def status(conn, _params), do: json(conn, Noa.Ops.status())

  def index(conn, _params) do
    actor = conn.assigns.current_user

    with {:ok, orgs} <- Orgs.list_orgs(actor) do
      orgs = Ash.load!(orgs, [memberships: :user, invites: []], actor: actor)
      usage = Noa.LLM.usage()

      json(conn, %{
        orgs:
          Enum.map(orgs, fn org ->
            Payload.org(org)
            |> Map.merge(%{
              admins: for(m <- org.memberships, m.role == :org_admin, do: m.user.name || to_string(m.user.email)),
              member_count: length(org.memberships),
              pending_invites: Enum.count(org.invites, &(&1.status == :pending)),
              llm_24h: usage[org.id] || %{calls: 0, errors: 0, avg_ms: nil, approx_tokens: 0}
            })
          end)
      })
    end
  end

  def create(conn, %{"name" => name, "domains" => domains, "admin_email" => admin_email} = params) do
    actor = conn.assigns.current_user
    domains = if is_binary(domains), do: String.split(domains, ~r/[,\s]+/, trim: true), else: domains

    normalized = Enum.map(domains, &(&1 |> String.trim() |> String.trim_leading("@") |> String.downcase()))

    # Check the admin's email before creating anything, so a typo never leaves a workspace with no admin.
    with true <- Noa.Orgs.WorkEmail.allowed?(%{allowed_domains: normalized}, admin_email) || {:error, :not_work_email},
         {:ok, org} <- Orgs.create_org(%{name: name, allowed_domains: domains}, actor),
         {:ok, invite, url} <- Orgs.invite(org, admin_email, :org_admin, actor, title: params["admin_title"]) do
      conn |> put_status(201) |> json(%{org: Payload.org(org), invite: Payload.invite(invite), url: url})
    end
  end
end
