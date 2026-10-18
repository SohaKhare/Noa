defmodule Noa.Extraction.Prompt do
  @moduledoc """
  The extraction prompt (1.17). The rules keep Tulpa v1's wording where it still
  applies; the context block adds Noa's vocabularies (docs/extraction.md, "Prompt").
  """

  alias Noa.Extraction.{Vocabulary, Window}

  @max_open_tasks 40

  @rules """
  You extract work items from a team chat transcript for a project tracker.
  Rules:
  - Only extract items with clear support in the messages. Do not infer or invent.
  - For each item, cite the exact message sequence numbers (the [N] prefixes) that support it in evidence_sequences. Cite at least one message from the Transcript; messages under Earlier are context only.
  - tasks: new work someone agreed to or was asked to do. title is imperative, at most 80 characters. owner is the person who will do the work, as a name from the People list, or null. "I'll do it" or "on it" means the speaker. When someone asks or assigns another person ("Soha, can you…", "@vedant take this", "assigning X to Prathamesh"), the owner is the person asked, not the speaker. If it is unclear who will do it, owner is null; never default to the speaker. due is an ISO date (YYYY-MM-DD) resolved against the window date, or null.
  - status_changes: a task from Open tasks (or one named in the transcript) moved to todo, in_progress, blocked or done. blocker is required when status is blocked.
  - deadline_changes: an existing task's due date moved. new_due is an ISO date.
  - decisions: a choice the team made (kind "decision") or a conclusion they reached (kind "conclusion"). Not tasks.
  - scope_changes: work added to, removed from or changed in a task or project.
  - Do not propose a task that is already in Open tasks; report a status or deadline change instead.
  - project is an id from the Projects list, or null if unclear. Never invent a project id.
  - confidence is 0.0-1.0.
  - If nothing qualifies, return empty arrays. Prefer precision over recall.
  """

  @doc "System instructions: the rules plus this window's context."
  @spec instructions(Window.t(), Vocabulary.t()) :: String.t()
  def instructions(window, vocab), do: @rules <> "\n" <> context(window, vocab)

  @doc "The user message: earlier context, then the transcript, one `[seq] Author: body` per line."
  @spec transcript(Window.t()) :: String.t()
  def transcript(%Window{lines: lines, context: context}) do
    earlier = if context == [], do: "", else: "Earlier:\n" <> lines_text(context) <> "\n\n"
    earlier <> "Transcript:\n" <> lines_text(lines)
  end

  @spec context(Window.t(), Vocabulary.t()) :: String.t()
  def context(window, vocab) do
    weekday = Calendar.strftime(window.date, "%A")

    channel =
      case Vocabulary.channel_route(vocab, window.channel) do
        id when is_binary(id) -> "#{window.channel} (mapped to project #{id})"
        _ -> "#{window.channel} (no single project; route each item)"
      end

    projects =
      Enum.map_join(vocab.projects, "\n", fn p ->
        aliases = if p.aliases == [], do: "", else: " (aliases: #{Enum.join(p.aliases, ", ")})"
        about = if p.about, do: ". #{p.about}", else: ""
        "- #{p.id}: #{p.name}#{aliases}#{about}"
      end)

    people =
      Enum.map_join(vocab.people, "\n", fn p ->
        handles =
          case p.handles -- [p.name] do
            [] -> ""
            list -> " (also: #{Enum.join(list, ", ")})"
          end

        "- #{p.name}#{if p.title, do: ", #{p.title}", else: ""}#{handles}"
      end)

    tasks =
      case Enum.take(vocab.open_tasks, @max_open_tasks) do
        [] -> "- none"
        list -> Enum.map_join(list, "\n", &"- [#{&1["project"] || &1[:project]}] #{&1["title"] || &1[:title]}")
      end

    """
    Window date: #{Date.to_iso8601(window.date)}, #{weekday}. Channel: #{channel}.
    Projects:
    #{projects}
    People:
    #{people}
    Open tasks:
    #{tasks}
    """
  end

  # Messages in a thread carry its name: work is usually agreed inside the thread.
  defp lines_text(lines), do: Enum.map_join(lines, "\n", &"[#{&1.seq}] #{thread(&1)}#{&1.author}: #{&1.body}")

  defp thread(%{thread: name}) when is_binary(name) and name != "", do: "(thread “#{name}”) "
  defp thread(_), do: ""
end
