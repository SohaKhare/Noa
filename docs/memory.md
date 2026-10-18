# Noa as agent memory (Track 02)

Noa is a shared, durable memory for a company, written by people, by chat ingest and by agents, and read by all three. This page maps it onto the track's terms and says how concurrent writers stay consistent.

## Kinds of memory

| Kind | In Noa | Where |
| --- | --- | --- |
| **Episodic**: what happened, when, said by whom | Every chat message (`Episode`), every change record (who changed what, why, approved by whom), every event in the log | `events` table (append-only); `Episode` and `Change` nodes in the graph |
| **Semantic**: what is true now | Tasks with owners and status, decisions (with what they supersede), projects, people, allocations | Postgres rows; `Task`, `Decision`, `Project`, `Person` nodes and their edges |
| **Derived**: what the memory implies | Who knows what (`KNOWS_ABOUT` weights), who the work runs through (PageRank), working groups (WCC), bridges (betweenness), bus-factor risk | Computed in FalkorDB from the semantic and episodic layers |
| **Procedural**: how this team works | Lead rules (a member's deadline change waits for the lead), routing rules (channel → project, aliases), the agent packs (`CLAUDE.md`, `AGENTS.md`) given to coding agents | `Noa.Work` rules; `Noa.Packs` |

Each semantic fact links back to the episode it came from (`EXTRACTED_FROM`), so an agent can always ask "why do we believe this?" and get the message.

## Who writes and reads

| Writer or reader | How |
| --- | --- |
| People | The web app, WhatsApp replies (`done`, approve buttons) |
| Chat ingest | Discord gateway, Kapso webhook: messages become episodes; extraction proposes semantic changes |
| Noa's own agents | Extraction (proposes and, when confident, applies), triage (files owner proposals from the graph) |
| Outside agents | The MCP server: `ask`, `project_context`, `who_knows`, `how_connected`, `risks`, `suggest_owner` to read; `update_task_status`, `assign_task`, `triage` to write, as the token's person |

Every write, whoever makes it, goes through the same Ash actions and policies, and appends to the same event log.

## Consistency under concurrent writers

- **One order.** `Noa.Events.append/4` takes a transaction-scoped advisory lock, so events get strictly increasing ids with no gaps between writers. Readers (the projector, the WhatsApp notifier) keep a position and never miss or reorder an event.
- **Snapshots are the committed row.** Each `.saved` event carries the row as it stands inside the writing transaction, read again after the write, not the writer's possibly stale copy. Without that, two people editing different fields of one task at once left a last snapshot missing one of the edits, and the graph drifted from Postgres. `test/noa/memory_test.exs` caught it.
- **Redelivery is harmless.** Chat messages carry an idempotency key (`discord:<message id>`), so a repeated gateway event is recorded once; the Kapso webhook ignores a WhatsApp message id it has already handled.
- **Edits are never lost silently.** Every change to a shared field is a change record; a member's deadline or scope change waits for the lead instead of overwriting.
- **The graph can always be rebuilt.** FalkorDB is a projection of the log with unique constraints on ids, so replaying is idempotent and `Noa.Release.graph/1` rebuilds a company's memory from scratch in seconds.
- **Deleted means deleted.** The log is append-only with one exception: when someone deletes a chat message, its text is erased from the log entries that carried it and from the graph, and readers skip it. An edit updates the message's text the same way and is recorded as `message.edited`. Tasks and decisions taken from a message keep their own quote.
- **Isolation.** One graph per company (`noa_<org id>`); every query is scoped to it, and Postgres policies scope every read to the asker's workspace.

`test/noa/memory_test.exs` runs about 110 concurrent writes (40 messages each delivered twice, 20 new tasks, and nine writers editing one task at once) and checks the order, the duplicates, the change records, the last snapshot against the row, and that the rebuilt graph matches Postgres. The test database shares one connection, so it exercises Noa's code under concurrent callers rather than Postgres itself; the advisory lock and row locks cover the database side.
