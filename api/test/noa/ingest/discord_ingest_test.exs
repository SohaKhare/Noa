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

  test "an edit replaces the text; a delete erases it from the log", %{org: org} do
    {:ok, _} = Discord.ingest(gateway_message())

    assert {:ok, edited} =
             Discord.edit(gateway_message(%{content: "on it, Board report PDF export by Monday"}))

    assert edited.type == "message.edited"
    [original] = Events.since(0, org_id: org.id, limit: 1000) |> Enum.filter(&(&1.type == "message.received"))
    assert original.data["text"] == "on it, Board report PDF export by Monday" and original.data["edited_at"]
    assert {:ignore, :unchanged} = Discord.edit(gateway_message(%{content: "on it, Board report PDF export by Monday"}))

    assert {:ok, deleted} = Discord.delete(%{id: 5_001, channel_id: 2_001, guild_id: 1_001})
    assert deleted.type == "message.deleted"

    for e <- Events.since(0, org_id: org.id, limit: 1000), e.type in ["message.received", "message.edited"] do
      assert e.data["text"] == nil and e.data["deleted"] == true
    end

    assert {:ignore, :deleted} = Discord.delete(%{id: 5_001, channel_id: 2_001, guild_id: 1_001})
    assert {:ignore, :unknown_message} = Discord.delete(%{id: 9_999, channel_id: 2_001, guild_id: 1_001})
    assert {:ignore, :wrong_guild} = Discord.delete(%{id: 5_001, channel_id: 2_001, guild_id: 7})
  end

  @tag :graph
  test "the graph's episode follows edits and loses its text on delete", %{org: org} do
    on_exit(fn -> Noa.Graph.drop(org.id) end)
    :ok = Noa.Graph.bootstrap(org.id)

    {:ok, _} = Discord.ingest(gateway_message())
    {:ok, _} = Discord.edit(gateway_message(%{content: "edited text"}))
    project = fn -> for e <- Events.since(0, org_id: org.id, limit: 1000), do: :ok = Noa.Graph.Projector.project(e) end
    project.()

    {:ok, [%{"text" => "edited text"}]} =
      Noa.Graph.ro_query(org.id, "MATCH (e:Episode {id: 'discord:5001'}) RETURN e.text AS text")

    {:ok, _} = Discord.delete(%{id: 5_001, channel_id: 2_001, guild_id: 1_001})
    project.()

    {:ok, [%{"text" => nil, "deleted" => true}]} =
      Noa.Graph.ro_query(org.id, "MATCH (e:Episode {id: 'discord:5001'}) RETURN e.text AS text, e.deleted AS deleted")

    # A rebuild from the log gives the same: the text is gone from the log too.
    {:ok, _} = Noa.Graph.Projector.rebuild(org.id)

    {:ok, [%{"text" => nil}]} =
      Noa.Graph.ro_query(org.id, "MATCH (e:Episode {id: 'discord:5001'}) RETURN e.text AS text")
  end

  test "backfill loads a mapped channel's history oldest first", %{org: org} do
    veriq =
      Noa.Work.Channel |> Ash.read!(authorize?: false) |> Enum.find(&(&1.org_id == org.id and &1.name == "#veriq"))

    {:ok, _} = veriq |> Ash.Changeset.for_update(:update, %{external_id: "2001"}) |> Ash.update(authorize?: false)

    msg = fn id, text ->
      %{
        "id" => to_string(id),
        "channel_id" => "2001",
        "content" => text,
        "timestamp" => DateTime.utc_now() |> DateTime.add(-86_400, :second) |> DateTime.to_iso8601(),
        "author" => %{"id" => "3001", "username" => "saish"}
      }
    end

    Req.Test.stub(DiscordAPI, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)

      case conn.query_params["before"] do
        nil -> Req.Test.json(conn, [msg.(103, "third"), msg.(102, "second")])
        "102" -> Req.Test.json(conn, [msg.(101, "first")])
      end
    end)

    assert {:ok, 3} =
             Discord.backfill(org.id, "2001", token: "t", limit: 2, req_options: [plug: {Req.Test, DiscordAPI}])

    texts =
      Events.since(0, org_id: org.id, limit: 1000)
      |> Enum.filter(&(&1.type == "message.received"))
      |> Enum.map(& &1.data["text"])

    assert texts == ["first", "second", "third"]

    # Running it again records nothing new.
    assert {:ok, 3} =
             Discord.backfill(org.id, "2001", token: "t", limit: 2, req_options: [plug: {Req.Test, DiscordAPI}])

    assert 3 == Events.since(0, org_id: org.id, limit: 1000) |> Enum.count(&(&1.type == "message.received"))
  end

  test "backfill only loads the history window and stops paging past it", %{org: org} do
    veriq =
      Noa.Work.Channel |> Ash.read!(authorize?: false) |> Enum.find(&(&1.org_id == org.id and &1.name == "#veriq"))

    {:ok, _} = veriq |> Ash.Changeset.for_update(:update, %{external_id: "2001"}) |> Ash.update(authorize?: false)

    ago = fn days -> DateTime.utc_now() |> DateTime.add(-days * 86_400, :second) |> DateTime.to_iso8601() end

    msg = fn id, text, days ->
      %{
        "id" => to_string(id),
        "channel_id" => "2001",
        "content" => text,
        "timestamp" => ago.(days),
        "author" => %{"id" => "3001", "username" => "saish"}
      }
    end

    Req.Test.stub(DiscordAPI, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)

      case conn.query_params["before"] do
        nil -> Req.Test.json(conn, [msg.(203, "this week", 3), msg.(202, "two months ago", 60)])
        _ -> flunk("paged past the history window")
      end
    end)

    assert {:ok, 1} =
             Discord.backfill(org.id, "2001", token: "t", limit: 2, req_options: [plug: {Req.Test, DiscordAPI}])

    assert ["this week"] ==
             Events.since(0, org_id: org.id, limit: 1000)
             |> Enum.filter(&(&1.type == "message.received"))
             |> Enum.map(& &1.data["text"])
  end

  test "a Discord tag becomes the person's name, so extraction knows who was asked", %{org: org} do
    {:ok, _} = Noa.Work.identify(org.id, :discord, "824574911841566740", "soha")

    payload = %{
      "id" => "9001",
      "guild_id" => "1001",
      "channel_id" => "2001",
      "channel_name" => "veriq",
      "content" => "<@824574911841566740> we want to focus on an i2v API. <@!555> can review",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "author" => %{"id" => "3001", "username" => "pratos"},
      "mentions" => [%{"id" => "824574911841566740", "username" => "soha"}, %{"id" => "555", "global_name" => "Vedant"}]
    }

    Discord.ingest(org.id, payload)

    [text] =
      Events.since(0, org_id: org.id, limit: 1000)
      |> Enum.filter(&(&1.type == "message.received"))
      |> Enum.map(& &1.data["text"])

    assert text == "@Soha we want to focus on an i2v API. @Vedant can review"
  end

  test "backfill reads the channel's threads and files them under the channel", %{org: org} do
    veriq =
      Noa.Work.Channel |> Ash.read!(authorize?: false) |> Enum.find(&(&1.org_id == org.id and &1.name == "#veriq"))

    {:ok, _} = veriq |> Ash.Changeset.for_update(:update, %{external_id: "2001"}) |> Ash.update(authorize?: false)
    now = fn -> DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.to_iso8601() end

    msg = fn id, channel, text ->
      %{
        "id" => to_string(id),
        "channel_id" => channel,
        "content" => text,
        "timestamp" => now.(),
        "author" => %{"id" => "3001", "username" => "saish"}
      }
    end

    Req.Test.stub(DiscordAPI, fn conn ->
      case conn.request_path do
        "/api/v10/channels/2001/messages" ->
          Req.Test.json(conn, [msg.(301, "2001", "who takes i2v?")])

        "/api/v10/channels/2001/threads/archived/public" ->
          Req.Test.json(conn, %{"threads" => []})

        "/api/v10/guilds/" <> _ ->
          Req.Test.json(conn, %{
            "threads" => [
              %{"id" => "4001", "parent_id" => "2001", "name" => "i2v API"},
              %{"id" => "4002", "parent_id" => "9999", "name" => "elsewhere"}
            ]
          })

        "/api/v10/channels/4001/messages" ->
          Req.Test.json(conn, [msg.(302, "4001", "I'll design it by Friday")])
      end
    end)

    assert {:ok, 2} =
             Discord.backfill(org.id, "2001", token: "t", limit: 50, req_options: [plug: {Req.Test, DiscordAPI}])

    [parent, in_thread] =
      Events.since(0, org_id: org.id, limit: 1000)
      |> Enum.filter(&(&1.type == "message.received"))
      |> Enum.map(& &1.data)

    assert parent["thread"] == nil
    assert in_thread["thread"] == "i2v API" and in_thread["channel"] == parent["channel"]
  end
end
