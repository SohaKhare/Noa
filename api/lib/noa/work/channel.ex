defmodule Noa.Work.Channel do
  @moduledoc """
  A consented source and the project it maps to (`MAPS_TO`). Chat DMs are never read;
  the explicitly configured Gmail support INBOX is a separate workspace-wide source. `split: true` routes each message on its own, for
  channels like #dev that cover several projects.
  """
  use Ash.Resource,
    otp_app: :noa,
    domain: Noa.Work,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("channels")
    repo(Noa.Repo)
    identity_wheres_to_sql(unique_external_id: "external_id is not null")

    references do
      reference(:org, on_delete: :delete)
      reference(:project, on_delete: :nilify)
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:platform, :atom,
      constraints: [one_of: [:discord, :slack, :whatsapp, :email]],
      allow_nil?: false,
      public?: true
    )

    attribute(:name, :string, allow_nil?: false, public?: true)
    attribute(:external_id, :string, public?: true)
    attribute(:split, :boolean, allow_nil?: false, default: false, public?: true)
    attribute(:read, :boolean, allow_nil?: false, default: true, public?: true)
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to(:org, Noa.Orgs.Org, allow_nil?: false, attribute_writable?: true, public?: true)
    belongs_to(:project, Noa.Work.Project, attribute_writable?: true, public?: true)
  end

  identities do
    identity(:unique_name, [:org_id, :platform, :name])

    identity(:unique_external_id, [:org_id, :platform, :external_id], where: expr(not is_nil(external_id)))
  end

  changes do
    change({Noa.Events.Record, name: "channel"}, on: [:create, :update, :destroy])
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:platform, :name, :external_id, :split, :read, :org_id, :project_id])
    end

    update :update do
      accept([:name, :external_id, :split, :read, :project_id])
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
      authorize_if({Noa.Work.Checks.ActorInOrg, roles: [:org_admin]})
    end
  end
end
