defmodule Noa.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Noa.Repo,
      {Phoenix.PubSub, name: Noa.PubSub},
      {AshAuthentication.Supervisor, otp_app: :noa},
      NoaWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Noa.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    NoaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
