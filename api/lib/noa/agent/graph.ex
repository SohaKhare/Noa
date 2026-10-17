defmodule Noa.Agent.Graph do
  @moduledoc """
  `@noa`'s retrieval from FalkorDB (2.5): the graph decides what the agent reads.

  For a question it runs, against the asker's workspace graph only:

  - **Anchored walks** from the projects and people the question names:
    Project ← Task (status, owner, due) and its source message, Project ← Decision,
    Project ← Channel ← Episode (recent talk), Person ← Task, Person → Decision,
    Person → Episode.
  - **Full-text search** (FalkorDB full-text indexes) over task titles, decision
    statements and message text, for the question's own words.
  - **Intent queries** when nothing is named: blocked work, late work, recent decisions.
  - **Graph algorithms as tools:** `KNOWS_ABOUT` weights for "who knows…", PageRank for
    "who does the work run through", betweenness for "who connects…", and the
    shortest path between two named things for "how is X connected to Y".

  Every source carries `via`, the route that found it, and the answer reports the
  routes used. Ranking is shared with the Postgres fallback in `Noa.Agent`.
  """
  alias Noa.Agent.Source
  alias Noa.Graph

  @doc """
  Candidates for `ask`: `{:ok, sources, routes}` or `{:error, reason}` (the caller falls
  back to Postgres), including `:graph_not_built` for a workspace the projector has not
  reached yet. `q` is the parsed question: `%{words, projects, people, intent}`
  where projects and people are the named ones (`%{id, name}` maps).
  """
  def candidates(org_id, q) do
    case Graph.ro_query(org_id, "MATCH (p:Project) RETURN count(p) AS n") do
      {:ok, [%{"n" => n}]} when n > 0 ->
        # "Who knows…" reads KNOWS_ABOUT, which is derived; bring it up to date first.
        if MapSet.member?(q.intent, :who), do: Noa.Graph.Experts.refresh(org_id)
        run(org_id, q)

      {:ok, _} ->
        {:error, :graph_not_built}

      error ->
        error
    end
  end

  defp run(org_id, q) do
    runs =
      [
        Enum.flat_map(q.projects, &project_walk(&1.id)),
        Enum.flat_map(q.people, &person_walk(&1.id)),
        fulltext(q.words),
        intent_queries(q),
        algorithm_queries(q)
      ]
      |> List.flatten()

    Enum.reduce_while(runs, {:ok, [], MapSet.new()}, fn {route, cypher, params, build}, {:ok, acc, routes} ->
      case Graph.ro_query(org_id, cypher, params) do
        {:ok, rows} ->
          found = rows |> Enum.map(&build.(&1)) |> Enum.reject(&is_nil/1) |> Enum.map(&%{&1 | via: route})
          {:cont, {:ok, acc ++ found, if(found == [], do: routes, else: MapSet.put(routes, route))}}

        error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, sources, routes} -> {:ok, Enum.uniq_by(sources, & &1.id), MapSet.to_list(routes)}
      error -> error
    end
  end

  # Return values the Source builders read. Tasks and decisions carry their project and source.
  @task_ret """
  t.id AS id, t.title AS title, t.status AS status, t.due AS due, t.blocked_reason AS blocked_reason,
  p.id AS project_id, p.key AS project_key, p.name AS project, o.id AS owner_id, o.name AS owner,
  coalesce(t.src_channel, sc.name) AS src_channel, coalesce(t.src_author, se.author) AS src_author,
  coalesce(t.src_at, se.at) AS src_at, coalesce(t.src_quote, se.text) AS src_quote
  """
  @decision_ret """
  d.id AS id, d.statement AS statement, d.kind AS kind, d.at AS at, p.id AS project_id, p.key AS project_key,
  p.name AS project, x.id AS by_id, x.name AS by,
  coalesce(d.src_channel, sc.name) AS src_channel, coalesce(d.src_author, se.author) AS src_author,
  coalesce(d.src_at, se.at) AS src_at, coalesce(d.src_quote, se.text) AS src_quote
  """
  @episode_ret """
  e.id AS id, e.text AS text, e.at AS at, e.author AS author, c.name AS channel, p.id AS project_id, a.id AS author_id
  """

  defp task(route, match, params),
    do:
      {route, "#{match} OPTIONAL MATCH (t)-[:ASSIGNED_TO]->(o:Person) #{cited("t")} RETURN #{@task_ret}", params,
       &Source.graph_task/1}

  defp decision(route, match, params),
    do:
      {route, "#{match} OPTIONAL MATCH (x:Person)-[:DECIDED]->(d) #{cited("d")} RETURN #{@decision_ret}", params,
       &Source.graph_decision/1}

  # The message a task or decision came from, followed through EXTRACTED_FROM, for its citation.
  defp cited(var), do: "OPTIONAL MATCH (#{var})-[:EXTRACTED_FROM]->(se:Episode) OPTIONAL MATCH (se)-[:IN]->(sc:Channel)"

  defp episode(route, match, params),
    do:
      {route, "#{match} OPTIONAL MATCH (a:Person)-[:AUTHORED]->(e) RETURN #{@episode_ret} ORDER BY e.at DESC LIMIT 25",
       params, &Source.graph_episode/1}

  defp project_walk(id) do
    [
      task("Project ← Task", "MATCH (t:Task)-[:BELONGS_TO]->(p:Project {id: $id})", %{id: id}),
      decision("Project ← Decision", "MATCH (d:Decision {status: 'active'})-[:AFFECTS]->(p:Project {id: $id})", %{
        id: id
      }),
      episode(
        "Project ← Channel ← Message",
        "MATCH (e:Episode)-[:IN]->(c:Channel)-[:MAPS_TO]->(p:Project {id: $id})",
        %{id: id}
      )
    ]
  end

  defp person_walk(id) do
    [
      task(
        "Person ← Task",
        "MATCH (t:Task)-[:ASSIGNED_TO]->(:Person {id: $id}) MATCH (t)-[:BELONGS_TO]->(p:Project)",
        %{id: id}
      ),
      decision(
        "Person → Decision",
        "MATCH (:Person {id: $id})-[:DECIDED]->(d:Decision {status: 'active'}) OPTIONAL MATCH (d)-[:AFFECTS]->(p:Project)",
        %{id: id}
      ),
      episode(
        "Person → Message",
        "MATCH (:Person {id: $id})-[:AUTHORED]->(e:Episode) OPTIONAL MATCH (e)-[:IN]->(c:Channel) OPTIONAL MATCH (c)-[:MAPS_TO]->(p:Project)",
        %{id: id}
      )
    ]
  end

  # FalkorDB full-text indexes (RediSearch syntax): any of the words, with prefixes.
  defp fulltext([]), do: []

  defp fulltext(words) do
    query = words |> Enum.uniq() |> Enum.take(8) |> Enum.map_join("|", &"#{&1}*")

    [
      task(
        "Full-text: tasks",
        "CALL db.idx.fulltext.queryNodes('Task', $q) YIELD node AS t MATCH (t)-[:BELONGS_TO]->(p:Project)",
        %{q: query}
      ),
      decision(
        "Full-text: decisions",
        "CALL db.idx.fulltext.queryNodes('Decision', $q) YIELD node AS d WHERE d.status = 'active' OPTIONAL MATCH (d)-[:AFFECTS]->(p:Project)",
        %{q: query}
      ),
      episode(
        "Full-text: messages",
        "CALL db.idx.fulltext.queryNodes('Episode', $q) YIELD node AS e OPTIONAL MATCH (e)-[:IN]->(c:Channel) OPTIONAL MATCH (c)-[:MAPS_TO]->(p:Project)",
        %{q: query}
      )
    ]
  end

  # When the question names nothing, its intent still points somewhere in the graph.
  defp intent_queries(%{projects: [], people: []} = q) do
    [
      MapSet.member?(q.intent, :blocked) &&
        task("Blocked tasks", "MATCH (t:Task {status: 'blocked'})-[:BELONGS_TO]->(p:Project)", %{}),
      MapSet.member?(q.intent, :late) &&
        task(
          "Late tasks",
          "MATCH (t:Task)-[:BELONGS_TO]->(p:Project) WHERE t.status <> 'done' AND t.due IS NOT NULL AND t.due < $today",
          %{today: Date.to_iso8601(Date.utc_today())}
        ),
      MapSet.member?(q.intent, :decided) &&
        decision(
          "Recent decisions",
          "MATCH (d:Decision {status: 'active'}) OPTIONAL MATCH (d)-[:AFFECTS]->(p:Project)",
          %{}
        )
    ]
    |> Enum.filter(& &1)
  end

  defp intent_queries(_q), do: []

  defp algorithm_queries(q) do
    who = MapSet.member?(q.intent, :who)

    [
      who &&
        Enum.map(q.projects, fn p ->
          {"KNOWS_ABOUT weights",
           "MATCH (x:Person)-[k:KNOWS_ABOUT]->(p:Project {id: $id}) RETURN x.id AS person_id, x.name AS name, p.id AS project_id, p.name AS project, k.weight AS weight ORDER BY weight DESC LIMIT 3",
           %{id: p.id}, &Source.expert/1}
        end),
      (who and q.projects == [] and q.people == []) &&
        {"PageRank",
         "CALL algo.pageRank(NULL, NULL) YIELD node, score WITH node, score WHERE node:Person RETURN node.id AS person_id, node.name AS name, score ORDER BY score DESC LIMIT 3",
         %{}, &Source.key_person/1},
      MapSet.member?(q.intent, :connects) &&
        {"Betweenness",
         "CALL algo.betweenness({nodeLabels: ['Person', 'Project', 'Task'], relationshipTypes: ['ASSIGNED_TO', 'BELONGS_TO', 'WORKS_ON', 'LEADS']}) YIELD node, score WITH node, score WHERE node:Person AND score > 0 RETURN node.id AS person_id, node.name AS name, score ORDER BY score DESC LIMIT 3",
         %{}, &Source.bridge/1},
      path_query(q)
    ]
    |> List.flatten()
    |> Enum.filter(& &1)
  end

  # "How is Saish connected to Emmarie?": the shortest path between the two named things.
  defp path_query(%{intent: intent} = q) do
    case MapSet.member?(intent, :connects) && Enum.take(q.people ++ q.projects, 2) do
      [a, b] ->
        {"Shortest path",
         """
         MATCH p = (a {id: $a})-[*1..5]-(b {id: $b})
         RETURN length(p) AS hops, [n IN nodes(p) | coalesce(n.name, n.title, n.statement, n.text)] AS names, $a AS a, $b AS b
         ORDER BY hops LIMIT 1
         """, %{a: a.id, b: b.id}, &Source.path/1}

      _ ->
        nil
    end
  end
end
