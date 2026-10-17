import Config

# The graph (1.9). Locally: `docker compose --profile graph up -d`. Prod sets FALKORDB_URL.
config :noa, Noa.Graph, url: "redis://127.0.0.1:6379", projector: true

# Noa.Events.Record notifies the projector after a commit; inside an outer transaction
# that is an early, harmless poke, so Ash's warning about it is off.
config :ash, warn_on_transaction_hooks?: false

# Never log these request fields (4.3).
config :phoenix, :filter_parameters, ["password", "token", "reset_token", "secret", "api_key", "key"]

# Background jobs. Extraction runs one channel at a time per org (1.17).
config :noa, Oban, repo: Noa.Repo, queues: [extraction: 2, whatsapp: 4]

# Proposals at or above this confidence apply themselves, with undo (2.2). nil turns it off.
config :noa, Noa.Work, auto_apply: 0.9

# Extraction waits this long after a channel's latest message, so a burst is one model call.
config :noa, Noa.Extraction, debounce_seconds: 20, utc_offset: 19_800

config :noa,
  ecto_repos: [Noa.Repo],
  ash_domains: [Noa.Accounts, Noa.Orgs, Noa.Work],
  web_origin: "http://localhost:3000",
  api_base_url: "http://localhost:4000",
  mail_from: {"Noa", "no-reply@noa.local"},
  token_signing_secret: "dev-only-token-signing-secret-change-me-0123456789"

config :noa, NoaWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [json: NoaWeb.ErrorJSON], layout: false],
  pubsub_server: Noa.PubSub

# Dev and test keep mail in memory; dev shows it at http://localhost:4000/dev/mailbox.
config :noa, Noa.Mailer, adapter: Swoosh.Adapters.Local
config :swoosh, :api_client, false

config :nostrum,
  token: System.get_env("DISCORD_BOT_TOKEN"),
  gateway_intents: [:guilds, :guild_messages, :guild_members, :message_content]

# The emailed magic link signs in on GET so it can redirect straight into the web app.
config :ash_authentication, :bypass_require_interaction_for_magic_link?, true

config :ash,
  allow_forbidden_field_for_relationships_by_default?: true,
  include_embedded_source_by_default?: false,
  show_keysets_for_all_actions?: false,
  default_page_type: :keyset,
  missed_notifications: :ignore,
  policies: [no_filter_static_forbidden_reads?: false],
  default_string_length_count: :codepoints

config :phoenix, :json_library, Jason
config :logger, :default_formatter, format: "$time $metadata[$level] $message\n", metadata: [:request_id]

import_config "#{config_env()}.exs"
