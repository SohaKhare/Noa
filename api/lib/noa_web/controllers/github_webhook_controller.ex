defmodule NoaWeb.GitHubWebhookController do
  @moduledoc """
  GitHub's webhook (3.7). Deliveries from Noa's GitHub App are checked with the app's
  secret and belong to the workspace that installed it; hand-added webhooks are checked
  with the secret of the workspace that owns the repository. Then it hands push, pull_request and workflow_run events to
  `Noa.GitHub`. Redeliveries are harmless: each commit, PR state and run is recorded once.
  """
  use NoaWeb, :controller

  def receive(conn, params) do
    raw = conn.assigns[:raw_body] || ""
    signature = conn |> get_req_header("x-hub-signature-256") |> List.first()
    event = conn |> get_req_header("x-github-event") |> List.first()
    installation = get_in(params, ["installation", "id"])
    repo = get_in(params, ["repository", "full_name"])

    cond do
      # From Noa's GitHub App: signed with the app's secret; the installation says whose it is.
      installation && Noa.GitHub.valid_app_signature?(raw, signature) ->
        case {event, Noa.Connectors.org_for_installation(installation)} do
          {"installation", _} -> reply(conn, Noa.GitHub.handle(event, params))
          {_, nil} -> json(conn, %{ignored: :unknown_installation})
          {_, org_id} -> reply(conn, Noa.GitHub.handle(event, params, org_id))
        end

      # A webhook an org admin added by hand, signed with their workspace's secret.
      Noa.GitHub.valid_signature?(raw, signature, repo) ->
        reply(conn, Noa.GitHub.handle(event, params))

      true ->
        send_resp(conn, 401, "bad signature")
    end
  end

  defp reply(conn, {:ok, n}), do: json(conn, %{recorded: n})
  defp reply(conn, {:ignore, reason}), do: json(conn, %{ignored: reason})
end
