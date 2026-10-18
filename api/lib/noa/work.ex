defmodule Noa.Work do
  @moduledoc """
  Projects, people, tasks and the Inbox (1.24). Contract: docs/schema.md.

  Every function that acts for a person takes the `actor` and goes through Ash
  policies. `save_proposals/3` and `load_seed/2` run as Noa itself, without an actor.

  Writes go through the functions here, not straight to the resources, so the event
  log (1.8) can wrap each one and append its event in the same transaction.
  """
  use Ash.Domain, otp_app: :noa

  require Ash.Query
  import Ecto.Query, only: [from: 2]

  alias Noa.Extraction
  alias Noa.Repo
  alias Noa.Work.{Allocation, Change, Channel, Decision, Identity, Person, Project, ProjectAlias, Proposal, Shift, Task}

  resources do
    resource(Person)
    resource(Project)
    resource(ProjectAlias)
    resource(Allocation)
    resource(Channel)
    resource(Task)
    resource(Proposal)
    resource(Identity)
    resource(Decision)
    resource(Change)
    resource(Shift)
  end

  ## Reads

  @doc "People in the org with their current allocations."
  def people(org_id, actor) do
    Person
    |> Ash.Query.filter(org_id == ^org_id)
    |> Ash.Query.load([:allocations, :membership])
    |> Ash.Query.sort(:name)
    |> Ash.read(actor: actor)
    |> current_allocations()
  end

  @doc "Projects in the org with lead, aliases and current allocations."
  def projects(org_id, actor) do
    Project
    |> Ash.Query.filter(org_id == ^org_id)
    |> Ash.Query.load([:lead, :aliases, :allocations])
    |> Ash.Query.sort(:name)
    |> Ash.read(actor: actor)
    |> current_allocations()
  end

  # Allocations are kept after they end (a shift sets `ends_on`); lists show current ones.
  defp current_allocations({:ok, rows}) do
    today = Date.utc_today()
    current? = &(is_nil(&1.ends_on) or Date.compare(&1.ends_on, today) != :lt)
    {:ok, Enum.map(rows, &%{&1 | allocations: Enum.filter(&1.allocations, current?)})}
  end

  defp current_allocations(error), do: error

  def channels(org_id, actor) do
    Channel |> Ash.Query.filter(org_id == ^org_id) |> Ash.Query.sort(:name) |> Ash.read(actor: actor)
  end

  @doc "Tasks in the org. Filters: `project_id`, `owner_id`, `open: true` (not done)."
  def tasks(org_id, actor, filters \\ []) do
    Task
    |> Ash.Query.filter(org_id == ^org_id)
    |> then(fn q -> if id = filters[:project_id], do: Ash.Query.filter(q, project_id == ^id), else: q end)
    |> then(fn q -> if id = filters[:owner_id], do: Ash.Query.filter(q, owner_id == ^id), else: q end)
    |> then(fn q -> if filters[:open], do: Ash.Query.filter(q, status != :done), else: q end)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read(actor: actor)
  end

  @doc "Inbox: proposals in the org, newest first. `status` defaults to `:pending`."
  def proposals(org_id, actor, status \\ :pending) do
    Proposal
    |> Ash.Query.filter(org_id == ^org_id and status == ^status)
    |> Ash.Query.load([:project, :owner])
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read(actor: actor)
  end

  @doc """
  Decisions in the org, newest first. Filters: `project_id`, `since` (a DateTime),
  `status` (`:active` or `:superseded`; both when not given).
  """
  def decisions(org_id, actor, filters \\ []) do
    Decision
    |> Ash.Query.filter(org_id == ^org_id)
    |> then(fn q -> if id = filters[:project_id], do: Ash.Query.filter(q, project_id == ^id), else: q end)
    |> then(fn q -> if at = filters[:since], do: Ash.Query.filter(q, inserted_at >= ^at), else: q end)
    |> then(fn q -> if st = filters[:status], do: Ash.Query.filter(q, status == ^st), else: q end)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read(actor: actor)
  end

  @doc "The person record linked to the user's membership in the org, or nil."
  def person_for(%{id: user_id}, org_id) do
    Person
    |> Ash.Query.filter(org_id == ^org_id and membership.user_id == ^user_id)
    |> Ash.read_one!(authorize?: false)
  end

  ## Tasks

  def create_task(org_id, attrs, actor) do
    Repo.transaction(fn ->
      with {:ok, task} <-
             Task
             |> Ash.Changeset.for_create(:create, Map.merge(attrs, %{org_id: org_id, created_by_id: actor.id}),
               actor: actor
             )
             |> Ash.create(),
           :ok <- ensure_on_project(task) do
        task
      else
        {:error, error} -> Repo.rollback(error)
      end
    end)
  end

  @doc """
  Puts a task's owner on its project if they aren't on it yet: a 10% "contributor"
  allocation from today. Who works where, the graph, triage and the owner's agent pack
  then all include the project, and the notifier tells them their pack changed.
  """
  def ensure_on_project(%{owner_id: nil}), do: :ok
  def ensure_on_project(%{project_id: nil}), do: :ok

  def ensure_on_project(%{org_id: org_id, owner_id: person_id, project_id: project_id}) do
    today = Date.utc_today()

    on? =
      Allocation
      |> Ash.Query.filter(
        person_id == ^person_id and project_id == ^project_id and (is_nil(ends_on) or ends_on >= ^today)
      )
      |> Ash.exists?(authorize?: false)

    if on? do
      :ok
    else
      Allocation
      |> Ash.Changeset.for_create(:create, %{
        percent: 10,
        role: "contributor",
        org_id: org_id,
        person_id: person_id,
        project_id: project_id
      })
      |> Ash.create(authorize?: false)
      |> case do
        {:ok, _} -> :ok
        error -> error
      end
    end
  end

  # Task fields that are shared items (2.19), and the change kind each one records.
  @watched [due_on: :deadline, detail: :scope, owner_id: :owner, status: :status, title: :title]
  # Kinds that wait for a lead when anyone else makes them (2.20).
  @held [:deadline, :scope]

  @doc """
  Edits a task under the lead rules (2.19, 2.20). Every change to a shared field
  (deadline, scope, owner, status, title) is recorded in `changes`. A lead's edits apply
  at once; anyone else's deadline and scope changes wait as pending changes for a lead,
  and their other edits apply at once. `attrs` may carry a `:reason`.

  Returns `{:ok, task}`; the task does not yet have the held fields.
  """
  def update_task(task_id, attrs, actor, source \\ nil) do
    with {:ok, task} <- Ash.get(Task, task_id, actor: actor) do
      change_task(task, attrs, actor, source)
    end
  end

  defp change_task(task, attrs, actor, source) do
    {reason, attrs} = Map.pop(attrs, :reason)
    lead = Map.get(actor, :is_superadmin) || lead?(actor.id, task.org_id, task.project_id)

    {held, applied} =
      @watched
      |> Enum.filter(fn {field, _kind} -> Map.has_key?(attrs, field) end)
      |> Enum.map(fn {field, kind} -> {field, kind, value(Map.get(task, field)), value(Map.get(attrs, field))} end)
      |> Enum.reject(fn {_field, _kind, old, new} -> old == new end)
      |> Enum.split_with(fn {_field, kind, _old, _new} -> kind in @held and not lead end)

    rest = Map.drop(attrs, Enum.map(held, &elem(&1, 0)))

    Repo.transaction(fn ->
      with {:ok, updated} <-
             if(rest == %{}, do: {:ok, task}, else: Ash.update(task, rest, action: :update, actor: actor)),
           :ok <- record(task, applied, :applied, reason, source, actor),
           :ok <- record(task, held, :pending, reason, source, actor),
           :ok <- if(Enum.any?(applied, &(elem(&1, 0) == :owner_id)), do: ensure_on_project(updated), else: :ok) do
        updated
      else
        {:error, error} -> Repo.rollback(error)
      end
    end)
  end

  defp record(task, diffs, status, reason, source, actor) do
    Enum.reduce_while(diffs, :ok, fn {_field, kind, old, new}, :ok ->
      Change
      |> Ash.Changeset.for_create(
        :create,
        %{
          kind: kind,
          old_value: old,
          new_value: new,
          reason: reason,
          status: status,
          source: source,
          org_id: task.org_id,
          project_id: task.project_id,
          task_id: task.id,
          requested_by_id: actor.id
        },
        actor: actor
      )
      |> Ash.create()
      |> case do
        {:ok, _} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  # Values are compared and stored as strings: ISO dates, ids, status names.
  defp value(nil), do: nil
  defp value(""), do: nil
  defp value(%Date{} = d), do: Date.to_iso8601(d)
  defp value(v) when is_atom(v), do: Atom.to_string(v)
  defp value(v), do: to_string(v)

  @doc "An org admin or PM in the org, or the person set as the project's lead."
  def lead?(user_id, org_id, project_id) do
    Noa.Orgs.role(user_id, org_id) in [:org_admin, :pm] or
      (project_id != nil and
         Project
         |> Ash.Query.filter(id == ^project_id and lead.membership.user_id == ^user_id)
         |> Ash.exists?(authorize?: false))
  end

  @doc "Change records, newest first. Filters: `task_id`, `project_id`, `status`."
  def changes(org_id, actor, filters \\ []) do
    Change
    |> Ash.Query.filter(org_id == ^org_id)
    |> then(fn q -> if id = filters[:task_id], do: Ash.Query.filter(q, task_id == ^id), else: q end)
    |> then(fn q -> if id = filters[:project_id], do: Ash.Query.filter(q, project_id == ^id), else: q end)
    |> then(fn q -> if st = filters[:status], do: Ash.Query.filter(q, status == ^st), else: q end)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read(actor: actor)
  end

  @doc "A lead approves a pending change: it is applied to the task."
  def approve_change(change_id, actor), do: decide_change(change_id, :applied, actor)

  @doc "A lead rejects a pending change: the task stays as it was."
  def reject_change(change_id, actor), do: decide_change(change_id, :rejected, actor)

  defp decide_change(change_id, status, actor) do
    with {:ok, change} <- Ash.get(Change, change_id, actor: actor),
         :ok <- if(change.status == :pending, do: :ok, else: {:error, :already_decided}) do
      Repo.transaction(fn ->
        with {:ok, decided} <-
               change
               |> Ash.Changeset.for_update(:decide, %{status: status, decided_by_id: actor.id}, actor: actor)
               |> Ash.update(),
             {:ok, _task} <- if(status == :applied, do: set_field(change, change.new_value), else: {:ok, nil}) do
          decided
        else
          {:error, error} -> Repo.rollback(error)
        end
      end)
    end
  end

  @doc """
  Undoes an applied change, if the task still has the value it set. A lead or whoever
  made the change can revert it.
  """
  def revert_change(change_id, actor) do
    with {:ok, change} <- Ash.get(Change, change_id, actor: actor),
         :ok <- if(change.status == :applied, do: :ok, else: {:error, :already_decided}),
         task = Ash.get!(Task, change.task_id, authorize?: false),
         :ok <-
           if(value(Map.get(task, field(change.kind))) == change.new_value, do: :ok, else: {:error, :changed_since}) do
      Repo.transaction(fn ->
        with {:ok, reverted} <-
               change |> Ash.Changeset.for_update(:revert, %{decided_by_id: actor.id}, actor: actor) |> Ash.update(),
             {:ok, _task} <- set_field(change, change.old_value) do
          reverted
        else
          {:error, error} -> Repo.rollback(error)
        end
      end)
    end
  end

  defp field(kind), do: @watched |> Enum.find(fn {_f, k} -> k == kind end) |> elem(0)

  # The change was authorized above, so writing the field runs as Noa.
  defp set_field(change, value) do
    Task
    |> Ash.get!(change.task_id, authorize?: false)
    |> Ash.Changeset.for_update(:update, %{field(change.kind) => value})
    |> Ash.update(authorize?: false)
  end

  ## Notification preferences (2.15)

  @doc "Sets a person's notification preferences. They can set their own; admins and PMs anyone's."
  def set_notifications(person_id, attrs, actor) do
    with {:ok, person} <- Ash.get(Person, person_id, actor: actor) do
      person |> Ash.Changeset.for_update(:notifications, attrs, actor: actor) |> Ash.update()
    end
  end

  @doc """
  Where to reach a person (for 2.9 and 2.21): WhatsApp, Discord, Slack, email, or
  `:in_app` when the chosen channel has no address yet.
  """
  def notify_target(%Person{} = p) do
    case p.notify_via do
      :whatsapp when is_binary(p.phone) -> {:whatsapp, p.phone}
      :discord when p.handles != [] -> {:discord, hd(p.handles)}
      :slack -> {:slack, p.id}
      :email -> if email = p.email || account_email(p), do: {:email, to_string(email)}, else: :in_app
      _ -> :in_app
    end
  end

  # Members picked email in Settings; their org-map entry may not carry one, their account does.
  defp account_email(%Person{membership_id: nil}), do: nil

  defp account_email(%Person{membership_id: id}) do
    case Ash.get(Noa.Orgs.Membership, id, load: [:user], authorize?: false) do
      {:ok, m} -> m.user.email
      _ -> nil
    end
  end

  @doc """
  Whether `at` (UTC) falls in the person's quiet hours, in their local time. Quiet hours
  may wrap midnight (21:00 to 08:00). Approvals that block someone may still go out.
  """
  def quiet?(person, at \\ DateTime.utc_now())

  def quiet?(%Person{quiet_from: from, quiet_to: to} = p, at)
      when not is_nil(from) and not is_nil(to) do
    local = at |> DateTime.add(p.utc_offset * 60, :second) |> DateTime.to_time()

    if Time.compare(from, to) == :lt,
      do: Time.compare(local, from) != :lt and Time.compare(local, to) == :lt,
      else: Time.compare(local, from) != :lt or Time.compare(local, to) == :lt
  end

  def quiet?(_person, _at), do: false

  ## Shifts (3.1)

  # Questions about the old project go to the person who left it for this long.
  @route_days 14

  @doc """
  What a shift would do, without doing it: the person's open tasks in the project they
  leave, each with a suggested new owner. Suggested owners are the others on that
  project, least loaded first (allocation, then open tasks); the project lead if nobody
  else is on it.
  """
  def plan_shift(org_id, %{person_id: person_id, from_project_id: from}, actor) do
    with {:ok, people} <- people(org_id, actor),
         {:ok, open} <- tasks(org_id, actor, open: true) do
      project = from && Ash.get!(Project, from, actor: actor)

      tasks =
        if from, do: Enum.filter(open, &(&1.project_id == from and &1.owner_id == person_id)), else: []

      suggested = suggest_owner(people, open, project, person_id)

      {:ok,
       Enum.map(tasks, fn t ->
         %{task_id: t.id, title: t.title, status: t.status, due_on: t.due_on, to_owner_id: suggested && suggested.id}
       end)}
    end
  end

  defp suggest_owner(_people, _open, nil, _mover), do: nil

  defp suggest_owner(people, open, project, mover) do
    load = fn p -> Enum.sum(Enum.map(p.allocations, & &1.percent)) end
    open_count = fn p -> Enum.count(open, &(&1.owner_id == p.id)) end

    people
    |> Enum.filter(&(&1.id != mover and Enum.any?(&1.allocations, fn a -> a.project_id == project.id end)))
    |> Enum.sort_by(&{load.(&1), open_count.(&1)})
    |> List.first()
    |> Kernel.||(Enum.find(people, &(&1.id == project.lead_id and &1.id != mover)))
  end

  @doc """
  Moves a person (3.1). `attrs`: `person_id`, `from_project_id` and `to_project_id`
  (nil is the bench), optional `percent` (default: what they had on the old project, or
  100), `starts_on` (default today), `handover` (`%{task_id => new owner id or nil}`;
  tasks not listed get the suggested owner) and `note`.

  In one transaction: ends the old allocation the day before `starts_on`, starts the
  new one, reassigns the tasks (each recorded as an owner change) and saves the shift.
  Org admins and PMs only.
  """
  def shift(org_id, attrs, actor) do
    from = attrs[:from_project_id]
    to = attrs[:to_project_id]
    starts_on = attrs[:starts_on] || Date.utc_today()

    lead = Map.get(actor, :is_superadmin) || Noa.Orgs.role(actor.id, org_id) in [:org_admin, :pm]

    with :ok <- if(lead, do: :ok, else: {:error, :not_a_lead}),
         :ok <- if(from == to, do: {:error, :same_project}, else: :ok),
         {:ok, person} <- Ash.get(Person, attrs.person_id, actor: actor, load: [:allocations]),
         {:ok, plan} <- plan_shift(org_id, %{person_id: person.id, from_project_id: from}, actor) do
      old = Enum.find(person.allocations, &(&1.project_id == from and current?(&1)))
      percent = attrs[:percent] || (old && old.percent) || 100
      chosen = attrs[:handover] || %{}

      handover =
        Enum.map(plan, fn t ->
          owner = if Map.has_key?(chosen, t.task_id), do: chosen[t.task_id], else: t.to_owner_id
          %{"task_id" => t.task_id, "title" => t.title, "to_owner_id" => owner}
        end)

      Repo.transaction(fn ->
        with {:ok, shift} <-
               Shift
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   org_id: org_id,
                   person_id: person.id,
                   from_project_id: from,
                   to_project_id: to,
                   percent: percent,
                   starts_on: starts_on,
                   routes_until: from && Date.add(starts_on, @route_days),
                   handover: handover,
                   note: attrs[:note],
                   created_by_id: actor.id
                 },
                 actor: actor
               )
               |> Ash.create(),
             :ok <- end_allocation(old, starts_on, actor),
             :ok <- start_allocation(org_id, person, to, percent, starts_on, actor),
             :ok <- hand_over(handover, actor) do
          shift
        else
          {:error, error} -> Repo.rollback(error)
        end
      end)
    end
  end

  defp current?(a), do: is_nil(a.ends_on) or Date.compare(a.ends_on, Date.utc_today()) != :lt

  defp end_allocation(nil, _starts_on, _actor), do: :ok

  defp end_allocation(allocation, starts_on, actor) do
    allocation
    |> Ash.Changeset.for_update(:update, %{ends_on: Date.add(starts_on, -1)}, actor: actor)
    |> Ash.update()
    |> ok()
  end

  defp start_allocation(_org_id, _person, nil, _percent, _starts_on, _actor), do: :ok

  defp start_allocation(org_id, person, project_id, percent, starts_on, actor) do
    Allocation
    |> Ash.Changeset.for_create(
      :create,
      %{org_id: org_id, person_id: person.id, project_id: project_id, percent: percent, starts_on: starts_on},
      actor: actor
    )
    |> Ash.create()
    |> ok()
  end

  defp hand_over(handover, actor) do
    Enum.reduce_while(handover, :ok, fn h, :ok ->
      case update_task(h["task_id"], %{owner_id: h["to_owner_id"], reason: "Handed over in a shift"}, actor) do
        {:ok, _} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp ok({:ok, _}), do: :ok
  defp ok(error), do: error

  @doc "Shifts in the org, newest first. `person_id` or `project_id` (either side) narrow it."
  def shifts(org_id, actor, filters \\ []) do
    Shift
    |> Ash.Query.filter(org_id == ^org_id)
    |> then(fn q -> if id = filters[:person_id], do: Ash.Query.filter(q, person_id == ^id), else: q end)
    |> then(fn q ->
      if id = filters[:project_id], do: Ash.Query.filter(q, from_project_id == ^id or to_project_id == ^id), else: q
    end)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read(actor: actor)
  end

  @doc "People who left the project recently and still take questions about it (until `routes_until`)."
  def previous_owners(org_id, project_id, actor) do
    today = Date.utc_today()

    with {:ok, shifts} <- shifts(org_id, actor, project_id: project_id) do
      {:ok,
       Enum.filter(
         shifts,
         &((&1.from_project_id == project_id and &1.routes_until) && Date.compare(&1.routes_until, today) != :lt)
       )}
    end
  end

  @doc "The KT brief for a project (3.2), optionally for the person joining it. See `Noa.Work.Brief`."
  defdelegate brief(org_id, project_id, actor, person_id \\ nil), to: Noa.Work.Brief, as: :build

  ## Channels

  @doc "Maps a channel to a project, to split routing, or turns reading off. Org admins only (policy)."
  def update_channel(channel_id, attrs, actor) do
    with {:ok, channel} <- Ash.get(Channel, channel_id, actor: actor) do
      channel |> Ash.Changeset.for_update(:update, attrs, actor: actor) |> Ash.update()
    end
  end

  ## Inbox

  @doc """
  Approves a pending proposal and applies it, in one transaction. `edits` may change
  `summary`, `project_id`, `owner_id` and fields in `data` (title, due) first, so
  "edit, then approve" is one step. Returns `{:ok, proposal}` with `task` loaded.

  A task proposal needs a project; without one this returns `{:error, :needs_project}`.
  Decisions and scope changes are recorded as approved; they get their own records in
  2.4 and 2.19.
  """
  def approve(proposal_id, edits, actor) do
    with {:ok, proposal} <- pending(proposal_id, actor) do
      Repo.transaction(fn ->
        attrs =
          edits
          |> Map.take([:summary, :project_id, :owner_id])
          |> Map.put(:data, Map.merge(proposal.data, Map.get(edits, :data, %{})))

        merged = struct(proposal, attrs)

        with {:ok, task} <- apply_proposal(merged, actor),
             {:ok, decided} <-
               decide(proposal, Map.merge(attrs, %{status: :approved, task_id: task && task.id}), actor) do
          Ash.load!(decided, [:task, :project, :owner], authorize?: false)
        else
          {:error, error} -> Repo.rollback(error)
        end
      end)
    end
  end

  def reject(proposal_id, actor) do
    with {:ok, proposal} <- pending(proposal_id, actor) do
      decide(proposal, %{status: :rejected}, actor)
    end
  end

  defp pending(proposal_id, actor) do
    case Ash.get(Proposal, proposal_id, actor: actor) do
      {:ok, %{status: :pending} = p} -> {:ok, p}
      {:ok, _} -> {:error, :already_decided}
      error -> error
    end
  end

  defp decide(proposal, attrs, actor) do
    proposal
    |> Ash.Changeset.for_update(:decide, Map.put(attrs, :decided_by_id, actor.id), actor: actor)
    |> Ash.update()
  end

  # The approval was authorized above, so applying it runs as Noa.
  defp apply_proposal(%{kind: :task, project_id: nil}, _actor), do: {:error, :needs_project}

  defp apply_proposal(%{kind: :task} = p, actor) do
    Task
    |> Ash.Changeset.for_create(:create, %{
      title: p.data["title"] || p.summary,
      detail: p.data["detail"],
      due_on: p.data["due"],
      source: p.source,
      org_id: p.org_id,
      project_id: p.project_id,
      owner_id: p.owner_id,
      created_by_id: actor.id
    })
    |> Ash.create(authorize?: false)
    |> then(fn
      {:ok, task} -> with(:ok <- ensure_on_project(task), do: {:ok, task})
      error -> error
    end)
  end

  # Status and deadline changes follow the lead rules: a member approving their own
  # deadline change turns it into a pending change for their lead (2.20).
  defp apply_proposal(%{kind: kind, task_id: task_id} = p, actor)
       when kind in [:status_change, :deadline_change] and not is_nil(task_id) do
    changes =
      case kind do
        :status_change -> %{status: p.data["status"], blocked_reason: p.data["blocker"]}
        :deadline_change -> %{due_on: p.data["new_due"], reason: p.data["reason"]}
      end

    Task |> Ash.get!(task_id, authorize?: false) |> change_task(changes, actor, p.source)
  end

  # From the triage agent (3.24): the owner change is recorded like any other edit.
  defp apply_proposal(%{kind: :assignment, task_id: task_id} = p, actor) when not is_nil(task_id) do
    Task
    |> Ash.get!(task_id, authorize?: false)
    |> change_task(%{owner_id: p.owner_id, reason: p.data["reason"]}, actor, p.source)
  end

  defp apply_proposal(%{kind: :decision} = p, actor) do
    with {:ok, decision} <-
           Decision
           |> Ash.Changeset.for_create(:create, %{
             statement: p.summary,
             kind: p.data["kind"] || :decision,
             affects: Enum.flat_map(p.data["affects"] || [], &uuid/1),
             source: p.source,
             org_id: p.org_id,
             project_id: p.project_id,
             made_by_id: p.owner_id,
             approved_by_id: actor.id
           })
           |> Ash.create(authorize?: false),
         :ok <- supersede(p, decision) do
      {:ok, nil}
    end
  end

  defp apply_proposal(_proposal, _actor), do: {:ok, nil}

  # The model names the decision it replaces by id, or by its statement.
  defp supersede(%{data: %{"supersedes_ref" => ref}} = p, decision) when is_binary(ref) and ref != "" do
    old =
      Decision
      |> Ash.Query.filter(org_id == ^p.org_id and status == :active and id != ^decision.id)
      |> Ash.read!(authorize?: false)
      |> Enum.find(&(&1.id == ref or String.downcase(&1.statement) == String.downcase(ref)))

    case old do
      nil ->
        :ok

      old ->
        old
        |> Ash.Changeset.for_update(:supersede, %{superseded_by_id: decision.id})
        |> Ash.update(authorize?: false)
        |> case do
          {:ok, _} -> :ok
          error -> error
        end
    end
  end

  defp supersede(_p, _decision), do: :ok

  defp uuid(ref) do
    case Ecto.UUID.cast(ref) do
      {:ok, id} -> [id]
      :error -> []
    end
  end

  ## From chat

  @doc """
  The person behind a chat account (1.11). Looks up the stored identity; for a new
  account, matches a person whose handles include the account id or display name, or
  whose name is the display name, then stores the identity (with no person if none
  matched, for an admin to link). Returns `{:ok, identity}`; `identity.person_id` may
  be nil.
  """
  def identify(org_id, platform, external_id, display_name \\ nil) do
    existing =
      Identity
      |> Ash.Query.filter(org_id == ^org_id and platform == ^platform and external_id == ^external_id)
      |> Ash.read_one!(authorize?: false)

    case existing do
      nil ->
        person = match_person(org_id, external_id, display_name)

        Identity
        |> Ash.Changeset.for_create(:create, %{
          platform: platform,
          external_id: external_id,
          display_name: display_name,
          person_id: person && person.id,
          org_id: org_id
        })
        |> Ash.create(authorize?: false, upsert?: true, upsert_identity: :unique_account)

      %{person_id: nil} ->
        person = match_person(org_id, external_id, display_name || existing.display_name)
        changes = %{display_name: display_name || existing.display_name, person_id: person && person.id}
        update_identity(existing, changes)

      _linked ->
        update_identity(existing, %{display_name: display_name || existing.display_name})
    end
  end

  defp update_identity(identity, changes) do
    if Enum.all?(changes, fn {k, v} -> Map.get(identity, k) == v end) do
      {:ok, identity}
    else
      identity |> Ash.Changeset.for_update(:update, changes) |> Ash.update(authorize?: false)
    end
  end

  defp match_person(org_id, external_id, display_name) do
    wanted = [external_id, display_name] |> Enum.reject(&is_nil/1) |> Enum.map(&String.downcase/1)
    people = Person |> Ash.Query.filter(org_id == ^org_id) |> Ash.read!(authorize?: false)

    Enum.find(people, fn p -> Enum.any?(p.handles, &(String.downcase(&1) in wanted)) end) ||
      Enum.find(people, fn p -> String.downcase(p.name) in wanted end)
  end

  @doc """
  Records a message from a mapped channel (including the consented email INBOX) as a `message.received` event (the
  Episode). Ingest (1.13, 1.15) calls this for every message it reads. `message`:

      %{platform: :discord, channel: "veriq", channel_id: "123", message_id: "456",
        author_id: "789", author: "Saish", text: "...", at: ~U[...]}

  A new message queues extraction for its channel (`Noa.Work.Extract`, 1.17).

  Returns `{:ok, event}`, `{:duplicate, event}` for a message seen before, or
  `{:error, :not_read}` when the channel is unknown or not read. DMs never get here:
  they have no channel row.
  """
  def record_message(org_id, message) do
    platform = message.platform

    channel =
      Channel
      |> Ash.Query.filter(
        org_id == ^org_id and platform == ^platform and
          (name in ^[message.channel, "#" <> message.channel] or
             (not is_nil(external_id) and external_id == ^(message[:channel_id] || "")))
      )
      |> Ash.read!(authorize?: false)
      |> List.first()

    if channel && channel.read do
      {:ok, identity} = identify(org_id, platform, to_string(message.author_id), message[:author])
      key = "#{platform}:#{message.message_id}"

      Noa.Events.append(
        org_id,
        "message.received",
        %{
          episode_id: key,
          platform: platform,
          channel: channel.name,
          channel_id: channel.id,
          project_id: if(channel.split, do: nil, else: channel.project_id),
          author: message[:author],
          person_id: identity.person_id,
          identity_id: identity.id,
          text: message.text,
          thread: message[:thread],
          at: message[:at] || DateTime.utc_now()
        },
        key: key,
        occurred_at: message[:at]
      )
      |> tap(fn
        {:ok, _event} -> Noa.Work.Extract.enqueue(org_id, channel.id)
        _duplicate -> :ok
      end)
    else
      {:error, :not_read}
    end
  end

  @doc """
  A chat message was edited (2.10). The message's text in the log becomes the new text
  (so `@noa`, briefs and extraction read what was last said) and `message.edited` is
  appended for the graph and the record. Returns `{:ok, event}` or `{:ignore, reason}`.
  """
  def edit_message(org_id, %{platform: platform, message_id: id, text: text} = message) do
    key = "#{platform}:#{id}"

    case message_event(org_id, key) do
      nil ->
        {:ignore, :unknown_message}

      %{data: %{"deleted" => true}} ->
        {:ignore, :deleted}

      %{data: %{"text" => ^text}} ->
        {:ignore, :unchanged}

      original ->
        at = message[:at] || DateTime.utc_now()

        Repo.transaction(fn ->
          original
          |> Ecto.Changeset.change(
            data: Map.merge(original.data, %{"text" => text, "edited_at" => Noa.Events.json(at)})
          )
          |> Repo.update!()

          case Noa.Events.append(org_id, "message.edited", %{episode_id: key, text: text, at: at}) do
            {:ok, event} -> event
            {:error, error} -> Repo.rollback(error)
          end
        end)
        |> tap(fn
          {:ok, _} -> Noa.Events.notify(org_id)
          _ -> :ok
        end)
    end
  end

  @doc """
  A chat message was deleted (2.10). Its text is erased from the log (the one place the
  log is rewritten, so a deleted message is really gone), the graph's episode loses its
  text, and readers skip it from then on. Tasks and decisions taken from it keep their
  own quote. Returns `{:ok, event}` or `{:ignore, reason}`.
  """
  def delete_message(org_id, platform, id) do
    key = "#{platform}:#{id}"

    case message_event(org_id, key) do
      nil ->
        {:ignore, :unknown_message}

      %{data: %{"deleted" => true}} ->
        {:ignore, :deleted}

      _original ->
        import Ecto.Query

        Repo.transaction(fn ->
          from(e in Noa.Events.Event,
            where: e.org_id == ^org_id and e.type in ["message.received", "message.edited"],
            where: fragment("?->>'episode_id' = ?", e.data, ^key),
            update: [set: [data: fragment(~s|jsonb_set(?, '{text}', 'null') \|\| '{"deleted": true}'::jsonb|, e.data)]]
          )
          |> Repo.update_all([])

          case Noa.Events.append(org_id, "message.deleted", %{episode_id: key}) do
            {:ok, event} -> event
            {:error, error} -> Repo.rollback(error)
          end
        end)
        |> tap(fn
          {:ok, _} -> Noa.Events.notify(org_id)
          _ -> :ok
        end)
    end
  end

  defp message_event(org_id, key) do
    Repo.get_by(Noa.Events.Event, org_id: org_id, key: key, type: "message.received")
  end

  ## From extraction

  @doc """
  Stores routed extraction proposals in the org's Inbox. `lines` are the window's
  lines, used to quote the source message. Project and person keys from the model are
  resolved to ids; unknown ones are left empty for the Inbox to ask about.
  """
  def save_proposals(org_id, proposals, lines) do
    by_line = Map.new(lines, &{&1.id, &1})

    projects =
      Project |> Ash.Query.filter(org_id == ^org_id) |> Ash.read!(authorize?: false) |> Map.new(&{&1.key, &1.id})

    vocab = vocabulary(org_id)
    people = Person |> Ash.Query.filter(org_id == ^org_id) |> Ash.read!(authorize?: false) |> Map.new(&{&1.key, &1.id})

    open = Task |> Ash.Query.filter(org_id == ^org_id and status != :done) |> Ash.read!(authorize?: false)
    pending = Proposal |> Ash.Query.filter(org_id == ^org_id and status == :pending) |> Ash.read!(authorize?: false)

    proposals
    # Old chat is not new work (Noa.Work.History).
    |> Enum.reject(
      &Noa.Work.History.historical?(by_line[List.first(&1.evidence)] && by_line[List.first(&1.evidence)].at)
    )
    |> Enum.reject(&already_pending?(&1, projects[&1.route.project], pending))
    |> Enum.map(fn %Extraction.Proposal{} = p ->
      first = by_line[List.first(p.evidence)]
      data = p.item |> Map.from_struct() |> Map.drop([:evidence_sequences, :confidence, :project]) |> stringify()
      owner = Extraction.Vocabulary.person(vocab, owner_name(p, first))
      project_id = projects[p.route.project]
      data = Map.merge(data, duplicate_of(p, project_id, open))

      Proposal
      |> Ash.Changeset.for_create(:create, %{
        kind: p.type,
        summary: summary(p.type, p.item),
        data:
          Map.put(data, "route", %{
            "rule" => p.route.rule,
            "suggest" => p.route.suggest,
            "candidates" => p.route.candidates
          }),
        confidence: p.confidence,
        source: first && source(first),
        org_id: org_id,
        project_id: project_id,
        owner_id: owner && people[owner.id],
        task_id: task_ref(p)
      })
      |> Ash.create!(authorize?: false)
      |> auto_apply()
    end)
  end

  ## Auto-apply (2.2)

  # Applies a proposal without waiting for the Inbox when Noa is sure enough and it is
  # safe to undo: a new task with a project and an owner (not a likely duplicate), or a
  # status change said by the task's own owner. Deadlines, scope and decisions always
  # wait for a person. It acts as the person who said it, so change records stay honest,
  # and only for people who have joined. Threshold: `config :noa, Noa.Work, auto_apply: 0.9`.
  defp auto_apply(proposal) do
    threshold = Application.get_env(:noa, __MODULE__, [])[:auto_apply]
    user = threshold && (proposal.confidence || 0) >= threshold && auto_kind?(proposal) && owner_user(proposal)

    if user do
      Repo.transaction(fn ->
        with {:ok, task} <- apply_proposal(proposal, user),
             {:ok, decided} <-
               proposal
               |> Ash.Changeset.for_update(:decide, %{
                 status: :approved,
                 task_id: task && task.id,
                 data: Map.put(proposal.data, "auto", true)
               })
               |> Ash.update(authorize?: false) do
          decided
        else
          {:error, error} -> Repo.rollback(error)
        end
      end)
      |> case do
        {:ok, decided} -> decided
        _ -> proposal
      end
    else
      proposal
    end
  end

  defp auto_kind?(%{kind: :task} = p), do: p.project_id != nil and p.owner_id != nil and is_nil(p.data["duplicate_of"])

  defp auto_kind?(%{kind: :status_change, task_id: task_id, owner_id: owner_id}) when not is_nil(task_id) do
    match?(%{owner_id: ^owner_id}, Ash.get!(Task, task_id, authorize?: false)) and owner_id != nil
  end

  defp auto_kind?(_p), do: false

  defp owner_user(%{owner_id: nil}), do: nil

  defp owner_user(%{owner_id: owner_id}) do
    case Ash.get!(Person, owner_id, authorize?: false, load: [membership: :user]) do
      %{membership: %{user: user}} when not is_nil(user) -> user
      _ -> nil
    end
  end

  @doc """
  Undoes an automatically applied proposal (2.2) and puts it back in the Inbox: a task
  it created is removed if nobody has touched it since; a status change is reverted.
  A lead or the person it is about can undo.
  """
  def undo(proposal_id, actor) do
    with {:ok, p} <- Ash.get(Proposal, proposal_id, actor: actor),
         :ok <- if(p.status == :approved and p.data["auto"], do: :ok, else: {:error, :already_decided}),
         :ok <- if(may_undo?(p, actor), do: :ok, else: {:error, :not_a_lead}) do
      Repo.transaction(fn ->
        with :ok <- unapply(p, actor),
             {:ok, back} <-
               p
               |> Ash.Changeset.for_update(:decide, %{
                 status: :pending,
                 task_id: if(p.kind == :task, do: nil, else: p.task_id),
                 data: p.data |> Map.delete("auto") |> Map.put("undone", true)
               })
               |> Ash.update(authorize?: false) do
          back
        else
          {:error, error} -> Repo.rollback(error)
        end
      end)
    end
  end

  defp may_undo?(p, actor) do
    Map.get(actor, :is_superadmin) || lead?(actor.id, p.org_id, p.project_id) ||
      match?(%{id: id} when id == actor.id, owner_user(p))
  end

  defp unapply(%{kind: :task, task_id: task_id}, _actor) when not is_nil(task_id) do
    task = Ash.get!(Task, task_id, authorize?: false)
    touched = Change |> Ash.Query.filter(task_id == ^task.id) |> Ash.exists?(authorize?: false)

    if task.status == :todo and not touched do
      task |> Ash.Changeset.for_destroy(:destroy) |> Ash.destroy(authorize?: false)
    else
      {:error, :changed_since}
    end
  end

  defp unapply(%{kind: :status_change, task_id: task_id}, actor) when not is_nil(task_id) do
    change =
      Change
      |> Ash.Query.filter(task_id == ^task_id and kind == :status and status == :applied)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.read!(authorize?: false)
      |> List.first()

    case change && revert_change(change.id, actor) do
      {:ok, _} -> :ok
      nil -> {:error, :changed_since}
      error -> error
    end
  end

  defp unapply(_p, _actor), do: :ok

  # Overlapping windows can find the same task twice; keep the first proposal (2.3).
  defp already_pending?(%{type: :task, item: %{title: title}}, project_id, pending) do
    Enum.any?(
      pending,
      &(&1.kind == :task and &1.project_id == project_id and Noa.Work.Similar.same?(&1.summary, title))
    )
  end

  defp already_pending?(_p, _project_id, _pending), do: false

  # A new task that matches an open one in the same project is flagged for the Inbox (2.3).
  defp duplicate_of(%{type: :task, item: %{title: title}}, project_id, open) when not is_nil(project_id) do
    case Noa.Work.Similar.find(title, Enum.filter(open, &(&1.project_id == project_id))) do
      nil -> %{}
      task -> %{"duplicate_of" => %{"task_id" => task.id, "title" => task.title}}
    end
  end

  defp duplicate_of(_p, _project_id, _open), do: %{}

  # A task belongs to whoever will do it. The model names them or says it can't tell;
  # the message's author is not a fallback: asking Soha for work doesn't make it yours.
  # Unowned tasks go to triage, which suggests an owner from the graph.
  defp owner_name(%{type: :task, item: %{owner: owner}}, _first), do: owner
  defp owner_name(_p, %{author: author}), do: author
  defp owner_name(_p, _), do: nil

  defp task_ref(%{item: %{task_ref: ref}}) when is_binary(ref) do
    case Ecto.UUID.cast(ref) do
      {:ok, id} -> id
      :error -> nil
    end
  end

  defp task_ref(_), do: nil

  defp summary(:task, i), do: i.title
  defp summary(:status_change, i), do: "#{i.task_ref} → #{i.status}"
  defp summary(:deadline_change, i), do: "#{i.task_ref} due #{i.new_due}"
  defp summary(:decision, i), do: i.statement
  defp summary(:scope_change, i), do: i.summary

  defp source(line) do
    %{
      "channel" => line.channel,
      "author" => line.author,
      "at" => line.at,
      "quote" => line.body,
      "episode_id" => line.id
    }
  end

  defp stringify(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)

  ## Vocabulary for extraction

  @doc "What extraction may answer with for this org, built from the database."
  def vocabulary(org_id) do
    projects =
      Project |> Ash.Query.filter(org_id == ^org_id) |> Ash.Query.load(:aliases) |> Ash.read!(authorize?: false)

    people = Person |> Ash.Query.filter(org_id == ^org_id) |> Ash.read!(authorize?: false)
    project_key = Map.new(projects, &{&1.id, &1.key})
    person_key = Map.new(people, &{&1.id, &1.key})

    allocations =
      Allocation |> Ash.Query.for_read(:current) |> Ash.Query.filter(org_id == ^org_id) |> Ash.read!(authorize?: false)

    channels = Channel |> Ash.Query.filter(org_id == ^org_id) |> Ash.read!(authorize?: false)
    open = Task |> Ash.Query.filter(org_id == ^org_id and status != :done) |> Ash.read!(authorize?: false)

    %Extraction.Vocabulary{
      projects:
        Enum.map(
          projects,
          &%{id: &1.key, name: &1.name, about: &1.about, aliases: Enum.map(&1.aliases, fn a -> to_string(a.alias) end)}
        ),
      people: Enum.map(people, &%{id: &1.key, name: &1.name, title: &1.title, handles: &1.handles}),
      channels:
        Map.new(channels, fn c ->
          route =
            cond do
              not c.read -> nil
              c.split -> :split
              true -> project_key[c.project_id]
            end

          {c.name, route}
        end),
      works_on: allocations |> Enum.group_by(&person_key[&1.person_id], &project_key[&1.project_id]),
      open_tasks:
        Enum.map(
          open,
          &%{id: &1.id, project: project_key[&1.project_id], title: &1.title, owner: person_key[&1.owner_id]}
        )
    }
  end

  ## Event log

  @doc """
  Appends a `.saved` event for every row in the org that has none yet: rows written
  before the event log existed (1.8). Safe to run again. Returns how many it appended.
  """
  def backfill_events(org_id) do
    logged = MapSet.new(Noa.Repo.all(from(e in Noa.Events.Event, where: e.org_id == ^org_id, select: e.subject_id)))

    # Parents before children, so the replay builds nodes before edges point at them.
    [{Person, "person"}, {Project, "project"}, {ProjectAlias, "alias"}, {Channel, "channel"}, {Identity, "identity"}]
    |> Kernel.++([
      {Allocation, "allocation"},
      {Task, "task"},
      {Change, "change"},
      {Decision, "decision"},
      {Proposal, "proposal"}
    ])
    |> Enum.flat_map(fn {resource, name} ->
      resource
      |> Ash.Query.filter(org_id == ^org_id)
      |> Ash.read!(authorize?: false)
      |> Enum.reject(&MapSet.member?(logged, &1.id))
      |> Enum.map(&Noa.Events.append(org_id, "#{name}.saved", Noa.Events.Record.snapshot(&1), subject_id: &1.id))
    end)
    |> length()
  end

  ## Seed

  @doc """
  Loads an org seed (the format of docs/seeds/nyi.json) into the org: people,
  projects, aliases, channels and allocations. Safe to run again: rows are matched by
  key and updated. People are linked to members whose email or name matches.
  """
  defdelegate load_seed(org_id, seed), to: Noa.Work.Seed, as: :load

  @doc "Links people with no account to the org's members, by email, then by name."
  defdelegate link_people(org_id), to: Noa.Work.Seed
end
