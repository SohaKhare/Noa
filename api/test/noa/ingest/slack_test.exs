defmodule Noa.Ingest.SlackTest do
  use NoaWeb.ConnCase, async: false
  use Oban.Testing, repo: Noa.Repo

  require Ash.Query

  alias Noa.{Connectors, Events, Repo, Vault, Work}
  alias Noa.Ingest.Slack
  alias Noa.Ingest.Slack.{Client, Event}

  @seed Path.expand("../../../../docs/seeds/nyi.json", __DIR__) |> File.read!() |> Jason.decode!()

  setup do
    root = superadmin!()
    {:ok, org} = Noa.Orgs.create_org(%{name: "NotYourIdea", allowed_domains: ["notyouridea.com"]}, root)
    {:ok, _, url} = Noa.Orgs.invite(org, "vedant@notyouridea.com", :org_admin, root)
    vedant = accept!(url, "Vedant")
    {:ok, _} = Work.load_seed(org.id, @seed)

    now = DateTime.utc_now()

    Repo.insert_all("org_connectors", [
      %{
        id: Ecto.UUID.bingenerate(),
        org_id: Ecto.UUID.dump!(org.id),
        kind: "slack",
        external_id: "T001",
        token_enc: Vault.encrypt("xoxb-test"),
        connected_by_id: Ecto.UUID.dump!(vedant.id),
        inserted_at: now,
        updated_at: now
      }
    ])

    previous = Application.get_env(:noa, Noa.Ingest.Slack.Client)

    Application.put_env(
      :noa,
      Noa.Ingest.Slack.Client,
      Keyword.put(previous, :req_options, plug: {Req.Test, SlackAPI})
    )

    Req.Test.stub(SlackAPI, &stub/1)
    on_exit(fn -> Application.put_env(:noa, Noa.Ingest.Slack.Client, previous) end)

    {:ok, projects} = Work.projects(org.id, vedant)
    veriq = Enum.find(projects, &(&1.key == "veriq"))

    {:ok, _channel} =
      Work.Setup.create_channel(
        org.id,
        %{platform: :slack, name: "#veriq-slack", external_id: "C001", project_id: veriq.id},
        vedant
      )

    %{org: org, vedant: vedant, veriq: veriq}
  end

  defp stub(%{request_path: "/api/users.info"} = conn) do
    conn = Plug.Conn.fetch_query_params(conn)
    id = conn.query_params["user"]

    if id == "RATE" do
      conn
      |> Plug.Conn.put_status(429)
      |> Plug.Conn.put_resp_header("retry-after", "42")
      |> Req.Test.json(%{"ok" => false, "error" => "ratelimited"})
    else
      Req.Test.json(conn, %{"ok" => true, "user" => user(id, "Saish")})
    end
  end

  defp stub(%{request_path: "/api/conversations.list"} = conn) do
    conn = Plug.Conn.fetch_query_params(conn)

    if conn.query_params["cursor"] == "page-2" do
      Req.Test.json(conn, %{
        "ok" => true,
        "channels" => [
          %{"id" => "C005", "name" => "private", "is_private" => true, "is_member" => true}
        ],
        "response_metadata" => %{"next_cursor" => ""}
      })
    else
      Req.Test.json(conn, %{
        "ok" => true,
        "channels" => [
          %{"id" => "C001", "name" => "veriq-slack", "is_member" => true},
          %{"id" => "C002", "name" => "not-joined", "is_member" => false},
          %{"id" => "C003", "name" => "shared", "is_member" => true, "is_shared" => true},
          %{"id" => "C004", "name" => "archived", "is_member" => true, "is_archived" => true}
        ],
        "response_metadata" => %{"next_cursor" => "page-2"}
      })
    end
  end

  defp stub(%{request_path: "/api/users.list"} = conn) do
    Req.Test.json(conn, %{
      "ok" => true,
      "members" => [user("U001", "Saish"), user("U002", "Noa", %{"is_bot" => true})],
      "response_metadata" => %{"next_cursor" => ""}
    })
  end

  defp stub(%{request_path: "/api/conversations.history"} = conn) do
    Req.Test.json(conn, %{
      "ok" => true,
      "messages" => [message("1710000003.000003", "third"), message("1710000002.000002", "second")]
    })
  end

  defp stub(%{request_path: "/api/conversations.open"} = conn),
    do: Req.Test.json(conn, %{"ok" => true, "channel" => %{"id" => "D001"}})

  defp stub(%{request_path: "/api/chat.postMessage"} = conn),
    do: Req.Test.json(conn, %{"ok" => true, "channel" => "D001", "ts" => "1710000004.000004"})

  defp user(id, name, extra \\ %{}) do
    Map.merge(%{"id" => id, "name" => String.downcase(name), "profile" => %{"display_name" => name}}, extra)
  end

  defp message(ts, text, extra \\ %{}) do
    Map.merge(
      %{
        "type" => "message",
        "channel" => "C001",
        "channel_type" => "channel",
        "user" => "U001",
        "text" => text,
        "ts" => ts
      },
      extra
    )
  end

  test "mapped messages are recorded once and edits/deletes retain Slack's stable id", %{org: org} do
    envelope = %{"team_id" => "T001", "event" => message("1710000001.000001", "Ship Slack ingest")}

    assert {:ok, event} = Slack.ingest(envelope)
    assert event.key == "slack:C001:1710000001.000001"
    assert event.data["channel"] == "#veriq-slack"
    assert event.data["author"] == "Saish"
    assert {:duplicate, _} = Slack.ingest(envelope)

    changed = %{
      "team_id" => "T001",
      "event" => %{
        "type" => "message",
        "subtype" => "message_changed",
        "channel" => "C001",
        "message" => message("1710000001.000001", "Ship Slack ingest today")
      }
    }

    assert {:ok, %{type: "message.edited"}} = Slack.edit(changed)

    deleted = %{
      "team_id" => "T001",
      "event" => %{
        "type" => "message",
        "subtype" => "message_deleted",
        "channel" => "C001",
        "deleted_ts" => "1710000001.000001"
      }
    }

    assert {:ok, %{type: "message.deleted"}} = Slack.delete(deleted)
    [original] = Events.since(0, org_id: org.id, limit: 1000) |> Enum.filter(&(&1.type == "message.received"))
    assert original.data["deleted"] == true and original.data["text"] == nil
  end

  test "unmapped channels, DMs, MPDMs, Slack Connect, bots and system messages are ignored", %{org: org} do
    assert {:error, :not_read} =
             Slack.ingest(org.id, %{message("1710000010.000010", "private chatter") | "channel" => "C999"})

    assert {:ignore, :direct_message} = Slack.normalize(%{message("1.0", "dm") | "channel_type" => "im"})
    assert {:ignore, :direct_message} = Slack.normalize(%{message("1.0", "group dm") | "channel_type" => "mpim"})

    assert {:ignore, :shared_channel} =
             Slack.normalize(Map.put(message("1.0", "shared"), "is_ext_shared_channel", true))

    assert {:ignore, :bot} = Slack.normalize(Map.put(message("1.0", "bot"), "bot_id", "B001"))
    assert {:ignore, :system_message} = Slack.normalize(Map.put(message("1.0", "joined"), "subtype", "channel_join"))
  end

  test "the event worker completes unmapped-channel deliveries without retrying" do
    job = %Oban.Job{
      args: %{
        "payload" => %{
          "team_id" => "T001",
          "event" => message("1710000011.000011", "unmapped chatter", %{"channel" => "C999"})
        }
      }
    }

    assert :ok = Event.perform(job)
  end

  test "channel discovery paginates and returns only joined, non-shared, active channels", %{org: org} do
    assert {:ok, channels} = Slack.workspace_channels(org.id)

    assert channels == [
             %{id: "C005", name: "private", private: true},
             %{id: "C001", name: "veriq-slack", private: false}
           ]
  end

  test "channel mapping rejects unjoined, archived and Slack Connect channels", %{
    org: org,
    vedant: vedant,
    veriq: veriq
  } do
    for {id, name} <- [{"C002", "not-joined"}, {"C003", "shared"}, {"C004", "archived"}] do
      assert {:error, :slack_channel_unavailable} =
               Work.Setup.create_channel(
                 org.id,
                 %{platform: :slack, name: "##{name}", external_id: id, project_id: veriq.id},
                 vedant
               )
    end
  end

  test "user sync skips bots and backfill records the newest page oldest first", %{org: org} do
    assert {:ok, 1} = Slack.sync_users(org.id)
    assert {:ok, 2} = Slack.backfill(org.id, "C001")

    texts =
      Events.since(0, org_id: org.id, limit: 1000)
      |> Enum.filter(&(&1.type == "message.received"))
      |> Enum.map(& &1.data["text"])

    assert texts == ["second", "third"]
  end

  test "team_join and user_change refresh Slack identities", %{org: org} do
    joined = %Oban.Job{
      args: %{
        "payload" => %{
          "team_id" => "T001",
          "event" => %{"type" => "team_join", "user" => user("U009", "New Person")}
        }
      }
    }

    changed = %{
      joined
      | args:
          put_in(joined.args, ["payload", "event"], %{
            "type" => "user_change",
            "user" => user("U009", "Renamed")
          })
    }

    assert :ok = Event.perform(joined)
    assert :ok = Event.perform(changed)

    identity =
      Noa.Work.Identity
      |> Ash.Query.filter(org_id == ^org.id and platform == :slack and external_id == "U009")
      |> Ash.read_one!(authorize?: false)

    assert identity.display_name == "Renamed"
  end

  test "outbound DMs use the linked Slack identity", %{org: org, vedant: vedant} do
    person = Work.person_for(vedant, org.id)
    {:ok, identity} = Work.identify(org.id, :slack, "U001", "Vedant")

    if identity.person_id != person.id do
      {:ok, _} = identity |> Ash.Changeset.for_update(:update, %{person_id: person.id}) |> Ash.update(authorize?: false)
    end

    assert {:ok, %{"channel" => "D001"}} = Slack.dm(person, "A task needs you")
  end

  test "the client exposes Slack's retry-after delay" do
    assert {:error, {:rate_limited, 42}} = Client.user("xoxb-test", "RATE")
  end

  test "app_uninstalled deletes the workspace token", %{org: org} do
    assert is_binary(Connectors.slack_token(org.id))

    job = %Oban.Job{
      args: %{
        "payload" => %{
          "team_id" => "T001",
          "event" => %{"type" => "app_uninstalled"}
        }
      }
    }

    assert :ok = Event.perform(job)
    assert Connectors.slack_token(org.id) == nil
  end
end
