defmodule Noa.ModelFallbackTest do
  @moduledoc "When the model can't answer, @noa and its MCP tool still reply (with cited sources), and an empty key counts as none."
  use NoaWeb.ConnCase, async: false

  alias Noa.Work

  @seed Path.expand("../../../docs/seeds/nyi.json", __DIR__) |> File.read!() |> Jason.decode!()
  @sample Path.expand("../../../docs/seeds/nyi-sample-work.json", __DIR__) |> File.read!() |> Jason.decode!()

  defmodule Failing do
    @moduledoc false
    def answer(_question, _sources, _opts), do: {:error, %Req.Response{status: 401, body: %{"error" => "bad key"}}}
  end

  setup do
    root = superadmin!()
    {:ok, org} = Noa.Orgs.create_org(%{name: "NotYourIdea", allowed_domains: ["notyouridea.com"]}, root)
    {:ok, _, url} = Noa.Orgs.invite(org, "vedant@notyouridea.com", :org_admin, root)
    vedant = accept!(url, "Vedant")
    {:ok, _} = Work.load_seed(org.id, @seed)
    {:ok, _} = Work.Seed.load_sample(org.id, @sample)
    %{org: org, vedant: vedant}
  end

  test "a failing model falls back to a cited answer", %{org: org, vedant: vedant} do
    assert {:ok, answer} = Noa.Agent.ask(org.id, "What's blocking Veriq?", vedant, generator: Failing)
    assert is_binary(answer.answer) and answer.answer != ""
  end

  test "MCP tools turn any error into readable text, never a crash", %{org: org, vedant: vedant} do
    previous = Application.get_env(:noa, Noa.Agent)
    Application.put_env(:noa, Noa.Agent, generator: Failing)

    on_exit(fn ->
      if previous, do: Application.put_env(:noa, Noa.Agent, previous), else: Application.delete_env(:noa, Noa.Agent)
    end)

    assert {:ok, text} = Noa.MCP.Tools.call("ask", %{"question" => "What's blocking Veriq?"}, vedant, org.id)
    assert is_binary(text)

    reply =
      Noa.MCP.handle(
        %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "tools/call",
          "params" => %{"name" => "ask", "arguments" => %{"question" => "hi"}}
        },
        vedant,
        org.id
      )

    assert Jason.encode!(reply)
  end

  test "an empty OPENAI_API_KEY counts as no key" do
    previous = System.get_env("OPENAI_API_KEY")
    System.put_env("OPENAI_API_KEY", "  ")

    on_exit(fn ->
      if previous, do: System.put_env("OPENAI_API_KEY", previous), else: System.delete_env("OPENAI_API_KEY")
    end)

    refute Noa.LLM.configured?()
    System.put_env("OPENAI_API_KEY", "sk-test")
    assert Noa.LLM.configured?()
  end
end
