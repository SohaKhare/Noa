import Config

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
      language: System.get_env("KAPSO_TEMPLATE_LANG", "en")
    },
    notifier: System.get_env("NOA_WHATSAPP_NOTIFIER", "true") == "true"
end

if config_env() == :prod do
  config :noa, Noa.Repo,
    url: System.fetch_env!("DATABASE_URL"),
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: if(System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: [])

  config :noa, Noa.Graph, url: System.get_env("FALKORDB_URL"), projector: true

  config :noa,
    web_origin: System.fetch_env!("WEB_ORIGIN"),
    api_base_url: System.fetch_env!("API_BASE_URL"),
    token_signing_secret: System.fetch_env!("TOKEN_SIGNING_SECRET"),
    mail_from: {System.get_env("MAIL_FROM_NAME", "Noa"), System.fetch_env!("MAIL_FROM_EMAIL")},
    discord_bot_token: System.get_env("DISCORD_BOT_TOKEN"),
    discord_guild_id: System.get_env("DISCORD_GUILD_ID"),
    discord_org_id: System.get_env("DISCORD_ORG_ID")

  config :nostrum,
    token: System.get_env("DISCORD_BOT_TOKEN"),
    gateway_intents: [:guilds, :guild_messages, :guild_members, :message_content]

  config :noa, Noa.Mailer,
    adapter: Noa.Mailer.Resend

  config :noa, Noa.Mailer.Resend,
    api_key: System.fetch_env!("RESEND_API_KEY"),
    endpoint: System.get_env("RESEND_API_URL", "https://api.resend.com/emails")

  config :noa, NoaWeb.Endpoint,
    url: [host: URI.parse(System.fetch_env!("API_BASE_URL")).host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT") || "4000")],
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
    server: true
end
