defmodule Noa.Repo.Migrations.LlmCalls do
  @moduledoc "LLM usage (1.3): one row per model call, for cost and failures in the superadmin console."
  use Ecto.Migration

  def change do
    create table(:llm_calls) do
      add(:org_id, references(:orgs, type: :uuid, on_delete: :delete_all))
      add(:operation, :text, null: false)
      add(:model, :text, null: false)
      add(:ms, :integer, null: false)
      add(:ok, :boolean, null: false)
      add(:error, :text)
      add(:input_chars, :integer, null: false, default: 0)
      add(:output_chars, :integer, null: false, default: 0)
      add(:inserted_at, :utc_datetime_usec, null: false, default: fragment("now()"))
    end

    create(index(:llm_calls, [:org_id, :inserted_at]))
  end
end
