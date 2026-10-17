defmodule Noa.Agent.Source do
  @moduledoc """
  One thing an answer can cite: a task, a decision or a chat message. `text` is what
  the model reads; `title`, `href` and `source` are what the reader sees.
  """
  @derive {Jason.Encoder, only: [:id, :kind, :title, :text, :href, :project_id, :status, :source]}
  defstruct [
    :id,
    :kind,
    :title,
    :text,
    :href,
    :project_id,
    :status,
    :due,
    :note,
    :source,
    sort: 0,
    late: false,
    people: []
  ]

  @type t :: %__MODULE__{}

  def task(t, ctx) do
    project = ctx.projects[t.project_id]
    owner = ctx.people[t.owner_id]
    due = t.due_on && Date.to_iso8601(t.due_on)
    late = t.status != :done and t.due_on != nil and Date.compare(t.due_on, Date.utc_today()) == :lt

    detail =
      [
        "status #{t.status}",
        t.blocked_reason && "blocked because #{t.blocked_reason}",
        owner && "owner #{owner.name}",
        due && "due #{due}#{if late, do: " (late)"}"
      ]
      |> Enum.reject(&(&1 in [nil, false]))
      |> Enum.join(", ")

    %__MODULE__{
      id: "task:#{t.id}",
      kind: :task,
      title: t.title,
      text: "Task \"#{t.title}\" in #{project && project.name}: #{detail}.",
      href: project && "/projects/#{project.key}",
      project_id: t.project_id,
      status: to_string(t.status),
      due: due,
      note: t.blocked_reason,
      late: late,
      people: Enum.reject([t.owner_id], &is_nil/1),
      source: t.source,
      sort: -unix(t.updated_at)
    }
  end

  def decision(d, ctx) do
    project = ctx.projects[d.project_id]
    by = ctx.people[d.made_by_id]

    %__MODULE__{
      id: "decision:#{d.id}",
      kind: :decision,
      title: d.statement,
      text:
        "Decision in #{project && project.name}#{by && " by #{by.name}"} on #{Date.to_iso8601(DateTime.to_date(d.inserted_at))}: #{d.statement}.",
      href: project && "/projects/#{project.key}",
      project_id: d.project_id,
      status: to_string(d.status),
      people: Enum.reject([d.made_by_id], &is_nil/1),
      source: d.source,
      sort: -unix(d.inserted_at)
    }
  end

  def message(e, _ctx) do
    d = e.data

    %__MODULE__{
      id: "message:#{d["episode_id"]}",
      kind: :message,
      title: "#{d["author"]} in #{d["channel"]}",
      text: "#{d["author"]} wrote in #{d["channel"]} at #{d["at"]}: #{d["text"]}",
      project_id: d["project_id"],
      status: nil,
      people: Enum.reject([d["person_id"]], &is_nil/1),
      source: %{
        "channel" => d["channel"],
        "author" => d["author"],
        "at" => d["at"],
        "quote" => d["text"],
        "episode_id" => d["episode_id"]
      },
      sort: -e.id
    }
  end

  def shift(sh, ctx) do
    person = ctx.people[sh.person_id]
    from = ctx.projects[sh.from_project_id]
    to = ctx.projects[sh.to_project_id]
    name = person && person.name

    %__MODULE__{
      id: "shift:#{sh.id}",
      kind: :shift,
      title: "#{name} moved from #{from && from.name} to #{(to && to.name) || "the bench"}",
      text:
        "#{name} moved from #{from && from.name} to #{(to && to.name) || "the bench"} on #{sh.starts_on}. " <>
          "Ask #{name} about #{from && from.name} until #{sh.routes_until}.",
      href: from && "/projects/#{from.key}",
      project_id: sh.from_project_id,
      people: Enum.reject([sh.person_id], &is_nil/1),
      sort: -unix(sh.inserted_at)
    }
  end

  defp unix(nil), do: 0
  defp unix(%DateTime{} = at), do: DateTime.to_unix(at)
end
