defmodule NoaWeb.RawBody do
  @moduledoc "Keeps the exact request bytes for webhook signature checks (`/webhooks/*` only)."

  def read_body(%Plug.Conn{request_path: "/webhooks/" <> _} = conn, opts) do
    with {:ok, body, conn} <- Plug.Conn.read_body(conn, opts) do
      {:ok, body, Plug.Conn.assign(conn, :raw_body, (conn.assigns[:raw_body] || "") <> body)}
    end
  end

  def read_body(conn, opts), do: Plug.Conn.read_body(conn, opts)
end
