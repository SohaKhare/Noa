import Config

config :noa, Noa.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "noa_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :noa, NoaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test-only-secret-key-base-0123456789abcdef0123456789abcdef0123456789abcdef01234567",
  server: false

config :noa, Noa.Mailer, adapter: Swoosh.Adapters.Test
config :noa, Noa.Extraction, model: Noa.Extraction.Model.Stub
config :pbkdf2_elixir, :rounds, 1
config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
config :ash, :disable_async?, true
