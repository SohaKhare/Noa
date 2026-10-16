defmodule Noa.Repo.Migrations.AddOban do
  @moduledoc "Oban's jobs table, for extraction (1.17) and later jobs."
  use Ecto.Migration

  def up, do: Oban.Migration.up()
  def down, do: Oban.Migration.down(version: 1)
end
