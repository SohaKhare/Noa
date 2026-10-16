defmodule Noa.Work.ProjectAlias do
  @moduledoc "A name people use in chat for a project (\"the reports app\" for Veriq). Routing reads these (1.16)."
  use Ash.Resource,
    otp_app: :noa,
    domain: Noa.Work,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("project_aliases")
    repo(Noa.Repo)

    references do
      reference(:org, on_delete: :delete)
      reference(:project, on_delete: :delete)
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:alias, :ci_string, allow_nil?: false, public?: true)
    create_timestamp(:inserted_at)
  end

  relationships do
    belongs_to(:org, Noa.Orgs.Org, allow_nil?: false, attribute_writable?: true, public?: true)
    belongs_to(:project, Noa.Work.Project, allow_nil?: false, attribute_writable?: true, public?: true)
  end

  identities do
    identity(:unique_alias, [:org_id, :alias])
  end

  changes do
    change({Noa.Events.Record, name: "alias"}, on: [:create, :update, :destroy])
  end

  actions do
    defaults([:read, :destroy, create: [:alias, :org_id, :project_id]])
  end

  policies do
    bypass actor_attribute_equals(:is_superadmin, true) do
      authorize_if(always())
    end

    policy action_type(:read) do
      authorize_if(expr(exists(org.memberships, user_id == ^actor(:id))))
    end

    policy action_type([:create, :destroy]) do
      authorize_if({Noa.Work.Checks.ActorInOrg, roles: [:org_admin, :pm]})
    end
  end
end
