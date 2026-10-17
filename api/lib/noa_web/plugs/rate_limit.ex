defmodule NoaWeb.Plugs.RateLimit do
  @moduledoc """
  A small fixed-window rate limit (4.3), in ETS, per node. Enough for one Fly machine;
  a second machine would want a shared store.

      plug(NoaWeb.Plugs.RateLimit, name: :auth, limit: 10, per: 60, by: :ip)
      plug(NoaWeb.Plugs.RateLimit, name: :ask, limit: 20, per: 60, by: :user)

  Only writes (POST, PUT, PATCH, DELETE) count. Over the limit answers 429 with
  `retry-after`. `config :noa, NoaWeb.Plugs.RateLimit, enabled: false` turns it off (tests).
  """
  import Plug.Conn

  @table __MODULE__

  @doc "Creates the counter table. Called once from `Noa.Application`."
  def setup do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    end

    :ok
  end

  def init(opts), do: Map.new(opts)

  def call(%{method: method} = conn, opts) when method in ~w(POST PUT PATCH DELETE) do
    if Application.get_env(:noa, __MODULE__, [])[:enabled] == false do
      conn
    else
      check(conn, opts)
    end
  end

  def call(conn, _opts), do: conn

  defp check(conn, %{name: name, limit: limit, per: per} = opts) do
    now = System.system_time(:second)
    window = div(now, per)
    key = {name, who(conn, opts[:by]), window}
    count = :ets.update_counter(@table, key, 1, {key, 0})
    if count == 1, do: prune(name, window)

    if count > limit do
      conn
      |> put_resp_header("retry-after", Integer.to_string((window + 1) * per - now))
      |> put_resp_content_type("application/json")
      |> send_resp(429, ~s({"error":"rate_limited","message":"Too many requests. Wait a moment and try again."}))
      |> halt()
    else
      conn
    end
  end

  defp who(conn, :user), do: (conn.assigns[:current_user] && conn.assigns.current_user.id) || ip(conn)
  defp who(conn, _), do: ip(conn)

  # Behind Fly's proxy the client address is in fly-client-ip.
  defp ip(conn) do
    case get_req_header(conn, "fly-client-ip") do
      [ip | _] -> ip
      _ -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end

  # Drop this limiter's older windows when a new one starts.
  defp prune(name, window) do
    :ets.select_delete(@table, [{{{name, :_, :"$1"}, :_}, [{:<, :"$1", window}], [true]}])
  end
end
