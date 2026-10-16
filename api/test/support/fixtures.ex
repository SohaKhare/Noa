defmodule Noa.Fixtures do
  @moduledoc false
  alias Noa.Extraction.{Line, Vocabulary}

  def lines do
    Path.expand("../fixtures/messages.jsonl", __DIR__)
    |> File.stream!()
    |> Stream.reject(&(String.trim(&1) == ""))
    |> Enum.map(&(&1 |> Jason.decode!() |> Line.from_map()))
  end

  def vocab, do: Vocabulary.nyi_seed()

  def line(seq, attrs \\ []) do
    struct!(
      %Line{seq: seq, channel: "#veriq", author: "Vedant", at: ~U[2026-10-15 05:00:00Z], body: "hi", offset: 19_800},
      attrs
    )
  end

  def window(lines, context \\ []) do
    %Noa.Extraction.Window{channel: hd(lines).channel, date: ~D[2026-10-15], lines: lines, context: context}
  end
end
