# Noa plan

Read this first. It is the shared context for every developer on Noa and for their coding agents. Work items and their status are in [TASKS.md](TASKS.md). The full plan, with wireframes and diagrams, is in the team plan doc: https://claude.ai/code/artifact/3fe68f0f-3173-44c6-96f6-97c7457eb0a4

## What we are building

Noa is a company brain that turns team conversations into managed work. It reads Discord, Slack, Google Meet and WhatsApp, and keeps tasks, owners, deadlines and decisions in one FalkorDB graph per company. It answers questions with sources.

It is built for NYI to run its real, concurrent projects with tech and non-tech teammates, where people move between projects often. It is not a demo.

Hackathon: WeMakeDevs × FalkorDB "Graph Hacks: Context for AI Agents", Company Brain track. Deadline Oct 18, 2026, 11:59 PM IST; we target 6 PM IST. Team NotYourIdea: Saish (intern, coordinates and sets design direction), Vedant (full-time full-stack dev, and PM / lead for the hackathon), Soha (intern). The repo lives at `github.com/SohaKhare/Noa`.

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
  → Work API (Ash) · Notifier · Agent (@noa, KT) · MCP server (graph tools for coding agents)
  → Next.js web app (client of the API: ash_typescript RPC + Phoenix Channels); Next.js landing site; chat bots; coding agents
```

Rules:

- **The event log is the truth.** FalkorDB is a projection that can be rebuilt by replaying events, so never write to the graph except through the projector.
- **Typed extraction only.** Each extraction type is an Ecto embedded schema compiled to a strict JSON schema, and the model can only return that shape. InstructorLite validates the output and retries; untyped output never reaches the graph. Prefer precision over recall.
- **Everything cites its source.** Every Task and Decision has `EXTRACTED_FROM` an Episode.
- **Gmail inbox opt-in (1.29).** NYI approved importing all new mail arriving at `itsupport@notyouridea.com` (no historical backfill, no attachment content), LLM processing and workspace-member visibility. This explicitly approved email inbox differs from private chat DMs, which remain excluded. The connector uses read-only IMAP over TLS, not SMTP.
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
- **AI:** OpenAI Structured Outputs via InstructorLite. The MCP server speaks the protocol directly (Streamable HTTP, JSON-RPC) rather than through `ash_ai`, to keep its tools as plain FalkorDB queries run as the person.
- **Frontend:** Next.js 16 (App Router) for both `web/` (the app) and `landing/` (marketing site), Tailwind v4, Motion for animation, Phosphor icons, TanStack Query, dnd-kit for drag and drop, `ash_typescript` for the RPC client. The app uses no Next.js API routes or server actions: Phoenix is the only backend.
- **Design:** shared tokens in `packages/theme` (Mio- and Elf-inspired, graph-themed). See [docs/design.md](docs/design.md).
- **Connectors:** Nostrum for Discord, Slack Events API, Google Meet REST API, Kapso for WhatsApp.
- **Ops:** Fly.io, Postgres, Logfire / OpenTelemetry, Sentry, GitHub Actions.

## Repo layout (target)

```
api/        Phoenix + Ash backend (today: auth, workspaces and invites, plus the extraction core)
  lib/noa/        accounts, orgs, events, graph, ingest/<platform>, extraction, work, changes, agent, packs, secrets
  lib/noa_web/    endpoint, channels, webhooks, MCP
web/        Next.js app (App Router): src/app/(app)/* pages, src/components, src/lib (api, mock data)
landing/    Next.js marketing site with animated feature scenes
packages/theme/  shared design tokens (Tailwind v4 CSS)
docs/       schema.md, auth.md (accounts, workspaces, invites), extraction.md (types, prompt, routing), org-map.md + seeds/nyi.json, design.md, runbooks
docker-compose.yml  local Postgres (and FalkorDB under the graph profile)
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

## Re-plan (Oct 16 evening)

This section replaces the dates and splits in "Build phases" below where they disagree. Vedant is PM / lead: he owns the checkpoints, reviews PRs and approves cuts. He is busy for now, so since Oct 16 all build work is split between Saish (the most active, so slightly more) and Soha.

### Where we are

Built (in review, not committed yet):

- **Accounts and workspaces (1.4 to 1.7, 1.22).** Invite-only sign-in with password, magic link and reset. The superadmin creates a workspace and invites its first admin. Admins invite people by work email only. Roles, titles and reports-to are editable, and Ash policies check every read. A workspace always keeps an admin (1.26). See [docs/auth.md](docs/auth.md).
- **Extraction core (1.16, 1.17, 1.21).** Typed schemas, the prompt, message windows and project routing, runnable with `mix noa.extract --dry-run`. It has not yet run against OpenAI (0.9). See [docs/extraction.md](docs/extraction.md).
- **Web and landing.** Every app page exists, but on sample data in `web/src/lib/mock.ts`. The landing page is done (0.19), apart from its night images, which are missing from the CDN.
- **Org map and seed (0.14, 1.23).** Vedant is lead of Veriq and Emmarie; Saish and Soha report to him. `mix noa.seed` loads it into the workspace.
- **Work data and API (1.24), Inbox (1.19) and board (1.20) on real data.** People, projects, allocations, channels, tasks and proposals, with approve, dismiss and drag-to-move. See [docs/schema.md](docs/schema.md). 52 API tests pass.

Update Oct 17: the event log, graph wrapper, projector and identity (1.8 to 1.11) are in review, with the FalkorDB spike (0.5). The extraction job (1.17) now runs on recorded messages through Oban. Still on the critical path: Discord ingest (1.13, which calls `Noa.Work.record_message/2`) and Kapso (0.11, 1.15).

So Phase 1 runs into Oct 17 morning, and Phases 2 and 3 are trimmed to what the demo story needs.

### Checkpoints

| When (IST) | Checkpoint | Shown with |
| --- | --- | --- |
| Oct 17, 11:00 | **Spine:** a real message in `#veriq` becomes a proposal in the Inbox; approving it puts the card on the Veriq board, and the owner gets a WhatsApp | Local stack, real NYI Discord |
| Oct 17, 20:00 | **Work loop:** My day on real data; a deadline change waits for the lead; cited `@noa` answers | Deployed on Fly |
| Oct 18, 08:00 | **Shift:** Vedant moves Soha from Video Break to Emmarie; she gets a KT brief and an agent pack | Deployed, real shift (3.15) |
| Oct 18, 12:00 | Feature freeze (4.1) | |
| Oct 18, 18:00 | Submitted (4.9) | |

If a checkpoint slips by more than two hours, cut from the cut list before starting the next phase.

### Phase 1b: Spine (now to Oct 17, 11:00)

Schema (0.3): Saish confirms [docs/schema.md](docs/schema.md) and adds the graph part. Vedant only needs to read and approve it. The decision in it: current task and project state lives in Postgres, written only through `Noa.Work`, and the projector mirrors it into FalkorDB for questions, experts and paths. Both can be rebuilt from the event log.

| Owner | Work, in order |
| --- | --- |
| Saish | Done, in review: 1.23, 1.24, 1.19, 1.20, 1.26. Next: 0.3 schema (graph part); 0.5 FalkorDB client spike; 1.8 event log (Postgres, idempotent on platform + message id); 1.9 graph wrapper on local FalkorDB (`docker compose --profile graph up`); 1.10 projector; 1.11 identity (Discord user to Person through `people.handles`); 1.17 Oban job from new message events to proposals; 0.9 run on 40 real messages once the OpenAI key is in; 1.3 LLM usage logging |
| Soha | 0.10 Discord app and bot token; 0.15 channel consent; 1.13 Discord ingest (mapped channels only; call `Noa.Work.record_message/2` for each message, and the extraction job 1.17 turns them into proposals); 0.11 Kapso account and a "task assigned" template; 1.15 Kapso send; 1.25 real email delivery; 0.1 confirm NYI's daily tools; 0.12 and 1.2 Fly deploy with FalkorDB Cloud, by Oct 17 evening |

Moved out of Phase 1:

- **1.18 onboarding UI.** NYI is set up by the seed loader. A minimal channel-map page is built in Phase 4 for the second-team test (4.6).
- **1.12 v1 import.** Phase 3, if there is time. `@noa` works on live data without it.
- **1.14 Slack.** Cut unless 0.1 shows NYI uses Slack.
- **1.3 observability.** Only LLM usage logging now; Logfire and Sentry go in Phase 4.

### Phase 2: Work loop (Oct 17, 11:00 to 20:00)

The demo story: Saish asks to move the Board report PDF to Monday, Vedant approves it, Saish gets a WhatsApp, and Abhishek asks `@noa` what is blocking Emmarie.

| Owner | Must have | If time |
| --- | --- | --- |
| Saish | 2.12 My day on real data; 2.1 status, blocker and deadline extraction; 2.19 change records; 2.20 lead approval rules; 2.4 decisions; 2.18 Decided today; 2.5 `@noa` with citations (web; Soha's bot calls the same function for Discord); 2.16 permission tests | 2.2 auto-apply with undo; 2.3 duplicates; 2.11 read-only timeline; 2.15 notification preferences |
| Soha | 2.14 live board and Inbox over Phoenix Channels; 2.6 approve from Discord; 2.21 change notifications on WhatsApp; 2.7 WhatsApp "done" replies move cards; 2.13 task detail with sources and history | 2.9 daily digest on WhatsApp |

Proposed cuts: 2.8 Meet transcripts (needs Google verification and the 0.7 spike); 2.10 edits (handle deletes only); 2.17 eval harness (run the golden set by hand once for the README).

### Phase 3: Shift, KT and agent pack (Oct 17, 20:00 to Oct 18, 08:00)

The demo story: Vedant drags Soha from Video Break to Emmarie, confirms, and Soha gets a KT brief, the people to meet, and an Emmarie `CLAUDE.md`.

| Owner | Must have | If time |
| --- | --- | --- |
| Saish | 3.1 shift backend; 3.17 staffing board with the confirm popover (absorbs 3.11); 3.3 experts by PageRank ("people to meet") and bus factor; 3.2 KT brief; 3.9 portfolio on real data; 3.18 agent pack; 3.6 MCP server and 3.22 tokens | 3.19 `brief.md` only |
| Soha | 3.5 KT delivery on WhatsApp; 3.23 pack link on a shift; 3.20 access checklist; 3.15 run the real shift with the team | 1.12 v1 import |

Proposed cuts: 3.4 slip propagation, 3.7 GitHub, 3.8 voice notes, 3.14 beyond the first slice that exists, 3.21 beyond one-time links, 3.23 "add to repo" PR.

Update Oct 17 evening: the agent pack (3.18), graph panel (3.13), KT page (3.12) and graph rebuild drill (3.16) are built. **How a pack reaches someone:** (1) download from the pack page, works today; (2) a shift sends the person a WhatsApp or Discord link to their pack and brief (3.23, Soha, after 1.15); (3) their coding agent connects to Noa's MCP server and pulls context live (3.6 and 3.22, Saish, now in scope). MCP tools are FalkorDB queries run with the person's own permissions: `project_context`, `my_tasks`, `ask`, `who_knows`, `how_connected`, `decisions`, `list_projects`, and `update_task_status` under the lead rules. Tokens are per person and workspace, shown once, stored hashed and revocable. MCP also covers Track 01 (graph algorithms as agent tools).

### Phase 4: Harden and ship (Oct 18)

Saish: freeze (4.1), load test (4.2), security pass (4.3), video (4.7), README and blog (4.8), submit (4.9). Soha: empty and error states (4.4), landing, privacy and terms (4.5), second-team test with a minimal channel-map page (4.6). Plus Logfire and Sentry, and the landing night images.

### Blockers to clear today

- **OpenAI key** for 0.9 and 1.17, needed by Oct 17 morning.
- **Team consent** for the channels Noa reads (0.15), before the bot joins the real server.
- **Kapso and Meta template approval** (0.11) can take hours, so start it today. Fallback: Kapso's sandbox number.
- **FalkorDB Cloud** (0.12) only matters for deploy; local Docker covers development.
- **Landing images:** upload `night.jpg` and `night-water.jpg` to `cdn.saish.xyz/noa/images/`.

## Build phases

The original plan. Where it disagrees with the re-plan above, the re-plan wins.

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
