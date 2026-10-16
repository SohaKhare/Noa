defmodule Mix.Tasks.Noa.Extract do
  @shortdoc "Runs extraction over a JSONL file of chat lines (the 0.9 spike)"
  @moduledoc """
  Runs `Noa.Extraction` over chat lines and prints a review table.

      mix noa.extract --dry-run ../docs/seeds/messages.example.jsonl
      OPENAI_API_KEY=... mix noa.extract path/to/messages.jsonl

  Each line of the file is a JSON object with `seq`, `channel`, `author`, `at`
  (ISO 8601 with offset) and `body`. The vocabulary is `docs/seeds/nyi.json`.
  `--dry-run` prints the windows and the first request without calling a model.
  Scoring is described in docs/extraction.md, "Spike (0.9)".
  """

  use Mix.Task

  alias Noa.Extraction
  alias Noa.Extraction.{Line, Vocabulary}

  @impl Mix.Task
  def run(args) do
    {opts, [path], _} = OptionParser.parse(args, strict: [dry_run: :boolean])
    Mix.Task.run("app.start")

    vocab = Vocabulary.nyi_seed()

    lines =
      path
      |> File.stream!()
      |> Stream.reject(&(String.trim(&1) == ""))
      |> Enum.map(&(&1 |> Jason.decode!() |> Line.from_map()))

    windows = Extraction.windows(lines)
    Mix.shell().info("#{length(lines)} lines, #{length(windows)} windows\n")

    if opts[:dry_run] do
      for w <- windows,
          do: Mix.shell().info("#{w.channel} #{w.date}: seq #{hd(w.lines).seq}..#{List.last(w.lines).seq}")

      first = hd(windows)

      Mix.shell().info(
        "\nFirst request:\n" <> Jason.encode!(Extraction.Model.OpenAI.request(first, vocab), pretty: true)
      )
    else
      Enum.each(windows, &report(&1, vocab))
    end
  end

  defp report(window, vocab) do
    Mix.shell().info("## #{window.channel}, #{window.date}\n")

    case Extraction.extract(window, vocab) do
      {:ok, []} ->
        Mix.shell().info("Nothing extracted.\n")

      {:ok, proposals} ->
        Mix.shell().info(
          "| Type | Item | Route | Owner / status | Due | Conf | Evidence |\n| --- | --- | --- | --- | --- | --- | --- |"
        )

        for p <- proposals do
          i = p.item
          what = Map.get(i, :title) || Map.get(i, :statement) || Map.get(i, :task_ref) || Map.get(i, :summary)
          who = Map.get(i, :owner) || Map.get(i, :status) || Map.get(i, :kind) || Map.get(i, :change)
          due = Map.get(i, :due) || Map.get(i, :new_due)

          route =
            "#{p.route.project || "ask"} (#{p.route.rule})#{if p.route.suggest, do: ", move to #{p.route.suggest}?"}"

          Mix.shell().info(
            "| #{p.type} | #{what} | #{route} | #{who} | #{due} | #{p.confidence} | #{inspect(i.evidence_sequences)} |"
          )
        end

        Mix.shell().info("")

      {:error, %Ecto.Changeset{} = cs} ->
        Mix.shell().error("Invalid after retries: #{inspect(Ecto.Changeset.traverse_errors(cs, &elem(&1, 0)))}\n")

      {:error, reason} ->
        Mix.shell().error("Failed: #{inspect(reason)}\n")
    end
  end
end
