defmodule Noa.LLM do
  @moduledoc """
  LLM usage (1.3). `track/5` wraps a model call and records which workspace made it,
  what for, which model, how long it took, whether it worked, and its size in
  characters (tokens are roughly characters / 4). The superadmin console reads
  `usage/1`. Logging never breaks the call: a failed insert is only logged.
  """
  import Ecto.Query
  require Logger

  alias Noa.Repo

  @doc "Runs `fun` (a model call returning `{:ok, _}` or `{:error, _}`) and records it."
  def track(org_id, operation, model, input, fun) do
    started = System.monotonic_time(:millisecond)
    result = fun.()
    ms = System.monotonic_time(:millisecond) - started

    {ok, error, output} =
      case result do
        {:ok, value} -> {true, nil, value}
        {:error, error} -> {false, error |> inspect() |> String.slice(0, 500), nil}
        other -> {false, other |> inspect() |> String.slice(0, 500), nil}
      end

    try do
      Repo.insert_all("llm_calls", [
        %{
          org_id: org_id && Ecto.UUID.dump!(org_id),
          operation: to_string(operation),
          model: model,
          ms: ms,
          ok: ok,
          error: error,
          input_chars: size(input),
          output_chars: size(output),
          inserted_at: DateTime.utc_now()
        }
      ])
    rescue
      e -> Logger.warning("Could not record an LLM call: #{Exception.message(e)}")
    end

    result
  end

  defp size(nil), do: 0
  defp size(text) when is_binary(text), do: String.length(text)
  defp size(other), do: other |> inspect(limit: :infinity, printable_limit: :infinity) |> String.length()

  @doc "Per-workspace usage since `since` (default: the last 24 hours)."
  def usage(since \\ DateTime.add(DateTime.utc_now(), -86_400, :second)) do
    from(c in "llm_calls",
      where: c.inserted_at >= ^since,
      group_by: c.org_id,
      select: %{
        org_id: c.org_id,
        calls: count(c.id),
        errors: filter(count(c.id), not c.ok),
        avg_ms: avg(c.ms),
        chars: sum(c.input_chars + c.output_chars)
      }
    )
    |> Repo.all()
    |> Map.new(fn u ->
      {u.org_id && Ecto.UUID.load!(u.org_id),
       %{
         calls: u.calls,
         errors: u.errors,
         avg_ms: u.avg_ms && round(Decimal.to_float(u.avg_ms)),
         approx_tokens: div(u.chars || 0, 4)
       }}
    end)
  end

  @doc "The model name extraction and `@noa` use."
  def model, do: System.get_env("NOA_MODEL", "gpt-5.6-luna")
end
