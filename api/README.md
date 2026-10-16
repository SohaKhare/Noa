# Noa API

Phoenix + Ash. The only backend: the web app is a client of this API (PLAN.md, "Architecture").

What is here today:

- **Accounts, workspaces, invites** (1.4, 1.5, 1.6, 1.22): invite-only sign-in with password or magic link, work-email domains per workspace, Ash policies on every read. See [docs/auth.md](../docs/auth.md).
- **Extraction core** (1.16, 1.17, 1.21): chat lines in, typed and routed proposals out. See [docs/extraction.md](../docs/extraction.md).

```sh
docker compose up -d postgres            # from the repo root
mix setup                                # deps, database, migrations
mix noa.superadmin you@company.com --name "You"
mix phx.server                           # http://localhost:4000, mailbox at /dev/mailbox
mix test                                 # needs the Postgres container; never calls a model
mix noa.extract --dry-run test/fixtures/messages.jsonl
```

Next for Vedant's items: the event log (1.8), `Noa.Graph` (1.9) and the projector (1.10). FalkorDB is in `docker-compose.yml` under the `graph` profile: `docker compose --profile graph up -d`.
