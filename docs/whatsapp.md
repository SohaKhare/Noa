# WhatsApp through Kapso (0.6, 0.11, 1.15, 2.7)

Noa messages people on WhatsApp when work changes around them, and acts on their replies. Direct messages are commands, never extracted as work. Sending uses [Kapso](https://kapso.ai) in front of Meta's WhatsApp Cloud API. Without `KAPSO_API_KEY` and `KAPSO_PHONE_NUMBER_ID`, nothing leaves the machine: the same messages are stored as `simulated` and shown in Settings → Connectors.

## What gets sent

`Noa.WhatsApp.Notifier` tails the event log from its current end, so a restart does not resend old news. A person gets a message only if they chose WhatsApp and gave a number in Settings → Notifications. Quiet hours hold everything except an approval waiting on a lead. Nobody is told about their own changes.

| When | To | Example | Buttons |
| --- | --- | --- | --- |
| A task gets an owner | The owner | Vedant put you on "Board report PDF export" in Veriq, due 2026-10-24. | Start now · Done · Need help |
| A member's deadline or scope change waits | The project lead (or admins and PMs) | Saish wants to change the deadline of "Report share links": 2026-10-18 → 2026-10-20 (client moved review). | Approve · Reject |
| That change is decided | Whoever asked | Vedant approved your deadline change to "Report share links" (2026-10-20). | |
| Someone moves projects | Them | You're moving from Video Break to Emmarie from 2026-10-19. Your brief and agent pack: …/pack. | |

## Replies

Noa finds the person by their number and acts as them, with their permissions.

- A button id says what to do: `start:`/`done:<task id>` move the card, `help:<task id>` tells the project lead, `approve_change:`/`reject_change:<change id>` decide a change (leads only).
- A bare "done" or "on it" moves the task from the last message Noa sent that person; "done Board report PDF export" finds it among their tasks.
- Anything else is a question for `@noa`, answered from the graph with sources, using only what that person can see.
- An unknown number gets a note to add it under Settings → Notifications.

## Set up Kapso

1. **Account and number.** Create a Kapso project and connect a WhatsApp number (Kapso's sandbox number works for testing). Note the phone number ID and create a project API key.
2. **Webhook.** Point it at `POST https://<your-noa-api>/webhooks/kapso`, subscribe to `whatsapp.message.received`, and set a long random secret. Noa checks `X-Webhook-Signature` (HMAC-SHA256 of the raw body, hex), ignores a message id it has already seen, queues the rest, and answers 200 at once (Kapso wants a reply within 10 seconds). Batched deliveries are unpacked.
3. **Templates.** Free-form messages only reach someone who wrote in the last 24 hours. After that Noa sends the same text through an approved template, and templates have fixed buttons, so there is one per button set. Submit them early: Meta approval takes hours. The sandbox cannot send templates; it covers text and buttons after you message the sandbox number. Templates need your own connected number. Category Utility, English:

   | Name | Body | Quick-reply buttons |
   | --- | --- | --- |
   | `noa_update` | `{{1}}` | none |
   | `noa_task` | `{{1}}` | Start now, Done, Need help |
   | `noa_approval` | `{{1}}` | Approve, Reject |

4. **Environment:**

   ```
   KAPSO_API_KEY=
   KAPSO_PHONE_NUMBER_ID=
   KAPSO_WEBHOOK_SECRET=
   KAPSO_TEMPLATE_UPDATE=noa_update
   KAPSO_TEMPLATE_TASK=noa_task
   KAPSO_TEMPLATE_APPROVAL=noa_approval
   KAPSO_TEMPLATE_LANG=en
   ```

To try replies locally, set `KAPSO_WEBHOOK_SECRET` and post a signed body to `/webhooks/kapso`.

## How it works

- `Noa.WhatsApp.send/3` sends one message and records it in `whatsapp_messages` (in and out, with what it was about), which is how a bare "done" finds its task.
- `Noa.WhatsApp.Kapso` posts to `https://api.kapso.ai/meta/whatsapp/v24.0/{phone_number_id}/messages` with `X-API-Key`: text, or interactive reply buttons. If Meta refuses because the window closed (error 131047), it resends through the template for that button set, with the text as `{{1}}` and the button ids as quick-reply payloads.
- Button ids carry the action and its target, so a tap needs no lookup and still goes through the person's permissions.
- Settings → Connectors shows whether Kapso is configured and the recent messages. Admins see the workspace; everyone else sees their own.

Tests: `api/test/noa/whatsapp_test.exs` (notifications, webhook, replies) and `api/test/noa/kapso_test.exs` (requests against a stubbed Kapso API).
