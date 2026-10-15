# Noa plan

Read this first. It is the shared context for every developer on Noa and for their coding agents. Work items and their status are in [TASKS.md](TASKS.md). The full plan, with wireframes and diagrams, is in the team plan doc: https://claude.ai/code/artifact/3fe68f0f-3173-44c6-96f6-97c7457eb0a4

## What we are building

Noa is a company brain that turns team conversations into managed work. It reads Discord, Slack, Google Meet and WhatsApp, and keeps tasks, owners, deadlines and decisions in one FalkorDB graph per company. It answers questions with sources.

It is built for NYI to run its real, concurrent projects with tech and non-tech teammates, where people move between projects often. It is not a demo.

Hackathon: WeMakeDevs × FalkorDB "Graph Hacks: Context for AI Agents", Company Brain track. Deadline Oct 18, 2026, 11:59 PM IST; we target 6 PM IST. Team NotYourIdea: Saish (intern, coordinates and sets design direction), Vedant (full-time full-stack dev), Soha (intern). The repo lives at `github.com/SohaKhare/Noa`.

## Core flows

1. **Chat to task.** A message or meeting transcript is ingested and stored as an Episode. Typed extraction proposes tasks, status changes, deadlines and decisions, and routes each to a project. Confident items apply with undo; the rest go to an approval inbox, and approved items land on the Kanban.
2. **Daily work.** My day shows one list across all of a person's projects. PMs get boards, a Gantt timeline and a portfolio. Each person gets a daily digest on their preferred channel.
3. **Decisions and shared edits.** The "Decided today" panel shows decisions per project and per person. Anyone involved can edit a shared item. Each edit is a change record; scope and deadline changes wait for the editor's lead, and minor edits apply and can be reverted.
4. **`@noa`.** Ask in Discord, Slack, WhatsApp or the web. Answers are cited and permission-aware.
5. **Shift.** A PM drags a person to another project on the staffing board and confirms a popover. Noa then:
   - drafts the handover and suggests new owners
   - routes questions to the previous owner for 2 weeks
   - sends a KT brief
   - grants access from the project's access bundle
6. **Agent pack.** The moved person gets files generated from the project subgraph and kept current when tasks or decisions change:
   - `CLAUDE.md` / `AGENTS.md`, `tasks.md` and an `.mcp.json` snippet for developers
   - `brief.md`, `client.md`, `runbook.md` or `project-state.md` for other roles

   Secrets never go in these files. They are sent as one-time links that expire after 24 hours, and every fetch is logged.

## Roles

| Role | Lands on | Can do |
| --- | --- | --- |
| Superadmin | Platform console | Orgs, connectors, jobs, LLM spend |
| Org admin | Onboarding | Sources, channel-to-project map, people, roles |
| PM / lead | Portfolio | Boards, approvals, timeline, shifts, staffing, access bundles and secrets |
| Member | My day | Own tasks, approve own proposals, `@noa` |
| Guest | One project | Read-only timeline and decisions |

Every person has a reports-to lead; change notifications go to that lead.

## Architecture

```
Slack · Discord · Google Meet · WhatsApp (Kapso) · GitHub
  → ingest + bots (privacy gate, identity resolution)
  → append-only event log in Postgres (source of truth)
  → Oban jobs: typed extraction (OpenAI Structured Outputs via InstructorLite)
  → projector writes FalkorDB (one graph per org)
  → Work API (Ash) · Notifier · Agent (@noa, KT) · MCP server (ash_ai)
  → Next.js web app (client of the API: ash_typescript RPC + Phoenix Channels); Next.js landing site; chat bots; coding agents
```

Rules:

- **The event log is the truth.** FalkorDB is a projection that can be rebuilt by replaying events, so never write to the graph except through the projector.
- **Typed extraction only.** Each extraction type is an Ecto embedded schema compiled to a strict JSON schema, and the model can only return that shape. InstructorLite validates the output and retries; untyped output never reaches the graph. Prefer precision over recall.
- **Everything cites its source.** Every Task and Decision has `EXTRACTED_FROM` an Episode.
- **Ash policies enforce permissions** on every read, including `@noa` answers and MCP calls. Direct messages are never ingested, and unmapped channels are never ingested.

## Graph schema (draft; frozen by item 0.3 into `docs/schema.md`)

Nodes:

- Org, Person, Identity, Team, Project, Channel
- Episode (a message or transcript chunk), Meeting
- Task, Milestone, Decision, Topic, Document, ChangeRecord

Edges:

| Edge | From and to | Properties |
| --- | --- | --- |
| `HAS_IDENTITY` | Person → Identity | per platform |
| `REPORTS_TO` | Person → Person | |
| `WORKS_ON` | Person → Project | `from`, `to`, `allocation`, `role`; dated, never deleted |
| `MAPS_TO` | Channel → Project | |
| `AUTHORED` | Person → Episode | |
| `IN` | Episode → Channel / Meeting | |
| `BELONGS_TO` | Task → Project | |
| `ASSIGNED_TO` | Task → Person | |
| `PART_OF` | Task → Milestone | |
| `DEPENDS_ON` | Task → Task | |
| `EXTRACTED_FROM` | Task / Decision → Episode | |
| `SUPERSEDES` | Decision → Decision | |
| `AFFECTS` | Decision → Task / Project | |
| `ABOUT` | Episode → Topic | |
| `KNOWS_ABOUT` | Person → Topic | `weight` |
| `CHANGED` | ChangeRecord → item | `kind`, `old`, `new`, `by`, `approved_by` |

Indexes: a vector index (`vecf32`) on Episode and Decision embeddings, a full-text index on Episode text, and range indexes on ids.

Algorithms:

- PageRank over `KNOWS_ABOUT` finds experts and bus-factor risks.
- Shortest paths over `DEPENDS_ON` show how a slip spreads.
- Label propagation finds topic clusters.

Extraction types: `TaskProposal`, `StatusChange`, `DeadlineChange`, `Decision`, `ScopeChange`, `ProjectRoute`. Each carries `confidence` and `source_episode_id`.

## Stack

- **Backend:** Elixir, Phoenix, Ash 3 (AshPostgres, AshAuthentication, policies, multitenancy by org), Oban + AshOban.
- **Graph:** FalkorDB Cloud, through the official `falkordb` Hex client (built on Redix).
- **AI:** OpenAI Structured Outputs via InstructorLite; `ash_ai` for agent tools and the MCP server.
- **Frontend:** Next.js 16 (App Router) for both `web/` (the app) and `landing/` (marketing site), Tailwind v4, Motion for animation, Phosphor icons, TanStack Query, dnd-kit for drag and drop, `ash_typescript` for the RPC client. The app uses no Next.js API routes or server actions: Phoenix is the only backend.
- **Design:** shared tokens in `packages/theme` (Mio- and Elf-inspired, graph-themed). See [docs/design.md](docs/design.md).
- **Connectors:** Nostrum for Discord, Slack Events API, Google Meet REST API, Kapso for WhatsApp.
- **Ops:** Fly.io, Postgres, Logfire / OpenTelemetry, Sentry, GitHub Actions.

## Repo layout (target)

```
api/        Phoenix + Ash backend
  lib/noa/        accounts, orgs, events, graph, ingest/<platform>, extraction, work, changes, agent, packs, secrets
  lib/noa_web/    endpoint, channels, webhooks, MCP
web/        Next.js app (App Router): src/app/(app)/* pages, src/components, src/lib (api, mock data)
landing/    Next.js marketing site with animated feature scenes
packages/theme/  shared design tokens (Tailwind v4 CSS)
docs/       schema.md, runbooks
PLAN.md     this file
TASKS.md    tracker mirror
AGENTS.md   short rules for coding agents
```

## Reusing Tulpa v1

Tulpa v1 is NYI's earlier product, at `~/code/nyi/tulpa` (Elixir/Ash API in `apps/api`, React web app in `apps/web`). Copy or port from it, but every commit to Noa is new work made during the hackathon.

| Tulpa v1 | Use in Noa |
| --- | --- |
| `apps/api/lib/tulpa/accounts`, AshAuthentication setup | Copy: auth (1.4) |
| `apps/api/lib/tulpa/organizations` | Copy: orgs, invites, access requests (1.5) |
| `apps/api/lib/tulpa/event_store` | Port: event log (1.8) |
| `apps/api/lib/tulpa/connectors/discord` | Port: Discord ingest (1.13) |
| `apps/api/lib/tulpa/identity` | Port: Person and Identity (1.11) |
| `apps/api/lib/tulpa/decisions/extractor/open_ai.ex` | Port: strict-schema extraction prompt (1.17, 1.21) |
| `apps/api/lib/tulpa/answers` | Port: `@noa` answers with citations (2.5) |
| `apps/api/lib/tulpa/llm_audit.ex`, `llm_usage.ex` | Copy: LLM audit and usage (1.3) |
| `apps/api/Dockerfile`, `fly.toml`, `rel/` | Copy: deploy (1.2) |
| `apps/web/src` components and pages | Copy: web shell, login and invite pages (1.7) |
| Tulpa v1 Postgres data | Import: NYI history, decisions, projects, people (1.12) |

Rename modules from `Tulpa.*` to `Noa.*` when copying.

## Build phases

Each phase ends with something that runs on NYI's real data, so whatever phase we reach is shippable. Item numbers are rows in [TASKS.md](TASKS.md).

### Phase 0: Setup (Oct 15 evening)

| Owner | Focus |
| --- | --- |
| Vedant | Scaffold `api/` (Phoenix, Ash, Postgres, auth copied from v1) and `web/` (Next.js; pages already scaffolded on sample data); CI; FalkorDB Cloud, Fly, Logfire, Sentry (0.12); FalkorDB client spike (0.5); freeze schemas with Saish (0.3) |
| Saish | Design direction (0.17) and design kit tokens (0.18); extraction prompt spike on 40 real messages (0.9); NYI org map (0.14) |
| Soha | Register Discord, Slack and Google apps (0.10); Kapso account (0.11); channel consent and v1 export (0.15); golden question set (0.16) |

**Exit:** a login page deploys to Fly, the API reaches FalkorDB, and `docs/schema.md` is merged.

### Phase 1: Chat to Kanban (Oct 16)

| Owner | Focus |
| --- | --- |
| Vedant | Orgs and roles (1.5, 1.6); event log (1.8); `Noa.Graph` wrapper (1.9); projector (1.10); identity (1.11); reporting lines (1.22) |
| Saish | Web shell (1.7); typed schemas (1.21); task extraction (1.17); routing (1.16); Inbox (1.19); Kanban (1.20) |
| Soha | Discord ingest (1.13); v1 import (1.12); Slack ingest (1.14); Kapso send and receive (1.15); onboarding (1.18) |

**Critical path:** 1.8 → 1.10 → 1.17 → 1.19 → 1.20. Discord ingest (1.13) has to be feeding events by midday.

### Phase 2: Work loop (Oct 16 evening to Oct 17 midday)

Suggested split. Items start `Unassigned` in TASKS.md; claim one when you pick it up.

| Owner | Focus |
| --- | --- |
| Vedant | Auto-apply with undo (2.2); live updates (2.14); Gantt (2.11); change records and approval rules (2.19, 2.20); digest (2.9); permission tests (2.16) |
| Saish | Status, blocker and deadline extraction (2.1); duplicates (2.3); decisions (2.4); `@noa` (2.5); My day (2.12); Decided today (2.18) |
| Soha | Chat approval buttons (2.6); WhatsApp "done" (2.7); Meet action items (2.8); change notifications (2.21); task detail (2.13); notification preferences (2.15); eval harness (2.17) |

### Phase 3: Shifts, KT and agent packs (Oct 17 afternoon to night)

Suggested split. Items start `Unassigned` in TASKS.md; claim one when you pick it up.

| Owner | Focus |
| --- | --- |
| Vedant | Shift backend (3.1); experts and bus factor (3.3); MCP server (3.6); pack generator (3.18); MCP tokens (3.22); secrets as one-time links plus an audit log (3.21) |
| Saish | KT brief (3.2); staffing board (3.17); shift wizard (3.11); portfolio (3.9); role pack templates (3.19); one real shift (3.15) |
| Soha | KT delivery (3.5); project page (3.10); KT page (3.12); access checklist (3.20); pack delivery (3.23) |

### Phase 4: Harden and ship (Oct 18)

Items start `Unassigned`; claim them in TASKS.md. Until noon, bug fixes only, plus:

- load test (4.2) and security pass (4.3)
- empty and error states (4.4)
- landing page (4.5)
- second-team onboarding test (4.6)

Feature freeze is at 12:00 (4.1). Then the video (4.7) and README and blog (4.8). Submit by 18:00 (4.9).

### Cut list

If behind, cut from the top:

1. GitHub card closing and voice notes (3.7, 3.8)
2. Graph panel and superadmin console (3.13, 3.14)
3. Slack, if NYI mostly uses Discord
4. Gantt dependencies
5. Anything in the secrets vault beyond one-time links
6. Slip propagation (3.4)

**Never cut:** routing, chat to task with approval, Kanban, My day, cited `@noa`, the shift flow with KT, permissions.

## Working agreements

- One PR per TASKS.md item, reviewed by one teammate. `main` always deploys.
- Branch `<person>/<item>-<slug>`; PR title `<item>: <summary>`.
- Update the item's row in TASKS.md in the same PR, and its status in the plan doc (see TASKS.md for how).
- Design first: pages use Saish's theme tokens and design kit. Don't invent new colors or spacing.
- Secrets live only in `.env` (never committed) and Fly secrets. `.env.example` lists every key.
- Ask in the team channel before changing the graph schema or extraction types. They are contracts between all three people.
