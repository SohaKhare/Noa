defmodule Noa.Ingest.Discord.Accounts do
  @moduledoc "Verified Discord account bindings. Display names and inferred identities never authenticate commands."
  require Ash.Query
  alias Noa.{Repo, Work}

  @doc "Authentication boundary: resolve only the exact, verified account marker and a current membership."
  def actor(org_id, discord_id) do
    with [person] <- verified_people(discord_id) |> Enum.filter(&(&1.org_id == org_id)),
         true <- not is_nil(Noa.Connectors.guild_for(org_id)),
         {:ok, %{org_id: ^org_id, user_id: user_id}} <- membership(person) do
      Ash.get(Noa.Accounts.User, user_id, actor: %{id: user_id})
    else
      _ -> {:error, :discord_not_linked}
    end
  end

  @doc "Workspace ids only, for authenticating an explicit question sent directly to Noa."
  def workspaces(discord_id) do
    verified_people(discord_id)
    |> Enum.filter(fn person ->
      match?({:ok, %{org_id: org_id}} when org_id == person.org_id, membership(person)) and
        not is_nil(Noa.Connectors.guild_for(person.org_id))
    end)
    |> Enum.map(& &1.org_id)
    |> Enum.uniq()
  end

  def current(org_id, actor) do
    with {:ok, people} <- Work.people(org_id, actor) do
      person = Enum.find(people, &(&1.membership && &1.membership.user_id == actor.id))
      {:ok, person && discord_id(person)}
    end
  end

  def discord_id(person) do
    Enum.find_value(person.handles, fn
      "discord:" <> id -> if Regex.match?(~r/^\d{15,22}$/, id), do: id
      _ -> nil
    end)
  end

  @doc "Called only after a one-time gateway challenge is consumed by the signed-in member."
  def link(org_id, discord_id, actor) do
    transaction(org_id, fn ->
      with {:ok, people} <- Work.people(org_id, actor),
           person when not is_nil(person) <- Enum.find(people, &(&1.membership && &1.membership.user_id == actor.id)),
           false <- Enum.any?(people, &(&1.id != person.id and marker(discord_id) in &1.handles)) do
        handles = clean_handles(person) ++ [discord_id, marker(discord_id)]

        with {:ok, person} <- update(person, handles, actor),
             {:ok, _} <- identity(org_id, discord_id, person.id, actor) do
          {:ok, discord_id}
        end
      else
        true -> {:error, :discord_already_linked}
        nil -> {:error, :person_not_found}
        error -> error
      end
    end)
  end

  def unlink(org_id, actor) do
    transaction(org_id, fn ->
      with {:ok, people} <- Work.people(org_id, actor),
           person when not is_nil(person) <- Enum.find(people, &(&1.membership && &1.membership.user_id == actor.id)),
           {:ok, _} <- update(person, clean_handles(person), actor) do
        {:ok, nil}
      else
        nil -> {:error, :person_not_found}
        error -> error
      end
    end)
  end

  defp update(person, handles, actor) do
    person
    |> Ash.Changeset.for_update(:discord_link, %{handles: Enum.uniq(handles)}, actor: actor)
    |> Ash.update()
  end

  defp clean_handles(person) do
    ids = for "discord:" <> id <- person.handles, do: id
    Enum.reject(person.handles, &(String.starts_with?(&1, "discord:") or &1 in ids))
  end

  defp identity(org_id, discord_id, person_id, actor) do
    require Ash.Query

    existing =
      Work.Identity
      |> Ash.Query.filter(org_id == ^org_id and platform == :discord and external_id == ^discord_id)
      |> Ash.read_one!(actor: actor)

    # The account challenge proved ownership; repair any old display-name inference.
    if existing do
      existing |> Ash.Changeset.for_update(:update, %{person_id: person_id}) |> Ash.update(authorize?: false)
    else
      Work.Identity
      |> Ash.Changeset.for_create(:create, %{
        org_id: org_id,
        platform: :discord,
        external_id: discord_id,
        person_id: person_id
      })
      |> Ash.create(authorize?: false)
    end
  end

  defp transaction(org_id, fun) do
    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", ["discord-link:" <> org_id])

      case fun.() do
        {:ok, result} -> result
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # These authentication actions expose only account-binding ids, not work content.
  defp verified_people(discord_id) do
    Work.Person
    |> Ash.Query.for_read(:discord_authentication, %{}, actor: %{id: nil, discord_handle: marker(discord_id)})
    |> Ash.read!()
  end

  defp membership(person) do
    Noa.Orgs.Membership
    |> Ash.Query.for_read(:discord_authentication, %{}, actor: %{id: nil, discord_membership_id: person.membership_id})
    |> Ash.Query.filter(id == ^person.membership_id)
    |> Ash.read_one()
  end

  defp marker(id), do: "discord:" <> to_string(id)
end
