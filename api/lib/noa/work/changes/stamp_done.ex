defmodule Noa.Work.Changes.StampDone do
  @moduledoc "Sets `done_at` when a task moves to done, and clears it when it moves back."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    if Ash.Changeset.changing_attribute?(changeset, :status) do
      done_at = if Ash.Changeset.get_attribute(changeset, :status) == :done, do: DateTime.utc_now()
      Ash.Changeset.force_change_attribute(changeset, :done_at, done_at)
    else
      changeset
    end
  end
end
