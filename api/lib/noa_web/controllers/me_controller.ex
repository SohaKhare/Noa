defmodule NoaWeb.MeController do
  use NoaWeb, :controller

  def show(conn, _params), do: json(conn, %{user: Payload.user(conn.assigns.current_user)})

  def update(conn, %{"name" => name}) do
    user = conn.assigns.current_user

    with {:ok, user} <- user |> Ash.Changeset.for_update(:update_profile, %{name: name}, actor: user) |> Ash.update() do
      json(conn, %{user: Payload.user(user)})
    end
  end

  def sign_out(conn, _params) do
    conn |> configure_session(drop: true) |> json(%{ok: true})
  end
end
