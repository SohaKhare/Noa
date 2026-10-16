defmodule NoaWeb.WorkTest do
  @moduledoc """
  Projects, people, tasks and the Inbox (1.23, 1.24) on the NYI seed: Vedant is the
  lead (org admin), Saish a member, Soha a guest.
  """
  use NoaWeb.ConnCase, async: true

  @seed Path.expand("../../../docs/seeds/nyi.json", __DIR__) |> File.read!() |> Jason.decode!()
  @sample Path.expand("../../../docs/seeds/nyi-sample-work.json", __DIR__) |> File.read!() |> Jason.decode!()

  setup do
    root = superadmin!()
    {:ok, org} = Noa.Orgs.create_org(%{name: "NotYourIdea", allowed_domains: ["notyouridea.com"]}, root)
    {:ok, _, lead_url} = Noa.Orgs.invite(org, "vedant@notyouridea.com", :org_admin, root)
    vedant = accept!(lead_url, "Vedant")
    {:ok, _, saish_url} = Noa.Orgs.invite(org, "saish@notyouridea.com", :member, vedant)
    saish = accept!(saish_url, "Saish")
    {:ok, _, soha_url} = Noa.Orgs.invite(org, "soha@notyouridea.com", :guest, vedant)
    soha = accept!(soha_url, "Soha")

    {:ok, counts} = Noa.Work.load_seed(org.id, @seed)
    {:ok, _} = Noa.Work.Seed.load_sample(org.id, @sample)

    %{org: org, root: root, vedant: vedant, saish: saish, soha: soha, counts: counts}
  end

  defp pending(user, org), do: signed_in(user) |> get("/api/orgs/#{org.id}/proposals") |> json_response(200)
  defp proposal(user, org, summary), do: pending(user, org)["proposals"] |> Enum.find(&(&1["summary"] == summary))

  test "the seed loads the org map and links people to their accounts", %{org: org, vedant: vedant, counts: counts} do
    assert counts.people == 5 and counts.projects == 4
    assert counts.linked == 3

    # Running it again updates in place.
    {:ok, _} = Noa.Work.load_seed(org.id, @seed)
    {:ok, people} = Noa.Work.people(org.id, vedant)
    assert length(people) == 5

    dir = signed_in(vedant) |> get("/api/orgs/#{org.id}/directory") |> json_response(200)
    assert dir["projects"] |> Enum.map(& &1["name"]) == ["Emmarie", "Tulpa", "Veriq", "Video Break"]
    me = Enum.find(dir["people"], &(&1["id"] == dir["me"]))
    assert me["name"] == "Vedant" and me["role"] == "org_admin"

    veriq = Enum.find(dir["projects"], &(&1["key"] == "veriq"))
    assert veriq["lead_id"] == me["id"]
    assert "reports" in veriq["aliases"]
    assert veriq["allocations"] |> Enum.map(& &1["percent"]) |> Enum.sort() == [20, 40]
    assert Enum.find(dir["channels"], &(&1["name"] == "#dev"))["split"]
  end

  test "the seed feeds extraction's vocabulary from the database", %{org: org} do
    vocab = Noa.Work.vocabulary(org.id)
    assert Noa.Extraction.Vocabulary.channel_route(vocab, "#veriq") == "veriq"
    assert Noa.Extraction.Vocabulary.channel_route(vocab, "#random") == nil
    assert Noa.Extraction.Vocabulary.person(vocab, "VedantNYI").id == "ve"
    assert Enum.any?(vocab.open_tasks, &(&1.title == "Score weights v2"))
  end

  test "a member approves a task proposal about themselves and it lands on the board", %{org: org, saish: saish} do
    p = proposal(saish, org, "Board report PDF export")

    body =
      signed_in(saish)
      |> post("/api/orgs/#{org.id}/proposals/#{p["id"]}/approve", %{})
      |> json_response(200)

    assert body["proposal"]["status"] == "approved"
    assert body["task"]["title"] == "Board report PDF export"
    assert body["task"]["source"]["quote"] =~ "on it"
    assert body["task"]["project_id"] == p["project_id"]

    tasks = signed_in(saish) |> get("/api/orgs/#{org.id}/tasks?project_id=#{p["project_id"]}") |> json_response(200)
    assert Enum.any?(tasks["tasks"], &(&1["title"] == "Board report PDF export"))

    assert signed_in(saish) |> post("/api/orgs/#{org.id}/proposals/#{p["id"]}/approve", %{}) |> json_response(409)
  end

  test "a member can't approve someone else's change; the lead can", %{org: org, saish: saish, vedant: vedant} do
    p = proposal(vedant, org, "Prompt plan review moves out 2 days")
    assert signed_in(saish) |> post("/api/orgs/#{org.id}/proposals/#{p["id"]}/approve", %{}) |> json_response(403)

    body = signed_in(vedant) |> post("/api/orgs/#{org.id}/proposals/#{p["id"]}/approve", %{}) |> json_response(200)
    assert body["task"]["due_on"] == p["data"]["new_due"]

    status = proposal(vedant, org, "Score weights v2 → done")
    body = signed_in(vedant) |> post("/api/orgs/#{org.id}/proposals/#{status["id"]}/approve", %{}) |> json_response(200)
    assert body["task"]["status"] == "done" and body["task"]["done_at"]
  end

  test "a proposal with no project asks for one before it can be approved", %{org: org, vedant: vedant} do
    p = proposal(vedant, org, "Caption style guide for reels")
    assert p["data"]["route"]["candidates"] == ["emmarie", "video-break"]

    assert signed_in(vedant) |> post("/api/orgs/#{org.id}/proposals/#{p["id"]}/approve", %{}) |> json_response(422)

    dir = signed_in(vedant) |> get("/api/orgs/#{org.id}/directory") |> json_response(200)
    vb = Enum.find(dir["projects"], &(&1["key"] == "video-break"))

    body =
      signed_in(vedant)
      |> post("/api/orgs/#{org.id}/proposals/#{p["id"]}/approve", %{
        project_id: vb["id"],
        data: %{title: "Caption style guide"}
      })
      |> json_response(200)

    assert body["task"]["project_id"] == vb["id"] and body["task"]["title"] == "Caption style guide"
  end

  test "dismissing takes a proposal out of the Inbox", %{org: org, vedant: vedant} do
    p = proposal(vedant, org, "Caption style guide for reels")
    assert signed_in(vedant) |> post("/api/orgs/#{org.id}/proposals/#{p["id"]}/reject", %{}) |> json_response(200)
    refute proposal(vedant, org, "Caption style guide for reels")
  end

  test "members move cards; guests only look", %{org: org, saish: saish, soha: soha} do
    [task | _] =
      signed_in(saish) |> get("/api/orgs/#{org.id}/tasks?open=true") |> json_response(200) |> Map.fetch!("tasks")

    moved =
      signed_in(saish)
      |> patch("/api/orgs/#{org.id}/tasks/#{task["id"]}", %{status: "in_progress"})
      |> json_response(200)

    assert moved["task"]["status"] == "in_progress"

    assert signed_in(soha) |> get("/api/orgs/#{org.id}/tasks") |> json_response(200)
    assert signed_in(soha) |> patch("/api/orgs/#{org.id}/tasks/#{task["id"]}", %{status: "done"}) |> json_response(403)

    assert signed_in(soha)
           |> post("/api/orgs/#{org.id}/tasks", %{title: "x", project_id: task["project_id"]})
           |> json_response(403)
  end

  test "another workspace sees none of it", %{org: org, root: root, vedant: vedant} do
    {:ok, other} = Noa.Orgs.create_org(%{name: "Other Co", allowed_domains: ["other.co"]}, root)
    {:ok, _, url} = Noa.Orgs.invite(other, "boss@other.co", :org_admin, root)
    boss = accept!(url, "Boss")

    assert signed_in(boss) |> get("/api/orgs/#{org.id}/tasks") |> json_response(200) == %{"tasks" => []}
    assert signed_in(boss) |> get("/api/orgs/#{org.id}/directory") |> json_response(404)

    [task | _] = signed_in(vedant) |> get("/api/orgs/#{org.id}/tasks") |> json_response(200) |> Map.fetch!("tasks")
    assert signed_in(boss) |> patch("/api/orgs/#{org.id}/tasks/#{task["id"]}", %{status: "done"}) |> json_response(404)

    assert signed_in(boss)
           |> patch("/api/orgs/#{other.id}/tasks/#{task["id"]}", %{status: "done"})
           |> json_response(404)
  end

  test "extraction proposals are stored in the Inbox with their source", %{org: org, vedant: vedant} do
    line = %Noa.Extraction.Line{
      id: "m1",
      seq: 1,
      channel: "#veriq",
      author: "Saish",
      at: ~U[2026-10-16 05:12:00Z],
      body: "on it, report share links by Monday"
    }

    item = %Noa.Extraction.Types.TaskProposal{
      title: "Report share links v2",
      owner: "Saish",
      due: ~D[2026-10-19],
      confidence: 0.9
    }

    route = %Noa.Extraction.Routing{project: "veriq", confidence: 1.0, rule: :channel}
    proposal = %Noa.Extraction.Proposal{type: :task, item: item, route: route, confidence: 0.9, evidence: ["m1"]}

    [saved] = Noa.Work.save_proposals(org.id, [proposal], [line])
    assert saved.summary == "Report share links v2"
    assert saved.source["quote"] =~ "share links"

    p = proposal(vedant, org, "Report share links v2")
    assert p["owner_id"] && p["project_id"]
    assert p["data"]["due"] == "2026-10-19"
  end
end
