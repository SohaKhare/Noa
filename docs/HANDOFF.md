# Handoff: where Noa stands (Oct 18, 2026, evening IST)

Read this first in a new session. It covers what is built, what is deployed, what is uncommitted, where the credentials are, and what to do next. Standing rules from Saish: **don't push to GitHub, don't commit (Saish commits), don't call fal.ai.** Never print credentials; they live in the gitignored files listed below.

## Current: authorized pending-changes rollout

Saish explicitly authorized reviewing/committing all remaining changes and adding Slack/Attendee settings to Fly, then confirmed API-only deployment; Soha will redeploy the frontends. Branch: `saish/1.2-pending-integrations-deploy`, based on main `cacda07`; code PR #12 is merged, and deployment confirmation is recorded in docs-only PR #13. Slack #9 and Attendee #11 are included. Four settings (`SLACK_CLIENT_ID`, `SLACK_CLIENT_SECRET`, `SLACK_SIGNING_SECRET`, `ATTENDEE_API_KEY`) are now Deployed on `heynoa-api`; existing database/OpenAI secrets are untouched. No secret values were printed or committed.

Included: WhatsApp `tasks`/`my tasks` lists and task-completion lead notifications, README graph explanations, phased real-data demo plan. Review removed a policy-bypassing project lookup from the new task-list path, bounded long replies, and made the new completion owner fallback nil-safe. Validation: 249 API tests pass (1 load excluded), four voice-worker tests pass, compile warnings-as-errors/format and both frontend type/lint checks pass; all GitHub API/voice/frontend/image checks passed. Deployed image: `registry.fly.io/heynoa-api:release-cd22820`, digest `sha256:67dc2e1aecaefa2be49ece30d921f04103c79a19fab31a17ff651d275861d5c4`. Release migrations succeeded; existing singleton machine `6835e1ea567078` is started with passing checks. `/healthz` reports ok/db/graph true. Runtime confirms Slack/Attendee/LLM configured, signed Slack challenge returns 200 with the right challenge, and Attendee authenticated GET `/api/v1/bots` returns 200. No bots were created or calls recorded. Do not claim a workspace install or real recording/transcription success. Discord voice remains disabled. Both Vercel statuses on base `cacda07` report completed; new PR deployment checks are blocked, local CLI has no credentials, and frontend redeployment is handed to Soha.

## PR #8: meeting extension

Saish explicitly authorized committing, pushing and merging this extension via a PR, overriding the standing no-commit/push rule for this operation only. PR: https://github.com/SohaKhare/Noa/pull/8 (`saish/2.22-meeting-minutes` → `main`). Implementation is code-complete; deployment and real voice/ASR acceptance remain pending and recording defaults off. Unrelated demo and setup-tracker edits are deliberately left uncommitted. GitHub API/voice/Next.js checks passed; image checks are being verified. Both Vercel deployments are reported blocked, also present on the pre-existing base commit; do not describe those deployments as successful.

## Latest: meeting extension built locally (not deployed/enabled)

- Current branch: `saish/2.22-meeting-minutes`, based on Saish's new `962c024` Discord/mail commit. Those commits/checkouts landed concurrently; meeting-specific tracked wiring was restored on top without reverting SMTP/landing/other work. The agent created no commits or pushes.
- Item 2.22 is In review. `/noa meeting start/consent/stop/cancel/notes`, an opt-in DAVE-capable Node receiver, shared typed minutes pipeline and authenticated Meet transcript/list/detail API are implemented. Soha retains ownership of the Google Meet joining bot (2.8); send her `docs/meetings.md` for the exact transcript contract.
- Pinned Nostrum cannot handle modern DAVE voice. A private stdin/stdout Node worker uses discord.js, @discordjs/voice 0.19.2, @snazzah/davey, @noble/ciphers and opusscript, without upgrading the text bot. The Dockerfile now includes Node and locked worker dependencies. No FFmpeg/audio files/public worker socket.
- Voice is off unless `DISCORD_VOICE_ENABLED=true`; optional `DISCORD_VOICE_BOT_TOKEN`, otherwise the shared bot token. Needs Node >=22.12, OpenAI ASR + an available minutes model, Connect/View permissions, connected/consented text source, and verified linked accounts for all voice participants. No voice call, audio upload, real transcription or real minutes model call was performed. Do not claim live success yet.
- Organizer must be org admin/PM. Every participant consents individually within ten minutes before the bot joins. New unconsented arrivals stop recording; any participant can stop/cancel. Accounts/memberships/channel consent are rechecked before ASR. Speaker ids map to canonical verified org-map names/keys, not Discord nicknames. Interrupted recordings are marked partial; restarts fail sessions closed.
- New Postgres `meetings` resource/migration/Ash snapshot track state and a transcript cache; individual utterances are existing source Episodes. Strict `Noa.Meetings.Minutes` reuses current task/decision shapes. No graph labels/edges or existing extraction schemas changed. All work stays pending human approval, and the normal chat extractor excludes meeting Episodes so later chat cannot bypass meeting review.
- Checks: **215 API tests passed, 1 load excluded**; compile warnings-as-errors, format, web TypeScript and ESLint passed. Four worker tests pass both locally and inside the built Linux release image (including DAVE/Opus/XChaCha loading). Eighteen meeting-specific tests also passed on a fresh test database. Docker release image builds successfully. No new production deployment or voice enabling was done.
- Next: review/commit as Saish, deploy API + migration + worker, re-register commands, explicitly enable only for a consented two-person test. Verify real speaker/timestamp accuracy, jokes omitted from minutes, newcomers stop capture, citations and pending approvals. Local dev needs `mix ecto.migrate` and API restart; `cd api/priv/voice && npm ci --ignore-scripts` for worker deps. See `docs/meetings.md` for limits, retained transcript visibility and the live checklist.

## Earlier: Discord completion deployed

- Current branch `saish/2.6-discord-interactions`, based on `c33af97`. No new commits or pushes; all local changes remain for Saish to commit. SMTP was undone and remains Soha's task.
- Built `/noa ask`, `link`, `tasks`, `inbox`, `recap`, `brief`, `connect`, `disconnect`, `help`; private cited mention/DM answers; task/proposal/lead-change buttons; verified notification destinations; proposal and blocker notices. Slash results are ephemeral. Explicit DM questions never become company Episodes or extraction jobs.
- Account linking requires a single-use ten-minute gateway challenge confirmed by the signed-in member in the web app. Display names/inferred identities never grant command or notification access. Generic person edits cannot forge or transfer verified handles. Unlinking, member removal and server disconnect revoke access. Authentication and content reads use scoped Ash policies; mutations use Work/event-log rules.
- Checks: **191 tests passed, 1 load test excluded**; compile warnings-as-errors, format, web TypeScript, ESLint and production web build passed. One non-blocking existing font-fallback warning in the web build. Twenty-two Discord tests cover provider structs, permission failures, stale buttons, account proof/revocation, notifications and private replies.
- Current working-tree API deployed successfully (`deployment-01M57J87EQWMGFHTHQF356T706`), including Gmail code/fix and Discord completion. Production health HTTP 200 with db/graph true. Global and nyi-tech command lists verified as `["noa"]`; `/tulpa` removed from both scopes. HTTP interactions endpoint is unset (correct for gateway delivery). Recent logs show READY and no command-registration/response errors.
- `https://app.heynoa.xyz/login` and `/settings` now respond HTTP 200. **The newest local account-link UI still needs web deployment.** No local Vercel CLI auth, process token or project link is available. Saish must deploy this working tree via authenticated Vercel CLI or commit/push himself; the agent must not push.
- Authenticated production check: Discord bot runs but company server is still **unconnected**, with six seed channel mappings. Do not auto-connect/read channels without consent. Org admin connects nyi-tech (`1502935253809893386`), verifies mappings, then each member uses `/noa link` after the new web UI is deployed. Real account-link/button clicks have not yet been live-tested.
- Docs: `docs/discord.md` has setup, commands, security and live-test checklist. TASKS.md/PLAN.md are updated; external plan tracker sync still needs authentication.

## Earlier: integration readiness check (superseded above)

SMTP changes were undone at Saish's request; email item 1.25 remains Soha's. The original WhatsApp-window edits are preserved on `saish/4.2-deploy-ready`. No commits or pushes performed. The current API working tree (including WhatsApp-window support) was deployed to Fly at Saish's request using `fly deploy --ha=false --depot=false`; migrations succeeded and health is good.

Production health is good; `/github/setup` now returns HTTP 302 on both the Fly and custom API domains. `app.heynoa.xyz` still needs web hosting/DNS. Local API (:4000, healthy) and web (:3000, login HTTP 200) are running.

Authenticated status API checks confirm:
- Production: Discord bot is running, but NotYourIdea has no connected server; six channel mappings exist. GitHub App configuration is now active and the authenticated connector API generates an install link; company installation is still pending. OpenAI and email are off.
- Local: Discord bot is off and no server is connected. GitHub App config is off, no installation/secret/token exists. Veriq, Emmarie and Tulpa have repository mappings. OpenAI and email are off.
- GitHub/Discord Settings → API → event log → graph/pack wiring exists, with automated tests for install callbacks, signed webhooks, history, tenant isolation, Discord ingest/edit/delete and privacy gates. Checks after undo: 159 API tests passed, 1 excluded; compile warnings-as-errors, format check, web TypeScript and ESLint passed.

The UI can be tested at `http://localhost:3000`. Live integration testing still requires hosted web/DNS for the production install callback, an org admin connecting nyi-tech and verifying channel mappings, and installing the GitHub App on the intended repos. All four GitHub App secrets are now Deployed, not Staged. No connections, installs, backfills or production data changes were made during this read-only check.

## Earlier: Soha's Gmail integration

- Branch `saish/4.2-deploy-ready` was fast-forwarded to `c33af97` (Soha's merged PR #5 and tracker follow-up). Original local edits were restored; the TASKS.md conflict was resolved preserving both 1.28 deployment notes and 1.29. No new commits or pushes.
- Added five tests for the Gmail poller and fixed oversized-message handling: checkpoint the skipped UID, close the unread socket, resume the next UID on the next poll. `sync/1` accepts an IMAP module in config for offline tests; production defaults to the existing TLS client.
- Validation: 169 tests passed, 1 load test excluded; compile warnings-as-errors, format check, web TypeScript and ESLint passed.
- No Gmail settings in `.env`; `api/.env` does not exist locally. No live Gmail connection or receipt was tested. The integrated Gmail code/fix was subsequently deployed with Discord completion; live Gmail settings/receipt still need verification. Outbound SMTP remains Soha's separate item 1.25.
- Production recheck found Postgres refusing connections. Existing DB machine `d8925e6f7d9de8` and then API machine `6835e1ea567078` were restarted, without deleting/replacing data or volumes. All DB checks and API health recovered (`ok`, `db`, `graph` true). Root cause is unconfirmed; watch for recurrence.
- Discord replies/interaction handlers were missing at this checkpoint; they were subsequently implemented and deployed (see Latest above).
- Ordered release gaps are now summarized in TASKS.md → Release readiness and PLAN.md. External plan tracker remains unsynced without authenticated access.

## 1. Code state

- Current branch `saish/2.6-discord-interactions`, last commit `c33af97` (Soha's Gmail tracker completion), includes merged PRs #4 and #5. Discord completion, the Gmail poller fix/tests, WhatsApp-window helper and tracker/docs changes are uncommitted.
- **Uncommitted WhatsApp helper** (preserved alongside the new Discord work):
  - `api/lib/noa/whatsapp.ex`: `window_open?/1` (did this phone write to Noa in the last 24 h) and `display_number/0` (`KAPSO_DISPLAY_NUMBER`).
  - `api/lib/noa_web/controllers/work_controller.ex`: `GET /orgs/:id/me/notifications` also returns `whatsapp: {number, window_open, sending}`.
  - `api/config/runtime.exs` (`display_number`), `api/fly.toml` (`KAPSO_DISPLAY_NUMBER = "+1 205-341-2931"`), `api/test/noa/whatsapp_test.exs`.
  - `web/src/lib/api.ts` (`getWhatsAppWindow`), `web/src/app/(app)/settings/page.tsx` (Notifications shows "Message Noa on WhatsApp" with an open/closed dot).
- Checks: `cd api && mix test` (191 passed, 1 excluded), `mix compile --warnings-as-errors`, `mix format --check-formatted`; `cd web && npx tsc --noEmit && npx eslint src` (same for `landing`). **Never run `prettier --write`** on web/landing (no config; it reflows whole files).

## 2. What the product does now (all built and tested)

Company brain on FalkorDB: chat → proposals (needs `OPENAI_API_KEY`), Inbox, boards, My day, decisions, change records and lead approval, `@noa` from the graph with sources and routes, shifts and KT briefs, experts/PageRank/bridges/bus factor, Graph tab, agent packs (`CLAUDE.md`/`AGENTS.md`) and the MCP server.

Added in the last sessions:

| Area | What | Code |
| --- | --- | --- |
| Deploy | Dockerfiles (api, web, landing), Fly configs, one-server compose + Caddy, release tasks (`Noa.Release.superadmin/seed/graph/github`) | `api/Dockerfile`, `api/fly.toml`, `deploy/`, `docs/deploy.md` |
| Triage agent (Track 01) | Finds unowned/orphaned/overloaded work, ranks owners from the graph with the route, files Inbox proposals; "Who should own this?" on tasks; MCP `suggest_owner`, `assign_task`, `triage`, `risks` | `api/lib/noa/agent/triage.ex` |
| Shared memory (Track 02) | Concurrency test; fixed stale `.saved` snapshots (re-read committed row) | `api/lib/noa/events/record.ex`, `docs/memory.md` |
| Onboarding | Real `/onboarding`: projects (with GitHub repo), people x projects %, channels (Discord list), org-map import | `api/lib/noa/work/setup.ex`, `web/src/app/onboarding/page.tsx` |
| Join link | `/join/<slug>`: work-email request, org admin approves in Settings → People, invite email follows | `api/lib/noa/orgs/join.ex` |
| Assignments | Assigning a task puts the owner on the project (10% contributor); new allocations tell them their agent pack changed; "Your agent pack" card on My day | `Work.ensure_on_project/1`, notifier |
| Notifications | WhatsApp (buttons), Discord DM, or email per person; daily digest (Oban cron); bell items | `api/lib/noa/notify.ex`, `work/digest.ex` |
| Discord | Per-company: org admin connects their server in Settings → Connectors; edits/deletes followed; channel history backfilled when mapped | `api/lib/noa/ingest/discord.ex`, `api/lib/noa/connectors.ex` |
| GitHub | Noa's GitHub App (one-click install per company) or a hand-added webhook; commits/PRs/CI into the graph and packs; merged PR proposes closing its task | `api/lib/noa/github.ex`, `github/app.ex`, `docs/github.md` |
| Secrets at rest | Company GitHub secrets/tokens encrypted (`Noa.Vault`, keys from `SECRET_KEY_BASE`) | `api/lib/noa/vault.ex` |
| Admin console | `/admin` System panel: services, event-log readers, jobs | `api/lib/noa/ops.ex` |
| Other | Live refresh every 10 s, error/404/offline states, privacy and terms pages, CI for web builds and images | |

Roles: **superadmin = Noa admin** (platform: Fly, bot, Kapso number); **org admin = company admin** (their Discord server, GitHub, people, channels). Prathamesh = org admin ("Head of AI, PM / lead"), Vedant = org admin, Saish = PM / lead, Soha = member.

## 3. Production

| Part | Where | State |
| --- | --- | --- |
| API | Fly `heynoa-api`, region `sin` (Fly has no Mumbai), personal org, 1 machine | Live at `https://heynoa-api.fly.dev`; Current working-tree build deployed, including GitHub App code and WhatsApp-window support |
| Postgres | Fly `heynoa-db` | Live |
| Graph | Fly `heynoa-graph` (FalkorDB, private, 3 GB volume) | Live |
| Web app | Vercel, `app.heynoa.xyz` | Live HTTP 200; latest local Discord account-link UI needs deployment |
| Landing | Vercel, `heynoa.xyz` | Existing project; set `NEXT_PUBLIC_APP_URL=https://app.heynoa.xyz` |
| DNS | Cloudflare (`heynoa.xyz`) | `api.heynoa.xyz` A/AAAA done, Fly cert **Issued**; `app.heynoa.xyz` now resolves and serves the web app |

Workspace "NotYourIdea" (slug `notyouridea`) exists in production with the org map and graph. Invite links for Prathamesh, Vedant, Saish and Soha are in `deploy/.fly-invites`; the web domain is now live; validate invite acceptance there.

**Fly secrets set:** `DATABASE_URL`, `FALKORDB_URL`, `SECRET_KEY_BASE`, `TOKEN_SIGNING_SECRET`, `KAPSO_API_KEY`, `KAPSO_PHONE_NUMBER_ID`, `KAPSO_WEBHOOK_SECRET`, `DISCORD_BOT_TOKEN`, `DISCORD_CLIENT_ID`. **Also deployed:** `GITHUB_APP_ID`, `GITHUB_APP_SLUG`, `GITHUB_APP_PRIVATE_KEY`, `GITHUB_APP_WEBHOOK_SECRET`. **Not set:** `OPENAI_API_KEY`, email (see SMTP below).

Deploy from main: `cd ~/code/Noa && git checkout main && git pull && cd api && fly deploy --ha=false --depot=false`. Use `--depot=false` (the default depot builder timed out once). Migrations run on deploy.

Integrations:
- **Discord:** app/bot "Noa" (application id `1533733435187658884`, same app as Tulpa's; token came from `~/code/nyi/tulpa/.env`). Bot is live in production (logs show READY). It's in servers: **nyi-tech `1502935253809893386`**, Saish_k's server, breaking bad. Noa ignores servers no workspace has connected. Next: an org admin connects nyi-tech in Settings → Connectors and maps channels.
- **GitHub App:** `noa-nyi` (App ID `5367408`, owner SaishKorgaonkar), permissions contents/pull requests/actions read, events push/pull_request/workflow_run, Setup URL `https://api.heynoa.xyz/github/setup`, webhook `https://api.heynoa.xyz/webhooks/github`. Verified with GitHub (JWT works). API support is deployed; install from Settings → Connectors once the hosted web app is ready. Installer must have permission to install apps on the Not-Your-Idea org.
- **WhatsApp (Kapso):** number **+1 205-341-2931** ("Noa"), connected, verified. Templates `noa_update`, `noa_task`, `noa_approval` are **PENDING** with Meta (filed as Marketing, `en_US`). Until approved, Noa can only message people who wrote to the number in the last 24 h. Point Kapso's webhook at `https://api.heynoa.xyz/webhooks/kapso` for production.

## 4. Credentials (all gitignored; never print)

| File | Holds |
| --- | --- |
| `.env` | Local env incl. Kapso keys |
| `api/.superadmin`, `api/.dev-accounts` | Local superadmin; local dev logins (Vedant, Saish, Soha, Prathamesh) |
| `deploy/.fly-superadmin` | Production superadmin (itsupport@notyouridea.com) |
| `deploy/.fly-postgres`, `deploy/.fly-graph` | Fly Postgres creation output; FalkorDB password |
| `deploy/.fly-invites` | Production invite links |
| `deploy/.fly-github-app-secret`, `deploy/.fly-github-app.pem` | GitHub App webhook secret and private key |

## 5. Local dev

Postgres and FalkorDB via `docker compose`; API on :4000 (started with `.env` loaded, `KAPSO_API_KEY` unset so WhatsApp stays simulated, `KAPSO_DISPLAY_NUMBER` set); web on :3000; landing on :3001. Vedant's local fake WhatsApp number was cleared (he is on in-app). Saish's local profile is WhatsApp with his number (ending 32); Soha's has none yet.

## 6. Next steps, in order

1. **Commit** the uncommitted WhatsApp-window change (section 1), then **deploy the API** from main (applies GitHub App secrets and code).
2. **Vercel web app:** Root Directory `web`, `NEXT_PUBLIC_API_URL=https://api.heynoa.xyz`, domain `app.heynoa.xyz`; add the CNAME in Cloudflare (DNS only). Redeploy landing with `NEXT_PUBLIC_APP_URL`.
3. **Send invites** from `deploy/.fly-invites` (no email provider yet).
4. **Email via Gmail SMTP (Soha is setting this up with a Google app password, from the support address).** Code needed: add `{:gen_smtp, "~> 1.2"}` to `api/mix.exs`, and in `api/config/runtime.exs` (prod) choose `Swoosh.Adapters.SMTP` when `SMTP_HOST` is set, before the Resend branch:
   ```elixir
   config :noa, Noa.Mailer,
     adapter: Swoosh.Adapters.SMTP,
     relay: System.get_env("SMTP_HOST"),          # smtp.gmail.com
     port: String.to_integer(System.get_env("SMTP_PORT", "587")),
     username: System.get_env("SMTP_USERNAME"),   # the support address
     password: System.get_env("SMTP_PASSWORD"),   # the Google app password
     tls: :always, auth: :always, ssl: false, retries: 1
   ```
   Set `MAIL_FROM_EMAIL` to the same Gmail address (Gmail rewrites other From addresses), then `fly secrets set SMTP_HOST=smtp.gmail.com SMTP_PORT=587 SMTP_USERNAME=... SMTP_PASSWORD=... MAIL_FROM_EMAIL=...`. Update `Noa.Ops` (`email` service true for SMTP), Settings → Connectors email card, `docs/deploy.md`, `.env.example`. Gmail's limit is about 500 messages a day, fine for the demo.
5. **WhatsApp demo test:** get Soha's number; set her to WhatsApp (org admin can via API/Settings); both send "hi" to +1 205-341-2931; trigger: assign Soha a task (Start/Done/Need help), Soha changes a due date (Approve/Reject to the lead), move Soha (pack link). For button taps, Kapso's webhook must reach the API (production URL, or ngrok locally).
6. **Connect integrations in production:** nyi-tech server and channel mapping; install the GitHub App on Not-Your-Idea (veriq, emmarie, tulpa) and "Load recent history".
7. **`OPENAI_API_KEY`** on Fly so chat becomes proposals; check extraction on 30-40 real messages.
8. **Ship:** feature freeze, 3-minute video (`docs/demo.md`, scene 8 is triage), blog (`docs/blog.md`), submit on WeMakeDevs (all tracks). Tracker: `TASKS.md` and the plan doc (https://claude.ai/code/artifact/3fe68f0f-3173-44c6-96f6-97c7457eb0a4, build tracker node `5fc60be1-51b1`).

## 7. Gotchas learned

- Nostrum is `runtime: false` and included in the release with `releases: [noa: [applications: [nostrum: :load]]]`; without that line the API crashes on boot when `DISCORD_BOT_TOKEN` is set.
- `Noa.Release.migrate/0` ignores a slow pool shutdown after migrations (it once failed a deploy).
- `bin/noa eval` boots a second app (port clash); use `bin/noa rpc` for release tasks.
- FalkorDB on Fly needs `--bind 0.0.0.0 ::` (IPv6 private network) and `FALKORDB_IPV6=true`.
- The web app and API must share a parent domain for the session cookie (`app.` and `api.heynoa.xyz`).
- WhatsApp template parameters can't contain newlines; `Kapso.template_text/1` flattens them.
- Meta tends to reject a template body that is only `{{1}}`; ours have text around it.
