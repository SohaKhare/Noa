defmodule Noa.LLMTest do
  @moduledoc "LLM usage logging (1.3)."
  use NoaWeb.ConnCase, async: true

  test "model calls are recorded per workspace, failures included, and shown in the console" do
    root = superadmin!()
    {:ok, org} = Noa.Orgs.create_org(%{name: "Usage Co", allowed_domains: ["usage.test"]}, root)

    assert {:ok, "answer"} =
             Noa.LLM.track(org.id, :ask, "test-model", String.duplicate("q", 400), fn -> {:ok, "answer"} end)

    assert {:error, :timeout} = Noa.LLM.track(org.id, :extraction, "test-model", "window", fn -> {:error, :timeout} end)

    usage = Noa.LLM.usage()[org.id]
    assert usage.calls == 2 and usage.errors == 1 and usage.approx_tokens >= 100

    orgs = signed_in(root) |> get("/api/platform/orgs") |> json_response(200)
    mine = Enum.find(orgs["orgs"], &(&1["id"] == org.id))
    assert mine["llm_24h"]["calls"] == 2 and mine["llm_24h"]["errors"] == 1
  end
end
