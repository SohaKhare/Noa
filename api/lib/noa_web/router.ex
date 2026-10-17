defmodule NoaWeb.Router do
  use NoaWeb, :router

  import NoaWeb.AuthPlug

  pipeline :api do
    plug(:accepts, ["json"])
    plug(:fetch_session)
    plug(:put_secure_browser_headers)
    plug(NoaWeb.Plugs.RequireJson)
    plug(:load_from_session)
    plug(:load_from_bearer)
  end

  pipeline :signed_in do
    plug(NoaWeb.Plugs.EnsureSignedIn)
  end

  pipeline :in_org do
    plug(NoaWeb.Plugs.EnsureInOrg)
  end

  # Sign-in, magic links, password resets and invite links: by address (4.3).
  pipeline :auth_limit do
    plug(NoaWeb.Plugs.RateLimit, name: :auth, limit: 10, per: 60, by: :ip)
  end

  # @noa calls a model: by person.
  pipeline :ask_limit do
    plug(NoaWeb.Plugs.RateLimit, name: :ask, limit: 20, per: 60, by: :user)
  end

  pipeline :superadmin do
    plug(NoaWeb.Plugs.EnsureSuperadmin)
  end

  scope "/", NoaWeb do
    get("/healthz", HealthController, :show)
  end

  # Invite pages work before sign-in: the emailed token is the permission.
  scope "/api", NoaWeb do
    pipe_through([:api, :auth_limit])

    get("/invites/:token", InviteController, :show)
    post("/invites/:token/accept", InviteController, :accept)
  end

  scope "/api", NoaWeb do
    pipe_through([:api, :signed_in])

    get("/me", MeController, :show)
    patch("/me", MeController, :update)
    delete("/session", MeController, :sign_out)
  end

  scope "/api", NoaWeb do
    pipe_through([:api, :signed_in, :in_org, :ask_limit])
    post("/orgs/:org_id/ask", WorkController, :ask)
  end

  # Everything inside one workspace: 404 for anyone not in it (2.16).
  scope "/api", NoaWeb do
    pipe_through([:api, :signed_in, :in_org])

    # Org admins (and superadmins) manage their org; members can list it.
    get("/orgs/:org_id/members", OrgController, :members)
    patch("/orgs/:org_id/members/:id", OrgController, :update_member)
    delete("/orgs/:org_id/members/:id", OrgController, :remove_member)
    get("/orgs/:org_id/invites", OrgController, :invites)
    post("/orgs/:org_id/invites", OrgController, :create_invite)
    delete("/orgs/:org_id/invites/:id", OrgController, :revoke_invite)

    # Work (1.24): everyone in the org reads; policies decide writes.
    get("/orgs/:org_id/directory", WorkController, :directory)
    get("/orgs/:org_id/tasks", WorkController, :tasks)
    post("/orgs/:org_id/tasks", WorkController, :create_task)
    patch("/orgs/:org_id/tasks/:id", WorkController, :update_task)
    patch("/orgs/:org_id/channels/:id", WorkController, :update_channel)
    get("/orgs/:org_id/decisions", WorkController, :decisions)
    get("/orgs/:org_id/changes", WorkController, :changes)
    get("/orgs/:org_id/shifts", WorkController, :shifts)
    get("/orgs/:org_id/projects/:project_id/brief", WorkController, :brief)
    get("/orgs/:org_id/experts", WorkController, :experts)
    get("/orgs/:org_id/shifts/plan", WorkController, :plan_shift)
    post("/orgs/:org_id/shifts", WorkController, :create_shift)
    post("/orgs/:org_id/changes/:id/approve", WorkController, :approve_change)
    post("/orgs/:org_id/changes/:id/reject", WorkController, :reject_change)
    post("/orgs/:org_id/changes/:id/revert", WorkController, :revert_change)
    get("/orgs/:org_id/proposals", WorkController, :proposals)
    post("/orgs/:org_id/proposals/:id/approve", WorkController, :approve)
    post("/orgs/:org_id/proposals/:id/reject", WorkController, :reject)
    post("/orgs/:org_id/proposals/:id/undo", WorkController, :undo)
  end

  scope "/api/platform", NoaWeb do
    pipe_through([:api, :signed_in, :superadmin])

    get("/orgs", PlatformController, :index)
    post("/orgs", PlatformController, :create)
  end

  # AshAuthentication: password sign-in and reset, magic-link request and sign-in.
  scope "/auth" do
    pipe_through([:accepts_json_or_html, :fetch_session, :auth_limit, :auth_json])
    forward("/", NoaWeb.AuthPlug)
  end

  if Application.compile_env(:noa, :dev_routes) do
    scope "/dev" do
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end

  defp accepts_json_or_html(conn, _opts), do: accepts(conn, ["json", "html"])

  # Sign-in and reset posts must be JSON too, so another site can't post a login form (4.3).
  defp auth_json(conn, _opts), do: NoaWeb.Plugs.RequireJson.call(conn, [])
end
