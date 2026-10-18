defmodule Noa.Work.History do
  @moduledoc """
  Noa works from recent chat only. Loading a channel's past fetches the last
  `history_days` (default 30, `config :noa, Noa.Work, history_days: 30`), and extraction
  ignores anything older, so month-old "on it, by Friday" never lands as new work.
  """

  def days, do: Application.get_env(:noa, Noa.Work, [])[:history_days] || 30
  def cutoff, do: DateTime.add(DateTime.utc_now(), -days() * 86_400, :second)

  @doc "Whether something said at `at` (DateTime or ISO 8601) is older than the window."
  def historical?(%DateTime{} = at), do: DateTime.compare(at, cutoff()) == :lt

  def historical?(at) when is_binary(at) do
    case DateTime.from_iso8601(at) do
      {:ok, at, _} -> historical?(at)
      _ -> false
    end
  end

  def historical?(_), do: false
end
