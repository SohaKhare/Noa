defmodule NoaWeb.SlackConnectorTest do
  use NoaWeb.ConnCase, async: false
  use Oban.Testing, repo: Noa.Repo

  alias Noa.Connectors
  alias Noa.Ingest.Slack.SyncUsers

  setup do
    root = superadmin!()
    {:ok, org} = Noa.Orgs.create_org(%{name: "NotYourIdea", allowed_domains: ["notyouridea.com"]}, root)
    {:ok, _, url} = Noa.Orgs.invite(org, "vedant@notyouridea.com", :org_admin, root)
    vedant = accept!(url, "Vedant")

    previous = Application.get_env(:noa, Noa.Ingest.Slack.Client)

    Application.put_env(
      :noa,
      Noa.Ingest.Slack.Client,
      Keyword.put(previous, :req_options, plug: {Req.Test, SlackOAuthAPI})
    )

    Req.Test.stub(SlackOAuthAPI, fn
      %{request_path: "/api/oauth.v2.access"} = conn ->
        Req.Test.json(conn, %{
          "ok" => true,
          "access_token" => "xoxb-workspace-token",
          "team" => %{"id" => "T001", "name" => "NotYourIdea"}
        })

      %{request_path: "/api/auth.revoke"} = conn ->
        Req.Test.json(conn, %{"ok" => true, "revoked" => true})
    end)

    on_exit(fn -> Application.put_env(:noa, Noa.Ingest.Slack.Client, previous) end)
    %{org: org, vedant: vedant}
  end

  test "an org admin installs one Slack workspace through signed OAuth state", %{org: org, vedant: vedant} do
    url = Connectors.slack_install_url(org.id, vedant)
    query = url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    assert query["scope"] =~ "channels:history"
    assert query["scope"] =~ "groups:history"
    assert {:ok, installed_org_id} = Connectors.complete_slack_install(query["state"], "oauth-code")
    assert installed_org_id == org.id
    assert Connectors.org_for_slack_team("T001") == org.id
    assert Connectors.slack_token(org.id) == "xoxb-workspace-token"
    assert_enqueued(worker: SyncUsers, args: %{"org_id" => org.id})

    assert {:ok, reinstalled_org_id} = Connectors.complete_slack_install(query["state"], "oauth-code")
    assert reinstalled_org_id == org.id

    [stored] = Noa.Repo.query!("select token_enc from org_connectors where kind = 'slack'").rows
    refute hd(stored) =~ "xoxb-workspace-token"

    status = signed_in(vedant) |> get("/api/orgs/#{org.id}/connectors") |> json_response(200)
    assert status["slack"]["connected"]
    assert status["slack"]["team_id"] == "T001"
    refute Map.has_key?(status["slack"], "token")

    assert signed_in(vedant) |> delete("/api/orgs/#{org.id}/connectors/slack") |> json_response(200)
    assert Connectors.org_for_slack_team("T001") == nil
  end

  test "OAuth state cannot be used by a non-admin or for a second workspace", %{org: org, vedant: vedant} do
    url = Connectors.slack_install_url(org.id, vedant)
    state = url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query() |> Map.fetch!("state")
    assert {:ok, _} = Connectors.complete_slack_install(state, "oauth-code")

    root = superadmin!("another-root@noa.test")
    {:ok, other} = Noa.Orgs.create_org(%{name: "Acme", allowed_domains: ["acme.test"]}, root)
    {:ok, _, invite} = Noa.Orgs.invite(other, "ada@acme.test", :org_admin, root)
    ada = accept!(invite, "Ada")

    other_state =
      Connectors.slack_install_url(other.id, ada)
      |> URI.parse()
      |> Map.fetch!(:query)
      |> URI.decode_query()
      |> Map.fetch!("state")

    assert {:error, :slack_workspace_taken} = Connectors.complete_slack_install(other_state, "oauth-code")
    assert Connectors.complete_slack_install("tampered", "oauth-code") == {:error, :install_invalid}

    {:ok, _, member_invite} = Noa.Orgs.invite(org, "member@notyouridea.com", :member, vedant)
    member = accept!(member_invite, "Member")

    member_state = Phoenix.Token.sign(NoaWeb.Endpoint, "slack-install", %{org: org.id, user: member.id})
    assert {:error, :not_admin} = Connectors.complete_slack_install(member_state, "oauth-code")
  end

  test "the OAuth callback completes installation and returns to Settings", %{org: org, vedant: vedant} do
    state =
      org.id
      |> Connectors.slack_install_url(vedant)
      |> URI.parse()
      |> Map.fetch!(:query)
      |> URI.decode_query()
      |> Map.fetch!("state")

    conn = get(build_conn(), "/slack/oauth/callback", %{"state" => state, "code" => "oauth-code"})

    assert redirected_to(conn, 302) == "http://localhost:3000/settings?slack=installed"
    assert Connectors.slack_token(org.id) == "xoxb-workspace-token"
  end
end
