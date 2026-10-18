defmodule Noa.Meetings.Voice do
  @moduledoc "Explicit all-participant consent, bounded temporary audio, and fail-closed voice sessions."
  use GenServer
  require Ash.Query
  alias Noa.Meetings
  alias Noa.Meetings.Voice.Worker
  alias Noa.Ingest.Discord.Accounts

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def start(org_id, actor, attrs), do: GenServer.call(__MODULE__, {:start, org_id, actor, attrs}, 65_000)
  def consent(id, actor), do: GenServer.call(__MODULE__, {:consent, id, actor}, 65_000)
  def stop(id, actor), do: GenServer.call(__MODULE__, {:stop, id, actor}, 65_000)
  def cancel(id, actor), do: GenServer.call(__MODULE__, {:cancel, id, actor}, 65_000)
  defp worker, do: Application.get_env(:noa, __MODULE__, [])[:worker] || Worker

  @impl true
  def init(_) do
    if Application.get_env(:noa, __MODULE__, [])[:recover] != false, do: send(self(), :recover)
    {:ok, %{sessions: %{}, tasks: %{}}}
  end

  @impl true
  def handle_call({:start, org_id, actor, attrs}, _, state) do
    result =
      cond do
        not worker().enabled?() -> {:error, :voice_disabled}
        not Noa.LLM.configured?() -> {:error, :llm_not_configured}
        map_size(state.sessions) >= 1 -> {:error, :voice_busy}
        Noa.Orgs.role(actor.id, org_id) not in [:org_admin, :pm] -> {:error, %Ash.Error.Forbidden{}}
        true -> prepare(org_id, actor, attrs)
      end

    case result do
      {:ok, meeting} ->
        Process.send_after(self(), {:consent_timeout, meeting.id}, 600_000)
        session = %{actor: actor, meeting: meeting, next_seq: 1, stopped: false, stop_reason: "requested"}
        {:reply, result, put_in(state, [:sessions, meeting.id], session)}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:consent, id, actor}, _, state) do
    with %{actor: organizer} <- state.sessions[id],
         {:ok, meeting} <- Meetings.consent(id, actor) do
      result =
        if MapSet.subset?(MapSet.new(meeting.participant_ids), MapSet.new(meeting.consented_ids)) do
          with {:ok, meeting} <- Meetings.begin(id, organizer),
               {:ok, _} <-
                 worker().request(%{
                   op: "join",
                   meeting_id: id,
                   guild_id: meeting.source["guild_id"],
                   voice_channel_id: meeting.source["voice_channel_id"],
                   consenting_ids: Enum.map(meeting.source["participants"], & &1["discord_id"])
                 }) do
            {:ok, meeting}
          else
            error ->
              worker().request(%{op: "stop", meeting_id: id})
              Meetings.fail(id, "voice_join_failed", organizer)
              error
          end
        else
          {:ok, meeting}
        end

      {:reply, result, if(match?({:error, _}, result), do: discard(state, id), else: state)}
    else
      nil -> {:reply, {:error, :meeting_not_recording}, state}
      error -> {:reply, error, state}
    end
  end

  def handle_call({operation, id, actor}, _, state) when operation in [:stop, :cancel] do
    with %{actor: organizer} <- state.sessions[id],
         {:ok, meeting} <- Meetings.fetch(id, actor),
         true <- actor.id in meeting.participant_ids or Noa.Orgs.role(actor.id, meeting.org_id) in [:org_admin, :pm] do
      worker().request(%{op: "stop", meeting_id: id})

      if operation == :cancel or meeting.status == :awaiting_consent do
        result = Meetings.cancel(id, organizer)
        {:reply, result, discard(state, id)}
      else
        {:reply, {:ok, meeting}, state}
      end
    else
      _ -> {:reply, {:error, :meeting_not_recording}, state}
    end
  end

  @impl true
  def handle_info(:recover, state) do
    # Trusted system recovery uses Ash's explicit superadmin policy; no content leaves the node.
    system = %{id: nil, is_superadmin: true}

    try do
      Meetings.Meeting
      |> Ash.Query.filter(platform == :discord and status in [:recording, :awaiting_consent])
      |> Ash.read!(actor: system)
      |> Enum.each(&Meetings.fail(&1.id, "voice_restarted", system))
    rescue
      _ -> :ok
    end

    {:noreply, state}
  end

  def handle_info({:consent_timeout, id}, state) do
    with %{actor: actor} <- state.sessions[id],
         {:ok, %{status: :awaiting_consent}} <- Meetings.fetch(id, actor) do
      Meetings.cancel(id, actor)
      {:noreply, discard(state, id)}
    else
      _ -> {:noreply, state}
    end
  end

  def handle_info({:voice_event, %{"type" => "audio", "meeting_id" => id} = event}, state) do
    with %{actor: actor, stopped: false} = session <- state.sessions[id],
         true <- map_size(state.tasks) < 3,
         {:ok, meeting} <- Meetings.fetch(id, actor),
         true <- session_allowed?(meeting, actor),
         participant when not is_nil(participant) <-
           Enum.find(meeting.source["participants"], &(&1["discord_id"] == event["speaker_id"])),
         {:ok, wav} <- Base.decode64(event["wav"] || ""),
         true <- byte_size(wav) <= 1_000_000 do
      transcriber = Application.get_env(:noa, __MODULE__, [])[:transcriber] || Meetings.Transcriber

      task =
        Task.Supervisor.async_nolink(Noa.Meetings.Tasks, fn ->
          try do
            transcriber.transcribe(wav)
          rescue
            _ -> {:error, :transcription_failed}
          end
        end)

      metadata = %{
        id: id,
        pid: task.pid,
        actor: actor,
        seq: session.next_seq,
        speaker: participant["name"],
        start_ms: event["start_ms"],
        end_ms: event["end_ms"]
      }

      state = put_in(state, [:sessions, id, :next_seq], session.next_seq + 1)
      {:noreply, put_in(state, [:tasks, task.ref], metadata)}
    else
      _ -> {:noreply, fail(state, id, "audio_overload_or_invalid")}
    end
  end

  def handle_info({:voice_event, %{"type" => "stopped", "meeting_id" => id} = event}, state) do
    if state.sessions[id] do
      reason = if event["reason"] in [nil, "requested"], do: "requested", else: "recording_interrupted"
      state = put_in(state, [:sessions, id, :stop_reason], reason)
      state = put_in(state, [:sessions, id, :stopped], true)
      {:noreply, maybe_finish(state, id)}
    else
      {:noreply, state}
    end
  end

  def handle_info({:voice_event, %{"type" => "worker_error"}}, state) do
    {:noreply, Enum.reduce(Map.keys(state.sessions), state, &fail(&2, &1, "voice_worker_failed"))}
  end

  def handle_info({:voice_event, _}, state), do: {:noreply, state}

  def handle_info({ref, result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {metadata, tasks} = Map.pop(state.tasks, ref)
    state = %{state | tasks: tasks}

    if metadata && state.sessions[metadata.id] do
      result =
        case result do
          {:ok, ""} ->
            :ok

          {:ok, text} ->
            Meetings.append(
              metadata.id,
              %{
                seq: metadata.seq,
                speaker: metadata.speaker,
                text: text,
                start_ms: metadata.start_ms,
                end_ms: metadata.end_ms
              },
              metadata.actor
            )

          _ ->
            {:error, :transcription_failed}
        end

      state =
        if match?({:error, _}, result),
          do: fail(state, metadata.id, "transcription_failed"),
          else: maybe_finish(state, metadata.id)

      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, _, _, _}, state) do
    case Map.pop(state.tasks, ref) do
      {nil, _} -> {:noreply, state}
      {metadata, tasks} -> {:noreply, fail(%{state | tasks: tasks}, metadata.id, "transcription_failed")}
    end
  end

  defp prepare(org_id, actor, attrs) do
    with {:ok, snapshot} <- worker().request(%{op: "members", guild_id: attrs.guild_id, user_id: attrs.discord_id}),
         participants when is_list(participants) and length(participants) in 1..12 <- snapshot["participants"],
         {:ok, people} <- participants(org_id, participants),
         true <- Enum.any?(people, &(&1["user_id"] == actor.id)) do
      Meetings.create(
        org_id,
        %{
          platform: :discord,
          external_id: Ecto.UUID.generate(),
          title: attrs.title,
          project_id: attrs.project_id,
          participant_ids: Enum.map(people, & &1["user_id"]),
          source: %{
            "guild_id" => attrs.guild_id,
            "voice_channel_id" => snapshot["voice_channel_id"],
            "channel_id" => attrs.channel_id,
            "text_channel_id" => attrs.text_channel_id,
            "participants" => people
          }
        },
        actor
      )
    else
      {:error, _} = error -> error
      _ -> {:error, :meeting_participants_not_linked}
    end
  end

  defp participants(org_id, people) do
    Enum.reduce_while(people, {:ok, []}, fn participant, {:ok, acc} ->
      with {:ok, user} <- Accounts.actor(org_id, participant["id"]),
           {:ok, directory} <- Noa.Work.people(org_id, user),
           person when not is_nil(person) <- Enum.find(directory, &(&1.membership && &1.membership.user_id == user.id)) do
        name = String.slice("#{person.key}: #{person.name}", 0, 100)
        entry = %{"discord_id" => participant["id"], "user_id" => user.id, "person_id" => person.id, "name" => name}
        {:cont, {:ok, [entry | acc]}}
      else
        _ -> {:halt, {:error, :meeting_participants_not_linked}}
      end
    end)
  end

  defp maybe_finish(state, id) do
    case state.sessions[id] do
      %{stopped: true, actor: actor, stop_reason: reason} ->
        if Enum.any?(state.tasks, fn {_, task} -> task.id == id end) do
          state
        else
          case Meetings.finish(id, actor, reason) do
            {:ok, _} -> discard(state, id)
            _ -> fail(state, id, "meeting_finish_failed")
          end
        end

      _ ->
        state
    end
  end

  defp fail(state, id, reason) do
    if session = state.sessions[id] do
      worker().request(%{op: "stop", meeting_id: id})

      case Meetings.fail(id, reason, session.actor) do
        {:ok, _} -> :ok
        _ -> Meetings.fail(id, reason, %{id: nil, is_superadmin: true})
      end
    end

    discard(state, id)
  end

  defp session_allowed?(meeting, actor) do
    with true <- meeting.status == :recording and Noa.Orgs.role(actor.id, meeting.org_id) in [:org_admin, :pm],
         {:ok, channel} <- Ash.get(Noa.Work.Channel, meeting.source["channel_id"], actor: actor),
         true <- channel.read do
      Enum.all?(meeting.source["participants"], fn participant ->
        case Accounts.actor(meeting.org_id, participant["discord_id"]) do
          {:ok, user} -> user.id == participant["user_id"]
          _ -> false
        end
      end)
    else
      _ -> false
    end
  end

  defp discard(state, id) do
    {removed, keep} = Enum.split_with(state.tasks, fn {_, metadata} -> metadata.id == id end)

    Enum.each(removed, fn {ref, metadata} ->
      Process.demonitor(ref, [:flush])
      Task.Supervisor.terminate_child(Noa.Meetings.Tasks, metadata.pid)
    end)

    %{state | sessions: Map.delete(state.sessions, id), tasks: Map.new(keep)}
  end
end
