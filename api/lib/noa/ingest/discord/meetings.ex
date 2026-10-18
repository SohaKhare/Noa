defmodule Noa.Ingest.Discord.Meetings do
  @moduledoc false
  alias Noa.{Meetings, Work}
  alias Noa.Ingest.Discord.{Commands, Views}

  def spec do
    id = %{type: 3, name: "meeting", description: "Meeting id returned by /noa meeting start", required: true}

    %{
      type: 2,
      name: "meeting",
      description: "Consented voice notes and reviewed minutes",
      options: [
        %{
          type: 1,
          name: "start",
          description: "Request recording of your voice channel; all participants must consent",
          options: [%{type: 3, name: "title", description: "Meeting title", max_length: 200}]
        },
        %{type: 1, name: "consent", description: "Explicitly consent to the named recording", options: [id]},
        %{type: 1, name: "stop", description: "Stop recording and prepare minutes", options: [id]},
        %{
          type: 1,
          name: "cancel",
          description: "Withdraw consent and cancel without generating minutes",
          options: [id]
        },
        %{type: 1, name: "notes", description: "Read this meeting's status and cited minutes privately", options: [id]}
      ]
    }
  end

  def dispatch(interaction, org_id, actor) do
    group = interaction["data"]["options"] |> List.first()
    sub = (group["options"] || []) |> List.first(%{})
    options = Map.new(sub["options"] || [], &{&1["name"], &1["value"]})

    if sub["name"] == "start" do
      with {:ok, channels} <- Work.channels(org_id, actor),
           {:ok, metadata} <- Commands.api().channel(interaction["channel_id"]),
           name = Map.get(metadata, :name) || Map.get(metadata, "name"),
           channel when not is_nil(channel) <-
             Enum.find(
               channels,
               &(&1.platform == :discord and &1.read and
                   (&1.external_id == interaction["channel_id"] or
                      (is_nil(&1.external_id) and &1.name in [name, "#" <> to_string(name)])))
             ),
           true <- not is_nil(channel.project_id),
           {:ok, meeting} <-
             Meetings.Voice.start(org_id, actor, %{
               guild_id: interaction["guild_id"],
               discord_id:
                 get_in(interaction, ["user", "id"]) || get_in(interaction, ["member", "user", "id"]) ||
                   get_in(interaction, ["member", "user_id"]),
               title: options["title"] || "Standup",
               project_id: channel.project_id,
               channel_id: channel.id,
               text_channel_id: interaction["channel_id"]
             }) do
        notice =
          "Noa voice-recording request: #{meeting.id}\nEvery voice participant must run /noa meeting consent meeting:#{meeting.id}. No audio is captured until everyone agrees. A new arrival stops recording. Use /noa meeting cancel to withdraw consent."

        Commands.api().message(interaction["channel_id"], Views.text(notice))
        {:ok, Views.text(notice)}
      else
        {:error, _} = error -> error
        _ -> {:error, :meeting_source_not_enabled}
      end
    else
      with {:ok, id} <- Ecto.UUID.cast(options["meeting"]),
           {:ok, meeting} <- Meetings.fetch(id, actor),
           true <- meeting.org_id == org_id and meeting.source["guild_id"] in [nil, interaction["guild_id"]] do
        case sub["name"] do
          "consent" ->
            with {:ok, m} <- Meetings.Voice.consent(id, actor),
                 do:
                   {:ok,
                    Views.text(
                      "Consent saved. Meeting #{id}: #{m.status}. Recording starts only after everyone has agreed."
                    )}

          "stop" ->
            with {:ok, _} <- Meetings.Voice.stop(id, actor),
                 do:
                   {:ok,
                    Views.text(
                      "Recording stopped. Transcription and minutes processing may take a moment. Use /noa meeting notes meeting:#{id}. Tasks and decisions wait in the Inbox for review."
                    )}

          "cancel" ->
            with {:ok, _} <- Meetings.Voice.cancel(id, actor),
                 do:
                   {:ok,
                    Views.text(
                      "Recording cancelled. No minutes or work proposals will be generated. Already transcribed sources remain workspace-protected."
                    )}

          "notes" ->
            {:ok, notes(meeting)}

          _ ->
            {:error, :unknown_command}
        end
      else
        _ -> {:error, :not_found}
      end
    end
  end

  def notes(meeting) do
    header =
      "#{meeting.title} · #{meeting.status}\nMeeting: #{meeting.id}\nReview tasks/decisions: #{Views.web("/inbox")}"

    header =
      if meeting.source["partial"],
        do: header <> "\nPartial recording: recording was interrupted; minutes cover only the captured portion.",
        else: header

    if meeting.minutes do
      sections =
        for {field, label} <- [
              {"discussion", "Discussion"},
              {"decisions", "Decision proposals"},
              {"tasks", "Action proposals"},
              {"blockers", "Blockers"},
              {"open_questions", "Open questions"}
            ],
            items = meeting.minutes[field] || [],
            items != [] do
          label <>
            "\n" <>
            Enum.map_join(Enum.take(items, 2), "\n", fn item ->
              text = item["text"] || item["statement"] || item["title"]
              "• #{String.slice(text, 0, 130)} [#{Enum.join(item["evidence_sequences"] || [], ", ")}]"
            end)
        end

      Views.text(
        header <>
          "\n\n" <> if(sections == [], do: "No substantive work discussion found.", else: Enum.join(sections, "\n\n"))
      )
    else
      Views.text(
        header <> "\n\nNo minutes yet. #{meeting.error_code || "Waiting for consent, transcription or processing."}"
      )
    end
  end
end
