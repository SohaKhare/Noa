defmodule Noa.Extraction.Line do
  @moduledoc """
  One chat message (an Episode) as extraction sees it.

  `at` is UTC; `offset` is the author's UTC offset in seconds, kept so relative
  dates ("by Friday") resolve in the team's local time. `thread_project` is set by
  ingest when the message is a reply in a thread whose root was already routed.
  """

  @enforce_keys [:seq, :channel, :author, :at, :body]
  # thread: the Discord thread's name when the message was in one (its topic, for the model).
  defstruct [:id, :seq, :channel, :author, :at, :body, :thread, offset: 0, thread_project: nil]

  @type t :: %__MODULE__{
          id: term(),
          seq: integer(),
          channel: String.t(),
          thread: String.t() | nil,
          author: String.t(),
          at: DateTime.t(),
          offset: integer(),
          body: String.t(),
          thread_project: String.t() | nil
        }

  @doc "Builds a line from a decoded JSON map (`seq`, `channel`, `author`, `at`, `body`)."
  @spec from_map(map()) :: t()
  def from_map(%{"seq" => seq, "channel" => channel, "author" => author, "at" => at, "body" => body} = m) do
    {:ok, dt, offset} = DateTime.from_iso8601(at)

    %__MODULE__{
      id: Map.get(m, "id", seq),
      seq: seq,
      channel: channel,
      author: author,
      at: dt,
      offset: offset,
      body: body,
      thread_project: Map.get(m, "thread_project")
    }
  end

  @doc "The calendar date the author saw when they wrote the line."
  @spec local_date(t()) :: Date.t()
  def local_date(%__MODULE__{at: at, offset: offset}), do: at |> DateTime.add(offset, :second) |> DateTime.to_date()
end
