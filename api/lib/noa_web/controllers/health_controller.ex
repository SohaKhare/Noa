defmodule NoaWeb.HealthController do
  @moduledoc "Health check for the load balancer: 200 when Postgres answers. The graph is reported, not required."
  use NoaWeb, :controller

  def show(conn, _params) do
    db = match?({:ok, _}, Ecto.Adapters.SQL.query(Noa.Repo, "SELECT 1", [], timeout: 2_000))
    graph = Noa.Graph.enabled?() and match?({:ok, "PONG"}, Redix.command(Noa.Graph.Redix, ["PING"], timeout: 1_000))

    conn
    |> put_status(if db, do: 200, else: 503)
    |> json(%{ok: db, db: db, graph: graph})
  end
end
