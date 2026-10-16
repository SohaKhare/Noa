# Accounts, workspaces and invites

Items 1.4 (auth), 1.5 (orgs and invites), 1.6 (roles and policies), 1.22 (reporting lines) and the auth pages of 1.7. Code: `api/lib/noa/accounts*`, `api/lib/noa/orgs*`, `api/lib/noa_web`, and in the web app `src/app/{login,invite,reset-password,admin}`, `src/lib/{api,session}.ts*`, `src/components/PeopleSettings.tsx`.

## The flow

1. **Superadmin.** The one account that is not invited: `mix noa.superadmin you@company.com --name "You"` (password written to `api/.superadmin`, gitignored).
2. **Workspace.** The superadmin signs in, lands on `/admin`, and creates the workspace with its work-email domains and its first admin. For NYI: NotYourIdea, `notyouridea.com`, Vedant as admin (PM / lead for the hackathon). The admin gets an invite email; the console also shows the link.
3. **Admin joins.** Vedant opens `/invite/<token>`, sets his name and password, and lands in the workspace as `org_admin`: the lead's view, with Portfolio, Agent pack and people management.
4. **Members.** The admin invites people from Settings → People and roles. Only emails on the workspace's domains are accepted, checked when inviting and again when accepting. A member sets a password on the invite page and lands on My day.
5. **Signing in later.** `/login`: password, or "Email me a link instead" (one-time magic link), or "Forgot password?". There is no sign-up page.

## Roles

| Role | Who | Can |
| --- | --- | --- |
| Superadmin | NYI platform owner (a flag on the user) | Create workspaces, invite their first admin, see every workspace |
| `org_admin` | The workspace lead (Vedant for NYI during the hackathon) | Everything in the workspace: invite, change roles, titles, reporting lines, revoke invites |
| `pm` | Project leads | The lead's views (Portfolio, Agent pack); people management stays with admins |
| `member` | Everyone else | My day, Inbox, projects; can see who is in the workspace |
| `guest` | Outside collaborators | Reserved; scoped by project later |

## Security rules

- **Invite-only.** Password and magic-link registration are disabled. Accounts are only created by accepting an invite (or by the superadmin task).
- **Work emails only.** Each workspace stores `allowed_domains`. An invite to another domain is refused (`not_work_email`); the workspace is not created if its first admin's email is off-domain.
- **Invite links.** 32 random bytes, stored only as a SHA-256 hash, one use, 7-day expiry. Re-inviting the same email revokes the older link.
- **Passwords.** At least 10 characters, hashed with PBKDF2. Magic-link and reset requests answer the same whether or not the email has an account.
- **Sessions.** An httpOnly, `SameSite=Lax` cookie set by the API. The web app sends it with `credentials: "include"`; CORS allows only `WEB_ORIGIN`. Signed-in writes must be `application/json`, so another site cannot forge them.
- **Ash policies on every read and write.** A person sees only workspaces they belong to; only org admins (or the superadmin) manage people and invites. One workspace's admin gets a 404 for another workspace's people. The route plugs are a second gate, not the only one.

## Local development

```sh
docker compose up -d postgres          # repo root
cd api && mix setup                    # deps, database, migrations
mix noa.superadmin you@notyouridea.com --name "You"
mix phx.server                         # API on :4000; sent emails at http://localhost:4000/dev/mailbox
pnpm dev:web                           # web on :3000 (NEXT_PUBLIC_API_URL defaults to http://localhost:4000)
```

Tests: `cd api && mix test` (needs the Postgres container). `test/noa_web/onboarding_flow_test.exs` walks the whole flow above.

## Not done yet

- Google sign-in (needs the Google OAuth app from 0.10).
- Real email delivery in production (SMTP or a provider in `config/runtime.exs`); dev and test keep mail in memory.
- One workspace per person in the web app (the first membership); a workspace switcher comes when someone belongs to two.
- Leaving or removing the last admin of a workspace is not blocked yet.
