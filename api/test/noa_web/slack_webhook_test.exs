defmodule NoaWeb.SlackWebhookTest do
  use NoaWeb.ConnCase, async: false
  use Oban.Testing, repo: Noa.Repo

  alias Noa.Ingest.Slack.Event

  @secret "test-slack-signing-secret"

  defp post_slack(payload, opts \\ []) do
    body = Jason.encode!(payload)
    timestamp = Keyword.get(opts, :timestamp, System.system_time(:second)) |> to_string()
    secret = Keyword.get(opts, :secret, @secret)
    signature = "v0=" <> (:crypto.mac(:hmac, :sha256, secret, "v0:#{timestamp}:#{body}") |> Base.encode16(case: :lower))

    build_conn()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-slack-request-timestamp", timestamp)
    |> put_req_header("x-slack-signature", signature)
    |> post("/webhooks/slack", body)
  end

  test "answers URL verification only after checking Slack's signature" do
    payload = %{"type" => "url_verification", "challenge" => "challenge-token"}
    assert %{"challenge" => "challenge-token"} = post_slack(payload) |> json_response(200)
    assert post_slack(payload, secret: "wrong").status == 401
  end

  test "rejects stale requests" do
    payload = %{"type" => "url_verification", "challenge" => "challenge-token"}
    assert post_slack(payload, timestamp: System.system_time(:second) - 301).status == 401
  end

  test "queues a supported delivery once and acknowledges unsupported events" do
    payload = %{
      "type" => "event_callback",
      "team_id" => "T001",
      "event_id" => "Ev001",
      "event" => %{"type" => "message", "channel" => "C001", "user" => "U001", "text" => "hello", "ts" => "1.0"}
    }

    assert %{"ok" => true} = post_slack(payload) |> json_response(200)
    assert %{"ok" => true} = post_slack(payload) |> json_response(200)
    assert_enqueued(worker: Event, args: %{"event_id" => "Ev001"})
    assert Noa.Repo.aggregate(Oban.Job, :count) == 1

    unsupported = %{
      "type" => "event_callback",
      "team_id" => "T001",
      "event_id" => "Ev002",
      "event" => %{"type" => "reaction_added"}
    }

    assert %{"ignored" => "unsupported"} = post_slack(unsupported) |> json_response(200)
  end
end
