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
| Frontend | Next.js 16 for the app (`web/`) and the marketing site (`landing/`), Tailwind v4, Motion, dnd-kit, `ash_typescript` RPC client, Phoenix Channels |
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

Frontend (Node 22+, pnpm 11):

```bash
pnpm install
pnpm dev:web       # app on http://localhost:3000 (sample data until the API is wired)
pnpm dev:landing   # marketing site on http://localhost:3001
```

| Path | What |
| --- | --- |
| `web/` | Next.js app: My day, Inbox, project board / timeline / decisions / KT, Portfolio, People (staffing board), Agent pack, Ask Noa, Login, Onboarding |
| `landing/` | Next.js marketing site with animated feature scenes |
| `packages/theme/` | Shared design tokens (Tailwind v4) |
| `api/` | Phoenix + Ash backend (coming in Phase 0) |

API setup (Elixir, Postgres, FalkorDB, `.env` keys) lands with the `api/` scaffold.

## Build plan

| Phase | When | Goal |
| --- | --- | --- |
| 0. Setup | Oct 15 evening | Skeleton deploys; graph and extraction schemas frozen; design direction set |
| 1. Chat to Kanban | Oct 16 | A Discord message becomes a proposed task in the right project and lands on the Kanban once approved |
| 2. Work loop | Oct 16 to 17 | A developer and a non-tech teammate both run their day from Noa |
| 3. Shifts, KT, agent packs | Oct 17 | A teammate moves projects using only Noa and gets a KT brief and agent pack |
| 4. Harden and ship | Oct 18 | Freeze at noon, video, submit by 6 PM IST |

Full plan, owners, critical path and cut list: [PLAN.md](PLAN.md). Live task status: [TASKS.md](TASKS.md).

## License

To be decided.
