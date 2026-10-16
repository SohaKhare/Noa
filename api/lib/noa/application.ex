defmodule Noa.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        Noa.Repo,
        {Phoenix.PubSub, name: Noa.PubSub},
        {AshAuthentication.Supervisor, otp_app: :noa},
        {Oban, Application.fetch_env!(:noa, Oban)},
        Noa.Graph,
        projector(),
        NoaWeb.Endpoint
      ]
      |> Enum.reject(&is_nil/1)

    Supervisor.start_link(children, strategy: :one_for_one, name: Noa.Supervisor)
  end

  defp projector do
    config = Application.get_env(:noa, Noa.Graph, [])
    if config[:url] && config[:projector], do: Noa.Graph.Projector
  end

  @impl true
  def config_change(changed, _new, removed) do
    NoaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
