# Slack setup

Noa uses one Slack app that each company installs into its own workspace. The bot token returned by OAuth is encrypted in `org_connectors`; it is never sent to the web app. Postgres events remain the source of truth, and the existing event-log projector is the only writer to FalkorDB.

## Configure the Slack app

Create a Slack app and add this OAuth redirect URL:

```text
https://YOUR_API_HOST/slack/oauth/callback
```

Add these bot token scopes:

```text
channels:read
channels:history
groups:read
groups:history
users:read
chat:write
im:write
```

Enable Event Subscriptions with this request URL:

```text
https://YOUR_API_HOST/webhooks/slack
```

Keep Socket Mode off. Noa receives events through the signed HTTP request URL above;
Socket Mode sends them over a WebSocket connection that this integration does not run.

Subscribe to these bot events:

```text
message.channels
message.groups
team_join
user_change
app_uninstalled
```

Under **App Home → Show Tabs**, enable the **Messages Tab** so outbound Noa
notifications are visible in Slack. Leave **Allow users to send slash commands and
messages from the messages tab** off: Noa sends notifications there but never reads
direct messages.

Set `SLACK_CLIENT_ID`, `SLACK_CLIENT_SECRET`, and `SLACK_SIGNING_SECRET` on the API. Keep `SLACK_HISTORY_LIMIT=15` unless the app qualifies for Slack's higher Marketplace or internal-app [history limits](https://docs.slack.dev/apis/web-api/rate-limits/).

An organization admin can then open Settings → Connectors and choose **Install Noa on Slack**. After OAuth, add the bot to each public or private channel that the company consents to share, then map those channels under Settings → Channels or during onboarding. Noa does not list channels it has not joined, archived channels, Slack Connect channels, DMs, or group DMs.

## Local test

Start Postgres, FalkorDB, the API, and the web app. Expose the API with a temporary HTTPS tunnel:

```sh
docker compose up -d postgres
docker compose --profile graph up -d
cd api && mix phx.server
cloudflared tunnel --url http://localhost:4000
```

Temporarily put the generated HTTPS host in the Slack app's OAuth redirect and Events API request URLs. Set `API_BASE_URL` to that host before starting Phoenix so the generated OAuth link uses the same redirect. Do not commit the tunnel URL or Slack credentials.

Use a test workspace with one public channel, one private channel, and one unmapped channel. Verify OAuth, discovery, initial backfill, live messages, edits, deletes, identity sync, a Slack DM notification, and disconnect. Confirm that the unmapped channel, DMs, group DMs, bot messages, and Slack Connect messages never appear in Noa's event log.

Slack requests are checked against the unmodified request body with the platform's [signing procedure](https://docs.slack.dev/authentication/verifying-requests-from-slack/). Valid Events API deliveries are persisted to Oban before the endpoint acknowledges them, keeping the request inside Slack's [three-second response window](https://docs.slack.dev/apis/events-api/).
