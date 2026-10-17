defmodule NoaWeb.MCPTest do
  @moduledoc "The MCP server (3.6) and personal tokens (3.22) on the NYI seed."
  use NoaWeb.ConnCase, async: true

  @seed Path.expand("../../../docs/seeds/nyi.json", __DIR__) |> File.read!() |> Jason.decode!()
  @sample Path.expand("../../../docs/seeds/nyi-sample-work.json", __DIR__) |> File.read!() |> Jason.decode!()

  setup do
    root = superadmin!()
    {:ok, org} = Noa.Orgs.create_org(%{name: "NotYourIdea", allowed_domains: ["notyouridea.com"]}, root)
    {:ok, _, lead_url} = Noa.Orgs.invite(org, "vedant@notyouridea.com", :org_admin, root)
    vedant = accept!(lead_url, "Vedant")
    {:ok, _, url} = Noa.Orgs.invite(org, "saish@notyouridea.com", :member, vedant)
    saish = accept!(url, "Saish")
    {:ok, _, url} = Noa.Orgs.invite(org, "soha@notyouridea.com", :guest, vedant)
    soha = accept!(url, "Soha")
    {:ok, _} = Noa.Work.load_seed(org.id, @seed)
    {:ok, _} = Noa.Work.Seed.load_sample(org.id, @sample)
    %{org: org, root: root, vedant: vedant, saish: saish, soha: soha}
  end

  defp token(user, org) do
    signed_in(user)
    |> post("/api/orgs/#{org.id}/mcp_tokens", %{name: "Claude Code"})
    |> json_response(201)
    |> Map.fetch!("token")
  end

  defp rpc(token, method, params \\ %{}, id \\ 1) do
    json_conn()
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("accept", "application/json, text/event-stream")
    |> post("/mcp", %{jsonrpc: "2.0", id: id, method: method, params: params})
  end

  defp tool(token, name, args \\ %{}) do
    %{"result" => %{"content" => [%{"text" => text}], "isError" => error}} =
      rpc(token, "tools/call", %{name: name, arguments: args}) |> json_response(200)

    {error, text}
  end

  test "handshake and tool list", %{org: org, saish: saish} do
    t = token(saish, org)

    init =
      rpc(t, "initialize", %{
        protocolVersion: "2025-06-18",
        capabilities: %{},
        clientInfo: %{name: "test", version: "1"}
      })
      |> json_response(200)

    assert init["result"]["protocolVersion"] == "2025-06-18"
    assert init["result"]["serverInfo"]["name"] == "noa"
    assert init["result"]["capabilities"]["tools"]

    notified =
      json_conn()
      |> put_req_header("authorization", "Bearer #{t}")
      |> post("/mcp", %{jsonrpc: "2.0", method: "notifications/initialized"})

    assert notified.status == 202

    tools = rpc(t, "tools/list") |> json_response(200) |> get_in(["result", "tools"]) |> Enum.map(& &1["name"])

    assert Enum.sort(tools) ==
             ~w(ask decisions how_connected kt_brief list_projects my_tasks project_context update_task_status who_knows)

    assert rpc(t, "nope") |> json_response(200) |> get_in(["error", "code"]) == -32601
  end

  test "tools answer as the person", %{org: org, saish: saish} do
    t = token(saish, org)

    assert {false, projects} = tool(t, "list_projects")
    assert projects =~ "veriq: Veriq"

    assert {false, context} = tool(t, "project_context", %{project: "Veriq"})
    assert context =~ "# Veriq" and context =~ "Lead: Vedant"

    assert {false, mine} = tool(t, "my_tasks")
    assert mine =~ "Report share links" and mine =~ "source:"

    assert {false, answer} = tool(t, "ask", %{question: "what's blocking Veriq?"})
    assert answer =~ "Brand logo pack import" and answer =~ "Sources:"

    assert {true, unknown} = tool(t, "project_context", %{project: "atlantis"})
    assert unknown =~ "No project called"

    # The one write: recorded as a change, under the lead rules.
    assert {false, moved} = tool(t, "update_task_status", %{task: "report share links", status: "in_progress"})
    assert moved =~ "is now in_progress"

    task =
      Noa.Work.Task
      |> Ash.read!(authorize?: false)
      |> Enum.find(&(&1.org_id == org.id and &1.title == "Report share links"))

    assert task.status == :in_progress
    {:ok, [change]} = Noa.Work.changes(org.id, saish, task_id: task.id)
    assert change.kind == :status and change.requested_by_id == saish.id
  end

  test "a guest's agent can read but not change anything", %{org: org, soha: soha} do
    t = token(soha, org)
    assert {false, _} = tool(t, "decisions", %{project: "veriq"})
    assert {true, denied} = tool(t, "update_task_status", %{task: "Report share links", status: "done"})
    assert denied =~ "can't change"
  end

  test "tokens: shown once, listed without the secret, revocable; bad and foreign tokens get 401",
       %{org: org, root: root, saish: saish} do
    t = token(saish, org)
    list = signed_in(saish) |> get("/api/orgs/#{org.id}/mcp_tokens") |> json_response(200)
    assert [%{"name" => "Claude Code", "id" => id}] = list["tokens"]
    refute inspect(list) =~ t
    assert list["url"] =~ "/mcp"

    assert rpc("noa_not-a-real-token", "ping").status == 401
    assert rpc("", "ping").status == 401

    assert signed_in(saish) |> delete("/api/orgs/#{org.id}/mcp_tokens/#{id}") |> response(204)
    assert rpc(t, "ping").status == 401

    # Another workspace's agent only ever sees its own workspace.
    {:ok, other} = Noa.Orgs.create_org(%{name: "Other Co", allowed_domains: ["other.co"]}, root)
    {:ok, _, url} = Noa.Orgs.invite(other, "boss@other.co", :org_admin, root)
    boss = accept!(url, "Boss")
    ot = token(boss, other)
    assert {false, projects} = tool(ot, "list_projects")
    refute projects =~ "Veriq"
    assert {true, _} = tool(ot, "project_context", %{project: "veriq"})
  end

  test "an agent stops working when its person leaves the workspace", %{org: org, vedant: vedant, saish: saish} do
    t = token(saish, org)
    assert rpc(t, "ping") |> json_response(200)

    membership =
      Noa.Orgs.Membership
      |> Ash.read!(authorize?: false)
      |> Enum.find(&(&1.user_id == saish.id and &1.org_id == org.id))

    assert signed_in(vedant) |> delete("/api/orgs/#{org.id}/members/#{membership.id}") |> json_response(200)
    assert rpc(t, "ping").status == 401
  end
end
