defmodule Noa.MCP do
  @moduledoc """
  Noa's MCP server (3.6): a coding agent (Claude Code, Cursor, any MCP client) connects
  with a personal token (`Noa.MCP.Tokens`) and gets the project's context live from the
  FalkorDB graph instead of a file that goes stale.

  Transport: Streamable HTTP, one JSON-RPC message per POST, JSON responses (no
  streaming). Methods: `initialize`, `notifications/initialized`, `ping`, `tools/list`,
  `tools/call`. Every tool runs as the token's person, through the same functions and
  policies as the web app; writes (`update_task_status`, `assign_task`) follow the lead
  rules and are recorded as changes, and `triage` only files Inbox proposals.
  """
  alias Noa.MCP.Tools

  @versions ["2025-11-25", "2025-06-18", "2025-03-26"]

  @instructions """
  Noa is the team's company brain. Use it for context about the projects you work on:
  start with `project_context` for the project you're in, `my_tasks` for what's assigned,
  and `ask` for anything else (answers cite their sources). `who_knows`, `how_connected`
  and `risks` use graph algorithms over the team's work. Use `update_task_status` when
  you start or finish a task. To get work carried: `suggest_owner` ranks who should take
  a task (with the graph route), `assign_task` gives it to them, and `triage` (leads)
  files owner proposals for work nobody is carrying.
  """

  @doc "Handles one JSON-RPC message for `user` in `org_id`. Returns a reply map, or `:accepted` for notifications."
  def handle(%{"jsonrpc" => "2.0", "method" => method} = msg, user, org_id) do
    id = msg["id"]
    params = msg["params"] || %{}

    case {method, id} do
      {"notifications/" <> _, _} ->
        :accepted

      {"initialize", _} ->
        requested = params["protocolVersion"]

        result(id, %{
          protocolVersion: if(requested in @versions, do: requested, else: hd(@versions)),
          capabilities: %{tools: %{listChanged: false}},
          serverInfo: %{name: "noa", title: "Noa", version: "0.1.0"},
          instructions: @instructions
        })

      {"ping", _} ->
        result(id, %{})

      {"tools/list", _} ->
        result(id, %{tools: Tools.definitions()})

      {"tools/call", _} ->
        case Tools.call(params["name"], params["arguments"] || %{}, user, org_id) do
          {:ok, text} -> result(id, %{content: [%{type: "text", text: text}], isError: false})
          {:error, text} -> result(id, %{content: [%{type: "text", text: text}], isError: true})
          :unknown -> error(id, -32602, "Unknown tool: #{params["name"]}")
        end

      _ ->
        error(id, -32601, "Method not found: #{method}")
    end
  end

  def handle(msg, _user, _org_id), do: error(msg["id"], -32600, "Invalid request")

  defp result(id, result), do: %{jsonrpc: "2.0", id: id, result: result}
  defp error(id, code, message), do: %{jsonrpc: "2.0", id: id, error: %{code: code, message: message}}
end
