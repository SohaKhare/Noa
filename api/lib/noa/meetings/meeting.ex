defmodule Noa.Meetings.Meeting do
  @moduledoc "Consented meeting sessions and reviewed minutes. The graph still uses existing Episode/Task/Decision nodes."
  use Ash.Resource,
    otp_app: :noa,
    domain: Noa.Meetings,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("meetings")
    repo(Noa.Repo)

    custom_indexes do
      index([:org_id, :inserted_at])
    end

    references do
      reference(:org, on_delete: :delete)
      reference(:project, on_delete: :delete)
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:platform, :atom, constraints: [one_of: [:discord, :meet]], allow_nil?: false, public?: true)
    attribute(:external_id, :string, constraints: [max_length: 200], allow_nil?: false, public?: true)
    attribute(:title, :string, constraints: [max_length: 200], allow_nil?: false, public?: true)

    attribute(:status, :atom,
      constraints: [one_of: [:awaiting_consent, :recording, :processing, :review, :failed, :cancelled]],
      default: :awaiting_consent,
      allow_nil?: false,
      public?: true
    )

    attribute(:source, :map, default: %{}, allow_nil?: false, public?: true)
    attribute(:participant_ids, {:array, :uuid}, default: [], allow_nil?: false, public?: true)
    attribute(:consented_ids, {:array, :uuid}, default: [], allow_nil?: false, public?: true)
    # A read cache. Individual utterances are the message.received events of record.
    attribute(:transcript, {:array, :map}, default: [], allow_nil?: false)
    attribute(:minutes, :map, public?: true)
    attribute(:error_code, :string, public?: true)
    create_timestamp(:inserted_at, public?: true)
    update_timestamp(:updated_at, public?: true)
  end

  relationships do
    belongs_to(:org, Noa.Orgs.Org, allow_nil?: false, attribute_writable?: true, public?: true)
    belongs_to(:project, Noa.Work.Project, allow_nil?: false, attribute_writable?: true, public?: true)
    belongs_to(:created_by, Noa.Accounts.User, allow_nil?: false, attribute_writable?: true, public?: true)
  end

  identities do
    identity(:external_meeting, [:org_id, :platform, :external_id])
  end

  actions do
    defaults([:read])

    create :create do
      accept([:org_id, :project_id, :created_by_id, :platform, :external_id, :title, :source, :participant_ids])
    end

    update :update do
      accept([:status, :source, :consented_ids, :transcript, :minutes, :error_code])
      require_atomic?(false)
    end

    update :consent do
      accept([:consented_ids])
      require_atomic?(false)
    end
  end

  changes do
    change({Noa.Events.Record, name: "meeting"})
  end

  policies do
    bypass actor_attribute_equals(:is_superadmin, true) do
      authorize_if(always())
    end

    policy action_type(:read) do
      authorize_if(expr(exists(org.memberships, user_id == ^actor(:id))))
    end

    policy action_type(:create) do
      authorize_if({Noa.Work.Checks.ActorInOrg, roles: [:org_admin, :pm]})
    end

    policy action(:update) do
      authorize_if({Noa.Work.Checks.ActorInOrg, roles: [:org_admin, :pm]})
    end

    policy action(:consent) do
      authorize_if(
        expr(
          status == :awaiting_consent and ^actor(:id) in participant_ids and
            exists(org.memberships, user_id == ^actor(:id))
        )
      )
    end
  end
end
