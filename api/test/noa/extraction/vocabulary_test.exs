defmodule Noa.Extraction.VocabularyTest do
  use ExUnit.Case, async: true
  alias Noa.Extraction.Vocabulary

  setup do: %{vocab: Vocabulary.nyi_seed()}

  test "resolves people by name or handle, ignoring case and @", %{vocab: v} do
    assert Vocabulary.person(v, "vedant").id == "ve"
    assert Vocabulary.person(v, "@VedantNYI").id == "ve"
    assert Vocabulary.person(v, "Saish-NYI").id == "sa"
    assert Vocabulary.person(v, "Rahul") == nil
  end

  test "finds project names and aliases only as whole words", %{vocab: v} do
    assert Vocabulary.projects_named_in(v, "the film app crashed") == ["emmarie"]
    assert Vocabulary.projects_named_in(v, "VB research is due") == ["video-break"]
    assert Vocabulary.projects_named_in(v, "VBA macros") == []
    assert Vocabulary.projects_named_in(v, "Veriq and Tulpa") |> Enum.sort() == ["tulpa", "veriq"]
  end

  test "channel routes: mapped, split, not read", %{vocab: v} do
    assert Vocabulary.channel_route(v, "#veriq") == "veriq"
    assert Vocabulary.channel_route(v, "#general") == :split
    assert Vocabulary.channel_route(v, "#random") == nil
  end
end
