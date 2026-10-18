# Discord: Noa commands, replies and approvals (1.13, 2.5, 2.6)

## Connect the company

1. The Noa admin runs the shared bot using `DISCORD_BOT_TOKEN` and `DISCORD_CLIENT_ID`. In Discord's developer portal enable **Server Members** and **Message Content** intents. Noa also requests the Direct Messages intent for explicit questions to the bot; it never imports DMs as company sources.
2. An org admin adds the bot using Settings → Connectors → Add to Discord (bot + applications.commands scopes; View Channels, Send Messages, Read Message History). The bot is already in **nyi-tech**, server id `1502935253809893386`.
3. That org admin connects the server id in Settings → Connectors. Adding the bot to Discord alone does not connect the Noa workspace. A server belongs to one workspace.
4. Verify Settings → Channels. Only enable channels whose participants consented. Existing seed mappings may already be enabled by name, so review them before connecting the server. Unmapped/disabled channels are not ingested.

## Verify each person's account

Discord display names are not credentials. Existing name-inferred identities can attribute messages, but cannot authenticate commands, receive private work notifications or approve anything.

1. Accept your workspace invite and sign in to the hosted Noa web app.
2. In the connected server, run **`/noa link`**. Only you can see the response.
3. Open its private link and confirm in Settings. If login was needed, reopen the original link after signing in. The challenge expires after ten minutes, works once, and is invalidated by an API restart. Never share it.
4. Settings → Connectors → Your Discord account shows the verified user id and lets you unlink it. Choose **Discord** in Settings → Notifications for task, approval, digest and shift/agent-pack DMs. Allow DMs from the bot/server.

The link binds proof from Discord's authenticated gateway to the currently signed-in Noa member in that workspace. It does not grant a role. Generic people edits cannot forge/transfer verified handles. Another member cannot take an already verified account. Unlinking, removing workspace membership or disconnecting the server stops command/DM authentication immediately.

The production web app and API must share a parent domain (`app.heynoa.xyz` and `api.heynoa.xyz`). Until web hosting/DNS is configured, the secure link confirmation page is unavailable; do not bypass account verification to test commands.

## Commands

All slash-command results are **ephemeral**, including sources and errors. Noa acknowledges before database/model work, then edits that private response. Source/notification text cannot trigger Discord mentions.

| Command | What it does |
| --- | --- |
| `/noa help` | Setup and command guide; works before account linking |
| `/noa link` | One-time private account-link challenge; server must already be connected |
| `/noa ask question:…` | Permission-aware cited answer, using the same agent as the web/MCP |
| `/noa tasks` | Up to five of your open tasks, with **Start**, **Done**, **Need help** buttons |
| `/noa inbox` | Up to five pending proposals/changes, with **Approve/Reject** buttons |
| `/noa recap` | Last 24 hours of decisions for this channel's mapped project, with source quotes |
| `/noa brief` | KT context for this channel's mapped project, plus full brief/agent-pack link |
| `/noa connect project:veriq` | Noa **org admins only**: enable the current text/announcement channel and queue recent-history backfill |
| `/noa connect` | Org admins: enable split/per-message routing in the current channel |
| `/noa disconnect` | Org admins: stop reading this channel, retaining existing history |

Recap/brief need a project-mapped channel; split channels have no single project. Proposals without a project must be routed in the web Inbox before approval. Inbox visibility does not imply approval permission: every click rechecks the current actor and Ash policies. Discord's Manage Channels/Administrator flags never substitute for a Noa org-admin role.

**Mention replies:** mention @Noa in a consented mapped channel. A new accepted message is recorded once; its author must be verified. The cited answer is sent **privately by DM**, not posted to everyone in the channel (Discord participants are not automatically Noa members). If your DMs are blocked, use `/noa ask` for an ephemeral reply.

**DM follow-up questions:** a verified member can ask Noa directly, including after a handover. Noa answers from their workspace with their permissions, without recording the DM as an Episode or queuing extraction. If the Discord account is linked to multiple workspaces, use `/noa ask` in the intended server to avoid mixing contexts. Normal model audit/rate limiting still applies to questions explicitly sent to Noa.

## Notifications and buttons

The existing event-log notifier now sends Discord components for assigned tasks and pending lead changes. New pending proposals also notify their owner (or workspace leads when unowned) if their selected channel is Discord. **Need help** marks a task blocked through the Work API and alerts its lead. Digests, shifts and project allocations use the same verified DM destination, with brief/pack links.

Button ids carry workspace/action/item ids, never a bearer credential. All reads/mutations run as the verified member through Ash and the Work API; writes append events and only the projector writes the graph. Buttons from another workspace/guild are rejected. Approval clicks are serialized per item and stale decisions are refused. DMs only accept those permission-checked interactions; private conversation text is never ingested into company memory.

Per-node limits: 40 interactions/minute per Discord user, 20 agent questions/minute per member/workspace, plus mention/DM limits. Responses fit Discord's 2,000-character and 100-character custom-id limits; lists show at most five items, with web links for the rest.

## Replacing the old Tulpa commands

Noa and Tulpa v1 reused the same Discord application. On READY, Noa upserts the global **`/noa`** command and removes only the legacy **`/tulpa`** command. On guild creation/reconnect it does the same for guild-scoped registrations, so old guild commands do not shadow global changes. Unrelated application commands are preserved. A cached `/tulpa` invocation responds privately directing the user to `/noa`.

Stop any old Tulpa deployment using the same bot token; otherwise it can register the old commands again or compete for interactions. Keep the Discord application's **Interactions Endpoint URL empty** because Noa receives interactions over the authenticated gateway, not an HTTP interaction webhook. Global command caches can lag; guild registration is immediate.

An operator can retry registration inside the deployed node without printing secrets:

```sh
fly ssh console --app heynoa-api -C "/app/bin/noa rpc 'Noa.Ingest.Discord.Commands.register()'"
fly ssh console --app heynoa-api -C "/app/bin/noa rpc 'Noa.Ingest.Discord.Commands.register(\"1502935253809893386\")'"
```

## Verify

- Check `/noa help` appears, `/tulpa` disappears and both global/guild registration succeed.
- Link an org admin and a member; prove an unlinked/same-name user cannot read or act.
- Map a consented test channel; check one new message, duplicate delivery, edit and delete.
- Ask through slash command, mention and DM; check citations stay private and DMs never create Episodes.
- Assign a task; try Start/Done/Need help. Request a member deadline change; approve/reject as lead and confirm member/guest clicks fail.
- Try `/noa inbox`, recap and brief; move a person in the web app and check their KT/pack DM.
- Unlink/remove a member or disconnect the server; old buttons must stop working.

Tests: `api/test/noa/ingest/discord_commands_test.exs`, existing Discord ingest tests and workspace endpoint permission coverage. Provider transport is stubbed in automated tests; real Discord clicks still need a live run with linked accounts.
