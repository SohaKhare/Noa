defmodule Noa.Ingest.Discord.Consumer do
  @moduledoc """
  Small adapter between a Discord gateway client and `Noa.Ingest.Discord`.

  Keeping the event shape at this boundary means a gateway library can be added or
  swapped without allowing connector code to bypass the Work/event-log pipeline.
  Guild messages go through the consent gate; slash commands, mentions and explicit
  questions to Noa use verified accounts. DMs never enter the ingestion pipeline.
  """

  use Nostrum.Consumer

  alias Noa.Ingest.Discord
  alias Noa.Ingest.Discord.Commands

  @impl true
  def handle_event({:READY, %{user: %{id: _}}, _state}), do: register()

  @impl true
  def handle_event({:INTERACTION_CREATE, interaction, _state}), do: Commands.handle(interaction)

  @impl true
  def handle_event({:MESSAGE_CREATE, payload, _state}) do
    message = Discord.normalize_payload(payload)

    if is_nil(message["guild_id"]) do
      Commands.direct(message)
    else
      result = Discord.ingest(payload)
      if match?({:ok, _}, result), do: Commands.mention(payload)
      result
    end
  end

  @impl true
  def handle_event({:MESSAGE_UPDATE, {_old, updated}, _state}), do: Discord.edit(updated)

  @impl true
  def handle_event({:MESSAGE_DELETE, deleted, _state}), do: Discord.delete(deleted)

  @impl true
  def handle_event({:GUILD_MEMBER_ADD, {guild_id, member}, _state}) do
    with {:ok, org_id} <- configured_org(guild_id) do
      Discord.ingest_member(org_id, %{
        "guild_id" => guild_id,
        "user" => %{"id" => member.user_id, "username" => member.nick}
      })
    end
  end

  @impl true
  def handle_event({:GUILD_AVAILABLE, guild, state}), do: handle_event({:GUILD_CREATE, guild, state})

  @impl true
  def handle_event({:GUILD_CREATE, guild, _state}) do
    guild = Discord.normalize_payload(guild)
    register(guild["id"])

    with {:ok, org_id} <- configured_org(guild["id"]) do
      Enum.each(guild["members"] || [], fn member ->
        Discord.ingest_member(org_id, Map.put(member, "guild_id", guild["id"]))
      end)
    end
  end

  defp configured_org(guild_id), do: Discord.org_for_guild(guild_id)

  defp register(guild_id \\ nil) do
    case Commands.register(guild_id) do
      :ok ->
        :ok

      _ ->
        require Logger
        Logger.warning("Noa Discord command registration failed; retry registration after reconnecting")
        :error
    end
  end
end
