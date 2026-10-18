# Gmail INBOX ingestion (1.29)

This is **inbound email**, not SMTP/outbound sending. The NYI workspace approved processing all new email in `itsupport@notyouridea.com` and allowing all workspace members to see ingested source text. Chat DMs are still excluded.

## Setup

1. Enable IMAP in the Google Workspace mailbox if required by its settings / admin. Create a Google **app password** for Noa (not the account password). Workspace policy can disable app passwords. Never put the password in git, chat, logs or a tracked file.
2. Create the intended workspace in Noa and obtain its UUID. For production, set these as Fly secrets. For Windows local development, copy `api/.env.example` to `api/.env`, fill in your workspace UUID and app password, then launch with `./api/scripts/start-gmail.ps1` from the repo root. `api/.env` is gitignored; do not commit or share it. The helper loads the file into that process and starts Phoenix. Alternatively, set the variables in the API shell before starting it.

   ```text
   GMAIL_IMAP_ENABLED=true
   GMAIL_ORG_ID=<existing Noa workspace UUID>
   GMAIL_IMAP_USERNAME=itsupport@notyouridea.com
   GMAIL_IMAP_PASSWORD=<Google app password, with display spaces removed>
   ```

   You can paste the app password directly into the ignored local `api/.env` file; it is never printed by the helper. Noa connects to `imap.gmail.com:993` using verified TLS.
3. Start the API. The first successful `EXAMINE INBOX` saves `UIDNEXT - 1`: **all preexisting inbox messages are ignored**. Send a *new* plain-text test email mentioning a project, and allow ~60 seconds for poll plus ~20 seconds for extraction. The `email` / `INBOX` channel is created for the workspace as a split channel; routing chooses a project from email text/model or leaves a proposal to be routed manually. Configure `OPENAI_API_KEY` to enable extraction; without it the email is retained but no proposals are created yet.

The connector uses `EXAMINE` and `BODY.PEEK[]`, so mail remains unread and unchanged. It imports subject, sender and decoded `text/plain` content (including MIME multipart text/plain parts); attachments and HTML are not included. Unsupported mail is logged as skipped. Messages > 1 MB are explicitly logged as skipped (they are not ingested), so attachments cannot stall the inbox. Only the approved workspace is ingested. It checkpoints UID per UIDVALIDITY in `projections`; event keys deduplicate after retries/restarts. A new UIDVALIDITY starts at the then-current UIDNEXT (no accidental historical backfill). Up to 100 messages are processed per poll. No credentials are stored in Postgres or FalkorDB.

**Access:** imported email is an Episode in the event log and graph; its text and citations can be returned to any member of the configured workspace through existing work and `@noa` reads. Do not enable this connector for a mailbox that receives confidential third-party mail unless that exposure is acceptable.
