defmodule NoaWeb.ConnectorsTest do
  @moduledoc """
  Each company's org admin connects their own Discord server and GitHub (1.18). Secrets
  are stored encrypted and never returned again; a server belongs to one workspace.
  """
  use NoaWeb.ConnCase, async: false

  alias Noa.{Connectors, Events, Work}

  @seed Path.expand("../../../docs/seeds/nyi.json", __DIR__) |> File.read!() |> Jason.decode!()

  setup do
    root = superadmin!()
    {:ok, org} = Noa.Orgs.create_org(%{name: "NotYourIdea", allowed_domains: ["notyouridea.com"]}, root)
    {:ok, _, url} = Noa.Orgs.invite(org, "vedant@notyouridea.com", :org_admin, root)
    vedant = accept!(url, "Vedant")
    {:ok, _, url} = Noa.Orgs.invite(org, "saish@notyouridea.com", :pm, vedant)
    saish = accept!(url, "Saish")
    {:ok, _} = Work.load_seed(org.id, @seed)

    {:ok, other} = Noa.Orgs.create_org(%{name: "Acme", allowed_domains: ["acme.test"]}, root)
    {:ok, _, url} = Noa.Orgs.invite(other, "ada@acme.test", :org_admin, root)
    ada = accept!(url, "Ada")

    # Only the workspace's own secret counts: no platform secret in this test.
    previous = Application.get_env(:noa, Noa.GitHub)
    Application.put_env(:noa, Noa.GitHub, [])
    on_exit(fn -> Application.put_env(:noa, Noa.GitHub, previous) end)

    %{org: org, vedant: vedant, saish: saish, other: other, ada: ada}
  end

  defp hook(payload, secret) do
    body = Jason.encode!(payload)
    sig = "sha256=" <> (:crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower))

    build_conn()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-github-event", "push")
    |> put_req_header("x-hub-signature-256", sig)
    |> post("/webhooks/github", body)
  end

  defp push,
    do: %{
      "ref" => "refs/heads/main",
      "repository" => %{"full_name" => "Not-Your-Idea/veriq"},
      "commits" => [
        %{
          "id" => "c1",
          "message" => "hi",
          "timestamp" => "2026-10-18T09:00:00Z",
          "author" => %{"username" => "Saish-NYI"}
        }
      ]
    }

  test "an org admin's GitHub secret verifies their repo's webhooks; it's shown once and stored encrypted", ctx do
    %{org: org, vedant: vedant} = ctx

    %{"secret" => secret, "webhook" => webhook} =
      signed_in(vedant) |> post("/api/orgs/#{org.id}/connectors/github/secret") |> json_response(200)

    assert webhook =~ "/webhooks/github"
    status = signed_in(vedant) |> get("/api/orgs/#{org.id}/connectors") |> json_response(200)
    assert status["github"]["secret_set"] and not Map.has_key?(status["github"], "secret")

    [row] = Noa.Repo.query!("select secret_enc from org_connectors").rows
    refute hd(row) =~ secret

    assert %{"recorded" => 1} = hook(push(), secret) |> json_response(200)
    assert hook(push(), "someone-elses").status == 401
    assert [_] = Events.since(0, org_id: org.id, limit: 1000) |> Enum.filter(&(&1.type == "commit.pushed"))

    # Rotating makes the old secret stop working.
    %{"secret" => fresh} =
      signed_in(vedant) |> post("/api/orgs/#{org.id}/connectors/github/secret") |> json_response(200)

    assert hook(push(), secret).status == 401
    assert hook(Map.update!(push(), "commits", fn [c] -> [%{c | "id" => "c2"}] end), fresh).status == 200

    assert signed_in(vedant)
           |> put("/api/orgs/#{org.id}/connectors/github/token", %{token: "ghp_test"})
           |> json_response(200)

    assert Connectors.github_token(org.id) == "ghp_test"
  end

  test "a Discord server belongs to the workspace that connected it", ctx do
    %{org: org, vedant: vedant, other: other, ada: ada} = ctx
    assert signed_in(vedant) |> put("/api/orgs/#{org.id}/connectors/discord", %{guild_id: "nope"}) |> json_response(422)

    assert signed_in(vedant)
           |> put("/api/orgs/#{org.id}/connectors/discord", %{guild_id: "123456789012345678"})
           |> json_response(200)

    assert Connectors.org_for_guild("123456789012345678") == org.id
    assert Connectors.org_for_guild(123_456_789_012_345_678) == org.id

    assert signed_in(ada)
           |> put("/api/orgs/#{other.id}/connectors/discord", %{guild_id: "123456789012345678"})
           |> json_response(409)

    # Messages from that server now land in that workspace.
    {:ok, event} =
      Noa.Ingest.Discord.ingest(%{
        id: 77,
        guild_id: 123_456_789_012_345_678,
        channel_id: 5,
        channel_name: "veriq",
        content: "on it",
        timestamp: ~U[2026-10-18 09:00:00Z],
        author: %{id: 9, username: "saish"}
      })

    assert event.org_id == org.id

    assert signed_in(vedant) |> delete("/api/orgs/#{org.id}/connectors/discord") |> json_response(200)
    assert Connectors.org_for_guild("123456789012345678") == nil
  end

  test "PMs and members can see the status but not change connectors", ctx do
    %{org: org, saish: saish} = ctx
    assert signed_in(saish) |> get("/api/orgs/#{org.id}/connectors") |> json_response(200)
    assert signed_in(saish) |> post("/api/orgs/#{org.id}/connectors/github/secret") |> json_response(403)

    assert signed_in(saish)
           |> put("/api/orgs/#{org.id}/connectors/discord", %{guild_id: "123456789012345678"})
           |> json_response(403)

    assert signed_in(saish) |> delete("/api/orgs/#{org.id}/connectors/github") |> json_response(403)
  end
end
