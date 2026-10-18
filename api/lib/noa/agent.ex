defmodule Noa.Agent do
  @moduledoc """
  `@noa` (2.5): answers a question about the org's work with numbered citations.

  1. **Sources.** Tasks, decisions and recent chat messages, read through Ash with the
     asker as the actor, so an answer can only use what that person may see. Each is
     scored against the question: projects and people it names, what it asks about
     (blocked, decided, late, done), then shared words.
  2. **Answer.** With `OPENAI_API_KEY`, one strict-schema call (`Noa.Agent.Answer`)
     that may only cite the sources it was given; without it, `Noa.Agent.Extractive`
     builds a plain answer from the top sources. Either way the answer leads with the
     facts and marks each claim with `[n]`.

  The web Ask page and the chat bots (Discord, WhatsApp) call `ask/3`.
  """
  alias Noa.Agent.{Answer, Extractive, Source}
  alias Noa.Work

  @max_sources 12
  @stop ~w(a an the is are was were be to of in on for and or what whats what's who whom which why how when where
           does do did has have had it its this that these those me my our we you your i about with any anything
           there tell show give brief us please noa can could should would will right now today)

  @doc """
  Answers `question` for `actor` in the org. Returns
  `{:ok, %{answer: text, citations: [Source.t()]}}`; `[n]` in the text is the n-th citation.
  """
  def ask(org_id, question, actor, opts \\ []) do
    with :ok <- member(org_id, actor),
         {:ok, sources, retrieval} <- sources(org_id, question, actor) do
      generator = Keyword.get_lazy(opts, :generator, &generator/0)

      answer = fn -> generator.answer(question, sources, opts) end

      result =
        if generator == Answer,
          do: Noa.LLM.track(org_id, :ask, Noa.LLM.model(), question <> Enum.map_join(sources, "\n", & &1.text), answer),
          else: answer.()

      case result do
        {:ok, %{answer: answer, cited: cited}} ->
          answer = renumber(answer, cited, sources)
          routes = answer.citations |> Enum.map(& &1.via) |> Enum.reject(&is_nil/1) |> Enum.uniq()
          {:ok, Map.put(answer, :retrieval, %{retrieval | routes: routes})}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp generator do
    cond do
      mod = Application.get_env(:noa, __MODULE__, [])[:generator] -> mod
      System.get_env("OPENAI_API_KEY") -> Answer
      true -> Extractive
    end
  end

  defp member(org_id, actor) do
    if Map.get(actor, :is_superadmin) || Noa.Orgs.role(actor.id, org_id), do: :ok, else: {:error, :not_found}
  end

  # The generator cites sources by their number in `sources`; the answer is renumbered
  # so `[1]` is the first citation returned.
  defp renumber(answer, cited, sources) do
    order = cited |> Enum.uniq() |> Enum.filter(&(&1 in 1..length(sources)//1))
    index = order |> Enum.with_index(1) |> Map.new()

    text =
      Regex.replace(~r/\[(\d+)\]/, answer, fn whole, n ->
        case index[String.to_integer(n)] do
          nil -> if(String.to_integer(n) in 1..length(sources)//1, do: "", else: whole)
          i -> "[#{i}]"
        end
      end)

    %{answer: String.trim(text), citations: Enum.map(order, &Enum.at(sources, &1 - 1))}
  end

  @doc """
  The sources for a question, best first, read as `actor`, and how they were found:
  `{:ok, sources, %{store: "falkordb" | "postgres", routes: [...]}}`.
  """
  def sources(org_id, question, actor) do
    with {:ok, projects} <- Work.projects(org_id, actor),
         {:ok, people} <- Work.people(org_id, actor),
         {:ok, tasks} <- Work.tasks(org_id, actor),
         {:ok, decisions} <- Work.decisions(org_id, actor, status: :active),
         {:ok, shifts} <- Work.shifts(org_id, actor) do
      q = String.downcase(question)
      words = q |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true) |> Enum.reject(&(&1 in @stop or String.length(&1) < 3))

      named_projects =
        projects |> Enum.filter(&names?(q, [&1.name, &1.key | Enum.map(&1.aliases, fn a -> to_string(a.alias) end)]))

      named_people = people |> Enum.filter(&names?(q, [&1.name | &1.handles]))
      intent = intent(q)
      ctx = %{projects: Map.new(projects, &{&1.id, &1}), people: Map.new(people, &{&1.id, &1})}

      named = %{projects: MapSet.new(named_projects, & &1.id), people: MapSet.new(named_people, & &1.id)}

      name_words =
        (Enum.flat_map(named_projects, &[&1.name, &1.key]) ++ Enum.map(named_people, & &1.name))
        |> Enum.flat_map(&String.split(String.downcase(&1), ~r/\s+/))

      words = words -- name_words

      shifts = shifts |> Enum.filter(&routing?/1) |> Enum.map(&Source.shift(&1, ctx))
      parsed = %{words: words, projects: named_projects, people: named_people, intent: intent}

      # FalkorDB first (the graph decides what the agent reads); Postgres if the graph is down.
      {candidates, retrieval} =
        case Noa.Agent.Graph.candidates(org_id, parsed) do
          {:ok, found, routes} ->
            {found ++ shifts, %{store: "falkordb", routes: routes}}

          _ ->
            {Enum.map(tasks, &Source.task(&1, ctx)) ++
               Enum.map(decisions, &Source.decision(&1, ctx)) ++
               Enum.map(messages(org_id), &Source.message(&1, ctx)) ++ shifts, %{store: "postgres", routes: []}}
        end

      ranked =
        candidates
        |> Enum.map(&{score(&1, words, named, intent), &1})
        |> Enum.filter(fn {s, _} -> s > 0 end)
        |> Enum.sort_by(fn {s, src} -> {-s, src.sort} end)
        |> Enum.take(@max_sources)
        |> Enum.map(&elem(&1, 1))

      {:ok, ranked, retrieval}
    end
  end

  # A shift is worth citing while its previous owner still takes questions.
  defp routing?(shift), do: shift.routes_until && Date.compare(shift.routes_until, Date.utc_today()) != :lt

  defp names?(q, names) do
    Enum.any?(names, fn n ->
      n = n |> to_string() |> String.downcase()
      n != "" and Regex.match?(~r/(^|[^\p{L}])#{Regex.escape(n)}($|[^\p{L}])/u, q)
    end)
  end

  defp intent(q) do
    [
      blocked: q =~ ~r/block|stuck|waiting on|holding|risk/,
      decided: q =~ ~r/decid|decision|agree|chose|choice|why did/,
      late: q =~ ~r/late|deadline|due|slip|when will|overdue|behind/,
      done: q =~ ~r/done|finish|shipped|complete|merged/,
      who: q =~ ~r/\bwho\b|owner|working on|expert|knows/,
      connects: q =~ ~r/connect|between|related|link|bridge/
    ]
    |> Enum.filter(&elem(&1, 1))
    |> Enum.map(&elem(&1, 0))
    |> MapSet.new()
  end

  defp score(src, words, named, intent) do
    text = String.downcase(src.text)
    overlap = Enum.count(words, &String.contains?(text, &1))
    boost = boost(src, intent)
    in_project = src.project_id != nil and MapSet.member?(named.projects, src.project_id)
    about_person = Enum.any?(src.people, &MapSet.member?(named.people, &1))

    cond do
      # Graph algorithm answers (experts, PageRank, paths) are about the question as a whole.
      src.kind in [:expert, :path] -> if(boost > 0, do: boost + overlap + if(in_project, do: 3, else: 0), else: 0)
      # A project was named: stay inside it.
      MapSet.size(named.projects) > 0 and not in_project -> 0
      # Done work only counts when the question asks about it.
      src.status == "done" and not MapSet.member?(intent, :done) -> 0
      # A specific question (blocked, decided, late...) drops items with nothing to do with it.
      MapSet.size(intent) > 0 and boost == 0 and overlap == 0 -> 0
      true -> overlap + boost + if(in_project, do: 3, else: 0) + if(about_person, do: 3, else: 0)
    end
  end

  defp boost(src, intent) do
    [
      {:blocked, src.status == "blocked", 4},
      {:decided, src.kind == :decision, 4},
      {:late, src.late, 3},
      {:late, src.kind == :task and src.due != nil, 1},
      {:done, src.status == "done", 3},
      {:who, src.kind == :task and src.people != [], 1},
      {:who, src.kind == :shift, 3},
      {:who, src.kind == :expert, 4},
      {:connects, src.kind == :path, 6},
      {:connects, src.kind == :expert, 2},
      {:blocked, src.kind == :shift, 1}
    ]
    |> Enum.filter(fn {i, hit, _} -> hit and MapSet.member?(intent, i) end)
    |> Enum.map(&elem(&1, 2))
    |> Enum.sum()
  end

  # The newest chat messages in the org's read channels (they are in the event log).
  defp messages(org_id) do
    import Ecto.Query

    Noa.Events.Event
    |> where([e], e.org_id == ^org_id and e.type == "message.received")
    |> where([e], fragment("coalesce(?->>'deleted', '') = ''", e.data))
    |> order_by(desc: :id)
    |> limit(300)
    |> Noa.Repo.all()
  end
end
