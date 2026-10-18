defmodule Noa.Ingest.GmailIngestTest do
  use NoaWeb.ConnCase, async: false
  use Oban.Testing, repo: Noa.Repo

  alias Noa.{Events, Work}

  test "email INBOX produces a deduplicated episode and extraction job" do
    root = superadmin!()
    {:ok, org} = Noa.Orgs.create_org(%{name: "MailboxOrg", allowed_domains: ["notyouridea.com"]}, root)

    {:ok, channel} =
      Work.Channel
      |> Ash.Changeset.for_create(:create, %{
        org_id: org.id,
        platform: :email,
        name: "INBOX",
        external_id: "itsupport@notyouridea.com",
        split: true,
        read: true
      })
      |> Ash.create(authorize?: false)

    message = %{
      platform: :email,
      channel: "INBOX",
      channel_id: "itsupport@notyouridea.com",
      message_id: "gmail:#{org.id}:42:7",
      author_id: "customer@example.com",
      author: "customer@example.com",
      text: "Subject: Veriq\n\nPrepare the report",
      at: DateTime.utc_now()
    }

    assert {:ok, event} = Work.record_message(org.id, message)
    assert event.data["platform"] == "email"
    assert event.data["channel_id"] == channel.id
    assert event.data["project_id"] == nil
    assert_enqueued(worker: Work.Extract)
    assert {:duplicate, _} = Work.record_message(org.id, message)
    assert Enum.count(Events.since(0, org_id: org.id, limit: 100), &(&1.type == "message.received")) == 1

    channel |> Ash.Changeset.for_update(:update, %{read: false}) |> Ash.update!(authorize?: false)
    assert {:error, :not_read} = Work.record_message(org.id, %{message | message_id: "different"})
  end
end
