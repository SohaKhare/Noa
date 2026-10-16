defmodule NoaWeb.Router do
  use NoaWeb, :router

  import NoaWeb.AuthPlug

  pipeline :api do
    plug(:accepts, ["json"])
    plug(:fetch_session)
    plug(NoaWeb.Plugs.RequireJson)
    plug(:load_from_session)
    plug(:load_from_bearer)
  end

  pipeline :signed_in do
    plug(NoaWeb.Plugs.EnsureSignedIn)
  end

  pipeline :superadmin do
    plug(NoaWeb.Plugs.EnsureSuperadmin)
  end

  scope "/", NoaWeb do
    get("/healthz", HealthController, :show)
  end

  # Invite pages work before sign-in: the emailed token is the permission.
  scope "/api", NoaWeb do
    pipe_through(:api)

    get("/invites/:token", InviteController, :show)
    post("/invites/:token/accept", InviteController, :accept)
  end

  scope "/api", NoaWeb do
    pipe_through([:api, :signed_in])

    get("/me", MeController, :show)
    patch("/me", MeController, :update)
    delete("/session", MeController, :sign_out)

    # Org admins (and superadmins) manage their org; members can list it.
    get("/orgs/:org_id/members", OrgController, :members)
    patch("/orgs/:org_id/members/:id", OrgController, :update_member)
    delete("/orgs/:org_id/members/:id", OrgController, :remove_member)
    get("/orgs/:org_id/invites", OrgController, :invites)
    post("/orgs/:org_id/invites", OrgController, :create_invite)
    delete("/orgs/:org_id/invites/:id", OrgController, :revoke_invite)
  end

  scope "/api/platform", NoaWeb do
    pipe_through([:api, :signed_in, :superadmin])

    get("/orgs", PlatformController, :index)
    post("/orgs", PlatformController, :create)
  end

  # AshAuthentication: password sign-in and reset, magic-link request and sign-in.
  scope "/auth" do
    pipe_through([:accepts_json_or_html, :fetch_session])
    forward("/", NoaWeb.AuthPlug)
  end

  if Application.compile_env(:noa, :dev_routes) do
    scope "/dev" do
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end

  defp accepts_json_or_html(conn, _opts), do: accepts(conn, ["json", "html"])
end
