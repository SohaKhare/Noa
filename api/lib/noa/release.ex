defmodule Noa.Release do
  @moduledoc """
  Tasks for a running release, where Mix is not installed (see docs/deploy.md):

      bin/migrate                                              # migrations (Fly runs this on deploy)
      bin/noa rpc  'Noa.Release.superadmin("you@co.com", "You")'
      bin/noa rpc  'Noa.Release.seed("notyouridea")'           # org map from priv/seeds/nyi.json
      bin/noa rpc  'Noa.Release.graph("notyouridea")'          # rebuild the workspace's graph
      bin/noa rpc  'Noa.Release.github("notyouridea")'         # load recent commits and PRs

  These use `rpc`, so they run inside the live node (next to the projector) instead of
  booting a second copy of the app. `superadmin` generates a password and prints it
  once to the operator's console, unless one is passed as the third argument.
  """
  @app :noa

  require Ash.Query

  def migrate do
    load_app()

    for repo <- repos() do
      try do
        {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
      catch
        # The migrations ran; only closing the pool afterwards was slow. Not a failure.
        :exit, {:timeout, {GenServer, :stop, _}} -> :ok
      end
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc "Creates the platform superadmin (the one account that is not invited)."
  def superadmin(email, name \\ nil, password \\ nil) do
    {password, generated?} =
      if is_binary(password) and byte_size(password) >= 12,
        do: {password, false},
        else: {18 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false), true}

    Noa.Accounts.User
    |> Ash.Changeset.for_create(:create_with_password, %{
      email: email,
      name: name,
      is_superadmin: true,
      password: password
    })
    |> Ash.create(authorize?: false)
    |> case do
      {:ok, user} ->
        IO.puts("Superadmin #{user.email} created.")
        if generated?, do: IO.puts("Password (shown once; change it with Forgot password): #{password}")
        :ok

      {:error, error} ->
        {:error, Exception.message(error)}
    end
  end

  @doc "Loads the org map in `priv/seeds/<file>` into the workspace with `slug`. `sample: true` adds sample work."
  def seed(slug, opts \\ []) do
    org = org!(slug)
    dir = Application.app_dir(@app, "priv/seeds")
    {:ok, counts} = Noa.Work.load_seed(org.id, read!(Path.join(dir, opts[:file] || "nyi.json")))

    if opts[:sample] do
      {:ok, _} = Noa.Work.Seed.load_sample(org.id, read!(Path.join(dir, "nyi-sample-work.json")))
    end

    {:ok, counts}
  end

  @doc "Rebuilds the workspace's FalkorDB graph from its event log."
  def graph(slug) do
    org = org!(slug)
    backfilled = Noa.Work.backfill_events(org.id)

    with {:ok, count} <- Noa.Graph.Projector.rebuild(org.id),
         do: {:ok, %{backfilled: backfilled, replayed: count}}
  end

  @doc "Loads recent commits and pull requests from GitHub for every project with a repo (needs GITHUB_TOKEN for private repos)."
  def github(slug) do
    org = org!(slug)

    Noa.Work.Project
    |> Ash.Query.filter(org_id == ^org.id and not is_nil(repo))
    |> Ash.read!(authorize?: false)
    |> Map.new(fn p -> {p.name, Noa.GitHub.backfill(p)} end)
  end

  defp org!(slug) do
    Noa.Orgs.Org |> Ash.Query.filter(slug == ^slug) |> Ash.read_one!(authorize?: false) ||
      raise "No workspace with slug #{inspect(slug)}. Create it from the superadmin console first."
  end

  defp read!(path), do: path |> File.read!() |> Jason.decode!()

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
