defmodule Noa.Graph.Experts do
  @moduledoc """
  Who knows what (3.3), from the graph.

  `refresh/1` writes `KNOWS_ABOUT` edges from each person to each project, weighted by
  what the graph shows they did there: tasks they finished (3), decisions they made (3),
  tasks they own (1), messages they wrote in its channels (1), commits to its repo (1)
  and pull requests of theirs that were merged there (2). `experts/2` ranks
  people on one project; `key_people/1` runs PageRank over the whole work graph; `bus_factor/1` flags projects where one person holds most of the knowledge,
  `groups/1` finds working groups (WCC) and `bridges/1` the people who connect them
  (betweenness).

  These are derived edges, rebuilt from projected data, so they stay a projection of
  the event log like everything else in the graph.
  """
  alias Noa.Graph

  @weights [
    {"MATCH (x:Person)<-[:ASSIGNED_TO]-(t:Task {status: 'done'})-[:BELONGS_TO]->(p:Project)", 3},
    {"MATCH (x:Person)-[:DECIDED]->(d:Decision {status: 'active'})-[:AFFECTS]->(p:Project)", 3},
    {"MATCH (x:Person)<-[:ASSIGNED_TO]-(t:Task)-[:BELONGS_TO]->(p:Project) WHERE t.status <> 'done'", 1},
    {"MATCH (x:Person)-[:AUTHORED]->(:Episode)-[:IN]->(:Channel)-[:MAPS_TO]->(p:Project)", 1},
    {"MATCH (x:Person)-[:COMMITTED]->(:Commit)-[:BELONGS_TO]->(p:Project)", 1},
    {"MATCH (x:Person)-[:OPENED]->(:PullRequest {state: 'merged'})-[:BELONGS_TO]->(p:Project)", 2}
  ]

  @doc "Recomputes every `KNOWS_ABOUT` edge in the org's graph."
  def refresh(org_id) do
    with {:ok, _} <- Graph.query(org_id, "MATCH (:Person)-[k:KNOWS_ABOUT]->() DELETE k") do
      Enum.reduce_while(@weights, :ok, fn {match, weight}, :ok ->
        cypher = """
        #{match}
        WITH x, p, count(*) AS n
        MERGE (x)-[k:KNOWS_ABOUT]->(p)
        SET k.weight = coalesce(k.weight, 0) + n * $w
        """

        case Graph.query(org_id, cypher, %{w: weight}) do
          {:ok, _} -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    end
  end

  @doc "People who know the project, strongest first: `[%{person_id, name, weight, share}]`."
  def experts(org_id, project_id) do
    with :ok <- refresh(org_id),
         {:ok, rows} <-
           Graph.ro_query(
             org_id,
             """
             MATCH (x:Person)-[k:KNOWS_ABOUT]->(:Project {id: $id})
             RETURN x.id AS person_id, x.name AS name, k.weight AS weight
             ORDER BY weight DESC
             """,
             %{id: project_id}
           ) do
      total = rows |> Enum.map(& &1["weight"]) |> Enum.sum()

      {:ok,
       Enum.map(rows, fn r ->
         %{
           person_id: r["person_id"],
           name: r["name"],
           weight: r["weight"],
           share: if(total > 0, do: r["weight"] / total, else: 0)
         }
       end)}
    end
  end

  @doc """
  PageRank over the org's whole work graph (tasks point at their owners, people at
  their decisions, messages and projects), people only, highest first: who the work
  runs through.
  """
  def key_people(org_id) do
    with :ok <- refresh(org_id),
         {:ok, rows} <-
           Graph.ro_query(org_id, """
           CALL algo.pageRank(NULL, NULL) YIELD node, score
           WITH node, score WHERE node:Person
           RETURN node.id AS person_id, node.name AS name, score
           ORDER BY score DESC
           """) do
      {:ok, Enum.map(rows, &%{person_id: &1["person_id"], name: &1["name"], score: &1["score"]})}
    end
  end

  @doc """
  Working groups (the track's "teams"): connected components (`algo.WCC`) of people and
  the projects they work on or lead. Returns `[%{people: [names], projects: [names]}]`,
  largest first; people on no project are left out.
  """
  def groups(org_id) do
    with {:ok, rows} <-
           Graph.ro_query(org_id, """
           CALL algo.WCC({nodeLabels: ['Person', 'Project'], relationshipTypes: ['WORKS_ON', 'LEADS']}) YIELD node, componentId
           RETURN componentId, collect(CASE WHEN node:Person THEN node.name END) AS people,
                  collect(CASE WHEN node:Project THEN node.name END) AS projects
           """) do
      {:ok,
       rows
       |> Enum.map(
         &%{
           people: Enum.reject(&1["people"], fn x -> is_nil(x) end),
           projects: Enum.reject(&1["projects"], fn x -> is_nil(x) end)
         }
       )
       |> Enum.reject(&(&1.projects == []))
       |> Enum.sort_by(&(-length(&1.people)))}
    end
  end

  @doc """
  People who connect the work (`algo.betweenness` over people, projects and tasks): the
  ones most shortest paths pass through. `[%{person_id, name, score}]`, highest first.
  """
  def bridges(org_id) do
    with {:ok, rows} <-
           Graph.ro_query(org_id, """
           CALL algo.betweenness({nodeLabels: ['Person', 'Project', 'Task'], relationshipTypes: ['ASSIGNED_TO', 'BELONGS_TO', 'WORKS_ON', 'LEADS']})
           YIELD node, score
           WITH node, score WHERE node:Person AND score > 0
           RETURN node.id AS person_id, node.name AS name, score ORDER BY score DESC
           """) do
      {:ok, Enum.map(rows, &%{person_id: &1["person_id"], name: &1["name"], score: &1["score"]})}
    end
  end

  @doc "Projects where one person holds at least `threshold` of the knowledge: `[%{project_id, project, person_id, name, share}]`."
  def bus_factor(org_id, threshold \\ 0.6) do
    with :ok <- refresh(org_id),
         {:ok, rows} <-
           Graph.ro_query(
             org_id,
             """
             MATCH (x:Person)-[k:KNOWS_ABOUT]->(p:Project)
             WITH p, x, k.weight AS w
             WITH p, collect({id: x.id, name: x.name, w: w}) AS people, sum(w) AS total
             UNWIND people AS person
             WITH p, person, total WHERE total > 0 AND person.w * 1.0 / total >= $t
             RETURN p.id AS project_id, p.name AS project, person.id AS person_id, person.name AS name, person.w * 1.0 / total AS share
             """,
             %{t: threshold}
           ) do
      {:ok, Enum.map(rows, &Map.new(&1, fn {k, v} -> {String.to_atom(k), v} end))}
    end
  end
end
