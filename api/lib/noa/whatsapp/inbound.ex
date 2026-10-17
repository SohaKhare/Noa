defmodule Noa.WhatsApp.Inbound do
  @moduledoc """
  A WhatsApp message to Noa (1.15, 2.7), from Kapso's webhook. Noa finds the person by
  their number (Settings → Notifications) and acts as them:

  - Button taps: `start:`/`done:` move the card, `help:` tells the lead,
    `approve_change:`/`reject_change:` decide a pending change (leads only, by policy).
  - "done" or "on it", alone or with a task name: moves that task (alone: the task Noa
    last messaged them about).
  - Anything else is a question for `@noa`, answered from the graph with sources.

  Messages to Noa are commands and questions, never team chat: they are not extracted.
  """
  use Oban.Worker, queue: :whatsapp, max_attempts: 3
  require Ash.Query

  alias Noa.{WhatsApp, Work}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payload" => payload}}) do
    handle(payload)
    :ok
  end

  @doc "Handles one inbound message. Returns the reply text it sent (for tests)."
  def handle(%{"message" => message} = payload) do
    phone = get_in(payload, ["conversation", "phone_number"]) || message["from"] || ""
    person = person_by_phone(phone)
    {action, text} = parse(message)

    WhatsApp.record(%{
      org_id: person && person.org_id,
      person_id: person && person.id,
      direction: "in",
      phone: phone,
      kind: message["type"] || "text",
      body: text || action,
      buttons: nil,
      context: %{},
      wa_message_id: message["id"],
      status: "received",
      error: nil
    })

    reply =
      cond do
        is_nil(person) ->
          "I don't know this number yet. Add it in Noa under Settings → Notifications, then message me again."

        is_nil(user(person)) ->
          "You're in the org map but haven't joined Noa yet. Accept your invite, then message me again."

        action ->
          button(action, person)

        # Threading uses the number as Noa stored it: Kapso leaves out the "+".
        true ->
          text(String.trim(text || ""), person, person.phone)
      end

    WhatsApp.send(person || %{phone: phone, org_id: nil, id: nil}, reply)
    reply
  end

  defp parse(%{"type" => "interactive", "interactive" => %{"button_reply" => %{"id" => id}}}), do: {id, nil}
  defp parse(%{"type" => "button", "button" => %{"payload" => id}}), do: {id, nil}
  defp parse(%{"text" => %{"body" => body}}), do: {nil, body}
  defp parse(_), do: {nil, ""}

  ## Buttons

  defp button("start:" <> task_id, p), do: move(task_id, :in_progress, p)
  defp button("done:" <> task_id, p), do: move(task_id, :done, p)

  defp button("help:" <> task_id, p) do
    task = Ash.get!(Work.Task, task_id, authorize?: false)
    project = Ash.get!(Work.Project, task.project_id, authorize?: false, load: [:lead])

    case project.lead do
      %Work.Person{} = lead when lead.id != p.id ->
        if match?({:whatsapp, _}, Work.notify_target(lead)),
          do:
            WhatsApp.send(lead, "#{p.name} needs help with \"#{task.title}\" in #{project.name}.",
              context: %{"task_id" => task.id}
            )

        "I've told #{lead.name} you need help with \"#{task.title}\"."

      _ ->
        "I couldn't find a lead for #{project.name}. Ask in the project channel."
    end
  end

  defp button("approve_change:" <> id, p), do: decide(id, :approve, p)
  defp button("reject_change:" <> id, p), do: decide(id, :reject, p)
  defp button(_other, _p), do: "I didn't understand that button."

  defp move(task_id, status, p) do
    case Work.update_task(task_id, %{status: status, reason: "From WhatsApp"}, user(p)) do
      {:ok, task} ->
        if status == :done, do: "Done: \"#{task.title}\" is off your list.", else: "\"#{task.title}\" is in progress."

      {:error, %Ash.Error.Forbidden{}} ->
        "You can't change that task."

      {:error, _} ->
        "I couldn't update that task. Try the board in Noa."
    end
  end

  defp decide(id, verb, p) do
    fun = if verb == :approve, do: &Work.approve_change/2, else: &Work.reject_change/2

    case fun.(id, user(p)) do
      {:ok, change} -> "#{if verb == :approve, do: "Approved", else: "Turned down"}: the #{change.kind} change."
      {:error, :already_decided} -> "Someone already decided that one."
      {:error, %Ash.Error.Forbidden{}} -> "Only the project's lead can decide that."
      {:error, _} -> "I couldn't do that. Try the Inbox in Noa."
    end
  end

  ## Text

  @done ~r/^(done|finished|completed|shipped)\b[\s:,-]*/i
  @start ~r/^(start|starting|on it|working on)\b[\s:,-]*/i

  defp text("", _p, _phone), do: "Ask me anything about your projects, or reply \"done\" when you finish a task."

  defp text(text, p, phone) do
    cond do
      text =~ @done -> by_text(Regex.replace(@done, text, ""), :done, p, phone)
      text =~ @start -> by_text(Regex.replace(@start, text, ""), :in_progress, p, phone)
      true -> ask(text, p)
    end
  end

  # "done" alone means the task Noa last wrote about; "done <name>" finds it among theirs.
  defp by_text(rest, status, p, phone) do
    task_id =
      if String.trim(rest) == "" do
        case WhatsApp.last_out(phone) do
          %{context: %{"task_id" => id}} -> id
          _ -> nil
        end
      else
        {:ok, mine} = Work.tasks(p.org_id, user(p), owner_id: p.id, open: true)
        task = Enum.find(mine, &Noa.Work.Similar.same?(&1.title, rest))
        task && task.id
      end

    if task_id,
      do: move(task_id, status, p),
      else: "Which task? Reply with its name, like \"done Board report PDF export\"."
  end

  defp ask(question, p) do
    case Noa.Agent.ask(p.org_id, String.slice(question, 0, 500), user(p)) do
      {:ok, %{answer: answer, citations: citations}} ->
        sources =
          citations
          |> Enum.take(3)
          |> Enum.with_index(1)
          |> Enum.map_join("\n", fn {c, i} ->
            "[#{i}] #{c.title}#{c.source && c.source["channel"] && " (#{c.source["channel"]})"}"
          end)

        answer <> if(sources == "", do: "", else: "\n\n" <> sources)

      _ ->
        "I couldn't answer that right now."
    end
  end

  ## Who

  # Numbers are compared by digits: Kapso sends 919800000000, Noa stores +919800000000.
  defp person_by_phone(phone) do
    digits = String.replace(phone, ~r/\D/, "")

    if digits == "" do
      nil
    else
      Work.Person
      |> Ash.Query.filter(not is_nil(phone))
      |> Ash.read!(authorize?: false)
      |> Enum.find(&(String.replace(&1.phone, ~r/\D/, "") == digits))
    end
  end

  defp user(%Work.Person{membership_id: nil}), do: nil

  defp user(%Work.Person{membership_id: id}) do
    Ash.get!(Noa.Orgs.Membership, id, authorize?: false, load: [:user]).user
  end
end
