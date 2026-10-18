defmodule Noa.Ingest.Discord.Views do
  @moduledoc false

  def text(content, components \\ []),
    do: %{content: String.slice(content, 0, 1900), components: components, allowed_mentions: %{parse: []}}

  def buttons(org_id, items) do
    %{
      type: 1,
      components:
        Enum.map(items, fn {action, id, label} ->
          %{
            type: 2,
            style: if(String.starts_with?(action, "reject"), do: 4, else: 1),
            label: String.slice(label, 0, 80),
            custom_id: "noa:#{org_id}:#{action}:#{id}"
          }
        end)
    }
  end

  def notification_buttons(org_id, items) do
    allowed = ~w(start done help approve_change reject_change approve reject)

    actions =
      for {key, label} <- items || [],
          [action, id] <- [String.split(key, ":", parts: 2)],
          action in allowed,
          match?({:ok, _}, Ecto.UUID.cast(id)),
          do: {action, id, label}

    if actions == [], do: [], else: [buttons(org_id, Enum.take(actions, 5))]
  end

  def answer(%{answer: answer, citations: citations}) do
    sources =
      citations
      |> Enum.with_index(1)
      |> Enum.take(5)
      |> Enum.map_join("\n", fn {source, n} ->
        href = if source.href && String.starts_with?(source.href, "/"), do: web(source.href), else: web("/ask")
        "[#{n}] #{String.slice(source.title || "Source", 0, 70)} — #{href}"
      end)

    text(String.slice(answer, 0, 1250) <> if(sources == "", do: "", else: "\n\nSources\n" <> sources))
  end

  def inbox(org_id, proposals, changes) do
    items = Enum.take(Enum.map(changes, &{:change, &1}) ++ Enum.map(proposals, &{:proposal, &1}), 5)

    if items == [] do
      text("Nothing pending in your Inbox.")
    else
      content =
        items
        |> Enum.with_index(1)
        |> Enum.map_join("\n\n", fn {{kind, item}, n} ->
          summary =
            if kind == :change,
              do: "#{item.kind}: #{item.old_value || "none"} → #{item.new_value || "none"}",
              else: item.summary

          quote = item.source && item.source["quote"]

          "#{n}. #{String.slice(summary, 0, 160)}" <>
            if(is_binary(quote), do: "\nSource: #{String.slice(quote, 0, 100)}", else: "")
        end)

      components =
        items
        |> Enum.with_index(1)
        |> Enum.map(fn {{kind, item}, n} ->
          suffix = if kind == :change, do: "_change", else: ""

          buttons(org_id, [{"approve" <> suffix, item.id, "Approve #{n}"}, {"reject" <> suffix, item.id, "Reject #{n}"}])
        end)

      text("Pending work (your usual approval permissions apply)\n\n" <> content <> "\n\n" <> web("/inbox"), components)
    end
  end

  def tasks(org_id, tasks) do
    tasks = Enum.take(tasks, 5)

    if tasks == [] do
      text("No open tasks assigned to you.")
    else
      content =
        tasks
        |> Enum.with_index(1)
        |> Enum.map_join("\n", fn {task, n} ->
          "#{n}. #{String.slice(task.title, 0, 150)} — #{task.status}#{if task.due_on, do: ", due #{task.due_on}"}"
        end)

      components =
        tasks
        |> Enum.with_index(1)
        |> Enum.map(fn {task, n} ->
          buttons(org_id, [
            {"start", task.id, "Start #{n}"},
            {"done", task.id, "Done #{n}"},
            {"help", task.id, "Need help #{n}"}
          ])
        end)

      text("Your open tasks\n\n" <> content <> "\n\n" <> web("/"), components)
    end
  end

  def web(path), do: Application.fetch_env!(:noa, :web_origin) <> path
end
