defmodule Noa.Agent.Source do
  @moduledoc """
  One thing an answer can cite: a task, a decision or a chat message. `text` is what
  the model reads; `title`, `href` and `source` are what the reader sees.
  """
  @derive {Jason.Encoder, only: [:id, :kind, :title, :text, :href, :project_id, :status, :source, :via]}
  defstruct [
    :id,
    :via,
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

  ## From graph rows (Noa.Agent.Graph)

  def graph_task(r) do
    late = r["status"] != "done" and is_binary(r["due"]) and r["due"] < Date.to_iso8601(Date.utc_today())

    detail =
      [
        "status #{r["status"]}",
        r["blocked_reason"] && "blocked because #{r["blocked_reason"]}",
        r["owner"] && "owner #{r["owner"]}",
        r["due"] && "due #{r["due"]}#{if late, do: " (late)"}"
      ]
      |> Enum.reject(&(&1 in [nil, false]))
      |> Enum.join(", ")

    %__MODULE__{
      id: "task:#{r["id"]}",
      kind: :task,
      title: r["title"],
      text: "Task \"#{r["title"]}\" in #{r["project"]}: #{detail}.",
      href: r["project_key"] && "/projects/#{r["project_key"]}",
      project_id: r["project_id"],
      status: r["status"],
      due: r["due"],
      note: r["blocked_reason"],
      late: late,
      people: Enum.reject([r["owner_id"]], &is_nil/1),
      source: graph_source(r),
      sort: 0
    }
  end

  def graph_decision(r) do
    %__MODULE__{
      id: "decision:#{r["id"]}",
      kind: :decision,
      title: r["statement"],
      text:
        "Decision in #{r["project"]}#{r["by"] && " by #{r["by"]}"} on #{String.slice(r["at"] || "", 0, 10)}: #{r["statement"]}.",
      href: r["project_key"] && "/projects/#{r["project_key"]}",
      project_id: r["project_id"],
      status: "active",
      people: Enum.reject([r["by_id"]], &is_nil/1),
      source: graph_source(r),
      sort: -seconds(r["at"])
    }
  end

  def graph_episode(r) do
    %__MODULE__{
      id: "message:#{r["id"]}",
      kind: :message,
      title: "#{r["author"]} in #{r["channel"]}",
      text: "#{r["author"]} wrote in #{r["channel"]} at #{r["at"]}: #{r["text"]}",
      project_id: r["project_id"],
      people: Enum.reject([r["author_id"]], &is_nil/1),
      source: %{
        "channel" => r["channel"],
        "author" => r["author"],
        "at" => r["at"],
        "quote" => r["text"],
        "episode_id" => r["id"]
      },
      sort: -seconds(r["at"])
    }
  end

  def expert(r) do
    %__MODULE__{
      id: "expert:#{r["person_id"]}:#{r["project_id"]}",
      kind: :expert,
      title: "#{r["name"]} knows #{r["project"]}",
      text: "#{r["name"]} knows #{r["project"]} well (weight #{r["weight"]} from tasks, decisions and messages).",
      project_id: r["project_id"],
      people: [r["person_id"]],
      sort: -(r["weight"] || 0)
    }
  end

  def key_person(r) do
    %__MODULE__{
      id: "pagerank:#{r["person_id"]}",
      kind: :expert,
      title: "#{r["name"]} (PageRank)",
      text: "The work runs through #{r["name"]} (PageRank #{Float.round(r["score"] * 1.0, 3)} over the work graph).",
      people: [r["person_id"]],
      sort: -r["score"]
    }
  end

  def bridge(r) do
    %__MODULE__{
      id: "bridge:#{r["person_id"]}",
      kind: :expert,
      title: "#{r["name"]} connects projects",
      text: "#{r["name"]} connects people and projects (betweenness #{Float.round(r["score"] * 1.0, 1)}).",
      people: [r["person_id"]],
      sort: -r["score"]
    }
  end

  def path(%{"names" => names, "a" => a, "b" => b}) when is_list(names) do
    %__MODULE__{
      id: "path:#{a}:#{b}",
      kind: :path,
      title: Enum.join(names, " → "),
      text: "In the graph: #{Enum.join(names, " → ")}.",
      people: [a, b],
      sort: 0
    }
  end

  def path(_), do: nil

  defp graph_source(%{"src_quote" => quote} = r) when is_binary(quote),
    do: %{"channel" => r["src_channel"], "author" => r["src_author"], "at" => r["src_at"], "quote" => quote}

  defp graph_source(_), do: nil

  defp seconds(nil), do: 0

  defp seconds(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, at, _} -> DateTime.to_unix(at)
      _ -> 0
    end
  end

  defp unix(nil), do: 0
  defp unix(%DateTime{} = at), do: DateTime.to_unix(at)
end
