defmodule Noa.Meetings do
  @moduledoc "Consented transcript → typed minutes → pending proposals. No direct graph writes and no meeting auto-apply."
  use Ash.Domain, otp_app: :noa
  require Ash.Query
  alias Noa.{Events, Repo, Work}
  alias Noa.Meetings.{Meeting, Minutes, Utterance}
  alias Noa.Extraction.{Line, Vocabulary, Window}

  resources do
    resource(Meeting)
  end

  def for_org(org_id, actor),
    do: Meeting |> Ash.Query.filter(org_id == ^org_id) |> Ash.Query.sort(inserted_at: :desc) |> Ash.read(actor: actor)

  def fetch(id, actor), do: Ash.get(Meeting, id, actor: actor)

  def create(org_id, attrs, actor) do
    with :ok <- lead(org_id, actor),
         {:ok, project} <- Ash.get(Work.Project, attrs[:project_id], actor: actor),
         true <- project.org_id == org_id,
         {:ok, channel} <- Ash.get(Work.Channel, get_in(attrs, [:source, "channel_id"]), actor: actor),
         true <- channel.org_id == org_id and channel.read and (channel.project_id == project.id or channel.split) do
      Meeting
      |> Ash.Changeset.for_create(:create, Map.merge(attrs, %{org_id: org_id, created_by_id: actor.id}), actor: actor)
      |> Ash.create()
    else
      false -> {:error, :meeting_source_not_enabled}
      error -> error
    end
  end

  def consent(id, actor) do
    locked(id, actor, fn meeting ->
      if meeting.status == :awaiting_consent and fresh_consent?(meeting) and actor.id in meeting.participant_ids do
        meeting
        |> Ash.Changeset.for_update(:consent, %{consented_ids: Enum.uniq([actor.id | meeting.consented_ids])},
          actor: actor
        )
        |> Ash.update()
      else
        {:error, :meeting_consent_required}
      end
    end)
  end

  def begin(id, actor) do
    locked(id, actor, fn meeting ->
      if meeting.status == :awaiting_consent and fresh_consent?(meeting) and meeting.participant_ids != [] and
           MapSet.subset?(MapSet.new(meeting.participant_ids), MapSet.new(meeting.consented_ids)) do
        source = Map.put(meeting.source, "recording_started_at", DateTime.to_iso8601(DateTime.utc_now()))
        update(meeting, %{status: :recording, source: source}, actor)
      else
        {:error, :meeting_consent_required}
      end
    end)
  end

  def append(id, raw, actor) do
    with {:ok, utterance} <- Utterance.cast(raw) do
      locked(id, actor, fn meeting ->
        with true <- meeting.status == :recording,
             {:ok, channel} <- Ash.get(Work.Channel, meeting.source["channel_id"], actor: actor),
             true <- channel.read and channel.org_id == meeting.org_id do
          old = Enum.find(meeting.transcript, &(&1["seq"] == utterance["seq"]))

          cond do
            old == utterance ->
              {:ok, meeting}

            old != nil ->
              {:error, :transcript_conflict}

            length(meeting.transcript) >= 400 or
                Enum.sum(Enum.map(meeting.transcript, &String.length(&1["text"]))) + String.length(utterance["text"]) >
                  120_000 ->
              {:error, :meeting_limit}

            true ->
              speaker = Enum.find(meeting.source["participants"] || [], &(&1["name"] == utterance["speaker"]))

              data = %{
                person_id: speaker && speaker["person_id"],
                episode_id: episode_id(meeting.id, utterance["seq"]),
                platform: to_string(meeting.platform),
                channel_id: channel.id,
                channel: "Meeting: #{meeting.title}",
                project_id: meeting.project_id,
                author: utterance["speaker"],
                text: utterance["text"],
                at: DateTime.add(started_at(meeting), utterance["start_ms"], :millisecond),
                meeting_id: meeting.id
              }

              with {:ok, _} <-
                     Events.append(meeting.org_id, "message.received", data, key: data.episode_id, actor_id: actor.id),
                   do:
                     update(meeting, %{transcript: Enum.sort_by([utterance | meeting.transcript], & &1["seq"])}, actor)
          end
        else
          _ -> {:error, :meeting_not_recording}
        end
      end)
    end
  end

  def finish(id, actor, reason \\ "requested") do
    locked(id, actor, fn meeting ->
      if meeting.status == :recording do
        source = Map.merge(meeting.source, %{"stop_reason" => reason, "partial" => reason != "requested"})

        with {:ok, meeting} <- update(meeting, %{status: :processing, source: source}, actor),
             {:ok, _} <- %{meeting_id: id, user_id: actor.id} |> Noa.Meetings.Process.new() |> Oban.insert(),
             do: {:ok, meeting}
      else
        {:error, :meeting_not_recording}
      end
    end)
  end

  def cancel(id, actor),
    do:
      locked(id, actor, fn meeting ->
        if meeting.status in [:awaiting_consent, :recording],
          do: update(meeting, %{status: :cancelled}, actor),
          else: {:error, :meeting_not_recording}
      end)

  def fail(id, code, actor), do: locked(id, actor, &update(&1, %{status: :failed, error_code: to_string(code)}, actor))

  @doc "Authenticated Meet-bot import. The bot must obtain consent before sending any utterances."
  def import_transcript(org_id, attrs, utterances, actor) do
    with :ok <- lead(org_id, actor),
         true <- attrs[:consent_confirmed] == true,
         true <- is_binary(attrs[:external_id]) and byte_size(attrs[:external_id]) in 1..200,
         true <- is_list(utterances) and length(utterances) in 1..400,
         {:ok, utterances} <- normalize(utterances) do
      Repo.transaction(fn ->
        external_id = attrs.external_id
        Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", ["meet-import:#{org_id}:#{external_id}"])

        existing =
          Meeting
          |> Ash.Query.filter(org_id == ^org_id and platform == :meet and external_id == ^external_id)
          |> Ash.read_one!(actor: actor)

        if existing do
          if existing.project_id == attrs.project_id and existing.title == attrs.title and
               existing.source["channel_id"] == attrs.source["channel_id"] and existing.transcript == utterances,
             do: existing,
             else: Repo.rollback(:transcript_conflict)
        else
          attrs =
            attrs
            |> Map.drop([:consent_confirmed])
            |> Map.put(:platform, :meet)
            |> Map.put(:participant_ids, [actor.id])

          with {:ok, meeting} <- create(org_id, attrs, actor),
               {:ok, _} <- consent(meeting.id, actor),
               {:ok, _} <- begin(meeting.id, actor) do
            for utterance <- utterances do
              case append(meeting.id, utterance, actor) do
                {:ok, _} -> :ok
                {:error, reason} -> Repo.rollback(reason)
              end
            end

            case finish(meeting.id, actor) do
              {:ok, meeting} -> meeting
              {:error, reason} -> Repo.rollback(reason)
            end
          else
            {:error, reason} -> Repo.rollback(reason)
          end
        end
      end)
    else
      false -> {:error, :meeting_consent_required}
      error -> error
    end
  end

  def process(id, actor) do
    with {:ok, meeting} <- fetch(id, actor),
         :ok <- lead(meeting.org_id, actor) do
      cond do
        meeting.status == :review ->
          {:ok, meeting}

        meeting.status != :processing ->
          {:error, :meeting_not_processing}

        meeting.transcript == [] ->
          complete(id, %Minutes{}, actor)

        true ->
          with {:ok, context} <- context(meeting, actor),
               model = Application.get_env(:noa, __MODULE__, [])[:model] || Noa.Meetings.Model,
               {:ok, result} <- model.generate(context),
               {:ok, minutes} <- Minutes.from_map(Events.json(result), context.extra) do
            complete(id, minutes, actor)
          end
      end
    end
  end

  defp complete(id, minutes, actor) do
    minutes = %{
      minutes
      | tasks: Enum.filter(minutes.tasks, &(&1.confidence >= 0.8)),
        decisions: Enum.filter(minutes.decisions, &(&1.confidence >= 0.8))
    }

    locked(id, actor, fn meeting ->
      cond do
        meeting.status == :review ->
          {:ok, meeting}

        meeting.status != :processing ->
          {:error, :meeting_not_processing}

        true ->
          with {:ok, people} <- Work.people(meeting.org_id, actor) do
            proposals =
              for {kind, items} <- [task: minutes.tasks, decision: minutes.decisions],
                  item <- items,
                  item.confidence >= 0.8 do
                first = Enum.find(meeting.transcript, &(&1["seq"] == hd(item.evidence_sequences)))
                owner = if kind == :task, do: Enum.find(people, &(&1.key == item.owner))

                source = %{
                  "meeting_id" => meeting.id,
                  "episode_id" => episode_id(meeting.id, first["seq"]),
                  "quote" => first["text"],
                  "author" => first["speaker"],
                  "channel" => "Meeting: #{meeting.title}",
                  "start_ms" => first["start_ms"]
                }

                data = Events.json(item) |> Map.put("meeting_id", meeting.id)

                Work.Proposal
                |> Ash.Changeset.for_create(
                  :create,
                  %{
                    org_id: meeting.org_id,
                    project_id: meeting.project_id,
                    owner_id: owner && owner.id,
                    kind: kind,
                    summary: if(kind == :task, do: item.title, else: item.statement),
                    confidence: item.confidence,
                    source: source,
                    data: data
                  },
                  actor: actor
                )
                |> Ash.create!()
              end

            data = Events.json(minutes) |> Map.put("proposal_ids", Enum.map(proposals, & &1.id))
            update(meeting, %{status: :review, minutes: data, error_code: nil}, actor)
          end
      end
    end)
  end

  defp context(meeting, actor) do
    with {:ok, project} <- Ash.get(Work.Project, meeting.project_id, actor: actor),
         {:ok, people} <- Work.people(meeting.org_id, actor) do
      offset = Application.get_env(:noa, Noa.Extraction, [])[:utc_offset] || 0

      lines =
        Enum.map(meeting.transcript, fn u ->
          %Line{
            seq: u["seq"],
            id: episode_id(meeting.id, u["seq"]),
            channel: meeting.id,
            author: u["speaker"],
            body: u["text"],
            offset: offset,
            at: DateTime.add(started_at(meeting), u["start_ms"], :millisecond)
          }
        end)

      date = started_at(meeting) |> DateTime.add(offset, :second) |> DateTime.to_date()
      window = %Window{channel: meeting.id, date: date, lines: lines}

      vocab = %Vocabulary{
        projects: [%{id: project.key, name: project.name, about: project.about, aliases: []}],
        people: Enum.map(people, &%{id: &1.key, name: &1.name, title: &1.title, handles: [&1.key | &1.handles]})
      }

      {:ok,
       %{
         meeting: meeting,
         project: project,
         people: people,
         window: window,
         extra: %{window: window, vocabulary: vocab}
       }}
    end
  end

  defp update(meeting, attrs, actor),
    do: meeting |> Ash.Changeset.for_update(:update, attrs, actor: actor) |> Ash.update()

  defp locked(id, actor, fun) do
    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", ["noa-meeting:" <> id])

      with {:ok, meeting} <- fetch(id, actor),
           {:ok, result} <- fun.(meeting),
           do: result,
           else: ({:error, reason} -> Repo.rollback(reason))
    end)
  end

  defp lead(org_id, actor) do
    if Map.get(actor, :is_superadmin) or Noa.Orgs.role(actor.id, org_id) in [:org_admin, :pm],
      do: :ok,
      else: {:error, %Ash.Error.Forbidden{}}
  end

  defp normalize(utterances) do
    Enum.reduce_while(utterances, {:ok, %{}}, fn raw, {:ok, acc} ->
      case Utterance.cast(raw) do
        {:ok, item} ->
          if acc[item["seq"]] in [nil, item],
            do: {:cont, {:ok, Map.put(acc, item["seq"], item)}},
            else: {:halt, {:error, :transcript_conflict}}

        error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, items |> Map.values() |> Enum.sort_by(& &1["seq"])}
      error -> error
    end
  end

  defp fresh_consent?(meeting), do: DateTime.diff(DateTime.utc_now(), meeting.inserted_at) < 600

  defp started_at(meeting) do
    case DateTime.from_iso8601(meeting.source["recording_started_at"] || "") do
      {:ok, time, _} -> time
      _ -> meeting.inserted_at
    end
  end

  defp episode_id(id, seq), do: "meeting:#{id}:#{seq}"
end
