defmodule Noa.Work.Project do
  @moduledoc "A project, such as Veriq. `key` is the seed id (\"veriq\"); `lead` is the person who approves changes to it."
  use Ash.Resource,
    otp_app: :noa,
    domain: Noa.Work,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("projects")
    repo(Noa.Repo)

    references do
      reference(:org, on_delete: :delete)
      reference(:lead, on_delete: :nilify)
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:key, :string, allow_nil?: false, public?: true)
    attribute(:name, :string, allow_nil?: false, public?: true)
    attribute(:about, :string, public?: true)
    attribute(:repo, :string, public?: true)

    attribute(:status, :atom,
      constraints: [one_of: [:active, :paused, :done]],
      default: :active,
      allow_nil?: false,
      public?: true
    )

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to(:org, Noa.Orgs.Org, allow_nil?: false, attribute_writable?: true, public?: true)
    belongs_to(:lead, Noa.Work.Person, attribute_writable?: true, public?: true)
    has_many(:aliases, Noa.Work.ProjectAlias)
    has_many(:allocations, Noa.Work.Allocation)
    has_many(:tasks, Noa.Work.Task)
  end

  identities do
    identity(:unique_key, [:org_id, :key])
  end

  changes do
    change({Noa.Events.Record, name: "project"}, on: [:create, :update, :destroy])
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:key, :name, :about, :repo, :status, :org_id, :lead_id])
    end

    update :update do
      accept([:name, :about, :repo, :status, :lead_id])
    end
  end

  policies do
    bypass actor_attribute_equals(:is_superadmin, true) do
      authorize_if(always())
    end

    policy action_type(:read) do
      authorize_if(expr(exists(org.memberships, user_id == ^actor(:id))))
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if({Noa.Work.Checks.ActorInOrg, roles: [:org_admin, :pm]})
    end
  end
end
