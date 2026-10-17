defmodule NoaWeb.WorkController do
  @moduledoc "Projects, people, tasks and the Inbox for one workspace (1.24). Ash policies decide who may do what."
  use NoaWeb, :controller

  alias Noa.Work
  alias Noa.Work.{Change, Channel, Person, Project, Proposal, Task}

  @doc "Who and what is in the workspace: people, projects, channels, and the signed-in person."
  def directory(conn, %{"org_id" => org_id}) do
    actor = conn.assigns.current_user

    with {:ok, org} <- Noa.Orgs.get_org(org_id, actor),
         {:ok, people} <- Work.people(org.id, actor),
         {:ok, projects} <- Work.projects(org.id, actor),
         {:ok, channels} <- Work.channels(org.id, actor) do
      me = Work.person_for(actor, org.id)

      json(conn, %{
        me: me && me.id,
        people: Enum.map(people, &Payload.person/1),
        projects: Enum.map(projects, &Payload.project/1),
        channels: Enum.map(channels, &Payload.channel/1)
      })
    end
  end

  def tasks(conn, %{"org_id" => org_id} = params) do
    filters = [project_id: params["project_id"], owner_id: params["owner_id"], open: params["open"] == "true"]

    with {:ok, tasks} <- Work.tasks(org_id, conn.assigns.current_user, filters) do
      json(conn, %{tasks: Enum.map(tasks, &Payload.task/1)})
    end
  end

  def create_task(conn, %{"org_id" => org_id} = params) do
    actor = conn.assigns.current_user
    attrs = task_attrs(params)

    with :ok <- refs_in_org(attrs, org_id, actor),
         {:ok, task} <- Work.create_task(org_id, attrs, actor) do
      conn |> put_status(201) |> json(%{task: Payload.task(task)})
    end
  end

  def update_task(conn, %{"org_id" => org_id, "id" => id} = params) do
    actor = conn.assigns.current_user
    attrs = task_attrs(params)

    with :ok <- in_org(Task, id, org_id, actor),
         :ok <- refs_in_org(attrs, org_id, actor),
         {:ok, task} <- Work.update_task(id, Map.put(attrs, :reason, params["reason"]), actor),
         {:ok, pending} <- Work.changes(org_id, actor, task_id: task.id, status: :pending) do
      json(conn, %{task: Payload.task(task), pending_changes: Enum.map(pending, &Payload.change/1)})
    end
  end

  @doc "Change records (2.19). Query: `task_id`, `project_id`, `status` (applied, pending, rejected, reverted)."
  def changes(conn, %{"org_id" => org_id} = params) do
    filters = [
      task_id: params["task_id"],
      project_id: params["project_id"],
      status:
        if(params["status"] in ~w(applied pending rejected reverted), do: String.to_existing_atom(params["status"]))
    ]

    with {:ok, changes} <- Work.changes(org_id, conn.assigns.current_user, filters) do
      json(conn, %{changes: Enum.map(changes, &Payload.change/1)})
    end
  end

  def approve_change(conn, params), do: decide_change(conn, params, &Work.approve_change/2)
  def reject_change(conn, params), do: decide_change(conn, params, &Work.reject_change/2)
  def revert_change(conn, params), do: decide_change(conn, params, &Work.revert_change/2)

  defp decide_change(conn, %{"org_id" => org_id, "id" => id}, fun) do
    actor = conn.assigns.current_user

    with :ok <- in_org(Change, id, org_id, actor),
         {:ok, change} <- fun.(id, actor) do
      json(conn, %{change: Payload.change(change)})
    end
  end

  @doc "Changes where a channel's messages go: `project_id`, `split`, `read`."
  def update_channel(conn, %{"org_id" => org_id, "id" => id} = params) do
    actor = conn.assigns.current_user
    attrs = params |> Map.take(~w(project_id split read)) |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)

    with :ok <- in_org(Channel, id, org_id, actor),
         :ok <- refs_in_org(attrs, org_id, actor),
         {:ok, channel} <- Work.update_channel(id, attrs, actor) do
      json(conn, %{channel: Payload.channel(channel)})
    end
  end

  @doc "Decisions, newest first. Query: `project_id`, `since` (ISO 8601), `status` (active, superseded)."
  def decisions(conn, %{"org_id" => org_id} = params) do
    filters = [
      project_id: params["project_id"],
      since: with({:ok, at, _} <- DateTime.from_iso8601(params["since"] || ""), do: at, else: (_ -> nil)),
      status: if(params["status"] in ~w(active superseded), do: String.to_existing_atom(params["status"]))
    ]

    with {:ok, decisions} <- Work.decisions(org_id, conn.assigns.current_user, filters) do
      json(conn, %{decisions: Enum.map(decisions, &Payload.decision/1)})
    end
  end

  @doc "`@noa` (2.5): an answer with citations, from what the signed-in person can see."
  def ask(conn, %{"org_id" => org_id, "question" => question}) when is_binary(question) and question != "" do
    with {:ok, result} <- Noa.Agent.ask(org_id, String.slice(question, 0, 500), conn.assigns.current_user) do
      json(conn, result)
    end
  end

  @doc "What moving someone would do (3.1): their open tasks in the old project, with suggested new owners."
  def plan_shift(conn, %{"org_id" => org_id, "person_id" => person_id} = params) do
    actor = conn.assigns.current_user
    from = blank(params["from_project_id"])

    with :ok <- in_org(Person, person_id, org_id, actor),
         :ok <- refs_in_org(%{project_id: from}, org_id, actor),
         {:ok, tasks} <- Work.plan_shift(org_id, %{person_id: person_id, from_project_id: from}, actor) do
      json(conn, %{tasks: tasks})
    end
  end

  @doc "Moves someone (3.1). Body: person_id, from_project_id, to_project_id (empty is the bench), percent, starts_on, handover, note."
  def create_shift(conn, %{"org_id" => org_id, "person_id" => person_id} = params) do
    actor = conn.assigns.current_user
    from = blank(params["from_project_id"])
    to = blank(params["to_project_id"])
    handover = Map.new(params["handover"] || %{}, fn {task, owner} -> {task, blank(owner)} end)

    with :ok <- in_org(Person, person_id, org_id, actor),
         :ok <- refs_in_org(%{project_id: from}, org_id, actor),
         :ok <- refs_in_org(%{project_id: to}, org_id, actor),
         :ok <-
           Enum.reduce_while(handover, :ok, fn {task, owner}, :ok ->
             case {in_org(Task, task, org_id, actor), refs_in_org(%{owner_id: owner}, org_id, actor)} do
               {:ok, :ok} -> {:cont, :ok}
               {:ok, error} -> {:halt, error}
               {error, _} -> {:halt, error}
             end
           end),
         {:ok, starts_on} <- date(params["starts_on"]),
         {:ok, shift} <-
           Work.shift(
             org_id,
             %{
               person_id: person_id,
               from_project_id: from,
               to_project_id: to,
               percent: params["percent"],
               starts_on: starts_on,
               handover: handover,
               note: params["note"]
             },
             actor
           ) do
      conn |> put_status(201) |> json(%{shift: Payload.shift(shift)})
    end
  end

  def shifts(conn, %{"org_id" => org_id} = params) do
    with {:ok, shifts} <- Work.shifts(org_id, conn.assigns.current_user, person_id: params["person_id"]) do
      json(conn, %{shifts: Enum.map(shifts, &Payload.shift/1)})
    end
  end

  defp blank(""), do: nil
  defp blank(v), do: v

  defp date(nil), do: {:ok, nil}
  defp date(""), do: {:ok, nil}

  defp date(iso) do
    case Date.from_iso8601(iso) do
      {:ok, d} -> {:ok, d}
      _ -> {:error, :not_found}
    end
  end

  @doc "KT brief (3.2) for a project; `person_id` adds that person's tasks and leaves them out of people to meet."
  def brief(conn, %{"org_id" => org_id, "project_id" => project_id} = params) do
    actor = conn.assigns.current_user
    person_id = blank(params["person_id"])

    with :ok <- in_org(Project, project_id, org_id, actor),
         :ok <- refs_in_org(%{owner_id: person_id}, org_id, actor),
         {:ok, brief} <- Work.brief(org_id, project_id, actor, person_id) do
      json(conn, brief)
    end
  end

  @doc "Who knows a project (3.3), and where one person holds most of the knowledge. Empty when the graph is down."
  def experts(conn, %{"org_id" => org_id} = params) do
    project_id = blank(params["project_id"])

    with :ok <- if(project_id, do: in_org(Project, project_id, org_id, conn.assigns.current_user), else: :ok) do
      graph =
        with {:ok, experts} <- if(project_id, do: Noa.Graph.Experts.experts(org_id, project_id), else: {:ok, []}),
             {:ok, key} <- Noa.Graph.Experts.key_people(org_id),
             {:ok, risks} <- Noa.Graph.Experts.bus_factor(org_id) do
          %{experts: experts, key_people: key, bus_factor: risks, graph: true}
        else
          _ -> %{experts: [], key_people: [], bus_factor: [], graph: false}
        end

      json(conn, graph)
    end
  end

  def proposals(conn, %{"org_id" => org_id} = params) do
    status = if params["status"] in ~w(approved rejected), do: String.to_existing_atom(params["status"]), else: :pending

    with {:ok, proposals} <- Work.proposals(org_id, conn.assigns.current_user, status) do
      json(conn, %{proposals: Enum.map(proposals, &Payload.proposal/1)})
    end
  end

  def approve(conn, %{"org_id" => org_id, "id" => id} = params) do
    actor = conn.assigns.current_user

    edits =
      params
      |> Map.take(["summary", "project_id", "owner_id", "data"])
      |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)
      |> Map.update(:data, %{}, &Map.take(&1 || %{}, ~w(title detail due new_due status)))

    with :ok <- in_org(Proposal, id, org_id, actor),
         :ok <- refs_in_org(edits, org_id, actor),
         {:ok, proposal} <- Work.approve(id, edits, actor) do
      json(conn, %{proposal: Payload.proposal(proposal), task: proposal.task && Payload.task(proposal.task)})
    end
  end

  def reject(conn, %{"org_id" => org_id, "id" => id}) do
    actor = conn.assigns.current_user

    with :ok <- in_org(Proposal, id, org_id, actor),
         {:ok, proposal} <- Work.reject(id, actor) do
      json(conn, %{proposal: Payload.proposal(proposal)})
    end
  end

  defp task_attrs(params) do
    params
    |> Map.take(~w(title detail status due_on blocked_reason owner_id project_id))
    |> Map.new(fn
      {"status", v} ->
        {:status, if(v in Enum.map(Task.statuses(), &Atom.to_string/1), do: String.to_existing_atom(v), else: v)}

      {k, v} ->
        {String.to_existing_atom(k), v}
    end)
  end

  # Ids in the path, and project or owner ids in the body, must belong to the org in the path.
  defp in_org(resource, id, org_id, actor) do
    case Ash.get(resource, id, actor: actor) do
      {:ok, %{org_id: ^org_id}} -> :ok
      {:ok, _} -> {:error, :not_found}
      error -> error
    end
  end

  defp refs_in_org(attrs, org_id, actor) do
    [project_id: Project, owner_id: Person]
    |> Enum.reduce_while(:ok, fn {key, resource}, :ok ->
      case Map.get(attrs, key) do
        nil ->
          {:cont, :ok}

        id ->
          case in_org(resource, id, org_id, actor),
            do: (
              :ok -> {:cont, :ok}
              error -> {:halt, error}
            )
      end
    end)
  end
end
