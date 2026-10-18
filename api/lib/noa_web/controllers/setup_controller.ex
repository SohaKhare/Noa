defmodule NoaWeb.SetupController do
  @moduledoc "Workspace setup from the web app (1.18): projects, people, allocations, channels, org map import."
  use NoaWeb, :controller

  alias Noa.Work.{Person, Project, Setup}
  alias NoaWeb.Payload

  def create_project(conn, %{"org_id" => org_id} = params) do
    attrs = take(params, ~w(key name about repo lead_id))

    with :ok <- person_in_org(attrs[:lead_id], org_id, conn),
         {:ok, project} <- Setup.create_project(org_id, attrs, actor(conn)) do
      conn |> put_status(201) |> json(%{project: Payload.project(project)})
    end
  end

  def update_project(conn, %{"org_id" => org_id, "id" => id} = params) do
    attrs = take(params, ~w(name about repo status lead_id))

    with :ok <- in_org(Project, id, org_id, conn),
         :ok <- person_in_org(attrs[:lead_id], org_id, conn),
         {:ok, project} <- Setup.update_project(id, attrs, actor(conn)) do
      json(conn, %{project: Payload.project(project)})
    end
  end

  def create_person(conn, %{"org_id" => org_id} = params) do
    with {:ok, person} <- Setup.create_person(org_id, take(params, ~w(name title email handles)), actor(conn)) do
      conn |> put_status(201) |> json(%{person: Payload.person(person)})
    end
  end

  def update_person(conn, %{"org_id" => org_id, "id" => id} = params) do
    with :ok <- in_org(Person, id, org_id, conn),
         {:ok, person} <- Setup.update_person(id, take(params, ~w(name title email handles)), actor(conn)) do
      json(conn, %{person: Payload.person(person)})
    end
  end

  def add_members(conn, %{"org_id" => org_id}) do
    with {:ok, added} <- Setup.add_members(org_id, actor(conn)), do: json(conn, %{added: added})
  end

  def set_allocation(conn, %{"org_id" => org_id, "person_id" => person_id, "project_id" => project_id} = params) do
    percent =
      params["percent"]
      |> to_string()
      |> Integer.parse()
      |> then(fn
        {n, _} -> n
        :error -> 100
      end)

    with :ok <- in_org(Person, person_id, org_id, conn),
         :ok <- in_org(Project, project_id, org_id, conn),
         {:ok, allocation} <-
           Setup.set_allocation(
             org_id,
             %{person_id: person_id, project_id: project_id, percent: percent, role: params["role"]},
             actor(conn)
           ) do
      json(conn, %{allocation: allocation && Payload.allocation(allocation)})
    end
  end

  def create_channel(conn, %{"org_id" => org_id} = params) do
    attrs =
      params
      |> take(~w(name external_id project_id split read backfill))
      |> Map.put(
        :platform,
        if(params["platform"] in ~w(discord slack whatsapp meet),
          do: String.to_existing_atom(params["platform"]),
          else: :discord
        )
      )

    with :ok <- if(attrs[:project_id], do: in_org(Project, attrs[:project_id], org_id, conn), else: :ok),
         {:ok, channel} <- Setup.create_channel(org_id, attrs, actor(conn)) do
      conn |> put_status(201) |> json(%{channel: Payload.channel(channel)})
    end
  end

  @doc "Loads a mapped Discord channel's recent history in the background."
  def backfill_channel(conn, %{"org_id" => org_id, "id" => id}) do
    with {:ok, state} <- Setup.backfill_channel(org_id, id, actor(conn)), do: json(conn, %{backfill: state})
  end

  def delete_channel(conn, %{"org_id" => org_id, "id" => id}) do
    with {:ok, _} <-
           (case Setup.delete_channel(org_id, id, actor(conn)) do
              :ok -> {:ok, nil}
              other -> other
            end),
         do: json(conn, %{ok: true})
  end

  def discord_channels(conn, %{"org_id" => org_id}) do
    with {:ok, result} <- Setup.discord_channels(org_id, actor(conn)), do: json(conn, result)
  end

  def slack_channels(conn, %{"org_id" => org_id}) do
    with {:ok, result} <- Setup.slack_channels(org_id, actor(conn)), do: json(conn, result)
  end

  def import(conn, %{"org_id" => org_id} = params) do
    with {:ok, counts} <- Setup.import(org_id, params["seed"], actor(conn)), do: json(conn, %{loaded: counts})
  end

  defp actor(conn), do: conn.assigns.current_user

  defp take(params, keys) do
    params
    |> Map.take(keys)
    |> Map.new(fn {k, v} -> {String.to_existing_atom(k), if(v == "", do: nil, else: v)} end)
  end

  defp person_in_org(nil, _org_id, _conn), do: :ok
  defp person_in_org(id, org_id, conn), do: in_org(Person, id, org_id, conn)

  defp in_org(resource, id, org_id, conn) do
    case Ash.get(resource, id, actor: actor(conn)) do
      {:ok, %{org_id: ^org_id}} -> :ok
      _ -> {:error, :not_found}
    end
  end
end
