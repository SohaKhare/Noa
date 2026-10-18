defmodule Noa.Demo do
  @moduledoc """
  The public demo workspace, Lumen Labs (`priv/demo/lumen.json`): a made-up company with
  four projects, eight people, two weeks of chat and GitHub activity, so judges and
  visitors can try Noa without touching a real company's data.

  It loads through the same paths real work takes: messages are recorded as episodes,
  proposals cite them, a lead approves them (tasks and decisions get `EXTRACTED_FROM`
  their message), members move their own work (change records), and some proposals and
  a deadline change are left waiting in the Inbox. Then the graph's `KNOWS_ABOUT` edges
  are recomputed.

      /app/bin/noa rpc 'Noa.Demo.load(password: "...")'    # on the server
      mix noa.demo --password ...                           # locally

  Every person gets an account (`<first name>@demo.heynoa.xyz`). Only the accounts
  named in `published` get `password`; the rest get random passwords nobody holds, so
  their work is attributed honestly but nobody can sign in as them. Nobody in the demo
  has a phone number or chat identity outside the demo, so notifications stay in the app.

  Safe to run again: accounts, people and projects are matched, events are keyed and
  proposals are matched by summary, so a second run adds only what is missing.
  """
  require Ash.Query

  alias Noa.{Events, Work}
  alias Noa.Accounts.User
  alias Noa.Orgs.{Membership, Org}
  alias Noa.Work.{Channel, Person, Project, Proposal, Task}

  @published ~w(maya priya)

  def file, do: Application.app_dir(:noa, "priv/demo/lumen.json")

  def load(opts \\ []) do
    password = Keyword.fetch!(opts, :password)
    seed = file() |> File.read!() |> Jason.decode!()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    org = ensure_org(seed["org"])
    users = Map.new(seed["people"], fn p -> {p["id"], ensure_account(org, p, password)} end)

    {:ok, _} = Work.load_seed(org.id, Map.take(seed, ~w(people projects aliases channels allocations)))

    ctx = %{
      org: org,
      now: now,
      users: users,
      people: Person |> Ash.Query.filter(org_id == ^org.id) |> Ash.read!(authorize?: false) |> Map.new(&{&1.key, &1}),
      projects:
        Project |> Ash.Query.filter(org_id == ^org.id) |> Ash.read!(authorize?: false) |> Map.new(&{&1.key, &1}),
      channels:
        Channel |> Ash.Query.filter(org_id == ^org.id) |> Ash.read!(authorize?: false) |> Map.new(&{&1.name, &1})
    }

    messages = Map.new(seed["messages"], fn m -> {m["id"], record_message(ctx, m)} end)
    fresh = Enum.reduce(seed["items"], MapSet.new(), &item(ctx, messages, &1, &2))

    for c <- seed["held_changes"] || [], MapSet.member?(fresh, c["task"]) do
      {:ok, _} =
        Work.update_task(
          task_by_title(org.id, c["task"]).id,
          %{due_on: Date.add(Date.utc_today(), c["due_in"]), reason: c["reason"]},
          users[c["by"]]
        )
    end

    for c <- seed["commits"] || [], do: commit(ctx, c)
    for pr <- seed["prs"] || [], do: pull_request(ctx, pr)

    if Noa.Graph.enabled?() and Process.whereis(Noa.Graph.Projector) do
      Noa.Graph.Projector.catch_up()
      Noa.Graph.Experts.refresh(org.id)
    end

    %{
      org: org.slug,
      accounts: Enum.map(@published, &to_string(users[&1].email)),
      messages: map_size(messages),
      new_items: MapSet.size(fresh)
    }
  end

  ## Workspace and accounts

  defp ensure_org(%{"name" => name, "slug" => slug}) do
    Org |> Ash.Query.filter(slug == ^slug) |> Ash.read_one!(authorize?: false) ||
      Org
      |> Ash.Changeset.for_create(:create, %{name: name, slug: slug, allowed_domains: []})
      |> Ash.create!(authorize?: false)
  end

  defp ensure_account(org, p, password) do
    email = p["email"]

    user =
      User |> Ash.Query.filter(email == ^email) |> Ash.read_one!(authorize?: false) ||
        User
        |> Ash.Changeset.for_create(:create_with_password, %{
          email: email,
          name: p["name"],
          password: if(p["id"] in @published, do: password, else: random_password())
        })
        |> Ash.create!(authorize?: false)

    unless Membership
           |> Ash.Query.filter(org_id == ^org.id and user_id == ^user.id)
           |> Ash.exists?(authorize?: false) do
      Membership
      |> Ash.Changeset.for_create(:create, %{
        role: String.to_existing_atom(p["role"]),
        title: p["title"],
        org_id: org.id,
        user_id: user.id
      })
      |> Ash.create!(authorize?: false)
    end

    user
  end

  defp random_password, do: 24 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  ## Chat

  # The same `message.received` event Discord ingest writes, keyed so a rerun is a no-op.
  # Extraction is not queued: the proposals below stand in for it, so the demo is stable.
  defp record_message(ctx, m) do
    person = ctx.people[m["author"]]
    channel = ctx.channels[m["channel"]]
    at = DateTime.add(ctx.now, -m["h"] * 3600)
    key = "discord:demo-" <> m["id"]
    {:ok, identity} = Work.identify(ctx.org.id, :discord, "demo-" <> m["author"], person.name)

    result =
      Events.append(
        ctx.org.id,
        "message.received",
        %{
          episode_id: key,
          platform: :discord,
          channel: channel.name,
          channel_id: channel.id,
          project_id: if(channel.split, do: nil, else: channel.project_id),
          author: person.name,
          person_id: identity.person_id,
          identity_id: identity.id,
          text: m["text"],
          thread: m["thread"],
          at: at
        },
        key: key,
        occurred_at: at
      )

    stored_at =
      case result do
        {:duplicate, event} -> event.data["at"]
        _ -> DateTime.to_iso8601(at)
      end

    %{
      "channel" => channel.name,
      "author" => person.name,
      "at" => stored_at,
      "quote" => m["text"],
      "thread" => m["thread"],
      "episode_id" => key
    }
  end

  ## Proposals, approvals and follow-up changes

  defp item(ctx, messages, it, fresh) do
    summary = it["title"] || it["statement"] || summary(it)

    if Proposal |> Ash.Query.filter(org_id == ^ctx.org.id and summary == ^summary) |> Ash.exists?(authorize?: false) do
      fresh
    else
      owner = ctx.people[it["owner"] || it["by"]]
      project = ctx.projects[it["project"]]
      task = it["task"] && task_by_title(ctx.org.id, it["task"])

      proposal =
        Proposal
        |> Ash.Changeset.for_create(:create, %{
          kind: String.to_existing_atom(it["kind"]),
          summary: summary,
          data: data(it, owner),
          confidence: it["confidence"] || 0.86,
          source: messages[it["msg"]],
          org_id: ctx.org.id,
          project_id: project && project.id,
          owner_id: owner && owner.id,
          task_id: task && task.id
        })
        |> Ash.create!(authorize?: false)

      if it["pending"] do
        fresh
      else
        {:ok, decided} = Work.approve(proposal.id, %{}, ctx.users["maya"])

        for step <- it["history"] || [] do
          {:ok, _} =
            Work.update_task(
              decided.task_id,
              %{status: String.to_existing_atom(step["status"]), blocked_reason: step["blocker"]},
              ctx.users[step["by"]]
            )
        end

        MapSet.put(fresh, summary)
      end
    end
  end

  defp summary(%{"kind" => "deadline_change"} = it), do: "Move \"#{it["task"]}\" to #{due(it["due_in"])}"

  defp summary(%{"kind" => "status_change"} = it),
    do: "Mark \"#{it["task"]}\" #{String.replace(it["status"], "_", " ")}"

  defp data(%{"kind" => "task"} = it, owner),
    do: %{"title" => it["title"], "due" => it["due_in"] && due(it["due_in"]), "owner" => owner && owner.name}

  defp data(%{"kind" => "decision"} = it, _owner),
    do: %{"kind" => "decision", "affects" => [], "supersedes_ref" => it["supersedes"]}

  defp data(%{"kind" => "deadline_change"} = it, _owner),
    do: %{"new_due" => due(it["due_in"]), "reason" => it["reason"]}

  defp data(%{"kind" => "status_change"} = it, _owner), do: %{"status" => it["status"]}

  defp due(days), do: Date.utc_today() |> Date.add(days) |> Date.to_iso8601()

  defp task_by_title(org_id, title),
    do: Task |> Ash.Query.filter(org_id == ^org_id and title == ^title) |> Ash.read_one!(authorize?: false)

  ## GitHub

  # The events the GitHub App webhook writes (`Noa.GitHub`), for a repo that doesn't exist.
  defp commit(ctx, c) do
    project = ctx.projects[c["project"]]
    person = ctx.people[c["author"]]
    at = DateTime.add(ctx.now, -c["h"] * 3600)
    sha = :crypto.hash(:sha, project.key <> c["message"]) |> Base.encode16(case: :lower)

    Events.append(
      ctx.org.id,
      "commit.pushed",
      %{
        sha: sha,
        message: c["message"],
        url: nil,
        branch: "main",
        repo: project.repo,
        project_id: project.id,
        author: List.first(person.handles) || person.name,
        person_id: person.id,
        at: at
      },
      key: "github:commit:demo-" <> sha,
      occurred_at: at
    )
  end

  defp pull_request(ctx, pr) do
    project = ctx.projects[pr["project"]]
    person = ctx.people[pr["author"]]
    at = DateTime.add(ctx.now, -pr["h"] * 3600)
    id = "#{project.repo}##{pr["number"]}"

    Events.append(
      ctx.org.id,
      "pr.saved",
      %{
        id: id,
        number: pr["number"],
        title: pr["title"],
        state: pr["state"],
        url: nil,
        branch: nil,
        repo: project.repo,
        project_id: project.id,
        author: List.first(person.handles) || person.name,
        person_id: person.id,
        merged_at: if(pr["state"] == "merged", do: at),
        at: at
      },
      key: "github:pr:demo-" <> id,
      occurred_at: at
    )
  end
end
