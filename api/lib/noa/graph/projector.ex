defmodule Noa.Graph.Projector do
  @moduledoc """
  Keeps FalkorDB in step with the event log (1.10). It reads events after its saved
  position, turns each into Cypher (`statements/1`) and runs it against the org's
  graph, then saves the position. It wakes on every announced append and every two seconds, so a
  missed message or a FalkorDB outage only delays the graph.

  Every statement MERGEs by id, so running an event twice is harmless. `rebuild/1`
  drops an org's graph and replays its whole log.
  """
  use GenServer
  require Logger

  alias Noa.{Events, Graph}

  @name "graph"
  @every 2_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Projects everything new now. Returns how many events it applied."
  def catch_up, do: GenServer.call(__MODULE__, :catch_up, 60_000)

  @impl true
  def init(_opts) do
    Events.subscribe()
    send(self(), :tick)
    {:ok, %{ready: MapSet.new(), timer: nil, failing: false}}
  end

  @impl true
  def handle_call(:catch_up, _from, state) do
    {count, state} = run(state)
    {:reply, count, state}
  end

  @impl true
  def handle_info(:tick, state) do
    {_count, state} = run(state)
    {:noreply, %{state | timer: Process.send_after(self(), :tick, @every)}}
  end

  def handle_info({:appended, _org_id}, state) do
    {_count, state} = run(state)
    {:noreply, state}
  end

  defp run(state) do
    case apply_since(Events.position(@name), state.ready, 0) do
      {:ok, count, ready} ->
        if state.failing, do: Logger.info("Graph projector caught up again")
        {count, %{state | ready: ready, failing: false}}

      {:error, event, error, count, ready} ->
        unless state.failing do
          Logger.warning("Graph projector stopped at event #{event.id} (#{event.type}): #{inspect(error)}")
        end

        {count, %{state | ready: ready, failing: true}}
    end
  end

  defp apply_since(position, ready, count) do
    case Events.since(position, limit: 200) do
      [] ->
        {:ok, count, ready}

      events ->
        Enum.reduce_while(events, {:ok, count, ready}, fn event, {:ok, count, ready} ->
          with {:ok, ready} <- ensure_ready(event.org_id, ready),
               :ok <- project(event) do
            Events.put_position(@name, event.id)
            {:cont, {:ok, count + 1, ready}}
          else
            {:error, error} -> {:halt, {:error, event, error, count, ready}}
          end
        end)
        |> case do
          {:ok, count, ready} -> apply_since(List.last(events).id, ready, count)
          error -> error
        end
    end
  end

  defp ensure_ready(org_id, ready) do
    if MapSet.member?(ready, org_id) do
      {:ok, ready}
    else
      with :ok <- Graph.bootstrap(org_id), do: {:ok, MapSet.put(ready, org_id)}
    end
  end

  @doc "Drops the org's graph and replays its whole event log into it."
  def rebuild(org_id) do
    with :ok <- Graph.drop(org_id), :ok <- Graph.bootstrap(org_id) do
      replay(org_id, 0, 0)
    end
  end

  defp replay(org_id, position, count) do
    case Events.since(position, org_id: org_id, limit: 500) do
      [] ->
        {:ok, count}

      events ->
        Enum.reduce_while(events, :ok, fn event, :ok ->
          case project(event) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end
        end)
        |> case do
          :ok -> replay(org_id, List.last(events).id, count + length(events))
          error -> error
        end
    end
  end

  @doc "Runs one event's statements against its org's graph."
  def project(event) do
    event
    |> statements()
    |> Enum.reduce_while(:ok, fn {cypher, params}, :ok ->
      case Graph.query(event.org_id, cypher, params) do
        {:ok, _} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  @doc "The Cypher for one event, as `[{cypher, params}]`. Unknown event types project to nothing."
  def statements(%{type: type, data: d}), do: statements(type, d)

  defp statements("person.saved", d) do
    [
      {"MERGE (p:Person {id: $id}) SET p.key = $key, p.name = $name, p.title = $title, p.email = $email, p.handles = $handles",
       params(d, ~w(id key name title email handles))}
    ]
  end

  defp statements("project.saved", d) do
    [
      {"MERGE (p:Project {id: $id}) SET p.key = $key, p.name = $name, p.about = $about, p.repo = $repo, p.status = $status",
       params(d, ~w(id key name about repo status))},
      {"MATCH (:Person)-[l:LEADS]->(:Project {id: $id}) DELETE l", %{"id" => d["id"]}}
    ] ++
      edge_to(d["lead_id"], "MATCH (p:Project {id: $id}) MERGE (l:Person {id: $to}) MERGE (l)-[:LEADS]->(p)", d)
  end

  defp statements("alias.saved", d) do
    [
      {"""
       MERGE (p:Project {id: $project_id})
       SET p.aliases = CASE WHEN $alias IN coalesce(p.aliases, []) THEN p.aliases ELSE coalesce(p.aliases, []) + $alias END
       """, params(d, ~w(project_id alias))}
    ]
  end

  defp statements("alias.deleted", d) do
    [
      {"MATCH (p:Project {id: $project_id}) SET p.aliases = [a IN coalesce(p.aliases, []) WHERE a <> $alias]",
       params(d, ~w(project_id alias))}
    ]
  end

  defp statements("allocation.saved", d) do
    [
      {"""
       MERGE (a:Person {id: $person_id}) MERGE (p:Project {id: $project_id})
       MERGE (a)-[w:WORKS_ON {id: $id}]->(p)
       SET w.percent = $percent, w.role = $role, w.from = $starts_on, w.to = $ends_on
       """, params(d, ~w(id person_id project_id percent role starts_on ends_on))}
    ]
  end

  defp statements("allocation.deleted", d),
    do: [{"MATCH ()-[w:WORKS_ON {id: $id}]->() DELETE w", %{"id" => d["id"]}}]

  defp statements("channel.saved", d) do
    [
      {"MERGE (c:Channel {id: $id}) SET c.name = $name, c.platform = $platform, c.split = $split, c.read = $read",
       params(d, ~w(id name platform split read))},
      {"MATCH (:Channel {id: $id})-[m:MAPS_TO]->() DELETE m", %{"id" => d["id"]}}
    ] ++
      edge_to(d["project_id"], "MATCH (c:Channel {id: $id}) MERGE (p:Project {id: $to}) MERGE (c)-[:MAPS_TO]->(p)", d)
  end

  defp statements("identity.saved", d) do
    [
      {"MERGE (i:Identity {id: $id}) SET i.platform = $platform, i.external_id = $external_id, i.name = $display_name",
       params(d, ~w(id platform external_id display_name))},
      {"MATCH (:Person)-[h:HAS_IDENTITY]->(:Identity {id: $id}) DELETE h", %{"id" => d["id"]}}
    ] ++
      edge_to(
        d["person_id"],
        "MATCH (i:Identity {id: $id}) MERGE (p:Person {id: $to}) MERGE (p)-[:HAS_IDENTITY]->(i)",
        d
      )
  end

  defp statements("task.saved", d) do
    episode = get_in(d, ["source", "episode_id"])

    [
      {"""
       MERGE (t:Task {id: $id})
       SET t.title = $title, t.detail = $detail, t.status = $status, t.due = $due_on,
           t.blocked_reason = $blocked_reason, t.done_at = $done_at, t.created_at = $inserted_at
       """, params(d, ~w(id title detail status due_on blocked_reason done_at inserted_at))},
      {"MATCH (:Task {id: $id})-[r:BELONGS_TO|ASSIGNED_TO]->() DELETE r", %{"id" => d["id"]}}
    ] ++
      edge_to(d["project_id"], "MATCH (t:Task {id: $id}) MERGE (p:Project {id: $to}) MERGE (t)-[:BELONGS_TO]->(p)", d) ++
      edge_to(d["owner_id"], "MATCH (t:Task {id: $id}) MERGE (p:Person {id: $to}) MERGE (t)-[:ASSIGNED_TO]->(p)", d) ++
      edge_to(episode, "MATCH (t:Task {id: $id}) MERGE (e:Episode {id: $to}) MERGE (t)-[:EXTRACTED_FROM]->(e)", d)
  end

  defp statements("message.received", d) do
    [
      {"""
       MERGE (e:Episode {id: $episode_id})
       SET e.text = $text, e.at = $at, e.platform = $platform, e.author = $author
       MERGE (c:Channel {id: $channel_id})
       MERGE (e)-[:IN]->(c)
       """, params(d, ~w(episode_id text at platform author channel_id))}
    ] ++
      edge_to(
        d["person_id"],
        "MATCH (e:Episode {id: $id}) MERGE (p:Person {id: $to}) MERGE (p)-[:AUTHORED]->(e)",
        %{"id" => d["episode_id"]}
      )
  end

  defp statements(type, d) do
    case String.split(type, ".") do
      [thing, "deleted"] when thing in ~w(person project channel identity task) ->
        [{"MATCH (n:#{label(thing)} {id: $id}) DETACH DELETE n", %{"id" => d["id"]}}]

      _ ->
        []
    end
  end

  defp label(thing), do: thing |> Macro.camelize()

  # Every name the Cypher uses must be sent, so missing fields go as null.
  defp params(d, keys), do: Map.new(keys, &{&1, d[&1]})

  defp edge_to(nil, _cypher, _d), do: []
  defp edge_to(to, cypher, d), do: [{cypher, %{"id" => d["id"], "to" => to}}]
end
