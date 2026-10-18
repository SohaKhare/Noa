defmodule Noa.Repo.Migrations.OrgConnectors do
  @moduledoc "Per-workspace connectors (1.18): which Discord server and GitHub secrets belong to a company. Secrets are encrypted."
  use Ecto.Migration

  def change do
    create table(:org_connectors, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:org_id, references(:orgs, type: :uuid, on_delete: :delete_all), null: false)
      add(:kind, :text, null: false)
      add(:external_id, :text)
      add(:secret_enc, :text)
      add(:token_enc, :text)
      add(:connected_by_id, references(:users, type: :uuid, on_delete: :nilify_all))
      add(:inserted_at, :utc_datetime_usec, null: false, default: fragment("now()"))
      add(:updated_at, :utc_datetime_usec, null: false, default: fragment("now()"))
    end

    create(unique_index(:org_connectors, [:org_id, :kind]))
    create(unique_index(:org_connectors, [:kind, :external_id], where: "external_id is not null"))
  end
end
