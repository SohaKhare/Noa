defmodule Noa.WhatsAppTest do
  @moduledoc "WhatsApp through Kapso (1.15, 2.7, 2.21): notifications from the event log, signed webhooks, replies that act."
  use NoaWeb.ConnCase, async: false
  use Oban.Testing, repo: Noa.Repo

  import Ecto.Query
  alias Noa.{Events, Work}
  alias Noa.WhatsApp.{Inbound, Notifier}

  @seed Path.expand("../../../docs/seeds/nyi.json", __DIR__) |> File.read!() |> Jason.decode!()
  @sample Path.expand("../../../docs/seeds/nyi-sample-work.json", __DIR__) |> File.read!() |> Jason.decode!()

  setup do
    root = superadmin!()
    {:ok, org} = Noa.Orgs.create_org(%{name: "NotYourIdea", allowed_domains: ["notyouridea.com"]}, root)
    {:ok, _, url} = Noa.Orgs.invite(org, "vedant@notyouridea.com", :org_admin, root)
    vedant = accept!(url, "Vedant")
    {:ok, _, url} = Noa.Orgs.invite(org, "saish@notyouridea.com", :member, vedant)
    saish = accept!(url, "Saish")
    {:ok, _} = Work.load_seed(org.id, @seed)
    {:ok, _} = Work.Seed.load_sample(org.id, @sample)

    {:ok, _} =
      Work.set_notifications(
        Work.person_for(vedant, org.id).id,
        %{notify_via: :whatsapp, phone: "+919800000001"},
        vedant
      )

    {:ok, _} =
      Work.set_notifications(Work.person_for(saish, org.id).id, %{notify_via: :whatsapp, phone: "+919800000002"}, saish)

    %{org: org, vedant: vedant, saish: saish}
  end

  defp last_event(org, type),
    do: Events.since(0, org_id: org.id, limit: 10_000) |> Enum.filter(&(&1.type == type)) |> List.last()

  defp project(org, key),
    do: Work.Project |> Ash.read!(authorize?: false) |> Enum.find(&(&1.org_id == org.id and &1.key == key))

  defp task(org, title),
    do: Work.Task |> Ash.read!(authorize?: false) |> Enum.find(&(&1.org_id == org.id and &1.title == title))

  defp outbox(phone) do
    from(m in "whatsapp_messages",
      where: m.phone == ^phone and m.direction == "out",
      order_by: [asc: m.inserted_at],
      select: %{body: m.body, buttons: m.buttons, status: m.status}
    )
    |> Noa.Repo.all()
  end

  describe "notifications from the event log" do
    test "a task given to someone tells them, with buttons; not when you give it to yourself", %{
      org: org,
      vedant: vedant,
      saish: saish
    } do
      me = Work.person_for(saish, org.id)

      {:ok, _} =
        Work.create_task(
          org.id,
          %{title: "Caption export", project_id: project(org, "veriq").id, owner_id: me.id},
          vedant
        )

      [{:ok, _}] = Notifier.handle(last_event(org, "task.saved"))

      [msg] = outbox("+919800000002")
      assert msg.body =~ ~s(Vedant put you on "Caption export" in Veriq)
      assert msg.status == "simulated"
      assert msg.buttons |> Map.values() |> Enum.sort() == ["Done", "Need help", "Start now"]

      {:ok, _} =
        Work.create_task(org.id, %{title: "Self note", project_id: project(org, "veriq").id, owner_id: me.id}, saish)

      assert Notifier.handle(last_event(org, "task.saved")) == []
    end

    test "a member's deadline change goes to the lead; the decision goes back", %{
      org: org,
      vedant: vedant,
      saish: saish
    } do
      t = task(org, "Report share links")
      {:ok, _} = Work.update_task(t.id, %{due_on: ~D[2026-12-01], reason: "client moved review"}, saish)
      [{:ok, _}] = Notifier.handle(last_event(org, "change.saved"))
      [ask] = outbox("+919800000001")

      assert ask.body =~ ~s(Saish wants to change the deadline of "Report share links") and
               ask.body =~ "client moved review"

      assert ask.buttons |> Map.values() |> Enum.sort() == ["Approve", "Reject"]

      [change] = Work.changes(org.id, vedant, status: :pending) |> elem(1)
      {:ok, _} = Work.approve_change(change.id, vedant)
      [{:ok, _}] = Notifier.handle(last_event(org, "change.saved"))
      assert List.last(outbox("+919800000002")).body =~ "Vedant approved your deadline change"
    end

    test "quiet hours hold updates but not approvals waiting on a lead", %{org: org, vedant: vedant, saish: saish} do
      for {user, phone} <- [{saish, "+919800000002"}, {vedant, "+919800000001"}] do
        {:ok, _} =
          Work.set_notifications(
            Work.person_for(user, org.id).id,
            %{phone: phone, quiet_from: ~T[00:00:00], quiet_to: ~T[23:59:59]},
            user
          )
      end

      {:ok, _} =
        Work.create_task(
          org.id,
          %{title: "Quiet one", project_id: project(org, "veriq").id, owner_id: Work.person_for(saish, org.id).id},
          vedant
        )

      assert Notifier.handle(last_event(org, "task.saved")) == []

      {:ok, _} = Work.update_task(task(org, "Report share links").id, %{due_on: ~D[2026-12-02]}, saish)
      assert [{:ok, _}] = Notifier.handle(last_event(org, "change.saved"))
    end
  end

  describe "the webhook" do
    defp signed(body, secret \\ "test-kapso-secret") do
      raw = Jason.encode!(body)
      sig = :crypto.mac(:hmac, :sha256, secret, raw) |> Base.encode16(case: :lower)

      Phoenix.ConnTest.build_conn()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-webhook-event", "whatsapp.message.received")
      |> put_req_header("x-webhook-signature", sig)
      |> post("/webhooks/kapso", raw)
    end

    defp inbound(id, phone, message),
      do: %{
        "message" => Map.put(message, "id", id),
        "conversation" => %{"phone_number" => phone},
        "phone_number_id" => "123"
      }

    test "only correctly signed deliveries are accepted, each message queued once" do
      body = inbound("wamid.1", "919800000002", %{"type" => "text", "text" => %{"body" => "hi"}})
      assert signed(body, "wrong-secret").status == 401
      assert signed(body).status == 200
      assert [_] = all_enqueued(worker: Inbound)

      batch = %{
        "type" => "whatsapp.message.received",
        "batch" => true,
        "data" => [body, inbound("wamid.2", "919800000002", %{"type" => "text", "text" => %{"body" => "yo"}})]
      }

      assert signed(batch).status == 200
      assert length(all_enqueued(worker: Inbound)) == 2
    end
  end

  describe "replies act as the person" do
    test "\"tasks\" lists their open work, soonest due first", %{org: org, vedant: vedant, saish: saish} do
      me = Work.person_for(saish, org.id)

      {:ok, _} =
        Work.create_task(
          org.id,
          %{title: "Caption export", project_id: project(org, "veriq").id, owner_id: me.id, due_on: Date.utc_today()},
          vedant
        )

      reply =
        Inbound.handle(inbound("wamid.t1", "919800000002", %{"type" => "text", "text" => %{"body" => "my tasks"}}))

      assert reply =~ "Your open tasks:\n1. Caption export (Veriq · due "
      assert reply =~ ~s(Reply "done <task>")
    end

    test "task lists exclude completed work and other people's assignments", %{org: org, vedant: vedant, saish: saish} do
      me = Work.person_for(saish, org.id)
      lead = Work.person_for(vedant, org.id)
      project_id = project(org, "veriq").id

      for attrs <- [
            %{title: "Undated assignment", owner_id: me.id},
            %{title: "Already completed", owner_id: me.id, status: :done},
            %{title: "Only for Vedant", owner_id: lead.id}
          ] do
        assert {:ok, _} = Work.create_task(org.id, Map.put(attrs, :project_id, project_id), vedant)
      end

      reply = Inbound.handle(inbound("wamid.list-scope", "919800000002", %{"text" => %{"body" => "tasks"}}))
      assert reply =~ "Undated assignment"
      refute reply =~ "Already completed"
      refute reply =~ "Only for Vedant"
    end

    test "task lists cap long titles and the number of displayed tasks", %{org: org, vedant: vedant, saish: saish} do
      me = Work.person_for(saish, org.id)
      project_id = project(org, "veriq").id

      for i <- 1..11 do
        assert {:ok, _} =
                 Work.create_task(
                   org.id,
                   %{
                     title: "Long task #{i} " <> String.duplicate("x", 2000),
                     owner_id: me.id,
                     project_id: project_id,
                     due_on: ~D[2000-01-01]
                   },
                   vedant
                 )
      end

      reply = Inbound.handle(inbound("wamid.list-limit", "919800000002", %{"text" => %{"body" => "my work"}}))
      assert reply =~ "10. Long task 10"
      refute reply =~ "11. Long task 11"
      assert reply =~ "more in Noa"
      assert String.length(reply) < 4096
    end

    test "finishing a task tells the project's lead", %{org: org, vedant: vedant, saish: saish} do
      me = Work.person_for(saish, org.id)
      veriq = project(org, "veriq")

      {:ok, _} =
        veriq
        |> Ash.Changeset.for_update(:update, %{lead_id: Work.person_for(vedant, org.id).id})
        |> Ash.update(authorize?: false)

      {:ok, t} = Work.create_task(org.id, %{title: "Caption export", project_id: veriq.id, owner_id: me.id}, vedant)

      {:ok, _} = Work.update_task(t.id, %{status: :done}, saish)
      Notifier.handle(last_event(org, "task.saved"))

      assert Enum.any?(outbox("+919800000001"), &(&1.body =~ ~s(Saish finished "Caption export" in Veriq)))
    end

    test "Done and Start buttons move the card", %{org: org} do
      t = task(org, "Report share links")

      reply =
        Inbound.handle(
          inbound("wamid.3", "919800000002", %{
            "type" => "interactive",
            "interactive" => %{"type" => "button_reply", "button_reply" => %{"id" => "done:#{t.id}", "title" => "Done"}}
          })
        )

      assert reply =~ ~s(Done: "Report share links")
      assert task(org, "Report share links").status == :done
    end

    test "a bare \"done\" finishes the task Noa last wrote about; \"done <name>\" finds it", %{
      org: org,
      vedant: vedant,
      saish: saish
    } do
      me = Work.person_for(saish, org.id)

      {:ok, _} =
        Work.create_task(
          org.id,
          %{title: "Caption export", project_id: project(org, "veriq").id, owner_id: me.id},
          vedant
        )

      Notifier.handle(last_event(org, "task.saved"))

      assert Inbound.handle(inbound("wamid.4", "919800000002", %{"type" => "text", "text" => %{"body" => "done"}})) =~
               "Caption export"

      assert task(org, "Caption export").status == :done

      assert Inbound.handle(
               inbound("wamid.5", "919800000002", %{
                 "type" => "text",
                 "text" => %{"body" => "on it: practitioner report layout"}
               })
             ) =~ "in progress"
    end

    test "only the lead's Approve decides a change", %{org: org, vedant: vedant, saish: saish} do
      {:ok, _} = Work.update_task(task(org, "Report share links").id, %{due_on: ~D[2026-12-01]}, saish)
      [change] = Work.changes(org.id, vedant, status: :pending) |> elem(1)

      tap = fn phone, id ->
        Inbound.handle(
          inbound(id, phone, %{
            "type" => "interactive",
            "interactive" => %{"button_reply" => %{"id" => "approve_change:#{change.id}"}}
          })
        )
      end

      assert tap.("919800000002", "wamid.6") =~ "Only the project's lead"
      assert tap.("919800000001", "wamid.7") =~ "Approved"
      assert task(org, "Report share links").due_on == ~D[2026-12-01]
    end

    test "questions get a cited answer; unknown numbers are told how to connect", %{org: org} do
      _ = org

      answer =
        Inbound.handle(
          inbound("wamid.8", "919800000002", %{"type" => "text", "text" => %{"body" => "what's blocking Veriq?"}})
        )

      assert answer =~ "Brand logo pack import"

      assert Inbound.handle(inbound("wamid.9", "15550000000", %{"type" => "text", "text" => %{"body" => "hello"}})) =~
               "don't know this number"
    end
  end

  test "the outbox shows admins everything and others their own", %{org: org, vedant: vedant, saish: saish} do
    {:ok, _} =
      Work.create_task(
        org.id,
        %{title: "Caption export", project_id: project(org, "veriq").id, owner_id: Work.person_for(saish, org.id).id},
        vedant
      )

    Notifier.handle(last_event(org, "task.saved"))

    admin = signed_in(vedant) |> get("/api/orgs/#{org.id}/whatsapp") |> json_response(200)
    assert admin["configured"] == false and admin["scope"] == "workspace"
    assert [%{"body" => body, "status" => "simulated"}] = admin["messages"]
    assert body =~ "Caption export"

    mine = signed_in(saish) |> get("/api/orgs/#{org.id}/whatsapp") |> json_response(200)
    assert mine["scope"] == "you" and length(mine["messages"]) == 1
  end

  test "the 24-hour window is open only after the person wrote to Noa", %{org: org} do
    refute Noa.WhatsApp.window_open?("+91 98000 00002")

    Noa.WhatsApp.record(%{
      org_id: org.id,
      direction: "in",
      phone: "919800000002",
      kind: "text",
      body: "hi",
      status: "received"
    })

    assert Noa.WhatsApp.window_open?("+91 98000 00002")
    refute Noa.WhatsApp.window_open?("+91 98000 00009")
  end
end
