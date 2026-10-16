defmodule NoaWeb.OnboardingFlowTest do
  @moduledoc """
  The invite-only flow end to end: superadmin creates NotYourIdea and invites the lead;
  the lead accepts and invites a member; the member accepts with a work email.
  """
  use NoaWeb.ConnCase, async: true
  import Swoosh.TestAssertions

  setup do
    root = superadmin!()

    body =
      signed_in(root)
      |> post("/api/platform/orgs", %{
        name: "NotYourIdea",
        domains: "notyouridea.com",
        admin_email: "vedant@notyouridea.com",
        admin_title: "PM / Lead"
      })
      |> json_response(201)

    %{root: root, org_id: body["org"]["id"], lead_url: body["url"]}
  end

  test "superadmin creates the workspace and the lead's invite is emailed", %{org_id: org_id, lead_url: url} do
    assert url =~ "http://localhost:3000/invite/"
    assert_email_sent(to: "vedant@notyouridea.com", subject: "Saish invited you to NotYourIdea on Noa")
    assert {:ok, org} = Ash.get(Noa.Orgs.Org, org_id, authorize?: false)
    assert org.allowed_domains == ["notyouridea.com"]
    assert org.slug == "notyouridea"
  end

  test "the lead accepts, lands signed in as org admin, and invites a member", %{org_id: org_id, lead_url: url} do
    token = url |> String.split("/invite/") |> List.last()

    shown = json_conn() |> get("/api/invites/#{token}") |> json_response(200)
    assert shown["invite"]["email"] == "vedant@notyouridea.com"
    assert shown["invite"]["org"]["name"] == "NotYourIdea"
    assert shown["invite"]["role"] == "org_admin"

    conn =
      json_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> post("/api/invites/#{token}/accept", %{name: "Vedant", password: "a-long-password"})

    assert %{"user" => %{"name" => "Vedant", "memberships" => [m]}} = json_response(conn, 200)
    assert m["role"] == "org_admin" and m["title"] == "PM / Lead"

    # The session cookie from accepting keeps them signed in.
    me = conn |> recycle() |> put_req_header("accept", "application/json") |> get("/api/me") |> json_response(200)
    assert me["user"]["email"] == "vedant@notyouridea.com"
    assert me["user"]["home"] == "/"

    lead =
      Noa.Accounts.User
      |> Ash.Query.for_read(:get_by_email, %{email: "vedant@notyouridea.com"})
      |> Ash.read_one!(authorize?: false)

    invite =
      signed_in(lead)
      |> post("/api/orgs/#{org_id}/invites", %{email: "Saish@NotYourIdea.com", role: "member", title: "Intern"})
      |> json_response(201)

    assert invite["invite"]["email"] == "saish@notyouridea.com"

    saish = accept!(invite["url"], "Saish")
    members = signed_in(saish) |> get("/api/orgs/#{org_id}/members") |> json_response(200)
    assert members["members"] |> Enum.map(& &1["user"]["name"]) |> Enum.sort() == ["Saish", "Vedant"]
  end

  test "a workspace is not created when its admin's email is off-domain", %{root: root} do
    body =
      signed_in(root)
      |> post("/api/platform/orgs", %{name: "Typo Co", domains: "typo.co", admin_email: "boss@gmail.com"})
      |> json_response(422)

    assert body["error"] == "not_work_email"
    assert {:ok, orgs} = Noa.Orgs.list_orgs(root)
    refute Enum.any?(orgs, &(&1.name == "Typo Co"))
  end

  test "password reset emails a link to the web app and the token sets a new password", %{lead_url: url} do
    accept!(url, "Vedant", "a-long-password")
    assert_email_sent(subject: "Saish invited you to NotYourIdea on Noa")

    json_conn()
    |> post("/auth/user/password/reset_request", %{user: %{email: "vedant@notyouridea.com"}})
    |> json_response(200)

    assert_email_sent(fn email ->
      [_, token] = Regex.run(~r{/reset-password\?token=([^\s"<]+)}, email.text_body)
      send(self(), {:reset_token, URI.decode_www_form(token)})
      email.subject == "Reset your Noa password"
    end)

    assert_received {:reset_token, token}

    reset =
      json_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> post("/auth/user/password/reset", %{user: %{reset_token: token, password: "a-brand-new-password"}})

    assert json_response(reset, 200)["user"]["email"] == "vedant@notyouridea.com"

    assert json_conn()
           |> post("/auth/user/password/sign_in", %{
             user: %{email: "vedant@notyouridea.com", password: "a-brand-new-password"}
           })
           |> json_response(200)
  end

  test "only work emails can be invited", %{root: root, org_id: org_id} do
    body = signed_in(root) |> post("/api/orgs/#{org_id}/invites", %{email: "someone@gmail.com"}) |> json_response(422)
    assert body["error"] == "not_work_email"
  end

  test "members cannot invite, manage people or see the platform console", %{org_id: org_id, lead_url: url} do
    lead = accept!(url, "Vedant")
    {:ok, org} = Noa.Orgs.get_org(org_id, lead)
    {:ok, _, saish_url} = Noa.Orgs.invite(org, "saish@notyouridea.com", :member, lead)
    saish = accept!(saish_url, "Saish")

    assert signed_in(saish)
           |> post("/api/orgs/#{org_id}/invites", %{email: "soha@notyouridea.com"})
           |> json_response(403)

    assert signed_in(saish) |> get("/api/orgs/#{org_id}/invites") |> json_response(200) == %{"invites" => []}
    assert signed_in(saish) |> get("/api/platform/orgs") |> json_response(403)

    [lead_membership] = Noa.Orgs.memberships_for(lead)

    assert signed_in(saish)
           |> patch("/api/orgs/#{org_id}/members/#{lead_membership.id}", %{role: "member"})
           |> json_response(403)
  end

  test "the last admin can't be demoted or removed until there is another", %{org_id: org_id, lead_url: url} do
    lead = accept!(url, "Vedant")
    {:ok, org} = Noa.Orgs.get_org(org_id, lead)
    [lead_m] = Noa.Orgs.memberships_for(lead)

    for conn <- [
          signed_in(lead) |> patch("/api/orgs/#{org_id}/members/#{lead_m.id}", %{role: "member"}),
          signed_in(lead) |> delete("/api/orgs/#{org_id}/members/#{lead_m.id}")
        ] do
      assert json_response(conn, 409)["error"] == "last_admin"
    end

    {:ok, _, ojas_url} = Noa.Orgs.invite(org, "ojas@notyouridea.com", :org_admin, lead)
    accept!(ojas_url, "Ojas")

    assert signed_in(lead)
           |> patch("/api/orgs/#{org_id}/members/#{lead_m.id}", %{role: "pm"})
           |> json_response(200)
  end

  test "one org's admin cannot see another org", %{root: root, org_id: nyi_id, lead_url: url} do
    lead = accept!(url, "Vedant")

    other =
      signed_in(root)
      |> post("/api/platform/orgs", %{name: "Other Co", domains: "other.co", admin_email: "boss@other.co"})
      |> json_response(201)

    boss = accept!(other["url"], "Boss")

    assert signed_in(boss) |> get("/api/orgs/#{nyi_id}/members") |> json_response(404)

    assert signed_in(lead)
           |> post("/api/orgs/#{other["org"]["id"]}/invites", %{email: "x@other.co"})
           |> json_response(404)
  end

  test "an invite works once, and re-inviting replaces the old link", %{root: root, org_id: org_id, lead_url: url} do
    token = url |> String.split("/invite/") |> List.last()
    accept!(url, "Vedant")
    assert json_conn() |> get("/api/invites/#{token}") |> json_response(410)

    first =
      signed_in(root) |> post("/api/orgs/#{org_id}/invites", %{email: "soha@notyouridea.com"}) |> json_response(201)

    second =
      signed_in(root) |> post("/api/orgs/#{org_id}/invites", %{email: "soha@notyouridea.com"}) |> json_response(201)

    old_token = first["url"] |> String.split("/invite/") |> List.last()
    assert json_conn() |> get("/api/invites/#{old_token}") |> json_response(404)
    assert accept!(second["url"], "Soha").name == "Soha"
  end

  test "expired invites are refused", %{lead_url: url} do
    token = url |> String.split("/invite/") |> List.last()
    hash = :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
    Noa.Repo.query!("update invites set expires_at = now() - interval '1 day' where token_hash = $1", [hash])

    assert json_conn() |> get("/api/invites/#{token}") |> json_response(410)
    assert {:error, :expired} = Noa.Orgs.accept_invite(token, %{"name" => "P", "password" => "a-long-password"})
  end

  test "short passwords are rejected", %{lead_url: url} do
    token = url |> String.split("/invite/") |> List.last()
    body = json_conn() |> post("/api/invites/#{token}/accept", %{name: "P", password: "short"}) |> json_response(422)
    assert body["message"] =~ "10 characters"
  end

  test "sign in with password, then sign out", %{lead_url: url} do
    accept!(url, "Vedant", "a-long-password")

    conn =
      json_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> post("/auth/user/password/sign_in", %{
        user: %{email: "vedant@notyouridea.com", password: "a-long-password"}
      })

    assert json_response(conn, 200)["user"]["name"] == "Vedant"

    assert json_conn()
           |> post("/auth/user/password/sign_in", %{
             user: %{email: "vedant@notyouridea.com", password: "wrong-password"}
           })
           |> json_response(401)

    out = conn |> recycle() |> put_req_header("content-type", "application/json") |> delete("/api/session")
    assert json_response(out, 200) == %{"ok" => true}
    assert out |> recycle() |> put_req_header("accept", "application/json") |> get("/api/me") |> json_response(401)
  end

  test "magic link requests never reveal whether an account exists", %{lead_url: url} do
    accept!(url, "Vedant")
    assert_email_sent(subject: "Saish invited you to NotYourIdea on Noa")
    known = json_conn() |> post("/auth/user/magic_link/request", %{user: %{email: "vedant@notyouridea.com"}})
    unknown = json_conn() |> post("/auth/user/magic_link/request", %{user: %{email: "nobody@notyouridea.com"}})
    assert json_response(known, 200) == json_response(unknown, 200)
    assert_email_sent(to: "vedant@notyouridea.com", subject: "Your Noa sign-in link")
  end

  test "signed-in writes must be JSON, so other sites cannot forge them", %{root: root, org_id: org_id} do
    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> AshAuthentication.Plug.Helpers.store_in_session(Noa.Accounts.with_session_token(root))
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post("/api/orgs/#{org_id}/invites", "email=x%40notyouridea.com")

    assert conn.status == 415
  end
end
