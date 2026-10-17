defmodule Noa.Agent.Extractive do
  @moduledoc """
  Answers without a model, from the top sources (2.5). Used when no OpenAI key is set,
  and in tests. Plain and correct rather than clever: it lists what it found, grouped
  the way the question asks (blocked, decided, late), each with its citation.
  """

  def answer(question, [], _opts) do
    {:ok,
     %{answer: "I couldn't find anything about \"#{String.trim(question)}\" in the projects you can see.", cited: []}}
  end

  def answer(question, sources, _opts) do
    q = String.downcase(question)
    numbered = Enum.with_index(sources, 1)

    picks =
      cond do
        q =~ ~r/block|stuck|waiting on|holding|risk/ ->
          Enum.filter(numbered, fn {s, _} -> s.status == "blocked" or s.late end)

        q =~ ~r/decid|decision|agree|chose|choice/ ->
          Enum.filter(numbered, fn {s, _} -> s.kind == :decision end)

        q =~ ~r/late|deadline|due|slip|overdue|behind/ ->
          Enum.filter(numbered, fn {s, _} -> s.kind == :task and s.due != nil end)

        q =~ ~r/\bwho\b|owner|ask/ ->
          Enum.filter(numbered, fn {s, _} -> s.kind == :shift or (s.kind == :task and s.people != []) end)

        true ->
          []
      end
      |> case do
        [] -> Enum.take(numbered, 5)
        found -> Enum.take(found, 6)
      end

    lines = Enum.map(picks, fn {s, i} -> "- #{line(s)} [#{i}]" end)
    {:ok, %{answer: Enum.join(lines, "\n"), cited: Enum.map(picks, &elem(&1, 1))}}
  end

  defp line(%{kind: :task} = s) do
    case s do
      %{status: "blocked"} -> "#{s.title} is blocked#{s.note && ": #{s.note}"}"
      %{late: true} -> "#{s.title} is late (was due #{s.due})"
      %{status: "done"} -> "#{s.title} is done"
      %{due: due} when is_binary(due) -> "#{s.title}, #{status(s.status)}, due #{due}"
      _ -> "#{s.title}, #{status(s.status)}"
    end
  end

  defp line(%{kind: :decision} = s), do: "Decided: #{s.title}"
  defp line(%{kind: :shift} = s), do: s.text |> String.trim_trailing(".")
  defp line(%{kind: :message} = s), do: "#{s.title}: \"#{s.source["quote"]}\""

  defp status("in_progress"), do: "in progress"
  defp status("todo"), do: "to do"
  defp status(other), do: other
end
