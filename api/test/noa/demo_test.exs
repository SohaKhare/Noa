defmodule Noa.DemoTest do
  @moduledoc "The public demo workspace (Noa.Demo) loads through the real pipeline and can load again."
  use NoaWeb.ConnCase, async: false

  require Ash.Query
  import Ecto.Query, only: [from: 2]

  alias Noa.Work
  alias Noa.Work.{Change, Decision, Proposal, Task}

  test "loads Lumen Labs with sourced work, pending review and only two usable accounts" do
    assert %{org: "lumen-demo", accounts: accounts, messages: 53, new_items: 21} =
             Noa.Demo.load(password: "demo-password-123")

    assert accounts == ["maya@demo.heynoa.xyz", "priya@demo.heynoa.xyz"]
    org = Noa.Orgs.Org |> Ash.Query.filter(slug == "lumen-demo") |> Ash.read_one!(authorize?: false)

    tasks = Task |> Ash.Query.filter(org_id == ^org.id) |> Ash.read!(authorize?: false)
    assert length(tasks) == 13
    assert Enum.all?(tasks, &String.starts_with?(&1.source["episode_id"], "discord:demo-"))
    assert Enum.count(tasks, &(&1.status == :done)) == 3
    assert Enum.count(tasks, &(&1.status == :blocked)) == 2
    assert Enum.find(tasks, &(&1.title == "Rate limiting on the Tulpa API")).owner_id == nil

    decisions = Decision |> Ash.Query.filter(org_id == ^org.id) |> Ash.read!(authorize?: false)
    assert length(decisions) == 8
    assert Enum.count(decisions, &(&1.status == :superseded)) == 1

    pending = Proposal |> Ash.Query.filter(org_id == ^org.id and status == :pending) |> Ash.read!(authorize?: false)
    assert length(pending) == 6

    held = Change |> Ash.Query.filter(org_id == ^org.id and status == :pending) |> Ash.read!(authorize?: false)
    assert [%{kind: :deadline}] = held

    # The published lead can act; the others' passwords are random.
    maya = Noa.Accounts.User |> Ash.Query.filter(email == "maya@demo.heynoa.xyz") |> Ash.read_one!(authorize?: false)
    assert {:ok, [_ | _]} = Work.proposals(org.id, maya)
    assert {:ok, _} = sign_in("maya@demo.heynoa.xyz", "demo-password-123")
    assert :error = sign_in("arjun@demo.heynoa.xyz", "demo-password-123")

    # Running it again adds nothing.
    # The org map is re-saved on every seed load; chat, work and GitHub must not repeat.
    work = ~w(message.received task.saved decision.saved change.saved commit.pushed pr.saved)

    events = fn ->
      Noa.Repo.aggregate(from(e in Noa.Events.Event, where: e.org_id == ^org.id and e.type in ^work), :count)
    end

    before = events.()
    assert %{new_items: 0} = Noa.Demo.load(password: "demo-password-123")
    assert events.() == before
    assert length(Task |> Ash.Query.filter(org_id == ^org.id) |> Ash.read!(authorize?: false)) == 13
  end

  defp sign_in(email, password) do
    strategy = AshAuthentication.Info.strategy!(Noa.Accounts.User, :password)

    case AshAuthentication.Strategy.action(strategy, :sign_in, %{email: email, password: password}) do
      {:ok, user} -> {:ok, user}
      _ -> :error
    end
  end
end
