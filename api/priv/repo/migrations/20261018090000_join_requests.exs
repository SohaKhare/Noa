defmodule Noa.Repo.Migrations.JoinRequests do
  @moduledoc "Join requests (1.5): someone with a work email asks to join from the workspace's link; an org admin approves."
  use Ecto.Migration

  def change do
    create table(:join_requests, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:org_id, references(:orgs, type: :uuid, on_delete: :delete_all), null: false)
      add(:email, :citext, null: false)
      add(:name, :text, null: false)
      add(:note, :text)
      add(:status, :text, null: false, default: "pending")
      add(:role, :text)
      add(:decided_by_id, references(:users, type: :uuid, on_delete: :nilify_all))
      add(:decided_at, :utc_datetime_usec)
      add(:inserted_at, :utc_datetime_usec, null: false, default: fragment("now()"))
    end

    create(index(:join_requests, [:org_id, :status]))
    create(unique_index(:join_requests, [:org_id, :email], where: "status = 'pending'"))
  end
end
