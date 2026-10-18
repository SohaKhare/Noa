defmodule Noa.GoogleMeetTest do
  use NoaWeb.ConnCase, async: false
  use Oban.Testing, repo: Noa.Repo

  defmodule FakeProvider do
    @behaviour Noa.Meet.Provider
    def join(_url, _opts \\ []), do: {:ok, "bot_google_test"}
    def leave(_id, _opts \\ []), do: :ok
    def status(_id, _opts \\ []), do: {:ok, %{state: "ended", transcription: "complete"}}

    def transcript(_id, _opts \\ []),
      do:
        {:ok,
         Application.get_env(:noa, :meet_test_transcript, [
           %{speaker: "Lead", start_ms: 1200, end_ms: 2600, text: "We will ship Veriq"}
         ])}
  end

  setup do
    old = Application.get_env(:noa, Noa.Meet.Attendee)
    Application.put_env(:noa, Noa.Meet.Attendee, api_key: "test")
    Application.put_env(:noa, Noa.Meet, provider: FakeProvider)

    on_exit(fn ->
      if old,
        do: Application.put_env(:noa, Noa.Meet.Attendee, old),
        else: Application.delete_env(:noa, Noa.Meet.Attendee)

      Application.delete_env(:noa, Noa.Meet)
      Application.delete_env(:noa, :meet_test_transcript)
    end)

    root = superadmin!()
    {:ok, org} = Noa.Orgs.create_org(%{name: "MeetFlow", allowed_domains: ["meet.test"]}, root)
    {:ok, _, invite} = Noa.Orgs.invite(org, "lead@meet.test", :org_admin, root)
    lead = accept!(invite, "Lead")
    {:ok, project} = Noa.Work.Setup.create_project(org.id, %{name: "Veriq", key: "veriq"}, lead)
    {:ok, channel} = Noa.Work.Setup.create_channel(org.id, %{name: "standup", project_id: project.id}, lead)
    %{org: org, lead: lead, project: project, channel: channel}
  end

  test "provider clock timestamps and empty segments produce valid cited utterances", ctx do
    Application.put_env(:noa, :meet_test_transcript, [
      %{speaker: nil, start_ms: 1_700_000_000_000, end_ms: 1_700_000_000_300, text: "  "},
      %{speaker: "  Lead  ", start_ms: 1_700_000_001_200, end_ms: 1_700_000_002_600, text: "  We will ship Veriq  "}
    ])

    path = "/api/orgs/#{ctx.org.id}/google_meetings"

    started =
      post(signed_in(ctx.lead), path, %{meeting_url: "https://meet.google.com/abc-defg-hij", consent: true})
      |> json_response(201)

    id = started["meeting"]["id"]
    assert %{status: 200} = post(signed_in(ctx.lead), "#{path}/#{id}/stop", %{})
    synced = post(signed_in(ctx.lead), "#{path}/#{id}/sync", %{}) |> json_response(200)

    assert [%{"seq" => 1, "speaker" => "Lead", "text" => "We will ship Veriq", "start_ms" => 0, "end_ms" => 1400}] =
             synced["meeting"]["transcript"]

    imported =
      post(signed_in(ctx.lead), "#{path}/#{id}/import", %{
        project_id: ctx.project.id,
        channel_id: ctx.channel.id,
        title: "Google Meet"
      })
      |> json_response(201)

    meeting = Ash.get!(Noa.Meetings.Meeting, imported["imported_meeting_id"], authorize?: false)
    assert meeting.transcript == synced["meeting"]["transcript"]
  end

  test "a previously synced ready session can be imported after normalization", ctx do
    path = "/api/orgs/#{ctx.org.id}/google_meetings"

    started =
      post(signed_in(ctx.lead), path, %{meeting_url: "https://meet.google.com/abc-defg-hij", consent: true})
      |> json_response(201)

    session = Ash.get!(Noa.Meet.Session, started["meeting"]["id"], authorize?: false)

    {:ok, _} =
      Ash.update(
        session,
        %{
          status: :ready,
          transcript: %{
            "lines" => [
              %{
                "seq" => 1,
                "speaker" => "Lead",
                "text" => "Ship it",
                "start_ms" => 1_700_000_000_000,
                "end_ms" => 1_700_000_001_000
              }
            ]
          }
        }, action: :advance, actor: ctx.lead)

    imported =
      post(signed_in(ctx.lead), "#{path}/#{session.id}/import", %{
        project_id: ctx.project.id,
        channel_id: ctx.channel.id,
        title: "Google Meet"
      })
      |> json_response(201)

    meeting = Ash.get!(Noa.Meetings.Meeting, imported["imported_meeting_id"], authorize?: false)
    assert [%{"start_ms" => 0, "end_ms" => 1000}] = meeting.transcript
  end

  test "visible provider session hands off to existing consented meeting minutes pipeline", ctx do
    path = "/api/orgs/#{ctx.org.id}/google_meetings"
    assert %{status: 422} = post(signed_in(ctx.lead), path, %{meeting_url: "https://meet.google.com/abc-defg-hij"})

    started = post(signed_in(ctx.lead), path, %{meeting_url: "https://meet.google.com/abc-defg-hij", consent: true})
    %{"meeting" => %{"id" => id, "status" => "running"}} = json_response(started, 201)
    assert %{status: 200} = post(signed_in(ctx.lead), "#{path}/#{id}/stop", %{})

    synced = post(signed_in(ctx.lead), "#{path}/#{id}/sync", %{}) |> json_response(200)
    assert synced["meeting"]["status"] == "ready"
    assert [%{"seq" => 1, "speaker" => "Lead", "text" => "We will ship Veriq"}] = synced["meeting"]["transcript"]

    imported =
      post(signed_in(ctx.lead), "#{path}/#{id}/import", %{
        project_id: ctx.project.id,
        channel_id: ctx.channel.id,
        title: "Veriq standup"
      })
      |> json_response(201)

    assert imported["meeting"]["status"] == "imported"
    assert imported["pipeline_status"] == "processing"

    meeting = Ash.get!(Noa.Meetings.Meeting, imported["imported_meeting_id"], authorize?: false)
    assert meeting.platform == :meet
    assert meeting.project_id == ctx.project.id

    assert meeting.transcript == [
             %{"seq" => 1, "speaker" => "Lead", "text" => "We will ship Veriq", "start_ms" => 1200, "end_ms" => 2600}
           ]

    assert_enqueued(worker: Noa.Meetings.Process, args: %{meeting_id: meeting.id, user_id: ctx.lead.id})
  end
end
