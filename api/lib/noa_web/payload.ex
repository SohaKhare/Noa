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
      user_id: loaded(p.membership) && p.membership.user_id,
      allocations: Enum.map(loaded(p.allocations) || [], &allocation/1)
    }
  end

  def notifications(p) do
    Map.take(p, [:notify_via, :phone, :digest_at, :quiet_from, :quiet_to, :utc_offset])
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

  def change(c) do
    %{
      id: c.id,
      kind: c.kind,
      old_value: c.old_value,
      new_value: c.new_value,
      reason: c.reason,
      status: c.status,
      source: c.source,
      task_id: c.task_id,
      project_id: c.project_id,
      requested_by_id: c.requested_by_id,
      decided_by_id: c.decided_by_id,
      decided_at: c.decided_at,
      inserted_at: c.inserted_at
    }
  end

  def shift(s) do
    %{
      id: s.id,
      person_id: s.person_id,
      from_project_id: s.from_project_id,
      to_project_id: s.to_project_id,
      percent: s.percent,
      starts_on: s.starts_on,
      routes_until: s.routes_until,
      handover: s.handover,
      note: s.note,
      inserted_at: s.inserted_at
    }
  end

  def decision(d) do
    %{
      id: d.id,
      statement: d.statement,
      kind: d.kind,
      status: d.status,
      affects: d.affects,
      source: d.source,
      project_id: d.project_id,
      made_by_id: d.made_by_id,
      superseded_by_id: d.superseded_by_id,
      inserted_at: d.inserted_at
    }
  end

  defp allocation(a) do
    %{person_id: a.person_id, project_id: a.project_id, percent: a.percent, role: a.role, starts_on: a.starts_on}
  end

  defp loaded(%Ash.NotLoaded{}), do: nil
  defp loaded(value), do: value
end
