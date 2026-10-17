defmodule NoaWeb.PermissionsTest do
  @moduledoc """
  Permission leak tests (2.16): every workspace endpoint, called by people who should
  not get through. Two workspaces load the same NYI seed; nothing from one may be read
  or changed from the other, guests may only read, and members may not do a lead's job.
  Add every new `/api/orgs/:org_id` route to `@routes`.
  """
  use NoaWeb.ConnCase, async: true

  @seed Path.expand("../../../docs/seeds/nyi.json", __DIR__) |> File.read!() |> Jason.decode!()
  @sample Path.expand("../../../docs/seeds/nyi-sample-work.json", __DIR__) |> File.read!() |> Jason.decode!()

  # {method, path with :org, :task, :proposal, :channel, :change, :member, :invite ids}
  @routes [
    {:get, "/members"},
    {:patch, "/members/:member"},
    {:delete, "/members/:member"},
    {:get, "/invites"},
    {:post, "/invites"},
    {:delete, "/invites/:invite"},
    {:get, "/directory"},
    {:get, "/tasks"},
    {:post, "/tasks"},
    {:patch, "/tasks/:task"},
    {:patch, "/channels/:channel"},
    {:get, "/decisions"},
    {:get, "/changes"},
    {:post, "/ask"},
    {:get, "/shifts"},
    {:get, "/projects/:project/brief"},
    {:get, "/experts"},
    {:get, "/shifts/plan?person_id=:person"},
    {:post, "/shifts"},
    {:post, "/changes/:change/approve"},
    {:post, "/changes/:change/reject"},
    {:post, "/changes/:change/revert"},
    {:get, "/proposals"},
    {:post, "/proposals/:proposal/approve"},
    {:post, "/proposals/:proposal/reject"},
    {:post, "/proposals/:proposal/undo"}
  ]

  @body %{
    "title" => "Leak",
    "status" => "done",
    "due_on" => "2027-01-01",
    "read" => false,
    "role" => "org_admin",
    "email" => "x@notyouridea.com",
    "question" => "what's blocking Veriq?",
    "to_project_id" => ""
  }

  setup do
    root = superadmin!()
    nyi = workspace!(root, "NotYourIdea", "notyouridea.com", ["vedant", "saish", "soha"])
    other = workspace!(root, "Other Co", "other.com", ["olga"])
    %{nyi: nyi, other: other}
  end

  defp workspace!(root, name, domain, [admin | rest]) do
    {:ok, org} = Noa.Orgs.create_org(%{name: name, allowed_domains: [domain]}, root)
    {:ok, _, url} = Noa.Orgs.invite(org, "#{admin}@#{domain}", :org_admin, root)
    lead = accept!(url, String.capitalize(admin))

    users =
      Enum.zip(rest, [:member, :guest])
      |> Map.new(fn {who, role} ->
        {:ok, _, url} = Noa.Orgs.invite(org, "#{who}@#{domain}", role, lead)
        {who, accept!(url, String.capitalize(who))}
      end)

    {:ok, _} = Noa.Work.load_seed(org.id, @seed)
    {:ok, _} = Noa.Work.Seed.load_sample(org.id, @sample)

    # One pending change and one open invite, so every route has a real id to aim at.
    task = Noa.Work.Task |> Ash.read!(authorize?: false) |> Enum.find(&(&1.org_id == org.id))
    member = users["saish"] || lead
    {:ok, _} = Noa.Work.update_task(task.id, %{due_on: ~D[2026-12-24]}, member)
    {:ok, invite, _} = Noa.Orgs.invite(org, "later@#{domain}", :member, lead)

    first = fn resource -> resource |> Ash.read!(authorize?: false) |> Enum.find(&(&1.org_id == org.id)) end

    ids = %{
      task: task.id,
      project: task.project_id,
      person: first.(Noa.Work.Person).id,
      proposal: first.(Noa.Work.Proposal).id,
      channel: first.(Noa.Work.Channel).id,
      change: first.(Noa.Work.Change).id,
      member: first.(Noa.Orgs.Membership).id,
      invite: invite.id
    }

    Map.merge(%{org: org, lead: lead, ids: ids}, Map.new(users, fn {k, v} -> {String.to_atom(k), v} end))
  end

  defp path(org_id, route, ids) do
    "/api/orgs/#{org_id}" <> Regex.replace(~r/:(\w+)/, route, fn _, key -> ids[String.to_atom(key)] end)
  end

  # Bodies carry real ids from the workspace the ids came from, so requests fail on permission, not validation.
  defp call(conn, method, path, ids) do
    body = Map.merge(@body, %{"project_id" => ids.project, "person_id" => ids.person})
    dispatch(conn, @endpoint, method, path, if(method == :get, do: nil, else: body))
  end

  defp leaked?(conn), do: conn.resp_body =~ ~r/Veriq|Emmarie|Board report|Vedant/

  test "signed-out requests get 401 everywhere", %{nyi: nyi} do
    for {method, route} <- @routes do
      conn = call(json_conn(), method, path(nyi.org.id, route, nyi.ids), nyi.ids)
      assert conn.status == 401, "#{method} #{route} gave #{conn.status}"
    end
  end

  test "someone from another workspace gets 404 on every route and sees nothing", %{nyi: nyi, other: other} do
    for {method, route} <- @routes do
      conn = call(signed_in(other.lead), method, path(nyi.org.id, route, nyi.ids), nyi.ids)
      assert conn.status in [403, 404], "#{method} #{route} gave #{conn.status}"
      refute leaked?(conn), "#{method} #{route} leaked: #{conn.resp_body}"
    end
  end

  test "ids from another workspace can't be used through your own", %{nyi: nyi, other: other} do
    for {method, route} <- @routes, String.contains?(route, ":") do
      conn = call(signed_in(other.lead), method, path(other.org.id, route, nyi.ids), nyi.ids)
      assert conn.status in [403, 404], "#{method} #{route} with a foreign id gave #{conn.status}"
      refute leaked?(conn), "#{method} #{route} leaked: #{conn.resp_body}"
    end
  end

  test "a guest can read but not change anything", %{nyi: nyi} do
    for {method, route} <- @routes do
      conn = call(signed_in(nyi.soha), method, path(nyi.org.id, route, nyi.ids), nyi.ids)

      cond do
        method == :get or route == "/ask" -> assert conn.status == 200, "#{method} #{route} gave #{conn.status}"
        # Never a success; usually 403, or 409 when the row isn't in a state anyone could change.
        true -> assert conn.status in 400..499, "guest #{method} #{route} gave #{conn.status}"
      end
    end
  end

  test "a member can't do a lead's job", %{nyi: nyi} do
    lead_only = [
      {:patch, "/members/:member"},
      {:delete, "/members/:member"},
      {:post, "/invites"},
      {:delete, "/invites/:invite"},
      {:patch, "/channels/:channel"},
      {:post, "/changes/:change/approve"},
      {:post, "/changes/:change/reject"},
      {:post, "/shifts"}
    ]

    for {method, route} <- lead_only do
      conn = call(signed_in(nyi.saish), method, path(nyi.org.id, route, nyi.ids), nyi.ids)
      # 404 where the member can't even see the row (invites are admin-only).
      assert conn.status in [403, 404], "member #{method} #{route} gave #{conn.status}"
    end
  end

  test "every workspace route is covered here" do
    routes =
      NoaWeb.Router.__routes__()
      |> Enum.filter(&String.starts_with?(&1.path, "/api/orgs/:org_id"))
      |> MapSet.new(
        &{&1.verb,
         &1.path |> String.replace("/api/orgs/:org_id", "") |> then(fn p -> Regex.replace(~r/:\w+/, p, ":id") end)}
      )

    covered =
      MapSet.new(@routes, fn {m, r} ->
        {m, r |> String.split("?") |> hd() |> then(&Regex.replace(~r/:\w+/, &1, ":id"))}
      end)

    assert MapSet.difference(routes, covered) == MapSet.new()
  end
end
