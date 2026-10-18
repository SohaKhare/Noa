defmodule Noa.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    NoaWeb.Plugs.RateLimit.setup()

    children =
      [
        Noa.Repo,
        {Phoenix.PubSub, name: Noa.PubSub},
        {AshAuthentication.Supervisor, otp_app: :noa},
        {Oban, Application.fetch_env!(:noa, Oban)},
        Noa.Graph,
        projector(),
        if(Application.get_env(:noa, Noa.WhatsApp, [])[:notifier], do: Noa.WhatsApp.Notifier),
        Noa.Ingest.Discord.Links,
        discord_children(),
        if(Application.get_env(:noa, Noa.Ingest.Gmail, [])[:enabled], do: Noa.Ingest.Gmail.Poller),
        NoaWeb.Endpoint
      ]
      |> List.flatten()
      |> Enum.reject(&is_nil/1)

    Supervisor.start_link(children, strategy: :one_for_one, name: Noa.Supervisor)
  end

  defp projector do
    config = Application.get_env(:noa, Noa.Graph, [])
    if config[:url] && config[:projector], do: Noa.Graph.Projector
  end

  defp discord_children do
    if Noa.Ingest.Discord.enabled?(), do: [Nostrum.Application, Noa.Ingest.Discord.Consumer], else: []
  end

  @impl true
  def config_change(changed, _new, removed) do
    NoaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
