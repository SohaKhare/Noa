defmodule NoaWeb.MCPTokenController do
  @moduledoc "Personal MCP tokens (3.22) for the signed-in person in one workspace."
  use NoaWeb, :controller

  alias Noa.MCP.Tokens

  def index(conn, %{"org_id" => org_id}) do
    json(conn, %{tokens: Tokens.list(org_id, conn.assigns.current_user), url: mcp_url()})
  end

  @doc "Creates a token. The plain token is in this response only."
  def create(conn, %{"org_id" => org_id} = params) do
    {:ok, token, row} = Tokens.create(org_id, conn.assigns.current_user, params["name"])
    conn |> put_status(201) |> json(%{token: token, info: row, url: mcp_url()})
  end

  def delete(conn, %{"org_id" => org_id, "id" => id}) do
    with :ok <- Tokens.revoke(org_id, conn.assigns.current_user, id) do
      send_resp(conn, 204, "")
    end
  end

  defp mcp_url, do: Application.fetch_env!(:noa, :api_base_url) <> "/mcp"
end
