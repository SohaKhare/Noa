defmodule Noa.Ingest.Gmail.MessageTest do
  use ExUnit.Case, async: true
  alias Noa.Ingest.Gmail.Message

  test "keeps subject and decoded plain text with sender identity" do
    raw = """
    From: Support <Client@Example.COM>
    Subject: Board export
    Content-Transfer-Encoding: quoted-printable

    Please finish the PDF=20
    by Monday.
    """

    assert {:ok, email} = Message.parse(raw)
    assert email.author_id == "client@example.com"
    assert email.text =~ "Subject: Board export"
    assert email.text =~ "Please finish the PDF "
  end

  test "extracts only plain text from multipart and ignores attachments and HTML" do
    raw = """
    From: Sender <sender@example.com>
    Subject: Update
    Content-Type: multipart/mixed; boundary="AbCd"

    --AbCd
    Content-Type: multipart/alternative; boundary="inner"

    --inner
    Content-Type: text/plain
    Content-Transfer-Encoding: base64

    SGVsbG8gTm9h
    --inner
    Content-Type: text/html

    <script>secret</script>
    --inner--
    --AbCd
    Content-Type: text/plain
    Content-Disposition: attachment; filename=secrets.txt

    PASSWORD
    --AbCd--
    """

    assert {:ok, email} = Message.parse(raw)
    assert email.text == "Subject: Update\n\nHello Noa"
    refute email.text =~ "PASSWORD"
    refute email.text =~ "secret"
  end

  test "HTML-only messages do not enter extraction" do
    assert {:error, :no_plain_text} = Message.parse("From: a@example.com\r\nContent-Type: text/html\r\n\r\n<p>Hi</p>")
  end

  test "missing sender fails closed" do
    assert {:error, :missing_sender} = Message.parse("Subject: hello\r\n\r\nbody")
  end
end
