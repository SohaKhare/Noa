defmodule Noa.WhatsApp.Notifier do
  @moduledoc """
  Turns the event log into WhatsApp messages (2.21 WhatsApp side, 2.7, 3.5): a reader of
  the log like the graph projector, with its own position (`whatsapp`). On first start it
  begins at the end of the log, so it never sends old news.

  - A task gets an owner (not themselves): "Vedant put you on …", buttons Start / Done / Need help.
  - A deadline or scope change waits for a lead: to the project lead, buttons Approve / Reject.
  - A pending change is decided: to whoever asked.
  - Someone moves projects: to them, with links to their brief and agent pack.
  - Someone is put on a project another way (onboarding, a task assigned to them): to
    them, saying their agent pack now covers it.

  Each person gets these on the channel they chose (`Noa.Notify`): WhatsApp with reply
  buttons, a Discord DM or email with a link to act in the web app, or nothing for "in
  app" (2.15, 2.21, 3.23). Quiet hours hold everything except approvals waiting on a lead.
  """
  use GenServer
  require Logger
  require Ash.Query

  alias Noa.{Events, Work}

  @name "whatsapp"
  @every 3_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    if Events.position(@name) == 0, do: Events.put_position(@name, latest())
    Events.subscribe()
    send(self(), :tick)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    run()
    Process.send_after(self(), :tick, @every)
    {:noreply, state}
  end

  def handle_info({:appended, _org}, state) do
    run()
    {:noreply, state}
  end

  defp latest do
    import Ecto.Query
    Noa.Repo.one(from(e in Events.Event, select: max(e.id))) || 0
  end

  defp run do
    for event <- Events.since(Events.position(@name), limit: 100) do
      try do
        handle(event)
      rescue
        e -> Logger.warning("WhatsApp notifier skipped event #{event.id}: #{Exception.message(e)}")
      end

      Events.put_position(@name, event.id)
    end
  end

  @doc "The messages one event causes, sent now. Returns the list of `{person, text, opts}` it sent."
  def handle(%{type: "proposal.saved", data: %{"status" => "pending"} = d} = event) do
    if is_nil(previous(event)) do
      recipients =
        if d["owner_id"], do: [person(d["owner_id"])], else: leads(%{project_id: d["project_id"], org_id: event.org_id})

      recipients
      |> Enum.filter(&(&1 && &1.notify_via == :discord))
      |> Enum.flat_map(fn recipient ->
        deliver(event, recipient, "Noa found a proposal: #{d["summary"]}",
          buttons: [{"approve:#{d["id"]}", "Approve"}, {"reject:#{d["id"]}", "Reject"}],
          link: "/inbox"
        )
      end)
    else
      []
    end
  end

  def handle(%{type: "task.saved", data: d} = event) do
    previous = previous(event)

    if d["owner_id"] && d["status"] != "done" && (is_nil(previous) or previous.data["owner_id"] != d["owner_id"]) do
      owner = person(d["owner_id"])
      by = actor_name(event)
      due = d["due_on"] && ", due #{d["due_on"]}"

      deliver(event, owner, "#{by || "Noa"} put you on \"#{d["title"]}\" in #{project_name(d["project_id"])}#{due}.",
        buttons: [{"start:#{d["id"]}", "Start now"}, {"done:#{d["id"]}", "Done"}, {"help:#{d["id"]}", "Need help"}],
        context: %{"task_id" => d["id"]},
        link: "/"
      )
    else
      cond do
        # Finished work reaches the lead without anyone writing a status update.
        (d["status"] == "done" and previous) && previous.data["status"] != "done" ->
          owner = d["owner_id"] && person(d["owner_id"])
          who = actor_name(event) || (owner && owner.name) || "Someone"

          leads(%{project_id: d["project_id"], org_id: event.org_id})
          |> Enum.flat_map(
            &deliver(event, &1, "#{who} finished \"#{d["title"]}\" in #{project_name(d["project_id"])}.", link: "/")
          )

        (d["status"] == "blocked" and previous) && previous.data["status"] != "blocked" ->
          leads(%{project_id: d["project_id"], org_id: event.org_id})
          |> Enum.flat_map(fn lead ->
            deliver(
              event,
              lead,
              "#{actor_name(event) || "Someone"} needs help with \"#{d["title"]}\": #{d["blocked_reason"] || "Blocked"}.",
              link: "/"
            )
          end)

        true ->
          []
      end
    end
  end

  def handle(%{type: "change.saved", data: %{"status" => "pending"} = d} = event) do
    if is_nil(previous(event)) do
      task = Ash.get!(Work.Task, d["task_id"], authorize?: false)

      for lead <- leads(task) do
        deliver(
          event,
          lead,
          "#{actor_name(event) || "Someone"} wants to change the #{d["kind"]} of \"#{task.title}\": #{d["old_value"] || "none"} → #{d["new_value"] || "none"}#{d["reason"] && " (#{d["reason"]})"}.",
          buttons: [{"approve_change:#{d["id"]}", "Approve"}, {"reject_change:#{d["id"]}", "Reject"}],
          context: %{"change_id" => d["id"], "task_id" => d["task_id"]},
          link: "/inbox",
          urgent: true
        )
      end
      |> List.flatten()
    else
      []
    end
  end

  def handle(%{type: "change.saved", data: %{"status" => status} = d} = event) when status in ["applied", "rejected"] do
    case previous(event) do
      %{data: %{"status" => "pending"}} ->
        task = Ash.get!(Work.Task, d["task_id"], authorize?: false)
        asker = d["requested_by_id"] && person_for_user(d["requested_by_id"], task.org_id)
        verb = if status == "applied", do: "approved", else: "turned down"

        deliver(
          event,
          asker,
          "#{actor_name(event) || "Your lead"} #{verb} your #{d["kind"]} change to \"#{task.title}\" (#{d["new_value"]}).",
          context: %{"task_id" => d["task_id"]}
        )

      _ ->
        []
    end
  end

  def handle(%{type: "shift.saved", data: d} = event) do
    to = d["to_project_id"] && project_name(d["to_project_id"])
    from = d["from_project_id"] && project_name(d["from_project_id"])
    web = Application.fetch_env!(:noa, :web_origin)

    text =
      "You're moving #{if from, do: "from #{from} "}to #{to || "the bench"} from #{d["starts_on"]}." <>
        if(to, do: " Your brief and agent pack: #{web}/pack. Ask me anything about #{to} here.", else: "")

    deliver(event, person(d["person_id"]), text, context: %{"shift_id" => d["id"]})
  end

  # Someone is put on a project (onboarding, the People board, or a task assigned to them):
  # their agent pack now covers it. A shift says the same in its own message.
  def handle(%{type: "allocation.saved", data: d} = event) do
    if is_nil(previous(event)) and not from_shift?(d) do
      project = project_name(d["project_id"])
      web = Application.fetch_env!(:noa, :web_origin)
      why = if d["role"] == "contributor", do: "You have a task there now, so ", else: ""

      deliver(
        event,
        person(d["person_id"]),
        "#{actor_name(event) || "Noa"} put you on #{project} (#{d["percent"]}%). #{why}your agent pack and brief now cover #{project}: #{web}/pack. Connect your coding agent from that page to give it the context.",
        context: %{"allocation_id" => d["id"]},
        link: "/pack"
      )
    else
      []
    end
  end

  def handle(_event), do: []

  defp from_shift?(d) do
    Work.Shift
    |> Ash.Query.filter(person_id == ^d["person_id"] and to_project_id == ^d["project_id"])
    |> Ash.Query.filter(starts_on == ^Date.from_iso8601!(d["starts_on"]))
    |> Ash.exists?(authorize?: false)
  end

  ## Delivery

  defp deliver(_event, nil, _text, _opts), do: []

  defp deliver(event, %Work.Person{} = p, text, opts) do
    to_self = p.membership_id && event.actor_id && membership_user(p) == event.actor_id

    cond do
      to_self -> []
      Work.quiet?(p) and not Keyword.get(opts, :urgent, false) -> []
      true -> [Noa.Notify.deliver(p, text, opts)] |> Enum.reject(&(&1 == :skipped))
    end
  end

  ## Lookups (as Noa: the events were already authorized)

  defp previous(%{subject_id: nil}), do: nil

  defp previous(event) do
    event.org_id |> Events.history(event.subject_id) |> Enum.filter(&(&1.id < event.id)) |> List.last()
  end

  defp person(nil), do: nil
  defp person(id), do: Ash.get!(Work.Person, id, authorize?: false)

  defp person_for_user(user_id, org_id) do
    Work.Person
    |> Ash.Query.filter(org_id == ^org_id and membership.user_id == ^user_id)
    |> Ash.read_one!(authorize?: false)
  end

  defp membership_user(%{membership_id: id}), do: Ash.get!(Noa.Orgs.Membership, id, authorize?: false).user_id

  defp actor_name(%{actor_id: nil}), do: nil
  defp actor_name(%{actor_id: id, org_id: org}), do: (p = person_for_user(id, org)) && p.name

  defp project_name(nil), do: "a project"
  defp project_name(id), do: Ash.get!(Work.Project, id, authorize?: false).name

  # The project's lead, or the workspace's admins and PMs if it has none.
  defp leads(task) do
    project = task.project_id && Ash.get!(Work.Project, task.project_id, authorize?: false)

    if project && project.lead_id do
      [person(project.lead_id)]
    else
      Work.Person
      |> Ash.Query.filter(org_id == ^task.org_id and membership.role in [:org_admin, :pm])
      |> Ash.read!(authorize?: false)
    end
  end
end
