defmodule Noa.Work.Proposal do
  @moduledoc """
  Something Noa found in chat that waits in the Inbox (1.17, 1.19): a new task, a
  status or deadline change, a decision or a scope change. `data` holds the typed
  item's fields; `source` is the message it came from.

  Approving applies it (see `Noa.Work.approve/3`). Leads (org admin or PM) can approve
  anything; a member can approve proposals about themselves.
  """
  use Ash.Resource,
    otp_app: :noa,
    domain: Noa.Work,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @kinds [:task, :status_change, :deadline_change, :decision, :scope_change, :assignment]
  def kinds, do: @kinds

  postgres do
    table("proposals")
    repo(Noa.Repo)

    references do
      reference(:org, on_delete: :delete)
      reference(:project, on_delete: :nilify)
      reference(:owner, on_delete: :nilify)
      reference(:task, on_delete: :nilify)
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:kind, :atom, constraints: [one_of: @kinds], allow_nil?: false, public?: true)
    attribute(:summary, :string, allow_nil?: false, public?: true)
    attribute(:data, :map, allow_nil?: false, default: %{}, public?: true)
    attribute(:confidence, :float, public?: true)
    attribute(:source, :map, public?: true)

    attribute(:status, :atom,
      constraints: [one_of: [:pending, :approved, :rejected]],
      default: :pending,
      allow_nil?: false,
      public?: true
    )

    attribute(:decided_at, :utc_datetime_usec, public?: true)
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to(:org, Noa.Orgs.Org, allow_nil?: false, attribute_writable?: true, public?: true)
    belongs_to(:project, Noa.Work.Project, attribute_writable?: true, public?: true)
    belongs_to(:owner, Noa.Work.Person, attribute_writable?: true, public?: true)
    belongs_to(:task, Noa.Work.Task, attribute_writable?: true, public?: true)
    belongs_to(:decided_by, Noa.Accounts.User, attribute_writable?: true, public?: true)
  end

  changes do
    change({Noa.Events.Record, name: "proposal"}, on: [:create, :update, :destroy])
  end

  actions do
    defaults([:read])

    create :create do
      accept([:kind, :summary, :data, :confidence, :source, :org_id, :project_id, :owner_id, :task_id])
    end

    update :decide do
      accept([:status, :decided_by_id, :task_id, :project_id, :owner_id, :data, :summary])
      require_atomic?(false)
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

    # Proposals are created by Noa's pipeline (no actor) or by a lead by hand.
    policy action_type(:create) do
      authorize_if({Noa.Work.Checks.ActorInOrg, roles: [:org_admin, :pm]})
    end

    policy action(:decide) do
      authorize_if({Noa.Work.Checks.ActorInOrg, roles: [:org_admin, :pm]})
      authorize_if(expr(owner.membership.user_id == ^actor(:id)))
    end
  end
end
