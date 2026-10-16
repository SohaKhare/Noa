defmodule Noa.Accounts.Senders.PasswordReset do
  @moduledoc "Emails a password reset link to the web app's reset page."
  use AshAuthentication.Sender
  import Swoosh.Email
  alias Noa.Mailer

  @impl true
  def send(user, token, _opts) do
    url = Mailer.web_url("/reset-password?token=" <> URI.encode_www_form(token))

    new()
    |> to(to_string(user.email))
    |> from(Mailer.from())
    |> subject("Reset your Noa password")
    |> text_body("Choose a new password: #{url}\n\nIf you didn't ask for this, ignore this email.")
    |> html_body("""
    <p><a href="#{url}">Choose a new Noa password</a></p>
    <p>If you didn't ask for this, ignore this email.</p>
    """)
    |> Mailer.deliver()
  end
end
