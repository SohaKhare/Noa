defmodule Noa.Orgs.Membership do
  @moduledoc """
  A person in an org, with their role (1.6), title and reporting line (1.22).

  Roles: `org_admin` (runs the org and invites people; for NYI this is the lead, who
  sees the PM side), `pm` (leads projects), `member`, `guest`. Superadmin is a flag on
  the user, not an org role.
  """
  use Ash.Resource,
    otp_app: :noa,
    domain: Noa.Orgs,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @roles [:org_admin, :pm, :member, :guest]
  def roles, do: @roles

  postgres do
    table("memberships")
    repo(Noa.Repo)

    references do
      reference(:org, on_delete: :delete)
      reference(:user, on_delete: :delete)
      reference(:reports_to, on_delete: :nilify)
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:role, :atom, constraints: [one_of: @roles], allow_nil?: false, public?: true)
    attribute(:title, :string, public?: true)
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to(:org, Noa.Orgs.Org, allow_nil?: false, attribute_writable?: true, public?: true)
    belongs_to(:user, Noa.Accounts.User, allow_nil?: false, attribute_writable?: true, public?: true)
    belongs_to(:reports_to, __MODULE__, attribute_writable?: true, public?: true)
  end

  identities do
    identity(:unique_user_org, [:user_id, :org_id])
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:role, :title, :org_id, :user_id])
      upsert?(true)
      upsert_identity(:unique_user_org)
      upsert_fields([])
    end

    update :update do
      accept([:role, :title, :reports_to_id])
    end
  end

  policies do
    bypass actor_attribute_equals(:is_superadmin, true) do
      authorize_if(always())
    end

    policy action_type(:read) do
      authorize_if(expr(exists(org.memberships, user_id == ^actor(:id))))
    end

    policy action_type([:update, :destroy]) do
      authorize_if(expr(exists(org.memberships, user_id == ^actor(:id) and role == :org_admin)))
    end
  end
end
