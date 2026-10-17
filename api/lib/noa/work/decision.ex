defmodule Noa.Work.Decision do
  @moduledoc """
  A choice the team made, or a conclusion it reached (2.4), with the message it came
  from. Created when a decision proposal is approved. A newer decision can supersede an
  older one: the old one stays, marked `superseded` and pointing at its replacement, so
  the history of what was decided is never lost.
  """
  use Ash.Resource,
    otp_app: :noa,
    domain: Noa.Work,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("decisions")
    repo(Noa.Repo)

    references do
      reference(:org, on_delete: :delete)
      reference(:project, on_delete: :nilify)
      reference(:made_by, on_delete: :nilify)
      reference(:superseded_by, on_delete: :nilify)
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:statement, :string, allow_nil?: false, public?: true)
    attribute(:kind, :atom, constraints: [one_of: [:decision, :conclusion]], default: :decision, public?: true)

    attribute(:status, :atom,
      constraints: [one_of: [:active, :superseded]],
      default: :active,
      allow_nil?: false,
      public?: true
    )

    # Task ids this decision changes.
    attribute(:affects, {:array, :uuid}, allow_nil?: false, default: [], public?: true)
    attribute(:source, :map, public?: true)
    create_timestamp(:inserted_at, public?: true)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to(:org, Noa.Orgs.Org, allow_nil?: false, attribute_writable?: true, public?: true)
    belongs_to(:project, Noa.Work.Project, attribute_writable?: true, public?: true)
    belongs_to(:made_by, Noa.Work.Person, attribute_writable?: true, public?: true)
    belongs_to(:approved_by, Noa.Accounts.User, attribute_writable?: true, public?: true)
    belongs_to(:superseded_by, __MODULE__, attribute_writable?: true, public?: true)
  end

  changes do
    change({Noa.Events.Record, name: "decision"}, on: [:create, :update, :destroy])
  end

  actions do
    defaults([:read])

    create :create do
      accept([:statement, :kind, :affects, :source, :org_id, :project_id, :made_by_id, :approved_by_id])
    end

    update :supersede do
      accept([:superseded_by_id])
      change(set_attribute(:status, :superseded))
    end
  end

  policies do
    bypass actor_attribute_equals(:is_superadmin, true) do
      authorize_if(always())
    end

    policy action_type(:read) do
      authorize_if(expr(exists(org.memberships, user_id == ^actor(:id))))
    end

    # Decisions are written by Noa when a proposal is approved (the approval is authorized).
    policy action_type([:create, :update]) do
      authorize_if({Noa.Work.Checks.ActorInOrg, roles: [:org_admin, :pm]})
    end
  end
end
