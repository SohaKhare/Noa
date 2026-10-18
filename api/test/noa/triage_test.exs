defmodule Noa.TriageTest do
  @moduledoc """
  The triage agent (3.24): finds work nobody is carrying, ranks owners from the graph,
  files assignment proposals, and approving one changes the owner under the lead rules.
  Tests tagged :graph need FalkorDB.
  """
  use NoaWeb.ConnCase, async: false
  use Oban.Testing, repo: Noa.Repo

  alias Noa.{Events, Graph, Work}
  alias Noa.Agent.Triage
  alias Noa.Graph.Projector

  @seed Path.expand("../../../docs/seeds/nyi.json", __DIR__) |> File.read!() |> Jason.decode!()
  @sample Path.expand("../../../docs/seeds/nyi-sample-work.json", __DIR__) |> File.read!() |> Jason.decode!()

  setup do
    root = superadmin!()
    {:ok, org} = Noa.Orgs.create_org(%{name: "NotYourIdea", allowed_domains: ["notyouridea.com"]}, root)
    {:ok, _, url} = Noa.Orgs.invite(org, "vedant@notyouridea.com", :org_admin, root)
    vedant = accept!(url, "Vedant")
    {:ok, _, url} = Noa.Orgs.invite(org, "saish@notyouridea.com", :member, vedant)
    saish = accept!(url, "Saish")
    {:ok, _} = Work.load_seed(org.id, @seed)
    {:ok, _} = Work.Seed.load_sample(org.id, @sample)

    {:ok, projects} = Work.projects(org.id, vedant)
    project = &Enum.find(projects, fn p -> p.key == &1 end)
    person = &Enum.find(Work.people(org.id, vedant) |> elem(1), fn p -> p.name == &1 end)

    %{org: org, vedant: vedant, saish: saish, project: project, person: person}
  end

  defp unowned!(org, project, vedant, title) do
    {:ok, task} = Work.create_task(org.id, %{title: title, project_id: project.id}, vedant)
    task
  end

  test "files a proposal for unowned work and for tasks whose owner left the project", ctx do
    %{org: org, vedant: vedant, project: project} = ctx
    veriq = project.("veriq")
    task = unowned!(org, veriq, vedant, "Board report PDF export")

    assert {:ok, %{filed: filed}} = Triage.run(org.id, vedant, project_id: veriq.id)

    by_task = Map.new(filed, &{&1.task_id, &1})
    p = by_task[task.id]
    assert p.kind == :assignment and p.project_id == veriq.id
    assert p.data["trigger"] == "unowned"
    assert p.owner_id in [ctx.person.("Saish").id, ctx.person.("Vedant").id]
    assert [_ | _] = p.data["why"]
    assert [_ | _] = p.data["graph_route"]

    # Soha owns "Prompt plan review" on Veriq but isn't allocated to it.
    moved = Enum.find(filed, &(&1.data["title"] == "Prompt plan review"))
    assert moved.data["trigger"] == "moved" and moved.data["from_owner_id"] == ctx.person.("Soha").id
    refute moved.owner_id == ctx.person.("Soha").id

    # Running again files nothing new while those wait.
    assert {:ok, %{filed: []}} = Triage.run(org.id, vedant, project_id: veriq.id)
  end

  test "approving an assignment changes the owner and records the change", ctx do
    %{org: org, vedant: vedant, project: project} = ctx
    task = unowned!(org, project.("veriq"), vedant, "Board report PDF export")
    {:ok, %{filed: filed}} = Triage.run(org.id, vedant, project_id: project.("veriq").id)
    p = Enum.find(filed, &(&1.task_id == task.id))

    saish = ctx.person.("Saish")
    assert {:ok, approved} = Work.approve(p.id, %{owner_id: saish.id}, vedant)
    assert approved.status == :approved and approved.task.owner_id == saish.id

    {:ok, [change]} = Work.changes(org.id, vedant, task_id: task.id)
    assert change.kind == :owner and change.status == :applied and change.new_value == saish.id
    assert Enum.any?(Events.history(org.id, task.id), &(&1.data["owner_id"] == saish.id))
  end

  test "members run it only for the projects they lead", ctx do
    %{org: org, saish: saish, project: project} = ctx
    assert {:error, :not_a_project_lead} = Triage.run(org.id, saish, project_id: project.("veriq").id)

    # Saish leads Tulpa.
    assert {:ok, %{filed: filed}} = Triage.run(org.id, saish)
    assert Enum.all?(filed, &(&1.project_id == project.("tulpa").id))
  end

  test "the API files proposals and suggests owners", ctx do
    %{org: org, vedant: vedant, saish: saish, project: project} = ctx
    task = unowned!(org, project.("veriq"), vedant, "Board report PDF export")

    owners =
      signed_in(vedant)
      |> get("/api/orgs/#{org.id}/tasks/#{task.id}/owners")
      |> json_response(200)
      |> Map.fetch!("owners")

    assert [%{"name" => _, "why" => [_ | _], "route" => [_ | _]} | _] = owners

    filed =
      signed_in(vedant)
      |> post("/api/orgs/#{org.id}/triage", %{project_id: project.("veriq").id})
      |> json_response(200)

    assert Enum.any?(filed["proposals"], &(&1["task_id"] == task.id and &1["kind"] == "assignment"))

    assert signed_in(saish)
           |> post("/api/orgs/#{org.id}/triage", %{project_id: project.("veriq").id})
           |> json_response(403)
  end

  @tag :graph
  test "ranks owners from the graph: knowledge, similar finished work and load", ctx do
    %{org: org, vedant: vedant, project: project} = ctx
    on_exit(fn -> Graph.drop(org.id) end)
    :ok = Graph.bootstrap(org.id)

    veriq = project.("veriq")
    saish = ctx.person.("Saish")

    {:ok, done} =
      Work.create_task(org.id, %{title: "Board report PDF layout", project_id: veriq.id, owner_id: saish.id}, vedant)

    {:ok, _} = Work.update_task(done.id, %{status: :done}, vedant)
    task = unowned!(org, veriq, vedant, "Board report PDF export")

    for event <- Events.since(0, org_id: org.id, limit: 10_000), do: :ok = Projector.project(event)

    {:ok, [best | _] = ranked} = Triage.suggest_owners(org.id, task.id, vedant)
    assert Enum.all?(ranked, & &1.graph)
    assert best.person_id == saish.id
    assert Enum.any?(best.why, &String.contains?(&1, "Board report PDF layout"))
    assert Enum.any?(best.route, &String.contains?(&1, "KNOWS_ABOUT"))
    assert Enum.any?(best.route, &String.contains?(&1, "WORKS_ON"))
  end
end
