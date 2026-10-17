defmodule Noa.Ingest.DiscordIngestTest do
  @moduledoc "Gateway messages (1.13) as Nostrum delivers them reach the event log and the Inbox pipeline."
  use NoaWeb.ConnCase, async: false
  use Oban.Testing, repo: Noa.Repo

  alias Noa.{Events, Work}
  alias Noa.Ingest.Discord

  @seed Path.expand("../../../../docs/seeds/nyi.json", __DIR__) |> File.read!() |> Jason.decode!()

  setup do
    root = superadmin!()
    {:ok, org} = Noa.Orgs.create_org(%{name: "NotYourIdea", allowed_domains: ["notyouridea.com"]}, root)
    {:ok, _} = Work.load_seed(org.id, @seed)

    Application.put_env(:noa, :discord_org_id, org.id)
    Application.put_env(:noa, :discord_guild_id, "1001")

    on_exit(fn ->
      Application.delete_env(:noa, :discord_org_id)
      Application.delete_env(:noa, :discord_guild_id)
    end)

    %{org: org}
  end

  # The shape of a Nostrum.Struct.Message: atom keys, integer snowflakes, DateTime.
  defp gateway_message(attrs \\ %{}) do
    Map.merge(
      %{
        id: 5_001,
        guild_id: 1_001,
        channel_id: 2_001,
        channel_name: "veriq",
        content: "on it, Board report PDF export by Friday",
        timestamp: ~U[2026-10-17 04:30:00Z],
        type: 0,
        webhook_id: nil,
        author: %{id: 3_001, username: "saish", global_name: "Saish", bot: nil}
      },
      attrs
    )
  end

  test "a mapped channel's message is recorded once and queued for extraction", %{org: org} do
    assert {:ok, event} = Discord.ingest(gateway_message())
    assert event.type == "message.received"
    assert event.data["channel"] == "#veriq" and event.data["episode_id"] == "discord:5001"
    assert event.data["at"] == "2026-10-17T04:30:00Z"
    assert event.data["project_id"]
    assert_enqueued(worker: Work.Extract)

    assert {:duplicate, _} = Discord.ingest(gateway_message())
    assert Enum.count(Events.since(0, org_id: org.id, limit: 1000), &(&1.type == "message.received")) == 1
  end

  test "unmapped channels, other guilds, DMs and bots never reach the log", %{org: org} do
    assert {:error, :not_read} = Discord.ingest(gateway_message(%{id: 5_002, channel_name: "random"}))
    assert {:ignore, _} = Discord.ingest(gateway_message(%{id: 5_003, guild_id: 9_999}))
    assert {:ignore, _} = Discord.ingest(gateway_message(%{id: 5_004, guild_id: nil}))

    assert {:ignore, :bot} =
             Discord.ingest(gateway_message(%{id: 5_005, author: %{id: 3_002, username: "noa", bot: true}}))

    refute Enum.any?(Events.since(0, org_id: org.id, limit: 1000), &(&1.type == "message.received"))
  end

  test "a new guild member gets an identity", %{org: org} do
    assert {:ok, identity} =
             Noa.Ingest.Discord.Consumer.handle_event(
               {:GUILD_MEMBER_ADD, {1_001, %{user_id: 3_003, nick: "abhishek"}}, nil}
             )

    assert identity.org_id == org.id and identity.external_id == "3003"
  end
end
