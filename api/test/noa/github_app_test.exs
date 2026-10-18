defmodule Noa.GitHubAppTest do
  @moduledoc """
  Noa's GitHub App (3.7): an org admin installs it from Settings; GitHub's deliveries are
  checked with the app's secret and land in the workspace that installed it; history is
  read with installation tokens. GitHub's API is stubbed.
  """
  use NoaWeb.ConnCase, async: false

  alias Noa.{Connectors, Events, Work}

  @seed Path.expand("../../../docs/seeds/nyi.json", __DIR__) |> File.read!() |> Jason.decode!()

  setup do
    jwk = JOSE.JWK.generate_key({:rsa, 2048})
    {_, pem} = JOSE.JWK.to_pem(jwk)
    previous = Application.get_env(:noa, Noa.GitHub)

    Application.put_env(:noa, Noa.GitHub,
      app_id: "123",
      slug: "noa-test",
      private_key: pem,
      app_webhook_secret: "app-secret",
      api_url: "http://gh.test",
      req_options: [plug: {Req.Test, GitHubApp}]
    )

    on_exit(fn -> Application.put_env(:noa, Noa.GitHub, previous) end)

    root = superadmin!()
    {:ok, org} = Noa.Orgs.create_org(%{name: "NotYourIdea", allowed_domains: ["notyouridea.com"]}, root)
    {:ok, _, url} = Noa.Orgs.invite(org, "vedant@notyouridea.com", :org_admin, root)
    vedant = accept!(url, "Vedant")
    {:ok, _, url} = Noa.Orgs.invite(org, "saish@notyouridea.com", :pm, vedant)
    saish = accept!(url, "Saish")
    {:ok, _} = Work.load_seed(org.id, @seed)

    # Another company with a project on a repo of the same name, to prove isolation.
    {:ok, acme} = Noa.Orgs.create_org(%{name: "Acme", allowed_domains: ["acme.test"]}, root)
    {:ok, _, url} = Noa.Orgs.invite(acme, "ada@acme.test", :org_admin, root)
    ada = accept!(url, "Ada")
    {:ok, _} = Work.Setup.create_project(acme.id, %{name: "Veriq copy", repo: "Not-Your-Idea/veriq"}, ada)

    %{org: org, vedant: vedant, saish: saish, acme: acme, ada: ada, jwk: jwk}
  end

  defp state_from(url), do: url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query() |> Map.fetch!("state")

  defp deliver(event, payload, secret \\ "app-secret") do
    body = Jason.encode!(payload)
    sig = "sha256=" <> (:crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower))

    build_conn()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-github-event", event)
    |> put_req_header("x-hub-signature-256", sig)
    |> post("/webhooks/github", body)
  end

  defp push_event(installation, sha),
    do: %{
      "ref" => "refs/heads/main",
      "installation" => %{"id" => installation},
      "repository" => %{"full_name" => "Not-Your-Idea/veriq"},
      "commits" => [
        %{
          "id" => sha,
          "message" => "Ship it",
          "timestamp" => "2026-10-18T09:00:00Z",
          "author" => %{"username" => "Saish-NYI"}
        }
      ]
    }

  defp commits(org), do: Events.since(0, org_id: org.id, limit: 1000) |> Enum.filter(&(&1.type == "commit.pushed"))

  test "the app's JWT is signed with its private key and names the app", %{jwk: jwk} do
    token = Noa.GitHub.App.jwt()
    {true, %JOSE.JWT{fields: claims}, _} = JOSE.JWT.verify_strict(JOSE.JWK.to_public(jwk), ["RS256"], token)
    assert claims["iss"] == "123" and claims["exp"] - claims["iat"] == 600
  end

  test "an org admin installs the app; deliveries land in their workspace only", ctx do
    %{org: org, vedant: vedant, saish: saish, acme: acme} = ctx

    status = signed_in(vedant) |> get("/api/orgs/#{org.id}/connectors") |> json_response(200)
    assert status["github"]["app"] and not status["github"]["installed"]
    url = status["github"]["install_url"]
    assert url =~ "https://github.com/apps/noa-test/installations/new?state="

    # PMs don't get an install link.
    assert signed_in(saish)
           |> get("/api/orgs/#{org.id}/connectors")
           |> json_response(200)
           |> get_in(["github", "install_url"]) == nil

    # GitHub sends the admin back to the setup URL.
    conn =
      build_conn() |> get("/github/setup", %{installation_id: "999", setup_action: "install", state: state_from(url)})

    assert redirected_to(conn) =~ "/settings?github=installed"
    assert Connectors.org_for_installation(999) == org.id

    assert %{"recorded" => 1} = deliver("push", push_event(999, "a1")) |> json_response(200)
    assert [_] = commits(org)
    assert [] == commits(acme)

    # Unknown installations and wrong secrets get nothing.
    assert %{"ignored" => "unknown_installation"} = deliver("push", push_event(555, "a2")) |> json_response(200)
    assert deliver("push", push_event(999, "a3"), "wrong").status == 401

    # Uninstalling on GitHub disconnects the workspace.
    assert deliver("installation", %{"action" => "deleted", "installation" => %{"id" => 999}}) |> json_response(200)
    assert Connectors.org_for_installation(999) == nil
  end

  test "install links are checked: a member's, a tampered one, or a second workspace's are refused", ctx do
    %{org: org, saish: saish, acme: acme, ada: ada} = ctx
    member_state = Phoenix.Token.sign(NoaWeb.Endpoint, "github-install", %{org: org.id, user: saish.id})
    assert {:error, :not_admin} = Connectors.complete_github_install(member_state, "1")
    assert {:error, :install_invalid} = Connectors.complete_github_install("garbage", "1")

    {:ok, _} =
      Connectors.complete_github_install(
        Phoenix.Token.sign(NoaWeb.Endpoint, "github-install", %{org: acme.id, user: ada.id}),
        "7"
      )

    vedant_state = Phoenix.Token.sign(NoaWeb.Endpoint, "github-install", %{org: org.id, user: ctx.vedant.id})
    assert {:error, :installation_taken} = Connectors.complete_github_install(vedant_state, "7")
  end

  test "history is read with the installation's token", ctx do
    %{org: org, vedant: vedant} = ctx

    {:ok, _} =
      Connectors.complete_github_install(
        Phoenix.Token.sign(NoaWeb.Endpoint, "github-install", %{org: org.id, user: vedant.id}),
        "999"
      )

    test = self()

    Req.Test.stub(GitHubApp, fn conn ->
      case {conn.method, conn.request_path} do
        {"POST", "/app/installations/999/access_tokens"} ->
          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{
            "token" => "ghs_install",
            "expires_at" => DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), 3600, :second))
          })

        {"GET", "/installation/repositories"} ->
          Req.Test.json(conn, %{"repositories" => [%{"full_name" => "Not-Your-Idea/veriq"}]})

        {"GET", path} ->
          send(test, {:auth, path, Plug.Conn.get_req_header(conn, "authorization")})
          Req.Test.json(conn, [])
      end
    end)

    assert %{"repos" => ["Not-Your-Idea/veriq"]} =
             signed_in(vedant) |> get("/api/orgs/#{org.id}/connectors/github/repos") |> json_response(200)

    veriq = Enum.find(Work.projects(org.id, vedant) |> elem(1), &(&1.key == "veriq"))
    assert {:ok, 0} = Noa.GitHub.backfill(veriq, base_url: "http://gh.test", req_options: [plug: {Req.Test, GitHubApp}])
    assert_received {:auth, "/repos/Not-Your-Idea/veriq/commits", ["Bearer ghs_install"]}
  end
end
