defmodule NoaWeb.ConnectorController do
  @moduledoc "A workspace's own connectors, managed by org admins: Discord, Slack and GitHub."
  use NoaWeb, :controller

  alias Noa.Connectors

  def connect_discord(conn, %{"org_id" => org_id} = params) do
    with :ok <- Connectors.connect_discord(org_id, params["guild_id"], conn.assigns.current_user),
         do: json(conn, %{ok: true})
  end

  def disconnect(conn, %{"org_id" => org_id, "kind" => kind})
      when kind in ["discord", "slack", "github", "github_app"] do
    with :ok <- Connectors.disconnect(org_id, kind, conn.assigns.current_user), do: json(conn, %{ok: true})
  end

  def disconnect(_conn, _params), do: {:error, :not_found}

  @doc "A new webhook secret for the workspace, returned once."
  def github_secret(conn, %{"org_id" => org_id}) do
    with {:ok, secret} <- Connectors.rotate_github_secret(org_id, conn.assigns.current_user) do
      json(conn, %{secret: secret, webhook: Application.fetch_env!(:noa, :api_base_url) <> "/webhooks/github"})
    end
  end

  def github_token(conn, %{"org_id" => org_id} = params) do
    with :ok <- Connectors.set_github_token(org_id, params["token"], conn.assigns.current_user),
         do: json(conn, %{ok: true})
  end

  @doc "The repositories the workspace's GitHub App installation can see, for picking each project's repo."
  def github_repos(conn, %{"org_id" => org_id}) do
    case Noa.Connectors.installation_for(org_id) do
      nil ->
        json(conn, %{repos: []})

      id ->
        case Noa.GitHub.App.repositories(id) do
          {:ok, repos} -> json(conn, %{repos: repos})
          {:error, _} -> json(conn, %{repos: [], error: "GitHub didn't answer; try again in a moment."})
        end
    end
  end

  @doc "Loads recent commits and pull requests for the workspace's projects with a repo."
  def github_backfill(conn, %{"org_id" => org_id}) do
    actor = conn.assigns.current_user

    if Map.get(actor, :is_superadmin) or Noa.Orgs.admin?(actor.id, org_id) do
      {:ok, projects} = Noa.Work.projects(org_id, actor)

      results =
        for p <- projects, p.repo do
          case Noa.GitHub.backfill(p) do
            {:ok, n} -> %{project: p.name, recorded: n}
            {:error, {:github, status, message}} -> %{project: p.name, error: "GitHub said #{status}: #{message}"}
            {:error, error} -> %{project: p.name, error: inspect(error)}
          end
        end

      json(conn, %{results: results})
    else
      {:error, %Ash.Error.Forbidden{}}
    end
  end
end
