defmodule Noa.EventsTest do
  @moduledoc """
  The event log (1.8), identity (1.11) and the graph projector (1.10) on the NYI seed.
  Tests tagged :graph need FalkorDB (`docker compose --profile graph up -d`) and are
  skipped without it.
  """
  use NoaWeb.ConnCase, async: false
  use Oban.Testing, repo: Noa.Repo

  alias Noa.{Events, Graph, Work}
  alias Noa.Graph.Projector

  @seed Path.expand("../../../docs/seeds/nyi.json", __DIR__) |> File.read!() |> Jason.decode!()

  setup do
    root = superadmin!()
    {:ok, org} = Noa.Orgs.create_org(%{name: "NotYourIdea", allowed_domains: ["notyouridea.com"]}, root)
    {:ok, _, lead_url} = Noa.Orgs.invite(org, "vedant@notyouridea.com", :org_admin, root)
    vedant = accept!(lead_url, "Vedant")
    {:ok, _} = Work.load_seed(org.id, @seed)
    %{org: org, vedant: vedant}
  end

  defp types(org), do: Events.since(0, org_id: org.id, limit: 1000) |> Enum.map(& &1.type)

  defp message(attrs \\ %{}) do
    Map.merge(
      %{
        platform: :discord,
        channel: "veriq",
        channel_id: "c1",
        message_id: "m1",
        author_id: "u-saish",
        author: "saish",
        text: "on it, Board report PDF export by Friday",
        at: ~U[2026-10-16 10:42:00Z]
      },
      attrs
    )
  end

  test "every write to work appends an event with a snapshot", %{org: org, vedant: vedant} do
    seen = Enum.frequencies(types(org))
    assert seen["project.saved"] == 4 and seen["channel.saved"] == 7 and seen["alias.saved"] == 8
    # Five people, then Vedant linked to his account.
    assert seen["person.saved"] == 6

    veriq = Enum.find(Work.projects(org.id, vedant) |> elem(1), &(&1.key == "veriq"))
    {:ok, task} = Work.create_task(org.id, %{title: "Score weights v2", project_id: veriq.id}, vedant)
    {:ok, _} = Work.update_task(task.id, %{status: :done}, vedant)

    [created, done] = Events.history(org.id, task.id)
    assert created.type == "task.saved" and created.actor_id == vedant.id
    assert created.data["title"] == "Score weights v2" and created.data["project_id"] == veriq.id
    assert done.data["status"] == "done" and done.data["done_at"]
  end

  test "a failed write appends nothing", %{org: org, vedant: vedant} do
    before = length(types(org))
    assert {:error, _} = Work.create_task(org.id, %{title: "No project"}, vedant)
    assert length(types(org)) == before
  end

  test "a chat message is recorded once and its author resolved through their handles", %{org: org} do
    assert {:ok, event} = Work.record_message(org.id, message())
    assert event.type == "message.received" and event.key == "discord:m1"
    assert event.data["channel"] == "#veriq" and event.data["project_id"]

    saish = Noa.Work.Person |> Ash.read!(authorize?: false) |> Enum.find(&(&1.org_id == org.id and &1.key == "sa"))
    assert event.data["person_id"] == saish.id

    # Delivered again: stored once.
    assert {:duplicate, same} = Work.record_message(org.id, message())
    assert same.id == event.id

    # The account is remembered, so a new display name still resolves.
    {:ok, again} = Work.record_message(org.id, message(%{message_id: "m2", author: "Saish K"}))
    assert again.data["person_id"] == saish.id and again.data["identity_id"] == event.data["identity_id"]
  end

  test "unknown authors are kept for an admin to link; unread channels are refused", %{org: org} do
    {:ok, event} = Work.record_message(org.id, message(%{author_id: "u-x", author: "stranger"}))
    assert event.data["person_id"] == nil and event.data["identity_id"]

    assert {:error, :not_read} = Work.record_message(org.id, message(%{channel: "random", channel_id: "c9"}))
    assert {:error, :not_read} = Work.record_message(org.id, message(%{channel: "dm-with-noa", channel_id: "c8"}))
  end

  test "new messages are extracted per channel into Inbox proposals, once", %{org: org, vedant: vedant} do
    on_exit(fn -> Application.put_env(:noa, Noa.Extraction, Keyword.delete(config(), :respond)) end)
    seen = self()

    Application.put_env(
      :noa,
      Noa.Extraction,
      Keyword.put(config(), :respond, fn window ->
        send(seen, {:window, Enum.map(window.context, & &1.body), Enum.map(window.lines, & &1.body)})
        [ask, reply | _] = Enum.map(window.lines, & &1.seq) ++ [nil, nil]

        tasks =
          if reply,
            do: [
              %{
                "title" => "Board report PDF export",
                "owner" => "Saish",
                "due" => Date.to_iso8601(Date.add(window.date, 1)),
                "detail" => nil,
                "project" => "veriq",
                "evidence_sequences" => [ask, reply],
                "confidence" => 0.9
              }
            ],
            else: []

        %{"tasks" => tasks, "status_changes" => [], "deadline_changes" => [], "decisions" => [], "scope_changes" => []}
      end)
    )

    {:ok, ask} =
      Work.record_message(
        org.id,
        message(%{
          message_id: "m0",
          author_id: "u-ve",
          author: "Vedant",
          text: "who can take the Board report PDF export?"
        })
      )

    {:ok, _} = Work.record_message(org.id, message())
    channel_id = ask.data["channel_id"]
    assert_enqueued(worker: Noa.Work.Extract, args: %{org_id: org.id, channel_id: channel_id})
    assert [_] = all_enqueued(worker: Noa.Work.Extract)

    assert {:ok, 1} =
             perform_job(Noa.Work.Extract, %{org_id: org.id, channel_id: channel_id})

    assert_received {:window, [], [_, _]}

    {:ok, [p]} = Work.proposals(org.id, vedant)
    assert p.summary == "Board report PDF export" and p.project.key == "veriq" and p.owner.name == "Saish"
    # Cites the first message of its evidence: Vedant's question.
    assert p.source["episode_id"] == "discord:m0" and p.source["author"] == "Vedant"

    # Nothing new: no model call, no new proposal.
    assert {:ok, 0} = Noa.Work.Extract.run(org.id, channel_id)
    refute_received {:window, _, _}

    # The next message is extracted alone, with the earlier ones as context.
    {:ok, _} = Work.record_message(org.id, message(%{message_id: "m3", text: "PDF export is in review"}))
    assert {:ok, 0} = Noa.Work.Extract.run(org.id, channel_id)
    assert_received {:window, [_, _], ["PDF export is in review"]}
  end

  defp config, do: Application.get_env(:noa, Noa.Extraction, [])

  test "statements cover every work event type" do
    for type <- ~w(person.saved project.saved alias.saved alias.deleted allocation.saved channel.saved
                   identity.saved task.saved message.received task.deleted) do
      assert [_ | _] = Projector.statements(%{type: type, data: %{"id" => "x", "episode_id" => "e"}}), type
    end

    assert Projector.statements(%{type: "proposal.saved", data: %{}}) == []
  end

  @tag :graph
  test "the projector mirrors the log into the org's graph and rebuilds it", %{org: org, vedant: vedant} do
    on_exit(fn -> Graph.drop(org.id) end)
    :ok = Graph.bootstrap(org.id)

    veriq = Enum.find(Work.projects(org.id, vedant) |> elem(1), &(&1.key == "veriq"))
    saish = Noa.Work.Person |> Ash.read!(authorize?: false) |> Enum.find(&(&1.org_id == org.id and &1.key == "sa"))
    {:ok, msg} = Work.record_message(org.id, message())

    {:ok, _} =
      Work.create_task(
        org.id,
        %{
          title: "Board report PDF export",
          project_id: veriq.id,
          owner_id: saish.id,
          source: %{"episode_id" => "discord:m1"}
        },
        vedant
      )

    for event <- Events.since(0, org_id: org.id, limit: 1000), do: assert(:ok = Projector.project(event), event.type)

    {:ok, [row]} =
      Graph.ro_query(
        org.id,
        """
        MATCH (p:Person {name: 'Saish'})-[:AUTHORED]->(e:Episode)<-[:EXTRACTED_FROM]-(t:Task)-[:BELONGS_TO]->(:Project {key: 'veriq'})
        MATCH (t)-[:ASSIGNED_TO]->(p)
        MATCH (e)-[:IN]->(:Channel)-[:MAPS_TO]->(pr:Project)
        RETURN t.title AS task, e.text AS said, pr.name AS project
        """
      )

    assert row == %{"task" => "Board report PDF export", "said" => msg.data["text"], "project" => "Veriq"}

    {:ok, [%{"n" => works_on}]} =
      Graph.ro_query(org.id, "MATCH (:Person)-[w:WORKS_ON]->(:Project) RETURN count(w) AS n")

    assert works_on ==
             length(Noa.Work.Allocation |> Ash.read!(authorize?: false) |> Enum.filter(&(&1.org_id == org.id)))

    {:ok, [%{"lead" => "Vedant"}]} =
      Graph.ro_query(org.id, "MATCH (l:Person)-[:LEADS]->(:Project {key: 'veriq'}) RETURN l.name AS lead")

    {:ok, [%{"aliases" => aliases}]} =
      Graph.ro_query(org.id, "MATCH (p:Project {key: 'veriq'}) RETURN p.aliases AS aliases")

    assert "reports" in aliases

    # Replaying twice changes nothing; a rebuild from the log gives the same graph.
    count = fn -> Graph.ro_query(org.id, "MATCH (n) RETURN count(n) AS n") |> elem(1) |> hd() end
    before = count.()
    for event <- Events.since(0, org_id: org.id, limit: 1000), do: :ok = Projector.project(event)
    assert count.() == before
    assert {:ok, _} = Projector.rebuild(org.id)
    assert count.() == before
  end
end
