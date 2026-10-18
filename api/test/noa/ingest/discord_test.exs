defmodule Noa.Ingest.DiscordTest do
  use NoaWeb.ConnCase, async: false

  alias Noa.Ingest.Discord
  alias Noa.Ingest.Discord.Consumer

  setup do
    previous_guild = Application.get_env(:noa, :discord_guild_id)
    Application.put_env(:noa, :discord_guild_id, "guild-1")

    on_exit(fn ->
      if previous_guild,
        do: Application.put_env(:noa, :discord_guild_id, previous_guild),
        else: Application.delete_env(:noa, :discord_guild_id)
    end)

    :ok
  end

  test "normalizes a guild message to the Work contract" do
    assert {:ok, message} = Discord.normalize(message_payload())
    assert message.platform == :discord
    assert message.channel_id == "channel-1"
    assert message.author_id == "user-1"
    assert message.author == "Soha"
    assert message.text == "Ship the ingest"
    assert message.at == ~U[2026-10-17 04:30:00Z]
  end

  test "normalizes Nostrum-style atom-keyed structs at the gateway boundary" do
    payload = %{
      id: "message-2",
      guild_id: "guild-1",
      channel_id: "channel-1",
      content: "hello",
      timestamp: "2026-10-17T04:30:00Z",
      author: %{id: "user-2", username: "member"}
    }

    assert {:ok, %{message_id: "message-2", author_id: "user-2"}} = Discord.normalize(payload)
  end

  test "rejects DMs before they reach Work" do
    assert {:ignore, :direct_message} = Discord.normalize(Map.delete(message_payload(), "guild_id"))
  end

  test "rejects bots and webhook messages" do
    assert {:ignore, :bot} = Discord.normalize(update_in(message_payload(), ["author", "bot"], fn _ -> true end))
    assert {:ignore, :bot} = Discord.normalize(Map.put(message_payload(), "webhook_id", "hook-1"))
  end

  test "rejects empty and unapproved guild messages" do
    assert {:ignore, :empty} = Discord.normalize(Map.put(message_payload(), "content", "  "))

    Application.put_env(:noa, :discord_guild_id, "other-guild")
    assert {:ignore, :wrong_guild} = Discord.normalize(message_payload())
  end

  test "consumer ignores non-message gateway events before touching Work" do
    assert :noop = Consumer.handle_event({:READY, %{}, %{}})
  end

  defp message_payload do
    %{
      "id" => "message-1",
      "guild_id" => "guild-1",
      "channel_id" => "channel-1",
      "channel_name" => "#veriq",
      "content" => " Ship the ingest ",
      "timestamp" => "2026-10-17T04:30:00Z",
      "author" => %{"id" => "user-1", "username" => "soha", "global_name" => "Soha"}
    }
  end
end
