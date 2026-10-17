defmodule Noa.Mailer.ResendTest do
  use ExUnit.Case, async: true

  import Swoosh.Email

  alias Noa.Mailer.Resend

  test "builds a provider payload from a Swoosh email" do
    email =
      new()
      |> from({"Noa", "no-reply@example.com"})
      |> to({"Soha", "soha@example.com"})
      |> subject("Welcome")
      |> text_body("Hello")
      |> html_body("<p>Hello</p>")

    assert Resend.build_payload(email) == %{
             from: "Noa <no-reply@example.com>",
             to: ["Soha <soha@example.com>"],
             subject: "Welcome",
             text: "Hello",
             html: "<p>Hello</p>"
           }
  end
end
