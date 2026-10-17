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

    # Notification preferences (2.15). Delivery (2.9, 2.21) reads these through
    # `Noa.Work.notify_target/1` and `Noa.Work.quiet?/2`.
    attribute(:notify_via, :atom,
      constraints: [one_of: [:whatsapp, :discord, :email, :in_app]],
      allow_nil?: false,
      default: :in_app,
      public?: true
    )

    attribute(:phone, :string, public?: true, constraints: [match: ~r/^\+[1-9]\d{7,14}$/])
    attribute(:digest_at, :time, public?: true)
    attribute(:quiet_from, :time, public?: true)
    attribute(:quiet_to, :time, public?: true)
    # Minutes east of UTC; 330 is IST.
    attribute(:utc_offset, :integer, allow_nil?: false, default: 330, public?: true, constraints: [min: -720, max: 840])
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

    # Anyone can set their own; admins and PMs can set anyone's.
    update :notifications do
      accept([:notify_via, :phone, :digest_at, :quiet_from, :quiet_to, :utc_offset])
    end
  end

  policies do
    bypass actor_attribute_equals(:is_superadmin, true) do
      authorize_if(always())
    end

    policy action_type(:read) do
      authorize_if(expr(exists(org.memberships, user_id == ^actor(:id))))
    end

    policy action([:create, :update, :destroy]) do
      authorize_if({Noa.Work.Checks.ActorInOrg, roles: [:org_admin, :pm]})
    end

    policy action(:notifications) do
      authorize_if(expr(membership.user_id == ^actor(:id)))
      authorize_if({Noa.Work.Checks.ActorInOrg, roles: [:org_admin, :pm]})
    end
  end
end
