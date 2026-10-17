defmodule Noa.Packs do
  @moduledoc """
  Agent packs (3.18): the files someone joining a project hands their coding agent, and
  their own day-one checklist, generated from the project's subgraph in FalkorDB.

  - `CLAUDE.md` and `AGENTS.md`: what the project is, who leads it and who knows it,
    where the talk happens, what was decided and why (with sources), where work stands.
  - `tasks.md`: the person's open tasks first, then the rest of the project's open work.
  - `brief.md`: the KT brief for non-developer roles (`Noa.Work.Brief`, 3.19).
  - `.mcp.json`: connects the agent to Noa's MCP server (3.6) for live context. It holds
    the address only; the person's token comes from `NOA_TOKEN`.

  Generated on request from the live graph, so a pack is always current. Secrets never
  go in these files. When the graph is down the same files come from Postgres.
  """
  alias Noa.Graph
  alias Noa.Work

  @doc "Builds the pack. Returns `{:ok, %{project, person, store, files: [%{path, content}], steps}}`."
  def build(org_id, project_id, actor, person_id \\ nil) do
    with {:ok, project} <- Ash.get(Work.Project, project_id, actor: actor, load: [:lead]),
         {:ok, data} <- data(org_id, project, actor),
         {:ok, brief} <- Work.brief(org_id, project_id, actor, person_id) do
      # The person may not be on the project yet (the pack is for joining it).
      person = person_id && Ash.get!(Work.Person, person_id, actor: actor)
      name = person && person.name
      agents = agents_md(project, data)

      {:ok,
       %{
         project: %{id: project.id, key: project.key, name: project.name},
         person: person && %{id: person.id, name: person.name},
         store: data.store,
         files: [
           %{path: "CLAUDE.md", content: agents},
           %{path: "AGENTS.md", content: agents},
           %{path: "tasks.md", content: tasks_md(project, data, person_id, name)},
           %{path: ".mcp.json", content: mcp_json()},
           %{path: "brief.md", content: Work.Brief.markdown(brief, project.name, name)}
         ],
         steps: steps(project, data, person_id)
       }}
    end
  end

  ## Data: the graph first

  defp data(org_id, project, actor) do
    case graph_data(org_id, project.id) do
      {:ok, data} -> {:ok, Map.put(data, :store, "falkordb")}
      _ -> postgres_data(org_id, project, actor)
    end
  end

  defp graph_data(org_id, id) do
    Noa.Graph.Experts.refresh(org_id)
    p = %{id: id}

    with {:ok, [_ | _]} <- Graph.ro_query(org_id, "MATCH (p:Project {id: $id}) RETURN p.id AS id", p),
         {:ok, people} <-
           Graph.ro_query(
             org_id,
             """
             MATCH (x:Person)-[r:WORKS_ON|LEADS|KNOWS_ABOUT]->(:Project {id: $id})
             RETURN x.id AS id, x.name AS name, x.title AS title,
                    max(CASE WHEN type(r) = 'WORKS_ON' AND r.to IS NULL THEN r.percent END) AS percent,
                    max(CASE WHEN type(r) = 'KNOWS_ABOUT' THEN r.weight END) AS weight
             """,
             p
           ),
         {:ok, tasks} <-
           Graph.ro_query(
             org_id,
             """
             MATCH (t:Task)-[:BELONGS_TO]->(:Project {id: $id}) WHERE t.status <> 'done'
             OPTIONAL MATCH (t)-[:ASSIGNED_TO]->(o:Person)
             OPTIONAL MATCH (t)-[:EXTRACTED_FROM]->(e:Episode)
             RETURN t.title AS title, t.status AS status, t.due AS due, t.blocked_reason AS blocked,
                    o.id AS owner_id, o.name AS owner, coalesce(t.src_quote, e.text) AS quote,
                    coalesce(t.src_channel, '') AS channel
             ORDER BY coalesce(t.due, '9999')
             """,
             p
           ),
         {:ok, decisions} <-
           Graph.ro_query(
             org_id,
             """
             MATCH (d:Decision {status: 'active'})-[:AFFECTS]->(:Project {id: $id})
             OPTIONAL MATCH (x:Person)-[:DECIDED]->(d)
             OPTIONAL MATCH (d)-[:EXTRACTED_FROM]->(e:Episode)
             RETURN d.statement AS statement, d.at AS at, x.name AS by, coalesce(d.src_quote, e.text) AS quote,
                    coalesce(d.src_channel, '') AS channel
             ORDER BY d.at DESC
             """,
             p
           ),
         {:ok, channels} <-
           Graph.ro_query(org_id, "MATCH (c:Channel)-[:MAPS_TO]->(:Project {id: $id}) RETURN c.name AS name", p) do
      {:ok,
       %{
         people:
           Enum.map(
             people,
             &%{id: &1["id"], name: &1["name"], title: &1["title"], percent: &1["percent"], weight: &1["weight"]}
           ),
         tasks: Enum.map(tasks, &task_row/1),
         decisions:
           Enum.map(
             decisions,
             &%{statement: &1["statement"], at: &1["at"], by: &1["by"], quote: &1["quote"], channel: &1["channel"]}
           ),
         channels: Enum.map(channels, & &1["name"])
       }}
    else
      {:ok, []} -> {:error, :graph_not_built}
      error -> error
    end
  end

  defp task_row(r) do
    %{
      title: r["title"],
      status: r["status"],
      due: r["due"],
      blocked: r["blocked"],
      owner_id: r["owner_id"],
      owner: r["owner"],
      quote: r["quote"],
      channel: r["channel"]
    }
  end

  defp postgres_data(org_id, project, actor) do
    with {:ok, people} <- Work.people(org_id, actor),
         {:ok, tasks} <- Work.tasks(org_id, actor, project_id: project.id, open: true),
         {:ok, decisions} <- Work.decisions(org_id, actor, project_id: project.id, status: :active),
         {:ok, channels} <- Work.channels(org_id, actor) do
      on =
        Enum.filter(people, fn x ->
          Enum.any?(x.allocations, &(&1.project_id == project.id)) or x.id == project.lead_id
        end)

      name = Map.new(people, &{&1.id, &1.name})

      {:ok,
       %{
         store: "postgres",
         people:
           Enum.map(on, fn x ->
             %{
               id: x.id,
               name: x.name,
               title: x.title,
               percent: Enum.find_value(x.allocations, &(&1.project_id == project.id && &1.percent)),
               weight: nil
             }
           end),
         tasks:
           Enum.map(tasks, fn t ->
             %{
               title: t.title,
               status: to_string(t.status),
               due: t.due_on && Date.to_iso8601(t.due_on),
               blocked: t.blocked_reason,
               owner_id: t.owner_id,
               owner: name[t.owner_id],
               quote: t.source && t.source["quote"],
               channel: (t.source && t.source["channel"]) || ""
             }
           end),
         decisions:
           Enum.map(decisions, fn d ->
             %{
               statement: d.statement,
               at: DateTime.to_iso8601(d.inserted_at),
               by: name[d.made_by_id],
               quote: d.source && d.source["quote"],
               channel: (d.source && d.source["channel"]) || ""
             }
           end),
         channels: channels |> Enum.filter(&(&1.project_id == project.id)) |> Enum.map(& &1.name)
       }}
    end
  end

  ## Files

  defp agents_md(project, data) do
    lead = project.lead && project.lead.name
    experts = data.people |> Enum.filter(& &1.weight) |> Enum.sort_by(&(-&1.weight)) |> Enum.take(4)
    on = Enum.filter(data.people, & &1.percent)

    sections = [
      "# #{project.name}\n\n#{project.about || "No description yet."}",
      section("Where things are", [
        project.repo && "Repo: `#{project.repo}`",
        lead && "Lead: #{lead}",
        data.channels != [] && "Talk: #{Enum.join(data.channels, ", ")} (Noa reads these)"
      ]),
      section("People", Enum.map(on, &"#{&1.name}#{&1.title && ", #{&1.title}"} (#{&1.percent}%)")),
      section(
        "Who knows it best",
        Enum.map(experts, &"#{&1.name}: weight #{&1.weight} from finished tasks, decisions and messages")
      ),
      section("Decided, and why", Enum.map(Enum.take(data.decisions, 8), &decision_line/1)),
      section("Where work stands", status_lines(data.tasks)),
      section("How to work here", [
        "Open tasks live in `tasks.md` and on the Noa board; Noa keeps both current from chat.",
        "Deadline and scope changes go to the lead for approval; status changes apply at once.",
        "Ask `@noa` in #{List.first(data.channels) || "the team channel"} or the web app for anything not here; answers cite their sources.",
        "For live context, connect your agent to Noa's MCP server (`.mcp.json`; create your token on the Agent pack page). Tools: `project_context`, `my_tasks`, `ask`, `who_knows`, `how_connected`, `decisions`, `update_task_status`.",
        "Never commit secrets. Ask the lead for one-time access instead."
      ])
    ]

    Enum.reject(sections, &is_nil/1) |> Enum.join("\n\n") |> Kernel.<>("\n\n" <> footer())
  end

  defp tasks_md(project, data, person_id, name) do
    mine = Enum.filter(data.tasks, &(person_id && &1.owner_id == person_id))
    rest = data.tasks -- mine

    by_status =
      for {status, label} <- [{"blocked", "Blocked"}, {"in_progress", "In progress"}, {"todo", "To do"}],
          items = Enum.filter(rest, &(&1.status == status)),
          items != [] do
        section(label, Enum.map(items, &task_line(&1, true)))
      end

    [
      "# #{project.name} tasks",
      person_id &&
        section(
          "Yours, #{name}",
          if(mine == [],
            do: ["Nothing assigned yet. Ask the lead where to start."],
            else: Enum.map(mine, &task_line(&1, false))
          )
        ),
      by_status
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
    |> Kernel.<>("\n\n" <> footer())
  end

  defp decision_line(d) do
    by = d.by && " (#{d.by}, #{String.slice(d.at || "", 0, 10)})"
    src = d.quote && "\n  > #{d.quote}#{if d.channel != "", do: " (#{d.channel})"}"
    "#{d.statement}#{by}#{src}"
  end

  defp task_line(t, owner?) do
    meta =
      [
        owner? && t.owner && "owner #{t.owner}",
        t.due && "due #{t.due}",
        t.blocked && "blocked: #{t.blocked}"
      ]
      |> Enum.filter(& &1)

    src = t.quote && "\n  > #{t.quote}#{if t.channel != "", do: " (#{t.channel})"}"
    "[ ] #{t.title}#{if meta == [], do: "", else: " · " <> Enum.join(meta, " · ")}#{src}"
  end

  defp status_lines(tasks) do
    counts = Enum.frequencies_by(tasks, & &1.status)

    [
      "#{length(tasks)} open: #{counts["in_progress"] || 0} in progress, #{counts["todo"] || 0} to do, #{counts["blocked"] || 0} blocked"
      | tasks
        |> Enum.filter(&(&1.status == "blocked"))
        |> Enum.map(&"Blocked: #{&1.title}#{&1.blocked && " (#{&1.blocked})"}")
    ]
  end

  defp section(_title, []), do: nil

  defp section(title, items) do
    case Enum.filter(items, & &1) do
      [] -> nil
      items -> "## #{title}\n\n" <> Enum.map_join(items, "\n", &"- #{&1}")
    end
  end

  defp footer,
    do: "_Generated by Noa on #{Date.utc_today()} from the project graph. Regenerate any time; it is always current._\n"

  # The server address only; the person's token goes in by hand (created on the pack page).
  defp mcp_json do
    Jason.encode!(
      %{
        mcpServers: %{
          noa: %{
            type: "http",
            url: Application.fetch_env!(:noa, :api_base_url) <> "/mcp",
            headers: %{Authorization: "Bearer ${NOA_TOKEN}"}
          }
        }
      },
      pretty: true
    ) <> "\n"
  end

  ## Day-one checklist

  defp steps(project, data, person_id) do
    mine = Enum.find(data.tasks, &(person_id && &1.owner_id == person_id))
    lead = project.lead && project.lead.name

    [
      %{label: "Read the KT brief", kind: "brief"},
      project.repo && %{label: "Get access to #{project.repo}", kind: "access"},
      data.channels != [] && %{label: "Join #{Enum.join(data.channels, ", ")}", kind: "access"},
      %{label: "Add CLAUDE.md (or AGENTS.md) and tasks.md to your agent's workspace", kind: "pack"},
      %{label: "Connect your agent to Noa (MCP)", kind: "mcp"},
      lead && %{label: "Meet #{lead}, your lead", kind: "people"},
      mine && %{label: "First task: #{mine.title}", kind: "task"}
    ]
    |> Enum.filter(& &1)
  end
end
