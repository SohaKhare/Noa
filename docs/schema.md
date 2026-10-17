# Schema (draft for 0.3)

Draft written with 1.24 on Oct 16; event log and graph added with 1.8 to 1.11 on Oct 17. Vedant approves it in 0.3; until then, ask in the team channel before changing it.

## Where state lives

| Store | Holds | Written by |
| --- | --- | --- |
| Postgres, Ash resources | Accounts, workspaces, invites, and the current state of work: people, projects, tasks, proposals | `Noa.Orgs` and `Noa.Work` functions only |
| Postgres, `events` (1.8) | Every change, append-only, plus every chat message read | `Noa.Events.Record` on each Work resource, in the write's transaction; ingest through `Noa.Work.record_message/2` |
| FalkorDB, graph `noa_<org id>` (1.9, 1.10) | The graph for questions, experts and paths | `Noa.Graph.Projector` only, from the event log |

Proposed decision: current state stays in Postgres because policies, the board and undo are simplest there. The graph is a projection of the event log and can be rebuilt from it (`mix noa.graph`).

## Work tables (1.24)

Every table has `org_id`. Reads need a membership in that org. Writes are checked per row by `Noa.Work.Checks.ActorInOrg` and Ash policies.

| Table | Graph node or edge | Key fields | Who writes |
| --- | --- | --- | --- |
| `people` | `Person` | `key` (seed id, e.g. `ve`), `name`, `title`, `email`, `handles` (chat and git names), `membership_id` once they join; notification preferences (2.15): `notify_via` (whatsapp, discord, email, in_app), `phone` (E.164), `digest_at`, `quiet_from`, `quiet_to`, `utc_offset` (minutes, 330 = IST) | Admins, PMs, the seed; each person sets their own preferences |
| `projects` | `Project` | `key` (e.g. `veriq`), `name`, `about`, `repo`, `status`, `lead_id` → person | Admins, PMs, the seed |
| `project_aliases` | alias on `Project` | `alias` (case-insensitive, unique per org), `project_id` | Admins, PMs, the seed |
| `allocations` | `WORKS_ON` | `person_id`, `project_id`, `percent`, `role`, `starts_on`, `ends_on`; never deleted, a shift sets `ends_on` | Admins, PMs, the seed |
| `channels` | `Channel` + `MAPS_TO` | `platform`, `name`, `external_id`, `project_id`, `split`, `read` | Admins, the seed |
| `tasks` | `Task` + `BELONGS_TO`, `ASSIGNED_TO`, `EXTRACTED_FROM` | `title`, `detail`, `status` (todo, in_progress, blocked, done), `due_on`, `blocked_reason`, `owner_id`, `source`, `done_at` | Members, PMs, admins (not guests); delete: PMs and admins |
| `proposals` | (Inbox only) | `kind` (task, status_change, deadline_change, decision, scope_change), `summary`, `data` (the typed item), `confidence`, `source`, `status` (pending, approved, rejected), `owner_id`, `project_id`, `task_id` | Noa's pipeline; decided by leads, or by the member it is about |
| `identities` | `Identity` + `HAS_IDENTITY` | `platform` (discord, slack, whatsapp, meet, github), `external_id`, `display_name`, `person_id` (empty until matched or linked) | Ingest through `Noa.Work.identify/4`; admins and PMs link |
| `decisions` | `Decision` + `DECIDED`, `AFFECTS`, `SUPERSEDES`, `EXTRACTED_FROM` | `statement`, `kind` (decision, conclusion), `status` (active, superseded), `affects` (task ids), `source`, `project_id`, `made_by_id` → person, `approved_by_id` → user, `superseded_by_id` | Created when a decision proposal is approved; never deleted, a newer decision marks the old one superseded |
| `changes` | `ChangeRecord` + `CHANGED` | `kind` (deadline, scope, owner, status, title), `old_value`, `new_value` (strings: ISO dates, ids, status names), `reason`, `status` (applied, pending, rejected, reverted), `source` (when it came from chat), `task_id`, `project_id`, `requested_by_id`, `decided_by_id` | Written by `Noa.Work.update_task/4` for every edit to a shared field; decided by leads; reverted by a lead or whoever made it |
| `shifts` | (allocations change; no node of its own) | `person_id`, `from_project_id`, `to_project_id` (nil is the bench), `percent`, `starts_on`, `routes_until` (14 days on), `handover` (`[{task_id, title, to_owner_id}]`), `note`, `created_by_id` | `Noa.Work.shift/3`, org admins and PMs; never edited |

`source` on tasks and proposals is `{channel, author, at, quote, episode_id}`; `episode_id` is the message's id in the event log and the graph (`<platform>:<message id>`).

People are linked to accounts by email, then by name, when the seed loads and whenever someone accepts an invite (`Noa.Work.link_people/1`).

## Event log (1.8)

Table `events`: `id` (the position, in commit order), `org_id`, `type`, `subject_id` (the row it is about), `data` (JSON), `actor_id`, `key` (unique per org when set), `occurred_at`.

| Type | When | `data` |
| --- | --- | --- |
| `person.saved`, `project.saved`, `alias.saved`, `channel.saved`, `identity.saved`, `allocation.saved`, `task.saved`, `decision.saved`, `change.saved`, `shift.saved`, `proposal.saved` | Any create or update of that row, by anyone (the seed, the API, Noa) | The row's public fields after the write |
| `<thing>.deleted` | A delete | The row's fields before it |
| `message.received` | Ingest read a message in a mapped, read channel | `episode_id` (= the key, `<platform>:<message id>`), `platform`, `channel`, `channel_id`, `project_id` (empty for split channels), `author`, `person_id`, `identity_id`, `text`, `at` |

Rules:

- A write and its event commit together; if the append fails, the write rolls back.
- A message delivered twice is stored once: `record_message` returns `{:duplicate, event}` the second time.
- Messages from unknown or unread channels are refused (`{:error, :not_read}`), and DMs have no channel row, so they never reach the log.
- `task.source.episode_id` is the message's `episode_id`, which links the card to the Episode in the graph.

## Graph (1.9, 1.10, 1.11)

One FalkorDB graph per org, named `noa_<org id without dashes>`. The projector reads the log after its saved position (`projections` table), turns each event into MERGE statements and saves the position. It wakes on appends and every 2 seconds, so the graph trails Postgres by a couple of seconds at most. Replaying an event twice changes nothing.

| Node | Key properties | From |
| --- | --- | --- |
| `Person` | `id`, `key`, `name`, `title`, `email`, `handles` | `person.saved` |
| `Identity` | `id`, `platform`, `external_id`, `name` | `identity.saved` |
| `Project` | `id`, `key`, `name`, `about`, `repo`, `status`, `aliases` | `project.saved`, `alias.*` |
| `Channel` | `id`, `name`, `platform`, `split`, `read` | `channel.saved` |
| `Task` | `id`, `title`, `detail`, `status`, `due`, `blocked_reason`, `done_at`, `created_at` | `task.saved` |
| `Episode` | `id` (the episode id), `text`, `at`, `platform`, `author` | `message.received` |
| `Decision` | `id`, `statement`, `kind`, `status`, `at` | `decision.saved` |
| `ChangeRecord` | `id`, `kind`, `old`, `new`, `status`, `reason`, `at` | `change.saved` |

| Edge | From and to | From event |
| --- | --- | --- |
| `HAS_IDENTITY` | Person → Identity | `identity.saved` |
| `LEADS` | Person → Project | `project.saved` |
| `WORKS_ON` | Person → Project, with `id`, `percent`, `role`, `from`, `to` | `allocation.saved` |
| `MAPS_TO` | Channel → Project | `channel.saved` |
| `BELONGS_TO`, `ASSIGNED_TO` | Task → Project, Task → Person | `task.saved` |
| `EXTRACTED_FROM` | Task → Episode | `task.saved` with `source.episode_id` |
| `AUTHORED`, `IN` | Person → Episode, Episode → Channel | `message.received` |
| `CHANGED` | ChangeRecord → Task | `change.saved` |
| `KNOWS_ABOUT` | Person → Project, with `weight` | Derived by `Noa.Graph.Experts.refresh/1` from the graph: finished tasks 3, decisions 3, owned open tasks 1, messages in the project's channels 1 |
| `DECIDED`, `AFFECTS`, `SUPERSEDES`, `EXTRACTED_FROM` | Person → Decision, Decision → Project and Task, newer → older Decision, Decision → Episode | `decision.saved` |

Indexes: range indexes on `id` for every label, full-text on `Episode.text` and `Task.title`. Still to come, with their items: `Topic` (topic-level `KNOWS_ABOUT`), `DEPENDS_ON` (2.11), and the vector index on Episode embeddings (2.5). Proposals stay out of the graph; they are the Inbox.

Reading: `Noa.Graph.ro_query(org_id, cypher, params)` returns rows as maps. Return properties, not whole nodes. Dates are ISO strings (FalkorDB 4.10 has no `date()`).

Local: `docker compose --profile graph up -d`, then `mix noa.graph` logs any rows written before the event log and rebuilds the workspace's graph. Without FalkorDB the API still works; the projector logs once and waits.

## Lead rules (2.19, 2.20)

A lead is an org admin or PM, or the person set as the project's lead (`Noa.Work.lead?/3`).

- Every edit to a task's deadline, scope (detail), owner, status or title writes a `changes` row with the old and new value.
- A lead's edits apply at once.
- Anyone else's deadline and scope changes are held as `pending` and the task keeps its old value until a lead approves (`POST /changes/:id/approve`) or rejects them. Their other edits apply at once.
- An applied change can be reverted by a lead or by whoever made it, if nobody changed that field again since (otherwise 409).
- Approved status and deadline proposals go through the same rules, so a member approving their own deadline change sends it to their lead.

## Shifts (3.1)

`Noa.Work.shift/3` moves a person in one transaction: it ends their allocation on the old project the day before `starts_on`, starts one on the new project (same percent unless given), and hands each open task they owned there to the owner the lead picked, or to the suggestion: the least-loaded other person on that project, else its lead. Each handover is an `owner` change record ("Handed over in a shift"), so it can be reverted. For 14 days `@noa` tells people to ask the person who left about the old project.

## Duplicates and auto-apply (2.3, 2.2)

- A new task proposal whose title names the same work as an open task in its project (`Noa.Work.Similar`: one title's words contain the other's, or 60% overlap) gets `data.duplicate_of` and the Inbox offers to dismiss it. A proposal matching one already pending is not stored again, since extraction windows overlap.
- At or above `config :noa, Noa.Work, auto_apply: 0.9`, two kinds apply themselves: a new task with a project and owner (not flagged as a duplicate), and a status change said by the task's own owner. Deadlines, scope and decisions always wait. It acts as the person who said it, and only if they have joined. The proposal is marked `data.auto`; `POST /proposals/:id/undo` (a lead or that person) removes a created task if nobody touched it, or reverts the status, and puts the proposal back in the Inbox.

## Approving a proposal

`Noa.Work.approve/3` runs in one transaction:

1. Checks the actor may decide it: an org admin or PM, or the person it is about.
2. Applies the edits made in the Inbox (title, project, owner, due).
3. Applies the proposal. A task creates a card; it needs a project, or the API answers 422 "Pick a project". A status change sets the task's status; a deadline change sets its due date. Decisions and scope changes are only marked approved until 2.4 and 2.19.
4. Marks the proposal approved, with who and when. A second approve answers 409.

## API (all under `/api/orgs/:org_id`)

| Method and path | Does |
| --- | --- |
| `GET /directory` | People (with current allocations), projects (lead, aliases, allocations), channels, and `me` (the signed-in person's id) |
| `GET /tasks?project_id=&owner_id=&open=true` | Tasks |
| `POST /tasks`, `PATCH /tasks/:id` | Create or change a task. `PATCH` takes an optional `reason` and answers with the task and its `pending_changes` |
| `GET /changes?task_id=&project_id=&status=` | Change records, newest first |
| `POST /changes/:id/approve`, `/reject`, `/revert` | Decide a pending change (leads), or undo an applied one |
| `GET /decisions?project_id=&since=&status=` | Decisions, newest first; `since` is ISO 8601, `status` is active or superseded |
| `PATCH /channels/:id` | Map a channel: `project_id`, `split`, `read` (org admins) |
| `POST /ask` | `@noa` (2.5): body `question`; answers `answer` (text with `[n]` markers) and `citations` (task, decision or message, with title, link and source). Reads only what the asker can see |
| `GET /me/notifications`, `PATCH /me/notifications` | The signed-in person's notification preferences. For delivery (2.9, 2.21): `Noa.Work.notify_target(person)` gives `{:whatsapp, phone}`, `{:discord, handle}`, `{:email, email}` or `:in_app`; `Noa.Work.quiet?(person)` says whether it is their quiet hours |
| `GET /shifts/plan?person_id=&from_project_id=` | What a move would hand over, with suggested owners |
| `POST /shifts` | Move someone: `person_id`, `from_project_id`, `to_project_id` (empty is the bench), `percent`, `starts_on`, `handover` (`{task_id: owner_id or ""}`), `note`. Org admins and PMs |
| `GET /shifts` | Moves, newest first |
| `GET /projects/:project_id/brief?person_id=` | KT brief (3.2): sections of cited items for someone joining the project |
| `GET /experts?project_id=` | Who knows the project (3.3), PageRank over the work graph (`key_people`), and bus-factor risks; empty with `graph: false` when FalkorDB is down |
| `GET /proposals` | Pending proposals, newest first |
| `POST /proposals/:id/approve` | Body can carry `summary`, `project_id`, `owner_id`, `data.title`, `data.due`, `data.new_due` |
| `POST /proposals/:id/reject` | Dismiss |
| `POST /proposals/:id/undo` | Undo an automatically applied proposal; it returns to the Inbox |

Ids in the path, and project or owner ids in a body, must belong to the org in the path, or the API answers 404.

## Seed

`mix noa.seed` loads [`seeds/nyi.json`](seeds/nyi.json) into the workspace with slug `notyouridea`. It is safe to run again. `--sample` also loads [`seeds/nyi-sample-work.json`](seeds/nyi-sample-work.json): ten tasks and four proposals for local development. Never load the sample into a real workspace.

Extraction reads the same data through `Noa.Work.vocabulary/1`, so routing uses the database's channel map, aliases and allocations rather than the seed file.
