# Agent instructions for Noa

Before any work, read [PLAN.md](PLAN.md) (product, architecture, graph schema, phases) and [TASKS.md](TASKS.md) (tracker).

- Find your developer's item in TASKS.md and work only on that item. Name the branch `<person>/<item>-<slug>`.
- In the same PR, update that item's row in TASKS.md: set the Status (`In progress`, `In review`, `Done` or `Cut`) and add the PR number. Never renumber rows.
- Write to FalkorDB only through the event-log projector. Postgres events are the source of truth.
- All LLM extraction goes through typed schemas (Ecto embedded schema → strict JSON schema, validated with InstructorLite). Never parse free text from a model.
- Every read path goes through Ash policies, including agent tools and MCP.
- When copying from Tulpa v1 (`~/code/nyi/tulpa`), rename `Tulpa.*` to `Noa.*` and keep only what the item needs.
- Never commit secrets. Add new env keys to `.env.example`.
- Don't change the graph schema or extraction types without asking the developer. Other people's work depends on them.
