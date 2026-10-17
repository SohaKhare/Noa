defmodule Noa.Work.Brief do
  @moduledoc """
  The KT brief (3.2): what someone joining a project needs on day one, built from the
  project's data and cited, read as the person asking.

  Sections: what it is, where it stands, your tasks (when built for a person), what was
  decided, people to meet (the lead, the people who know it best from the graph, and
  anyone who just moved off it), and recent talk. Follow-up questions go to `@noa`.
  WhatsApp delivery (3.5) sends the same sections.
  """
  import Ecto.Query

  alias Noa.Work

  def build(org_id, project_id, actor, person_id \\ nil) do
    with {:ok, project} <- Ash.get(Work.Project, project_id, actor: actor, load: [:lead]),
         {:ok, people} <- Work.people(org_id, actor),
         {:ok, tasks} <- Work.tasks(org_id, actor, project_id: project_id),
         {:ok, decisions} <- Work.decisions(org_id, actor, project_id: project_id, status: :active),
         {:ok, channels} <- Work.channels(org_id, actor),
         {:ok, leavers} <- Work.previous_owners(org_id, project_id, actor) do
      name = Map.new(people, &{&1.id, &1.name})
      href = "/projects/#{project.key}"
      open = Enum.reject(tasks, &(&1.status == :done))
      today = Date.utc_today()
      late? = &(&1.due_on != nil and Date.compare(&1.due_on, today) == :lt)
      chans = channels |> Enum.filter(&(&1.project_id == project_id)) |> Enum.map(& &1.name)

      sections =
        [
          {"What it is",
           [
             item(project.about || project.name),
             project.lead && item("#{project.lead.name} leads it."),
             chans != [] && item("Talk happens in #{Enum.join(chans, ", ")}.")
           ]},
          {"Where it stands",
           [
             item(
               "#{length(open)} open, #{Enum.count(tasks, &(&1.status == :done))} done" <>
                 count_text(open, :blocked, "blocked") <> count_text(open, :in_progress, "in progress") <> "."
             )
           ] ++
             (open |> Enum.filter(&(&1.status == :blocked)) |> Enum.map(&task_item(&1, href, "Blocked", name))) ++
             (open
              |> Enum.filter(&(late?.(&1) and &1.status != :blocked))
              |> Enum.map(&task_item(&1, href, "Late", name))) ++
             (open
              |> Enum.filter(&(&1.due_on && not late?.(&1)))
              |> Enum.sort_by(& &1.due_on, Date)
              |> Enum.take(1)
              |> Enum.map(&task_item(&1, href, "Next due", name)))},
          person_id &&
            {"Your tasks",
             case Enum.filter(open, &(&1.owner_id == person_id)) do
               [] ->
                 [
                   item(
                     "Nothing assigned to you yet. Ask #{(project.lead && project.lead.name) || "the lead"} where to start."
                   )
                 ]

               mine ->
                 Enum.map(mine, &task_item(&1, href, nil, name))
             end},
          {"Decided",
           case Enum.take(decisions, 6) do
             [] -> [item("No decisions recorded yet.")]
             ds -> Enum.map(ds, &%{text: &1.statement, href: href, source: &1.source})
           end},
          {"People to meet", people_to_meet(org_id, project, people, leavers, person_id)},
          {"Recent talk", recent_talk(org_id, project_id)}
        ]
        |> Enum.reject(&(&1 in [nil, false]))
        |> Enum.map(fn {title, items} -> %{title: title, items: Enum.reject(items, &(&1 in [nil, false]))} end)
        |> Enum.reject(&(&1.items == []))

      {:ok, %{project_id: project.id, person_id: person_id, sections: sections}}
    end
  end

  defp item(text), do: %{text: text, href: nil, source: nil}

  defp count_text(tasks, status, label) do
    case Enum.count(tasks, &(&1.status == status)) do
      0 -> ""
      n -> ", #{n} #{label}"
    end
  end

  defp task_item(t, href, label, name) do
    parts =
      [
        t.title,
        name[t.owner_id] && "owner #{name[t.owner_id]}",
        t.due_on && "due #{Date.to_iso8601(t.due_on)}",
        t.blocked_reason
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" · ")

    %{text: if(label, do: "#{label}: #{parts}", else: parts), href: href, source: t.source}
  end

  # The lead, then who the graph says knows it best, then anyone still taking questions after leaving.
  defp people_to_meet(org_id, project, people, leavers, person_id) do
    name = Map.new(people, &{&1.id, &1.name})

    experts =
      case Noa.Graph.Experts.experts(org_id, project.id) do
        {:ok, rows} -> rows
        _ -> []
      end

    lead = project.lead && [%{id: project.lead.id, why: "leads the project"}]

    known =
      for e <- experts, e.person_id != person_id do
        %{id: e.person_id, why: "knows it well (#{round(e.share * 100)}% of the work Noa has seen)"}
      end

    left =
      for s <- leavers, s.person_id != person_id do
        %{id: s.person_id, why: "worked on it until #{s.starts_on}; ask them until #{s.routes_until}"}
      end

    (left ++ (lead || []) ++ known)
    |> Enum.reject(&(&1.id == person_id))
    |> Enum.uniq_by(& &1.id)
    |> Enum.take(4)
    |> Enum.map(&item("#{name[&1.id]} #{&1.why}."))
  end

  defp recent_talk(org_id, project_id) do
    Noa.Events.Event
    |> where([e], e.org_id == ^org_id and e.type == "message.received")
    |> where([e], fragment("?->>'project_id' = ?", e.data, ^project_id))
    |> order_by(desc: :id)
    |> limit(4)
    |> Noa.Repo.all()
    |> Enum.map(fn e ->
      d = e.data

      %{
        text: "#{d["author"]}: #{d["text"]}",
        href: nil,
        source: %{"channel" => d["channel"], "author" => d["author"], "at" => d["at"], "quote" => d["text"]}
      }
    end)
  end
end
