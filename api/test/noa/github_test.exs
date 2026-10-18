defmodule Noa.GitHubTest do
  @moduledoc """
  GitHub (3.7): signed webhooks record commits, pull requests and CI runs once; a merged
  pull request proposes closing its task; packs show recent changes; backfill reads the API.
  Graph checks need FalkorDB.
  """
  use NoaWeb.ConnCase, async: false

  alias Noa.{Events, Graph, Work}

  @seed Path.expand("../../../docs/seeds/nyi.json", __DIR__) |> File.read!() |> Jason.decode!()

  setup do
    root = superadmin!()
    {:ok, org} = Noa.Orgs.create_org(%{name: "NotYourIdea", allowed_domains: ["notyouridea.com"]}, root)
    {:ok, _, url} = Noa.Orgs.invite(org, "vedant@notyouridea.com", :org_admin, root)
    vedant = accept!(url, "Vedant")
    {:ok, _} = Work.load_seed(org.id, @seed)
    {:ok, projects} = Work.projects(org.id, vedant)
    veriq = Enum.find(projects, &(&1.key == "veriq"))
    %{org: org, vedant: vedant, veriq: veriq, repo: veriq.repo}
  end

  defp hook(event, payload, secret \\ "test-github-secret") do
    body = Jason.encode!(payload)
    sig = "sha256=" <> (:crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower))

    build_conn()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-github-event", event)
    |> put_req_header("x-hub-signature-256", sig)
    |> post("/webhooks/github", body)
  end

  defp push(repo, sha \\ "abc123"),
    do: %{
      "ref" => "refs/heads/main",
      "repository" => %{"full_name" => repo},
      "commits" => [
        %{
          "id" => sha,
          "message" => "Render the board report PDF with Typst\n\nlonger body",
          "url" => "https://github.com/#{repo}/commit/#{sha}",
          "timestamp" => "2026-10-18T09:00:00Z",
          "author" => %{"username" => "Saish-NYI", "name" => "Saish Korgaonkar", "email" => "s@x.com"}
        }
      ]
    }

  defp pr(repo, attrs),
    do: %{
      "action" => "closed",
      "repository" => %{"full_name" => repo},
      "pull_request" =>
        Map.merge(
          %{
            "number" => 42,
            "title" => "Board report PDF export",
            "state" => "closed",
            "merged" => true,
            "merged_at" => DateTime.to_iso8601(DateTime.utc_now()),
            "updated_at" => DateTime.to_iso8601(DateTime.utc_now()),
            "html_url" => "https://github.com/#{repo}/pull/42",
            "head" => %{"ref" => "saish/board-report-pdf-export"},
            "user" => %{"login" => "Saish-NYI"}
          },
          attrs
        )
    }

  defp events(org, type), do: Events.since(0, org_id: org.id, limit: 10_000) |> Enum.filter(&(&1.type == type))

  test "a signed push records each commit once, linked to the project and its author", %{
    org: org,
    repo: repo,
    veriq: veriq
  } do
    assert %{"recorded" => 1} = hook("push", push(repo)) |> json_response(200)
    assert %{"recorded" => 0} = hook("push", push(repo)) |> json_response(200)

    [c] = events(org, "commit.pushed")
    saish = Work.Person |> Ash.read!(authorize?: false) |> Enum.find(&(&1.org_id == org.id and &1.key == "sa"))
    assert c.data["project_id"] == veriq.id and c.data["person_id"] == saish.id
    assert c.data["message"] == "Render the board report PDF with Typst" and c.data["branch"] == "main"
  end

  test "bad signatures and unknown repos are refused", %{repo: repo} do
    assert hook("push", push(repo), "wrong").status == 401
    assert %{"ignored" => "unknown_repo"} = hook("push", push("someone/else")) |> json_response(200)
  end

  test "a merged pull request proposes closing the task it finished", ctx do
    %{org: org, vedant: vedant, veriq: veriq, repo: repo} = ctx
    {:ok, task} = Work.create_task(org.id, %{title: "Board report PDF export", project_id: veriq.id}, vedant)

    assert %{"recorded" => 1} = hook("pull_request", pr(repo, %{})) |> json_response(200)
    [pr_event] = events(org, "pr.saved")
    assert pr_event.data["state"] == "merged" and pr_event.data["id"] == "#{repo}#42"

    {:ok, proposals} = Work.proposals(org.id, vedant)
    p = Enum.find(proposals, &(&1.task_id == task.id))
    assert p.kind == :status_change and p.data["status"] == "done" and p.source["channel"] == "GitHub"

    {:ok, approved} = Work.approve(p.id, %{}, vedant)
    assert approved.task.status == :done
  end

  test "CI runs are recorded, and the pack shows recent changes", ctx do
    %{org: org, vedant: vedant, veriq: veriq, repo: repo} = ctx

    run = %{
      "repository" => %{"full_name" => repo},
      "workflow_run" => %{
        "id" => 9,
        "run_attempt" => 1,
        "status" => "completed",
        "conclusion" => "failure",
        "name" => "api",
        "head_branch" => "main",
        "head_sha" => "abc123",
        "html_url" => "https://github.com/#{repo}/actions/runs/9",
        "updated_at" => "2026-10-18T09:05:00Z"
      }
    }

    assert %{"recorded" => 1} = hook("workflow_run", run) |> json_response(200)
    hook("pull_request", pr(repo, %{}))

    hook(
      "pull_request",
      pr(repo, %{
        "number" => 43,
        "title" => "Score weights v3",
        "state" => "open",
        "merged" => false,
        "merged_at" => nil,
        "head" => %{"ref" => "ve/score-v3"}
      })
    )

    {:ok, pack} = Noa.Packs.build(org.id, veriq.id, vedant)
    md = Enum.find(pack.files, &(&1.path == "CLAUDE.md")).content
    assert md =~ "## Recent changes on GitHub"
    assert md =~ "Merged: #42 Board report PDF export"
    assert md =~ "Open PR: #43 Score weights v3"
    assert md =~ "CI api on `main`: failure"
  end

  test "backfill reads commits and pull requests from GitHub's API", %{org: org, veriq: veriq, repo: repo} do
    Req.Test.stub(GitHubAPI, fn conn ->
      case conn.request_path do
        "/repos/" <> rest ->
          if String.ends_with?(rest, "/commits") do
            Req.Test.json(conn, [
              %{
                "sha" => "c2",
                "html_url" => "u",
                "commit" => %{
                  "message" => "Fix the queue",
                  "author" => %{"name" => "Vedant", "email" => "v@x", "date" => "2026-10-17T10:00:00Z"}
                },
                "author" => %{"login" => "VedantNYI"}
              }
            ])
          else
            Req.Test.json(conn, [pr(repo, %{"number" => 7, "title" => "Old PR"})["pull_request"]])
          end
      end
    end)

    assert {:ok, 2} =
             Noa.GitHub.backfill(veriq, base_url: "http://github.test", req_options: [plug: {Req.Test, GitHubAPI}])

    assert [_] = events(org, "commit.pushed")
    assert [_] = events(org, "pr.saved")
  end

  @tag :graph
  test "commits and pull requests land in the graph and count toward who knows the project", ctx do
    %{org: org, repo: repo, veriq: veriq} = ctx
    on_exit(fn -> Graph.drop(org.id) end)
    :ok = Graph.bootstrap(org.id)
    hook("push", push(repo))
    hook("pull_request", pr(repo, %{}))
    for e <- Events.since(0, org_id: org.id, limit: 10_000), do: :ok = Noa.Graph.Projector.project(e)

    {:ok, [%{"n" => 1}]} =
      Graph.ro_query(
        org.id,
        "MATCH (:Person {name: 'Saish'})-[:COMMITTED]->(c:Commit)-[:BELONGS_TO]->(:Project {key: 'veriq'}) RETURN count(c) AS n"
      )

    {:ok, [%{"state" => "merged"}]} =
      Graph.ro_query(org.id, "MATCH (:Person {name: 'Saish'})-[:OPENED]->(r:PullRequest) RETURN r.state AS state")

    {:ok, experts} = Noa.Graph.Experts.experts(org.id, veriq.id)
    saish = Enum.find(experts, &(&1.name == "Saish"))
    # 1 for the commit + 2 for the merged PR on top of his allocation-free history.
    assert saish.weight >= 3
  end
end
