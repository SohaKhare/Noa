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
    attrs = normalize_repo(attrs)

    attrs = Map.put_new_lazy(attrs, :key, fn -> unique_key(Project, org_id, attrs[:name]) end)

    Project
    |> Ash.Changeset.for_create(:create, Map.put(attrs, :org_id, org_id), actor: actor)
    |> Ash.create()
  end

  def update_project(id, attrs, actor) do
    with {:ok, project} <- Ash.get(Project, id, actor: actor) do
      project |> Ash.Changeset.for_update(:update, normalize_repo(attrs), actor: actor) |> Ash.update()
    end
  end

  # "https://github.com/Owner/name.git" and "Owner/name" both become "Owner/name", the
  # form GitHub webhooks name the repository in.
  defp normalize_repo(%{repo: repo} = attrs) when is_binary(repo) do
    clean =
      repo
      |> String.trim()
      |> String.replace(~r{^(https?://)?(www\.)?github\.com/}i, "")
      |> String.replace(~r{\.git$}, "")
      |> String.trim("/")

    %{attrs | repo: if(clean == "", do: nil, else: clean)}
  end

  defp normalize_repo(attrs), do: attrs

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
    {backfill, attrs} = Map.pop(attrs, :backfill, true)

    with {:ok, channel} <- insert_channel(org_id, attrs, actor) do
      # A Discord channel with its id: load its recent history in the background, unless asked not to.
      if backfill not in [false, "false"], do: queue_backfill(channel)
      {:ok, channel}
    end
  end

  @doc "Loads a mapped Discord channel's recent history again (Settings → Channels). Org admins."
  def backfill_channel(org_id, channel_id, actor) do
    with :ok <- role(org_id, actor, [:org_admin]),
         {:ok, %{org_id: ^org_id} = channel} <- Ash.get(Channel, channel_id, authorize?: false) do
      cond do
        not Noa.Ingest.Discord.enabled?() -> {:error, :discord_off}
        channel.platform != :discord or is_nil(channel.external_id) -> {:error, :not_backfillable}
        not channel.read -> {:error, :not_backfillable}
        true -> {:ok, queue_backfill(channel)}
      end
    else
      {:ok, _other_org} -> {:error, :not_found}
      error -> error
    end
  end

  defp queue_backfill(%{platform: :discord, external_id: id, read: true, org_id: org_id}) when is_binary(id) do
    if Noa.Ingest.Discord.enabled?() do
      case %{org_id: org_id, channel_id: id} |> Noa.Ingest.Discord.Backfill.new() |> Oban.insert() do
        {:ok, %{conflict?: true}} -> :already_queued
        {:ok, _} -> :queued
        _ -> :failed
      end
    else
      :discord_off
    end
  end

  defp queue_backfill(_channel), do: :skipped

  @doc "Stops reading a channel and removes its mapping. Messages already recorded stay. Org admins."
  def delete_channel(org_id, channel_id, actor) do
    with :ok <- role(org_id, actor, [:org_admin]),
         {:ok, %{org_id: ^org_id} = channel} <- Ash.get(Channel, channel_id, authorize?: false) do
      Ash.destroy(channel, actor: actor)
    else
      {:ok, _other_org} -> {:error, :not_found}
      error -> error
    end
  end

  defp insert_channel(org_id, attrs, actor) do
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
      mapped = Enum.filter(mapped, &(&1.platform == :discord))
      counts = message_counts(org_id)
      admin? = role(org_id, actor, [:org_admin]) == :ok

      case Noa.Ingest.Discord.guild_channels(org_id) do
        {:ok, channels} ->
          rows =
            Enum.map(channels, fn c ->
              noa =
                Enum.find(mapped, &(&1.external_id == c.id)) ||
                  Enum.find(mapped, &(is_nil(&1.external_id) and &1.name in [c.name, "#" <> c.name]))

              # A channel matched by name gets its Discord id, so its history can be loaded.
              noa = if admin? && noa && is_nil(noa.external_id), do: attach_id(noa, c.id), else: noa

              Map.merge(c, %{
                mapped: noa != nil,
                channel_id: noa && noa.id,
                project_id: noa && noa.project_id,
                split: (noa && noa.split) || false,
                read: (noa && noa.read) || false,
                messages: (noa && counts[noa.id]) || 0
              })
            end)

          in_server = MapSet.new(channels, & &1.id)

          # Mappings that point at no channel in the server (old or mistyped), to clean up.
          stale =
            mapped
            |> Enum.reject(&(&1.external_id in in_server))
            |> Enum.reject(fn m -> Enum.any?(rows, &(&1.channel_id == m.id)) end)
            |> Enum.map(&%{channel_id: &1.id, name: &1.name, messages: counts[&1.id] || 0})

          {:ok, %{connected: true, channels: rows, stale: stale}}

        _ ->
          {:ok, %{connected: false, channels: [], stale: []}}
      end
    end
  end

  defp attach_id(channel, discord_id) do
    case channel |> Ash.Changeset.for_update(:update, %{external_id: discord_id}) |> Ash.update(authorize?: false) do
      {:ok, updated} -> updated
      _ -> channel
    end
  end

  # Messages recorded per Noa channel id (deleted ones excluded).
  defp message_counts(org_id) do
    import Ecto.Query

    from(e in Noa.Events.Event,
      where: e.org_id == ^org_id and e.type == "message.received",
      where: fragment("coalesce(?->>'deleted', '') = ''", e.data),
      group_by: fragment("?->>'channel_id'", e.data),
      select: {fragment("?->>'channel_id'", e.data), count(e.id)}
    )
    |> Noa.Repo.all()
    |> Map.new()
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
