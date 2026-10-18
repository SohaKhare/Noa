defmodule Noa.Work.Identity do
  @moduledoc """
  A chat or git account (a Discord or Slack user, a WhatsApp number) and the person behind it
  (1.11). Ingest calls `Noa.Work.identify/4` for every author; an unknown account is
  stored with no person so an admin can link it later.
  """
  use Ash.Resource,
    otp_app: :noa,
    domain: Noa.Work,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("identities")
    repo(Noa.Repo)

    references do
      reference(:org, on_delete: :delete)
      reference(:person, on_delete: :nilify)
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:platform, :atom,
      constraints: [one_of: [:discord, :slack, :whatsapp, :meet, :github, :email]],
      allow_nil?: false,
      public?: true
    )

    attribute(:external_id, :string, allow_nil?: false, public?: true)
    attribute(:display_name, :string, public?: true)
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to(:org, Noa.Orgs.Org, allow_nil?: false, attribute_writable?: true, public?: true)
    belongs_to(:person, Noa.Work.Person, attribute_writable?: true, public?: true)
  end

  identities do
    identity(:unique_account, [:org_id, :platform, :external_id])
  end

  changes do
    change({Noa.Events.Record, name: "identity"}, on: [:create, :update, :destroy])
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:platform, :external_id, :display_name, :org_id, :person_id])
    end

    update :update do
      accept([:display_name, :person_id])
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
