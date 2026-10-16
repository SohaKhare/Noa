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
end
