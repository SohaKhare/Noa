defmodule NoaWeb.ConnCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest
      import NoaWeb.ConnCase
      @endpoint NoaWeb.Endpoint
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Noa.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    {:ok, conn: json_conn()}
  end

  def json_conn do
    Phoenix.ConnTest.build_conn()
    |> Plug.Conn.put_req_header("accept", "application/json")
    |> Plug.Conn.put_req_header("content-type", "application/json")
  end

  @doc "Creates the superadmin directly, as `mix noa.superadmin` does."
  def superadmin!(email \\ "root@noa.test") do
    Noa.Accounts.User
    |> Ash.Changeset.for_create(:create_with_password, %{
      email: email,
      name: "Saish",
      is_superadmin: true,
      password: "superadmin-pass-1"
    })
    |> Ash.create!(authorize?: false)
  end

  @doc "A conn signed in as `user` through the session, like the browser."
  def signed_in(user) do
    json_conn()
    |> Phoenix.ConnTest.init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(Noa.Accounts.with_session_token(user))
  end

  @doc "Accepts an invite url's token and returns the new user."
  def accept!(url, name, password \\ "member-pass-123") do
    token = url |> String.split("/invite/") |> List.last()
    {:ok, user} = Noa.Orgs.accept_invite(token, %{"name" => name, "password" => password})
    user
  end
end
