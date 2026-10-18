defmodule Noa.AssignAllocationTest do
  @moduledoc "Assigning a task puts its owner on the project, and they hear that their agent pack now covers it."
  use NoaWeb.ConnCase, async: false

  alias Noa.{Events, Work}
  alias Noa.WhatsApp.Notifier

  @seed Path.expand("../../../docs/seeds/nyi.json", __DIR__) |> File.read!() |> Jason.decode!()

  setup do
    root = superadmin!()
    {:ok, org} = Noa.Orgs.create_org(%{name: "NotYourIdea", allowed_domains: ["notyouridea.com"]}, root)
    {:ok, _, url} = Noa.Orgs.invite(org, "vedant@notyouridea.com", :org_admin, root)
    vedant = accept!(url, "Vedant")
    {:ok, _, url} = Noa.Orgs.invite(org, "soha@notyouridea.com", :member, vedant)
    soha = accept!(url, "Soha")
    {:ok, _} = Work.load_seed(org.id, @seed)
    {:ok, projects} = Work.projects(org.id, vedant)
    person = Work.person_for(soha, org.id)
    {:ok, _} = Work.set_notifications(person.id, %{notify_via: :whatsapp, phone: "+919800000003"}, soha)
    %{org: org, vedant: vedant, soha: soha, person: person, veriq: Enum.find(projects, &(&1.key == "veriq"))}
  end

  defp on_veriq?(ctx),
    do:
      Enum.any?(
        Work.people(ctx.org.id, ctx.vedant) |> elem(1) |> Enum.find(&(&1.id == ctx.person.id)) |> Map.get(:allocations),
        &(&1.project_id == ctx.veriq.id)
      )

  test "a task on a project you're not on puts you on it, tells you, and shows in your bell", ctx do
    refute on_veriq?(ctx)
    {:ok, task} = Work.create_task(ctx.org.id, %{title: "Prompt plan review", project_id: ctx.veriq.id}, ctx.vedant)
    {:ok, _} = Work.update_task(task.id, %{owner_id: ctx.person.id}, ctx.vedant)
    assert on_veriq?(ctx)

    alloc =
      Events.since(0, org_id: ctx.org.id, limit: 10_000) |> Enum.filter(&(&1.type == "allocation.saved")) |> List.last()

    assert alloc.data["role"] == "contributor" and alloc.data["percent"] == 10
    [{:ok, :whatsapp}] = Notifier.handle(alloc)
    [msg | _] = Noa.WhatsApp.recent(ctx.org.id, ctx.person.id, 5)
    assert msg.body =~ "put you on Veriq" and msg.body =~ "/pack"

    {:ok, feed} = Work.Feed.build(ctx.org.id, ctx.soha)
    assert Enum.any?(feed, &(&1.kind == "pack" and &1.href == "/pack"))

    # Reassigning again, or editing the task, doesn't add a second allocation.
    {:ok, _} = Work.update_task(task.id, %{title: "Prompt plan review v2"}, ctx.vedant)

    assert 1 ==
             Events.since(0, org_id: ctx.org.id, limit: 10_000)
             |> Enum.count(
               &(&1.type == "allocation.saved" and &1.data["person_id"] == ctx.person.id and
                   &1.data["project_id"] == ctx.veriq.id)
             )
  end

  test "editing a task someone owns after they left the project doesn't put them back", ctx do
    {:ok, task} =
      Work.create_task(ctx.org.id, %{title: "Old work", project_id: ctx.veriq.id, owner_id: ctx.person.id}, ctx.vedant)

    {:ok, _} =
      Work.Setup.set_allocation(
        ctx.org.id,
        %{person_id: ctx.person.id, project_id: ctx.veriq.id, percent: 0},
        ctx.vedant
      )

    count = fn ->
      Noa.Work.Allocation
      |> Ash.read!(authorize?: false)
      |> Enum.count(&(&1.person_id == ctx.person.id and &1.project_id == ctx.veriq.id))
    end

    before = count.()

    {:ok, _} = Work.update_task(task.id, %{status: :in_progress}, ctx.vedant)
    assert count.() == before
  end
end
