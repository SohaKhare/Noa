defmodule Noa.Work.Change do
  @moduledoc """
  A change record (2.19): one edit to a shared task (its deadline, scope, owner, status
  or title), with the old and new value, who asked and why.

  Lead rules (2.20, `Noa.Work.update_task/3`): a lead's edits apply at once. Anyone
  else's deadline and scope changes wait here as `pending` until a lead approves; their
  other edits apply at once and can be reverted by a lead or by whoever made them.
  """
  use Ash.Resource,
    otp_app: :noa,
    domain: Noa.Work,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @kinds [:deadline, :scope, :owner, :status, :title]
  def kinds, do: @kinds

  postgres do
    table("changes")
    repo(Noa.Repo)

    references do
      reference(:org, on_delete: :delete)
      reference(:project, on_delete: :delete)
      reference(:task, on_delete: :delete)
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:kind, :atom, constraints: [one_of: @kinds], allow_nil?: false, public?: true)
    attribute(:old_value, :string, public?: true)
    attribute(:new_value, :string, public?: true)
    attribute(:reason, :string, public?: true)

    attribute(:status, :atom,
      constraints: [one_of: [:applied, :pending, :rejected, :reverted]],
      allow_nil?: false,
      public?: true
    )

    attribute(:source, :map, public?: true)
    attribute(:decided_at, :utc_datetime_usec, public?: true)
    create_timestamp(:inserted_at, public?: true)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to(:org, Noa.Orgs.Org, allow_nil?: false, attribute_writable?: true, public?: true)
    belongs_to(:project, Noa.Work.Project, allow_nil?: false, attribute_writable?: true, public?: true)
    belongs_to(:task, Noa.Work.Task, allow_nil?: false, attribute_writable?: true, public?: true)
    belongs_to(:requested_by, Noa.Accounts.User, attribute_writable?: true, public?: true)
    belongs_to(:decided_by, Noa.Accounts.User, attribute_writable?: true, public?: true)
  end

  changes do
    change({Noa.Events.Record, name: "change"}, on: [:create, :update])
  end

  actions do
    defaults([:read])

    create :create do
      accept([
        :kind,
        :old_value,
        :new_value,
        :reason,
        :status,
        :source,
        :org_id,
        :project_id,
        :task_id,
        :requested_by_id
      ])
    end

    # Approve or reject a pending change.
    update :decide do
      accept([:status, :decided_by_id])
      change(set_attribute(:decided_at, &DateTime.utc_now/0))
    end

    update :revert do
      accept([:decided_by_id])
      change(set_attribute(:status, :reverted))
      change(set_attribute(:decided_at, &DateTime.utc_now/0))
    end
  end

  policies do
    bypass actor_attribute_equals(:is_superadmin, true) do
      authorize_if(always())
    end

    policy action_type(:read) do
      authorize_if(expr(exists(org.memberships, user_id == ^actor(:id))))
    end

    policy action_type(:create) do
      authorize_if(Noa.Work.Checks.ActorInOrg)
    end

    policy action(:decide) do
      authorize_if(Noa.Work.Checks.ProjectLead)
    end

    policy action(:revert) do
      authorize_if(Noa.Work.Checks.ProjectLead)
      authorize_if(expr(requested_by_id == ^actor(:id)))
    end
  end
end
