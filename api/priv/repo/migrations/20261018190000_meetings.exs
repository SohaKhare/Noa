defmodule Noa.Repo.Migrations.Meetings do
  use Ecto.Migration

  def change do
    create table(:meetings, primary_key: false) do
      add(:id, :uuid, primary_key: true, default: fragment("gen_random_uuid()"))
      add(:org_id, references(:orgs, type: :uuid, on_delete: :delete_all), null: false)
      add(:project_id, references(:projects, type: :uuid, on_delete: :delete_all), null: false)
      add(:created_by_id, references(:users, type: :uuid), null: false)
      add(:platform, :text, null: false)
      add(:external_id, :text, null: false)
      add(:title, :text, null: false)
      add(:status, :text, null: false, default: "awaiting_consent")
      add(:source, :map, null: false, default: %{})
      add(:participant_ids, {:array, :uuid}, null: false, default: [])
      add(:consented_ids, {:array, :uuid}, null: false, default: [])
      add(:transcript, {:array, :map}, null: false, default: [])
      add(:minutes, :map)
      add(:error_code, :text)
      add(:inserted_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')"))
      add(:updated_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')"))
    end

    create(unique_index(:meetings, [:org_id, :platform, :external_id], name: :meetings_external_meeting_index))
    create(index(:meetings, [:org_id, :inserted_at]))
  end
end
