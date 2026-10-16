defmodule Noa.Orgs.Org do
  @moduledoc """
  A workspace, such as NotYourIdea. Only a superadmin creates one. `allowed_domains`
  are the work-email domains members may join with.
  """
  use Ash.Resource,
    otp_app: :noa,
    domain: Noa.Orgs,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("orgs")
    repo(Noa.Repo)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, allow_nil?: false, public?: true)
    attribute(:slug, :string, allow_nil?: false, public?: true)
    attribute(:allowed_domains, {:array, :string}, allow_nil?: false, default: [], public?: true)
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    has_many(:memberships, Noa.Orgs.Membership)
    has_many(:invites, Noa.Orgs.Invite)
  end

  identities do
    identity(:unique_slug, [:slug])
  end

  actions do
    defaults([:read])

    create :create do
      accept([:name, :slug, :allowed_domains])
      change(Noa.Orgs.Changes.NormalizeDomains)
      validate(present(:allowed_domains), message: "add at least one work email domain")
    end

    update :update do
      accept([:name, :allowed_domains])
      require_atomic?(false)
      change(Noa.Orgs.Changes.NormalizeDomains)
    end
  end

  policies do
    bypass actor_attribute_equals(:is_superadmin, true) do
      authorize_if(always())
    end

    policy action_type(:read) do
      authorize_if(expr(exists(memberships, user_id == ^actor(:id))))
    end

    policy action_type(:update) do
      authorize_if(expr(exists(memberships, user_id == ^actor(:id) and role == :org_admin)))
    end
  end
end
