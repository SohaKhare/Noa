defmodule Noa.Meetings.Process do
  @moduledoc false
  use Oban.Worker, queue: :extraction, max_attempts: 3, unique: [period: 300, keys: [:meeting_id]]

  @impl true
  def perform(%Oban.Job{args: %{"meeting_id" => id, "user_id" => user_id}} = job) do
    with {:ok, actor} <- Ash.get(Noa.Accounts.User, user_id, actor: %{id: user_id}) do
      case Noa.Meetings.process(id, actor) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          if job.attempt >= job.max_attempts, do: Noa.Meetings.fail(id, "minutes_failed", actor)
          {:error, reason}
      end
    end
  end
end
