defmodule NoaWeb.WorkController do
  @moduledoc "Projects, people, tasks and the Inbox for one workspace (1.24). Ash policies decide who may do what."
  use NoaWeb, :controller

  alias Noa.Work
  alias Noa.Work.{Person, Project, Proposal, Task}

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
         {:ok, task} <- Work.update_task(id, attrs, actor) do
      json(conn, %{task: Payload.task(task)})
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
