defmodule Noa.Repo do
  use AshPostgres.Repo, otp_app: :noa

  @impl true
  def installed_extensions, do: ["ash-functions", "citext"]

  @impl true
  def min_pg_version, do: %Version{major: 16, minor: 0, patch: 0}
end
