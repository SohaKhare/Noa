defmodule Noa.Accounts.Senders.MagicLink do
  @moduledoc "Emails a one-time sign-in link. The link hits the API, which signs in and redirects to the web app."
  use AshAuthentication.Sender
  import Swoosh.Email
  alias Noa.Mailer

  @impl true
  def send(user_or_email, token, _opts) do
    url = Mailer.api_url("/auth/user/magic_link?token=" <> URI.encode_www_form(token))

    new()
    |> to(email_of(user_or_email))
    |> from(Mailer.from())
    |> subject("Your Noa sign-in link")
    |> text_body(
      "Sign in to Noa: #{url}\n\nThe link works once and expires soon. If you didn't ask for it, ignore this email."
    )
    |> html_body("""
    <p>Click to sign in to Noa. The link works once and expires soon.</p>
    <p><a href="#{url}">Sign in to Noa</a></p>
    <p>If you didn't ask for this, ignore this email.</p>
    """)
    |> Mailer.deliver()
  end

  defp email_of(%{email: email}), do: to_string(email)
  defp email_of(email) when is_binary(email), do: email
end
