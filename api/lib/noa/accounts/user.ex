defmodule Noa.Accounts.User do
  @moduledoc """
  A person who can sign in. Invite-only: there is no public registration. Accounts are
  created by `Noa.Orgs.accept_invite/2` and, for the first superadmin, by seeds.
  """
  use Ash.Resource,
    otp_app: :noa,
    domain: Noa.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication]

  authentication do
    strategies do
      password :password do
        identity_field(:email)
        hashed_password_field(:hashed_password)
        hash_provider(Noa.Accounts.Pbkdf2HashProvider)
        confirmation_required?(false)
        registration_enabled?(false)

        resettable do
          sender(Noa.Accounts.Senders.PasswordReset)
        end
      end

      magic_link :magic_link do
        identity_field(:email)
        # Existing users only; an unknown email gets the same "check your email" reply.
        registration_enabled?(false)
        prevent_hijacking?(false)
        require_interaction?(false)
        sender(Noa.Accounts.Senders.MagicLink)
      end
    end

    tokens do
      enabled?(true)
      token_resource(Noa.Accounts.Token)
      signing_secret(Noa.Secrets)
      require_token_presence_for_authentication?(false)
    end

    session_identifier(:jti)
  end

  postgres do
    table("users")
    repo(Noa.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:email, :ci_string, allow_nil?: false, public?: true)
    attribute(:name, :string, public?: true)
    attribute(:hashed_password, :string, sensitive?: true)
    attribute(:is_superadmin, :boolean, default: false, allow_nil?: false, public?: true)
    attribute(:confirmed_at, :utc_datetime_usec)

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    has_many(:memberships, Noa.Orgs.Membership)
  end

  identities do
    identity(:unique_email, [:email])
  end

  actions do
    defaults([:read])

    read :get_by_email do
      argument(:email, :ci_string, allow_nil?: false)
      get?(true)
      filter(expr(email == ^arg(:email)))
    end

    create :create_with_password do
      description("Creates an account from an accepted invite, or the first superadmin from seeds.")
      accept([:email, :name, :is_superadmin])
      argument(:password, :string, allow_nil?: false, sensitive?: true)
      validate(string_length(:password, min: 10), message: "must be at least 10 characters")
      change(set_context(%{strategy_name: :password}))
      change(set_attribute(:confirmed_at, &DateTime.utc_now/0))
      change(AshAuthentication.Strategy.Password.HashPasswordChange)
    end

    update :update_profile do
      accept([:name])
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if(always())
    end

    bypass actor_attribute_equals(:is_superadmin, true) do
      authorize_if(always())
    end

    policy action_type(:read) do
      authorize_if(expr(id == ^actor(:id)))
      authorize_if(expr(exists(memberships.org.memberships, user_id == ^actor(:id))))
    end

    policy action(:update_profile) do
      authorize_if(expr(id == ^actor(:id)))
    end
  end
end
