defmodule Noa.DigestTest do
  @moduledoc "The daily digest (2.9): what goes in it, when it is due, and that it goes out once on the person's channel."
  use NoaWeb.ConnCase, async: false
  use Oban.Testing, repo: Noa.Repo

  alias Noa.Work
  alias Noa.Work.Digest

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
    %{org: org, vedant: vedant, saish: saish, person: Work.person_for(saish, org.id)}
  end

  test "lists open tasks with what's late, what waits, and what's blocked", %{person: person, org: org, vedant: vedant} do
    veriq = Enum.find(Work.projects(org.id, vedant) |> elem(1), &(&1.key == "veriq"))
    today = Date.utc_today()

    {:ok, _} =
      Work.create_task(
        org.id,
        %{title: "Board report PDF export", project_id: veriq.id, owner_id: person.id, due_on: Date.add(today, -2)},
        vedant
      )

    text = Digest.build(person, today)
    assert text =~ "Good morning, Saish."
    assert text =~ "Board report PDF export (Veriq, late since #{Date.add(today, -2)})"
    assert text =~ "Your open tasks"
    assert text =~ "http://"
  end

  test "nothing to say means no digest", %{org: org, vedant: vedant} do
    {:ok, abhishek} = Work.Setup.create_person(org.id, %{name: "Nobody Here"}, vedant)
    assert Digest.build(abhishek) == nil
    assert Digest.deliver(abhishek) == :nothing
  end

  test "is due at the person's local time and goes out once per day on WhatsApp", %{person: person, saish: saish} do
    {:ok, _} =
      Work.set_notifications(
        person.id,
        %{notify_via: :whatsapp, phone: "+919800000002", digest_at: ~T[09:00:00], utc_offset: 330},
        saish
      )

    # 09:05 in India is 03:35 UTC.
    assert Enum.any?(Digest.due(~U[2026-10-18 03:35:00Z]), &(&1.id == person.id))
    refute Enum.any?(Digest.due(~U[2026-10-18 04:00:00Z]), &(&1.id == person.id))

    {:ok, _} = Digest.Send.new(%{person_id: person.id, day: "2026-10-18"}) |> Oban.insert()
    {:ok, _} = Digest.Send.new(%{person_id: person.id, day: "2026-10-18"}) |> Oban.insert()
    assert [_] = all_enqueued(worker: Digest.Send)

    assert :ok = perform_job(Digest.Send, %{"person_id" => person.id, "day" => "2026-10-18"})
    [msg | _] = Noa.WhatsApp.recent(person.org_id, person.id, 5)
    assert msg.direction == "out" and msg.body =~ "Your day in Noa"
  end
end
