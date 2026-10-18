defmodule Noa.NotifyTest do
  @moduledoc "Notifications on each person's chosen channel (2.21, 3.23): email with a link to act, Discord DMs, nothing for in-app."
  use NoaWeb.ConnCase, async: false
  import Swoosh.TestAssertions

  alias Noa.{Events, Work}
  alias Noa.WhatsApp.Notifier

  @seed Path.expand("../../../docs/seeds/nyi.json", __DIR__) |> File.read!() |> Jason.decode!()

  setup do
    root = superadmin!()
    {:ok, org} = Noa.Orgs.create_org(%{name: "NotYourIdea", allowed_domains: ["notyouridea.com"]}, root)
    {:ok, _, url} = Noa.Orgs.invite(org, "vedant@notyouridea.com", :org_admin, root)
    vedant = accept!(url, "Vedant")
    {:ok, _, url} = Noa.Orgs.invite(org, "saish@notyouridea.com", :member, vedant)
    saish = accept!(url, "Saish")
    {:ok, _} = Work.load_seed(org.id, @seed)
    {:ok, projects} = Work.projects(org.id, vedant)
    flush_emails()

    %{
      org: org,
      vedant: vedant,
      saish: saish,
      person: Work.person_for(saish, org.id),
      veriq: Enum.find(projects, &(&1.key == "veriq"))
    }
  end

  # The invites above sent emails; start each test with an empty mailbox.
  defp flush_emails do
    receive do
      {:email, _} -> flush_emails()
    after
      0 -> :ok
    end
  end

  defp assign(ctx) do
    {:ok, _} =
      Work.create_task(
        ctx.org.id,
        %{title: "Board report PDF export", project_id: ctx.veriq.id, owner_id: ctx.person.id},
        ctx.vedant
      )

    Events.since(0, org_id: ctx.org.id, limit: 10_000) |> Enum.filter(&(&1.type == "task.saved")) |> List.last()
  end

  test "email: the new owner gets the message with a link to act", ctx do
    {:ok, _} = Work.set_notifications(ctx.person.id, %{notify_via: :email}, ctx.saish)

    assert [{:ok, :email}] = Notifier.handle(assign(ctx))

    assert_email_sent(fn email ->
      assert [{_, "saish@notyouridea.com"}] = email.to
      assert email.subject =~ "Vedant put you on"
      assert email.text_body =~ "Board report PDF export"
      assert email.text_body =~ "http://localhost:3000/"
    end)
  end

  test "discord: without the bot connected nothing is sent and nothing crashes", ctx do
    {:ok, _} = Work.Setup.update_person(ctx.person.id, %{handles: ["saish"]}, ctx.vedant)
    {:ok, _} = Work.set_notifications(ctx.person.id, %{notify_via: :discord}, ctx.saish)

    assert [{:error, :not_connected}] = Notifier.handle(assign(ctx))
    assert_no_email_sent()
  end

  test "in app: nothing leaves Noa", ctx do
    {:ok, _} = Work.set_notifications(ctx.person.id, %{notify_via: :in_app}, ctx.saish)
    assert Notifier.handle(assign(ctx)) == []
    assert_no_email_sent()
  end
end
