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
    assert counts.people == 6 and counts.projects == 4
    assert counts.linked == 3

    # Running it again updates in place.
    {:ok, _} = Noa.Work.load_seed(org.id, @seed)
    {:ok, people} = Noa.Work.people(org.id, vedant)
    assert length(people) == 6

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

    assert signed_in(boss) |> get("/api/orgs/#{org.id}/tasks") |> json_response(404)
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

    # It names work already on the board, so the Inbox flags it (2.3)...
    assert saved.data["duplicate_of"]["title"] == "Report share links"
    # ...and the same proposal from an overlapping window is not stored twice.
    assert Noa.Work.save_proposals(org.id, [proposal], [line]) == []
    assert saved.source["quote"] =~ "share links"

    p = proposal(vedant, org, "Report share links v2")
    assert p["owner_id"] && p["project_id"]
    assert p["data"]["due"] == "2026-10-19"
  end

  test "only an admin remaps a channel", %{org: org, vedant: vedant, saish: saish} do
    dir = signed_in(vedant) |> get("/api/orgs/#{org.id}/directory") |> json_response(200)
    random = Enum.find(dir["channels"], &(&1["name"] == "#random"))
    veriq = Enum.find(dir["projects"], &(&1["key"] == "veriq"))
    path = "/api/orgs/#{org.id}/channels/#{random["id"]}"

    assert signed_in(saish) |> patch(path, %{read: true}) |> json_response(403)

    body = signed_in(vedant) |> patch(path, %{read: true, split: false, project_id: veriq["id"]}) |> json_response(200)
    assert body["channel"]["read"] and body["channel"]["project_id"] == veriq["id"]
    assert Noa.Extraction.Vocabulary.channel_route(Noa.Work.vocabulary(org.id), "#random") == "veriq"
  end

  test "approving a decision records it, and a newer one supersedes it", %{org: org, vedant: vedant} do
    p = proposal(vedant, org, "Score all seven model families in every report")
    assert signed_in(vedant) |> post("/api/orgs/#{org.id}/proposals/#{p["id"]}/approve", %{}) |> json_response(200)

    [d] = signed_in(vedant) |> get("/api/orgs/#{org.id}/decisions") |> json_response(200) |> Map.fetch!("decisions")
    assert d["statement"] == "Score all seven model families in every report" and d["status"] == "active"
    assert d["source"]["quote"] =~ "seven families"
    assert d["made_by_id"]

    # A later decision names the first one; the first stays, marked superseded.
    veriq = Enum.find(Noa.Work.projects(org.id, vedant) |> elem(1), &(&1.key == "veriq"))

    {:ok, newer} =
      Noa.Work.Proposal
      |> Ash.Changeset.for_create(:create, %{
        kind: :decision,
        summary: "Score five model families; drop the two slowest",
        data: %{"kind" => "decision", "supersedes_ref" => "score all seven model families in every report"},
        org_id: org.id,
        project_id: veriq.id
      })
      |> Ash.create(authorize?: false)

    assert signed_in(vedant) |> post("/api/orgs/#{org.id}/proposals/#{newer.id}/approve", %{}) |> json_response(200)

    all = signed_in(vedant) |> get("/api/orgs/#{org.id}/decisions?project_id=#{veriq.id}") |> json_response(200)
    [latest, old] = all["decisions"]
    assert latest["status"] == "active" and old["status"] == "superseded" and old["superseded_by_id"] == latest["id"]

    active = signed_in(vedant) |> get("/api/orgs/#{org.id}/decisions?status=active") |> json_response(200)
    assert Enum.map(active["decisions"], & &1["id"]) == [latest["id"]]
  end

  describe "change records and lead rules (2.19, 2.20)" do
    defp task_named(org, user, title) do
      signed_in(user)
      |> get("/api/orgs/#{org.id}/tasks")
      |> json_response(200)
      |> Map.fetch!("tasks")
      |> Enum.find(&(&1["title"] == title))
    end

    test "a member's deadline change waits for the lead; status applies at once and can be reverted",
         %{org: org, vedant: vedant, saish: saish} do
      task = task_named(org, saish, "Report share links")
      path = "/api/orgs/#{org.id}/tasks/#{task["id"]}"

      body =
        signed_in(saish)
        |> patch(path, %{due_on: "2026-12-01", status: "blocked", reason: "waiting on the API keys"})
        |> json_response(200)

      # Status applied, the deadline did not.
      assert body["task"]["status"] == "blocked" and body["task"]["due_on"] == task["due_on"]

      assert [%{"kind" => "deadline", "new_value" => "2026-12-01", "reason" => "waiting on the API keys"} = pending] =
               body["pending_changes"]

      # The member can't approve it; the lead can, and the deadline moves.
      assert signed_in(saish) |> post("/api/orgs/#{org.id}/changes/#{pending["id"]}/approve") |> json_response(403)
      assert signed_in(vedant) |> post("/api/orgs/#{org.id}/changes/#{pending["id"]}/approve") |> json_response(200)
      assert task_named(org, saish, "Report share links")["due_on"] == "2026-12-01"

      # The status change is on record, and whoever made it can revert it.
      changes = signed_in(saish) |> get("/api/orgs/#{org.id}/changes?task_id=#{task["id"]}") |> json_response(200)
      status = Enum.find(changes["changes"], &(&1["kind"] == "status"))
      assert status["status"] == "applied" and status["old_value"] == task["status"]
      assert signed_in(saish) |> post("/api/orgs/#{org.id}/changes/#{status["id"]}/revert") |> json_response(200)
      assert task_named(org, saish, "Report share links")["status"] == task["status"]
    end

    test "a lead's deadline change applies at once; a rejected change leaves the task alone",
         %{org: org, vedant: vedant, saish: saish} do
      task = task_named(org, vedant, "Score weights v2")
      path = "/api/orgs/#{org.id}/tasks/#{task["id"]}"

      body = signed_in(vedant) |> patch(path, %{due_on: "2026-11-02"}) |> json_response(200)
      assert body["task"]["due_on"] == "2026-11-02" and body["pending_changes"] == []

      body = signed_in(saish) |> patch(path, %{due_on: "2026-11-09"}) |> json_response(200)
      [pending] = body["pending_changes"]
      assert signed_in(vedant) |> post("/api/orgs/#{org.id}/changes/#{pending["id"]}/reject") |> json_response(200)
      assert task_named(org, vedant, "Score weights v2")["due_on"] == "2026-11-02"

      # Decided once only.
      assert signed_in(vedant) |> post("/api/orgs/#{org.id}/changes/#{pending["id"]}/approve") |> json_response(409)
    end

    test "a member approving their own deadline proposal sends it to the lead", %{
      org: org,
      vedant: vedant,
      saish: saish
    } do
      task = task_named(org, saish, "Report share links")
      people = Noa.Work.Person |> Ash.read!(authorize?: false) |> Enum.filter(&(&1.org_id == org.id))
      me = Enum.find(people, &(&1.key == "sa"))

      {:ok, p} =
        Noa.Work.Proposal
        |> Ash.Changeset.for_create(:create, %{
          kind: :deadline_change,
          summary: "Report share links moves to Dec 3",
          data: %{"new_due" => "2026-12-03", "reason" => "client review moved"},
          source: %{"channel" => "#veriq", "author" => "Saish", "quote" => "share links will slip to the 3rd"},
          org_id: org.id,
          project_id: task["project_id"],
          owner_id: me.id,
          task_id: task["id"]
        })
        |> Ash.create(authorize?: false)

      assert signed_in(saish) |> post("/api/orgs/#{org.id}/proposals/#{p.id}/approve", %{}) |> json_response(200)
      assert task_named(org, saish, "Report share links")["due_on"] == task["due_on"]

      pending = signed_in(vedant) |> get("/api/orgs/#{org.id}/changes?status=pending") |> json_response(200)

      assert [%{"kind" => "deadline", "new_value" => "2026-12-03", "reason" => "client review moved"} = c] =
               pending["changes"]

      assert c["source"]["quote"] =~ "slip"
    end
  end

  describe "@noa (2.5)" do
    defp ask(user, org, q), do: signed_in(user) |> post("/api/orgs/#{org.id}/ask", %{question: q}) |> json_response(200)

    test "answers what is blocking a project, citing the blocked task", %{org: org, saish: saish} do
      body = ask(saish, org, "What's blocking Veriq?")
      assert [first | _] = body["citations"]
      assert first["title"] == "Brand logo pack import" and first["kind"] == "task"
      assert body["answer"] =~ "Brand logo pack import is blocked" and body["answer"] =~ "[1]"
      # Only Veriq: nothing from other projects.
      veriq = Enum.find(Noa.Work.Project |> Ash.read!(authorize?: false), &(&1.org_id == org.id and &1.key == "veriq"))
      assert Enum.all?(body["citations"], &(&1["project_id"] == veriq.id))
    end

    test "answers what was decided, from approved decisions only", %{org: org, vedant: vedant} do
      assert ask(vedant, org, "What did we decide about Veriq scoring?")["citations"] == []

      p = proposal(vedant, org, "Score all seven model families in every report")
      signed_in(vedant) |> post("/api/orgs/#{org.id}/proposals/#{p["id"]}/approve", %{}) |> json_response(200)

      body = ask(vedant, org, "What did we decide about Veriq scoring?")

      assert [%{"kind" => "decision", "title" => "Score all seven model families in every report"} | _] =
               body["citations"]

      assert body["answer"] =~ "Decided: Score all seven"
    end

    test "cites chat messages, and says so when it finds nothing", %{org: org, saish: saish} do
      {:ok, _} =
        Noa.Work.record_message(org.id, %{
          platform: :discord,
          channel: "veriq",
          message_id: "q1",
          author_id: "u-sa",
          author: "Saish",
          text: "the typst renderer handles the board report fonts now"
        })

      body = ask(saish, org, "anything about the typst renderer?")
      assert Enum.any?(body["citations"], &(&1["kind"] == "message" and &1["source"]["quote"] =~ "typst"))

      assert ask(saish, org, "zebra migration plans")["answer"] =~ "couldn't find"
    end

    test "only people in the workspace can ask", %{org: org, root: root} do
      {:ok, other} = Noa.Orgs.create_org(%{name: "Other", allowed_domains: ["other.com"]}, root)
      {:ok, _, url} = Noa.Orgs.invite(other, "x@other.com", :org_admin, root)
      outsider = accept!(url, "X")

      assert signed_in(outsider)
             |> post("/api/orgs/#{org.id}/ask", %{question: "what's blocking Veriq?"})
             |> json_response(404)
    end
  end

  describe "shifts (3.1)" do
    test "moving Soha from Video Break to Emmarie hands over her tasks and moves her allocation",
         %{org: org, vedant: vedant, saish: saish} do
      dir = signed_in(vedant) |> get("/api/orgs/#{org.id}/directory") |> json_response(200)
      key = fn list, k -> Enum.find(dir[list], &(&1["key"] == k)) end
      {soha, abhishek} = {key.("people", "so"), key.("people", "ab")}
      {vb, emmarie} = {key.("projects", "video-break"), key.("projects", "emmarie")}

      # The plan: her open Video Break task, suggested for Abhishek (the only other person on it).
      plan =
        signed_in(vedant)
        |> get("/api/orgs/#{org.id}/shifts/plan?person_id=#{soha["id"]}&from_project_id=#{vb["id"]}")
        |> json_response(200)

      assert [%{"title" => "Hook analysis: 20 reels", "to_owner_id" => to}] = plan["tasks"]
      assert to == abhishek["id"]

      body = %{person_id: soha["id"], from_project_id: vb["id"], to_project_id: emmarie["id"], note: "Emmarie demo"}

      # Members can't move people.
      assert signed_in(saish) |> post("/api/orgs/#{org.id}/shifts", body) |> json_response(403)

      shift = signed_in(vedant) |> post("/api/orgs/#{org.id}/shifts", body) |> json_response(201)
      assert shift["shift"]["percent"] == 100
      assert shift["shift"]["routes_until"] == Date.utc_today() |> Date.add(14) |> Date.to_iso8601()

      # Now on Emmarie at 100%, off Video Break.
      after_dir = signed_in(vedant) |> get("/api/orgs/#{org.id}/directory") |> json_response(200)
      allocations = Enum.find(after_dir["people"], &(&1["id"] == soha["id"]))["allocations"]
      assert [%{"project_id" => p, "percent" => 100}] = allocations
      assert p == emmarie["id"]

      # The task went to Abhishek, recorded as an owner change.
      tasks = signed_in(vedant) |> get("/api/orgs/#{org.id}/tasks?project_id=#{vb["id"]}") |> json_response(200)
      hook = Enum.find(tasks["tasks"], &(&1["title"] == "Hook analysis: 20 reels"))
      assert hook["owner_id"] == abhishek["id"]

      changes = signed_in(vedant) |> get("/api/orgs/#{org.id}/changes?task_id=#{hook["id"]}") |> json_response(200)
      assert [%{"kind" => "owner", "status" => "applied", "reason" => "Handed over in a shift"}] = changes["changes"]

      # She still takes Video Break questions for two weeks.
      {:ok, [prev]} = Noa.Work.previous_owners(org.id, vb["id"], vedant)
      assert prev.person_id == soha["id"]

      # And @noa says so.
      answer =
        signed_in(vedant)
        |> post("/api/orgs/#{org.id}/ask", %{question: "who should I ask about Video Break?"})
        |> json_response(200)

      assert answer["answer"] =~ "Ask Soha about Video Break"
    end

    test "a lead can keep a task with someone else, or leave it unassigned; moving to the same project fails",
         %{org: org, vedant: vedant} do
      dir = signed_in(vedant) |> get("/api/orgs/#{org.id}/directory") |> json_response(200)
      key = fn list, k -> Enum.find(dir[list], &(&1["key"] == k)) end
      {soha, vb} = {key.("people", "so"), key.("projects", "video-break")}
      [task] = Noa.Work.plan_shift(org.id, %{person_id: soha["id"], from_project_id: vb["id"]}, vedant) |> elem(1)

      body = %{person_id: soha["id"], from_project_id: vb["id"], to_project_id: vb["id"]}
      assert signed_in(vedant) |> post("/api/orgs/#{org.id}/shifts", body) |> json_response(422)

      body = %{person_id: soha["id"], from_project_id: vb["id"], to_project_id: "", handover: %{task.task_id => ""}}
      assert signed_in(vedant) |> post("/api/orgs/#{org.id}/shifts", body) |> json_response(201)

      tasks = signed_in(vedant) |> get("/api/orgs/#{org.id}/tasks?project_id=#{vb["id"]}") |> json_response(200)
      assert Enum.find(tasks["tasks"], &(&1["id"] == task.task_id))["owner_id"] == nil
    end
  end

  describe "KT brief (3.2)" do
    test "a brief for Soha joining Emmarie: state, her tasks, decisions and people to meet", %{org: org, vedant: vedant} do
      dir = signed_in(vedant) |> get("/api/orgs/#{org.id}/directory") |> json_response(200)
      key = fn list, k -> Enum.find(dir[list], &(&1["key"] == k)) end
      {soha, emmarie} = {key.("people", "so"), key.("projects", "emmarie")}
      {:ok, _} = Noa.Work.create_task(org.id, %{title: "Undated idea", project_id: emmarie["id"]}, vedant)

      brief =
        signed_in(vedant)
        |> get("/api/orgs/#{org.id}/projects/#{emmarie["id"]}/brief?person_id=#{soha["id"]}")
        |> json_response(200)

      sections = Map.new(brief["sections"], &{&1["title"], Enum.map(&1["items"], fn i -> i["text"] end)})
      assert hd(sections["What it is"]) =~ "film"
      assert Enum.any?(sections["Where it stands"], &(&1 =~ "Motion-test queue fix"))
      assert sections["Your tasks"] |> hd() =~ "Nothing assigned to you yet"
      assert Enum.any?(sections["People to meet"], &(&1 =~ "Vedant leads the project"))
      refute Enum.any?(sections["People to meet"], &(&1 =~ "Soha"))

      # The same brief as brief.md (3.19).
      conn =
        signed_in(vedant)
        |> get("/api/orgs/#{org.id}/projects/#{emmarie["id"]}/brief?person_id=#{soha["id"]}&format=md")

      assert conn.status == 200 and get_resp_header(conn, "content-disposition") |> hd() =~ "emmarie-brief.md"

      assert conn.resp_body =~ "# Emmarie brief" and conn.resp_body =~ "For Soha." and
               conn.resp_body =~ "## People to meet"
    end
  end

  test "experts answers even without graph data", %{org: org, saish: saish} do
    body = signed_in(saish) |> get("/api/orgs/#{org.id}/experts") |> json_response(200)
    assert Map.has_key?(body, "key_people") and Map.has_key?(body, "bus_factor")
  end

  test "titles that name the same work match; different work doesn't" do
    alias Noa.Work.Similar
    assert Similar.same?("Board report PDF export", "PDF export for the board report")
    assert Similar.same?("Report share links", "report share link")
    refute Similar.same?("Board report PDF export", "Brand logo pack import")
    refute Similar.same?("Fix", "Update")
  end

  test "work found in chat older than the history window is not filed as new work", %{org: org} do
    old = %Noa.Extraction.Line{
      id: "old1",
      seq: 1,
      channel: "#veriq",
      author: "Saish",
      at: DateTime.add(DateTime.utc_now(), -45 * 86_400, :second),
      body: "on it, by Friday"
    }

    item = %Noa.Extraction.Types.TaskProposal{title: "Old export work", owner: "Saish", confidence: 0.95}
    route = %Noa.Extraction.Routing{project: "veriq", confidence: 1.0, rule: :channel}
    proposal = %Noa.Extraction.Proposal{type: :task, item: item, route: route, confidence: 0.95, evidence: ["old1"]}

    assert [] == Noa.Work.save_proposals(org.id, [proposal], [old])

    recent = %{old | id: "new1", at: DateTime.utc_now()}
    assert [_] = Noa.Work.save_proposals(org.id, [%{proposal | evidence: ["new1"]}], [recent])
  end

  test "a task the model can't place is unowned, not the speaker's", %{org: org} do
    line = %Noa.Extraction.Line{
      id: "ask1",
      seq: 1,
      channel: "#veriq",
      author: "Saish",
      at: DateTime.utc_now(),
      body: "can someone design a reliable i2v API?"
    }

    item = %Noa.Extraction.Types.TaskProposal{title: "Design a reliable i2v API", owner: nil, confidence: 0.8}
    route = %Noa.Extraction.Routing{project: "veriq", confidence: 1.0, rule: :channel}
    proposal = %Noa.Extraction.Proposal{type: :task, item: item, route: route, confidence: 0.8, evidence: ["ask1"]}

    assert [%{owner_id: nil}] = Noa.Work.save_proposals(org.id, [proposal], [line])
  end

  describe "auto-apply with undo (2.2)" do
    defp extracted(org, type, item, confidence, task_ref \\ nil) do
      line = %Noa.Extraction.Line{
        id: "a#{System.unique_integer([:positive])}",
        seq: 1,
        channel: "#veriq",
        author: "Saish",
        at: DateTime.utc_now(),
        body: "said in chat"
      }

      item = if task_ref, do: Map.put(item, :task_ref, task_ref), else: item
      route = %Noa.Extraction.Routing{project: "veriq", confidence: 1.0, rule: :channel}

      [p] =
        Noa.Work.save_proposals(
          org.id,
          [%Noa.Extraction.Proposal{type: type, item: item, route: route, confidence: confidence, evidence: [line.id]}],
          [line]
        )

      p
    end

    defp task_titled(org, title),
      do: Noa.Work.Task |> Ash.read!(authorize?: false) |> Enum.find(&(&1.org_id == org.id and &1.title == title))

    test "a sure new task for someone who has joined applies itself, and undo takes it back", %{
      org: org,
      saish: saish,
      soha: soha
    } do
      item = %Noa.Extraction.Types.TaskProposal{
        title: "Caption style for share cards",
        owner: "Saish",
        confidence: 0.95
      }

      p = extracted(org, :task, item, 0.95)

      assert p.status == :approved and p.data["auto"]
      task = task_titled(org, "Caption style for share cards")
      assert task.created_by_id == saish.id

      # A guest can't undo it; Saish (it is about him) can.
      assert signed_in(soha) |> post("/api/orgs/#{org.id}/proposals/#{p.id}/undo") |> json_response(403)
      body = signed_in(saish) |> post("/api/orgs/#{org.id}/proposals/#{p.id}/undo") |> json_response(200)
      assert body["proposal"]["status"] == "pending" and body["proposal"]["data"]["undone"]
      assert task_titled(org, "Caption style for share cards") == nil
    end

    test "a sure status change from the task's owner applies; undo reverts it", %{org: org, saish: saish} do
      task = task_titled(org, "Report share links")
      item = %Noa.Extraction.Types.StatusChange{status: :in_progress, confidence: 0.96}
      p = extracted(org, :status_change, item, 0.96, task.id)

      assert p.status == :approved
      assert task_titled(org, "Report share links").status == :in_progress

      signed_in(saish) |> post("/api/orgs/#{org.id}/proposals/#{p.id}/undo") |> json_response(200)
      assert task_titled(org, "Report share links").status == task.status
    end

    test "less sure proposals, deadlines and decisions wait in the Inbox", %{org: org} do
      unsure =
        extracted(
          org,
          :task,
          %Noa.Extraction.Types.TaskProposal{title: "Retry queue alerts", owner: "Saish", confidence: 0.8},
          0.8
        )

      assert unsure.status == :pending

      task = task_titled(org, "Report share links")

      deadline =
        extracted(
          org,
          :deadline_change,
          %Noa.Extraction.Types.DeadlineChange{new_due: ~D[2026-12-01], confidence: 0.99},
          0.99,
          task.id
        )

      assert deadline.status == :pending
    end
  end

  describe "notification preferences (2.15)" do
    test "people set their own; delivery reads where and when", %{org: org, saish: saish, vedant: vedant} do
      path = "/api/orgs/#{org.id}/me/notifications"
      assert signed_in(saish) |> get(path) |> json_response(200) |> get_in(["notifications", "notify_via"]) == "in_app"

      body =
        signed_in(saish)
        |> patch(path, %{
          notify_via: "whatsapp",
          phone: "+919800000000",
          digest_at: "09:30",
          quiet_from: "21:00",
          quiet_to: "08:00"
        })
        |> json_response(200)

      assert body["notifications"]["notify_via"] == "whatsapp" and body["notifications"]["quiet_from"] == "21:00:00"
      assert signed_in(saish) |> patch(path, %{phone: "98000"}) |> json_response(422)

      saish_person = Noa.Work.person_for(saish, org.id)
      assert Noa.Work.notify_target(saish_person) == {:whatsapp, "+919800000000"}
      # 17:00 UTC is 22:30 IST (quiet); 05:00 UTC is 10:30 IST (not).
      assert Noa.Work.quiet?(saish_person, ~U[2026-10-17 17:00:00Z])
      refute Noa.Work.quiet?(saish_person, ~U[2026-10-17 05:00:00Z])

      # Vedant (admin) can change Saish's; nobody changes theirs through someone else's path.
      assert {:ok, _} = Noa.Work.set_notifications(saish_person.id, %{notify_via: :email}, vedant)
    end

    test "a member can't change someone else's", %{org: org, saish: saish, vedant: vedant} do
      vedant_person = Noa.Work.person_for(vedant, org.id)

      assert {:error, %Ash.Error.Forbidden{}} =
               Noa.Work.set_notifications(vedant_person.id, %{notify_via: :email}, saish)
    end
  end

  describe "agent pack (3.18)" do
    test "Soha's Emmarie pack: CLAUDE.md, AGENTS.md, tasks.md and brief.md, no secrets", %{org: org, vedant: vedant} do
      dir = signed_in(vedant) |> get("/api/orgs/#{org.id}/directory") |> json_response(200)
      key = fn list, k -> Enum.find(dir[list], &(&1["key"] == k)) end
      {soha, emmarie} = {key.("people", "so"), key.("projects", "emmarie")}

      pack =
        signed_in(vedant)
        |> get("/api/orgs/#{org.id}/projects/#{emmarie["id"]}/pack?person_id=#{soha["id"]}")
        |> json_response(200)

      files = Map.new(pack["files"], &{&1["path"], &1["content"]})
      assert Map.keys(files) |> Enum.sort() == [".mcp.json", "AGENTS.md", "CLAUDE.md", "brief.md", "tasks.md"]
      assert files[".mcp.json"] =~ "/mcp" and files[".mcp.json"] =~ "${NOA_TOKEN}"
      assert files["CLAUDE.md"] =~ "# Emmarie" and files["CLAUDE.md"] =~ "Lead: Vedant"
      assert files["CLAUDE.md"] =~ "Never commit secrets"
      assert files["tasks.md"] =~ "Yours, Soha" and files["tasks.md"] =~ "Motion-test queue fix"
      assert pack["person"]["name"] == "Soha"
      assert Enum.any?(pack["steps"], &(&1["label"] =~ "Meet Vedant"))
      refute files["CLAUDE.md"] =~ ~r/password|api[_ ]key|secret_key/i
    end
  end

  test "the notification feed shows what waits on you and what changed around you", %{
    org: org,
    vedant: vedant,
    saish: saish
  } do
    lead = signed_in(vedant) |> get("/api/orgs/#{org.id}/feed") |> json_response(200)

    assert Enum.any?(
             lead["items"],
             &(&1["kind"] == "approval" and &1["text"] =~ "Waiting on you: Board report PDF export")
           )

    # Vedant moves one of Saish's tasks; Saish hears about it.
    task =
      Noa.Work.Task
      |> Ash.read!(authorize?: false)
      |> Enum.find(&(&1.org_id == org.id and &1.title == "Report share links"))

    {:ok, _} = Noa.Work.update_task(task.id, %{status: :blocked}, vedant)

    member = signed_in(saish) |> get("/api/orgs/#{org.id}/feed") |> json_response(200)
    assert Enum.any?(member["items"], &(&1["text"] == ~s(Vedant changed the status of "Report share links")))
    # Saish only sees proposals about himself.
    refute Enum.any?(member["items"], &(&1["text"] =~ "Prompt plan review"))
  end
end
