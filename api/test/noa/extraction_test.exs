defmodule Noa.ExtractionTest do
  use ExUnit.Case, async: true
  import Noa.Fixtures
  alias Noa.Extraction
  alias Noa.Extraction.Model.Stub

  @empty %{"tasks" => [], "status_changes" => [], "deadline_changes" => [], "decisions" => [], "scope_changes" => []}

  test "a reply in a mapped channel becomes a routed task proposal" do
    [veriq | _] = lines() |> Extraction.windows() |> Enum.filter(&(&1.channel == "#veriq"))

    response =
      Map.put(@empty, "tasks", [
        %{
          "title" => "Board report PDF export",
          "owner" => "Vedant",
          "due" => "2026-10-16",
          "detail" => nil,
          "project" => "veriq",
          "evidence_sequences" => [2, 3],
          "confidence" => 0.88
        }
      ])

    assert {:ok, [p]} = Extraction.extract(veriq, vocab(), model: Stub, response: response)
    assert p.type == :task
    assert p.item.owner == "Vedant"
    assert p.route.project == "veriq" and p.route.rule == :channel
    assert p.evidence == [2, 3]
    assert p.inbox
  end

  test "items in a split channel route by what they name, then by the author" do
    [general] = lines() |> Extraction.windows() |> Enum.filter(&(&1.channel == "#general"))

    response =
      Map.merge(@empty, %{
        "decisions" => [
          %{
            "statement" => "Hooks land in the first two seconds",
            "kind" => "decision",
            "affects" => [],
            "supersedes_ref" => nil,
            "project" => nil,
            "evidence_sequences" => [9],
            "confidence" => 0.9
          }
        ],
        "tasks" => [
          %{
            "title" => "Tag 20 reels for hook analysis",
            "owner" => "Soha",
            "due" => "2026-10-19",
            "detail" => nil,
            "project" => nil,
            "evidence_sequences" => [10, 11],
            "confidence" => 0.86
          }
        ]
      })

    assert {:ok, proposals} = Extraction.extract(general, vocab(), model: Stub, response: response)
    routes = Map.new(proposals, &{&1.type, {&1.route.project, &1.route.rule}})
    assert routes[:decision] == {"video-break", :named}
    assert routes[:task] == {"video-break", :author}
  end

  test "low-confidence items are dropped" do
    [emmarie | _] = Extraction.windows(lines())

    response =
      Map.put(@empty, "deadline_changes", [
        %{
          "task_ref" => "Emmarie demo",
          "new_due" => "2026-10-30",
          "reason" => nil,
          "project" => "emmarie",
          "evidence_sequences" => [8],
          "confidence" => 0.3
        }
      ])

    assert {:ok, []} = Extraction.extract(emmarie, vocab(), model: Stub, response: response)
  end

  test "an invalid response is an error, not a proposal" do
    [emmarie | _] = Extraction.windows(lines())

    response =
      Map.put(@empty, "tasks", [
        %{
          "title" => "x",
          "owner" => nil,
          "due" => nil,
          "detail" => nil,
          "project" => "nope",
          "evidence_sequences" => [8],
          "confidence" => 0.9
        }
      ])

    assert {:error, %Ecto.Changeset{}} = Extraction.extract(emmarie, vocab(), model: Stub, response: response)
  end
end
