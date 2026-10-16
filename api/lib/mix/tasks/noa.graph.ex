defmodule Mix.Tasks.Noa.Graph do
  @shortdoc "Rebuilds a workspace's FalkorDB graph from the event log"
  @moduledoc """
  Rebuilds a workspace's graph from its event log (1.10). First appends events for any
  rows written before the event log existed, so nothing is left out.

      mix noa.graph                  # the workspace with slug "notyouridea"
      mix noa.graph --org acme

  Needs FalkorDB: `docker compose --profile graph up -d`.
  """
  use Mix.Task

  require Ash.Query

  @requirements ["app.start"]

  @impl true
  def run(argv) do
    {opts, _} = OptionParser.parse!(argv, strict: [org: :string])
    slug = opts[:org] || "notyouridea"

    org =
      Noa.Orgs.Org |> Ash.Query.filter(slug == ^slug) |> Ash.read_one!(authorize?: false) ||
        Mix.raise("No workspace with slug #{inspect(slug)}.")

    backfilled = Noa.Work.backfill_events(org.id)

    case Noa.Graph.Projector.rebuild(org.id) do
      {:ok, count} ->
        Mix.shell().info("#{org.name}: #{backfilled} old rows logged, #{count} events replayed into the graph")

      {:error, error} ->
        Mix.raise("Graph rebuild failed: #{inspect(error)}")
    end
  end
end
