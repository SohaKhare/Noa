defmodule Noa.Orgs.Invite do
  @moduledoc """
  An emailed, one-time invite to an org (1.5). Only the SHA-256 of the token is stored.
  Org admins (or a superadmin) create and revoke invites; accepting is done by whoever
  holds the token, through `Noa.Orgs.accept_invite/2`.
  """
  use Ash.Resource,
    otp_app: :noa,
    domain: Noa.Orgs,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("invites")
    repo(Noa.Repo)

    references do
      reference(:org, on_delete: :delete)
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:email, :ci_string, allow_nil?: false, public?: true)
    attribute(:role, :atom, constraints: [one_of: Noa.Orgs.Membership.roles()], allow_nil?: false, public?: true)
    attribute(:title, :string, public?: true)
    attribute(:token_hash, :string, allow_nil?: false, sensitive?: true)

    attribute(:status, :atom,
      constraints: [one_of: [:pending, :accepted, :revoked]],
      default: :pending,
      allow_nil?: false,
      public?: true
    )

    attribute(:expires_at, :utc_datetime_usec, allow_nil?: false, public?: true)
    attribute(:accepted_at, :utc_datetime_usec, public?: true)
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to(:org, Noa.Orgs.Org, allow_nil?: false, attribute_writable?: true, public?: true)
    belongs_to(:invited_by, Noa.Accounts.User, attribute_writable?: true, public?: true)
    belongs_to(:accepted_by, Noa.Accounts.User, attribute_writable?: true, public?: true)
  end

  actions do
    defaults([:read])

    create :create do
      accept([:email, :role, :title, :token_hash, :expires_at, :org_id, :invited_by_id])
    end

    update :accept do
      accept([:accepted_by_id])
      change(set_attribute(:status, :accepted))
      change(set_attribute(:accepted_at, &DateTime.utc_now/0))
    end

    update :revoke do
      accept([])
      change(set_attribute(:status, :revoked))
    end
  end

  policies do
    bypass actor_attribute_equals(:is_superadmin, true) do
      authorize_if(always())
    end

    policy action_type(:create) do
      authorize_if(Noa.Orgs.Checks.ActorAdminsOrg)
    end

    policy action_type([:read, :update]) do
      authorize_if(expr(exists(org.memberships, user_id == ^actor(:id) and role == :org_admin)))
    end
  end
end
