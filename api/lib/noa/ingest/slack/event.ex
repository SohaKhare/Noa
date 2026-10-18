defmodule Noa.Ingest.Slack.Event do
  @moduledoc "Processes acknowledged Slack Events API deliveries outside the request."
  use Oban.Worker, queue: :slack, max_attempts: 10, unique: [period: 86_400, keys: [:event_id]]

  alias Noa.Ingest.Slack

  def supported?(%{"type" => "event_callback", "event" => %{"type" => type}})
      when type in ["message", "team_join", "user_change", "app_uninstalled"],
      do: true

  def supported?(_), do: false

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payload" => payload}}) do
    event = payload["event"] || %{}

    result =
      case {event["type"], event["subtype"]} do
        {"message", "message_changed"} -> Slack.edit(payload)
        {"message", "message_deleted"} -> Slack.delete(payload)
        {"message", nil} -> Slack.ingest(payload)
        {"team_join", _} -> member(payload, event["user"])
        {"user_change", _} -> member(payload, event["user"])
        {"app_uninstalled", _} -> Noa.Connectors.remove_slack_installation(payload["team_id"])
        _ -> {:ignore, :unsupported}
      end

    job_result(result)
  end

  defp member(payload, user) do
    case Noa.Connectors.org_for_slack_team(payload["team_id"]) do
      nil -> {:ignore, :unknown_workspace}
      org_id -> Slack.ingest_member(org_id, user || %{})
    end
  end

  defp job_result({:error, {:rate_limited, seconds}}), do: {:snooze, seconds}
  defp job_result({:error, reason}) when reason in [:not_read, :unknown_workspace], do: :ok
  defp job_result({:error, reason}), do: {:error, inspect(reason)}
  defp job_result(_accepted_or_ignored), do: :ok
end
