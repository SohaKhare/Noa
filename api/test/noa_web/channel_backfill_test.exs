defmodule NoaWeb.ChannelBackfillTest do
  @moduledoc "Settings → Channels (1.18, 2.10): load a mapped Discord channel's history on demand, and remove dead mappings."
  use NoaWeb.ConnCase, async: false
  use Oban.Testing, repo: Noa.Repo

  alias Noa.Work

  @seed Path.expand("../../../docs/seeds/nyi.json", __DIR__) |> File.read!() |> Jason.decode!()

  setup do
    root = superadmin!()
    {:ok, org} = Noa.Orgs.create_org(%{name: "NotYourIdea", allowed_domains: ["notyouridea.com"]}, root)
    {:ok, _, url} = Noa.Orgs.invite(org, "vedant@notyouridea.com", :org_admin, root)
    vedant = accept!(url, "Vedant")
    {:ok, _, url} = Noa.Orgs.invite(org, "saish@notyouridea.com", :pm, vedant)
    saish = accept!(url, "Saish")
    {:ok, _} = Work.load_seed(org.id, @seed)
    Application.put_env(:noa, :discord_bot_token, "test-token")
    on_exit(fn -> Application.delete_env(:noa, :discord_bot_token) end)
    %{org: org, vedant: vedant, saish: saish}
  end

  defp api(user, method, path, body \\ %{}), do: signed_in(user) |> dispatch(@endpoint, method, path, body)

  test "connecting a channel can skip the history load; loading it later queues one job", %{org: org, vedant: vedant} do
    base = "/api/orgs/#{org.id}"
    veriq = Enum.find(Work.projects(org.id, vedant) |> elem(1), &(&1.key == "veriq"))

    %{"channel" => ch} =
      api(vedant, :post, "#{base}/channels", %{
        name: "#ai-services",
        external_id: "111",
        project_id: veriq.id,
        backfill: false
      })
      |> json_response(201)

    refute_enqueued(worker: Noa.Ingest.Discord.Backfill)

    assert %{"backfill" => "queued"} = api(vedant, :post, "#{base}/channels/#{ch["id"]}/backfill") |> json_response(200)
    assert_enqueued(worker: Noa.Ingest.Discord.Backfill, args: %{org_id: org.id, channel_id: "111"})

    assert %{"backfill" => "already_queued"} =
             api(vedant, :post, "#{base}/channels/#{ch["id"]}/backfill") |> json_response(200)
  end

  test "channels with no Discord id can't load history; only org admins can load or remove", ctx do
    %{org: org, vedant: vedant, saish: saish} = ctx
    base = "/api/orgs/#{org.id}"
    dev = Work.Channel |> Ash.read!(authorize?: false) |> Enum.find(&(&1.org_id == org.id and &1.name == "#dev"))

    assert api(vedant, :post, "#{base}/channels/#{dev.id}/backfill") |> json_response(422)
    assert api(saish, :post, "#{base}/channels/#{dev.id}/backfill") |> json_response(403)
    assert api(saish, :delete, "#{base}/channels/#{dev.id}") |> json_response(403)

    assert api(vedant, :delete, "#{base}/channels/#{dev.id}") |> json_response(200)
    refute Work.Channel |> Ash.read!(authorize?: false) |> Enum.any?(&(&1.id == dev.id))
  end
end
