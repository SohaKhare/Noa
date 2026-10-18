defmodule NoaWeb.GitHubSetupController do
  @moduledoc """
  Where GitHub sends an org admin after they install Noa's GitHub App (the app's Setup
  URL). The signed `state` from the install link says which workspace; then back to
  Settings → Connectors.
  """
  use NoaWeb, :controller

  def show(conn, params) do
    web = Application.fetch_env!(:noa, :web_origin)

    result =
      case params do
        %{"state" => state, "installation_id" => id} -> Noa.Connectors.complete_github_install(state, id)
        _ -> {:error, :install_invalid}
      end

    case result do
      {:ok, _org_id} -> redirect(conn, external: web <> "/settings?github=installed")
      {:error, reason} -> redirect(conn, external: web <> "/settings?github=" <> to_string(reason))
    end
  end
end
