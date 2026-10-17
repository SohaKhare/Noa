defmodule Noa.Events.Record do
  @moduledoc """
  Ash change on every Work resource: after a create, update or destroy, appends
  `<name>.saved` or `<name>.deleted` with the row's public attributes, in the action's
  transaction. If the append fails, the write rolls back.

      change({Noa.Events.Record, name: "task"})
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, context) do
    changeset
    # Tell the projector as soon as the write commits, so the graph is current when
    # someone asks @noa right after approving something.
    |> Ash.Changeset.after_transaction(fn
      _changeset, {:ok, record} = result ->
        Noa.Events.notify(record.org_id)
        result

      _changeset, result ->
        result
    end)
    |> Ash.Changeset.after_action(fn changeset, record ->
      type = "#{opts[:name]}.#{if changeset.action_type == :destroy, do: "deleted", else: "saved"}"
      actor = context.actor && Map.get(context.actor, :id)

      case Noa.Events.append(record.org_id, type, snapshot(record), subject_id: record.id, actor_id: actor) do
        {:ok, _event} -> {:ok, record}
        {:error, error} -> {:error, error}
      end
    end)
  end

  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}

  @doc "The row's public attributes as JSON values: the data of its `.saved` event."
  def snapshot(%resource{} = record) do
    resource
    |> Ash.Resource.Info.public_attributes()
    |> Map.new(&{&1.name, Map.get(record, &1.name)})
    |> Noa.Events.json()
  end
end
