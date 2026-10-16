defmodule Noa.Repo.Migrations.EventLog do
  @moduledoc "The event log (1.8) and the projector's position (1.10). Plain Ecto: `Noa.Events` does not go through Ash."
  use Ecto.Migration

  def change do
    create table(:events, primary_key: false) do
      add(:id, :bigserial, primary_key: true)
      add(:org_id, references(:orgs, type: :uuid, on_delete: :delete_all), null: false)
      add(:type, :text, null: false)
      add(:subject_id, :uuid)
      add(:data, :map, null: false, default: %{})
      add(:actor_id, :uuid)
      add(:key, :text)
      add(:occurred_at, :utc_datetime_usec, null: false)
      add(:inserted_at, :utc_datetime_usec, null: false, default: fragment("now()"))
    end

    create(index(:events, [:org_id, :id]))
    create(index(:events, [:subject_id]))
    create(unique_index(:events, [:org_id, :key], where: "key is not null"))

    create table(:projections, primary_key: false) do
      add(:name, :text, primary_key: true)
      add(:position, :bigint, null: false, default: 0)
      add(:updated_at, :utc_datetime_usec, null: false, default: fragment("now()"))
    end
  end
end
