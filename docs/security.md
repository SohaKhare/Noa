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
| Chat | Only mapped, read channels are recorded; DMs have no channel row and never reach the log. A message delivered twice is stored once. |

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

- **Webhooks (Kapso, Discord).** Verify the provider's signature on every webhook before reading the body, and reject replays older than 5 minutes. Owner: Soha with 1.13 and 1.15.
- **Rate limits are per machine.** Fine on one Fly machine; a second machine needs a shared store.
- **Error reporting.** Sentry and Logfire are not wired yet (1.3).
- **Secrets as one-time links (3.21)** and MCP tokens (3.22) are proposed cuts; agent packs must never contain secrets.
