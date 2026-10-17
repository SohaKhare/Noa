defmodule Noa.Ingest.Discord.Consumer do
  @moduledoc """
  Small adapter between a Discord gateway client and `Noa.Ingest.Discord`.

  Keeping the event shape at this boundary means a gateway library can be added or
  swapped without allowing connector code to bypass the Work/event-log pipeline.
  `MESSAGE_CREATE` is the only event that reads content; DMs and bot messages are
  rejected by the normalizer before they reach the database.
  """

  use Nostrum.Consumer

  alias Noa.Ingest.Discord

  @impl true
  def handle_event({:MESSAGE_CREATE, payload, _state}), do: Discord.ingest(payload)

  @impl true
  def handle_event({:GUILD_MEMBER_ADD, payload, _state}) do
    with {:ok, org_id} <- configured_org(payload.guild_id),
         do: Discord.ingest_member(org_id, payload)
  end

  @impl true
  def handle_event({:GUILD_CREATE, guild, _state}) do
    guild = Discord.normalize_payload(guild)

    with {:ok, org_id} <- configured_org(guild["id"]) do
      Enum.each(guild["members"] || [], fn member ->
        Discord.ingest_member(org_id, Map.put(member, "guild_id", guild["id"]))
      end)
    end
  end

  @impl true
  def handle_event(_event), do: {:ignore, :unsupported_event}

  defp configured_org(guild_id) do
    case Application.get_env(:noa, :discord_org_id) || System.get_env("DISCORD_ORG_ID") do
      nil -> {:ignore, :unknown_workspace}
      "" -> {:ignore, :unknown_workspace}
      org_id -> if Discord.guild_allowed?(guild_id), do: {:ok, org_id}, else: {:ignore, :wrong_guild}
    end
  end
end
