defmodule Noa.Repo.Migrations.GoogleMeetSessions do
  use Ecto.Migration

  def change do
    create table(:google_meet_sessions, primary_key: false) do
      add(:id, :uuid, primary_key: true, default: fragment("gen_random_uuid()"))
      add(:org_id, references(:orgs, type: :uuid, on_delete: :delete_all), null: false)
      add(:organizer_id, references(:users, type: :uuid, on_delete: :nilify_all))
      add(:attendee_bot_id, :text)
      add(:meeting_url, :text, null: false)
      add(:status, :text, null: false)
      add(:consent_at, :utc_datetime_usec, null: false)
      add(:transcript, :map, null: false, default: %{"lines" => []})
      add(:imported_meeting_id, references(:meetings, type: :uuid, on_delete: :nilify_all))
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:google_meet_sessions, [:attendee_bot_id], where: "attendee_bot_id IS NOT NULL"))
    create(index(:google_meet_sessions, [:org_id, :inserted_at]))
  end
end
