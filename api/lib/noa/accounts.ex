defmodule Noa.Accounts do
  @moduledoc "People who can sign in. Accounts are only created by accepting an org invite (1.4)."
  use Ash.Domain, otp_app: :noa, extensions: [AshAuthentication.Domain]

  @doc """
  Attaches a fresh session token to a user who did not come through a sign-in action
  (for example, someone who just accepted an invite), so they can be stored in the session.
  """
  def with_session_token(user) do
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
    Ash.Resource.put_metadata(user, :token, token)
  end

  resources do
    resource(Noa.Accounts.User)
    resource(Noa.Accounts.Token)
  end
end
