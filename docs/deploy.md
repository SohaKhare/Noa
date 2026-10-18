# Deploying Noa (0.12, 1.2)

Noa is five parts: Postgres, FalkorDB, the Phoenix API, the web app and the landing page. The plan for the demo week:

| Part | Where | Host |
| --- | --- | --- |
| Landing | Vercel | `heynoa.xyz` |
| Web app | Vercel | `app.heynoa.xyz` |
| API (and webhooks `/webhooks/kapso`, MCP `/mcp`) | Fly.io, one machine | `api.heynoa.xyz` |
| Postgres | Fly Postgres, private network | |
| Graph | FalkorDB on Fly, private network (`heynoa-graph`) | |

About $5 on Fly for a week (API, Postgres and FalkorDB); Vercel costs nothing at this size. FalkorDB Cloud's free tier also works for the graph (section 1), but it deletes an instance after 7 days without use and has no backups or TLS. Other ways to run it: everything on Fly, or everything on one server with Docker Compose (both below).

DNS is on Cloudflare: set the Fly and Vercel records to "DNS only" (grey cloud) so both can issue certificates.

**Who sets what.** The Noa admin (superadmin) owns the platform: the Fly app, its secrets, Noa's Discord bot and the Kapso WhatsApp number. Each company's org admin connects their own Discord server and GitHub in Settings → Connectors; their GitHub secrets are encrypted at rest with keys derived from `SECRET_KEY_BASE` (rotating it means reconnecting GitHub).

**The app and the API must share a parent domain.** The web app signs in with an httpOnly, SameSite=Lax cookie set by the API, which is only sent between hosts of the same site. `app.heynoa.xyz` and `api.heynoa.xyz` work; a `*.vercel.app` app talking to a `*.fly.dev` API does not.

## Secrets

| Name | Needed | What |
| --- | --- | --- |
| `SECRET_KEY_BASE`, `TOKEN_SIGNING_SECRET` | yes | `openssl rand -base64 48` each |
| `DATABASE_URL` | yes | Set by `fly postgres attach` |
| `FALKORDB_URL` | yes | From the FalkorDB Cloud dashboard: `redis://<user>:<password>@<host>:<port>` (`rediss://` on paid plans with TLS) |
| `WEB_ORIGIN`, `API_BASE_URL` | yes | `https://app...`, `https://api...` (in `api/fly.toml`) |
| `RESEND_API_KEY`, `MAIL_FROM_EMAIL` | for email | Without a key, emails (invites, magic links) are written to the API log |
| `OPENAI_API_KEY` | for extraction | Without it, chat is recorded but not turned into proposals, and `@noa` answers extractively |
| `KAPSO_*` | for WhatsApp | See docs/whatsapp.md; webhook `https://api.../webhooks/kapso` |
| `DISCORD_BOT_TOKEN`, `DISCORD_CLIENT_ID` | for Discord | Noa's bot, run by the Noa admin. Each company's org admin adds it to their server and connects the server in Settings → Connectors. Empty token keeps Discord off |
| `GITHUB_APP_ID`, `GITHUB_APP_SLUG`, `GITHUB_APP_PRIVATE_KEY`, `GITHUB_APP_WEBHOOK_SECRET` | for GitHub | Noa's GitHub App, registered once by the Noa admin; each company installs it from Settings → Connectors. Without it, org admins can add webhooks by hand with their own secret. See docs/github.md |

## 1. Graph: FalkorDB Cloud

At [app.falkordb.cloud](https://app.falkordb.cloud), create a free instance on AWS or GCP in the region closest to Mumbai (`@noa` runs several graph queries per answer, so distance shows). Copy its host, port, user and password into `FALKORDB_URL`.

The free tier has 100 MB (plenty for one company), no TLS and no backups; an instance unused for a day is stopped, and after seven days deleted. Noa's health check pings the graph every 15 seconds, which keeps it in use, and the graph can always be rebuilt from Postgres with `Noa.Release.graph/1`.

## 2. API and Postgres: Fly.io

Region `sin` (Singapore, the closest to India; Fly has no Mumbai region); change `primary_region` in `api/fly.toml` for another. App names on Fly are global: if `heynoa-api` or `heynoa-db` is taken, pick another and change `app` in `api/fly.toml`.

```sh
fly auth login

# Postgres
fly postgres create --name heynoa-db --region sin --initial-cluster-size 1 --vm-size shared-cpu-1x --volume-size 3

# API (exactly one machine: the projector, WhatsApp notifier and Discord gateway are singletons)
cd api
fly launch --no-deploy --copy-config --name heynoa-api
fly postgres attach heynoa-db --app heynoa-api
fly secrets set --app heynoa-api \
  SECRET_KEY_BASE="$(openssl rand -base64 48)" \
  TOKEN_SIGNING_SECRET="$(openssl rand -base64 48)" \
  FALKORDB_URL="redis://<user>:<password>@<host>:<port>"
# Optional, any time later (each change restarts the machine):
#   fly secrets set --app heynoa-api OPENAI_API_KEY=... RESEND_API_KEY=... \
#     KAPSO_API_KEY=... KAPSO_PHONE_NUMBER_ID=... KAPSO_WEBHOOK_SECRET=... \
#     DISCORD_BOT_TOKEN=... DISCORD_CLIENT_ID=...
fly deploy --ha=false
fly certs add api.heynoa.xyz --app heynoa-api    # then add the DNS record it prints
cd ..
```

Keep `WEB_ORIGIN` and `API_BASE_URL` in `api/fly.toml` in step with your hosts; they decide CORS, the links in emails and where magic links land.

## 3. Web app and landing: Vercel

Import the repo into Vercel twice, one project each:

| Project | Root Directory | Environment variable | Domain |
| --- | --- | --- | --- |
| heynoa-web | `web` | `NEXT_PUBLIC_API_URL=https://api.heynoa.xyz` | `app.heynoa.xyz` |
| heynoa-landing | `landing` | `NEXT_PUBLIC_APP_URL=https://app.heynoa.xyz` (and `NEXT_PUBLIC_CDN_URL` if not `https://cdn.saish.xyz`) | `heynoa.xyz` |

Vercel detects Next.js and the pnpm workspace; keep "Include files outside the Root Directory" on, for `packages/theme`. `NEXT_PUBLIC_*` values are built into the bundle, so redeploy after changing one.

## Everything on Fly (alternative)

Instead of FalkorDB Cloud, run FalkorDB as a private Fly app; instead of Vercel, run web and landing on Fly:

```sh
fly launch --no-deploy --copy-config -c deploy/fly.graph.toml --name heynoa-graph
fly volumes create falkor_data --app heynoa-graph --region sin --size 3
fly secrets set --app heynoa-graph REDIS_ARGS="--bind 0.0.0.0 :: --requirepass <graph-password> --appendonly yes"
fly deploy -c deploy/fly.graph.toml --ha=false
# then set FALKORDB_IPV6 = "true" in api/fly.toml, and
fly secrets set --app heynoa-api FALKORDB_URL="redis://:<graph-password>@heynoa-graph.internal:6379"

fly launch --no-deploy --copy-config -c deploy/fly.web.toml --name heynoa-web
fly deploy -c deploy/fly.web.toml --dockerfile web/Dockerfile .
fly launch --no-deploy --copy-config -c deploy/fly.landing.toml --name heynoa-landing
fly deploy -c deploy/fly.landing.toml --dockerfile landing/Dockerfile .
fly certs add app.heynoa.xyz --app heynoa-web
fly certs add heynoa.xyz --app heynoa-landing
```

### First run

```sh
fly ssh console --app heynoa-api -C "/app/bin/noa rpc 'Noa.Release.superadmin(\"you@notyouridea.com\", \"Your Name\")'"
```

Sign in at `https://app.../login`, create the workspace (slug `notyouridea`) in the console and accept its invite. Then load the org map and build the graph:

```sh
fly ssh console --app heynoa-api -C "/app/bin/noa rpc 'Noa.Release.seed(\"notyouridea\")'"
fly ssh console --app heynoa-api -C "/app/bin/noa rpc 'Noa.Release.graph(\"notyouridea\")'"
```

`seed` is safe to run again. `Noa.Release.seed("notyouridea", sample: true)` also loads sample work (demo only).

### Check it

```sh
curl https://api.heynoa.xyz/healthz     # {"ok":true,"db":true,"graph":true}
fly logs --app heynoa-api
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
- **Tearing down.** Stopped machines stop billing but volumes don't: when you are done, `fly apps destroy heynoa-api heynoa-db` (and `heynoa-graph`, `heynoa-web`, `heynoa-landing` if used). That deletes the data; `pg_dump` first to keep it.
- **Backups.** Postgres is the system of record; the graph can always be rebuilt from it with `Noa.Release.graph/1`. Back up Postgres (`fly postgres` snapshots, or `pg_dump` on one server).
- **Images.** `api/Dockerfile` builds an Elixir release (Elixir 1.20.2, OTP 29). `web/Dockerfile` and `landing/Dockerfile` build Next.js standalone servers from the pnpm workspace; build them from the repo root.
