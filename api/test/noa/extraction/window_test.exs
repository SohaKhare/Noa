defmodule Noa.Extraction.WindowTest do
  use ExUnit.Case, async: true
  import Noa.Fixtures
  alias Noa.Extraction.Window

  test "splits a channel on a 30-minute gap and keeps channels apart" do
    windows = Window.build(lines())
    shape = Enum.map(windows, &{&1.channel, Enum.map(&1.lines, fn l -> l.seq end)})

    assert shape == [
             {"#emmarie", [6, 7, 8]},
             {"#general", [9, 10, 11, 12]},
             {"#veriq", [1, 2, 3]},
             {"#veriq", [4, 5]}
           ]
  end

  test "the second session carries the lines before it as context" do
    [_, _, _, later] = Window.build(lines())
    assert Enum.map(later.context, & &1.seq) == [1, 2, 3]
    assert MapSet.equal?(Window.own(later), MapSet.new([4, 5]))
    assert MapSet.equal?(Window.citable(later), MapSet.new([1, 2, 3, 4, 5]))
  end

  test "dates are the author's local date" do
    late = line(1, at: ~U[2026-10-15 19:00:00Z], offset: 19_800)
    assert [%Window{date: ~D[2026-10-16]}] = Window.build([late])
  end

  test "long sessions are chunked with overlap and no overlap-only tail" do
    long = for s <- 1..95, do: line(s, at: DateTime.add(~U[2026-10-15 05:00:00Z], s * 60))
    windows = Window.build(long)

    assert Enum.map(windows, &{hd(&1.lines).seq, List.last(&1.lines).seq}) == [{1, 50}, {46, 95}]
    assert Enum.map(Enum.at(windows, 1).context, & &1.seq) == [41, 42, 43, 44, 45]
  end
end
