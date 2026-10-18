defmodule NoaWeb.SetupTest do
  @moduledoc """
  Setting up a fresh workspace from the web app (1.18), the way a second team would
  (4.6): projects, people, allocations and channels by hand, or an org map at once.
  """
  use NoaWeb.ConnCase, async: false
  use Oban.Testing, repo: Noa.Repo

  alias Noa.Work

  @seed Path.expand("../../../docs/seeds/nyi.json", __DIR__) |> File.read!() |> Jason.decode!()

  setup do
    root = superadmin!()
    {:ok, org} = Noa.Orgs.create_org(%{name: "Acme", allowed_domains: ["acme.test"]}, root)
    {:ok, _, url} = Noa.Orgs.invite(org, "ada@acme.test", :org_admin, root)
    ada = accept!(url, "Ada")
    {:ok, _, url} = Noa.Orgs.invite(org, "bo@acme.test", :member, ada)
    bo = accept!(url, "Bo")
    %{org: org, ada: ada, bo: bo}
  end

  defp api(user, method, path, body \\ %{}),
    do: signed_in(user) |> dispatch(@endpoint, method, path, body)

  test "an admin sets up a workspace by hand and Noa starts reading", %{org: org, ada: ada} do
    base = "/api/orgs/#{org.id}"

    assert %{"added" => 2} = api(ada, :post, "#{base}/people/from_members") |> json_response(200)
    assert %{"added" => 0} = api(ada, :post, "#{base}/people/from_members") |> json_response(200)

    %{"person" => cy} =
      api(ada, :post, "#{base}/people", %{name: "Cy Contractor", handles: ["cy#1234"]}) |> json_response(201)

    refute cy["joined"]

    dir = api(ada, :get, "#{base}/directory") |> json_response(200)
    ada_p = Enum.find(dir["people"], &(&1["name"] == "Ada"))
    assert ada_p["joined"] and dir["me"] == ada_p["id"]

    %{"project" => rocket} =
      api(ada, :post, "#{base}/projects", %{name: "Rocket Site", about: "Marketing site", lead_id: ada_p["id"]})
      |> json_response(201)

    assert rocket["key"] == "rocket-site"

    %{"project" => with_repo} =
      api(ada, :patch, "#{base}/projects/#{rocket["id"]}", %{repo: "https://github.com/acme/rocket-site.git"})
      |> json_response(200)

    assert with_repo["repo"] == "acme/rocket-site"
    assert Noa.GitHub.project_for("Acme/Rocket-Site").id == rocket["id"]
    %{"project" => again} = api(ada, :post, "#{base}/projects", %{name: "Rocket Site"}) |> json_response(201)
    assert again["key"] == "rocket-site-2"

    assert %{"allocation" => %{"percent" => 60}} =
             api(ada, :put, "#{base}/allocations", %{person_id: cy["id"], project_id: rocket["id"], percent: 60})
             |> json_response(200)

    assert %{"allocation" => %{"percent" => 80}} =
             api(ada, :put, "#{base}/allocations", %{person_id: cy["id"], project_id: rocket["id"], percent: "80"})
             |> json_response(200)

    %{"channel" => ch} =
      api(ada, :post, "#{base}/channels", %{name: "#rocket", external_id: "998", project_id: rocket["id"]})
      |> json_response(201)

    assert ch["project_id"] == rocket["id"] and ch["read"]

    # A Discord message in that channel now reaches the log, routed to the project.
    {:ok, event} =
      Work.record_message(org.id, %{
        platform: :discord,
        channel: "998",
        channel_id: "998",
        message_id: "m1",
        author_id: "cy#1234",
        author: "cy",
        text: "hero section is done"
      })

    assert event.data["project_id"] == rocket["id"] and event.data["person_id"] == cy["id"]

    # Ending the allocation.
    assert %{"allocation" => %{"ends_on" => _}} =
             api(ada, :put, "#{base}/allocations", %{person_id: cy["id"], project_id: rocket["id"], percent: 0})
             |> json_response(200)

    assert %{"connected" => false, "channels" => []} = api(ada, :get, "#{base}/discord/channels") |> json_response(200)
  end

  test "an admin imports a whole org map", %{org: org, ada: ada} do
    assert %{"loaded" => %{"projects" => 4, "people" => 6}} =
             api(ada, :post, "/api/orgs/#{org.id}/import", %{seed: @seed}) |> json_response(200)

    assert api(ada, :post, "/api/orgs/#{org.id}/import", %{seed: "nope"}) |> json_response(422)
  end

  test "members can't set up the workspace", %{org: org, bo: bo, ada: ada} do
    base = "/api/orgs/#{org.id}"
    api(ada, :post, "#{base}/people/from_members")

    assert api(bo, :post, "#{base}/projects", %{name: "Mine"}) |> json_response(403)
    assert api(bo, :post, "#{base}/people", %{name: "X"}) |> json_response(403)
    assert api(bo, :post, "#{base}/people/from_members") |> json_response(403)
    assert api(bo, :post, "#{base}/channels", %{name: "#x"}) |> json_response(403)
    assert api(bo, :post, "#{base}/import", %{seed: @seed}) |> json_response(403)
  end
end
