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
| `people` | `Person` | `key` (seed id, e.g. `ve`), `name`, `title`, `email`, `handles` (chat and git names), `membership_id` once they join | Admins, PMs, the seed |
| `projects` | `Project` | `key` (e.g. `veriq`), `name`, `about`, `repo`, `status`, `lead_id` → person | Admins, PMs, the seed |
| `project_aliases` | alias on `Project` | `alias` (case-insensitive, unique per org), `project_id` | Admins, PMs, the seed |
| `allocations` | `WORKS_ON` | `person_id`, `project_id`, `percent`, `role`, `starts_on`, `ends_on`; never deleted, a shift sets `ends_on` | Admins, PMs, the seed |
| `channels` | `Channel` + `MAPS_TO` | `platform`, `name`, `external_id`, `project_id`, `split`, `read` | Admins, the seed |
| `tasks` | `Task` + `BELONGS_TO`, `ASSIGNED_TO`, `EXTRACTED_FROM` | `title`, `detail`, `status` (todo, in_progress, blocked, done), `due_on`, `blocked_reason`, `owner_id`, `source`, `done_at` | Members, PMs, admins (not guests); delete: PMs and admins |
| `proposals` | (Inbox only) | `kind` (task, status_change, deadline_change, decision, scope_change), `summary`, `data` (the typed item), `confidence`, `source`, `status` (pending, approved, rejected), `owner_id`, `project_id`, `task_id` | Noa's pipeline; decided by leads, or by the member it is about |
| `identities` | `Identity` + `HAS_IDENTITY` | `platform` (discord, slack, whatsapp, meet, github), `external_id`, `display_name`, `person_id` (empty until matched or linked) | Ingest through `Noa.Work.identify/4`; admins and PMs link |

`source` on tasks and proposals is `{channel, author, at, quote, episode_id}`; `episode_id` is the message's id in the event log and the graph (`<platform>:<message id>`).

People are linked to accounts by email, then by name, when the seed loads and whenever someone accepts an invite (`Noa.Work.link_people/1`).

## Event log (1.8)

Table `events`: `id` (the position, in commit order), `org_id`, `type`, `subject_id` (the row it is about), `data` (JSON), `actor_id`, `key` (unique per org when set), `occurred_at`.

| Type | When | `data` |
| --- | --- | --- |
| `person.saved`, `project.saved`, `alias.saved`, `channel.saved`, `identity.saved`, `allocation.saved`, `task.saved`, `proposal.saved` | Any create or update of that row, by anyone (the seed, the API, Noa) | The row's public fields after the write |
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

| Edge | From and to | From event |
| --- | --- | --- |
| `HAS_IDENTITY` | Person → Identity | `identity.saved` |
| `LEADS` | Person → Project | `project.saved` |
| `WORKS_ON` | Person → Project, with `id`, `percent`, `role`, `from`, `to` | `allocation.saved` |
| `MAPS_TO` | Channel → Project | `channel.saved` |
| `BELONGS_TO`, `ASSIGNED_TO` | Task → Project, Task → Person | `task.saved` |
| `EXTRACTED_FROM` | Task → Episode | `task.saved` with `source.episode_id` |
| `AUTHORED`, `IN` | Person → Episode, Episode → Channel | `message.received` |

Indexes: range indexes on `id` for every label, full-text on `Episode.text` and `Task.title`. Still to come, with their items: `Decision`, `SUPERSEDES`, `AFFECTS` (2.4), `ChangeRecord`, `CHANGED` (2.19), `Topic`, `KNOWS_ABOUT` (3.3), `DEPENDS_ON` (2.11), and the vector index on Episode embeddings (2.5). Proposals stay out of the graph; they are the Inbox.

Reading: `Noa.Graph.ro_query(org_id, cypher, params)` returns rows as maps. Return properties, not whole nodes. Dates are ISO strings (FalkorDB 4.10 has no `date()`).

Local: `docker compose --profile graph up -d`, then `mix noa.graph` logs any rows written before the event log and rebuilds the workspace's graph. Without FalkorDB the API still works; the projector logs once and waits.

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
| `POST /tasks`, `PATCH /tasks/:id` | Create or change a task |
| `GET /proposals` | Pending proposals, newest first |
| `POST /proposals/:id/approve` | Body can carry `summary`, `project_id`, `owner_id`, `data.title`, `data.due`, `data.new_due` |
| `POST /proposals/:id/reject` | Dismiss |

Ids in the path, and project or owner ids in a body, must belong to the org in the path, or the API answers 404.

## Seed

`mix noa.seed` loads [`seeds/nyi.json`](seeds/nyi.json) into the workspace with slug `notyouridea`. It is safe to run again. `--sample` also loads [`seeds/nyi-sample-work.json`](seeds/nyi-sample-work.json): ten tasks and four proposals for local development. Never load the sample into a real workspace.

Extraction reads the same data through `Noa.Work.vocabulary/1`, so routing uses the database's channel map, aliases and allocations rather than the seed file.
