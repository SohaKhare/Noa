defmodule NoaWeb.SecurityTest do
  @moduledoc "The security pass (4.3): JSON-only auth, rate limits, body size, headers."
  use NoaWeb.ConnCase, async: false

  setup do
    on_exit(fn -> Application.put_env(:noa, NoaWeb.Plugs.RateLimit, enabled: false) end)
    :ok
  end

  test "sign-in only takes JSON, so another site can't post a login form" do
    conn =
      Phoenix.ConnTest.build_conn()
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post("/auth/user/password/sign_in", "user[email]=a@b.c&user[password]=x")

    assert conn.status == 415
  end

  test "too many sign-in attempts from one address get 429" do
    Application.put_env(:noa, NoaWeb.Plugs.RateLimit, enabled: true)

    attempt = fn ->
      json_conn() |> post("/auth/user/password/sign_in", %{user: %{email: "nobody@x.test", password: "wrong"}})
    end

    statuses = for _ <- 1..11, do: attempt.().status
    assert Enum.take(statuses, 10) |> Enum.all?(&(&1 != 429))
    assert List.last(statuses) == 429
    assert attempt.() |> get_resp_header("retry-after") != []
  end

  test "API responses carry security headers" do
    conn = json_conn() |> get("/api/me")
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert [csp] = get_resp_header(conn, "content-security-policy")
    assert csp =~ "frame-ancestors 'self'"
  end

  test "bodies over 1 MB are refused" do
    big = Jason.encode!(%{note: String.duplicate("x", 1_100_000)})

    assert_raise Plug.Parsers.RequestTooLargeError, fn ->
      Phoenix.ConnTest.build_conn()
      |> put_req_header("content-type", "application/json")
      |> post("/api/invites/x/accept", big)
    end
  end
end
