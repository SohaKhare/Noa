# Graph Hacks compliance and FalkorDB use

Checked against the rules on [wemakedevs.org/hackathons/falkordb](https://www.wemakedevs.org/hackathons/falkordb) on Oct 17, 2026. Entered track: **03 Company Brain**. Tracks 01 and 02 are allowed too; see "Other tracks".

## Rules

| Rule | How Noa meets it |
| --- | --- |
| "FalkorDB must be the primary graph database, and it must support a central part of the product." | FalkorDB is Noa's knowledge store, one graph per company. Every `@noa` answer, KT brief's people to meet, expert ranking, PageRank, bridge, working group, bus-factor risk, path and the Graph tab are FalkorDB queries. Postgres holds accounts, permissions and the append-only event log the graph is built from. |
| "The graph has to shape what the agent does, not sit on the side." | `@noa` retrieves from the graph (`api/lib/noa/agent/graph.ex`): it walks from the projects and people a question names, runs full-text search over the graph, and calls graph algorithms as tools. Each answer says which graph routes it used. Postgres is only a fallback when the graph is down or not built yet. |
| "The submission and its main FalkorDB implementation must be new work completed during the event." | The repo and all FalkorDB code were written Oct 15 to 18. Tulpa v1 (NYI's earlier product) contributed only patterns: the extraction prompt and windowing, the event-log shape, and the answer generator's rules, each rewritten (see PLAN.md, "Reusing Tulpa v1"). Tulpa v1 never used FalkorDB. |
| "Enter on your own or with up to three others." | Three people: Saish, Soha, Vedant. |
| Coding assistants allowed; you must be able to explain what was built and why. | Design decisions are written down in `docs/` (schema, extraction, security, load test) and PLAN.md. |
| Live deployment preferred; otherwise complete local setup and a working demo video. | Live at app.heynoa.xyz (API, FalkorDB and Postgres on Fly.io; web on Vercel). Local setup in README.md; demo plan in docs/demo.md. |
| AI coding assistants must be disclosed. | Disclosed in README.md, "AI tools disclosure". |

## FalkorDB features in use

| Feature | Where | What it does for the company brain |
| --- | --- | --- |
| Multi-tenant graphs (one graph per company) | `Noa.Graph.name/1` | Each workspace's knowledge is isolated; a rebuild or drop affects one company. |
| Cypher, parameterised | everywhere in `api/lib/noa/graph*` and `agent/graph.ex` | Projector writes, traversals, aggregations. |
| Range indexes on `id` | `Noa.Graph.bootstrap/1` | Fast MERGE in the projector, anchored lookups. |
| Unique constraints on `id` per label | `Noa.Graph.bootstrap/1` | The graph itself refuses a duplicate node, so replays are safe. |
| Full-text indexes (messages, task titles, decisions) | `bootstrap/1`, `Noa.Agent.Graph` | `@noa` finds what people said and what was decided by keyword. |
| Traversals (variable length, OPTIONAL MATCH) | `Noa.Agent.Graph`, `Noa.Graph.View`, `Noa.Work.Brief` | Project → tasks → source messages → authors; decisions → what they affect; citations through `EXTRACTED_FROM`. |
| `algo.pageRank` | `Noa.Graph.Experts.key_people/1`, `@noa` | Who the work runs through (Portfolio, "who" questions). |
| `algo.betweenness` | `Noa.Graph.Experts.bridges/1`, `@noa` | People who connect projects; "who connects…" questions. |
| `algo.WCC` (connected components) | `Noa.Graph.Experts.groups/1` | Working groups: the teams that form around projects. |
| Weighted derived edges (`KNOWS_ABOUT`) | `Noa.Graph.Experts.refresh/1` | Who knows a project best; bus-factor risk; KT people to meet. |
| Shortest paths | `Noa.Graph.View.path/3`, `@noa` | "How is X connected to Y", path highlighting in the Graph tab. |
| MCP server (graph tools for agents) | `Noa.MCP`, `Noa.MCP.Tools` | Coding agents call graph queries and algorithms as tools: project context, `ask`, `who_knows` (`KNOWS_ABOUT`), `how_connected` (paths). |
| Subgraph reads for context packs | `Noa.Packs` | `CLAUDE.md`, `AGENTS.md` and `tasks.md` for coding agents come from the project's subgraph: people, experts, decisions with sources, open work. |
| Code activity in the graph | `Noa.GitHub` | Commits, pull requests and CI runs as nodes on their project and person; they weigh into `KNOWS_ABOUT` and feed each agent pack's recent changes. |
| Vector index | not used | Needs embeddings from a model; planned with the OpenAI key (2.5). |

Notes on the client (falkordb 0.8.2 on FalkorDB 4.10): query options must be a map; `Graph.constraint_create` sends arguments in the wrong order, so constraints use a raw command; there is no undirected `shortestPath`, so paths order variable-length matches by length.

## Track 03 checklist (Company Brain)

| The track asks for | Noa |
| --- | --- |
| One graph of people, teams, projects, documents and decisions | People, working groups, projects, channels, tasks, decisions, messages, change records. Documents (GitHub, Drive) are on the cut list. |
| Pull in docs, tickets and chats | Chats (Discord, WhatsApp), code (GitHub commits, pull requests, CI); tickets are Noa's own tasks. |
| Who owns what, who knows what | Owners and allocations; `KNOWS_ABOUT`, PageRank, betweenness, bus factor. |
| Trace decisions to their source | `EXTRACTED_FROM` on every task and decision; supersession keeps history. |
| Keep knowledge current | Event log → projector within seconds of each commit; change records. |
| Answers with clear sources | Numbered citations on every `@noa` claim, with the graph route that found each. |
| Context for AI agents (the hackathon's theme) | Agent packs give coding agents the project's context from the graph; `@noa` answers from it. |
| An agent that gets work done | Extraction proposes and (when confident) applies tasks and status changes; shifts hand over work; lead approvals. |

## Other tracks

All tracks are allowed. Company Brain is finished end to end; the same product enters the other two:

- **01 Agents That Act on Connected Data.** Noa's triage agent (`Noa.Agent.Triage`) finds work nobody is carrying (no owner, owner left the project, overdue on someone overloaded), ranks who should take it by walking the graph (`WORKS_ON`, `KNOWS_ABOUT`, full-text over finished tasks, `DECIDED → AFFECTS`, open load), and files a proposal that shows the graph route behind each reason. Approving it changes the owner under the lead rules. The same ranking is a button on every task ("Who should own this?"), and coding agents get it over MCP as `suggest_owner`, `assign_task`, `triage` and `risks`, next to `ask`, `who_knows` and `how_connected`. Tests: `test/noa/triage_test.exs`.
- **02 Agent Memory and Coordination.** Episodic, semantic, derived and procedural memory in one per-company graph built from an append-only log; people, ingest and agents write through the same rules; concurrent writers keep one order and a consistent graph. See [memory.md](memory.md); tests: `test/noa/memory_test.exs`.
