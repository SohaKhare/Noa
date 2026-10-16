defmodule Noa.Work.Checks.ActorInOrg do
  @moduledoc """
  True when the actor belongs to the org the changeset writes to, with one of `roles`
  (default: everyone but guests). Works for creates, where there is no row to filter yet.
  """
  use Ash.Policy.SimpleCheck

  @writers [:org_admin, :pm, :member]

  @impl true
  def describe(opts), do: "actor is in the target org as #{inspect(Keyword.get(opts, :roles, @writers))}"

  @impl true
  def match?(%{id: actor_id}, %{subject: %Ash.Changeset{} = changeset}, opts) do
    case Ash.Changeset.get_attribute(changeset, :org_id) do
      nil -> false
      org_id -> Noa.Orgs.role(actor_id, org_id) in Keyword.get(opts, :roles, @writers)
    end
  end

  def match?(_actor, _context, _opts), do: false
end
