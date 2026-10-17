defmodule Noa.KapsoTest do
  @moduledoc "The Kapso client's requests (0.6), against a stubbed API: no real messages leave."
  use ExUnit.Case, async: false

  alias Noa.WhatsApp.Kapso

  setup do
    previous = Application.get_env(:noa, Noa.WhatsApp)

    Application.put_env(:noa, Noa.WhatsApp,
      api_key: "test-key",
      phone_number_id: "1234567890",
      req_options: [plug: {Req.Test, Kapso}],
      templates: %{task: "noa_task", approval: "noa_approval", update: "noa_update", language: "en"}
    )

    on_exit(fn -> Application.put_env(:noa, Noa.WhatsApp, previous) end)
    :ok
  end

  defp capture(reply) do
    test = self()

    Req.Test.stub(Kapso, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:request, conn.request_path, Plug.Conn.get_req_header(conn, "x-api-key"), Jason.decode!(body)})
      reply.(conn, Jason.decode!(body))
    end)
  end

  defp ok(conn), do: Req.Test.json(conn, %{"messages" => [%{"id" => "wamid.OUT"}]})

  test "reply buttons go as an interactive message with X-API-Key" do
    capture(fn conn, _ -> ok(conn) end)
    assert {:ok, "wamid.OUT"} = Kapso.send("919800000002", "You're on Board report", [{"done:t1", "Done"}])

    assert_received {:request, "/meta/whatsapp/v24.0/1234567890/messages", ["test-key"], body}
    assert body["to"] == "919800000002" and body["type"] == "interactive"
    assert [%{"reply" => %{"id" => "done:t1", "title" => "Done"}}] = body["interactive"]["action"]["buttons"]
  end

  test "outside the 24-hour window it resends through the template for that button set" do
    capture(fn conn, body ->
      if body["type"] == "template",
        do: ok(conn),
        else:
          conn
          |> Plug.Conn.put_status(400)
          |> Req.Test.json(%{"error" => %{"code" => 131_047, "message" => "Re-engagement message"}})
    end)

    assert {:ok, "wamid.OUT"} =
             Kapso.send("919800000001", "Saish wants to move a deadline", [
               {"approve_change:c1", "Approve"},
               {"reject_change:c1", "Reject"}
             ])

    assert_received {:request, _, _, %{"type" => "interactive"}}
    assert_received {:request, _, _, %{"type" => "template", "template" => template}}
    assert template["name"] == "noa_approval"

    assert [
             %{"type" => "body", "parameters" => [%{"text" => "Saish wants to move a deadline"}]},
             %{"sub_type" => "quick_reply", "parameters" => [%{"payload" => "approve_change:c1"}]} | _
           ] =
             template["components"]
  end

  test "other errors come back as errors" do
    capture(fn conn, _ ->
      conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"error" => %{"code" => 190, "message" => "bad key"}})
    end)

    assert {:error, {:meta, 190, "bad key"}} = Kapso.send("919800000002", "hi", [])
  end
end
