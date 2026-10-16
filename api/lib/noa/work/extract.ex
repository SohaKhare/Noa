defmodule Noa.Work.Extract do
  @moduledoc """
  The extraction job (1.17): a channel's new messages in, Inbox proposals out.

  `Noa.Work.record_message/2` enqueues one job per channel, delayed by
  `debounce_seconds` and unique while it waits, so a burst of chat is one model call.
  The job reads the channel's `message.received` events after its saved position
  (`extract:<channel id>` in `projections`), groups them into windows with the 5
  messages before as context (docs/extraction.md, "Windows"), runs the model and saves
  what it finds with `Noa.Work.save_proposals/3`. The position moves after each window,
  so a retry does not extract a window twice.

  Without `OPENAI_API_KEY` the job is cancelled and the position stays, so the next
  message after the key is set covers the earlier ones.
  """
  use Oban.Worker, queue: :extraction, max_attempts: 3

  import Ecto.Query

  alias Noa.{Events, Extraction, Repo}
  alias Noa.Events.Event
  alias Noa.Extraction.Line

  @context 5

  @doc "Queues extraction for a channel, unless one is already waiting."
  def enqueue(org_id, channel_id) do
    delay = config(:debounce_seconds, 20)

    %{org_id: org_id, channel_id: channel_id}
    |> new(
      schedule_in: delay,
      unique: [period: max(delay, 1), keys: [:org_id, :channel_id], states: [:available, :scheduled]]
    )
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"org_id" => org_id, "channel_id" => channel_id}}) do
    if Extraction.Model.impl() == Extraction.Model.OpenAI and is_nil(System.get_env("OPENAI_API_KEY")) do
      {:cancel, :no_openai_key}
    else
      run(org_id, channel_id)
    end
  end

  @doc "Extracts the channel's new messages now. Returns `{:ok, proposals saved}`."
  def run(org_id, channel_id) do
    name = "extract:#{channel_id}"
    position = Events.position(name)

    case messages(org_id, channel_id, :after, position) do
      [] ->
        {:ok, 0}

      new ->
        earlier = messages(org_id, channel_id, :before, position) |> Enum.reverse()
        lines = Enum.map(new, &line/1)
        vocab = Noa.Work.vocabulary(org_id)

        lines
        |> Extraction.windows()
        |> Enum.map(fn
          %{context: []} = window -> %{window | context: Enum.map(earlier, &line/1)}
          window -> window
        end)
        |> Enum.reduce_while({:ok, 0}, fn window, {:ok, count} ->
          case Extraction.extract(window, vocab) do
            {:ok, proposals} ->
              saved = Noa.Work.save_proposals(org_id, proposals, window.context ++ window.lines)
              Events.put_position(name, List.last(window.lines).seq)
              {:cont, {:ok, count + length(saved)}}

            {:error, error} ->
              {:halt, {:error, error}}
          end
        end)
    end
  end

  defp messages(org_id, channel_id, direction, position) do
    query =
      from(e in Event,
        where: e.org_id == ^org_id and e.type == "message.received",
        where: fragment("?->>'channel_id' = ?", e.data, ^channel_id)
      )

    case direction do
      :after -> query |> where([e], e.id > ^position) |> order_by(asc: :id) |> limit(200)
      :before -> query |> where([e], e.id <= ^position) |> order_by(desc: :id) |> limit(@context)
    end
    |> Repo.all()
  end

  defp line(%Event{id: id, data: d}) do
    {:ok, at, _} = DateTime.from_iso8601(d["at"])

    %Line{
      id: d["episode_id"],
      seq: id,
      channel: d["channel"],
      author: d["author"] || "someone",
      at: at,
      offset: config(:utc_offset, 0),
      body: d["text"] || ""
    }
  end

  defp config(key, default), do: Application.get_env(:noa, Noa.Extraction, [])[key] || default
end
