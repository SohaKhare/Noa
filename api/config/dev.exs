import Config

config :noa, Noa.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "noa_dev",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :noa, NoaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev-only-secret-key-base-0123456789abcdef0123456789abcdef0123456789abcdef0123456789"

config :noa, dev_routes: true
config :logger, :default_formatter, format: "[$level] $message\n"
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
