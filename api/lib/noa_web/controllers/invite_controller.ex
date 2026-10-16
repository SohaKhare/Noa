defmodule NoaWeb.InviteController do
  @moduledoc "The invite page: show who is invited where, then create the account and sign in."
  use NoaWeb, :controller
  alias AshAuthentication.Plug.Helpers

  def show(conn, %{"token" => token}) do
    with {:ok, invite} <- Noa.Orgs.get_invite(token) do
      json(conn, %{
        invite: %{
          email: to_string(invite.email),
          role: invite.role,
          title: invite.title,
          expires_at: invite.expires_at,
          org: %{name: invite.org.name},
          has_account: has_account?(invite.email)
        }
      })
    end
  end

  def accept(conn, %{"token" => token} = params) do
    with {:ok, user} <- Noa.Orgs.accept_invite(token, Map.take(params, ["name", "password"])) do
      conn
      |> Helpers.store_in_session(Noa.Accounts.with_session_token(user))
      |> configure_session(renew: true)
      |> json(%{user: Payload.user(user)})
    end
  end

  defp has_account?(email) do
    Noa.Accounts.User
    |> Ash.Query.for_read(:get_by_email, %{email: email})
    |> Ash.read_one!(authorize?: false)
    |> Kernel.!=(nil)
  end
end
