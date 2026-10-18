defmodule Noa.Ingest.Discord.CommandsTest do
  use NoaWeb.ConnCase, async: false
  use Oban.Testing, repo: Noa.Repo

  alias Noa.{Connectors, Events, Work}
  alias Noa.Ingest.Discord.{Accounts, Commands, Consumer, Links, Views}

  @guild "1502935253809893386"
  @channel "1502935253809893387"
  @admin_id "1502935253809893388"
  @member_id "1502935253809893389"
  @guest_id "1502935253809893390"
  @bot_id "1533733435187658884"

  defmodule API do
    def global_commands, do: {:ok, [%{id: 1, name: "tulpa"}, %{id: 2, name: "other"}]}

    def guild_commands(id),
      do:
        (
          send(self(), {:guild_commands, id})
          global_commands()
        )

    def create_global(spec),
      do:
        (
          send(self(), {:create_global, spec})
          {:ok, %{id: 3}}
        )

    def create_guild(id, spec),
      do:
        (
          send(self(), {:create_guild, id, spec})
          {:ok, %{id: 3}}
        )

    def delete_global(id),
      do:
        (
          send(self(), {:delete_global, id})
          {:ok}
        )

    def delete_guild(guild, id),
      do:
        (
          send(self(), {:delete_guild, guild, id})
          {:ok}
        )

    def respond(interaction, payload) do
      send(self(), {:respond, interaction, payload})
      Process.get(:discord_defer, {:ok})
    end

    def edit(interaction, payload),
      do:
        (
          send(self(), {:edit, interaction, payload})
          {:ok, %{id: 1}}
        )

    def channel(_id), do: {:ok, %{name: Process.get(:discord_channel_name, "veriq"), type: 0}}

    def dm(id),
      do:
        (
          send(self(), {:dm, id})
          {:ok, %{id: 1_502_935_253_809_893_399}}
        )

    def message(id, payload),
      do:
        (
          send(self(), {:message, id, payload})
          {:ok, %{id: 1}}
        )
  end

  setup do
    previous =
      for key <- [Noa.Ingest.Discord, Noa.Graph, Noa.Agent, :discord_bot_token],
          into: %{},
          do: {key, Application.get_env(:noa, key)}

    Application.put_env(:noa, Noa.Ingest.Discord, api: API, bot_id: @bot_id)
    Application.put_env(:noa, Noa.Graph, [])
    Application.put_env(:noa, Noa.Agent, generator: Noa.Agent.Extractive)
    Application.put_env(:noa, :discord_bot_token, "test-only")

    on_exit(fn ->
      Enum.each(previous, fn {key, value} ->
        if value, do: Application.put_env(:noa, key, value), else: Application.delete_env(:noa, key)
      end)
    end)

    root = superadmin!()
    {:ok, org} = Noa.Orgs.create_org(%{name: "Acme", allowed_domains: ["acme.test"]}, root)
    {:ok, _, url} = Noa.Orgs.invite(org, "admin@acme.test", :org_admin, root)
    admin = accept!(url, "Admin")
    {:ok, _, url} = Noa.Orgs.invite(org, "bob@acme.test", :member, admin)
    member = accept!(url, "Bob")
    {:ok, _, url} = Noa.Orgs.invite(org, "eve@acme.test", :guest, admin)
    guest = accept!(url, "Eve")
    {:ok, _} = Work.Setup.add_members(org.id, admin)
    {:ok, project} = Work.Setup.create_project(org.id, %{name: "Veriq", key: "veriq"}, admin)
    :ok = Connectors.connect_discord(org.id, @guild, admin)

    {:ok, channel} =
      Work.Setup.create_channel(org.id, %{name: "veriq", external_id: @channel, project_id: project.id}, admin)

    {:ok, people} = Work.people(org.id, admin)
    person = Enum.find(people, &(&1.membership.user_id == member.id))

    {:ok, task} =
      Work.create_task(org.id, %{title: "Ship the Board report", project_id: project.id, owner_id: person.id}, admin)

    %{
      root: root,
      org: org,
      admin: admin,
      member: member,
      guest: guest,
      person: person,
      project: project,
      task: task,
      channel: channel
    }
  end

  test "registration renames legacy global and guild commands without deleting unrelated commands" do
    assert :ok = Commands.register()
    assert_receive {:create_global, %{name: "noa", dm_permission: false, options: options}}
    assert Enum.map(options, & &1.name) == ~w(ask link tasks inbox recap brief connect disconnect help)
    assert_receive {:delete_global, 1}
    refute_receive {:delete_global, 2}
    assert :ok = Commands.register(@guild)
    assert_receive {:create_guild, @guild, %{name: "noa"}}
    assert_receive {:delete_guild, @guild, 1}
    refute_receive {:delete_guild, @guild, 2}
  end

  test "inferred names and plain Discord handles cannot authenticate commands", ctx do
    {:ok, _} = Work.identify(ctx.org.id, :discord, @member_id, "Bob")
    assert {:error, :discord_not_linked} = Accounts.actor(ctx.org.id, @member_id)
    {:ok, _} = Work.Setup.update_person(ctx.person.id, %{handles: [@member_id]}, ctx.admin)
    assert {:error, :discord_not_linked} = Accounts.actor(ctx.org.id, @member_id)
    assert {:error, :discord_not_linked} = Commands.run(slash("tasks", @member_id))
  end

  test "one-time gateway link is confirmed by the signed-in user and can be revoked", ctx do
    {:ok, token} = Links.issue(ctx.org.id, @guild, @member_id)
    path = "/api/orgs/#{ctx.org.id}/me/discord"
    assert signed_in(ctx.member) |> post(path, %{code: token}) |> json_response(200) == %{"discord_id" => @member_id}
    assert {:ok, actor} = Accounts.actor(ctx.org.id, @member_id)
    assert actor.id == ctx.member.id
    assert signed_in(ctx.member) |> post(path, %{code: token}) |> json_response(422)
    assert signed_in(ctx.member) |> get(path) |> json_response(200) == %{"discord_id" => @member_id}
    assert signed_in(ctx.member) |> delete(path) |> json_response(200) == %{"discord_id" => nil}
    assert {:error, :discord_not_linked} = Accounts.actor(ctx.org.id, @member_id)
  end

  test "link tokens expire and another member cannot take an already verified account", ctx do
    link(ctx, ctx.member, @member_id)
    {:ok, token} = Links.issue(ctx.org.id, @guild, @member_id)
    assert {:error, :discord_already_linked} = Links.claim(ctx.org.id, token, ctx.guest)
    {:ok, token} = Links.issue(ctx.org.id, @guild, @guest_id)
    hash = :crypto.hash(:sha256, token)

    :sys.replace_state(Links, fn state ->
      Map.update!(state, hash, fn {org, guild, id, _} -> {org, guild, id, System.monotonic_time(:second) - 1} end)
    end)

    assert {:error, :discord_link_invalid} = Links.claim(ctx.org.id, token, ctx.guest)
  end

  test "generic person updates cannot forge verified handles or transfer a linked account", ctx do
    assert {:error, %Ash.Error.Invalid{}} =
             Work.Setup.update_person(ctx.person.id, %{handles: ["discord:#{@admin_id}"]}, ctx.admin)

    link(ctx, ctx.member, @member_id)
    assert {:error, %Ash.Error.Invalid{}} = Work.Setup.update_person(ctx.person.id, %{handles: []}, ctx.admin)
    [admin_membership] = Noa.Orgs.memberships_for(ctx.admin)

    assert {:error, %Ash.Error.Invalid{}} =
             Work.Setup.update_person(ctx.person.id, %{membership_id: admin_membership.id}, ctx.admin)
  end

  test "link commands are private, use URL fragments and reject unconnected servers and DMs", ctx do
    assert {:ok, payload} = Commands.run(slash("link", @member_id))
    assert payload.content =~ "/settings#discord-link="
    assert payload.content =~ "discord-org=#{ctx.org.id}"
    refute payload.content =~ "?discord-link"

    assert {:error, :server_not_connected} =
             Commands.run(Map.put(slash("link", @member_id), "guild_id", "1502935253809893391"))

    assert {:error, :guild_required} = Commands.run(Map.delete(slash("link", @member_id), "guild_id"))
  end

  test "commands defer ephemerally before work and don't execute if acknowledgement fails", ctx do
    link(ctx, ctx.member, @member_id)
    assert {:ok, _} = Commands.handle(slash("tasks", @member_id))
    assert_receive {:respond, _, %{type: 5, data: %{flags: 64}}}
    assert_receive {:edit, _, %{content: content, components: [_], allowed_mentions: %{parse: []}}}
    assert content =~ "Ship the Board report"
    Process.put(:discord_defer, {:error, :network})
    assert :error = Commands.handle(button(ctx.org.id, "done", ctx.task.id, @member_id))
    assert Ash.get!(Work.Task, ctx.task.id, actor: ctx.admin).status == :todo
  end

  test "verified task buttons update through Work; guests and unlinked users cannot write", ctx do
    link(ctx, ctx.member, @member_id)
    link(ctx, ctx.guest, @guest_id)
    assert {:ok, _} = Commands.run(button(ctx.org.id, "start", ctx.task.id, @member_id))
    assert Ash.get!(Work.Task, ctx.task.id, actor: ctx.admin).status == :in_progress
    assert {:error, _} = Commands.run(button(ctx.org.id, "done", ctx.task.id, @guest_id))
    assert {:error, _} = Commands.run(button(ctx.org.id, "done", ctx.task.id, @admin_id))
    assert {:ok, _} = Commands.run(button(ctx.org.id, "help", ctx.task.id, @member_id))
    assert Ash.get!(Work.Task, ctx.task.id, actor: ctx.admin).status == :blocked
    assert {:ok, _} = Commands.run(button(ctx.org.id, "done", ctx.task.id, @member_id))
    assert Ash.get!(Work.Task, ctx.task.id, actor: ctx.admin).status == :done
    assert Enum.any?(Events.since(0, org_id: ctx.org.id), &(&1.type == "change.saved"))
  end

  test "proposal buttons apply once, and rejection does not create a task", ctx do
    link(ctx, ctx.member, @member_id)
    proposal = proposal(ctx)
    assert {:ok, _} = Commands.run(button(ctx.org.id, "approve", proposal.id, @member_id))
    assert {:error, :already_decided} = Commands.run(button(ctx.org.id, "approve", proposal.id, @member_id))
    assert Ash.get!(Work.Proposal, proposal.id, actor: ctx.admin).status == :approved
    assert {:ok, tasks} = Work.tasks(ctx.org.id, ctx.admin)
    assert Enum.count(tasks, &(&1.title == "Prepare the report")) == 1
    rejected = proposal(ctx)
    assert {:ok, _} = Commands.run(button(ctx.org.id, "reject", rejected.id, @member_id))
    assert Ash.get!(Work.Proposal, rejected.id, actor: ctx.admin).status == :rejected
  end

  test "lead approval buttons work in DMs, recheck roles and refuse stale clicks", ctx do
    link(ctx, ctx.member, @member_id)
    link(ctx, ctx.admin, @admin_id)
    {:ok, _} = Work.update_task(ctx.task.id, %{due_on: ~D[2026-12-01]}, ctx.member)
    {:ok, [change]} = Work.changes(ctx.org.id, ctx.admin, status: :pending)
    assert {:error, _} = Commands.run(button(ctx.org.id, "approve_change", change.id, @member_id))

    interaction =
      button(ctx.org.id, "approve_change", change.id, @admin_id)
      |> Map.delete("guild_id")
      |> Map.delete("member")
      |> Map.put("user", %{"id" => @admin_id})

    assert {:ok, _} = Commands.run(interaction)
    assert Ash.get!(Work.Task, ctx.task.id, actor: ctx.admin).due_on == ~D[2026-12-01]
    assert {:error, _} = Commands.run(interaction)
  end

  test "foreign workspaces, forged guild contexts and removed memberships cannot act", ctx do
    link(ctx, ctx.member, @member_id)
    {:ok, foreign} = Noa.Orgs.create_org(%{name: "Other", allowed_domains: ["other.test"]}, ctx.root)
    {:ok, project} = Work.Setup.create_project(foreign.id, %{name: "Private"}, ctx.root)
    {:ok, task} = Work.create_task(foreign.id, %{title: "Other company's secret", project_id: project.id}, ctx.root)
    assert {:error, _} = Commands.run(button(ctx.org.id, "done", task.id, @member_id))

    assert {:error, _} =
             Commands.run(
               Map.put(button(ctx.org.id, "done", ctx.task.id, @member_id), "guild_id", "1502935253809893391")
             )

    [membership] = Noa.Orgs.memberships_for(ctx.member)
    :ok = Noa.Orgs.remove_member(membership.id, ctx.admin)
    assert {:error, :discord_not_linked} = Accounts.actor(ctx.org.id, @member_id)
  end

  test "channel consent requires Noa org admin, supports split routing and can be stopped", ctx do
    link(ctx, ctx.member, @member_id)
    link(ctx, ctx.admin, @admin_id)
    assert {:error, :admin_required} = Commands.run(slash("disconnect", @member_id))
    assert {:ok, _} = Commands.run(slash("disconnect", @admin_id))
    refute Ash.get!(Work.Channel, ctx.channel.id, actor: ctx.admin).read
    assert {:ok, _} = Commands.run(slash("connect", @admin_id, %{"project" => "veriq"}))
    channel = Ash.get!(Work.Channel, ctx.channel.id, actor: ctx.admin)
    assert channel.read and channel.project_id == ctx.project.id and not channel.split
    assert {:ok, _} = Commands.run(slash("connect", @admin_id))
    assert Ash.get!(Work.Channel, ctx.channel.id, actor: ctx.admin).split

    assert {:error, :project_not_found} = Commands.run(slash("connect", @admin_id, %{"project" => "missing"}))
  end

  test "cited slash replies and mentions stay private, never post company answers publicly", ctx do
    link(ctx, ctx.member, @member_id)
    assert {:ok, payload} = Commands.run(slash("ask", @member_id, %{"question" => "What's the Board report?"}))
    assert payload.content =~ "Sources"
    assert payload.allowed_mentions == %{parse: []}
    message = guild_message("<@#{@bot_id}> What's the Board report?")
    assert {:ok, _} = Consumer.handle_event({:MESSAGE_CREATE, message, %{}})
    assert_receive {:dm, @member_id}
    assert_receive {:message, "1502935253809893399", %{content: answer}}
    assert answer =~ "Sources"
    refute_receive {:message, @channel, _}
    assert {:duplicate, _} = Consumer.handle_event({:MESSAGE_CREATE, message, %{}})
    refute_receive {:dm, _}
    {:ok, _} = Work.update_channel(ctx.channel.id, %{read: false}, ctx.admin)

    assert {:error, :not_read} =
             Consumer.handle_event({:MESSAGE_CREATE, Map.put(message, "id", "1502935253809893499"), %{}})

    refute_receive {:dm, _}
  end

  test "explicit DM questions are answered without becoming Episodes or extraction jobs", ctx do
    link(ctx, ctx.member, @member_id)
    before = Events.since(0, org_id: ctx.org.id) |> Enum.count(&(&1.type == "message.received"))
    assert Accounts.workspaces(@member_id) == [ctx.org.id]
    message = guild_message("What's the Board report?") |> Map.delete("guild_id")
    assert {:ok, _} = Consumer.handle_event({:MESSAGE_CREATE, message, %{}})
    assert_receive {:message, @channel, %{content: answer}}
    assert answer =~ "Sources"
    after_count = Events.since(0, org_id: ctx.org.id) |> Enum.count(&(&1.type == "message.received"))
    assert before == after_count
  end

  test "Discord notifications carry real buttons only to verified accounts; unlink stops delivery", ctx do
    link(ctx, ctx.member, @member_id)
    person = Ash.get!(Work.Person, ctx.person.id, actor: ctx.admin)
    assert {:ok, _} = Noa.Ingest.Discord.dm(person, "Your task", buttons: [{"done:#{ctx.task.id}", "Done"}])
    assert_receive {:message, _, %{components: [%{components: [%{custom_id: custom_id}]}]}}
    assert custom_id == "noa:#{ctx.org.id}:done:#{ctx.task.id}"
    assert String.length(custom_id) <= 100
    assert {:ok, nil} = Accounts.unlink(ctx.org.id, ctx.member)
    assert {:error, :no_discord_account} = Noa.Ingest.Discord.dm(person, "Must not send")
  end

  test "inbox, recap and brief use the mapped project and normal permission-aware reads", ctx do
    link(ctx, ctx.member, @member_id)
    proposal(ctx)
    assert {:ok, inbox} = Commands.run(slash("inbox", @member_id))
    assert inbox.content =~ "Prepare the report"
    assert [%{components: [_, _]}] = inbox.components

    Work.Decision
    |> Ash.Changeset.for_create(
      :create,
      %{
        org_id: ctx.org.id,
        project_id: ctx.project.id,
        statement: "Use the blue theme",
        kind: :decision,
        source: %{"quote" => "We chose blue"}
      },
      actor: ctx.admin
    )
    |> Ash.create!()

    assert {:ok, recap} = Commands.run(slash("recap", @member_id))
    assert recap.content =~ "Use the blue theme"
    assert recap.content =~ "We chose blue"
    assert {:ok, brief} = Commands.run(slash("brief", @member_id))
    assert brief.content =~ "KT brief"
    assert brief.content =~ "/pack"
  end

  test "lead can reject a pending deadline without changing the task", ctx do
    link(ctx, ctx.admin, @admin_id)
    {:ok, _} = Work.update_task(ctx.task.id, %{due_on: ~D[2026-12-01]}, ctx.member)
    {:ok, [change]} = Work.changes(ctx.org.id, ctx.admin, status: :pending)
    assert {:ok, _} = Commands.run(button(ctx.org.id, "reject_change", change.id, @admin_id))
    assert Ash.get!(Work.Change, change.id, actor: ctx.admin).status == :rejected
    assert Ash.get!(Work.Task, ctx.task.id, actor: ctx.admin).due_on == nil
  end

  test "new proposals send actionable Discord notifications and Need help alerts the lead", ctx do
    link(ctx, ctx.member, @member_id)
    link(ctx, ctx.admin, @admin_id)
    {:ok, _} = Work.set_notifications(ctx.person.id, %{notify_via: :discord}, ctx.member)
    {:ok, people} = Work.people(ctx.org.id, ctx.admin)
    admin_person = Enum.find(people, &(&1.membership.user_id == ctx.admin.id))
    {:ok, _} = Work.set_notifications(admin_person.id, %{notify_via: :discord}, ctx.admin)
    proposal = proposal(ctx)
    [event] = Events.history(ctx.org.id, proposal.id)
    assert [{:ok, :discord}] = Noa.WhatsApp.Notifier.handle(event)
    assert_receive {:message, _, %{content: content, components: [%{components: [approve, reject]}]}}
    assert content =~ "Noa found a proposal"
    assert approve.custom_id =~ ":approve:"
    assert reject.custom_id =~ ":reject:"

    assert {:ok, _} = Commands.run(button(ctx.org.id, "help", ctx.task.id, @member_id))
    event = Events.history(ctx.org.id, ctx.task.id) |> Enum.filter(&(&1.type == "task.saved")) |> List.last()
    assert [{:ok, :discord}] = Noa.WhatsApp.Notifier.handle(event)
    assert_receive {:dm, @admin_id}
    assert_receive {:message, _, %{content: help}}
    assert help =~ "needs help"
  end

  test "disconnecting the server immediately revokes DM and command authentication", ctx do
    link(ctx, ctx.member, @member_id)
    assert {:ok, _} = Accounts.actor(ctx.org.id, @member_id)
    :ok = Connectors.disconnect(ctx.org.id, "discord", ctx.admin)
    assert Accounts.workspaces(@member_id) == []
    assert {:error, :discord_not_linked} = Accounts.actor(ctx.org.id, @member_id)
    assert {:error, :server_not_connected} = Commands.run(slash("tasks", @member_id))
  end

  test "Nostrum interaction structs resolve the top-level user copied from the guild member", ctx do
    link(ctx, ctx.member, @member_id)
    raw = slash("tasks", @member_id)
    raw = put_in(raw, ["data", "options", Access.at(0), "type"], 1)
    raw = raw |> Jason.encode!() |> Jason.decode!(keys: :atoms)
    interaction = Nostrum.Struct.Interaction.to_struct(raw)
    assert {:ok, _} = Commands.handle(interaction)
    assert_receive {:edit, _, %{content: content}}
    assert content =~ "Ship the Board report"
  end

  test "gateway rate limiting responds privately without doing more work" do
    interaction = slash("help", "999999999999999999")
    for _ <- 1..40, do: Commands.handle(interaction)
    Commands.handle(interaction)
    assert_receive {:respond, _, %{type: 4, data: %{flags: 64, content: content}}}
    assert content =~ "Too many requests"
  end

  test "component formatting obeys Discord limits and suppresses all mentions", ctx do
    payload =
      Views.text(
        String.duplicate("x", 3000),
        Views.notification_buttons(ctx.org.id, [{"approve_change:#{Ecto.UUID.generate()}", "Approve"}])
      )

    assert String.length(payload.content) < 2000
    assert payload.allowed_mentions == %{parse: []}
    for row <- payload.components, button <- row.components, do: assert(String.length(button.custom_id) <= 100)
  end

  defp link(ctx, user, id) do
    {:ok, token} = Links.issue(ctx.org.id, @guild, id)
    assert {:ok, ^id} = Links.claim(ctx.org.id, token, user)
  end

  defp proposal(ctx) do
    Work.Proposal
    |> Ash.Changeset.for_create(
      :create,
      %{
        org_id: ctx.org.id,
        project_id: ctx.project.id,
        owner_id: ctx.person.id,
        kind: :task,
        summary: "Prepare the report",
        data: %{"title" => "Prepare the report"},
        source: %{"quote" => "on it"}
      },
      actor: ctx.admin
    )
    |> Ash.create!()
  end

  defp slash(command, user_id, opts \\ %{}) do
    %{
      "id" => "1502935253809893490",
      "application_id" => @bot_id,
      "token" => "test-only",
      "type" => 2,
      "guild_id" => @guild,
      "channel_id" => @channel,
      "member" => %{"user" => %{"id" => user_id}},
      "data" => %{
        "name" => "noa",
        "options" => [
          %{"name" => command, "options" => Enum.map(opts, fn {key, value} -> %{"name" => key, "value" => value} end)}
        ]
      }
    }
  end

  defp button(org_id, action, id, user_id),
    do:
      slash("inbox", user_id)
      |> Map.put("type", 3)
      |> Map.put("data", %{"custom_id" => "noa:#{org_id}:#{action}:#{id}"})

  defp guild_message(content),
    do: %{
      "id" => "1502935253809893491",
      "guild_id" => @guild,
      "channel_id" => @channel,
      "channel_name" => "veriq",
      "content" => content,
      "author" => %{"id" => @member_id, "username" => "Bob", "bot" => false}
    }
end
