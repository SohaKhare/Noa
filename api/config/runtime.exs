import Config

if config_env() == :prod do
  config :noa, Noa.Repo,
    url: System.fetch_env!("DATABASE_URL"),
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: if(System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: [])

  config :noa, Noa.Graph, url: System.get_env("FALKORDB_URL"), projector: true

  config :noa,
    web_origin: System.fetch_env!("WEB_ORIGIN"),
    api_base_url: System.fetch_env!("API_BASE_URL"),
    token_signing_secret: System.fetch_env!("TOKEN_SIGNING_SECRET")

  config :noa, NoaWeb.Endpoint,
    url: [host: URI.parse(System.fetch_env!("API_BASE_URL")).host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT") || "4000")],
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
    server: true
end
