defmodule Noa.Work.Shift do
  @moduledoc """
  Someone moving from one project to another (3.1). Created by `Noa.Work.shift/3`,
  which ends their old allocation, starts the new one and hands their open tasks to new
  owners, all in one transaction. `handover` records what happened to each task, and
  `routes_until` is how long questions about the old project still go to them.
  A nil project means the bench.
  """
  use Ash.Resource,
    otp_app: :noa,
    domain: Noa.Work,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("shifts")
    repo(Noa.Repo)

    references do
      reference(:org, on_delete: :delete)
      reference(:person, on_delete: :delete)
      reference(:from_project, on_delete: :nilify)
      reference(:to_project, on_delete: :nilify)
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:percent, :integer, constraints: [min: 0, max: 100], allow_nil?: false, public?: true)
    attribute(:starts_on, :date, allow_nil?: false, public?: true)
    attribute(:routes_until, :date, public?: true)
    # [%{"task_id", "title", "to_owner_id"}]; a nil owner means the task is left unassigned.
    attribute(:handover, {:array, :map}, allow_nil?: false, default: [], public?: true)
    attribute(:note, :string, public?: true)
    create_timestamp(:inserted_at, public?: true)
  end

  relationships do
    belongs_to(:org, Noa.Orgs.Org, allow_nil?: false, attribute_writable?: true, public?: true)
    belongs_to(:person, Noa.Work.Person, allow_nil?: false, attribute_writable?: true, public?: true)
    belongs_to(:from_project, Noa.Work.Project, attribute_writable?: true, public?: true)
    belongs_to(:to_project, Noa.Work.Project, attribute_writable?: true, public?: true)
    belongs_to(:created_by, Noa.Accounts.User, attribute_writable?: true, public?: true)
  end

  changes do
    change({Noa.Events.Record, name: "shift"}, on: [:create])
  end

  actions do
    defaults([:read])

    create :create do
      accept([
        :percent,
        :starts_on,
        :routes_until,
        :handover,
        :note,
        :org_id,
        :person_id,
        :from_project_id,
        :to_project_id,
        :created_by_id
      ])
    end
  end

  policies do
    bypass actor_attribute_equals(:is_superadmin, true) do
      authorize_if(always())
    end

    policy action_type(:read) do
      authorize_if(expr(exists(org.memberships, user_id == ^actor(:id))))
    end

    # Moving people is a lead's job: org admins and PMs.
    policy action_type(:create) do
      authorize_if({Noa.Work.Checks.ActorInOrg, roles: [:org_admin, :pm]})
    end
  end
end
