defmodule Noa.Repo.Migrations.McpTokens do
  @moduledoc "Personal MCP tokens (3.22): one person, one workspace; only the hash is stored."
  use Ecto.Migration

  def change do
    create table(:mcp_tokens, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:org_id, references(:orgs, type: :uuid, on_delete: :delete_all), null: false)
      add(:user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false)
      add(:name, :text, null: false)
      add(:token_hash, :binary, null: false)
      add(:last_used_at, :utc_datetime_usec)
      add(:revoked_at, :utc_datetime_usec)
      add(:inserted_at, :utc_datetime_usec, null: false, default: fragment("now()"))
    end

    create(unique_index(:mcp_tokens, [:token_hash]))
    create(index(:mcp_tokens, [:org_id, :user_id]))
  end
end
