import Config

config :noa,
  ecto_repos: [Noa.Repo],
  ash_domains: [Noa.Accounts, Noa.Orgs],
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
