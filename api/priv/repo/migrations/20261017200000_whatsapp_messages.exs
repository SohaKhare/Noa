defmodule Noa.Repo.Migrations.WhatsappMessages do
  @moduledoc "WhatsApp (1.15): every message Noa sends or receives, for threading replies, retries and the outbox view."
  use Ecto.Migration

  def change do
    create table(:whatsapp_messages, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:org_id, references(:orgs, type: :uuid, on_delete: :delete_all))
      add(:person_id, references(:people, type: :uuid, on_delete: :nilify_all))
      add(:direction, :text, null: false)
      add(:phone, :text, null: false)
      add(:kind, :text, null: false)
      add(:body, :text)
      add(:buttons, :map)
      add(:context, :map, null: false, default: %{})
      add(:wa_message_id, :text)
      add(:status, :text, null: false)
      add(:error, :text)
      add(:inserted_at, :utc_datetime_usec, null: false, default: fragment("now()"))
    end

    create(index(:whatsapp_messages, [:org_id, :inserted_at]))
    create(index(:whatsapp_messages, [:phone, :inserted_at]))
    create(unique_index(:whatsapp_messages, [:wa_message_id], where: "wa_message_id is not null"))
  end
end
