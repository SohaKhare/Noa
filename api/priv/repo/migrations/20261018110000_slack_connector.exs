defmodule Noa.Repo.Migrations.SlackConnector do
  @moduledoc "Prevents the same provider channel from being mapped twice inside one workspace."
  use Ecto.Migration

  def change do
    create(
      unique_index(:channels, [:org_id, :platform, :external_id],
        name: :channels_unique_external_id_index,
        where: "external_id is not null"
      )
    )
  end
end
