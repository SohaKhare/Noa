defmodule Noa.Secrets do
  @moduledoc false
  use AshAuthentication.Secret

  def secret_for([:authentication, :tokens, :signing_secret], Noa.Accounts.User, _opts, _context) do
    Application.fetch_env(:noa, :token_signing_secret)
  end
end
