defmodule Noa.FeedUnlinkedTest do
  @moduledoc "The bell works for someone whose account isn't linked to a person in the org map yet."
  use NoaWeb.ConnCase, async: false

  @seed Path.expand("../../../docs/seeds/nyi.json", __DIR__) |> File.read!() |> Jason.decode!()

  test "a member with no person gets a feed, not a crash" do
    root = superadmin!()
    {:ok, org} = Noa.Orgs.create_org(%{name: "NotYourIdea", allowed_domains: ["notyouridea.com"]}, root)
    {:ok, _} = Noa.Work.load_seed(org.id, @seed)
    {:ok, _, url} = Noa.Orgs.invite(org, "newbie@notyouridea.com", :member, root)
    newbie = accept!(url, "Someone New")
    assert Noa.Work.person_for(newbie, org.id) == nil

    assert {:ok, items} = Noa.Work.Feed.build(org.id, newbie)
    assert is_list(items)
    assert signed_in(newbie) |> get("/api/orgs/#{org.id}/feed") |> json_response(200)
  end
end
