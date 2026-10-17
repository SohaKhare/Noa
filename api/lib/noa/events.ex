defmodule Noa.Events do
  @moduledoc """
  The event log (1.8): every change to work, append-only, in Postgres. It is the
  truth; the graph is a projection of it (`Noa.Graph.Projector`) and can be rebuilt by
  replaying it.

  Writes to the Work resources append `<thing>.saved` or `<thing>.deleted` with a
  snapshot of the row, in the same transaction (`Noa.Events.Record`). Ingest appends
  `message.received` through `Noa.Work.record_message/2`, keyed by platform and message
  id so a message delivered twice is stored once.

  Appends take a transaction lock, so events commit in `id` order and a reader that
  remembers the last `id` it saw never skips one.
  """
  import Ecto.Query

  alias Noa.Events.Event
  alias Noa.Repo

  @topic "events"

  @doc """
  Appends an event. `opts`: `subject_id`, `actor_id`, `key` (idempotency, unique per
  org), `occurred_at`. Returns `{:ok, event}`, or `{:duplicate, event}` with the stored
  event when the key was used before.
  """
  def append(org_id, type, data, opts \\ []) do
    outer? = Repo.in_transaction?()

    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock(hashtext('noa.events'))")

      case opts[:key] && Repo.get_by(Event, org_id: org_id, key: opts[:key]) do
        %Event{} = existing ->
          {:duplicate, existing}

        nil ->
          Repo.insert!(%Event{
            org_id: org_id,
            type: type,
            data: json(data),
            subject_id: opts[:subject_id],
            actor_id: opts[:actor_id],
            key: opts[:key],
            occurred_at: at(opts[:occurred_at])
          })
          |> then(&{:ok, &1})
      end
    end)
    |> case do
      {:ok, {:ok, event}} -> if outer?, do: {:ok, event}, else: notify(event)
      {:ok, duplicate} -> duplicate
      error -> error
    end
  end

  @doc """
  Tells readers (the projector) to look at the log. Ash writes announce themselves after
  they commit (`Noa.Events.Record`); the projector's 2-second timer catches anything else.
  """
  def notify(%Event{} = event) do
    notify(event.org_id)
    {:ok, event}
  end

  def notify(org_id) do
    Phoenix.PubSub.broadcast(Noa.PubSub, @topic, {:appended, org_id})
    :ok
  end

  defp at(nil), do: DateTime.utc_now()
  defp at(%DateTime{} = at), do: %{at | microsecond: {elem(at.microsecond, 0), 6}}
  defp at(iso) when is_binary(iso), do: iso |> DateTime.from_iso8601() |> elem(1) |> at()

  def subscribe, do: Phoenix.PubSub.subscribe(Noa.PubSub, @topic)

  @doc "Events after `position`, oldest first. `org_id: id` limits to one org."
  def since(position, opts \\ []) do
    Event
    |> where([e], e.id > ^position)
    |> then(fn q -> if org = opts[:org_id], do: where(q, [e], e.org_id == ^org), else: q end)
    |> order_by(asc: :id)
    |> limit(^Keyword.get(opts, :limit, 500))
    |> Repo.all(log: false)
  end

  @doc "An org's history for one thing (a task, a person), oldest first."
  def history(org_id, subject_id) do
    Event |> where(org_id: ^org_id, subject_id: ^subject_id) |> order_by(asc: :id) |> Repo.all()
  end

  def position(name) do
    Repo.one(from(p in "projections", where: p.name == ^name, select: p.position), log: false) || 0
  end

  def put_position(name, position) do
    Repo.insert_all("projections", [%{name: name, position: position, updated_at: DateTime.utc_now()}],
      on_conflict: {:replace, [:position, :updated_at]},
      conflict_target: :name,
      log: false
    )

    :ok
  end

  @doc "Turns a snapshot into plain JSON values (string keys, ISO dates)."
  def json(%Date{} = d), do: Date.to_iso8601(d)
  def json(%DateTime{} = d), do: DateTime.to_iso8601(d)
  def json(%NaiveDateTime{} = d), do: NaiveDateTime.to_iso8601(d)
  def json(%Time{} = t), do: Time.to_iso8601(t)
  def json(%Ash.CiString{} = s), do: to_string(s)
  def json(%{__struct__: _} = s), do: s |> Map.from_struct() |> json()
  def json(map) when is_map(map), do: Map.new(map, fn {k, v} -> {to_string(k), json(v)} end)
  def json(list) when is_list(list), do: Enum.map(list, &json/1)
  def json(atom) when is_atom(atom) and atom not in [nil, true, false], do: Atom.to_string(atom)
  def json(other), do: other
end
