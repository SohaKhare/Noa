defmodule Noa.Ops do
  @moduledoc """
  What the superadmin console's System panel shows (3.14): which services are connected,
  background jobs by queue and state, and how far each reader of the event log (the
  graph projector, the notifier) is behind. Nothing here is per workspace.
  """
  import Ecto.Query

  alias Noa.{Events, Repo}

  def status do
    latest = Repo.one(from(e in Events.Event, select: max(e.id))) || 0

    %{
      services: services(),
      readers:
        for {name, label, running?} <- [
              {"graph", "Graph projector", Noa.Graph.enabled?() and running?(Noa.Graph.Projector)},
              {"whatsapp", "Notifier (WhatsApp, Discord, email)", running?(Noa.WhatsApp.Notifier)}
            ] do
          position = Events.position(name)

          %{
            name: name,
            label: label,
            running: running?,
            position: position,
            latest: latest,
            behind: max(latest - position, 0)
          }
        end,
      jobs: jobs()
    }
  end

  defp services do
    whatsapp = Application.get_env(:noa, Noa.WhatsApp, [])

    %{
      database: match?({:ok, _}, Ecto.Adapters.SQL.query(Repo, "SELECT 1", [], timeout: 2_000)),
      graph: Noa.Graph.enabled?() and match?({:ok, "PONG"}, Redix.command(Noa.Graph.Redix, ["PING"], timeout: 1_000)),
      openai: Noa.LLM.configured?(),
      whatsapp: present?(whatsapp[:api_key]) and present?(whatsapp[:phone_number_id]),
      whatsapp_webhook: present?(whatsapp[:webhook_secret]),
      discord: Noa.Ingest.Discord.enabled?(),
      slack: Noa.Ingest.Slack.configured?(),
      github: Noa.GitHub.configured?() or Noa.GitHub.App.configured?(),
      email: Noa.Mailer.delivering?()
    }
  end

  # Jobs by queue and state; completed and discarded only from the last day.
  defp jobs do
    since = DateTime.add(DateTime.utc_now(), -86_400, :second)

    from(j in Oban.Job,
      where: j.state not in ["completed", "discarded", "cancelled"] or j.attempted_at >= ^since,
      group_by: [j.queue, j.state],
      select: {j.queue, j.state, count(j.id)}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), fn {_q, state, n} -> {state, n} end)
    |> Map.new(fn {queue, counts} -> {queue, Map.new(counts)} end)
  end

  defp running?(name), do: is_pid(Process.whereis(name))
  defp present?(v), do: is_binary(v) and v != ""
end
