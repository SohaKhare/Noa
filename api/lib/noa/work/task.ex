defmodule Noa.Work.Task do
  @moduledoc """
  A card on a project's board. `source` is where it came from (platform, channel,
  author, quote, time), so every task cites its message. Anyone in the org but a guest
  can create and move tasks.
  """
  use Ash.Resource,
    otp_app: :noa,
    domain: Noa.Work,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @statuses [:todo, :in_progress, :blocked, :done]
  def statuses, do: @statuses

  postgres do
    table("tasks")
    repo(Noa.Repo)

    references do
      reference(:org, on_delete: :delete)
      reference(:project, on_delete: :delete)
      reference(:owner, on_delete: :nilify)
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:title, :string, allow_nil?: false, public?: true)
    attribute(:detail, :string, public?: true)
    attribute(:status, :atom, constraints: [one_of: @statuses], default: :todo, allow_nil?: false, public?: true)
    attribute(:due_on, :date, public?: true)
    attribute(:blocked_reason, :string, public?: true)
    attribute(:source, :map, public?: true)
    attribute(:done_at, :utc_datetime_usec, public?: true)
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to(:org, Noa.Orgs.Org, allow_nil?: false, attribute_writable?: true, public?: true)
    belongs_to(:project, Noa.Work.Project, allow_nil?: false, attribute_writable?: true, public?: true)
    belongs_to(:owner, Noa.Work.Person, attribute_writable?: true, public?: true)
    belongs_to(:created_by, Noa.Accounts.User, attribute_writable?: true, public?: true)
  end

  changes do
    change({Noa.Events.Record, name: "task"}, on: [:create, :update, :destroy])
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:title, :detail, :status, :due_on, :source, :org_id, :project_id, :owner_id, :created_by_id])
      change(Noa.Work.Changes.StampDone)
    end

    update :update do
      accept([:title, :detail, :status, :due_on, :blocked_reason, :owner_id, :project_id])
      require_atomic?(false)
      change(Noa.Work.Changes.StampDone)
    end
  end

  policies do
    bypass actor_attribute_equals(:is_superadmin, true) do
      authorize_if(always())
    end

    policy action_type(:read) do
      authorize_if(expr(exists(org.memberships, user_id == ^actor(:id))))
    end

    policy action_type([:create, :update]) do
      authorize_if(Noa.Work.Checks.ActorInOrg)
    end

    policy action_type(:destroy) do
      authorize_if({Noa.Work.Checks.ActorInOrg, roles: [:org_admin, :pm]})
    end
  end
end
