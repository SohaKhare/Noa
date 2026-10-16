defmodule Noa.Extraction.Model.OpenAITest do
  # Drives InstructorLite's real prompt, parsing and retry loop with canned responses.
  use ExUnit.Case, async: true
  import Noa.Fixtures
  alias Noa.Extraction.Model.OpenAI

  defmodule FakeAdapter do
    @behaviour InstructorLite.Adapter
    alias InstructorLite.Adapters.ResponsesCompatible

    @impl true
    def send_request(params, _opts) do
      send(self(), {:request, params})
      [next | rest] = Process.get(:responses)
      Process.put(:responses, rest)

      {:ok,
       %{
         "id" => "resp_#{length(rest)}",
         "output" => [%{"role" => "assistant", "content" => [%{"text" => Jason.encode!(next)}]}]
       }}
    end

    @impl true
    defdelegate initial_prompt(params, opts), to: ResponsesCompatible
    @impl true
    defdelegate retry_prompt(params, resp, errors, response, opts), to: ResponsesCompatible
    @impl true
    defdelegate parse_response(response, opts), to: ResponsesCompatible
  end

  @empty %{"tasks" => [], "status_changes" => [], "deadline_changes" => [], "decisions" => [], "scope_changes" => []}

  test "sends strict-schema instructions and retries with validation errors" do
    [_, _, veriq, _] = Noa.Extraction.windows(lines())
    bad = Map.put(@empty, "tasks", [task("Rahul")])
    good = Map.put(@empty, "tasks", [task("Vedant")])
    Process.put(:responses, [bad, good])

    assert {:ok, result} = OpenAI.extract(veriq, vocab(), adapter: FakeAdapter, adapter_context: [])
    assert [%{owner: "Vedant"}] = result.tasks

    assert_received {:request, first}
    assert first.instructions =~ "Window date: 2026-10-15, Thursday"
    assert first.instructions =~ "veriq: Veriq (aliases: reports, AI rep)"
    assert first.text.format.strict
    assert first.text.format.schema == Noa.Extraction.Result.json_schema()
    assert [%{content: transcript}] = first.input
    assert transcript =~ "[3] Vedant: on it, Board report PDF export by Friday"

    assert_received {:request, retry}
    assert inspect(retry) =~ "Rahul is not in the People list"
  end

  test "gives up after the retries are spent" do
    [_, _, veriq, _] = Noa.Extraction.windows(lines())
    bad = Map.put(@empty, "tasks", [task("Rahul")])
    Process.put(:responses, [bad, bad, bad])

    assert {:error, %Ecto.Changeset{}} = OpenAI.extract(veriq, vocab(), adapter: FakeAdapter, adapter_context: [])
  end

  defp task(owner) do
    %{
      "title" => "Board report PDF export",
      "owner" => owner,
      "due" => "2026-10-16",
      "detail" => nil,
      "project" => "veriq",
      "evidence_sequences" => [3],
      "confidence" => 0.9
    }
  end
end
