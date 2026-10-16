defmodule NoaWeb.HealthController do
  use NoaWeb, :controller
  def show(conn, _params), do: json(conn, %{ok: true})
end
