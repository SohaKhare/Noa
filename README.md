# Noa

**A company brain that turns team conversations into managed work.**

Noa reads Discord, Slack, Google Meet and WhatsApp. It keeps tasks, owners, deadlines and decisions in one [FalkorDB](https://www.falkordb.com/) graph per company, and answers questions with sources. PMs get boards that update themselves, members get one list across all their projects, and people moving between projects get a knowledge-transfer (KT) brief and an agent-ready context pack.

Built by team **NotYourIdea** for [Graph Hacks: Context for AI Agents](https://www.wemakedevs.org/hackathons/falkordb) (WeMakeDevs × FalkorDB, Oct 15–18, 2026), Company Brain track. Noa is built to run NYI's real projects, not as a demo.

> Status: in active development during the hackathon. Setup instructions arrive with the Day 1 scaffold.

## What it does

- **Chat to tasks.** Messages and meeting transcripts become proposed tasks, status changes, deadlines and decisions, routed to the right project. Confident updates apply with undo; the rest wait in a one-click approval inbox.
- **Boards that stay current.** Kanban, Gantt timeline, My day, and a portfolio view with project health, workload and risks.
- **Decided today.** A per-project and per-person panel of decisions, each linked to the message it came from.
- **Shared edits with oversight.** Anyone involved can edit a shared item; scope and deadline changes notify, or wait for, the person they report to.
- **`@noa` everywhere.** Ask in Discord, Slack, WhatsApp or the web app and get cited, permission-aware answers.
- **Shifts and KT.** Drag a person to another project. Noa drafts the handover, suggests new owners, routes questions to the previous owner, and sends a KT brief.
- **Agent context packs.** People joining a project get `CLAUDE.md` / `AGENTS.md`, `tasks.md` and an `.mcp.json` snippet generated from the graph. Non-dev roles get their own pack: `brief.md`, `client.md`, `runbook.md` or `project-state.md`. Secrets never go in these files; they are delivered through one-time, logged links.
- **MCP server.** Coding agents (Claude Code, Cursor) connect to Noa for live, per-person, per-project context.

## How it works

```
Slack · Discord · Google Meet · WhatsApp (Kapso) · GitHub
                    │
        Ingest + bots (privacy gate, identity)
                    │
        Append-only event log (Postgres)
                    │
     Typed extraction (strict JSON schema, async jobs)
                    │
     FalkorDB: one graph per company
     Person · Project · Task · Decision · Episode
     vector + full-text indexes · PageRank · paths
                    │
   Work API · Notifier · Agent (@noa, KT) · MCP server
                    │
        Web app · chat surfaces · coding agents
```

- The Postgres event log is the source of truth. FalkorDB is a projection of it, so the graph can always be rebuilt.
- Every extracted item is a typed schema validated before it reaches the graph, and every item cites its source message.
- Graph algorithms do the product work: PageRank and `KNOWS_ABOUT` edges find experts and bus-factor risks, paths explain how a slip spreads, and vector plus full-text search ground `@noa` answers.

## Stack

| Layer | Choice |
| --- | --- |
| Backend | Elixir, Phoenix, Ash 3 (AshPostgres, AshAuthentication, policies), Oban |
| Graph | FalkorDB Cloud via the official [`falkordb`](https://hex.pm/packages/falkordb) Hex client |
| AI | OpenAI Structured Outputs through InstructorLite; `ash_ai` for agent tools and MCP |
| Frontend | React + Vite, TanStack, shadcn/ui, dnd-kit, `ash_typescript` RPC client, Phoenix Channels |
| Connectors | Discord (Nostrum), Slack Events API, Google Meet REST, WhatsApp via [Kapso](https://kapso.com/) |
| Ops | Fly.io, Postgres, Logfire / OpenTelemetry, Sentry, GitHub Actions |

## Roles

| Role | Lands on | Can do |
| --- | --- | --- |
| Superadmin | Platform console | Orgs, connectors, jobs, LLM spend |
| Org admin | Onboarding | Sources, channel-to-project mapping, people, roles |
| PM / lead | Portfolio | Boards, approvals, timeline, shifts, staffing, credentials |
| Member | My day | Own tasks, approvals, `@noa` |
| Guest | One project | Read-only timeline and decisions |

## Getting started

Coming with the Day 1 scaffold. It will cover:

- prerequisites (Elixir, Node, Postgres, a FalkorDB instance)
- `.env` setup (FalkorDB, OpenAI, Discord, Slack, Google and Kapso credentials)
- running the API and web app locally
- connecting a Discord server and mapping channels to projects

## Build plan

| Day | Date | Goal |
| --- | --- | --- |
| 1 | Oct 15 | Foundation: a Discord message becomes a proposed task in the right project and lands on the Kanban once approved |
| 2 | Oct 16 | Work loop: a developer and a non-tech teammate both run their day from Noa |
| 3 | Oct 17 | Shifts, KT, portfolio, staffing board and agent packs |
| 4 | Oct 18 | Harden and ship: security and load pass, second-team onboarding, video, submission |

## Team NotYourIdea

| Person | Focus |
| --- | --- |
| Saish | Lead: design direction, extraction and agent, key pages |
| Vedant | Backend, graph, platform |
| Soha | Connectors, bots, supporting pages, docs |

## Prior work

Noa is a new codebase written during the hackathon. It builds on lessons and infrastructure patterns from **Tulpa v1**, NYI's earlier Discord memory product (auth, event store, identity resolution, decision extraction), which is cited here as prior work.

## License

To be decided.
