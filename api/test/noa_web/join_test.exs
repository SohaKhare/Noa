defmodule NoaWeb.JoinTest do
  @moduledoc "Joining from the shared link (1.5): work email only, an org admin approves, and approval sends the normal invite."
  use NoaWeb.ConnCase, async: false
  import Swoosh.TestAssertions

  setup do
    root = superadmin!()
    {:ok, org} = Noa.Orgs.create_org(%{name: "NotYourIdea", allowed_domains: ["notyouridea.com"]}, root)
    {:ok, _, url} = Noa.Orgs.invite(org, "vedant@notyouridea.com", :org_admin, root)
    vedant = accept!(url, "Vedant")
    {:ok, _, url} = Noa.Orgs.invite(org, "saish@notyouridea.com", :member, vedant)
    saish = accept!(url, "Saish")
    flush()
    %{org: org, vedant: vedant, saish: saish}
  end

  defp flush do
    receive do
      {:email, _} -> flush()
    after
      0 -> :ok
    end
  end

  defp ask(org, body), do: json_conn() |> post("/api/join/#{org.slug}", body)

  test "a teammate asks with a work email, an admin approves, and the invite goes to their inbox", ctx do
    %{org: org, vedant: vedant} = ctx

    assert %{"org" => %{"name" => "NotYourIdea", "domains" => ["notyouridea.com"]}} =
             json_conn() |> get("/api/join/#{org.slug}") |> json_response(200)

    assert ask(org, %{name: "Prathamesh", email: "Prathamesh@notyouridea.com"}).status == 202
    # Asking twice is fine and files one request.
    assert ask(org, %{name: "Prathamesh", email: "prathamesh@notyouridea.com"}).status == 202

    [req] =
      signed_in(vedant) |> get("/api/orgs/#{org.id}/join_requests") |> json_response(200) |> Map.fetch!("requests")

    assert req["email"] == "prathamesh@notyouridea.com" and req["name"] == "Prathamesh"

    %{"url" => url} =
      signed_in(vedant)
      |> post("/api/orgs/#{org.id}/join_requests/#{req["id"]}/approve", %{role: "org_admin"})
      |> json_response(200)

    assert_email_sent(fn email -> assert [{_, "prathamesh@notyouridea.com"}] = email.to end)
    pratham = accept!(url, "Prathamesh")
    assert Noa.Orgs.role(pratham.id, org.id) == :org_admin

    assert signed_in(vedant) |> get("/api/orgs/#{org.id}/join_requests") |> json_response(200) == %{"requests" => []}
  end

  test "other domains are refused; members' emails don't leak; members can't approve", ctx do
    %{org: org, saish: saish, vedant: vedant} = ctx
    assert ask(org, %{name: "Mallory", email: "mallory@gmail.com"}) |> json_response(422)
    assert ask(org, %{name: "", email: "x@notyouridea.com"}) |> json_response(422)
    assert json_conn() |> get("/api/join/nope") |> json_response(404)

    # Already a member: the page answers the same as for anyone else.
    assert ask(org, %{name: "Saish", email: "saish@notyouridea.com"}).status == 202
    assert signed_in(vedant) |> get("/api/orgs/#{org.id}/join_requests") |> json_response(200) == %{"requests" => []}

    ask(org, %{name: "Bo", email: "bo@notyouridea.com"})
    assert signed_in(saish) |> get("/api/orgs/#{org.id}/join_requests") |> json_response(200) == %{"requests" => []}

    [req] =
      signed_in(vedant) |> get("/api/orgs/#{org.id}/join_requests") |> json_response(200) |> Map.fetch!("requests")

    assert signed_in(saish) |> post("/api/orgs/#{org.id}/join_requests/#{req["id"]}/approve", %{}) |> json_response(403)

    assert signed_in(vedant) |> post("/api/orgs/#{org.id}/join_requests/#{req["id"]}/reject", %{}) |> json_response(200)

    assert signed_in(vedant)
           |> post("/api/orgs/#{org.id}/join_requests/#{req["id"]}/approve", %{})
           |> json_response(409)
  end
end
