defmodule Noa.Mailer do
  use Swoosh.Mailer, otp_app: :noa

  @doc "The From address for every Noa email."
  def from, do: Application.fetch_env!(:noa, :mail_from)

  @doc "Where links in emails point: the web app."
  def web_url(path), do: Application.fetch_env!(:noa, :web_origin) <> path

  @doc "Where API links in emails point (the magic-link sign-in)."
  def api_url(path), do: Application.fetch_env!(:noa, :api_base_url) <> path
end
