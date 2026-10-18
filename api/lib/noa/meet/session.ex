defmodule Noa.Meet.Session do
  @moduledoc "Provider session for a visible Google Meet bot; imported minutes use Noa.Meetings."
  use Ash.Resource,
    otp_app: :noa,
    domain: Noa.Meet,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("google_meet_sessions")
    repo(Noa.Repo)

    references do
      reference(:org, on_delete: :delete)
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:org_id, :uuid, allow_nil?: false, public?: true)
    attribute(:organizer_id, :uuid, public?: true)
    attribute(:attendee_bot_id, :string, public?: true)
    attribute(:meeting_url, :string, allow_nil?: false, public?: true)

    attribute(:status, :atom,
      constraints: [one_of: [:joining, :running, :stopped, :ready, :imported, :failed]],
      allow_nil?: false,
      public?: true
    )

    attribute(:consent_at, :utc_datetime_usec, allow_nil?: false, public?: true)
    attribute(:transcript, :map, default: %{"lines" => []}, allow_nil?: false, public?: true)
    attribute(:imported_meeting_id, :uuid, public?: true)
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to(:org, Noa.Orgs.Org, allow_nil?: false, attribute_writable?: true, public?: true)
  end

  actions do
    defaults([:read])

    create :create do
      accept([:org_id, :organizer_id, :meeting_url, :consent_at, :status])
    end

    update :advance do
      accept([:attendee_bot_id, :status, :transcript, :imported_meeting_id])
      require_atomic?(false)
    end
  end

  changes do
    change({Noa.Events.Record, name: "google_meet_bot"}, on: [:create, :update])
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
