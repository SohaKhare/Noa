defmodule Noa.Extraction.ResultTest do
  use ExUnit.Case, async: true
  import Noa.Fixtures
  alias Noa.Extraction.Result

  setup do
    window = window([line(3), line(4)], [line(2)])
    %{extra: %{window: window, vocabulary: vocab()}}
  end

  defp empty,
    do: %{"tasks" => [], "status_changes" => [], "deadline_changes" => [], "decisions" => [], "scope_changes" => []}

  defp task(attrs) do
    Map.merge(
      %{
        "title" => "Board report PDF export",
        "owner" => "Vedant",
        "due" => "2026-10-16",
        "detail" => nil,
        "project" => "veriq",
        "evidence_sequences" => [3],
        "confidence" => 0.9
      },
      attrs
    )
  end

  defp errors(extra, params) do
    {:error, cs} = Result.from_map(params, extra)
    Ecto.Changeset.traverse_errors(cs, fn {msg, _} -> msg end)
  end

  test "casts a valid response into typed structs", %{extra: extra} do
    params =
      Map.merge(empty(), %{
        "tasks" => [task(%{})],
        "status_changes" => [
          %{
            "task_ref" => "AI Overview lane",
            "status" => "done",
            "blocker" => nil,
            "project" => nil,
            "evidence_sequences" => [4],
            "confidence" => 0.95
          }
        ]
      })

    assert {:ok, %Result{tasks: [t], status_changes: [s]}} = Result.from_map(params, extra)
    assert t.due == ~D[2026-10-16]
    assert s.status == :done
  end

  test "evidence may lean on context but must cite the window", %{extra: extra} do
    assert {:ok, _} = Result.from_map(Map.put(empty(), "tasks", [task(%{"evidence_sequences" => [2, 3]})]), extra)

    assert %{tasks: [%{evidence_sequences: ["must cite at least one message after the Earlier context"]}]} =
             errors(extra, Map.put(empty(), "tasks", [task(%{"evidence_sequences" => [2]})]))

    assert %{tasks: [%{evidence_sequences: ["cites a message that is not in the transcript"]}]} =
             errors(extra, Map.put(empty(), "tasks", [task(%{"evidence_sequences" => [3, 99]})]))

    assert %{tasks: [%{evidence_sequences: ["must cite at least one message"]}]} =
             errors(extra, Map.put(empty(), "tasks", [task(%{"evidence_sequences" => []})]))
  end

  test "owner and project must come from the vocabulary", %{extra: extra} do
    errs = errors(extra, Map.put(empty(), "tasks", [task(%{"owner" => "Rahul", "project" => "acme"})]))
    assert %{tasks: [%{owner: [owner], project: [project]}]} = errs
    assert owner =~ "Rahul is not in the People list"
    assert project =~ "acme is not a project id"
  end

  test "handles resolve as owners", %{extra: extra} do
    assert {:ok, _} = Result.from_map(Map.put(empty(), "tasks", [task(%{"owner" => "@VedantNYI"})]), extra)
  end

  test "due dates more than a day in the past are rejected", %{extra: extra} do
    assert {:ok, _} = Result.from_map(Map.put(empty(), "tasks", [task(%{"due" => "2026-10-14"})]), extra)
    assert %{tasks: [%{due: [msg]}]} = errors(extra, Map.put(empty(), "tasks", [task(%{"due" => "2026-10-10"})]))
    assert msg =~ "in the past"
  end

  test "a blocked status needs a blocker", %{extra: extra} do
    change = %{
      "task_ref" => "Logo pack",
      "status" => "blocked",
      "blocker" => nil,
      "project" => "veriq",
      "evidence_sequences" => [3],
      "confidence" => 0.8
    }

    assert %{status_changes: [%{blocker: ["is required when status is blocked"]}]} =
             errors(extra, Map.put(empty(), "status_changes", [change]))
  end

  test "enums outside the schema are rejected", %{extra: extra} do
    decision = %{
      "statement" => "Use seven families",
      "kind" => "maybe",
      "affects" => [],
      "supersedes_ref" => nil,
      "project" => "veriq",
      "evidence_sequences" => [3],
      "confidence" => 0.9
    }

    assert %{decisions: [%{kind: ["is invalid"]}]} = errors(extra, Map.put(empty(), "decisions", [decision]))
  end

  test "the JSON schema is strict: every property required, no extras" do
    schema = Result.json_schema()
    assert schema["additionalProperties"] == false

    for {_, list} <- schema["properties"] do
      item = list["items"]
      assert item["additionalProperties"] == false
      assert Enum.sort(item["required"]) == item["properties"] |> Map.keys() |> Enum.sort()
    end
  end
end
