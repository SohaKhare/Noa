defmodule Noa.Ingest.Discord.Links do
  @moduledoc "Ten-minute, single-use account-link challenges, issued only from Discord's gateway. Restarting invalidates them."
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def issue(org_id, guild_id, discord_id),
    do: GenServer.call(__MODULE__, {:issue, org_id, to_string(guild_id), to_string(discord_id)})

  def claim(org_id, token, actor) when is_binary(token) do
    with role when not is_nil(role) <- Noa.Orgs.role(actor.id, org_id),
         {:ok, guild_id, discord_id} <- GenServer.call(__MODULE__, {:take, org_id, token}),
         ^guild_id <- Noa.Connectors.guild_for(org_id) do
      Noa.Ingest.Discord.Accounts.link(org_id, discord_id, actor)
    else
      _ -> {:error, :discord_link_invalid}
    end
  end

  def claim(_, _, _), do: {:error, :discord_link_invalid}

  @impl true
  def init(_), do: {:ok, %{}}

  @impl true
  def handle_call({:issue, org_id, guild_id, discord_id}, _from, state) do
    now = System.monotonic_time(:second)
    state = fresh(state, now)

    if map_size(state) >= 500 do
      {:reply, {:error, :rate_limited}, state}
    else
      token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
      entry = {org_id, guild_id, discord_id, now + 600}
      {:reply, {:ok, token}, Map.put(state, hash(token), entry)}
    end
  end

  def handle_call({:take, org_id, token}, _from, state) do
    state = fresh(state, System.monotonic_time(:second))
    key = hash(token)

    case state[key] do
      {^org_id, guild_id, discord_id, _} -> {:reply, {:ok, guild_id, discord_id}, Map.delete(state, key)}
      _ -> {:reply, {:error, :discord_link_invalid}, state}
    end
  end

  defp fresh(state, now), do: Map.reject(state, fn {_key, {_, _, _, expires}} -> expires <= now end)
  defp hash(token), do: :crypto.hash(:sha256, token)
end
