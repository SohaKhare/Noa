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
- Owners are exactly: `Unassigned`, `Saish`, `Vedant`, `Soha`. Phases 0 and 1 are pre-assigned. Later items start `Unassigned`: claim one by setting Owner to yourself (here and in the plan doc's Owner dropdown) when you start it. PLAN.md lists a suggested split for later phases.
- Never renumber items. Branch names and PR titles use the number, for example `vedant/1.9-graph-wrapper` and `1.9: Noa.Graph wrapper`.

Source key: **New** = written fresh. **Copy** = infrastructure copied from Tulpa v1. **Port** = rewritten from a Tulpa v1 pattern. **Import** = Tulpa v1 data.

## Phase 0: Setup (Oct 15 evening)

Exit test: Skeleton deploys to Fly with login; API reaches FalkorDB; graph and extraction schemas frozen in `docs/schema.md`; design direction set.

| # | Item | Source | Owner | Status | PR |
| --- | --- | --- | --- | --- | --- |
| 0.1 | Confirm the tools NYI uses daily | New | Saish | Not started |  |
| 0.2 | Ask organizers: judging, multi-track, Tulpa v1 reuse split | New | Saish | Not started |  |
| 0.3 | Freeze graph schema, extraction schemas, API contracts | New | Vedant | Not started |  |
| 0.4 | Wireframes for every page (UI and flows tab) | New | Saish | Not started |  |
| 0.5 | Spike: falkordb Elixir client (vector, full-text, PageRank, paths) | New | Vedant | Not started |  |
| 0.6 | Spike: Kapso send, receive, buttons, signed webhooks | New | Soha | Not started |  |
| 0.7 | Spike: Google Meet transcript API on one NYI meeting | New | Soha | Not started |  |
| 0.8 | Spike: ash_ai tools + MCP, ash_typescript, React Gantt library | New | Vedant | Not started |  |
| 0.9 | Spike: extraction prompt on 40 real NYI messages | Port | Saish | Not started |  |
| 0.10 | Register Discord, Slack and Google apps (Internal + External testing) | New | Soha | Not started |  |
| 0.11 | Kapso account, 3 WhatsApp templates, start Meta verification | New | Soha | Not started |  |
| 0.12 | FalkorDB Cloud, Fly.io, Postgres, Logfire, Sentry, domain | Copy | Vedant | Not started |  |
| 0.13 | Privacy policy and terms text | New | Soha | Not started |  |
| 0.14 | NYI org map: projects, people, roles, reporting lines, allocations, channel-to-project | New | Saish | Not started |  |
| 0.15 | Team consent for channels; export Tulpa v1 data | Import | Soha | Not started |  |
| 0.16 | 40-question golden set from real NYI questions | New | Soha | Not started |  |
| 0.17 | Design direction: reference board, theme, colors, type, light and dark | New | Saish | In progress |  |
| 0.18 | Design kit: shadcn tokens and core components (task card, person chip, status pill, panels) | New | Saish | In progress |  |
| 0.19 | Landing page design and copy | New | Saish | In progress |  |

## Phase 1: Chat to Kanban (Oct 16)

Exit test: A real Discord message becomes a proposed task in the right project and lands live on the Kanban once approved.

| # | Item | Source | Owner | Status | PR |
| --- | --- | --- | --- | --- | --- |
| 1.1 | New repo | Copy | Soha | Done |  |
| 1.2 | Fly deploy: Dockerfiles, `fly.toml`, release migrations | Copy | Vedant | Not started |  |
| 1.3 | Observability: Logfire/OpenTelemetry, LLM audit and usage | Copy | Vedant | Not started |  |
| 1.4 | Auth: password, magic link, Google, reset (AshAuthentication) | Copy | Vedant | Not started |  |
| 1.5 | Orgs, invites, access requests | Copy | Vedant | Not started |  |
| 1.6 | Roles and Ash policies: superadmin, org admin, PM/lead, member, guest | New | Vedant | Not started |  |
| 1.7 | Web shell: login and invite pages, dashboard layout, shadcn theme | Copy | Saish | In progress |  |
| 1.8 | Event log: append-only, idempotent, projections | Port | Vedant | Not started |  |
| 1.9 | `Noa.Graph` wrapper, schema bootstrap, indexes | New | Vedant | Not started |  |
| 1.10 | Event-to-FalkorDB projector | New | Vedant | Not started |  |
| 1.11 | Identity: `Person` + `Identity` nodes | Port | Vedant | Not started |  |
| 1.12 | Import Tulpa v1 history, decisions, projects, aliases, people | Import | Soha | Not started |  |
| 1.13 | Discord ingest: privacy gate, consumer, membership, backfill | Port | Soha | Not started |  |
| 1.14 | Slack Events webhook ingest | New | Soha | Not started |  |
| 1.15 | Kapso WhatsApp send and receive | New | Soha | Not started |  |
| 1.16 | Project routing: channel map, aliases, thread, author's projects | New | Saish | Not started |  |
| 1.17 | Task extraction v1 to proposals (from v1 distiller prompt) | Port | Saish | Not started |  |
| 1.18 | Onboarding: connect sources, map channels, add people and allocations | New | Soha | Not started |  |
| 1.19 | Inbox page (proposals) | New | Saish | In progress |  |
| 1.20 | Kanban board | New | Saish | In progress |  |
| 1.21 | Typed extraction schemas: Ecto embedded schemas to strict JSON schema, validated with InstructorLite | Port | Saish | Not started |  |
| 1.22 | Reporting lines (reports-to) in org map and people settings | New | Vedant | Not started |  |

## Phase 2: Work loop (Oct 16 evening to Oct 17 midday)

Exit test: NYI uses no other tracker; a developer and a non-tech teammate both run their day from Noa.

| # | Item | Source | Owner | Status | PR |
| --- | --- | --- | --- | --- | --- |
| 2.1 | Status, blocker and deadline extraction | New | Unassigned | Not started |  |
| 2.2 | Auto-apply with undo above a confidence threshold | New | Unassigned | Not started |  |
| 2.3 | Duplicate task matching before proposing | New | Unassigned | Not started |  |
| 2.4 | Decisions and supersession | Port | Unassigned | Not started |  |
| 2.5 | `@noa` agent with citations (ash_ai tools, audience-first rules) | Port | Unassigned | Not started |  |
| 2.6 | Approval buttons in Discord, Slack, WhatsApp | New | Unassigned | Not started |  |
| 2.7 | WhatsApp "done" replies move cards | New | Unassigned | Not started |  |
| 2.8 | Google Calendar + Meet transcripts to action items | New | Unassigned | Not started |  |
| 2.9 | Daily digest per person (from v1 recap) | Port | Unassigned | Not started |  |
| 2.10 | Message edit and delete handling | New | Unassigned | Not started |  |
| 2.11 | Gantt timeline: milestones, dependencies, drag dates | New | Unassigned | Not started |  |
| 2.12 | My day and my work (simple and detailed views) | New | Unassigned | Not started |  |
| 2.13 | Task detail: sources, history, undo | New | Unassigned | Not started |  |
| 2.14 | Live updates over Phoenix Channels | New | Unassigned | Not started |  |
| 2.15 | Notification preferences: channel, digest time, quiet hours | New | Unassigned | Not started |  |
| 2.16 | Permission leakage tests in CI | New | Unassigned | Not started |  |
| 2.17 | Eval harness on the golden set | Port | Unassigned | Not started |  |
| 2.18 | Decided today panel (per project and per person) | New | Unassigned | Not started |  |
| 2.19 | Change records for shared-item edits: scope, deadline, owner, status, decision | New | Unassigned | Not started |  |
| 2.20 | Lead approval rules: deadline and scope changes wait, minor edits apply with revert | New | Unassigned | Not started |  |
| 2.21 | Change notifications to lead and owner in app, Discord, Slack, WhatsApp | New | Unassigned | Not started |  |

## Phase 3: Shifts, KT and agent packs (Oct 17 afternoon to night)

Exit test: A real NYI teammate moves projects using only Noa, gets a KT brief and agent pack, and both boards stay correct.

| # | Item | Source | Owner | Status | PR |
| --- | --- | --- | --- | --- | --- |
| 3.1 | Shift backend: handover draft, reassignment suggestions, previous-owner routing | New | Unassigned | Not started |  |
| 3.2 | KT brief generator and follow-up Q&A | New | Unassigned | Not started |  |
| 3.3 | Experts via `KNOWS_ABOUT` + PageRank; bus factor | New | Unassigned | Not started |  |
| 3.4 | Slip propagation and drift detection | New | Unassigned | Not started |  |
| 3.5 | KT delivery and Q&A on WhatsApp and Discord | New | Unassigned | Not started |  |
| 3.6 | MCP server through ash_ai | New | Unassigned | Not started |  |
| 3.7 | GitHub PR merged closes card (beta) | New | Unassigned | Not started |  |
| 3.8 | WhatsApp voice notes, transcribed (beta) | New | Unassigned | Not started |  |
| 3.9 | Portfolio: project health, workload heatmap, risks | New | Unassigned | Not started |  |
| 3.10 | Project page: board, timeline, decisions, people, KT tabs | New | Unassigned | Not started |  |
| 3.11 | Shift wizard | New | Unassigned | Not started |  |
| 3.12 | KT brief page and checklist | New | Unassigned | Not started |  |
| 3.13 | Graph panel with path highlighting | New | Unassigned | Not started |  |
| 3.14 | Superadmin console: orgs, connectors, ops, LLM usage | Copy | Unassigned | Not started |  |
| 3.15 | Run one real NYI shift end to end | New | Unassigned | Not started |  |
| 3.16 | Backfill and rebuild-the-graph drill | New | Unassigned | Not started |  |
| 3.17 | Staffing board: drag-and-drop people with confirm popover | New | Unassigned | Not started |  |
| 3.18 | Agent pack generator: `CLAUDE.md`/`AGENTS.md`, `tasks.md`, `.mcp.json` from the project subgraph; regenerate on change | New | Unassigned | Not started |  |
| 3.19 | Role pack templates: `brief.md`, `client.md`, `runbook.md`, `project-state.md` | New | Unassigned | Not started |  |
| 3.20 | Access bundles per project: GitHub team, Discord role, Drive share; checklist for the rest | New | Unassigned | Not started |  |
| 3.21 | Secrets vault: encrypted per project, one-time 24-hour links, fetch audit, revoke on shift | New | Unassigned | Not started |  |
| 3.22 | Per-person, per-project MCP tokens | New | Unassigned | Not started |  |
| 3.23 | Pack delivery in app, Discord, WhatsApp; "add to repo" PR | New | Unassigned | Not started |  |

## Phase 4: Harden and ship (Oct 18)

Exit test: A new team reaches its first proposed tasks in under 10 minutes without help. Freeze at noon, submit by 6 PM IST.

| # | Item | Source | Owner | Status | PR |
| --- | --- | --- | --- | --- | --- |
| 4.1 | Feature freeze at noon IST | New | Unassigned | Not started |  |
| 4.2 | Load test on NYI's full history | New | Unassigned | Not started |  |
| 4.3 | Security pass: tokens, webhooks, policies | New | Unassigned | Not started |  |
| 4.4 | Empty, loading and error states on every page | New | Unassigned | Not started |  |
| 4.5 | Landing, privacy and terms pages (from v1 landing) | Copy | Unassigned | Not started |  |
| 4.6 | Second-team onboarding test on a fresh org | New | Unassigned | Not started |  |
| 4.7 | 3-minute video of real NYI use | New | Unassigned | Not started |  |
| 4.8 | README with architecture and setup; blog post | New | Unassigned | Not started |  |
| 4.9 | Submit on WeMakeDevs (all tracks allowed) | New | Unassigned | Not started |  |

## Phase 5: After the event (Later)

| # | Item | Source | Owner | Status | PR |
| --- | --- | --- | --- | --- | --- |
| 5.1 | Google OAuth verification for external orgs | New | Unassigned | Not started |  |
| 5.2 | Meta business verification; own WhatsApp number per org | New | Unassigned | Not started |  |
| 5.3 | Slack Marketplace listing | New | Unassigned | Not started |  |
| 5.4 | Pricing and billing | New | Unassigned | Not started |  |
| 5.5 | Retire Tulpa v1 once Noa covers its features | New | Unassigned | Not started |  |
