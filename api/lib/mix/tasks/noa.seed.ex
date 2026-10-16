defmodule Mix.Tasks.Noa.Seed do
  @shortdoc "Loads an org seed (projects, people, channels, allocations) into a workspace"
  @moduledoc """
  Loads docs/seeds/nyi.json (or another seed file) into an existing workspace (1.23).

      mix noa.seed                       # NYI seed into the workspace with slug "notyouridea"
      mix noa.seed --org notyouridea --file ../docs/seeds/nyi.json
      mix noa.seed --sample              # also loads docs/seeds/nyi-sample-work.json (dev only)

  Safe to run again: rows are matched by key and updated. Create the workspace first
  from the superadmin console.
  """
  use Mix.Task

  require Ash.Query

  @requirements ["app.start"]

  @impl true
  def run(argv) do
    {opts, _} = OptionParser.parse!(argv, strict: [org: :string, file: :string, sample: :boolean])
    slug = opts[:org] || "notyouridea"
    file = opts[:file] || Path.expand("../docs/seeds/nyi.json", File.cwd!())

    org =
      Noa.Orgs.Org |> Ash.Query.filter(slug == ^slug) |> Ash.read_one!(authorize?: false) ||
        Mix.raise("No workspace with slug #{inspect(slug)}. Create it from the superadmin console first.")

    seed = file |> File.read!() |> Jason.decode!()
    {:ok, counts} = Noa.Work.load_seed(org.id, seed)
    Mix.shell().info("Loaded #{Path.relative_to_cwd(file)} into #{org.name}: #{inspect(counts)}")

    if opts[:sample] do
      sample = Path.join(Path.dirname(file), "nyi-sample-work.json")
      {:ok, counts} = Noa.Work.Seed.load_sample(org.id, sample |> File.read!() |> Jason.decode!())
      Mix.shell().info("Loaded sample work: #{inspect(counts)}")
    end
  end
end
