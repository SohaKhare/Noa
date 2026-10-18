defmodule NoaWeb.PlatformStatusTest do
  @moduledoc "The superadmin console's System panel (3.14): services, jobs and event-log readers, for superadmins only."
  use NoaWeb.ConnCase, async: false

  test "superadmins see services, readers and jobs; workspace admins don't" do
    root = superadmin!()
    {:ok, org} = Noa.Orgs.create_org(%{name: "Acme", allowed_domains: ["acme.test"]}, root)
    {:ok, _, url} = Noa.Orgs.invite(org, "ada@acme.test", :org_admin, root)
    ada = accept!(url, "Ada")

    body = signed_in(root) |> get("/api/platform/status") |> json_response(200)
    assert body["services"]["database"] == true
    assert Map.has_key?(body["services"], "whatsapp") and Map.has_key?(body["services"], "openai")
    assert [%{"name" => "graph", "behind" => _}, %{"name" => "whatsapp"}] = body["readers"]
    assert is_map(body["jobs"])

    assert signed_in(ada) |> get("/api/platform/status") |> json_response(403)
  end
end
