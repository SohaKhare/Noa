defmodule Noa.Work.Similar do
  @moduledoc """
  Whether two task titles name the same work (2.3). Titles are compared as sets of
  meaningful words ("the", "for" and the like dropped, plurals folded); they match when
  one set holds the other or they share at least 60% of their words.
  """

  @stop ~w(a an the to of for in on and or with by from at is be do task fix add make new update)

  def words(title) do
    title
    |> String.downcase()
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> Enum.reject(&(&1 in @stop))
    |> Enum.map(&String.replace(&1, ~r/(?<=\w{3})s$/, ""))
    |> MapSet.new()
  end

  def same?(a, b) do
    {wa, wb} = {words(a), words(b)}

    cond do
      MapSet.size(wa) == 0 or MapSet.size(wb) == 0 -> false
      MapSet.subset?(wa, wb) or MapSet.subset?(wb, wa) -> true
      true -> MapSet.size(MapSet.intersection(wa, wb)) / MapSet.size(MapSet.union(wa, wb)) >= 0.6
    end
  end

  @doc "The first task in `tasks` whose title names the same work as `title`, or nil."
  def find(title, tasks), do: Enum.find(tasks, &same?(title, &1.title))
end
