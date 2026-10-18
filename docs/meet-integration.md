# Google Meet notetaker (2.8)

This is an additive Google Meet source using Attendee's hosted visible bot. It preserves the shared Discord/meeting implementation in `Noa.Meetings`: that domain continues to own participant consent, utterances, typed Minutes, cited Inbox proposals, and review. The new `Noa.Meet` boundary owns only the provider bot session and final transcript handoff. Calendar auto-join is intentionally out of scope.

## Local setup

1. Set `ATTENDEE_API_KEY` in ignored root `.env` or `api/.env`. On Windows, `api/scripts/start-meet.ps1` loads only this key into Phoenix. Never expose it as `NEXT_PUBLIC_*`. On Fly, use a server secret.
2. Run `cd api && mix ecto.migrate`, then start the API. In another terminal run `cd web && npm run dev`.
3. Sign in as an org admin or PM. In **Settings → Meetings**, paste a `https://meet.google.com/xxx-xxxx-xxx` link, affirm that participants have been informed and consented, and start the visible `Noa Notetaker`. Admit it if Meet prompts. Stop it when finished.
4. After Attendee reports transcription complete, click **Fetch final transcript**. Then inspect the transcript, confirm a project, and select a readable channel mapped to that project. This channel is the source context required by the existing `Noa.Meetings` import pipeline.
5. Confirm import. The transcript is handed to `Noa.Meetings.import_transcript`, which writes consented meeting utterance episodes and queues its existing typed Minutes worker. Resulting task/decision items enter the Inbox as pending proposals; no project selection or extraction auto-approves them. `OPENAI_API_KEY` is required for the existing Minutes model in normal operation.

## Boundaries

- `Noa.Meet.Provider` and `Noa.Meet.Attendee` isolate provider transport. Normalized utterances cross into the established meeting contract; Attendee payloads and credentials do not.
- Google Meet bot sessions are in `google_meet_sessions`; imported meeting data uses the existing `meetings` table and `Noa.Meetings` domain.
- Ash policies govern session and meeting reads. Google Meet sessions and imported transcripts follow the existing workspace meeting policy: org members can read within their org; guests do not gain cross-org access.
- Existing event-log/projector behavior is unchanged. This integration adds no graph labels/edges and no extraction types. Meeting commitments use the existing validated Minutes schema and remain pending proposals.
- Explicit per-call consent is required; there is no hidden recording or Calendar auto-join.

## Remaining before production

- Signed Attendee webhook delivery/replay handling is not implemented. The UI explicitly fetches the final transcript. Do not configure a webhook until verification is implemented. Attendee documents base64 HMAC-SHA256 over canonical recursively sorted JSON (not raw-body HMAC).
- Attendee retention, data-processing terms, and deletion/redaction behavior for derived proposals and citations need workspace-owner review before confidential meetings.
- No Calendar scheduling or live bot speech. The five-hour hosted trial is limited, not a recurring free tier.
- Test transcript timestamps and speaker labels against an actual Meet before relying on citations. No real Noa-triggered bot meeting has yet been verified.

Do not alter the frozen graph schema or typed extraction contract without team approval.
