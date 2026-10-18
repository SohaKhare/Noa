# GitHub (3.7)

Noa reads each project's repository so the company graph knows what is being built, not only what was said. Pushes, pull requests and CI runs become `Commit`, `PullRequest` and `CIRun` nodes on the project, linked to the person who wrote them.

## What it does

| GitHub event | In Noa |
| --- | --- |
| A push | One `commit.pushed` event per commit (first line of the message, branch, author), linked to the person by git handle, name or email from the org map |
| A pull request opened, updated, merged or closed | `pr.saved` with its state; a merged one counts 2 toward `KNOWS_ABOUT`, a commit counts 1 |
| A workflow run finishes | `ci.completed` with its conclusion |
| A pull request is merged | If an open task on the project has the same title, or the branch carries all of the task's words, Noa proposes moving the task to done (an Inbox proposal) |

Every project's agent pack (`CLAUDE.md`, `AGENTS.md`) gets a **Recent changes on GitHub** section: pull requests merged this week, open pull requests, the latest CI result per workflow, and recent commits when there are no pull requests. Coding agents connected over MCP get the same through `project_context`.

## Noa's GitHub App (recommended)

**Once, by the Noa admin:** GitHub → Settings → Developer settings → GitHub Apps → New GitHub App.

| Field | Value |
| --- | --- |
| Name | Noa (or any free name; its URL slug is `GITHUB_APP_SLUG`) |
| Homepage URL | `https://heynoa.xyz` |
| Setup URL | `https://api.heynoa.xyz/github/setup`, with "Redirect on update" ticked |
| Webhook URL | `https://api.heynoa.xyz/webhooks/github` |
| Webhook secret | a long random string, saved as `GITHUB_APP_WEBHOOK_SECRET` |
| Repository permissions | Contents: Read, Pull requests: Read, Actions: Read (Metadata: Read is automatic) |
| Subscribe to events | Push, Pull request, Workflow run |
| Where can it be installed | Any account |

Then generate a private key (a `.pem` file) and set the four values on the API:

```sh
fly secrets set --app heynoa-api GITHUB_APP_ID=<App ID> GITHUB_APP_SLUG=<slug> \
  GITHUB_APP_WEBHOOK_SECRET=<secret> GITHUB_APP_PRIVATE_KEY="$(cat noa.private-key.pem)"
```

**Each company's org admin:** Settings → Connectors → **Install Noa on GitHub**, pick their organization and the repos, and GitHub brings them back to Noa. That's all: webhooks arrive for those repos, and history is read with short-lived installation tokens, so nobody pastes a secret or a personal token. "Change repos" adjusts the selection; uninstalling on GitHub disconnects the workspace.

Deliveries from the app are checked with the app's secret and belong to the workspace that installed it; a repository is matched only within that workspace, so two companies can have repositories of the same name.

## Without the app (by hand)

1. Give each project its repository as `Owner/name` (onboarding, or the org map's `repo`; also needed with the app). NYI's are `Not-Your-Idea/veriq`, `Not-Your-Idea/emmarie` and `Not-Your-Idea/tulpa`.
2. Under **Connect GitHub**, generate a webhook secret. It is shown once and stored encrypted; making a new one stops the old one working.
3. In each repository (or once for the GitHub organization): Settings → Webhooks → Add webhook.
   - Payload URL: `https://api.heynoa.xyz/webhooks/github`
   - Content type: `application/json`
   - Secret: the one from step 2
   - Events: Pushes, Pull requests, Workflow runs
4. Optional, to load history from before the webhook (needed for private repositories): save a fine-grained token with read access to contents and pull requests, then **Load recent history** (the last 50 commits and 30 pull requests of each project).

Each delivery is verified with the secret of the workspace that owns the repository, so one company's secret never opens another's. The platform's `GITHUB_WEBHOOK_SECRET` and `GITHUB_TOKEN`, if set, are only a fallback for a single-company install.

Noa checks `X-Hub-Signature-256` on every delivery and records each commit, pull request state and run once, so GitHub's redeliveries are harmless. Settings → Connectors and the superadmin console show whether GitHub is connected.

Code: `api/lib/noa/github.ex`, `api/lib/noa_web/controllers/github_webhook_controller.ex`. Tests: `api/test/noa/github_test.exs`.
