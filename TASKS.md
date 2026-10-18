# Noa tasks

The build tracker, mirrored from the "Build tracker" tab of the team plan doc: https://claude.ai/code/artifact/3fe68f0f-3173-44c6-96f6-97c7457eb0a4

The plan doc is the main chart. This file holds the same rows so agents can read and update them inside the repo. Context for every item is in [PLAN.md](PLAN.md).

## How to keep it in sync

- **Starting an item:** set its Status to `In progress` here in your branch, and in the plan doc.
- **Opening a PR:** set it to `In review` and put the PR number in the PR column, for example `#12`.
- **Merging:** the PR that does the work also sets the row to `Done`. The person merging sets the same status in the plan doc.
- **Cutting an item:** set it to `Cut` and add a short reason after the item text.
- **Adding new work:** add a row with the next free number in the right phase, in both places.
- Statuses are exactly: `Not started`, `In progress`, `In review`, `Done`, `Cut`.
- Owners are exactly: `Unassigned`, `Saish`, `Vedant`, `Soha`. Since Oct 16 every item that is not a proposed cut is assigned to Saish or Soha; Vedant is busy and stays lead (reviews and approvals). An `Unassigned` row is a proposed cut: pick it up only if the must-haves are done. To swap an item, change Owner here and in the plan doc's Owner dropdown.
- Never renumber items. Branch names and PR titles use the number, for example `vedant/1.9-graph-wrapper` and `1.9: Noa.Graph wrapper`.

Source key: **New** = written fresh. **Copy** = infrastructure copied from Tulpa v1. **Port** = rewritten from a Tulpa v1 pattern. **Import** = Tulpa v1 data.

## Phase 0: Setup (Oct 15 evening)

Exit test: Skeleton deploys to Fly with login; API reaches FalkorDB; graph and extraction schemas frozen in `docs/schema.md`; design direction set.

| # | Item | Source | Owner | Status | PR |
| --- | --- | --- | --- | --- | --- |
| 0.1 | Confirm the tools NYI uses daily | New | Soha | Not started |  |
| 0.2 | Ask organizers: judging, multi-track, Tulpa v1 reuse split | New | Saish | Not started |  |
| 0.3 | Freeze graph schema, extraction schemas, API contracts | New | Saish | Not started |  |
| 0.4 | Wireframes for every page (UI and flows tab) | New | Saish | Not started |  |
| 0.5 | Spike: falkordb Elixir client (vector, full-text, PageRank, paths) | New | Saish | In review | #2 |
| 0.6 | Spike: Kapso send, receive, buttons, signed webhooks | New | Saish | In review | #3 |
| 0.7 | Spike: Google Meet transcript API on one NYI meeting | New | Soha | Not started |  |
| 0.8 | Spike: ash_ai tools + MCP, ash_typescript, React Gantt library | New | Saish | Not started |  |
| 0.9 | Spike: extraction prompt on 40 real NYI messages | Port | Saish | In progress |  |
| 0.10 | Register Discord, Slack and Google apps (Internal + External testing) | New | Soha | In progress |  |
| 0.11 | Kapso account, 3 WhatsApp templates, start Meta verification | New | Saish | In progress |  |
| 0.12 | FalkorDB Cloud, Fly.io, Postgres, Logfire, Sentry, domain. Fly configs and one-server compose ready (docs/deploy.md); accounts and domain to do | Copy | Saish | In review | #4 |
| 0.13 | Privacy policy and terms text | New | Soha | Not started |  |
| 0.14 | NYI org map: projects, people, roles, reporting lines, allocations, channel-to-project | New | Saish | In review | #1 |
| 0.15 | Team consent for channels; export Tulpa v1 data | Import | Soha | Not started |  |
| 0.16 | 40-question golden set from real NYI questions | New | Soha | Not started |  |
| 0.17 | Design direction: reference board, theme, colors, type, light and dark | New | Saish | Done | #1 |
| 0.18 | Design kit: shadcn tokens and core components (task card, person chip, status pill, panels) | New | Saish | Done | #1 |
| 0.19 | Landing page design and copy | New | Saish | Done | #1 |

## Phase 1: Chat to Kanban (Oct 16 to Oct 17, 11:00)

Re-planned on Oct 16; see "Re-plan" in PLAN.md. 1.12 moves to Phase 3, 1.18 is replaced by the seed loader (1.23) for NYI, and 1.14 is cut unless 0.1 shows NYI uses Slack.

Exit test: A real Discord message becomes a proposed task in the right project and lands live on the Kanban once approved.

| # | Item | Source | Owner | Status | PR |
| --- | --- | --- | --- | --- | --- |
| 1.1 | New repo | Copy | Soha | Done |  |
| 1.2 | Fly deploy: Dockerfiles, `fly.toml`, release migrations | Copy | Saish | In review | #4 |
| 1.3 | Observability: Logfire/OpenTelemetry, LLM audit and usage | Copy | Saish | In review | #3 |
| 1.4 | Auth: password, magic link, Google, reset (AshAuthentication) | Copy | Saish | In review | #1 |
| 1.5 | Orgs, invites, access requests | Copy | Saish | In review | #1 |
| 1.6 | Roles and Ash policies: superadmin, org admin, PM/lead, member, guest | New | Saish | In review | #1 |
| 1.7 | Web shell: login and invite pages, dashboard layout, shadcn theme | Copy | Saish | In review | #1 |
| 1.8 | Event log: append-only, idempotent, projections | Port | Saish | In review | #2 |
| 1.9 | `Noa.Graph` wrapper, schema bootstrap, indexes | New | Saish | In review | #2 |
| 1.10 | Event-to-FalkorDB projector | New | Saish | In review | #2 |
| 1.11 | Identity: `Person` + `Identity` nodes | Port | Saish | In review | #2 |
| 1.12 | Import Tulpa v1 history, decisions, projects, aliases, people | Import | Soha | Not started |  |
| 1.13 | Discord ingest: privacy gate, consumer, membership, backfill | Port | Soha | In review |  |
| 1.14 | Slack Events webhook ingest | New | Soha | Not started |  |
| 1.15 | Kapso WhatsApp send and receive | New | Saish | In review | #3 |
| 1.16 | Project routing: channel map, aliases, thread, author's projects | New | Saish | In review | #1 |
| 1.17 | Task extraction v1 to proposals (from v1 distiller prompt) | Port | Saish | In review | #1 |
| 1.18 | Onboarding: connect sources, map channels, add people and allocations | New | Saish | In review | #4 |
| 1.19 | Inbox page (proposals) | New | Saish | In review | #2 |
| 1.20 | Kanban board | New | Saish | In review | #2 |
| 1.21 | Typed extraction schemas: Ecto embedded schemas to strict JSON schema, validated with InstructorLite | Port | Saish | In review | #1 |
| 1.22 | Reporting lines (reports-to) in org map and people settings | New | Saish | In review | #1 |
| 1.23 | Seed loader: `mix noa.seed` loads `docs/seeds/nyi.json` (projects, channels, aliases, allocations, git handles) | New | Saish | In review | #2 |
| 1.24 | Work API: projects, tasks and proposals as Ash resources with policies; endpoints the web app uses instead of `mock.ts` | New | Saish | In review | #2 |
| 1.25 | Real email delivery for invites, magic links and resets (Swoosh adapter in prod) | New | Soha | In progress |  |
| 1.26 | Guard against removing or demoting a workspace's last admin | New | Saish | In review | #2 |
| 1.27 | Join link: teammates ask to join with a work email; an org admin approves and the invite email follows | New | Saish | In review | #4 |
| 1.28 | Per-company connectors: org admins connect their Discord server and GitHub (secrets encrypted) in Settings; the Noa admin runs only the platform bot and number | New | Saish | In review | #4 |

## Phase 2: Work loop (Oct 17, 11:00 to 20:00)

PLAN.md's re-plan has the suggested owners, the must-haves and the proposed cuts.

Exit test: NYI uses no other tracker; a developer and a non-tech teammate both run their day from Noa.

| # | Item | Source | Owner | Status | PR |
| --- | --- | --- | --- | --- | --- |
| 2.1 | Status, blocker and deadline extraction | New | Saish | In review | #3 |
| 2.2 | Auto-apply with undo above a confidence threshold | New | Saish | In review | #3 |
| 2.3 | Duplicate task matching before proposing | New | Saish | In review | #3 |
| 2.4 | Decisions and supersession | Port | Saish | In review | #3 |
| 2.5 | `@noa` agent with citations (ash_ai tools, audience-first rules) | Port | Saish | In review | #3 |
| 2.6 | Approval buttons in Discord, Slack, WhatsApp | New | Soha | Not started |  |
| 2.7 | WhatsApp "done" replies move cards | New | Saish | In review | #3 |
| 2.8 | Google Calendar + Meet transcripts to action items | New | Unassigned | Not started |  |
| 2.9 | Daily digest per person (from v1 recap) | Port | Saish | In review | #4 |
| 2.10 | Message edit and delete handling (Discord): edits replace the text, deletes erase it from the log and graph | New | Saish | In review | #4 |
| 2.11 | Gantt timeline: milestones, dependencies, drag dates | New | Saish | In review | #3 |
| 2.12 | My day and my work (simple and detailed views) | New | Saish | In review | #2 |
| 2.13 | Task detail: sources, history, undo | New | Saish | In review | #3 |
| 2.14 | Live updates: shared work refreshes every 10 s while the tab is open (Phoenix Channels later) | New | Saish | In review | #4 |
| 2.15 | Notification preferences: channel, digest time, quiet hours | New | Saish | In review | #3 |
| 2.16 | Permission leakage tests in CI | New | Saish | In review | #3 |
| 2.17 | Eval harness on the golden set | Port | Unassigned | Not started |  |
| 2.18 | Decided today panel (per project and per person) | New | Saish | In review | #3 |
| 2.19 | Change records for shared-item edits: scope, deadline, owner, status, decision | New | Saish | In review | #3 |
| 2.20 | Lead approval rules: deadline and scope changes wait, minor edits apply with revert | New | Saish | In review | #3 |
| 2.21 | Change notifications to lead and owner on each person's channel: WhatsApp, Discord DM, email | New | Saish | In review | #4 |

## Phase 3: Shifts, KT and agent packs (Oct 17, 20:00 to Oct 18, 08:00)

PLAN.md's re-plan has the suggested owners, the must-haves and the proposed cuts.

Exit test: A real NYI teammate moves projects using only Noa, gets a KT brief and agent pack, and both boards stay correct.

| # | Item | Source | Owner | Status | PR |
| --- | --- | --- | --- | --- | --- |
| 3.1 | Shift backend: handover draft, reassignment suggestions, previous-owner routing | New | Saish | In review | #3 |
| 3.2 | KT brief generator and follow-up Q&A | New | Saish | In review | #3 |
| 3.3 | Experts via `KNOWS_ABOUT` + PageRank; bus factor | New | Saish | In review | #3 |
| 3.4 | Slip propagation and drift detection | New | Unassigned | Not started |  |
| 3.5 | KT delivery and Q&A on WhatsApp and Discord | New | Soha | Not started |  |
| 3.6 | MCP server: graph tools for coding agents (context, tasks, ask, experts, paths), Streamable HTTP | New | Saish | In review | #3 |
| 3.7 | GitHub: Noa's GitHub App (one-click install per company) or a hand-added webhook; commits, PRs and CI into the graph and agent packs; a merged PR proposes closing its task | New | Saish | In review | #4 |
| 3.8 | WhatsApp voice notes, transcribed (beta) | New | Unassigned | Not started |  |
| 3.9 | Portfolio: project health, workload heatmap, risks | New | Saish | In review | #3 |
| 3.10 | Project page: board, timeline, decisions, people, KT tabs | New | Saish | In review | #3 |
| 3.11 | Shift wizard | New | Saish | In review | #3 |
| 3.12 | KT brief page and checklist | New | Saish | In review | #3 |
| 3.13 | Graph panel with path highlighting | New | Saish | In review | #3 |
| 3.14 | Superadmin console: orgs, LLM usage, system status (services, jobs, event-log readers) | Copy | Saish | In review | #4 |
| 3.15 | Run one real NYI shift end to end | New | Soha | Not started |  |
| 3.16 | Backfill and rebuild-the-graph drill | New | Saish | In review | #3 |
| 3.17 | Staffing board: drag-and-drop people with confirm popover | New | Saish | In review | #3 |
| 3.18 | Agent pack generator: `CLAUDE.md`/`AGENTS.md`, `tasks.md`, `.mcp.json` from the project subgraph; regenerate on change | New | Saish | In review | #3 |
| 3.19 | Role pack templates: `brief.md`, `client.md`, `runbook.md`, `project-state.md` | New | Saish | In review | #3 |
| 3.20 | Access bundles per project: GitHub team, Discord role, Drive share; checklist for the rest | New | Soha | Not started |  |
| 3.21 | Secrets vault: encrypted per project, one-time 24-hour links, fetch audit, revoke on shift | New | Unassigned | Not started |  |
| 3.22 | Per-person MCP tokens: created on the pack page, shown once, hashed, revocable | New | Saish | In review | #3 |
| 3.23 | Pack delivery: shift sends a WhatsApp/Discord link to the pack and brief (after 1.15); "add to repo" PR later | New | Saish | In review | #4 |
| 3.24 | Triage agent: finds unowned, orphaned and overloaded work, ranks owners from the graph with the route shown, files Inbox proposals; MCP `suggest_owner`, `assign_task`, `triage`, `risks` (Track 01) | New | Saish | In review | #4 |
| 3.25 | Shared memory under concurrent writers: committed-row snapshots, concurrency test, docs/memory.md (Track 02) | New | Saish | In review | #4 |
| 3.26 | Assigning a task puts its owner on the project (10% contributor); new allocations tell the person their agent pack changed; agent pack card on My day | New | Saish | In review | #4 |

## Phase 4: Harden and ship (Oct 18)

Exit test: A new team reaches its first proposed tasks in under 10 minutes without help. Freeze at noon, submit by 6 PM IST.

| # | Item | Source | Owner | Status | PR |
| --- | --- | --- | --- | --- | --- |
| 4.1 | Feature freeze at noon IST | New | Saish | Not started |  |
| 4.2 | Load test on NYI's full history | New | Saish | In review | #3 |
| 4.3 | Security pass: tokens, webhooks, policies | New | Saish | In review | #3 |
| 4.4 | Empty, loading and error states on every page | New | Saish | In review | #4 |
| 4.5 | Landing, privacy and terms pages (privacy and terms drafted; need a read before launch) | Copy | Saish | In review | #4 |
| 4.6 | Second-team onboarding test on a fresh org (automated in setup_test; manual run to do) | New | Saish | In review | #4 |
| 4.7 | 3-minute video of real NYI use | New | Saish | Not started |  |
| 4.8 | README with architecture and setup; blog post | New | Saish | In progress |  |
| 4.9 | Submit on WeMakeDevs (all tracks allowed) | New | Saish | Not started |  |

## Phase 5: After the event (Later)

| # | Item | Source | Owner | Status | PR |
| --- | --- | --- | --- | --- | --- |
| 5.1 | Google OAuth verification for external orgs | New | Unassigned | Not started |  |
| 5.2 | Meta business verification; own WhatsApp number per org | New | Unassigned | Not started |  |
| 5.3 | Slack Marketplace listing | New | Unassigned | Not started |  |
| 5.4 | Pricing and billing | New | Unassigned | Not started |  |
| 5.5 | Retire Tulpa v1 once Noa covers its features | New | Unassigned | Not started |  |
