defmodule NoaWeb.DiscordAccountController do
  use NoaWeb, :controller
  alias Noa.Ingest.Discord.{Accounts, Links}

  def show(conn, %{"org_id" => org_id}) do
    with {:ok, discord_id} <- Accounts.current(org_id, conn.assigns.current_user),
         do: json(conn, %{discord_id: discord_id})
  end

  def create(conn, %{"org_id" => org_id} = params) do
    with {:ok, discord_id} <- Links.claim(org_id, params["code"], conn.assigns.current_user),
         do: json(conn, %{discord_id: discord_id})
  end

  def delete(conn, %{"org_id" => org_id}) do
    with {:ok, _} <- Accounts.unlink(org_id, conn.assigns.current_user),
         do: json(conn, %{discord_id: nil})
  end
end
