# Deploying Noa (0.12, 1.2)

Noa is five services: Postgres, FalkorDB, the Phoenix API, the web app and the landing page. Two ways to run them:

- **Fly.io** (the plan): one Fly app per service, Fly Postgres, FalkorDB on a private Fly app with a volume.
- **One server**: `deploy/docker-compose.prod.yml` runs all five plus Caddy for HTTPS on any VM with Docker.

Either way, use three hosts under one parent domain, for example:

| Host | Serves |
| --- | --- |
| `noa.notyouridea.com` | landing |
| `app.notyouridea.com` | web app |
| `api.notyouridea.com` | API, webhooks (`/webhooks/kapso`), MCP (`/mcp`) |

The web app signs in with an httpOnly, SameSite=Lax cookie set by the API. That only works when the app and API are the same site, so they must share a parent domain. Two `*.fly.dev` hosts are different sites and sign-in will not stick; use custom domains.

## Secrets

| Name | Needed | What |
| --- | --- | --- |
| `SECRET_KEY_BASE`, `TOKEN_SIGNING_SECRET` | yes | `openssl rand -base64 48` each |
| `DATABASE_URL` | yes | Fly sets it when you attach Postgres |
| `FALKORDB_URL` | yes | `redis://:<password>@noa-graph.internal:6379` on Fly; `rediss://` for FalkorDB Cloud |
| `WEB_ORIGIN`, `API_BASE_URL` | yes | `https://app...`, `https://api...` (in `api/fly.toml`) |
| `RESEND_API_KEY`, `MAIL_FROM_EMAIL` | for email | Without a key, emails (invites, magic links) are written to the API log |
| `OPENAI_API_KEY` | for extraction | Without it, chat is recorded but not turned into proposals, and `@noa` answers extractively |
| `KAPSO_*` | for WhatsApp | See docs/whatsapp.md; webhook `https://api.../webhooks/kapso` |
| `DISCORD_BOT_TOKEN`, `DISCORD_GUILD_ID`, `DISCORD_ORG_ID` | for Discord | Empty token keeps Discord off |

## Fly.io

Run from the repo root. Region `bom` (Mumbai); change `primary_region` in the four configs if you want another.

```sh
fly auth login

# 1. Postgres
fly postgres create --name noa-db --region bom --initial-cluster-size 1 --vm-size shared-cpu-1x --volume-size 3

# 2. FalkorDB (private network only)
fly launch --no-deploy --copy-config -c deploy/fly.graph.toml --name noa-graph
fly volumes create falkor_data --app noa-graph --region bom --size 3
fly secrets set --app noa-graph REDIS_ARGS="--bind 0.0.0.0 :: --requirepass <graph-password> --appendonly yes"
fly deploy -c deploy/fly.graph.toml --ha=false

# 3. API (exactly one machine: the projector, WhatsApp notifier and Discord gateway are singletons)
cd api
fly launch --no-deploy --copy-config --name noa-api
fly postgres attach noa-db --app noa-api
fly secrets set --app noa-api \
  SECRET_KEY_BASE="$(openssl rand -base64 48)" \
  TOKEN_SIGNING_SECRET="$(openssl rand -base64 48)" \
  FALKORDB_URL="redis://:<graph-password>@noa-graph.internal:6379" \
  RESEND_API_KEY=... OPENAI_API_KEY=... \
  KAPSO_API_KEY=... KAPSO_PHONE_NUMBER_ID=... KAPSO_WEBHOOK_SECRET=... \
  DISCORD_BOT_TOKEN=... DISCORD_GUILD_ID=... DISCORD_ORG_ID=...
fly deploy --ha=false
cd ..

# 4. Web and landing (NEXT_PUBLIC_* are build args in their configs)
fly launch --no-deploy --copy-config -c deploy/fly.web.toml --name noa-web
fly deploy -c deploy/fly.web.toml --dockerfile web/Dockerfile .
fly launch --no-deploy --copy-config -c deploy/fly.landing.toml --name noa-landing
fly deploy -c deploy/fly.landing.toml --dockerfile landing/Dockerfile .

# 5. Domains (then add the DNS records fly prints)
fly certs add api.notyouridea.com --app noa-api
fly certs add app.notyouridea.com --app noa-web
fly certs add noa.notyouridea.com --app noa-landing
```

App names on Fly are global; if `noa-api` is taken, pick another and change `app` in the config. Keep `WEB_ORIGIN` and `API_BASE_URL` in `api/fly.toml` and the build args in `deploy/fly.web.toml` and `deploy/fly.landing.toml` in step with your hosts.

### First run

```sh
fly ssh console --app noa-api -C "/app/bin/noa rpc 'Noa.Release.superadmin(\"you@notyouridea.com\", \"Your Name\")'"
```

Sign in at `https://app.../login`, create the workspace (slug `notyouridea`) in the console and accept its invite. Then load the org map and build the graph:

```sh
fly ssh console --app noa-api -C "/app/bin/noa rpc 'Noa.Release.seed(\"notyouridea\")'"
fly ssh console --app noa-api -C "/app/bin/noa rpc 'Noa.Release.graph(\"notyouridea\")'"
```

`seed` is safe to run again. `Noa.Release.seed("notyouridea", sample: true)` also loads sample work (demo only).

### Check it

```sh
curl https://api.notyouridea.com/healthz     # {"ok":true,"db":true,"graph":true}
fly logs --app noa-api
```

`/healthz` answers 503 when Postgres is down; the graph is reported but not required, because the API keeps working without it and the projector catches up.

## One server (Docker Compose)

On a VM with Docker and ports 80 and 443 open, with DNS for the three hosts pointing at it:

```sh
cp deploy/prod.env.example deploy/prod.env      # fill it in
docker compose -f deploy/docker-compose.prod.yml --env-file deploy/prod.env up -d --build
docker compose -f deploy/docker-compose.prod.yml exec api /app/bin/noa rpc 'Noa.Release.superadmin("you@notyouridea.com", "Your Name")'
docker compose -f deploy/docker-compose.prod.yml exec api /app/bin/noa rpc 'Noa.Release.seed("notyouridea")'
docker compose -f deploy/docker-compose.prod.yml exec api /app/bin/noa rpc 'Noa.Release.graph("notyouridea")'
```

Caddy gets the certificates. The API runs migrations on every start. Postgres, FalkorDB and Caddy keep their data in named volumes.

## Notes

- **One API machine.** The projector, the WhatsApp notifier and the Discord gateway each run once per node. Two API machines would send WhatsApp messages twice. Scale up the machine, not out.
- **Rate limits** key on `fly-client-ip` on Fly and on `X-Real-IP` (set by Caddy) on one server; `CLIENT_IP_HEADER` picks the header.
- **Backups.** Postgres is the system of record; the graph can always be rebuilt from it with `Noa.Release.graph/1`. Back up Postgres (`fly postgres` snapshots, or `pg_dump` on one server).
- **Images.** `api/Dockerfile` builds an Elixir release (Elixir 1.20.2, OTP 29). `web/Dockerfile` and `landing/Dockerfile` build Next.js standalone servers from the pnpm workspace; build them from the repo root.
