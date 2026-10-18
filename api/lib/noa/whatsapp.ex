defmodule Noa.WhatsApp do
  @moduledoc """
  WhatsApp through Kapso (0.6, 1.15). `send/2` messages one person and records it in
  `whatsapp_messages`; `Noa.WhatsApp.Notifier` decides what to send from the event log;
  `Noa.WhatsApp.Inbound` handles replies from Kapso's webhook.

  Messages are plain text with up to three reply buttons. A button's id carries what it
  does (`done:<task id>`, `approve_change:<change id>`…), so a tap needs no lookup. Outside
  WhatsApp's 24-hour window free-form messages are refused; Noa then sends the same text
  through the approved template for that button set (docs/whatsapp.md).

  Configure with `KAPSO_API_KEY`, `KAPSO_PHONE_NUMBER_ID` and `KAPSO_WEBHOOK_SECRET`.
  Without them messages go to the local outbox only (status `simulated`), so the whole
  flow runs in development and tests.
  """
  import Ecto.Query

  alias Noa.Repo

  @doc """
  Sends `text` to a person, with optional reply `buttons` (`[{id, title}]`, at most three)
  and `context` (what it is about, kept with the message). Returns `{:ok, row}` or
  `{:error, reason}`; the message is recorded either way.
  """
  def send(%{phone: phone} = person, text, opts \\ []) when is_binary(phone) do
    buttons = Keyword.get(opts, :buttons, []) |> Enum.take(3)
    context = Keyword.get(opts, :context, %{})

    {status, wa_id, error} =
      case client().send(phone, text, buttons) do
        {:ok, wa_id} -> {"sent", wa_id, nil}
        :simulated -> {"simulated", nil, nil}
        {:error, reason} -> {"failed", nil, inspect(reason) |> String.slice(0, 500)}
      end

    row =
      record(%{
        org_id: person.org_id,
        person_id: person.id,
        direction: "out",
        phone: phone,
        kind: if(buttons == [], do: "text", else: "buttons"),
        body: text,
        buttons: Map.new(buttons),
        context: context,
        wa_message_id: wa_id,
        status: status,
        error: error
      })

    if status == "failed", do: {:error, error}, else: {:ok, row}
  end

  @doc "Records a message (in or out). Returns the row as a map."
  def record(attrs) do
    id = Ecto.UUID.generate()

    row =
      attrs
      |> Map.put(:id, Ecto.UUID.dump!(id))
      |> Map.update(:org_id, nil, &(&1 && Ecto.UUID.dump!(&1)))
      |> Map.update(:person_id, nil, &(&1 && Ecto.UUID.dump!(&1)))
      |> Map.put(:inserted_at, DateTime.utc_now())

    Repo.insert_all("whatsapp_messages", [row], on_conflict: :nothing)
    Map.merge(attrs, %{id: id, inserted_at: row.inserted_at})
  end

  @doc "Whether a Kapso message id was already handled (webhooks can repeat)."
  def seen?(wa_message_id) when is_binary(wa_message_id) do
    Repo.exists?(from(m in "whatsapp_messages", where: m.wa_message_id == ^wa_message_id))
  end

  def seen?(_), do: false

  @doc "Recent messages, newest first, for the outbox view: the org's, or one person's."
  def recent(org_id, person_id \\ :all, limit \\ 30) do
    from(m in "whatsapp_messages",
      where: m.org_id == type(^org_id, :binary_id),
      where: ^if(person_id == :all, do: true, else: dynamic([m], m.person_id == type(^person_id, :binary_id))),
      order_by: [desc: m.inserted_at],
      limit: ^limit,
      select: %{
        id: type(m.id, :binary_id),
        person_id: type(m.person_id, :binary_id),
        direction: m.direction,
        kind: m.kind,
        body: m.body,
        buttons: m.buttons,
        status: m.status,
        # Schemaless reads come back without a zone; mark them UTC for the browser.
        inserted_at: type(m.inserted_at, :utc_datetime_usec)
      }
    )
    |> Repo.all()
  end

  @doc "The last message Noa sent this phone, to make sense of a bare \"done\" reply."
  def last_out(phone) do
    from(m in "whatsapp_messages",
      where: m.phone == ^phone and m.direction == "out",
      order_by: [desc: m.inserted_at],
      limit: 1,
      select: %{context: m.context, inserted_at: m.inserted_at}
    )
    |> Repo.one()
  end

  def configured?, do: client() == Noa.WhatsApp.Kapso

  @doc """
  Whether `phone` wrote to Noa in the last 24 hours. Inside that window WhatsApp lets Noa
  send ordinary messages with buttons; outside it only approved templates go through.
  """
  def window_open?(nil), do: false

  def window_open?(phone) do
    since = DateTime.add(DateTime.utc_now(), -24 * 3600, :second)
    digits = String.replace(phone, ~r/\D/, "")

    Repo.exists?(
      from(m in "whatsapp_messages",
        where: m.direction == "in" and m.inserted_at >= ^since,
        where: fragment("regexp_replace(?, '\\D', '', 'g') = ?", m.phone, ^digits)
      )
    )
  end

  @doc "Noa's WhatsApp number as people see it (`KAPSO_DISPLAY_NUMBER`), for the 'message Noa' link."
  def display_number, do: Application.get_env(:noa, __MODULE__, [])[:display_number]

  defp client do
    config = Application.get_env(:noa, __MODULE__, [])

    cond do
      config[:client] -> config[:client]
      config[:api_key] && config[:phone_number_id] -> Noa.WhatsApp.Kapso
      true -> Noa.WhatsApp.Outbox
    end
  end
end
