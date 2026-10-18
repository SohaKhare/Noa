defmodule Noa.Ingest.Slack.SyncUsers do
  @moduledoc "Synchronizes Slack workspace members after installation."
  use Oban.Worker, queue: :slack, max_attempts: 10, unique: [period: 300, keys: [:org_id]]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"org_id" => org_id}}) do
    case Noa.Ingest.Slack.sync_users(org_id) do
      {:ok, _count} -> :ok
      {:error, :not_connected} -> :ok
      {:error, {:rate_limited, seconds}} -> {:snooze, seconds}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end
end
