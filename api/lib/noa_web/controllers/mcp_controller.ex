defmodule NoaWeb.MCPController do
  @moduledoc "The MCP endpoint (3.6): Streamable HTTP, one JSON-RPC message per POST, JSON replies. See `Noa.MCP`."
  use NoaWeb, :controller

  def post(conn, params) do
    user = conn.assigns.current_user
    org_id = conn.assigns.mcp_org_id

    case params do
      # A JSON array arrives under "_json": answer each request, skip notifications.
      %{"_json" => messages} when is_list(messages) ->
        replies = messages |> Enum.map(&Noa.MCP.handle(&1, user, org_id)) |> Enum.reject(&(&1 == :accepted))
        if replies == [], do: send_resp(conn, 202, ""), else: json(conn, replies)

      message ->
        case Noa.MCP.handle(message, user, org_id) do
          :accepted -> send_resp(conn, 202, "")
          reply -> json(conn, reply)
        end
    end
  end

  # No server-to-client stream: clients fall back to plain POSTs.
  def get(conn, _params), do: conn |> put_resp_header("allow", "POST") |> send_resp(405, "")
end
