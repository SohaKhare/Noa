defmodule Noa.Work.Changes.ProtectDiscordHandles do
  @moduledoc false
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    old = verified(changeset.data.handles || [])
    new = verified(Ash.Changeset.get_attribute(changeset, :handles) || [])

    same_membership = changeset.data.membership_id == Ash.Changeset.get_attribute(changeset, :membership_id)

    if old == new and (old == [] or same_membership) do
      changeset
    else
      Ash.Changeset.add_error(changeset, field: :handles, message: "Use the verified Discord account-link flow")
    end
  end

  defp verified(handles), do: handles |> Enum.filter(&String.starts_with?(&1, "discord:")) |> Enum.sort()
end
