defmodule Noa.Graph.View do
  @moduledoc """
  The graph panel (3.13): a project's neighbourhood in FalkorDB as nodes and edges for
  the web app to draw, and the shortest path between two nodes for path highlighting.
  Read-only, from the projection.
  """
  alias Noa.Graph

  @doc """
  The project, the people who work on, lead or own work in it, its tasks and
  decisions, its channels, and the messages its tasks and decisions came from.
  Returns `{:ok, %{nodes: [%{id, label, name}], edges: [%{from, to, type}]}}`.
  """
  def project(org_id, project_id) do
    queries = [
      "MATCH (a:Project {id: $id}) RETURN a, null AS r, null AS b",
      "MATCH (a:Person)-[r:WORKS_ON|LEADS|KNOWS_ABOUT]->(b:Project {id: $id}) RETURN a, r, b",
      "MATCH (a:Task)-[r:BELONGS_TO]->(b:Project {id: $id}) RETURN a, r, b",
      "MATCH (:Project {id: $id})<-[:BELONGS_TO]-(a:Task)-[r:ASSIGNED_TO]->(b:Person) RETURN a, r, b",
      "MATCH (a:Decision)-[r:AFFECTS]->(b:Project {id: $id}) RETURN a, r, b",
      "MATCH (a:Person)-[r:DECIDED]->(b:Decision)-[:AFFECTS]->(:Project {id: $id}) RETURN a, r, b",
      "MATCH (a:Channel)-[r:MAPS_TO]->(b:Project {id: $id}) RETURN a, r, b",
      "MATCH (:Project {id: $id})<-[:BELONGS_TO]-(a:Task)-[r:EXTRACTED_FROM]->(b:Episode) RETURN a, r, b",
      "MATCH (:Project {id: $id})<-[:AFFECTS]-(a:Decision)-[r:EXTRACTED_FROM]->(b:Episode) RETURN a, r, b",
      "MATCH (:Project {id: $id})<-[:MAPS_TO]-(:Channel)<-[:IN]-(b:Episode)<-[r:AUTHORED]-(a:Person) RETURN a, r, b LIMIT 40"
    ]

    Enum.reduce_while(queries, {:ok, %{nodes: %{}, edges: MapSet.new()}}, fn q, {:ok, acc} ->
      case Graph.ro_query(org_id, rows(q), %{id: project_id}) do
        {:ok, rows} -> {:cont, {:ok, Enum.reduce(rows, acc, &add/2)}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, %{nodes: nodes, edges: edges}} ->
        {:ok, %{nodes: Map.values(nodes), edges: Enum.map(edges, fn {f, t, type} -> %{from: f, to: t, type: type} end)}}

      error ->
        error
    end
  end

  # Return plain properties, not node objects (see Noa.Graph on the client's schema cache).
  defp rows(query) do
    [match, ret] = String.split(query, " RETURN ", parts: 2)
    limit = if ret =~ "LIMIT", do: " LIMIT " <> (ret |> String.split("LIMIT ") |> List.last()), else: ""

    match <>
      " RETURN a.id AS a_id, labels(a)[0] AS a_label, coalesce(a.name, a.title, a.statement, a.text) AS a_name" <>
      if(ret =~ "null AS r",
        do: ", null AS type, null AS b_id, null AS b_label, null AS b_name",
        else:
          ", type(r) AS type, b.id AS b_id, labels(b)[0] AS b_label, coalesce(b.name, b.title, b.statement, b.text) AS b_name"
      ) <> limit
  end

  defp add(row, %{nodes: nodes, edges: edges}) do
    nodes = node(nodes, row["a_id"], row["a_label"], row["a_name"])
    nodes = node(nodes, row["b_id"], row["b_label"], row["b_name"])
    edges = if row["type"], do: MapSet.put(edges, {row["a_id"], row["b_id"], row["type"]}), else: edges
    %{nodes: nodes, edges: edges}
  end

  defp node(nodes, nil, _label, _name), do: nodes

  defp node(nodes, id, label, name) do
    Map.put_new(nodes, id, %{id: id, label: label, name: name |> to_string() |> String.slice(0, 80)})
  end

  @doc """
  The shortest path between two nodes, ignoring direction, up to 5 hops: the node ids
  along it, or [] when unconnected. FalkorDB 4.10 has no undirected `shortestPath`, so
  this orders the variable-length matches by length; fine at a project's size.
  """
  def path(org_id, from, to), do: shortest(org_id, from, to)

  defp shortest(org_id, from, to) do
    case Graph.ro_query(
           org_id,
           """
           MATCH p = (a {id: $from})-[*1..5]-(b {id: $to})
           RETURN length(p) AS hops, [n IN nodes(p) | n.id] AS ids
           ORDER BY hops
           LIMIT 1
           """,
           %{from: from, to: to}
         ) do
      {:ok, [%{"ids" => ids}]} when is_list(ids) -> {:ok, ids}
      {:ok, _} -> {:ok, []}
      error -> error
    end
  end
end
