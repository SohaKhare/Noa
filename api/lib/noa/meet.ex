defmodule Noa.Meet do
  @moduledoc "Attendee transport and explicit organizer session; transcript processing delegates to Noa.Meetings."
  use Ash.Domain, otp_app: :noa
  require Ash.Query
  alias Noa.Meet.{Attendee, Session}
  alias Noa.Meetings.Utterance

  resources do
    resource(Session)
  end

  def sessions(org_id, actor) do
    Session |> Ash.Query.filter(org_id == ^org_id) |> Ash.Query.sort(inserted_at: :desc) |> Ash.read(actor: actor)
  end

  def fetch(org_id, id, actor) do
    Session
    |> Ash.Query.filter(org_id == ^org_id and id == ^id)
    |> Ash.read_one(actor: actor)
    |> case do
      {:ok, nil} -> {:error, :not_found}
      other -> other
    end
  end

  def start(org_id, url, consent, actor) do
    with true <- consent == true,
         :ok <- lead(org_id, actor),
         :ok <- Attendee.valid_meet_url(url),
         :ok <- configured?(),
         {:ok, session} <-
           Session
           |> Ash.Changeset.for_create(
             :create,
             %{
               org_id: org_id,
               organizer_id: actor.id,
               meeting_url: url,
               consent_at: DateTime.utc_now(),
               status: :joining
             },
             actor: actor
           )
           |> Ash.create() do
      case provider().join(url, deduplication_key: session.id) do
        {:ok, bot_id} ->
          case Ash.update(session, %{attendee_bot_id: bot_id, status: :running}, action: :advance, actor: actor) do
            {:ok, updated} ->
              {:ok, updated}

            {:error, reason} ->
              _ = provider().leave(bot_id)
              {:error, reason}
          end

        {:error, reason} ->
          _ = Ash.update(session, %{status: :failed}, action: :advance, actor: actor)
          {:error, reason}
      end
    else
      false -> {:error, :consent_required}
      error -> error
    end
  end

  def stop(org_id, id, actor) do
    with {:ok, session} <- fetch(org_id, id, actor),
         :ok <- lead(org_id, actor),
         true <- session.status in [:joining, :running] and is_binary(session.attendee_bot_id),
         :ok <- provider().leave(session.attendee_bot_id),
         {:ok, session} <- Ash.update(session, %{status: :stopped}, action: :advance, actor: actor) do
      {:ok, session}
    else
      false -> {:error, :wrong_state}
      error -> error
    end
  end

  def sync(org_id, id, actor) do
    with {:ok, session} <- fetch(org_id, id, actor),
         :ok <- lead(org_id, actor),
         true <- session.status in [:running, :stopped],
         {:ok, %{state: "ended", transcription: "complete"}} <- provider().status(session.attendee_bot_id),
         {:ok, lines} <- provider().transcript(session.attendee_bot_id),
         {:ok, normalized} <- normalize_transcript(lines) do
      Ash.update(session, %{status: :ready, transcript: %{"lines" => normalized}}, action: :advance, actor: actor)
    else
      false -> {:error, :wrong_state}
      {:ok, _} -> {:error, :transcript_pending}
      error -> error
    end
  end

  # The channel/project selection is explicit at import; use the existing consented
  # Meeting pipeline, typed Minutes schema, citations, and review workflow.
  def import(org_id, id, project_id, channel_id, title, actor) do
    with {:ok, session} <- fetch(org_id, id, actor),
         :ok <- lead(org_id, actor),
         true <- session.status == :ready,
         {:ok, lines} <- normalize_transcript(session.transcript["lines"]),
         {:ok, meeting} <-
           Noa.Meetings.import_transcript(
             org_id,
             %{
               project_id: project_id,
               title: String.slice(title || "Google Meet", 0, 200),
               external_id: "attendee:#{session.id}",
               consent_confirmed: true,
               source: %{"channel_id" => channel_id, "provider" => "attendee", "meeting_url" => session.meeting_url}
             },
             lines,
             actor
           ),
         {:ok, updated} <-
           Ash.update(session, %{status: :imported, imported_meeting_id: meeting.id}, action: :advance, actor: actor) do
      {:ok, updated, meeting}
    else
      false -> {:error, :wrong_state}
      error -> error
    end
  end

  # Attendee can emit empty speech segments and timestamps based on the provider's
  # recording clock rather than the beginning of the transcript. Validate before
  # marking a session ready, and again at import for sessions synced before this fix.
  defp normalize_transcript(lines) when is_list(lines) do
    lines =
      Enum.reject(lines, fn line ->
        text = if is_map(line), do: Map.get(line, :text) || Map.get(line, "text"), else: nil
        is_binary(text) and String.trim(text) == ""
      end)

    with true <- length(lines) in 1..400 and Enum.all?(lines, &is_map/1),
         true <- Enum.all?(lines, fn line -> is_binary(Map.get(line, :text) || Map.get(line, "text")) end),
         true <-
           Enum.sum(Enum.map(lines, fn line -> String.length(Map.get(line, :text) || Map.get(line, "text")) end)) <=
             120_000,
         true <-
           Enum.all?(lines, fn line ->
             start_ms = Map.get(line, :start_ms) || Map.get(line, "start_ms")
             end_ms = Map.get(line, :end_ms) || Map.get(line, "end_ms")
             is_integer(start_ms) and is_integer(end_ms) and start_ms >= 0 and end_ms >= start_ms
           end) do
      first_ms =
        Enum.min_by(lines, fn line -> Map.get(line, :start_ms) || Map.get(line, "start_ms") end)
        |> then(fn line -> Map.get(line, :start_ms) || Map.get(line, "start_ms") end)

      # Preserve already-relative offsets; rebase only provider clock values outside
      # the shared one-hour transcript window.
      offset =
        if Enum.any?(lines, fn line -> (Map.get(line, :end_ms) || Map.get(line, "end_ms")) > 3_600_000 end),
          do: first_ms,
          else: 0

      lines
      |> Enum.with_index(1)
      |> Enum.reduce_while({:ok, []}, fn {line, seq}, {:ok, acc} ->
        speaker = Map.get(line, :speaker) || Map.get(line, "speaker")

        utterance = %{
          "seq" => seq,
          "speaker" =>
            if(is_binary(speaker) and String.trim(speaker) != "", do: String.trim(speaker), else: "Unknown speaker"),
          "text" => String.trim(Map.get(line, :text) || Map.get(line, "text")),
          "start_ms" => (Map.get(line, :start_ms) || Map.get(line, "start_ms")) - offset,
          "end_ms" => (Map.get(line, :end_ms) || Map.get(line, "end_ms")) - offset
        }

        case Utterance.cast(utterance) do
          {:ok, valid} -> {:cont, {:ok, [valid | acc]}}
          error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, valid} -> {:ok, Enum.reverse(valid)}
        error -> error
      end
    else
      false -> {:error, :invalid_transcript}
    end
  end

  defp normalize_transcript(_), do: {:error, :invalid_transcript}

  defp lead(org_id, actor),
    do:
      if(actor.is_superadmin or Noa.Orgs.role(actor.id, org_id) in [:org_admin, :pm],
        do: :ok,
        else: {:error, :not_a_lead}
      )

  defp provider, do: Application.get_env(:noa, __MODULE__, [])[:provider] || Attendee

  defp configured?,
    do:
      if(provider() != Attendee or Application.get_env(:noa, Attendee, [])[:api_key],
        do: :ok,
        else: {:error, :not_configured}
      )
end
