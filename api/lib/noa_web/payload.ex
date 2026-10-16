defmodule NoaWeb.Payload do
  @moduledoc "JSON shapes the web app reads. Keep in step with web/src/lib/api.ts."

  def user(user) do
    memberships = Noa.Orgs.memberships_for(user)

    %{
      id: user.id,
      email: to_string(user.email),
      name: user.name,
      is_superadmin: user.is_superadmin,
      # Where to land after sign-in: superadmins with no org go to the platform console.
      home: if(user.is_superadmin and memberships == [], do: "/admin", else: "/"),
      memberships: Enum.map(memberships, &membership_with_org/1)
    }
  end

  def org(org), do: %{id: org.id, name: org.name, slug: org.slug, allowed_domains: org.allowed_domains}

  def member(m) do
    %{
      id: m.id,
      role: m.role,
      title: m.title,
      reports_to_id: m.reports_to_id,
      reports_to_name:
        m.reports_to && m.reports_to.user && (m.reports_to.user.name || to_string(m.reports_to.user.email)),
      user: %{id: m.user.id, email: to_string(m.user.email), name: m.user.name}
    }
  end

  def invite(i) do
    %{id: i.id, email: to_string(i.email), role: i.role, title: i.title, status: i.status, expires_at: i.expires_at}
  end

  defp membership_with_org(m), do: %{id: m.id, role: m.role, title: m.title, org: org(m.org)}

  ## Work (1.24)

  def person(p) do
    %{
      id: p.id,
      key: p.key,
      name: p.name,
      title: p.title,
      handles: p.handles,
      joined: not is_nil(p.membership_id),
      role: loaded(p.membership) && p.membership.role,
      allocations: Enum.map(loaded(p.allocations) || [], &allocation/1)
    }
  end

  def project(p) do
    %{
      id: p.id,
      key: p.key,
      name: p.name,
      about: p.about,
      repo: p.repo,
      status: p.status,
      lead_id: p.lead_id,
      aliases: Enum.map(loaded(p.aliases) || [], &to_string(&1.alias)),
      allocations: Enum.map(loaded(p.allocations) || [], &allocation/1)
    }
  end

  def channel(c) do
    %{id: c.id, platform: c.platform, name: c.name, project_id: c.project_id, split: c.split, read: c.read}
  end

  def task(t) do
    %{
      id: t.id,
      title: t.title,
      detail: t.detail,
      status: t.status,
      due_on: t.due_on,
      blocked_reason: t.blocked_reason,
      project_id: t.project_id,
      owner_id: t.owner_id,
      source: t.source,
      done_at: t.done_at,
      inserted_at: t.inserted_at
    }
  end

  def proposal(p) do
    %{
      id: p.id,
      kind: p.kind,
      summary: p.summary,
      data: p.data,
      confidence: p.confidence,
      source: p.source,
      status: p.status,
      project_id: p.project_id,
      owner_id: p.owner_id,
      task_id: p.task_id,
      inserted_at: p.inserted_at
    }
  end

  defp allocation(a) do
    %{person_id: a.person_id, project_id: a.project_id, percent: a.percent, role: a.role, starts_on: a.starts_on}
  end

  defp loaded(%Ash.NotLoaded{}), do: nil
  defp loaded(value), do: value
end
