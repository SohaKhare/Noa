# Meeting notes: Discord voice + shared Google Meet intake (2.22)

## Status and ownership

Saish owns Discord voice and the shared minutes pipeline (2.22). Soha owns the Google Meet joining/notetaker bot (2.8). The bot transport differs; completed transcripts use the same backend. This does not implement Google Meet joining or change the existing graph schema/extraction types. `Noa.Meetings.Minutes` is a new, separately approved embedded schema which reuses the existing task and decision shapes.

Voice capture is **disabled by default** and has not yet been verified with a real Discord call. Automated tests use provider/model stubs; they do not establish transcription accuracy or summarization quality. Do not advertise a successful live recording until the checklist below passes.

## Why a separate voice worker

Discord's [voice documentation](https://docs.discord.com/developers/topics/voice-connections#end-to-end-encryption-dave-protocol) requires DAVE E2EE from March 1, 2026. The pinned Nostrum 0.10 release has no DAVE implementation. Rather than upgrade the working text bot to unreleased Nostrum, the API runs an opt-in Node receiver over a private stdin/stdout pipe:

- Node >=22.12, `discord.js` 14.27.0, `@discordjs/voice` 0.19.2 with `@snazzah/davey`, prism and opusscript; dependencies locked under `api/priv/voice/`.
- No public audio endpoint, extra TCP service, audio files, FFmpeg or direct graph writes.
- The Dockerfile installs worker dependencies and copies Node into the release. Linux dependency/DAVE loading is checked independently of a real call.
- The text gateway deliberately does **not** request Guild Voice States. The receiver requests that intent and handles its own voice connection. A separate `DISCORD_VOICE_BOT_TOKEN` may be used; otherwise it uses the existing bot token. Do not run any other recorder with that same voice identity.

## Enable only for a consented live test

Local: `cd api && mix ecto.migrate`, then `cd priv/voice && npm ci --ignore-scripts`; restart the API with Node on PATH, a valid `OPENAI_API_KEY`, an available `NOA_MODEL`, and `DISCORD_VOICE_ENABLED=true`. Tests explicitly disable the real worker even if that env variable is set.

Production: deploy the current API/Dockerfile and migration first, then explicitly enable the flag in Fly. Do not deploy unrelated teammates' incomplete working-tree changes. `DISCORD_VOICE_BOT_TOKEN` is optional, never printed or committed. The worker uses the same app's privileged Server Members intent; enable it in Discord's portal. Grant the receiver **View Channel + Connect**, and Noa **Send Messages** in the designated text channel. It joins self-muted, not self-deafened. A separate receiver bot must also be invited to the server.

There is one concurrent voice session per API node, up to twelve human participants, a thirty-minute recording cap, five-second speech chunks and at most three in-flight ASR requests. Overload/invalid audio fails closed rather than silently dropping speech. Restarting the API stops capture and marks interrupted Discord sessions failed; consent is never silently resumed. A worker timeout closes its pipe and stops the receiver rather than leaving an unknown recording running.

## Discord flow

1. Org admin connects the server and a consented project-mapped **text channel** in Noa. Every human participant must be a current workspace member with a verified `/noa link` binding. No display-name authentication.
2. Organizer (org admin or PM) joins the intended normal voice channel and runs `/noa meeting start title:Standup` from that text channel. Stage channels are not supported. The receiver takes a participant snapshot but **does not join or capture audio yet**.
3. Noa posts a recording notice and meeting UUID, with no private work details. Each participant runs `/noa meeting consent meeting:<UUID>`. Consent is individual, expires after ten minutes, and cannot be supplied by the organizer on someone else's behalf.
4. Only after everyone agrees does Noa join. It verifies the actual current voice participants again before subscribing to audio. An unconsented newcomer stops capture; already captured notes are marked partial. Consent is not automatically extended to newcomers.
5. Any original participant or lead may `/noa meeting stop meeting:<UUID>` to finish, or `/noa meeting cancel meeting:<UUID>` to withdraw consent/cancel. Cancel generates no minutes/proposals. Already transcribed, previously consented source text remains workspace-protected; cancelling is not a retroactive erasure operation.
6. `/noa meeting notes meeting:<UUID>` returns status and cited minutes privately. Approve/reject resulting task/decision proposals through the existing Inbox or `/noa inbox` buttons.

Participant account/membership and source-channel authorization are checked again before sending each audio chunk to ASR. Unlinking/removal/disconnecting the server/turning off the source channel stops subsequent transcription. Public Discord channels never receive the transcript/minutes; slash replies are ephemeral. The announcement only contains consent instructions and an opaque meeting id.

## Processing and retention

Audio is decoded in memory from Opus to 16kHz mono WAV, with silence filtered. Temporary WAV segments go to OpenAI's audio transcription endpoint (`gpt-4o-mini-transcribe`) and are discarded from application memory after use. No raw audio is written into Postgres, the event log, application logs or files. The external provider still receives the consented audio; do not record without approval for that processing.

ASR JSON is validated as text input, not treated as extracted work. Discord speaker ids come from the voice receiver and are mapped on the server to verified org-map person keys/names, not mutable Discord display names. Speaker/time-labelled utterances are validated, stored as consented source Episodes and cached on the meeting row. **Transcripts can include small talk and are retained as workspace-visible evidence**; it is the minutes that filter out jokes/greetings/repetition. Typed minutes include discussion, blockers, unresolved questions, tasks and decisions. Every item must cite real utterance sequence numbers. Unknown evidence/owners/projects and invalid dates fail validation. Empty/non-work conversations can yield completely empty minutes. No model key means no recording is started, not simulated notes.

Tasks/decisions below 0.8 confidence are omitted. The rest are **pending proposals even at 0.99 confidence**—meeting extraction never uses chat auto-apply. The ordinary chat extractor also explicitly excludes meeting-tagged Episodes, including its earlier-context window, so a later text message cannot accidentally re-extract/auto-apply those commitments. No guessed commitments or unsupported dates should be included; humans still verify the interpretation. Approved work uses existing event-log/projector paths and `EXTRACTED_FROM` links. No new graph node/edge labels were introduced: the Postgres meeting row and `meeting.saved` events track the session; existing Episode/Task/Decision nodes hold evidence and approved work.

Meeting transcripts/minutes are readable by workspace members under the current Ash policies, not by arbitrary Discord participants or outsiders. Transcript/audio request fields are filtered from Phoenix parameter logs. This version has no automatic transcript-retention/erasure policy; arrange any required source deletion before recording sensitive discussions.

## Contract for Soha's Google Meet bot

The bot obtains participant consent and transcribes the call itself. It then submits a completed, consented transcript using existing Noa session/bearer authentication as an org admin or PM. Do not use the platform superadmin for a company bot. Keep any credentials in ignored env files.

`POST /api/orgs/:org_id/meetings`, `Content-Type: application/json`:

```json
{
  "external_id": "google-meet:conference-record-id",
  "title": "Veriq standup",
  "project_id": "NOA-PROJECT-UUID",
  "channel_id": "NOA-CONSENTED-CHANNEL-UUID",
  "consent_confirmed": true,
  "utterances": [
    {"seq": 1, "speaker": "Soha", "text": "I'll prepare the report.", "start_ms": 0, "end_ms": 2400},
    {"seq": 2, "speaker": "Vedant", "text": "Decided: ship the blue version.", "start_ms": 2500, "end_ms": 4800}
  ]
}
```

`channel_id` is the **Noa channel UUID**, not a Discord channel snowflake or Google URL. It is the designated consented project/source context for these meeting minutes: channel must belong to this workspace, be enabled, and map to the selected project (or use split routing). This reuses the existing Channel/Episode graph contract without inventing a new Meet channel platform. No meeting URL is fetched by the backend.

Limits: 1–400 utterances, unique positive sequence ids <=1000, speaker <=100 characters, text <=2000 characters per utterance and <=120,000 total characters; timestamps are relative integer milliseconds within one hour with end >= start. Submit recent/completed standups; historical-call date semantics are not implemented. Split longer calls into bounded, independently identified segments. Duplicate exact sequence ids are deduplicated; conflicting content is rejected. Retrying the same `external_id` with identical content returns the existing meeting; different content for that id is a conflict. A malformed batch rolls back all session/source writes.

The response is `201 {"meeting": {"id": "...", "status": "processing", ...}}`. Poll:

- `GET /api/orgs/:org_id/meetings` — list tracked sessions (without full transcripts).
- `GET /api/orgs/:org_id/meetings/:id` — status, source, transcript and typed minutes/proposal ids.

Processing runs through Oban with validated InstructorLite output, retried up to three times. Status becomes `review` when notes/proposals are ready, or `failed` after final failure. No work items are created on unsupported/free-text model output. Reprocessing a reviewed session does not duplicate proposals.

## Live acceptance checklist

- Check DAVE/Opus loading in the Linux image; enable the worker only after review.
- With two linked test members: request recording, verify the bot stays out until both consent.
- Speak explicit commitments/decisions mixed with jokes; verify speaker labels, timestamps and small-talk omission.
- Add an unconsented third participant: verify recording stops, notes say partial, and their speech is not transcribed.
- Stop/cancel as a regular participant; unlink a participant or disable the mapped source and verify capture/transcription stops.
- Verify audio is never persisted; inspect source citations and prove all tasks/decisions await approval.
- Test Soha's completed-transcript POST/retry and foreign-workspace/guest rejection.

Tests: `api/test/noa/meetings_test.exs`, `api/test/noa/meeting_voice_test.exs`, workspace endpoint permission coverage, and `cd api/priv/voice && npm test`.
