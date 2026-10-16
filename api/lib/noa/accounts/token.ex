defmodule Noa.Accounts.Token do
  @moduledoc false
  use Ash.Resource,
    otp_app: :noa,
    domain: Noa.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication.TokenResource]

  postgres do
    table("tokens")
    repo(Noa.Repo)
  end
end
