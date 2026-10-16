defmodule Noa.Graph do
  @moduledoc """
  FalkorDB, one graph per org (1.9). Only the projector writes here
  (`Noa.Graph.Projector`); everything else reads with `ro_query/3`.

  The connection is a supervised Redix process that reconnects on its own, so the API
  starts and works without FalkorDB; graph features return `{:error, _}` until it is
  up. Locally: `docker compose --profile graph up -d`. Configure with
  `config :noa, Noa.Graph, url: "redis://..."`; no url turns the graph off.

  Client notes from the 0.5 spike (falkordb 0.8.2 on FalkorDB 4.10):
  - options must be a map (`%{params: ..}`); a keyword list crashes the client.
  - params can be strings, numbers, booleans, lists and maps, not dates or atoms, so
    pass `Noa.Events.json/1` output. There is no `date()` function; dates are ISO strings.
  - return properties, not whole nodes: each `select_graph` starts a schema cache process.
  """
  @conn __MODULE__.Redix

  def child_spec(_opts) do
    url = config(:url)

    %{
      id: __MODULE__,
      start: {Redix, :start_link, [url || "redis://127.0.0.1:6379", [name: @conn, sync_connect: false]]}
    }
  end

  def enabled?, do: config(:url) != nil
  defp config(key), do: Application.get_env(:noa, __MODULE__, [])[key]

  @doc "The graph's name for an org."
  def name(org_id), do: "noa_" <> String.replace(org_id, "-", "")

  @doc "Runs a write query. Returns `{:ok, rows}`, rows as maps keyed by the RETURN names."
  def query(org_id, cypher, params \\ %{}), do: run(org_id, :query, cypher, params)

  @doc "Runs a read-only query."
  def ro_query(org_id, cypher, params \\ %{}), do: run(org_id, :ro_query, cypher, params)

  defp run(org_id, fun, cypher, params) do
    if enabled?() do
      graph = FalkorDB.select_graph(db(), name(org_id))

      try do
        case apply(FalkorDB.Graph, fun, [graph, cypher, %{params: Noa.Events.json(params), timeout: 10_000}]) do
          {:ok, result} -> {:ok, result.data || []}
          {:error, error} -> {:error, error}
        end
      catch
        :exit, reason -> {:error, {:exit, reason}}
      after
        FalkorDB.Graph.close(graph)
      end
    else
      {:error, :graph_off}
    end
  end

  defp db, do: FalkorDB.from_connection(FalkorDB.Connection.with(FalkorDB.Connection.RedixSingle, @conn, :single))

  @indexes [
    "CREATE INDEX FOR (n:Person) ON (n.id)",
    "CREATE INDEX FOR (n:Identity) ON (n.id)",
    "CREATE INDEX FOR (n:Project) ON (n.id)",
    "CREATE INDEX FOR (n:Channel) ON (n.id)",
    "CREATE INDEX FOR (n:Task) ON (n.id)",
    "CREATE INDEX FOR (n:Episode) ON (n.id)",
    "CREATE INDEX FOR (n:Decision) ON (n.id)",
    "CREATE INDEX FOR (n:Topic) ON (n.id)",
    "CALL db.idx.fulltext.createNodeIndex('Episode', 'text')",
    "CALL db.idx.fulltext.createNodeIndex('Task', 'title')"
  ]

  @doc """
  Creates the org's indexes. Safe to run again: "already indexed" is ignored. The
  vector index on Episode embeddings is added with embeddings (2.5).
  """
  def bootstrap(org_id) do
    Enum.reduce_while(@indexes, :ok, fn cypher, :ok ->
      case query(org_id, cypher) do
        {:ok, _} ->
          {:cont, :ok}

        {:error, %{message: message} = error} ->
          if message =~ ~r/already indexed|already exists/i, do: {:cont, :ok}, else: {:halt, {:error, error}}

        error ->
          {:halt, error}
      end
    end)
  end

  @doc "Deletes the org's graph (before a rebuild)."
  def drop(org_id) do
    if enabled?() do
      graph = FalkorDB.select_graph(db(), name(org_id))

      try do
        case FalkorDB.Graph.delete(graph) do
          {:ok, _} -> :ok
          {:error, %{message: m}} = error -> if m =~ ~r/empty key|invalid graph/i, do: :ok, else: error
          error -> error
        end
      after
        FalkorDB.Graph.close(graph)
      end
    else
      {:error, :graph_off}
    end
  end
end
