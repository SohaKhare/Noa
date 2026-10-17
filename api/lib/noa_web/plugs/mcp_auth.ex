defmodule NoaWeb.Plugs.MCPAuth do
  @moduledoc "MCP requests (3.6) carry a personal token: `Authorization: Bearer noa_…`. Sets the person and workspace, or answers 401."
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, user, org_id} <- Noa.MCP.Tokens.authenticate(String.trim(token)) do
      conn |> assign(:current_user, user) |> assign(:mcp_org_id, org_id)
    else
      _ ->
        conn
        |> put_resp_header("www-authenticate", ~s(Bearer realm="noa", error="invalid_token"))
        |> put_resp_content_type("application/json")
        |> send_resp(
          401,
          ~s({"error":"unauthorized","message":"Create a personal token on your Agent pack page in Noa."})
        )
        |> halt()
    end
  end
end
