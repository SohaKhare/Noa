defmodule NoaWeb.SlackOAuthController do
  @moduledoc "Completes a workspace's Slack OAuth installation and returns to Settings."
  use NoaWeb, :controller

  def callback(conn, params) do
    web = Application.fetch_env!(:noa, :web_origin)

    result =
      case params do
        %{"state" => state, "code" => code} -> Noa.Connectors.complete_slack_install(state, code)
        %{"error" => error} -> {:error, error}
        _ -> {:error, :install_invalid}
      end

    case result do
      {:ok, _org_id} -> redirect(conn, external: web <> "/settings?slack=installed")
      {:error, reason} -> redirect(conn, external: web <> "/settings?slack=" <> URI.encode_www_form(error_name(reason)))
    end
  end

  defp error_name({:slack_api, reason, _body}), do: to_string(reason)
  defp error_name({:slack_http, _reason}), do: "slack_unavailable"
  defp error_name(reason), do: to_string(reason)
end
