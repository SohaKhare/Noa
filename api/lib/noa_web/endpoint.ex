defmodule NoaWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :noa

  # The web app (localhost:3000 in dev) and the API are the same site, so this
  # httpOnly, SameSite=Lax cookie rides along on its fetches with credentials.
  @session_options [
    store: :cookie,
    key: "_noa_session",
    signing_salt: "noa-session",
    same_site: "Lax",
    http_only: true,
    max_age: 60 * 60 * 24 * 30
  ]

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(CORSPlug, origin: &NoaWeb.Endpoint.cors_origins/0, credentials: true)

  if code_reloading? do
    plug(Phoenix.CodeReloader)
  end

  plug(NoaWeb.Router)

  def cors_origins, do: [Application.fetch_env!(:noa, :web_origin)]
  def session_options, do: @session_options
end
