# Extraction and routing

Contract for items 1.16 (routing), 1.17 (task extraction), 1.21 (typed schemas) and the 0.9 spike, implemented in `api/lib/noa/extraction` (see "Code"). Still a draft until the 0.3 freeze. Saish owns it; Vedant freezes it with the graph schema in 0.3. After the freeze, changes go through the team channel (PLAN.md, "Working rules").

Ported from Tulpa v1: `apps/api/lib/tulpa/decisions/distiller.ex` (windowing) and `extractor/open_ai.ex` (strict-schema prompt). What changed from v1 is called out as **New in Noa**.

## Pipeline

```
Episode appended (event log)
  → window: group a channel's recent Episodes into one chat window
  → route: pick a project per window, then per item (1.16)
  → extract: one strict-schema model call per window (1.17, 1.21)
  → validate: InstructorLite changesets; retry up to 2 times
  → ProposalCreated events → Inbox (Phase 1) or auto-apply with undo (2.2)
```

Extraction runs in an Oban job, never in the append path, the same as v1.

## Windows

Same rules as v1's distiller:

| Setting | Value | Why |
| --- | --- | --- |
| Session gap | 30 min | A pause this long starts a new conversation |
| Max window | 50 Episodes | Keeps one call small; long sessions are chunked |
| Overlap | 5 Episodes | An item that spans a chunk boundary is still seen whole |
| Prior context | 5 Episodes before the window | Lets "on it" resolve against the question above it |
| Schedule | every 15 min per active channel | No per-message model calls |

Each line goes to the model as `[sequence] Author: body`. The model cites sequences; the job maps them back to Episode ids, so every item gets `EXTRACTED_FROM` edges.

**New in Noa:** the window also carries the channel's timestamp and timezone (IST for NYI) so "by Friday" can become a date.

## Types (1.21)

Every type is an Ecto embedded schema compiled to a strict JSON schema. All share:

| Field | Type | Rule |
| --- | --- | --- |
| `evidence_sequences` | `[integer]` | Non-empty; every value must be in the window |
| `confidence` | `float` 0–1 | The model's own estimate; calibrated by the eval set (2.17) |
| `project` | `string` or `null` | A project id from the vocabulary, or `null` if unclear |

The model returns one object with one array per type, so a single call can find a new task and a decision in the same window:

```json
{
  "tasks": [],
  "status_changes": [],
  "deadline_changes": [],
  "decisions": [],
  "scope_changes": []
}
```

`ProjectRoute` is not a model output. It is created by routing when no project can be chosen (see below).

### TaskProposal

| Field | Type | Rule |
| --- | --- | --- |
| `title` | string | Imperative, at most 80 chars: "Board report PDF export" |
| `owner` | string or null | A person name or handle from the vocabulary; "I'll do it" resolves to the speaker |
| `due` | ISO date or null | Relative dates resolved against the window's date and timezone |
| `detail` | string or null | One sentence of acceptance or context, only if said |

### StatusChange

| Field | Type | Rule |
| --- | --- | --- |
| `task_ref` | string | The task as people named it; matched to an open task by the job |
| `status` | enum | `todo`, `in_progress`, `blocked`, `done` |
| `blocker` | string or null | Required when `status` is `blocked`: what it waits on |

### DeadlineChange

| Field | Type | Rule |
| --- | --- | --- |
| `task_ref` | string | As above |
| `new_due` | ISO date | Resolved like `due` |
| `reason` | string or null | Only if said |

### Decision

| Field | Type | Rule |
| --- | --- | --- |
| `statement` | string | The decision as a short sentence: "Score all seven model families" |
| `kind` | enum | `decision` or `conclusion`. v1's `action_item` is now a TaskProposal |
| `affects` | `[string]` | Task refs it changes, if any |
| `supersedes_ref` | string or null | An earlier decision it replaces, if named (2.4) |

### ScopeChange

| Field | Type | Rule |
| --- | --- | --- |
| `target_ref` | string | A task ref or the project name |
| `change` | enum | `add`, `remove`, `change` |
| `summary` | string | What changed, one sentence |

Scope and deadline changes always need the editor's lead to approve (2.20), whatever the confidence.

## Prompt (1.17)

The v1 rules are kept word for word where they still apply: extract only what the messages clearly support, cite exact sequences, prefer precision over recall, return empty arrays when nothing qualifies.

**New in Noa:** the system prompt gets three vocabulary blocks, built per org from the graph:

1. **Projects and aliases** (replaces v1's "existing themes"): `veriq: Veriq (aliases: reports, AI rep)`. The model must answer with an id from this list or `null`.
2. **People**: name, handles per platform, and title, so "@vedant" and "VedantNYI" are the same person.
3. **Open tasks** for the window's candidate projects (at most 40, newest first), so status and deadline changes can name a real task and new tasks are not duplicates (2.3).

The full prompt text is in `api/lib/noa/extraction/prompt.ex`.

## Routing (1.16)

Routing runs before extraction (to choose the vocabulary) and after it (per item). The first rule that gives an answer wins:

| Order | Rule | Confidence |
| --- | --- | --- |
| 1 | The channel `MAPS_TO` one project | 1.0 |
| 2 | The message is in a thread whose root was routed | root's |
| 3 | The message names a project or alias (only in split channels) | 0.9 |
| 4 | The model picked a project id from the vocabulary | model's |
| 5 | The author `WORKS_ON` exactly one current project | 0.7 |
| 6 | Otherwise: a `ProjectRoute` proposal ("Which project?") listing the author's projects and the model's pick | n/a |

In a mapped channel (rule 1), if the model is at least 0.8 sure the item belongs to a different project, the item still goes to the mapped project but is flagged in the Inbox with a "Move to…" suggestion. Mapped channels are never silently overridden.

DMs and unmapped channels never reach this step; the ingest privacy gate drops them.

## Validation and what happens next

InstructorLite `validate_changeset/2` rejects, and the call retries (at most 2 retries), when:

- a sequence is outside the window,
- `owner` does not resolve to a Person in the org (it is set to `null` instead if the name is ambiguous),
- `project` is not in the vocabulary,
- `due` is more than a day in the past,
- a required string is blank.

Each surviving item becomes a `ProposalCreated` event with its type, payload, Episode ids, confidence and route.

| Confidence | Phase 1 | From 2.2 |
| --- | --- | --- |
| ≥ 0.9 | Inbox | Status changes by the task's own owner apply with undo; everything else goes to the Inbox |
| 0.5 to 0.9 | Inbox | Inbox |
| < 0.5 | Dropped, logged for the eval set | Same |

## Code

The contract is implemented in `api/lib/noa/extraction/` as plain Elixir with no database, so it runs before the Phoenix app exists. The Phoenix app calls it from an Oban job and turns each proposal into a `ProposalCreated` event.

| Module | Does |
| --- | --- |
| `Noa.Extraction` | `windows/2`, then `extract/3`: a window in, routed proposals out; drops items under 0.5 |
| `Noa.Extraction.Window` | Sessions, chunks and context (the table under "Windows") |
| `Noa.Extraction.Vocabulary` | Projects, aliases, people, channel routes, allocations; `nyi_seed/0` loads `docs/seeds/nyi.json` |
| `Noa.Extraction.Result` and `Types.*` | The five types as Ecto embedded schemas, the hand-written strict JSON schema, and validation |
| `Noa.Extraction.Prompt` | The rules and the vocabulary blocks |
| `Noa.Extraction.Routing` | The six routing rules |
| `Noa.Extraction.Model.OpenAI` | One InstructorLite call per window (Responses API), 2 retries |
| `Noa.Extraction.Model.Stub` | Canned responses for tests |
| `mix noa.extract` | Runs the pipeline over a JSONL file and prints a review table (the 0.9 spike) |

## Spike (0.9)

```sh
cd api
mix noa.extract --dry-run test/fixtures/messages.jsonl   # windows and the exact request, no key needed
OPENAI_API_KEY=... mix noa.extract path/to/messages.jsonl
```

Input is one JSON object per line: `seq`, `channel`, `author`, `at` (ISO 8601 with offset), `body`. `test/fixtures/messages.jsonl` is made-up sample chat. For the spike, use 40 real NYI messages from the Tulpa v1 export (0.15) or Discord, and keep the file out of git. Mix new tasks, "on it" replies, status updates, moved deadlines, decisions, and chatter that should produce nothing.

Score each window by hand and record the totals in the 0.9 row of the plan doc:

- **Precision** = right items / extracted items. Target at least 0.9; it keeps the Inbox trustworthy.
- **Recall** = right items / items a person would extract. Target at least 0.7.
- **Routing** = items routed to the right project / all items.

An "Invalid after retries" line means the model kept breaking a validation rule: a prompt bug to fix before the freeze.

## Open questions for the 0.3 freeze

- One call per window for all types (proposed above), or one call per type? One call is cheaper and lets the model see that a reply is both a task and a decision. Per-type calls are easier to tune. Decide after the 0.9 spike.
- Model and reasoning effort. v1 used `gpt-5.6-luna` at low effort.
- Whether Meet transcripts (2.8) use the same windows, chunked by speaker turns instead of time gaps.
