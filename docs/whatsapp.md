# WhatsApp through Kapso (0.6, 1.15, 2.7)

Noa messages people on WhatsApp and acts on their replies. Direct messages are commands, never extracted as work. Sending uses [Kapso](https://kapso.ai)'s WhatsApp API. Without `KAPSO_API_KEY` and `KAPSO_PHONE_NUMBER_ID`, nothing leaves the machine: the same messages are stored as `simulated`.

## Configure

```
KAPSO_API_KEY=
KAPSO_PHONE_NUMBER_ID=
KAPSO_WEBHOOK_SECRET=
KAPSO_TEMPLATE=          # optional, for outside the 24-hour window
KAPSO_TEMPLATE_LANG=en
```

Point Kapso's webhook at `POST /webhooks/kapso` and subscribe to `whatsapp.message.received`. Noa checks `X-Webhook-Signature` (HMAC-SHA256 of the raw body), ignores a message id it has already seen, queues the rest, and answers 200 immediately.

## What gets sent

`Noa.WhatsApp.Notifier` tails the event log from its current end, so a restart does not resend old news. A person gets a message only if they chose WhatsApp and gave a number. Quiet hours hold everything except an approval waiting on a lead.

- Task assigned: Start / Done / Need help.
- Deadline or scope change waiting on a lead: Approve / Reject.
- That change decided: a note to whoever asked.
- A shift: a link to their brief and agent pack.

## Replies

A button id says what to do (`done:<task id>`, `approve_change:<change id>`). A bare "done" completes the task from the last message Noa sent that person. `@noa …` answers in the chat, using only what that person can see. An unknown number gets a short note to join from their invite.

Settings → Connectors shows whether Kapso is configured and the recent messages. Admins see the workspace; everyone else sees their own.
