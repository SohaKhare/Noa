defmodule Noa.Orgs.Senders.Invite do
  @moduledoc "Emails an org invite. The caller also gets the link back, so an admin can share it by hand."
  import Swoosh.Email
  alias Noa.Mailer

  def send(invite, org, url, invited_by) do
    who = if invited_by, do: invited_by.name || to_string(invited_by.email), else: "Noa"

    new()
    |> to(to_string(invite.email))
    |> from(Mailer.from())
    |> subject("#{who} invited you to #{org.name} on Noa")
    |> text_body("""
    #{who} invited you to join #{org.name} on Noa.

    Set up your account: #{url}

    The link works once and expires in 7 days. If you weren't expecting this, ignore it.
    """)
    |> html_body("""
    <p>#{who} invited you to join <strong>#{org.name}</strong> on Noa.</p>
    <p><a href="#{url}">Set up your account</a></p>
    <p>The link works once and expires in 7 days. If you weren't expecting this, ignore it.</p>
    """)
    |> Mailer.deliver()
  end
end
