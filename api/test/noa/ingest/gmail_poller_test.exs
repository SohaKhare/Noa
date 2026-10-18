defmodule Noa.Ingest.Gmail.PollerTest do
  use NoaWeb.ConnCase, async: false
  use Oban.Testing, repo: Noa.Repo

  alias Noa.{Events, Work}
  alias Noa.Ingest.Gmail.Poller

  defmodule IMAPStub do
    import ExUnit.Assertions

    def connect(_host, _port, _username, _password), do: step(:connect)
    def examine(:socket), do: step(:examine)
    def search(:socket, uid), do: step({:search, uid})
    def fetch(:socket, uid), do: step({:fetch, uid})
    def close(:socket), do: step(:close)

    defp step(call) do
      [{expected, result} | rest] = Process.get(__MODULE__)
      assert call == expected
      Process.put(__MODULE__, rest)
      result
    end
  end

  setup do
    root = superadmin!()
    {:ok, org} = Noa.Orgs.create_org(%{name: "MailboxOrg", allowed_domains: ["mail.test"]}, root)

    config = [
      org_id: org.id,
      username: "support@mail.test",
      password: "test-only",
      host: "imap.test",
      port: 993,
      imap: IMAPStub
    ]

    %{org: org, config: config, name: "gmail:#{org.id}:support@mail.test:42"}
  end

  test "first sync skips historical mail; later sync imports new UIDs and survives a retry", ctx do
    assert sync(ctx.config, 8, []) == {:ok, 0}
    assert Events.position(ctx.name) == 7
    assert messages(ctx.org) == []

    assert sync(ctx.config, 9, [
             {{:search, 8}, {:ok, [8]}},
             {{:fetch, 8}, {:ok, email()}}
           ]) == {:ok, 1}

    assert Events.position(ctx.name) == 8
    assert [event] = messages(ctx.org)
    assert event.data["text"] =~ "Ship the Veriq report"
    assert_enqueued(worker: Work.Extract)

    assert sync(ctx.config, 9, [{{:search, 9}, {:ok, []}}]) == {:ok, 0}
    assert length(messages(ctx.org)) == 1
  end

  test "a mailbox UIDVALIDITY reset starts at the new UIDNEXT without backfill", ctx do
    assert sync(ctx.config, 8, []) == {:ok, 0}
    assert sync(ctx.config, 100, [], "43") == {:ok, 0}
    assert Events.position("gmail:#{ctx.org.id}:support@mail.test:43") == 99
    assert messages(ctx.org) == []
  end

  test "network failures do not advance the checkpoint and the socket is closed", ctx do
    assert sync(ctx.config, 8, []) == {:ok, 0}

    assert sync(ctx.config, 9, [
             {{:search, 8}, {:ok, [8]}},
             {{:fetch, 8}, {:error, :timeout}}
           ]) == {:error, :timeout}

    assert Events.position(ctx.name) == 7
  end

  test "unsupported mail is skipped; oversized mail closes its unread stream before continuing", ctx do
    assert sync(ctx.config, 8, []) == {:ok, 0}

    assert sync(ctx.config, 11, [
             {{:search, 8}, {:ok, [8, 9, 10]}},
             {{:fetch, 8}, {:ok, "From: a@mail.test\r\nContent-Type: text/html\r\n\r\n<p>Skip</p>"}},
             {{:fetch, 9}, {:error, :message_too_large}}
           ]) == {:ok, 0}

    assert Events.position(ctx.name) == 9

    assert sync(ctx.config, 11, [
             {{:search, 10}, {:ok, [10]}},
             {{:fetch, 10}, {:ok, email()}}
           ]) == {:ok, 1}
  end

  test "turning off the inbox prevents subsequent connections and ingestion", ctx do
    assert sync(ctx.config, 8, []) == {:ok, 0}
    [channel] = Work.Channel |> Ash.read!(authorize?: false)
    channel |> Ash.Changeset.for_update(:update, %{read: false}) |> Ash.update!(authorize?: false)

    Process.put(IMAPStub, [])
    assert Poller.sync(ctx.config) == {:error, :inbox_not_enabled}
    assert Process.get(IMAPStub) == []
    assert messages(ctx.org) == []
  end

  defp sync(config, uidnext, steps, validity \\ "42") do
    Process.put(IMAPStub, [
      {:connect, {:ok, :socket}},
      {:examine, {:ok, {validity, uidnext}}}
      | steps ++ [{:close, :ok}]
    ])

    result = Poller.sync(config)
    assert Process.get(IMAPStub) == []
    result
  end

  defp email, do: "From: Client <client@mail.test>\r\nSubject: Veriq\r\n\r\nShip the Veriq report"

  defp messages(org),
    do: Events.since(0, org_id: org.id, limit: 100) |> Enum.filter(&(&1.type == "message.received"))
end
