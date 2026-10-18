defmodule Noa.Agent.Triage do
  @moduledoc """
  Noa's triage agent (3.24, Track 01: agents that act on connected data).

  It looks for open work nobody is really carrying: tasks with no owner, tasks whose
  owner has left the project, and overdue tasks on someone with too much open work.
  For each, it ranks who should take it by walking the company graph, then files an
  `:assignment` proposal in the Inbox with the reasons and the graph routes behind
  them. A lead (or the suggested person) approves it, and the owner change goes
  through the lead rules and the change log like any other edit.

  Ranking reads FalkorDB:

    * `WORKS_ON` (current allocations only): who is on the project now, and how much.
    * `KNOWS_ABOUT` weight (`Noa.Graph.Experts.refresh/1`): what they have done there.
    * Full-text over task titles, then `ASSIGNED_TO` on finished tasks: who has done
      similar work.
    * `DECIDED` then `AFFECTS`: who made a decision this task depends on.
    * `ASSIGNED_TO` from open tasks: how much they already carry.

  When the graph is not built, it falls back to allocations and load from Postgres
  and says so in each suggestion.
  """
  require Ash.Query

  alias Noa.{Graph, Work}
  alias Noa.Work.{Proposal, Task}

  @overloaded 3

  @doc """
  Finds work that needs an owner and files a proposal for each. Org admins, PMs and
  project leads (for their projects). Options: `project_id`.

  Returns `{:ok, %{filed: [proposal], checked: n}}`.
  """
  def run(org_id, actor, opts \\ []) do
    project_id = opts[:project_id]

    with :ok <- allowed(org_id, actor, project_id),
         {:ok, people} <- Work.people(org_id, actor),
         {:ok, open} <- Work.tasks(org_id, actor, open: true),
         {:ok, projects} <- Work.projects(org_id, actor) do
      projects = Map.new(projects, &{&1.id, &1})
      leads = if project_id, do: nil, else: led_projects(org_id, actor, Map.keys(projects))
      waiting = pending_task_ids(org_id)
      _ = Noa.Graph.Experts.refresh(org_id)

      found =
        open
        |> Enum.filter(
          &((project_id == nil or &1.project_id == project_id) and (leads == nil or &1.project_id in leads))
        )
        |> Enum.reject(&MapSet.member?(waiting, &1.id))
        |> Enum.map(&{&1, trigger(&1, people, open)})
        |> Enum.reject(fn {_t, trigger} -> trigger == nil end)

      filed =
        Enum.flat_map(found, fn {task, trigger} ->
          case suggest(org_id, task, people, open, projects) do
            [best | _] = ranked -> [file!(task, trigger, best, ranked, projects, people)]
            [] -> []
          end
        end)

      {:ok, %{filed: filed, checked: length(found)}}
    end
  end

  @doc """
  Who should take a task, best first, without filing anything:
  `[%{person_id, name, score, why: [text], route: [text]}]`. The current owner is left out.
  """
  def suggest_owners(org_id, task_id, actor) do
    with {:ok, task} <- Ash.get(Task, task_id, actor: actor),
         {:ok, people} <- Work.people(org_id, actor),
         {:ok, open} <- Work.tasks(org_id, actor, open: true),
         {:ok, projects} <- Work.projects(org_id, actor) do
      _ = Noa.Graph.Experts.refresh(org_id)
      {:ok, suggest(org_id, task, people, open, Map.new(projects, &{&1.id, &1}))}
    end
  end

  ## What needs an owner

  defp trigger(task, people, open) do
    owner = task.owner_id && Enum.find(people, &(&1.id == task.owner_id))

    cond do
      owner == nil ->
        :unowned

      not Enum.any?(owner.allocations, &(&1.project_id == task.project_id)) ->
        :moved

      overdue?(task) and Enum.count(open, &(&1.owner_id == owner.id)) >= @overloaded ->
        :overdue

      true ->
        nil
    end
  end

  defp overdue?(%{due_on: nil}), do: false
  defp overdue?(%{due_on: due}), do: Date.compare(due, Date.utc_today()) == :lt

  ## Ranking

  defp suggest(org_id, task, people, open, projects) do
    project = projects[task.project_id]

    ranked =
      case graph_candidates(org_id, task) do
        {:ok, rows} -> rows
        :error -> fallback_candidates(task, people, open, project)
      end

    ranked
    |> Enum.reject(&(&1.person_id == task.owner_id))
    |> Enum.sort_by(&(-&1.score))
  end

  defp graph_candidates(org_id, task) do
    today = Date.to_iso8601(Date.utc_today())

    with {:ok, [%{"n" => n}]} when n > 0 <-
           Graph.ro_query(org_id, "MATCH (p:Project {id: $id}) RETURN count(p) AS n", %{id: task.project_id}),
         {:ok, on} <-
           Graph.ro_query(
             org_id,
             """
             MATCH (x:Person)-[w:WORKS_ON]->(p:Project {id: $project})
             WHERE (w.to IS NULL OR w.to >= $today) AND (w.from IS NULL OR w.from <= $today)
             OPTIONAL MATCH (x)-[k:KNOWS_ABOUT]->(p)
             WITH x, p, max(w.percent) AS percent, max(coalesce(k.weight, 0)) AS knows
             OPTIONAL MATCH (x)<-[:ASSIGNED_TO]-(o:Task) WHERE o.status <> 'done'
             RETURN x.id AS id, x.name AS name, p.name AS project, percent, knows, count(o) AS load
             """,
             %{project: task.project_id, today: today}
           ),
         {:ok, similar} <- similar_work(org_id, task),
         {:ok, decided} <-
           Graph.ro_query(
             org_id,
             """
             MATCH (x:Person)-[:DECIDED]->(d:Decision {status: 'active'})-[:AFFECTS]->(:Task {id: $task})
             RETURN x.id AS id, collect(d.statement) AS statements
             """,
             %{task: task.id}
           ) do
      words = words(task.title)
      # Finished tasks that share at least half of this title's words, closest first.
      similar =
        Map.new(similar, fn r ->
          close =
            r["titles"]
            |> Enum.map(&{&1, overlap(words, &1)})
            |> Enum.filter(fn {_t, o} -> o >= 0.5 end)
            |> Enum.sort_by(fn {_t, o} -> -o end)

          {r["id"], close}
        end)

      decided = Map.new(decided, &{&1["id"], &1["statements"]})

      {:ok,
       Enum.map(on, fn r ->
         close = similar[r["id"]] || []
         titles = close |> Enum.map(&elem(&1, 0)) |> Enum.take(3)
         best_overlap = close |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 0 end)
         statements = decided[r["id"]] || []
         # Knowledge of the project, plus close past work and decisions, less what they already carry.
         score = r["knows"] + 4 * best_overlap + 2 * length(statements) - r["load"] + (r["percent"] || 0) / 50

         why =
           [
             r["knows"] > 0 && "Has worked on #{r["project"]} (KNOWS_ABOUT weight #{r["knows"]})",
             titles != [] && "Finished similar work: #{Enum.map_join(titles, ", ", &"“#{&1}”")}",
             statements != [] && "Made the decision this depends on: “#{hd(statements)}”",
             "#{r["percent"] || 0}% on #{r["project"]}, #{r["load"]} open #{if r["load"] == 1, do: "task", else: "tasks"}"
           ]
           |> Enum.filter(& &1)

         route =
           [
             "(#{r["name"]})-[:WORKS_ON {percent: #{r["percent"] || 0}}]->(#{r["project"]})",
             r["knows"] > 0 && "(#{r["name"]})-[:KNOWS_ABOUT {weight: #{r["knows"]}}]->(#{r["project"]})",
             titles != [] && "full-text Task titles → (:Task {status: 'done'})-[:ASSIGNED_TO]->(#{r["name"]})",
             statements != [] && "(#{r["name"]})-[:DECIDED]->(:Decision)-[:AFFECTS]->(this task)",
             "(#{r["name"]})<-[:ASSIGNED_TO]-(:Task) × #{r["load"]} open"
           ]
           |> Enum.filter(& &1)

         %{person_id: r["id"], name: r["name"], score: Float.round(score * 1.0, 2), why: why, route: route, graph: true}
       end)}
    else
      _ -> :error
    end
  end

  defp words(title) do
    title
    |> String.downcase()
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> Enum.filter(&(String.length(&1) >= 3))
    |> Enum.uniq()
    |> Enum.take(8)
  end

  # Share of the task's words that appear (as a prefix) in another title.
  defp overlap([], _title), do: 0

  defp overlap(words, title) do
    other = words(title)

    Enum.count(words, fn w -> Enum.any?(other, &(String.starts_with?(&1, w) or String.starts_with?(w, &1))) end) /
      length(words)
  end

  # Who finished tasks whose titles share words with this one (FalkorDB full-text).
  defp similar_work(org_id, task) do
    words = words(task.title)

    if words == [] do
      {:ok, []}
    else
      Graph.ro_query(
        org_id,
        """
        CALL db.idx.fulltext.queryNodes('Task', $q) YIELD node, score
        WITH node, score WHERE node.status = 'done' AND node.id <> $task
        MATCH (node)-[:ASSIGNED_TO]->(x:Person)
        WITH x, node ORDER BY score DESC
        RETURN x.id AS id, collect(node.title)[0..10] AS titles
        """,
        %{q: Enum.map_join(words, "|", &"#{&1}*"), task: task.id}
      )
    end
  end

  defp fallback_candidates(_task, _people, _open, nil), do: []

  defp fallback_candidates(task, people, open, project) do
    people
    |> Enum.flat_map(fn p ->
      case Enum.find(p.allocations, &(&1.project_id == task.project_id)) do
        nil ->
          []

        a ->
          load = Enum.count(open, &(&1.owner_id == p.id))

          [
            %{
              person_id: p.id,
              name: p.name,
              score: a.percent / 50 - load,
              why: ["#{a.percent}% on #{project.name}, #{load} open #{if load == 1, do: "task", else: "tasks"}"],
              route: ["Postgres allocations (the graph isn't built yet)"],
              graph: false
            }
          ]
      end
    end)
  end

  ## Filing

  defp file!(task, trigger, best, ranked, projects, people) do
    project = projects[task.project_id]
    from = task.owner_id && Enum.find(people, &(&1.id == task.owner_id))

    reason =
      case trigger do
        :unowned -> "Nobody owns “#{task.title}” in #{project.name}."
        :moved -> "#{from.name} is no longer on #{project.name} but still owns “#{task.title}”."
        :overdue -> "“#{task.title}” is overdue and #{from.name} has #{@overloaded} or more open tasks."
      end

    Proposal
    |> Ash.Changeset.for_create(:create, %{
      kind: :assignment,
      summary: "Give “#{task.title}” to #{best.name}",
      data: %{
        "trigger" => Atom.to_string(trigger),
        "reason" => reason,
        "title" => task.title,
        "from_owner_id" => task.owner_id,
        "why" => best.why,
        "graph_route" => best.route,
        "graph" => best.graph,
        "candidates" =>
          ranked |> Enum.take(3) |> Enum.map(&%{"person_id" => &1.person_id, "name" => &1.name, "score" => &1.score})
      },
      confidence: confidence(ranked),
      source: %{
        "author" => "Noa",
        "quote" => reason,
        "kind" => "triage",
        "at" => DateTime.to_iso8601(DateTime.utc_now())
      },
      org_id: task.org_id,
      project_id: task.project_id,
      owner_id: best.person_id,
      task_id: task.id
    })
    |> Ash.create!(authorize?: false)
  end

  # How clearly the best candidate beats the next one.
  defp confidence([_only]), do: 0.7

  defp confidence([a, b | _]) do
    gap = (a.score - b.score) / max(abs(a.score), 1)
    Float.round(min(0.95, max(0.5, 0.5 + gap / 2)), 2)
  end

  ## Who may run it

  defp allowed(org_id, actor, project_id) do
    cond do
      Map.get(actor, :is_superadmin) -> :ok
      Work.lead?(actor.id, org_id, project_id) -> :ok
      project_id == nil and led_projects(org_id, actor, nil) != [] -> :ok
      true -> {:error, :not_a_project_lead}
    end
  end

  # nil means every project (org admins and PMs); otherwise the projects the actor leads.
  defp led_projects(org_id, actor, ids) do
    if Map.get(actor, :is_superadmin) or Noa.Orgs.role(actor.id, org_id) in [:org_admin, :pm] do
      nil
    else
      Noa.Work.Project
      |> Ash.Query.filter(org_id == ^org_id and lead.membership.user_id == ^actor.id)
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.id)
      |> then(&if(ids, do: Enum.filter(&1, fn id -> id in ids end), else: &1))
    end
  end

  defp pending_task_ids(org_id) do
    Proposal
    |> Ash.Query.filter(org_id == ^org_id and status == :pending and kind == :assignment)
    |> Ash.read!(authorize?: false)
    |> MapSet.new(& &1.task_id)
  end
end
