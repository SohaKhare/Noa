# Security pass (4.3)

Done on Oct 17. What Noa does to keep each company's work private, what was fixed in this pass, and what is still open. Tests: `api/test/noa_web/permissions_test.exs`, `api/test/noa_web/security_test.exs`.

## Access

| Area | How it is protected |
| --- | --- |
| Accounts | Invite-only. Passwords hashed with PBKDF2. Magic links and reset tokens are single-use and expire. See [auth.md](auth.md). |
| Sessions | `httpOnly`, `SameSite=Lax` cookie, `Secure` in production. Bearer tokens for API clients. |
| Cross-site requests | Every write, including sign-in, must be `application/json`. A form on another site cannot send that without a CORS preflight, and CORS only allows the web app's origin. |
| Workspaces | Every `/api/orgs/:org_id` route answers 404 to anyone outside that workspace (`EnsureInOrg`), then Ash policies check each row: guests read, members write their own work, leads approve, org admins manage people and channels. Ids from another workspace answer 404. |
| Permission tests | Every workspace route is called signed out, by another workspace's admin, by a guest and by a member. A new route fails CI until it is added. |
| `@noa` | Reads only through Ash with the asker as the actor, so answers can't cite what they can't see. The model may only cite the sources it was given (validated, with retries). |
| MCP | Personal tokens, shown once and stored hashed, revocable, dead when the person leaves the workspace. Tools run through the same policies as the web app; the only write is a task status change, recorded and revertible. See [mcp.md](mcp.md). |
| Chat | Only mapped, read channels are recorded; DMs never become company Episodes or extraction jobs. Explicit questions sent directly to Noa are answered privately as a verified member (normal model audit applies). A guild message delivered twice is stored once. |
| Discord commands | Ephemeral responses and private mention answers. One-time, short-lived gateway challenges link Discord ids to signed-in members; display-name inference grants no command or notification access. Every work read and button action uses Ash policies; unlink/removal/server disconnect revokes access. See [discord.md](discord.md). |

## Fixed in this pass

- **Login CSRF.** `/auth` routes took form posts; they now require JSON like the rest of the API.
- **Rate limits.** Sign-in, magic links, password resets and invite links: 10 writes a minute per address. `@noa`: 20 questions a minute per person. Over the limit answers 429 with `retry-after`.
- **Body size.** Requests over 1 MB are refused.
- **Headers.** API responses send `content-security-policy: frame-ancestors 'self'`, `x-content-type-options: nosniff`, a referrer policy and `x-permitted-cross-domain-policies: none`.
- **Cookies.** The session cookie is `Secure` in production.
- **Logs.** Passwords, tokens, secrets and keys are filtered from request logs.
- **Outsiders.** List routes answered an outsider with an empty 200, which confirmed the workspace existed; they now answer 404.

## Data and secrets

- Secrets come from the environment in production (`runtime.exs` fails to boot without them). Dev values in `config/*.exs` are dev-only. Local credentials live in gitignored `api/.superadmin` and `api/.dev-accounts`.
- Graph queries use parameters, never string interpolation of user data. Graph names come from workspace UUIDs.
- Text from chat is data: extraction and `@noa` send it to the model as sources, and the output schema only allows typed items or an answer with citations, so instructions hidden in a message can't make Noa act.

## Still open

- **Discord live verification.** Noa uses the authenticated gateway, not a public Discord HTTP webhook. Leave the application's Interactions Endpoint URL empty; live-test linking, permissions, commands and button clicks with real accounts. Kapso independently checks `X-Webhook-Signature` and ignores duplicate message ids.
- **Rate limits are per machine.** Fine on one Fly machine; a second machine needs a shared store.
- **Error reporting.** Sentry and Logfire are not wired yet (1.3).
- **Secrets as one-time links (3.21)** are still a cut. MCP tokens (3.22) are built and stored hashed; agent packs must never contain a token.
