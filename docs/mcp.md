# Noa's MCP server (3.6, 3.22)

Coding agents connect to Noa and pull a project's context live from the FalkorDB graph, instead of reading a `CLAUDE.md` that went stale last week. Every tool runs as the person who owns the token, with the same permissions as the web app.

## Connect

1. In Noa, open **Agent pack** and use **Connect your agent** to create a personal token. It is shown once.
2. Add the server to your agent.

Claude Code:

```sh
claude mcp add --transport http noa https://<your-noa-api>/mcp --header "Authorization: Bearer <token>"
```

Or commit the pack's `.mcp.json` (it holds the address only) and set `NOA_TOKEN` in your environment:

```json
{ "mcpServers": { "noa": { "type": "http", "url": "https://<your-noa-api>/mcp", "headers": { "Authorization": "Bearer ${NOA_TOKEN}" } } } }
```

Locally the address is `http://localhost:4000/mcp`.

## Tools

| Tool | Does | Graph use |
| --- | --- | --- |
| `list_projects` | Projects in the workspace | |
| `project_context` | The project's `CLAUDE.md`, generated now | Project subgraph: people, `KNOWS_ABOUT`, decisions with sources, open work |
| `kt_brief` | The KT brief | Experts from the graph |
| `my_tasks` | Your open tasks with their source messages | |
| `ask` | `@noa`: cited answers | Anchored walks, full-text indexes, PageRank, betweenness, paths |
| `who_knows` | Who knows a project best | Weighted `KNOWS_ABOUT` |
| `how_connected` | Shortest path between two people, projects or tasks | Variable-length path search |
| `decisions` | A project's current decisions with sources | |
| `update_task_status` | Move one of your tasks (the only write) | Recorded as a change; lead rules apply; revertible |

## Protocol

Streamable HTTP: `POST /mcp`, one JSON-RPC 2.0 message (or a list) per request, JSON replies, no server-sent stream (`GET /mcp` answers 405). Protocol versions 2025-11-25, 2025-06-18 and 2025-03-26. Methods: `initialize`, `notifications/initialized`, `ping`, `tools/list`, `tools/call`.

## Security

- Tokens are per person and workspace, 256 random bits, shown once, stored as SHA-256 hashes, listed with last use, and revocable on the pack page.
- A token stops working when it is revoked or when its person leaves the workspace.
- Tools call the same functions and Ash policies as the web app: a guest's agent can read but not change anything, and a token never reaches another workspace.
- 120 requests a minute per person. Writes are limited to task status and recorded with who made them.
- Tests: `api/test/noa_web/mcp_test.exs`.
