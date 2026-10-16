defmodule Noa.Work.Allocation do
  @moduledoc """
  A person working on a project (`WORKS_ON`): how much of their time, and from when.
  Allocations are never deleted. A shift (3.1) ends one by setting `ends_on` and starts
  another, so history stays.
  """
  use Ash.Resource,
    otp_app: :noa,
    domain: Noa.Work,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("allocations")
    repo(Noa.Repo)

    references do
      reference(:org, on_delete: :delete)
      reference(:person, on_delete: :delete)
      reference(:project, on_delete: :delete)
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:percent, :integer, constraints: [min: 0, max: 100], allow_nil?: false, public?: true)
    attribute(:role, :string, public?: true)
    attribute(:starts_on, :date, allow_nil?: false, default: &Date.utc_today/0, public?: true)
    attribute(:ends_on, :date, public?: true)
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to(:org, Noa.Orgs.Org, allow_nil?: false, attribute_writable?: true, public?: true)
    belongs_to(:person, Noa.Work.Person, allow_nil?: false, attribute_writable?: true, public?: true)
    belongs_to(:project, Noa.Work.Project, allow_nil?: false, attribute_writable?: true, public?: true)
  end

  changes do
    change({Noa.Events.Record, name: "allocation"}, on: [:create, :update, :destroy])
  end

  actions do
    defaults([:read])

    read :current do
      filter(expr(is_nil(ends_on) or ends_on >= today()))
    end

    create :create do
      accept([:percent, :role, :starts_on, :ends_on, :org_id, :person_id, :project_id])
    end

    update :update do
      accept([:percent, :role, :ends_on])
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
      authorize_if({Noa.Work.Checks.ActorInOrg, roles: [:org_admin, :pm]})
    end
  end
end
