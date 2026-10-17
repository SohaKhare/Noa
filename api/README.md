# Noa API

Phoenix + Ash. The only backend: the web app is a client of this API (PLAN.md, "Architecture").

What is here today:

- **Accounts, workspaces, invites** (1.4, 1.5, 1.6, 1.22): invite-only sign-in with password or magic link, work-email domains per workspace, Ash policies on every read. See [docs/auth.md](../docs/auth.md).
- **Extraction core** (1.16, 1.17, 1.21): chat lines in, typed and routed proposals out. See [docs/extraction.md](../docs/extraction.md).
- **Work** (1.23, 1.24): people, projects, allocations, channels, aliases, tasks and the Inbox, with the seed loader. See [docs/schema.md](../docs/schema.md).
- **`@noa`** (2.5): `Noa.Agent.ask/3` answers with numbered citations from tasks, decisions and chat messages the asker can see. With `OPENAI_API_KEY` it calls the model (strict schema, may only cite given sources); without it, it lists what it found. Discord and WhatsApp bots call the same function.
- **Event log and graph** (1.8 to 1.11): every Work write appends an event in its transaction; chat ingest records messages with `Noa.Work.record_message/2`, which resolves the author through `identities`; `Noa.Graph.Projector` mirrors the log into one FalkorDB graph per workspace.

```sh
docker compose up -d postgres            # from the repo root
docker compose --profile graph up -d     # FalkorDB, for the graph (the API runs without it)
mix setup                                # deps, database, migrations
mix noa.superadmin you@company.com --name "You"
mix noa.seed --sample                    # after creating the workspace: NYI org map plus dev tasks and proposals
mix noa.graph                            # log old rows and rebuild the workspace's graph from the event log
mix phx.server                           # http://localhost:4000, mailbox at /dev/mailbox
mix test                                 # needs the Postgres container (graph tests skip without FalkorDB); never calls a model
mix noa.extract --dry-run test/fixtures/messages.jsonl
```

Extraction (1.17) runs in the Oban job `Noa.Work.Extract`, 20 seconds after a channel's latest message; it needs `OPENAI_API_KEY` and is skipped without it. For ingest (1.13, 1.15), call `Noa.Work.record_message/2` for each message in a mapped channel; it refuses unread channels and stores a message delivered twice once.
