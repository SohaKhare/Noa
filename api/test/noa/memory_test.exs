defmodule Noa.MemoryTest do
  @moduledoc """
  Shared memory under concurrent writers (Track 02): people, chat ingest and agents
  write at once. The event log keeps one order with no gaps or duplicates, redelivered
  messages are recorded once, conflicting edits all leave change records, and the graph
  rebuilt from the log agrees with Postgres. Graph checks need FalkorDB.

  The test sandbox shares one database connection, so the database sees the writes one
  after another; what this exercises is Noa's own code under concurrent callers.
  """
  use NoaWeb.ConnCase, async: false
  use Oban.Testing, repo: Noa.Repo

  alias Noa.{Events, Graph, Work}
  alias Noa.Graph.Projector

  @seed Path.expand("../../../docs/seeds/nyi.json", __DIR__) |> File.read!() |> Jason.decode!()

  setup do
    root = superadmin!()
    {:ok, org} = Noa.Orgs.create_org(%{name: "NotYourIdea", allowed_domains: ["notyouridea.com"]}, root)
    {:ok, _, url} = Noa.Orgs.invite(org, "vedant@notyouridea.com", :org_admin, root)
    vedant = accept!(url, "Vedant")
    {:ok, _} = Work.load_seed(org.id, @seed)
    {:ok, projects} = Work.projects(org.id, vedant)
    %{org: org, vedant: vedant, veriq: Enum.find(projects, &(&1.key == "veriq"))}
  end

  defp message(i),
    do: %{
      platform: :discord,
      channel: "veriq",
      channel_id: "c1",
      message_id: "m#{i}",
      author_id: "u-saish",
      author: "saish",
      text: "update #{i}"
    }

  defp concurrently(funs),
    do: funs |> Task.async_stream(& &1.(), max_concurrency: 16, timeout: 30_000) |> Enum.map(fn {:ok, r} -> r end)

  test "concurrent writers keep one order, record redeliveries once, and log every edit", ctx do
    %{org: org, vedant: vedant, veriq: veriq} = ctx
    before = Events.since(0, org_id: org.id, limit: 100_000) |> length()

    # 40 chat messages, each delivered twice (webhooks and gateways repeat), plus 20 tasks created by people.
    results =
      concurrently(
        for(i <- 1..40, _ <- 1..2, do: fn -> Work.record_message(org.id, message(i)) end) ++
          for(i <- 1..20, do: fn -> Work.create_task(org.id, %{title: "Task #{i}", project_id: veriq.id}, vedant) end)
      )

    assert Enum.count(results, &match?({:duplicate, _}, &1)) == 40

    # Then everyone edits the same task at once: status, owner and title from different writers.
    {:ok, task} = Work.create_task(org.id, %{title: "Shared task", project_id: veriq.id}, vedant)
    {:ok, people} = Work.people(org.id, vedant)

    edits =
      for {p, i} <- Enum.with_index(people) do
        fn -> Work.update_task(task.id, %{owner_id: p.id, title: "Shared task v#{i}"}, vedant) end
      end ++
        for(
          s <- [:in_progress, :blocked, :in_progress, :done],
          do: fn -> Work.update_task(task.id, %{status: s}, vedant) end
        )

    assert Enum.all?(concurrently(edits), &match?({:ok, _}, &1))

    events = Events.since(0, org_id: org.id, limit: 100_000)
    ids = Enum.map(events, & &1.id)
    assert ids == Enum.sort(ids) and ids == Enum.uniq(ids)
    assert Enum.count(events, &(&1.type == "message.received")) == 40
    assert length(events) - before >= 40 + 20 + 1 + length(edits)

    # Every edit is in the task's history, and the last snapshot is the task as it stands.
    {:ok, changes} = Work.changes(org.id, vedant, task_id: task.id)
    assert length(changes) >= length(people)
    last = events |> Enum.filter(&(&1.type == "task.saved" and &1.data["id"] == task.id)) |> List.last()
    now = Ash.get!(Work.Task, task.id, authorize?: false)

    assert last.data["owner_id"] == now.owner_id and last.data["title"] == now.title and
             last.data["status"] == to_string(now.status)
  end

  @tag :graph
  test "the graph rebuilt from the log agrees with Postgres after concurrent writes", ctx do
    %{org: org, vedant: vedant, veriq: veriq} = ctx
    on_exit(fn -> Graph.drop(org.id) end)

    concurrently(
      for(i <- 1..30, _ <- 1..2, do: fn -> Work.record_message(org.id, message(i)) end) ++
        for(i <- 1..15, do: fn -> Work.create_task(org.id, %{title: "Task #{i}", project_id: veriq.id}, vedant) end)
    )

    {:ok, _} = Projector.rebuild(org.id)

    {:ok, [%{"n" => episodes}]} = Graph.ro_query(org.id, "MATCH (e:Episode) RETURN count(e) AS n")

    {:ok, [%{"n" => tasks}]} =
      Graph.ro_query(org.id, "MATCH (t:Task)-[:BELONGS_TO]->(:Project {key: 'veriq'}) RETURN count(t) AS n")

    assert episodes == 30
    assert tasks == length(Work.tasks(org.id, vedant, project_id: veriq.id) |> elem(1))

    # Replaying again changes nothing: unique constraints and MERGE make it idempotent.
    for e <- Events.since(0, org_id: org.id, limit: 100_000), do: :ok = Projector.project(e)
    {:ok, [%{"n" => again}]} = Graph.ro_query(org.id, "MATCH (e:Episode) RETURN count(e) AS n")
    assert again == 30
  end
end
