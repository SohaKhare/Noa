defmodule Noa.MCP.Tools do
  @moduledoc """
  The tools Noa's MCP server offers (3.6). Each one is a read of the workspace graph or
  work data as the token's person; `update_task_status` is the only write. Results are
  plain text a model reads well, with sources quoted.
  """
  alias Noa.Work

  @project %{type: "string", description: "Project key or name, e.g. \"veriq\" or \"Emmarie\""}

  def definitions do
    [
      tool(
        "list_projects",
        "List projects",
        "The projects in your workspace, with what each is and who leads it.",
        %{},
        []
      ),
      tool(
        "project_context",
        "Project context",
        "Everything a coding agent should know about a project, generated now from the graph: what it is, repo, people, who knows it best, decisions and why, where work stands. Same as its CLAUDE.md.",
        %{project: @project},
        ["project"]
      ),
      tool(
        "kt_brief",
        "KT brief",
        "The knowledge-transfer brief for someone joining the project.",
        %{project: @project},
        ["project"]
      ),
      tool(
        "my_tasks",
        "My tasks",
        "Your open tasks, with status, due date, blocker and the message each came from. Optionally one project.",
        %{project: @project},
        []
      ),
      tool(
        "ask",
        "Ask Noa",
        "Ask anything about the team's work. Noa answers from the company graph with numbered sources.",
        %{question: %{type: "string"}},
        ["question"]
      ),
      tool(
        "who_knows",
        "Who knows a project",
        "People who know a project best, ranked by what the graph shows they did there (tasks, decisions, messages).",
        %{project: @project},
        ["project"]
      ),
      tool(
        "how_connected",
        "How two things connect",
        "The shortest path in the company graph between two people, projects or tasks, by name.",
        %{from: %{type: "string"}, to: %{type: "string"}},
        ["from", "to"]
      ),
      tool(
        "decisions",
        "Decisions",
        "A project's current decisions, newest first, with who made them and the source.",
        %{project: @project},
        ["project"]
      ),
      tool(
        "update_task_status",
        "Update a task's status",
        "Move one of your tasks to todo, in_progress, blocked or done. Recorded as a change and can be reverted.",
        %{
          task: %{type: "string", description: "Task title (or id)"},
          status: %{type: "string", enum: ["todo", "in_progress", "blocked", "done"]},
          reason: %{type: "string", description: "Why, e.g. the blocker"}
        },
        ["task", "status"]
      )
    ]
  end

  defp tool(name, title, description, props, required) do
    %{
      name: name,
      title: title,
      description: description,
      inputSchema: %{type: "object", properties: props, required: required, additionalProperties: false}
    }
  end

  @doc "Runs a tool: `{:ok, text}`, `{:error, text}` for a failure the model should see, or `:unknown`."
  def call(name, args, user, org_id) do
    run(name, args, user, org_id)
  rescue
    e -> {:error, "Noa couldn't do that: #{Exception.message(e)}"}
  end

  defp run("list_projects", _args, user, org_id) do
    with {:ok, projects} <- Work.projects(org_id, user) do
      {:ok,
       Enum.map_join(projects, "\n", fn p ->
         "- #{p.key}: #{p.name}#{p.about && " — #{p.about}"}#{p.lead && " (lead #{p.lead.name})"}"
       end)}
    end
  end

  defp run("project_context", args, user, org_id) do
    with {:ok, project} <- project(args, user, org_id),
         {:ok, pack} <- Noa.Packs.build(org_id, project.id, user, me(user, org_id)) do
      {:ok, Enum.find(pack.files, &(&1.path == "CLAUDE.md")).content}
    end
  end

  defp run("kt_brief", args, user, org_id) do
    with {:ok, project} <- project(args, user, org_id),
         {:ok, brief} <- Work.brief(org_id, project.id, user, me(user, org_id)) do
      {:ok, Work.Brief.markdown(brief, project.name, user.name)}
    end
  end

  defp run("my_tasks", args, user, org_id) do
    with me when not is_nil(me) <- me(user, org_id) || {:error, "You're not in this workspace's org map yet."},
         {:ok, project} <- if(blank?(args["project"]), do: {:ok, nil}, else: project(args, user, org_id)),
         {:ok, tasks} <- Work.tasks(org_id, user, owner_id: me, open: true, project_id: project && project.id),
         {:ok, projects} <- Work.projects(org_id, user) do
      name = Map.new(projects, &{&1.id, &1.name})

      case tasks do
        [] ->
          {:ok, "No open tasks assigned to you#{project && " in #{project.name}"}."}

        tasks ->
          {:ok,
           Enum.map_join(tasks, "\n", fn t ->
             meta = [
               name[t.project_id],
               t.status,
               t.due_on && "due #{t.due_on}",
               t.blocked_reason && "blocked: #{t.blocked_reason}"
             ]

             quote = t.source && t.source["quote"]
             "- #{t.title} (#{meta |> Enum.filter(& &1) |> Enum.join(", ")})#{quote && "\n  source: \"#{quote}\""}"
           end)}
      end
    end
  end

  defp run("ask", %{"question" => q}, user, org_id) when is_binary(q) and q != "" do
    with {:ok, a} <- Noa.Agent.ask(org_id, String.slice(q, 0, 500), user) do
      sources =
        a.citations
        |> Enum.with_index(1)
        |> Enum.map_join("\n", fn {c, i} ->
          quote = c.source && c.source["quote"]
          "[#{i}] #{c.title}#{c.via && " (#{c.via})"}#{quote && " — \"#{quote}\""}"
        end)

      {:ok, a.answer <> if(sources == "", do: "", else: "\n\nSources:\n" <> sources)}
    end
  end

  defp run("who_knows", args, user, org_id) do
    with {:ok, project} <- project(args, user, org_id),
         {:ok, experts} <- Noa.Graph.Experts.experts(org_id, project.id) do
      case experts do
        [] ->
          {:ok, "Noa hasn't seen enough work on #{project.name} yet to say."}

        rows ->
          {:ok,
           "Who knows #{project.name}, from the graph (finished tasks and decisions weigh 3, open tasks and messages 1):\n" <>
             Enum.map_join(rows, "\n", &"- #{&1.name}: weight #{&1.weight} (#{round(&1.share * 100)}%)")}
      end
    end
  end

  defp run("how_connected", %{"from" => from, "to" => to}, user, org_id) do
    with {:ok, a} <- node_named(from, user, org_id),
         {:ok, b} <- node_named(to, user, org_id),
         {:ok, ids} <- Noa.Graph.View.path(org_id, a, b) do
      case ids do
        [] ->
          {:ok, "#{from} and #{to} aren't connected within 5 steps in the graph."}

        ids ->
          {:ok, rows} =
            Noa.Graph.ro_query(
              org_id,
              "MATCH (n) WHERE n.id IN $ids RETURN n.id AS id, labels(n)[0] AS label, coalesce(n.name, n.title, n.statement, n.text) AS name",
              %{ids: ids}
            )

          names = Map.new(rows, &{&1["id"], "#{&1["name"]} (#{&1["label"]})"})
          {:ok, "Shortest path in the company graph:\n" <> Enum.map_join(ids, " → ", &names[&1])}
      end
    end
  end

  defp run("decisions", args, user, org_id) do
    with {:ok, project} <- project(args, user, org_id),
         {:ok, decisions} <- Work.decisions(org_id, user, project_id: project.id, status: :active),
         {:ok, people} <- Work.people(org_id, user) do
      name = Map.new(people, &{&1.id, &1.name})

      case decisions do
        [] ->
          {:ok, "No decisions recorded for #{project.name} yet."}

        ds ->
          {:ok,
           Enum.map_join(ds, "\n", fn d ->
             quote = d.source && d.source["quote"]

             "- #{d.statement} (#{name[d.made_by_id] || "unknown"}, #{Date.to_iso8601(DateTime.to_date(d.inserted_at))})#{quote && "\n  source: \"#{quote}\""}"
           end)}
      end
    end
  end

  defp run("update_task_status", %{"task" => ref, "status" => status} = args, user, org_id)
       when status in ["todo", "in_progress", "blocked", "done"] do
    with {:ok, task} <- task_named(ref, user, org_id),
         {:ok, updated} <-
           Work.update_task(
             task.id,
             %{
               status: String.to_existing_atom(status),
               blocked_reason: if(status == "blocked", do: args["reason"]),
               reason: args["reason"]
             },
             user
           ) do
      {:ok,
       "\"#{updated.title}\" is now #{updated.status}. It's on the board and in the task's history, and can be reverted."}
    else
      {:error, %Ash.Error.Forbidden{}} -> {:error, "You can't change that task."}
      other -> other
    end
  end

  defp run(name, _args, _user, _org_id) do
    if Enum.any?(definitions(), &(&1.name == name)),
      do: {:error, "Missing or invalid arguments for #{name}."},
      else: :unknown
  end

  ## Resolving names the model uses

  defp me(user, org_id), do: (p = Work.person_for(user, org_id)) && p.id

  defp blank?(v), do: v in [nil, ""]

  defp project(%{"project" => ref}, user, org_id) when is_binary(ref) and ref != "" do
    with {:ok, projects} <- Work.projects(org_id, user) do
      r = String.downcase(String.trim(ref))

      case Enum.find(
             projects,
             &(String.downcase(&1.key) == r or String.downcase(&1.name) == r or
                 Enum.any?(&1.aliases, fn a -> String.downcase(to_string(a.alias)) == r end))
           ) do
        nil -> {:error, "No project called \"#{ref}\". Projects: #{Enum.map_join(projects, ", ", & &1.key)}."}
        p -> {:ok, p}
      end
    end
  end

  defp project(_args, _user, _org_id), do: {:error, "Which project? Pass `project` (key or name)."}

  defp node_named(ref, user, org_id) do
    r = String.downcase(String.trim(ref))

    with {:ok, people} <- Work.people(org_id, user),
         {:ok, projects} <- Work.projects(org_id, user),
         {:ok, tasks} <- Work.tasks(org_id, user) do
      found =
        Enum.find(people, &(String.downcase(&1.name) == r)) ||
          Enum.find(projects, &(String.downcase(&1.key) == r or String.downcase(&1.name) == r)) ||
          Enum.find(tasks, &(String.downcase(&1.title) == r)) ||
          Enum.find(tasks, &String.contains?(String.downcase(&1.title), r))

      if found, do: {:ok, found.id}, else: {:error, "Nothing called \"#{ref}\" among people, projects or tasks."}
    end
  end

  # Your own tasks first, then any task in the workspace; by id, exact title, then a close title.
  defp task_named(ref, user, org_id) do
    me = me(user, org_id)

    with {:ok, tasks} <- Work.tasks(org_id, user) do
      r = String.downcase(String.trim(ref))
      ordered = Enum.sort_by(tasks, &if(&1.owner_id == me, do: 0, else: 1))

      found =
        Enum.find(ordered, &(&1.id == ref)) || Enum.find(ordered, &(String.downcase(&1.title) == r)) ||
          Enum.find(ordered, &Noa.Work.Similar.same?(&1.title, ref))

      if found, do: {:ok, found}, else: {:error, "No task matching \"#{ref}\". Try `my_tasks` to see yours."}
    end
  end
end
