defmodule Noa.Ingest.Slack.Backfill do
  @moduledoc "Loads the newest permitted history page for a newly mapped Slack channel."
  use Oban.Worker, queue: :slack, max_attempts: 10, unique: [period: 300, keys: [:org_id, :channel_id]]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"org_id" => org_id, "channel_id" => channel_id}}) do
    case Noa.Ingest.Slack.backfill(org_id, channel_id) do
      {:ok, _count} -> :ok
      {:error, :not_connected} -> :ok
      {:error, {:rate_limited, seconds}} -> {:snooze, seconds}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end
end
