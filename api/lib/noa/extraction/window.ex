defmodule Noa.Extraction.Window do
  @moduledoc """
  A channel-local slice of chat sent to the model in one call (docs/extraction.md, "Windows").

  Rules ported from Tulpa v1's distiller: a gap of 30 minutes starts a new session,
  sessions are chunked to 50 lines with 5 lines of overlap, and up to 5 earlier lines
  ride along as context so a reply like "on it" can be grounded in the question above.
  """

  alias Noa.Extraction.Line

  @gap_ms 30 * 60_000
  @max_size 50
  @overlap 5
  @context 5

  defstruct [:channel, :date, lines: [], context: []]

  @type t :: %__MODULE__{channel: String.t(), date: Date.t(), lines: [Line.t()], context: [Line.t()]}

  @doc """
  Groups lines into windows, ordered by channel and then by position.

  Options: `:gap_ms`, `:max_size`, `:overlap`, `:context`.
  """
  @spec build([Line.t()], keyword()) :: [t()]
  def build(lines, opts \\ []) do
    gap = Keyword.get(opts, :gap_ms, @gap_ms)
    max = Keyword.get(opts, :max_size, @max_size)
    overlap = Keyword.get(opts, :overlap, @overlap)
    context = Keyword.get(opts, :context, @context)

    lines
    |> Enum.group_by(& &1.channel)
    |> Enum.sort_by(fn {channel, _} -> channel end)
    |> Enum.flat_map(fn {channel, channel_lines} ->
      sorted = Enum.sort_by(channel_lines, & &1.seq)

      sorted
      |> sessions(gap)
      |> Enum.flat_map(&chunk(&1, max, overlap))
      |> Enum.map(fn chunk ->
        %__MODULE__{
          channel: channel,
          date: Line.local_date(hd(chunk)),
          lines: chunk,
          context: before(sorted, hd(chunk).seq, context)
        }
      end)
    end)
  end

  @doc "Sequence numbers the model may cite: the window's lines and its context."
  @spec citable(t()) :: MapSet.t(integer())
  def citable(%__MODULE__{lines: lines, context: context}), do: MapSet.new(context ++ lines, & &1.seq)

  @doc "Sequence numbers of the window's own lines (each item must cite at least one)."
  @spec own(t()) :: MapSet.t(integer())
  def own(%__MODULE__{lines: lines}), do: MapSet.new(lines, & &1.seq)

  defp sessions([], _gap), do: []

  defp sessions([first | rest], gap) do
    {done, current} =
      Enum.reduce(rest, {[], [first]}, fn line, {done, [prev | _] = current} ->
        if DateTime.diff(line.at, prev.at, :millisecond) > gap,
          do: {[Enum.reverse(current) | done], [line]},
          else: {done, [line | current]}
      end)

    Enum.reverse([Enum.reverse(current) | done])
  end

  defp chunk(lines, max, _overlap) when length(lines) <= max, do: [lines]

  defp chunk(lines, max, overlap) do
    lines
    |> Enum.chunk_every(max, max - overlap)
    # chunk_every leaves a tail that is entirely overlap; it adds nothing new.
    |> Enum.reject(&(length(&1) <= overlap))
  end

  defp before(sorted, seq, n) do
    sorted |> Enum.filter(&(&1.seq < seq)) |> Enum.take(-n)
  end
end
