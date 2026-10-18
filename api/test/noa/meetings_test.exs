defmodule Noa.MeetingsTest do
  use NoaWeb.ConnCase, async: false
  use Oban.Testing, repo: Noa.Repo
  alias Noa.{Events, Meetings, Work}

  defmodule Model do
    def generate(context) do
      raw = %{
        discussion: [%{text: "Release plan agreed", evidence_sequences: [1]}],
        blockers: [],
        open_questions: [],
        tasks: [
          %{
            title: "Prepare the report",
            owner: "bob",
            due: nil,
            detail: nil,
            project: context.project.key,
            confidence: 0.99,
            evidence_sequences: [1]
          }
        ],
        decisions: [
          %{
            statement: "Ship the blue version",
            kind: "decision",
            affects: [],
            supersedes_ref: nil,
            project: context.project.key,
            confidence: 0.99,
            evidence_sequences: [2]
          }
        ]
      }

      Noa.Meetings.Minutes.from_map(raw, context.extra)
    end
  end

  defmodule Banter do
    def generate(_), do: {:ok, %Noa.Meetings.Minutes{}}
  end

  defmodule Fabricated do
    def generate(_),
      do:
        {:ok,
         %{
           discussion: [%{text: "Invented claim", evidence_sequences: [99]}],
           blockers: [],
           open_questions: [],
           tasks: [],
           decisions: []
         }}
  end

  setup do
    old = Application.get_env(:noa, Meetings)
    Application.put_env(:noa, Meetings, model: Model)

    on_exit(fn ->
      if old, do: Application.put_env(:noa, Meetings, old), else: Application.delete_env(:noa, Meetings)
    end)

    root = superadmin!()
    {:ok, org} = Noa.Orgs.create_org(%{name: "Meetings", allowed_domains: ["meet.test"]}, root)
    {:ok, _, invite} = Noa.Orgs.invite(org, "lead@meet.test", :org_admin, root)
    lead = accept!(invite, "Lead")
    {:ok, _, invite} = Noa.Orgs.invite(org, "bob@meet.test", :member, lead)
    member = accept!(invite, "Bob")
    {:ok, _} = Work.Setup.add_members(org.id, lead)
    {:ok, people} = Work.people(org.id, lead)
    bob = Enum.find(people, &(&1.name == "Bob"))
    {:ok, _} = Work.Setup.update_person(bob.id, %{handles: ["bob"]}, lead)
    {:ok, project} = Work.Setup.create_project(org.id, %{name: "Veriq", key: "veriq"}, lead)
    {:ok, channel} = Work.Setup.create_channel(org.id, %{name: "standup", project_id: project.id}, lead)
    %{root: root, org: org, lead: lead, member: member, project: project, channel: channel}
  end

  test "Meet bot import is consented, source-cited, queued and never auto-applies meeting commitments", ctx do
    meeting = imported(ctx)
    assert meeting.status == :processing
    assert_enqueued(worker: Meetings.Process, args: %{meeting_id: meeting.id, user_id: ctx.lead.id})
    assert {:ok, reviewed} = Meetings.process(meeting.id, ctx.lead)
    assert reviewed.status == :review
    assert length(reviewed.minutes["proposal_ids"]) == 2
    assert {:ok, []} = Work.tasks(ctx.org.id, ctx.lead)
    assert {:ok, []} = Work.decisions(ctx.org.id, ctx.lead)
    {:ok, proposals} = Work.proposals(ctx.org.id, ctx.lead)
    assert Enum.all?(proposals, &(&1.status == :pending))
    assert Enum.all?(proposals, &(&1.source["meeting_id"] == meeting.id))
    assert Enum.all?(proposals, &String.starts_with?(&1.source["episode_id"], "meeting:#{meeting.id}:"))
    assert {:ok, _} = Meetings.process(meeting.id, ctx.lead)
    assert {:ok, again} = Work.proposals(ctx.org.id, ctx.lead)
    assert length(again) == 2
    [decision] = Enum.filter(proposals, &(&1.kind == :decision))
    assert {:ok, _} = Work.approve(decision.id, %{}, ctx.lead)
    assert {:ok, [_]} = Work.decisions(ctx.org.id, ctx.lead)
  end

  test "small talk produces no work items and fabricated evidence is rejected", ctx do
    Application.put_env(:noa, Meetings, model: Banter)
    meeting = imported(ctx)
    assert {:ok, %{minutes: %{"proposal_ids" => []}}} = Meetings.process(meeting.id, ctx.lead)
    Application.put_env(:noa, Meetings, model: Fabricated)
    another = imported(ctx)
    assert {:error, %Ecto.Changeset{}} = Meetings.process(another.id, ctx.lead)
    assert {:ok, []} = Work.proposals(ctx.org.id, ctx.lead)
  end

  test "a participant cannot start recording until all consent; consent is individual and role-bound", ctx do
    {:ok, meeting} = Meetings.create(ctx.org.id, attrs(ctx, :discord, [ctx.lead.id, ctx.member.id]), ctx.lead)
    assert {:error, :meeting_consent_required} = Meetings.begin(meeting.id, ctx.lead)
    assert {:ok, _} = Meetings.consent(meeting.id, ctx.lead)
    assert {:error, :meeting_consent_required} = Meetings.begin(meeting.id, ctx.lead)
    assert {:ok, _} = Meetings.consent(meeting.id, ctx.member)
    assert {:error, _} = Meetings.begin(meeting.id, ctx.member)
    assert {:ok, %{status: :recording}} = Meetings.begin(meeting.id, ctx.lead)
    assert {:error, :meeting_consent_required} = Meetings.consent(meeting.id, ctx.member)
  end

  test "utterances deduplicate, conflicting sequence ids fail and stop forbids further ingestion", ctx do
    {:ok, meeting} = Meetings.create(ctx.org.id, attrs(ctx, :discord, [ctx.lead.id]), ctx.lead)
    {:ok, _} = Meetings.consent(meeting.id, ctx.lead)
    {:ok, _} = Meetings.begin(meeting.id, ctx.lead)
    utterance = hd(utterances())
    assert {:ok, _} = Meetings.append(meeting.id, utterance, ctx.lead)
    assert {:ok, _} = Meetings.append(meeting.id, utterance, ctx.lead)

    assert {:error, :transcript_conflict} =
             Meetings.append(meeting.id, Map.put(utterance, "text", "Different"), ctx.lead)

    events = Events.since(0, org_id: ctx.org.id) |> Enum.filter(&(&1.type == "message.received"))
    assert length(events) == 1
    assert {:ok, _} = Meetings.finish(meeting.id, ctx.lead)
    assert {:error, :meeting_not_recording} = Meetings.append(meeting.id, List.last(utterances()), ctx.lead)
  end

  test "disabled/unmapped sources and cross-project sources fail closed", ctx do
    attrs = attrs(ctx, :meet, [ctx.lead.id])
    {:ok, _} = Work.update_channel(ctx.channel.id, %{read: false}, ctx.lead)
    assert {:error, :meeting_source_not_enabled} = Meetings.create(ctx.org.id, attrs, ctx.lead)
    {:ok, _} = Work.update_channel(ctx.channel.id, %{read: true}, ctx.lead)
    {:ok, other} = Work.Setup.create_project(ctx.org.id, %{name: "Elsewhere"}, ctx.lead)

    assert {:error, :meeting_source_not_enabled} =
             Meetings.create(ctx.org.id, %{attrs | project_id: other.id}, ctx.lead)
  end

  test "invalid transcripts roll the whole import back, and missing consent never creates a session", ctx do
    assert {:error, :meeting_consent_required} =
             Meetings.import_transcript(
               ctx.org.id,
               Map.put(attrs(ctx, :meet, []), :consent_confirmed, false),
               utterances(),
               ctx.lead
             )

    raw = Map.put(hd(utterances()), "end_ms", -1)

    assert {:error, :invalid_transcript} =
             Meetings.import_transcript(
               ctx.org.id,
               Map.put(attrs(ctx, :meet, []), :consent_confirmed, true),
               [raw],
               ctx.lead
             )

    assert {:ok, []} = Meetings.for_org(ctx.org.id, ctx.lead)
    refute Enum.any?(Events.since(0, org_id: ctx.org.id), &(&1.type == "message.received"))
  end

  test "members read meeting records but cannot import transcripts or produce proposals", ctx do
    meeting = imported(ctx)
    assert {:ok, _} = Meetings.fetch(meeting.id, ctx.member)

    assert {:error, _} =
             Meetings.import_transcript(
               ctx.org.id,
               Map.put(attrs(ctx, :meet, []), :consent_confirmed, true),
               utterances(),
               ctx.member
             )

    assert {:error, _} = Meetings.process(meeting.id, ctx.member)
  end

  test "cancelled sessions never produce minutes or proposals", ctx do
    {:ok, meeting} = Meetings.create(ctx.org.id, attrs(ctx, :discord, [ctx.lead.id]), ctx.lead)
    assert {:ok, %{status: :cancelled}} = Meetings.cancel(meeting.id, ctx.lead)
    assert {:error, :meeting_not_processing} = Meetings.process(meeting.id, ctx.lead)
  end

  test "Soha's shared endpoint accepts a transcript and returns a tracked, permission-protected meeting", ctx do
    body = %{
      project_id: ctx.project.id,
      channel_id: ctx.channel.id,
      external_id: "google-call-1",
      title: "Standup",
      consent_confirmed: true,
      utterances: utterances()
    }

    response = signed_in(ctx.lead) |> post("/api/orgs/#{ctx.org.id}/meetings", body) |> json_response(201)
    id = response["meeting"]["id"]
    assert response["meeting"]["status"] == "processing"
    assert signed_in(ctx.member) |> get("/api/orgs/#{ctx.org.id}/meetings/#{id}") |> json_response(200)
    assert signed_in(ctx.member) |> get("/api/orgs/#{ctx.org.id}/meetings") |> json_response(200)
  end

  test "later channel chat never re-extracts or auto-applies meeting utterances", ctx do
    imported(ctx)
    previous = Application.get_env(:noa, Noa.Extraction)
    caller = self()

    Application.put_env(
      :noa,
      Noa.Extraction,
      Keyword.put(previous, :respond, fn window ->
        send(caller, {:chat_window, window})
        %{}
      end)
    )

    on_exit(fn -> Application.put_env(:noa, Noa.Extraction, previous) end)
    assert {:ok, 0} = Work.Extract.run(ctx.org.id, ctx.channel.id)
    refute_receive {:chat_window, _}

    assert {:ok, _} =
             Work.record_message(ctx.org.id, %{
               platform: :discord,
               channel: "standup",
               message_id: "ordinary-chat",
               author_id: "lead",
               author: "Lead",
               text: "A normal chat message",
               at: DateTime.utc_now()
             })

    assert {:ok, 0} = Work.Extract.run(ctx.org.id, ctx.channel.id)
    assert_receive {:chat_window, window}
    assert Enum.map(window.lines, & &1.body) == ["A normal chat message"]
  end

  test "a retried Meet import returns the same session and rejects different content", ctx do
    attrs = Map.put(attrs(ctx, :meet, []), :consent_confirmed, true)
    assert {:ok, first} = Meetings.import_transcript(ctx.org.id, attrs, utterances(), ctx.lead)
    assert {:ok, second} = Meetings.import_transcript(ctx.org.id, attrs, utterances(), ctx.lead)
    assert first.id == second.id
    assert {:ok, [_]} = Meetings.for_org(ctx.org.id, ctx.lead)
    changed = List.update_at(utterances(), 0, &Map.put(&1, "text", "Different source"))
    assert {:error, :transcript_conflict} = Meetings.import_transcript(ctx.org.id, attrs, changed, ctx.lead)
  end

  test "ASR responses and audio format are validated, including silent chunks" do
    assert {:ok, "hello"} = Meetings.Transcriber.decode(%{"text" => "hello"})
    assert {:ok, ""} = Meetings.Transcriber.decode(%{"text" => ""})
    assert {:error, :invalid_transcription} = Meetings.Transcriber.decode(%{})
    assert {:error, :invalid_transcription} = Meetings.Transcriber.decode(%{"text" => String.duplicate("a", 2001)})
    assert {:error, :invalid_audio} = Meetings.Transcriber.transcribe("not audio")
  end

  defp imported(ctx) do
    assert {:ok, meeting} =
             Meetings.import_transcript(
               ctx.org.id,
               Map.put(attrs(ctx, :meet, []), :consent_confirmed, true),
               utterances(),
               ctx.lead
             )

    meeting
  end

  defp attrs(ctx, platform, participants),
    do: %{
      platform: platform,
      project_id: ctx.project.id,
      external_id: Ecto.UUID.generate(),
      title: "Standup",
      source: %{"channel_id" => ctx.channel.id},
      participant_ids: participants
    }

  defp utterances,
    do: [
      %{"seq" => 1, "speaker" => "Bob", "text" => "I'll prepare the report.", "start_ms" => 0, "end_ms" => 2000},
      %{
        "seq" => 2,
        "speaker" => "Lead",
        "text" => "Decided: ship the blue version.",
        "start_ms" => 2000,
        "end_ms" => 4000
      }
    ]
end
