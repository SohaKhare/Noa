defmodule Noa.Orgs.Checks.ActorAdminsOrg do
  @moduledoc "True when the actor is an org admin of the org the changeset writes to."
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "actor is an org admin of the target org"

  @impl true
  def match?(%{id: actor_id}, %{subject: %Ash.Changeset{} = changeset}, _opts) do
    case Ash.Changeset.get_attribute(changeset, :org_id) do
      nil -> false
      org_id -> Noa.Orgs.admin?(actor_id, org_id)
    end
  end

  def match?(_actor, _context, _opts), do: false
end
