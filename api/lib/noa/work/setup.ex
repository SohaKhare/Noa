defmodule Noa.Work.Setup do
  @moduledoc """
  Setting up a workspace from the web app (1.18): projects, the people in the org map,
  who works where (allocations), which channels Noa reads, or a whole org map at once.
  Writes go through the resources' policies as the actor (org admins and PMs; channels
  are admins only), so each one lands in the event log and the graph like any other.
  """
  require Ash.Query

  alias Noa.Orgs.Membership
  alias Noa.Work
  alias Noa.Work.{Allocation, Channel, Person, Project, Seed}

  ## Projects

  def create_project(org_id, attrs, actor) do
    with :ok <- role(org_id, actor, [:org_admin, :pm]), do: do_create_project(org_id, attrs, actor)
  end

  defp do_create_project(org_id, attrs, actor) do
    attrs = Map.put_new_lazy(attrs, :key, fn -> unique_key(Project, org_id, attrs[:name]) end)

    Project
    |> Ash.Changeset.for_create(:create, Map.put(attrs, :org_id, org_id), actor: actor)
    |> Ash.create()
  end

  def update_project(id, attrs, actor) do
    with {:ok, project} <- Ash.get(Project, id, actor: actor) do
      project |> Ash.Changeset.for_update(:update, attrs, actor: actor) |> Ash.update()
    end
  end

  ## People

  @doc "Adds someone to the org map (they don't need an account). Links them to a member with the same email or name."
  def create_person(org_id, attrs, actor) do
    with :ok <- role(org_id, actor, [:org_admin, :pm]), do: do_create_person(org_id, attrs, actor)
  end

  defp do_create_person(org_id, attrs, actor) do
    attrs = Map.put_new_lazy(attrs, :key, fn -> unique_key(Person, org_id, attrs[:name]) end)

    with {:ok, person} <-
           Person
           |> Ash.Changeset.for_create(:create, Map.put(attrs, :org_id, org_id), actor: actor)
           |> Ash.create() do
      Seed.link_people(org_id)
      {:ok, Ash.get!(Person, person.id, authorize?: false)}
    end
  end

  def update_person(id, attrs, actor) do
    with {:ok, person} <- Ash.get(Person, id, actor: actor) do
      person |> Ash.Changeset.for_update(:update, attrs, actor: actor) |> Ash.update()
    end
  end

  @doc "Puts every member who isn't in the org map yet into it. Returns `{:ok, added}`."
  def add_members(org_id, actor) do
    with :ok <- admin(org_id, actor) do
      Seed.link_people(org_id)

      linked =
        Person
        |> Ash.Query.filter(org_id == ^org_id and not is_nil(membership_id))
        |> Ash.read!(authorize?: false)
        |> MapSet.new(& &1.membership_id)

      Membership
      |> Ash.Query.filter(org_id == ^org_id)
      |> Ash.Query.load(:user)
      |> Ash.read!(authorize?: false)
      |> Enum.reject(&MapSet.member?(linked, &1.id))
      |> Enum.reduce_while({:ok, 0}, fn m, {:ok, n} ->
        name = m.user.name || m.user.email |> to_string() |> String.split("@") |> hd()

        case Person
             |> Ash.Changeset.for_create(
               :create,
               %{
                 key: unique_key(Person, org_id, name),
                 name: name,
                 title: m.title,
                 email: to_string(m.user.email),
                 org_id: org_id,
                 membership_id: m.id
               },
               actor: actor
             )
             |> Ash.create() do
          {:ok, _} -> {:cont, {:ok, n + 1}}
          error -> {:halt, error}
        end
      end)
    end
  end

  ## Allocations

  @doc """
  Sets how much of someone's time goes to a project. Updates their current allocation
  there, or starts one; `percent: 0` ends it today.
  """
  def set_allocation(org_id, attrs, actor) do
    with :ok <- role(org_id, actor, [:org_admin, :pm]), do: do_set_allocation(org_id, attrs, actor)
  end

  defp do_set_allocation(org_id, %{person_id: person_id, project_id: project_id} = attrs, actor) do
    today = Date.utc_today()
    percent = attrs[:percent] || 100

    current =
      Allocation
      |> Ash.Query.filter(
        org_id == ^org_id and person_id == ^person_id and project_id == ^project_id and
          (is_nil(ends_on) or ends_on >= ^today)
      )
      |> Ash.read!(authorize?: false)
      |> List.first()

    cond do
      current && percent == 0 ->
        current |> Ash.Changeset.for_update(:update, %{ends_on: today}, actor: actor) |> Ash.update()

      current ->
        current
        |> Ash.Changeset.for_update(:update, %{percent: percent, role: attrs[:role] || current.role}, actor: actor)
        |> Ash.update()

      percent == 0 ->
        {:ok, nil}

      true ->
        Allocation
        |> Ash.Changeset.for_create(
          :create,
          %{percent: percent, role: attrs[:role], org_id: org_id, person_id: person_id, project_id: project_id},
          actor: actor
        )
        |> Ash.create()
    end
  end

  ## Channels

  @doc "Starts reading a channel. `external_id` is the platform's channel id (Discord's, for example)."
  def create_channel(org_id, attrs, actor) do
    with :ok <- role(org_id, actor, [:org_admin]), do: do_create_channel(org_id, attrs, actor)
  end

  defp do_create_channel(org_id, attrs, actor) do
    Channel
    |> Ash.Changeset.for_create(:create, Map.merge(%{platform: :discord, read: true}, Map.put(attrs, :org_id, org_id)),
      actor: actor
    )
    |> Ash.create()
  end

  @doc """
  Text channels in the connected Discord server, with whether Noa reads each one yet:
  `{:ok, %{connected: bool, channels: [%{id, name, mapped}]}}`.
  """
  def discord_channels(org_id, actor) do
    with {:ok, mapped} <- Work.channels(org_id, actor) do
      mapped = mapped |> Enum.filter(&(&1.platform == :discord)) |> Enum.flat_map(&[&1.external_id, &1.name])

      case Noa.Ingest.Discord.guild_channels() do
        {:ok, channels} ->
          {:ok,
           %{
             connected: true,
             channels:
               Enum.map(
                 channels,
                 &Map.put(&1, :mapped, &1.id in mapped or &1.name in mapped or ("#" <> &1.name) in mapped)
               )
           }}

        _ ->
          {:ok, %{connected: false, channels: []}}
      end
    end
  end

  ## A whole org map

  @doc "Loads an org map (the shape of docs/seeds/nyi.json) into the workspace. Org admins only."
  def import(org_id, seed, actor) do
    with :ok <- admin(org_id, actor) do
      if is_map(seed), do: Work.load_seed(org_id, seed), else: {:error, :invalid_org_map}
    end
  end

  defp admin(org_id, actor), do: role(org_id, actor, [:org_admin])

  # Checked before validation, so a member gets 403 rather than a list of missing fields.
  defp role(org_id, actor, roles) do
    if Map.get(actor, :is_superadmin) or Noa.Orgs.role(actor.id, org_id) in roles,
      do: :ok,
      else: {:error, %Ash.Error.Forbidden{}}
  end

  # "Video Break" -> "video-break", then "video-break-2" if that's taken.
  defp unique_key(resource, org_id, name) do
    base =
      (name || "item")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")
      |> then(&if(&1 == "", do: "item", else: &1))

    taken = resource |> Ash.Query.filter(org_id == ^org_id) |> Ash.read!(authorize?: false) |> MapSet.new(& &1.key)

    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(&if(&1 == 1, do: base, else: "#{base}-#{&1}"))
    |> Enum.find(&(not MapSet.member?(taken, &1)))
  end
end
