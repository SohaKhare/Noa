defmodule Noa.Work.Person do
  @moduledoc """
  Someone who does work in an org, whether or not they have signed in yet (1.11).
  Chat authors, task owners and allocations point here. `key` is the seed id ("ve");
  `handles` are chat and git names that resolve to this person. `membership` links the
  person to their account once they join.
  """
  use Ash.Resource,
    otp_app: :noa,
    domain: Noa.Work,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("people")
    repo(Noa.Repo)

    references do
      reference(:org, on_delete: :delete)
      reference(:membership, on_delete: :nilify)
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:key, :string, allow_nil?: false, public?: true)
    attribute(:name, :string, allow_nil?: false, public?: true)
    attribute(:title, :string, public?: true)
    attribute(:email, :ci_string, public?: true)
    attribute(:handles, {:array, :string}, allow_nil?: false, default: [], public?: true)
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to(:org, Noa.Orgs.Org, allow_nil?: false, attribute_writable?: true, public?: true)
    belongs_to(:membership, Noa.Orgs.Membership, attribute_writable?: true, public?: true)
    has_many(:allocations, Noa.Work.Allocation)
  end

  identities do
    identity(:unique_key, [:org_id, :key])
  end

  changes do
    change({Noa.Events.Record, name: "person"}, on: [:create, :update, :destroy])
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:key, :name, :title, :email, :handles, :org_id, :membership_id])
    end

    update :update do
      accept([:name, :title, :email, :handles, :membership_id])
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
