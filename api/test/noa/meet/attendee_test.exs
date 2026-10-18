defmodule Noa.Meet.AttendeeTest do
  use ExUnit.Case, async: false

  alias Noa.Meet.Attendee

  @opts [api_key: "test-key", base_url: "http://attendee.test", req_options: [plug: {Req.Test, __MODULE__}]]

  test "joins a consented Meet with the visible Noa name" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/api/v1/bots"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Token test-key"]
      assert {:ok, body, _conn} = Plug.Conn.read_body(conn)

      assert Jason.decode!(body) == %{
               "bot_name" => "Noa Notetaker",
               "meeting_url" => "https://meet.google.com/abc-defg-hij"
             }

      Req.Test.json(conn, %{"id" => "bot_123"})
    end)

    assert {:ok, "bot_123"} = Attendee.join("https://meet.google.com/abc-defg-hij", @opts)
  end

  test "passes a stable deduplication key for a session retry" do
    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, _} = Plug.Conn.read_body(conn)
      assert Jason.decode!(body)["deduplication_key"] == "session-123"
      Req.Test.json(conn, %{"id" => "bot_123"})
    end)

    assert {:ok, "bot_123"} =
             Attendee.join("https://meet.google.com/abc-defg-hij", @opts ++ [deduplication_key: "session-123"])
  end

  test "rejects non-Meet URLs without sending credentials to them" do
    for url <- [
          "https://evil.test/",
          "http://meet.google.com/abc-defg-hij",
          "https://meet.google.com.evil.test/abc-defg-hij"
        ] do
      assert {:error, :invalid_meet_url} = Attendee.join(url, @opts)
    end
  end

  test "transcript normalizes speaker and time ranges, preserving order" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/api/v1/bots/bot_123/transcript"

      Req.Test.json(conn, [
        %{
          "id" => 1,
          "speaker_name" => "Sam",
          "speaker_uuid" => "p1",
          "timestamp_ms" => 1200,
          "duration_ms" => 300,
          "transcription" => "Hello"
        },
        %{"timestamp_ms" => 1600, "duration_ms" => 100, "transcription" => "Agreed"}
      ])
    end)

    assert {:ok,
            [
              %{provider_utterance_id: 1, speaker: "Sam", start_ms: 1200, end_ms: 1500, text: "Hello"},
              %{speaker: nil, start_ms: 1600, end_ms: 1700, text: "Agreed"}
            ]} =
             Attendee.transcript("bot_123", @opts)
  end

  test "rejects invalid bot IDs and invalid transcript lines" do
    assert {:error, :invalid_bot_id} = Attendee.transcript("../other", @opts)

    Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, [%{"transcription" => "no timing"}]) end)
    assert {:error, :invalid_transcript} = Attendee.transcript("bot_123", @opts)
  end

  test "leaves a bot and does not expose provider error bodies" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/api/v1/bots/bot_123/leave"
      conn |> Plug.Conn.put_status(403) |> Req.Test.json(%{"detail" => "secret"})
    end)

    assert {:error, {:provider_http, 403}} = Attendee.leave("bot_123", @opts)
  end

  test "missing API key fails closed" do
    assert {:error, :not_configured} = Attendee.join("https://meet.google.com/abc-defg-hij", api_key: nil)
  end
end
