# Google Meet notetaker: provider spike (0.7)

## Agreed product behavior

- A **visible meeting bot** joins Google Meet as `Noa Notetaker` using Attendee's hosted API. No hidden recording; an authorized organizer explicitly starts and stops it. No automatic calendar joins.
- The organizer explicitly starts the bot for each meeting and is responsible for confirming participant notice/consent before starting it.
- Attendee can supply timestamped, speaker-labelled captions and transcript updates; Noa must verify completion and fetch the final transcript. This is not the native Meet transcript API. The developer reports a test meeting transcribed decently, but webhook delivery and account retention have not been verified with Noa.
- Noa stores the meeting/transcript as cited source material in the configured workspace. Workspace members can read it. Attendee also processes/retains meeting data; review its sharing defaults and retention/deletion policy before any real confidential meeting.
- Noa suggests a project and waits for an authorized approver to confirm or change the project. No task/decision extraction should be committed to a project until that route is confirmed.
- After route approval, feed timestamped transcript lines to the existing typed extraction pipeline. Extracted decisions/tasks are proposals; normal Inbox approval rules still apply. Cite transcript time ranges/speakers for each item.

## More provider options (desk research; not yet live-tested)

| Option | Google Meet and integration | Free-first cost / caveat |
| --- | --- | --- |
| **Fireflies.ai** | Visible Fred bot; `addToLiveMeeting` GraphQL, speaker/timestamped transcript query, signed Webhooks V2 | Free plan lists 400 minutes storage and API access (30/min, 500/day). New free accounts get **3 manual** transcriptions with Auto-join OFF; unlimited requires Auto-join, which conflicts with explicit per-meeting consent. Renaming Fred is a paid add-on. |
| **Meeting BaaS** | Hosted API v2 sends a bot to Google Meet; webhook can return transcript and participant timeline | Pricing page currently advertises **8 recording hours free**, then from **$0.35 per recording hour**. Transcription adds **0.25 tokens/hour** in its token model; check exact billing and whether 8 free hours cover transcription before testing. Pay-as-you-go tier lists 3-day retention. |
| **Recall.ai** | Hosted bot API supports Google Meet; transcript support must be confirmed in the chosen API mode | Pricing advertises **first 5 recording hours free**, then **$0.50 per recording hour**; built-in transcription is listed separately at **$0.15/hour**. Trial credit is not a perpetual free tier. |
| **Attendee (hosted first; self-host later)** | Hosted REST API supports Google Meet, custom `bot_name`, timestamped transcript endpoint (including partial results), and signed webhooks | Attendee's pricing advertises **5 hours free, then $0.50/hour**, including realtime/post-meeting transcription as a feature. For the no-extra-STT-cost pilot, choose **Google Meet closed-caption transcription**, which its transcription guide describes as free but lower quality; third-party transcription requires a separate provider key and incurs its costs. Self-hosting has infrastructure costs and **Elastic License 2.0** hosted-service/license-key restrictions; review before reusing the source in Noa. |

Google's Meet Media API documentation currently says it is **not accepting new developer-preview signups**; do not rely on official real-time media access as a fallback.

**Recommendation:** use Attendee's **hosted five-hour trial** for a consented Meet pilot, with explicit per-meeting start, closed-caption transcription, and `Noa Notetaker` as the bot name. Do not confuse the hosted API trial with self-hosting (which has separate licensing and operations). Test webhooks, caption availability and transcript quality before connecting the extraction pipeline. Do not promise a perpetually free managed service. Prices/quotas are published claims, not verified for a Noa account, and may change.

## Spike objective — do not integrate a provider before passing these checks

A developer reports that an Attendee bot completed a test Meet and produced a decent transcript. A read-only `GET /api/v1/bots?limit=1` using the locally configured key returned HTTP 200 (no meeting data printed). This is **not** evidence that Noa's signed webhook, data retention, or end-to-end ingestion work. The key is currently in the root `.env`, not `api/.env`; the Phoenix runtime reads process environment, so it must be exported before launch or placed in the ignored `api/.env` and loaded by the launch script. The current 0.7 spike has a server-only provider boundary (`Noa.Meet.Provider` and `Noa.Meet.Attendee`), with mocked join/leave/transcript tests. It does not expose a start endpoint, schedule calls, persist a meeting, or ingest data. The organizer must explicitly authorize/consent to each call before the future 2.8 endpoint is enabled. Verify the remaining gates with an Attendee trial account before rollout.

Record evidence for each gate:

1. **Join reliability:** public/internal Meet link, guest access, waiting-room/admission, organizer controls, visible exact bot name, time to join, reconnect behavior, and how to stop/remove the bot.
2. **Transcript quality:** timestamps, speaker separation/labels, language coverage, corrections, finalization latency (measure from call end), supported transcript formats. Confirm transcript webhooks and a way to fetch the final transcript if webhook delivery is missed.
3. **Security:** signed webhook verification (Attendee documents base64 HMAC-SHA256 over recursively sorted JSON using a base64-decoded secret), event IDs/idempotency, retries, replay protection, secret rotation, tenant isolation, TLS, data-processing agreement, model/subprocessor disclosure, retention/deletion controls, storage region, and incident process.
4. **Consent and UX:** a clear organizer action and visible participant; show a consent reminder before dispatch; never auto-join calendar events in the spike. Determine whether recording is enabled by default and whether audio/video can be disabled while still receiving transcript.
5. **Cost and limits:** trial restrictions, per-minute charges, concurrency/quotas, minimum billing, cancellation fees, and expected cost at NYI meeting volume. Do not send real confidential calls before terms are approved.
6. **Integration fit:** webhook includes a stable meeting ID, transcript segments, timestamps, and speaker labels; can map it to a workspace and store event-log entries idempotently; no provider API credential is exposed to the browser.

**Go/no-go:** recommend a provider only after an actual test call completes, a transcript arrives, its webhook can be verified, and the account owner accepts the privacy terms and costs. Otherwise keep the feature at design stage. Provider credentials and consent for the test must be supplied by the developer; never commit secrets.

## Proposed implementation after spike (2.8 follow-up)

```text
Org admin configures provider credentials (server-side secret, never browser-side)
  → Noa stores a provider-neutral meeting session (org, organizer, consent, meeting URL, state)
  → provider adapter joins/leaves and normalizes timestamped utterances
  → authorized organizer starts Noa Notetaker for a Meet
  → signed provider webhook marks meeting complete / transcript ready (verify Attendee's documented HMAC-SHA256 over canonical sorted-key JSON, not raw-body HMAC)
  → verify signature, tenant, stable meeting id, and duplicate delivery
  → fetch final transcript and append stable-key utterance events in Postgres (source of truth)
  → show transcript with project suggestion: awaiting approval
  → authorized lead confirms or edits project route
  → Oban invokes existing typed extraction on timestamped speaker lines
  → cited proposals enter existing Inbox approval flow
  → approved decisions/tasks show on project page/board
```

Project routing approval and proposal approval are separate: confirming which project owns a meeting does **not** approve any extracted decision/task. Guests should not be able to approve routes or read the transcript. Do not add a provider-specific write path to FalkorDB; the projector remains the sole writer.

Before 2.8 implementation, the team must agree how meeting/transcript events fit the frozen Episode/Meeting schema and channel mapping. This spike makes no graph or extraction-schema changes. Use an idempotent provider event ID / utterance ID (or deterministic timestamp + index if missing); never append partial captions as final repeatedly. Keep provider-specific API payloads out of the Postgres/Ash and graph contracts. Store the provider's raw transcript only if retention is approved; otherwise retain normalized utterance text and provider IDs needed for deletion/audit. If the organizer deletes a meeting/transcript, define how derived proposals/source citations are deleted or redacted before rollout.

## References

- Fireflies pricing: https://fireflies.ai/pricing
- Fireflies Free transcription limits and Auto-join requirement: https://guide.fireflies.ai/hc/en-us/articles/21617190473617-How-to-get-unlimited-meeting-transcripts-on-Fireflies-ai-s-Free-plan
- Fireflies `addToLiveMeeting`: https://docs.fireflies.ai/graphql-api/mutation/add-to-live.md
- Fireflies transcript query: https://docs.fireflies.ai/graphql-api/query/transcript.md
- Fireflies V2 webhooks: https://docs.fireflies.ai/graphql-api/webhooks-v2.md
- Recall.ai bot quickstart: https://docs.recall.ai/docs/quickstart
- Meeting BaaS docs: https://docs.meetingbaas.com/
- Meeting BaaS pricing: https://www.meetingbaas.com/pricing
- Recall.ai pricing: https://www.recall.ai/pricing
- Attendee source and self-hosting docs: https://github.com/attendee-labs/attendee
- Attendee ELv2 license: https://github.com/attendee-labs/attendee/blob/main/LICENSE
- Attendee hosted pricing: https://attendee.dev/pricing
- Attendee transcription modes: https://docs.attendee.dev/guides/transcription
- Attendee webhooks: https://docs.attendee.dev/guides/webhooks
- Attendee bot creation API: https://docs.attendee.dev/api-reference/tag/bots/post/api/v1/bots
- Google Meet Media API availability: https://developers.google.com/workspace/meet/media-api/guides/overview
- Noa extraction contract: [extraction.md](extraction.md)
- Noa event/graph and work schema: [schema.md](schema.md)
