defmodule Noa.MeetingVoiceTest do
  use NoaWeb.ConnCase, async: false
  use Oban.Testing, repo: Noa.Repo
  alias Noa.{Connectors, Meetings, Work}
  alias Noa.Meetings.Voice
  alias Noa.Ingest.Discord.Links
  @guild "1502935253809893386"
  @lead_id "1502935253809893388"
  @member_id "1502935253809893389"

  defmodule Worker do
    def enabled?, do: true

    def request(payload) do
      config = Application.fetch_env!(:noa, Voice)
      send(config[:observer], {:voice_request, payload})

      case payload.op do
        "members" ->
          {:ok, %{"voice_channel_id" => "1502935253809893399", "participants" => config[:participants]}}

        "join" ->
          {:ok, %{"recording" => true}}

        "stop" ->
          send(Process.whereis(Voice), {:voice_event, %{"type" => "stopped", "meeting_id" => payload.meeting_id}})
          {:ok, %{}}
      end
    end
  end

  defmodule Transcriber do
    def transcribe(_), do: {:ok, "I'll finish the report."}
  end

  setup do
    old = Application.get_env(:noa, Voice)
    key = System.get_env("OPENAI_API_KEY")
    System.put_env("OPENAI_API_KEY", "test-only")

    Application.put_env(:noa, Voice,
      worker: Worker,
      transcriber: Transcriber,
      observer: self(),
      participants: [
        %{"id" => @lead_id, "name" => "Lead"},
        %{"id" => @member_id, "name" => "Bob"}
      ]
    )

    on_exit(fn ->
      if old, do: Application.put_env(:noa, Voice, old), else: Application.delete_env(:noa, Voice)
      if key, do: System.put_env("OPENAI_API_KEY", key), else: System.delete_env("OPENAI_API_KEY")
    end)

    Ecto.Adapters.SQL.Sandbox.allow(Noa.Repo, self(), Process.whereis(Voice))
    root = superadmin!()
    {:ok, org} = Noa.Orgs.create_org(%{name: "Voice", allowed_domains: ["voice.test"]}, root)
    {:ok, _, url} = Noa.Orgs.invite(org, "lead@voice.test", :org_admin, root)
    lead = accept!(url, "Lead")
    {:ok, _, url} = Noa.Orgs.invite(org, "bob@voice.test", :member, lead)
    member = accept!(url, "Bob")
    {:ok, _} = Work.Setup.add_members(org.id, lead)
    :ok = Connectors.connect_discord(org.id, @guild, lead)

    for {actor, discord} <- [{lead, @lead_id}, {member, @member_id}] do
      {:ok, code} = Links.issue(org.id, @guild, discord)
      assert {:ok, _} = Links.claim(org.id, code, actor)
    end

    {:ok, project} = Work.Setup.create_project(org.id, %{name: "Veriq"}, lead)
    {:ok, channel} = Work.Setup.create_channel(org.id, %{name: "standup", project_id: project.id}, lead)

    attrs = %{
      guild_id: @guild,
      discord_id: @lead_id,
      title: "Standup",
      project_id: project.id,
      channel_id: channel.id,
      text_channel_id: "1502935253809893397"
    }

    %{org: org, lead: lead, member: member, attrs: attrs}
  end

  test "no join or capture occurs until every verified participant explicitly consents", ctx do
    assert {:ok, meeting} = Voice.start(ctx.org.id, ctx.lead, ctx.attrs)
    refute_receive {:voice_request, %{op: "join"}}
    assert {:ok, %{status: :awaiting_consent}} = Voice.consent(meeting.id, ctx.lead)
    refute_receive {:voice_request, %{op: "join"}}
    assert {:ok, %{status: :recording}} = Voice.consent(meeting.id, ctx.member)
    assert_receive {:voice_request, %{op: "join", consenting_ids: ids}}
    assert Enum.sort(ids) == Enum.sort([@lead_id, @member_id])
    assert {:ok, %{status: :cancelled}} = Voice.cancel(meeting.id, ctx.member)
    assert_receive {:voice_request, %{op: "stop"}}
  end

  test "any participant can stop, in-flight audio becomes a cited utterance and processing is queued", ctx do
    {:ok, meeting} = Voice.start(ctx.org.id, ctx.lead, ctx.attrs)
    {:ok, _} = Voice.consent(meeting.id, ctx.lead)
    {:ok, _} = Voice.consent(meeting.id, ctx.member)

    send(
      Voice,
      {:voice_event,
       %{
         "type" => "audio",
         "meeting_id" => meeting.id,
         "speaker_id" => @member_id,
         "start_ms" => 0,
         "end_ms" => 2000,
         "wav" => Base.encode64("RIFF0000WAVEtest")
       }}
    )

    assert {:ok, _} = Voice.stop(meeting.id, ctx.member)
    meeting = eventually(fn -> Meetings.fetch(meeting.id, ctx.lead) |> elem(1) end, &(&1.status == :processing))
    assert [%{"text" => "I'll finish the report.", "speaker" => "bob: Bob"}] = meeting.transcript
    assert_enqueued(worker: Meetings.Process, args: %{meeting_id: meeting.id})
  end

  test "unlinked participants and missing credentials never create a recording", ctx do
    config = Application.fetch_env!(:noa, Voice)

    Application.put_env(
      :noa,
      Voice,
      Keyword.put(config, :participants, [%{"id" => "999999999999999999", "name" => "Unknown"}])
    )

    assert {:error, :meeting_participants_not_linked} = Voice.start(ctx.org.id, ctx.lead, ctx.attrs)
    refute_receive {:voice_request, %{op: "join"}}
    System.delete_env("OPENAI_API_KEY")
    assert {:error, :llm_not_configured} = Voice.start(ctx.org.id, ctx.lead, ctx.attrs)
    assert {:ok, []} = Meetings.for_org(ctx.org.id, ctx.lead)
  end

  test "a member cannot initiate recording, and a failed worker cancels capture safely", ctx do
    assert {:error, %Ash.Error.Forbidden{}} = Voice.start(ctx.org.id, ctx.member, ctx.attrs)
    {:ok, meeting} = Voice.start(ctx.org.id, ctx.lead, ctx.attrs)
    {:ok, _} = Voice.consent(meeting.id, ctx.lead)
    {:ok, _} = Voice.consent(meeting.id, ctx.member)
    send(Voice, {:voice_event, %{"type" => "worker_error"}})
    result = eventually(fn -> Meetings.fetch(meeting.id, ctx.lead) |> elem(1) end, &(&1.status == :failed))
    assert result.error_code == "voice_worker_failed"
    assert_receive {:voice_request, %{op: "stop"}}
  end

  test "an unconsented arrival stops with partial notes, while consent timeouts never join", ctx do
    {:ok, meeting} = Voice.start(ctx.org.id, ctx.lead, ctx.attrs)
    send(Voice, {:consent_timeout, meeting.id})
    eventually(fn -> Meetings.fetch(meeting.id, ctx.lead) |> elem(1) end, &(&1.status == :cancelled))
    refute_receive {:voice_request, %{op: "join"}}

    {:ok, meeting} = Voice.start(ctx.org.id, ctx.lead, ctx.attrs)
    {:ok, _} = Voice.consent(meeting.id, ctx.lead)
    {:ok, _} = Voice.consent(meeting.id, ctx.member)
    send(Voice, {:voice_event, %{"type" => "stopped", "meeting_id" => meeting.id, "reason" => "participant_changed"}})
    finished = eventually(fn -> Meetings.fetch(meeting.id, ctx.lead) |> elem(1) end, &(&1.status == :processing))
    assert finished.source["partial"] == true
  end

  test "unlinking a participant prevents sending any later audio to the transcriber", ctx do
    {:ok, meeting} = Voice.start(ctx.org.id, ctx.lead, ctx.attrs)
    {:ok, _} = Voice.consent(meeting.id, ctx.lead)
    {:ok, _} = Voice.consent(meeting.id, ctx.member)
    {:ok, _} = Noa.Ingest.Discord.Accounts.unlink(ctx.org.id, ctx.member)

    send(
      Voice,
      {:voice_event,
       %{
         "type" => "audio",
         "meeting_id" => meeting.id,
         "speaker_id" => @member_id,
         "start_ms" => 0,
         "end_ms" => 2000,
         "wav" => Base.encode64("RIFF0000WAVEtest")
       }}
    )

    failed = eventually(fn -> Meetings.fetch(meeting.id, ctx.lead) |> elem(1) end, &(&1.status == :failed))
    assert failed.transcript == []
    assert_receive {:voice_request, %{op: "stop"}}
  end

  defp eventually(fun, predicate, remaining \\ 50) do
    value = fun.()

    cond do
      predicate.(value) ->
        value

      remaining == 0 ->
        flunk("meeting did not reach its expected state")

      true ->
        Process.sleep(10)
        eventually(fun, predicate, remaining - 1)
    end
  end
end
