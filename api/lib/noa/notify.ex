defmodule Noa.Notify do
  @moduledoc """
  Sends one message to a person on the channel they chose in Settings → Notifications
  (2.15, 2.21): WhatsApp (with reply buttons), a Discord DM from Noa's bot, or email.
  Discord and email have no buttons, so they get a link to act in the web app instead.
  People on "in app" get nothing here; the bell shows it.

  Returns `{:ok, channel}`, `:skipped` (nothing to send on), or `{:error, reason}`.
  """
  alias Noa.Work

  def deliver(%Work.Person{} = person, text, opts \\ []) do
    case Work.notify_target(person) do
      {:whatsapp, _phone} ->
        with {:ok, _} <- Noa.WhatsApp.send(person, text, Keyword.take(opts, [:buttons, :context])), do: {:ok, :whatsapp}

      {:discord, _handle} ->
        with {:ok, _} <- Noa.Ingest.Discord.dm(person, with_link(text, opts)), do: {:ok, :discord}

      {:email, email} ->
        Swoosh.Email.new()
        |> Swoosh.Email.to({person.name, email})
        |> Swoosh.Email.from(Noa.Mailer.from())
        |> Swoosh.Email.subject(opts[:subject] || subject(text))
        |> Swoosh.Email.text_body(with_link(text, opts))
        |> Noa.Mailer.deliver()
        |> case do
          {:ok, _} -> {:ok, :email}
          error -> error
        end

      _ ->
        :skipped
    end
  end

  # Where to act on it, for channels without buttons.
  defp with_link(text, opts) do
    case opts[:link] do
      nil -> text
      path -> text <> "\n\n" <> Noa.Mailer.web_url(path)
    end
  end

  defp subject(text) do
    first = text |> String.split("\n") |> hd()
    if String.length(first) > 70, do: "Noa: " <> String.slice(first, 0, 66) <> "…", else: "Noa: " <> first
  end
end
