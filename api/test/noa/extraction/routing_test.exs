defmodule Noa.Extraction.RoutingTest do
  use ExUnit.Case, async: true
  import Noa.Fixtures
  alias Noa.Extraction.Routing

  setup do: %{vocab: vocab()}

  test "1. a mapped channel wins", %{vocab: v} do
    r = Routing.route([line(1, channel: "#veriq")], "emmarie", 0.6, v)
    assert %Routing{project: "veriq", rule: :channel, suggest: nil} = r
  end

  test "1. a confident disagreement is a suggestion, never an override", %{vocab: v} do
    r = Routing.route([line(1, channel: "#veriq")], "emmarie", 0.85, v)
    assert %Routing{project: "veriq", rule: :channel, suggest: "emmarie"} = r
  end

  test "2. thread replies inherit the root's project", %{vocab: v} do
    r = Routing.route([line(1, channel: "#general", thread_project: "tulpa", body: "Veriq too")], nil, nil, v)
    assert %Routing{project: "tulpa", rule: :thread} = r
  end

  test "3. a named project or alias routes in split channels", %{vocab: v} do
    r = Routing.route([line(1, channel: "#general", body: "the film app needs a fix")], "veriq", 0.9, v)
    assert %Routing{project: "emmarie", rule: :named, confidence: 0.9} = r
  end

  test "4. otherwise the model's pick", %{vocab: v} do
    r = Routing.route([line(1, channel: "#general", body: "fix it", author: "Saish")], "veriq", 0.75, v)
    assert %Routing{project: "veriq", rule: :model, confidence: 0.75} = r
  end

  test "5. otherwise the author's only project", %{vocab: v} do
    r = Routing.route([line(1, channel: "#general", body: "fix it", author: "Soha")], nil, nil, v)
    assert %Routing{project: "video-break", rule: :author, confidence: 0.7} = r
  end

  test "6. otherwise ask, offering the author's projects", %{vocab: v} do
    r = Routing.route([line(1, channel: "#general", body: "fix it", author: "Vedant")], nil, nil, v)
    assert %Routing{project: nil, rule: :ask} = r
    assert Enum.sort(r.candidates) == ["emmarie", "tulpa", "veriq"]
  end

  test "two named projects are ambiguous, so the model decides", %{vocab: v} do
    r = Routing.route([line(1, channel: "#general", body: "Veriq vs Tulpa")], "tulpa", 0.8, v)
    assert %Routing{project: "tulpa", rule: :model} = r
  end
end
