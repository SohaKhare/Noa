defmodule Noa.LoadTest do
  @moduledoc """
  Load test (4.2), excluded by default: `mix test --only load test/load_test.exs`.
  NYI-sized history on the NYI seed: 3,000 chat messages and 400 tasks over four
  projects, then the timings that matter for the demo. Prints a table for docs/load.md.
  Needs FalkorDB for the graph rows.
  """
  use NoaWeb.ConnCase, async: false

  @moduletag :load
  @moduletag timeout: 600_000

  @seed Path.expand("../../docs/seeds/nyi.json", __DIR__) |> File.read!() |> Jason.decode!()
  @words ~w(report pdf export score weights storyboard motion queue reels hooks caption share links brand logo prompt plan review deploy fix layout eval)

  defp ms(fun) do
    {us, result} = :timer.tc(fun)
    {Float.round(us / 1000, 1), result}
  end

  defp median(fun, n) do
    times = for _ <- 1..n, do: elem(ms(fun), 0)
    Enum.at(Enum.sort(times), div(n, 2))
  end

  test "NYI-sized history" do
    root = superadmin!()
    {:ok, org} = Noa.Orgs.create_org(%{name: "Load", allowed_domains: ["notyouridea.com"]}, root)
    {:ok, _, url} = Noa.Orgs.invite(org, "vedant@notyouridea.com", :org_admin, root)
    vedant = accept!(url, "Vedant")
    {:ok, _} = Noa.Work.load_seed(org.id, @seed)
    {:ok, projects} = Noa.Work.projects(org.id, vedant)
    {:ok, people} = Noa.Work.people(org.id, vedant)
    channels = ~w(veriq emmarie tulpa video-break)
    phrase = fn i -> Enum.map_join(0..4, " ", &Enum.at(@words, rem(i * 7 + &1 * 3, length(@words)))) end

    {tasks_ms, _} =
      ms(fn ->
        for i <- 1..400 do
          p = Enum.at(projects, rem(i, length(projects)))
          o = Enum.at(people, rem(i, length(people)))
          status = Enum.at([:todo, :in_progress, :blocked, :done], rem(i, 4))

          {:ok, _} =
            Noa.Work.create_task(
              org.id,
              %{
                title: "#{phrase.(i)} #{i}",
                project_id: p.id,
                owner_id: o.id,
                status: status,
                due_on: Date.add(Date.utc_today(), rem(i, 21) - 7)
              },
              vedant
            )
        end
      end)

    {messages_ms, _} =
      ms(fn ->
        for i <- 1..3000 do
          {:ok, _} =
            Noa.Work.record_message(org.id, %{
              platform: :discord,
              channel: Enum.at(channels, rem(i, 4)),
              message_id: "load-#{i}",
              author_id: "u#{rem(i, 5)}",
              author: Enum.at(people, rem(i, length(people))).name,
              text: "#{phrase.(i)} by friday?",
              at: DateTime.add(DateTime.utc_now(), -i * 60, :second)
            })
        end
      end)

    events = length(Noa.Events.since(0, org_id: org.id, limit: 100_000))

    graph_ms =
      if Noa.Graph.enabled?() and match?(:ok, Noa.Graph.bootstrap(org.id)) do
        on_exit(fn -> Noa.Graph.drop(org.id) end)
        {t, {:ok, _}} = ms(fn -> Noa.Graph.Projector.rebuild(org.id) end)
        t
      end

    veriq = Enum.find(projects, &(&1.key == "veriq"))
    conn = signed_in(vedant)

    rows = [
      {"Create 400 tasks (with event log)", "#{tasks_ms} ms total, #{Float.round(tasks_ms / 400, 2)} ms each"},
      {"Record 3,000 messages (dedupe, identity, event, job)",
       "#{messages_ms} ms total, #{Float.round(messages_ms / 3000, 2)} ms each"},
      {"Events in the log", "#{events}"},
      {"Rebuild the graph from the log",
       if(graph_ms,
         do: "#{graph_ms} ms (#{Float.round(events / (graph_ms / 1000), 0)} events/s)",
         else: "skipped, no FalkorDB"
       )},
      {"GET /directory (median of 10)", "#{median(fn -> get(conn, "/api/orgs/#{org.id}/directory") end, 10)} ms"},
      {"GET /tasks?project_id (median of 10)",
       "#{median(fn -> get(conn, "/api/orgs/#{org.id}/tasks?project_id=#{veriq.id}") end, 10)} ms"},
      {"POST /ask \"what's blocking Veriq?\" (median of 10)",
       "#{median(fn -> post(conn, "/api/orgs/#{org.id}/ask", %{question: "what's blocking Veriq?"}) end, 10)} ms"},
      {"GET /projects/:id/brief (median of 5)",
       "#{median(fn -> get(conn, "/api/orgs/#{org.id}/projects/#{veriq.id}/brief") end, 5)} ms"},
      {"GET /experts?project_id (median of 5)",
       "#{median(fn -> get(conn, "/api/orgs/#{org.id}/experts?project_id=#{veriq.id}") end, 5)} ms"}
    ]

    IO.puts("\n| Step | Result |\n| --- | --- |")
    for {k, v} <- rows, do: IO.puts("| #{k} | #{v} |")

    assert events >= 3400
  end
end
