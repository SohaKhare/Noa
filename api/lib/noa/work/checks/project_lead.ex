defmodule Noa.Work.Checks.ProjectLead do
  @moduledoc """
  True when the actor leads the work the changeset touches: an org admin or PM in its
  org, or the person set as lead of its project (2.20).
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "actor is an org admin, a PM, or the project's lead"

  @impl true
  def match?(%{id: actor_id}, %{subject: %Ash.Changeset{} = changeset}, _opts) do
    org_id = Ash.Changeset.get_attribute(changeset, :org_id)
    project_id = Ash.Changeset.get_attribute(changeset, :project_id)
    org_id != nil and Noa.Work.lead?(actor_id, org_id, project_id)
  end

  def match?(_actor, _context, _opts), do: false
end
