import Config

# Gmail IMAP is an explicit opt-in, isolated to one workspace (1.27).
if config_env() != :test and System.get_env("GMAIL_IMAP_ENABLED") == "true" do
  config :noa, Noa.Ingest.Gmail,
    enabled: true,
    org_id: System.fetch_env!("GMAIL_ORG_ID"),
    username: System.fetch_env!("GMAIL_IMAP_USERNAME"),
    password: System.fetch_env!("GMAIL_IMAP_PASSWORD"),
    host: "imap.gmail.com",
    port: 993
end

# WhatsApp through Kapso (1.15). Without these Noa keeps messages in a local outbox.
if config_env() != :test do
  config :noa, Noa.WhatsApp,
    api_key: System.get_env("KAPSO_API_KEY"),
    phone_number_id: System.get_env("KAPSO_PHONE_NUMBER_ID"),
    webhook_secret: System.get_env("KAPSO_WEBHOOK_SECRET"),
    templates: %{
      update: System.get_env("KAPSO_TEMPLATE_UPDATE"),
      task: System.get_env("KAPSO_TEMPLATE_TASK"),
      approval: System.get_env("KAPSO_TEMPLATE_APPROVAL"),
      language: System.get_env("KAPSO_TEMPLATE_LANG", "en_US")
    },
    notifier: System.get_env("NOA_WHATSAPP_NOTIFIER", "true") == "true",
    display_number: System.get_env("KAPSO_DISPLAY_NUMBER")
end

# GitHub (3.7): webhook secret, and a token for backfilling private repos.
if config_env() != :test do
  config :noa, Noa.GitHub,
    webhook_secret: System.get_env("GITHUB_WEBHOOK_SECRET"),
    token: System.get_env("GITHUB_TOKEN"),
    # Noa's GitHub App, registered by the Noa admin; companies install it from Settings.
    app_id: System.get_env("GITHUB_APP_ID"),
    slug: System.get_env("GITHUB_APP_SLUG"),
    private_key: System.get_env("GITHUB_APP_PRIVATE_KEY"),
    app_webhook_secret: System.get_env("GITHUB_APP_WEBHOOK_SECRET")
end

if config_env() == :prod do
  config :noa, Noa.Repo,
    url: System.fetch_env!("DATABASE_URL"),
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: if(System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: [])

  # rediss:// for FalkorDB Cloud (TLS); FALKORDB_IPV6=true for a FalkorDB app on Fly's private network.
  config :noa, Noa.Graph,
    url: System.get_env("FALKORDB_URL"),
    projector: true,
    socket_opts: if(System.get_env("FALKORDB_IPV6") in ~w(true 1), do: [:inet6], else: [])

  # The header that carries the client's address behind the proxy (rate limits).
  config :noa, NoaWeb.Plugs.RateLimit, ip_header: System.get_env("CLIENT_IP_HEADER", "fly-client-ip")

  config :noa,
    web_origin: System.fetch_env!("WEB_ORIGIN"),
    api_base_url: System.fetch_env!("API_BASE_URL"),
    token_signing_secret: System.fetch_env!("TOKEN_SIGNING_SECRET"),
    mail_from: {System.get_env("MAIL_FROM_NAME", "Noa"), System.get_env("MAIL_FROM_EMAIL", "no-reply@notyouridea.com")},
    discord_bot_token: System.get_env("DISCORD_BOT_TOKEN"),
    discord_guild_id: System.get_env("DISCORD_GUILD_ID"),
    discord_org_id: System.get_env("DISCORD_ORG_ID")

  config :nostrum,
    token: System.get_env("DISCORD_BOT_TOKEN"),
    gateway_intents: [:guilds, :guild_messages, :guild_members, :message_content, :direct_messages]

  # Without a Resend key, emails (invites, magic links, resets) are written to the log
  # so an admin can still pass a link on.
  if key = System.get_env("RESEND_API_KEY") do
    config :noa, Noa.Mailer, adapter: Noa.Mailer.Resend

    config :noa, Noa.Mailer.Resend,
      api_key: key,
      endpoint: System.get_env("RESEND_API_URL", "https://api.resend.com/emails")
  else
    config :noa, Noa.Mailer, adapter: Swoosh.Adapters.Logger, log_full_email: true
  end

  config :noa, NoaWeb.Endpoint,
    url: [host: URI.parse(System.fetch_env!("API_BASE_URL")).host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT") || "4000")],
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
    check_origin: [System.fetch_env!("WEB_ORIGIN")],
    server: true
end

# Email through Google Workspace SMTP (1.25), the same setup as Tulpa v1. With a Google
# app password present, invites, sign-in links, resets and notifications go out through
# Gmail; this wins over Resend and the log fallback. Gmail requires the From address to
# be the signed-in account (or a verified send-as alias), so From defaults to the SMTP
# user unless MAIL_FROM overrides.
smtp_password = System.get_env("GOOGLE_APP_PASSWORD")

if smtp_password && smtp_password != "" && config_env() != :test do
  smtp_username = System.get_env("MAIL_SMTP_USERNAME") || "itsupport@notyouridea.com"

  config :noa, Noa.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: "smtp.gmail.com",
    port: 587,
    username: smtp_username,
    password: smtp_password,
    ssl: false,
    tls: :always,
    auth: :always,
    retries: 2,
    # OTP 26+ verifies TLS but needs the CA certs and SNI given explicitly, or Gmail's
    # STARTTLS upgrade fails with :tls_failed.
    tls_options: [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: ~c"smtp.gmail.com",
      versions: [:"tlsv1.2", :"tlsv1.3"],
      depth: 3
    ]

  config :noa, mail_from: {System.get_env("MAIL_FROM_NAME", "Noa"), System.get_env("MAIL_FROM") || smtp_username}
end
