defmodule Noa.Ingest.Discord.API do
  @moduledoc false

  def respond(interaction, response),
    do: Nostrum.Api.Interaction.create_response(interaction["id"], interaction["token"], response)

  def edit(interaction, response),
    do: Nostrum.Api.Interaction.edit_response(interaction["application_id"], interaction["token"], response)

  def message(channel_id, payload), do: Nostrum.Api.Message.create(String.to_integer(channel_id), payload)
  def channel(channel_id), do: Nostrum.Api.Channel.get(String.to_integer(channel_id))
  def dm(discord_id), do: Nostrum.Api.User.create_dm(String.to_integer(discord_id))

  def global_commands, do: Nostrum.Api.ApplicationCommand.global_commands()
  def guild_commands(guild_id), do: Nostrum.Api.ApplicationCommand.guild_commands(String.to_integer(guild_id))
  def create_global(spec), do: Nostrum.Api.ApplicationCommand.create_global_command(spec)

  def create_guild(guild_id, spec),
    do: Nostrum.Api.ApplicationCommand.create_guild_command(String.to_integer(guild_id), spec)

  def delete_global(id), do: Nostrum.Api.ApplicationCommand.delete_global_command(id)

  def delete_guild(guild_id, id),
    do: Nostrum.Api.ApplicationCommand.delete_guild_command(String.to_integer(guild_id), id)
end
