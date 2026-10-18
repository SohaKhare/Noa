defmodule Noa.Ingest.Discord.Commands do
  @moduledoc "Noa's Discord commands, private cited replies and permission-checked work buttons (2.5, 2.6)."
  require Logger

  alias Noa.{Connectors, Repo, Work}
  alias Noa.Ingest.Discord
  alias Noa.Ingest.Discord.{Accounts, Links, Views}
  alias NoaWeb.Plugs.RateLimit

  def api, do: Application.get_env(:noa, Discord, [])[:api] || Discord.API

  def spec do
    %{
      name: "noa",
      description: "Your company brain: cited answers, tasks, approvals and project context",
      dm_permission: false,
      options: [
        command("ask", "Ask a cited question privately", [option("question", "Your question", true)]),
        command("link", "Securely link this Discord account to your signed-in Noa account"),
        command("tasks", "Your open tasks, with Start, Done and Need help buttons"),
        command("inbox", "Review proposals and pending lead approvals"),
        command("recap", "Recent decisions for this channel's project"),
        command("brief", "Your project handover brief and agent pack"),
        command("connect", "Org admins: consent to reading this channel", [
          option("project", "Project key (for example veriq); omit for split routing")
        ]),
        command("disconnect", "Org admins: stop reading this channel"),
        command("help", "How to use Noa and connect your workspace"),
        Noa.Ingest.Discord.Meetings.spec()
      ]
    }
  end

  @doc "Upsert /noa and remove only the legacy /tulpa command; leave unrelated commands alone."
  def register(guild_id \\ nil) do
    with {:ok, commands} <- if(guild_id, do: api().guild_commands(to_string(guild_id)), else: api().global_commands()),
         {:ok, _} <-
           if(guild_id, do: api().create_guild(to_string(guild_id), spec()), else: api().create_global(spec())) do
      commands
      |> Enum.filter(&(field(&1, :name) == "tulpa"))
      |> Enum.reduce_while(:ok, fn command, :ok ->
        result =
          if guild_id,
            do: api().delete_guild(to_string(guild_id), field(command, :id)),
            else: api().delete_global(field(command, :id))

        case result do
          {:ok} -> {:cont, :ok}
          {:ok, _} -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    end
  end

  def handle(raw) do
    interaction = Discord.normalize_payload(raw)

    if interaction["type"] == 3 or get_in(interaction, ["data", "name"]) in ["noa", "tulpa"] do
      user_id = user_id(interaction)

      if RateLimit.allow?(:discord_commands, user_id, 40) do
        case api().respond(interaction, %{type: 5, data: %{flags: 64}}) do
          {:ok} -> finish(interaction)
          {:ok, _} -> finish(interaction)
          _ -> :error
        end
      else
        api().respond(interaction, %{
          type: 4,
          data: Map.put(Views.text("Too many requests. Try again in a minute."), :flags, 64)
        })
      end
    else
      :ignore
    end
  rescue
    _ ->
      Logger.warning("Discord interaction response failed")
      :error
  end

  defp finish(interaction) do
    payload =
      try do
        case run(interaction) do
          {:ok, payload} -> payload
          {:error, reason} -> Views.text(error_message(reason))
        end
      rescue
        error ->
          Logger.warning("Discord command failed (#{inspect(error.__struct__)})")
          Views.text("Noa couldn't finish that request. Try again, or use the web app.")
      end

    api().edit(interaction, payload)
  end

  @doc "Gateway dispatch boundary; results are private response payloads."
  def run(interaction) do
    cond do
      interaction["type"] == 3 -> component(interaction)
      get_in(interaction, ["data", "name"]) == "tulpa" -> {:ok, Views.text("Tulpa is now Noa. Use /noa help.")}
      subcommand(interaction) == "help" -> {:ok, Views.text(help())}
      true -> slash(interaction, subcommand(interaction))
    end
  end

  defp slash(interaction, "link") do
    with {:ok, org_id} <- guild_org(interaction),
         {:ok, token} <- Links.issue(org_id, interaction["guild_id"], user_id(interaction)) do
      url = Views.web("/settings") <> "#discord-link=#{token}&discord-org=#{org_id}"

      {:ok,
       Views.text(
         "Open this private link, sign in to Noa, and confirm linking your account. It expires in 10 minutes and works once. Never share it.\n\n#{url}"
       )}
    end
  end

  defp slash(interaction, command) do
    with {:ok, org_id} <- guild_org(interaction),
         {:ok, actor} <- Accounts.actor(org_id, user_id(interaction)) do
      dispatch(command, interaction, org_id, actor)
    end
  end

  defp dispatch("ask", interaction, org_id, actor) do
    question = options(interaction)["question"] || ""
    ask(org_id, question, actor)
  end

  defp dispatch("tasks", _interaction, org_id, actor) do
    with {:ok, people} <- Work.people(org_id, actor),
         person when not is_nil(person) <- Enum.find(people, &(&1.membership && &1.membership.user_id == actor.id)),
         {:ok, tasks} <- Work.tasks(org_id, actor, owner_id: person.id, open: true) do
      {:ok, Views.tasks(org_id, tasks)}
    else
      nil -> {:error, :person_not_found}
      error -> error
    end
  end

  defp dispatch("inbox", _interaction, org_id, actor) do
    with {:ok, proposals} <- Work.proposals(org_id, actor),
         {:ok, changes} <- Work.changes(org_id, actor, status: :pending) do
      {:ok, Views.inbox(org_id, proposals, changes)}
    end
  end

  defp dispatch("recap", interaction, org_id, actor) do
    with {:ok, project} <- channel_project(interaction, org_id, actor),
         {:ok, decisions} <-
           Work.decisions(org_id, actor,
             project_id: project.id,
             status: :active,
             since: DateTime.add(DateTime.utc_now(), -86_400)
           ) do
      lines =
        Enum.map_join(Enum.take(decisions, 6), "\n\n", fn d ->
          quote = d.source && d.source["quote"]

          String.slice(d.statement, 0, 180) <>
            if(is_binary(quote), do: "\nSource: #{String.slice(quote, 0, 100)}", else: "")
        end)

      {:ok,
       Views.text(
         "#{project.name} · decisions in the last day\n\n" <>
           if(lines == "", do: "No decisions recorded.", else: lines) <> "\n\n" <> Views.web("/projects/#{project.key}")
       )}
    end
  end

  defp dispatch("brief", interaction, org_id, actor) do
    with {:ok, project} <- channel_project(interaction, org_id, actor),
         {:ok, brief} <- Work.Brief.build(org_id, project.id, actor) do
      body =
        Enum.take(brief.sections, 4)
        |> Enum.map_join("\n\n", fn section ->
          section.title <>
            "\n" <> (section.items |> Enum.take(3) |> Enum.map_join("\n", &String.slice(&1.text, 0, 150)))
        end)

      {:ok,
       Views.text(
         String.slice("#{project.name} · KT brief\n\n" <> body, 0, 1650) <>
           "\n\nFull brief and agent pack: " <> Views.web("/pack")
       )}
    end
  end

  defp dispatch("connect", interaction, org_id, actor) do
    with :ok <- admin(org_id, actor),
         {:ok, metadata} <- api().channel(interaction["channel_id"]),
         true <- field(metadata, :type) in [0, 5] || {:error, :invalid_channel},
         {:ok, channels} <- Work.channels(org_id, actor),
         {:ok, project_id} <- project_option(org_id, actor, options(interaction)["project"]) do
      id = interaction["channel_id"]
      name = field(metadata, :name)

      existing =
        Enum.find(channels, &(&1.platform == :discord and (&1.external_id == id or &1.name in [name, "#" <> name])))

      attrs = %{external_id: id, read: true, project_id: project_id, split: is_nil(project_id)}

      result =
        if existing do
          with {:ok, channel} <- Work.update_channel(existing.id, attrs, actor) do
            if Discord.enabled?(), do: %{org_id: org_id, channel_id: id} |> Discord.Backfill.new() |> Oban.insert()
            {:ok, channel}
          end
        else
          Work.Setup.create_channel(org_id, Map.merge(attrs, %{platform: :discord, name: name}), actor)
        end

      with {:ok, _} <- result do
        {:ok,
         Views.text(
           "Noa is now reading this channel#{if project_id, do: " for the selected project", else: " with per-message project routing"}. Recent history will load in the background. Only connect channels whose participants have consented."
         )}
      end
    else
      false -> {:error, :invalid_channel}
      error -> error
    end
  end

  defp dispatch("disconnect", interaction, org_id, actor) do
    with :ok <- admin(org_id, actor),
         {:ok, channel} <- mapped_channel(interaction, org_id, actor, false),
         {:ok, _} <- Work.update_channel(channel.id, %{read: false}, actor) do
      {:ok,
       Views.text("Noa stopped reading this channel. Existing sources remain; disconnecting does not erase history.")}
    end
  end

  defp dispatch("meeting", interaction, org_id, actor),
    do: Noa.Ingest.Discord.Meetings.dispatch(interaction, org_id, actor)

  defp dispatch(_, _, _, _), do: {:error, :unknown_command}

  defp component(interaction) do
    with ["noa", org_id, action, id] <- String.split(get_in(interaction, ["data", "custom_id"]) || "", ":"),
         {:ok, _} <- Ecto.UUID.cast(org_id),
         {:ok, _} <- Ecto.UUID.cast(id),
         :ok <- component_guild(interaction, org_id),
         {:ok, actor} <- Accounts.actor(org_id, user_id(interaction)) do
      Repo.transaction(fn ->
        Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", ["discord-action:" <> id])

        case action(action, id, org_id, actor) do
          {:ok, _} -> Views.text("#{action_label(action)}. Open /noa inbox or /noa tasks to refresh.")
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_button}
    end
  end

  defp action(action, id, org_id, actor) when action in ["approve", "reject"] do
    with {:ok, _} <- own_row(Work.Proposal, id, org_id, actor) do
      if action == "approve", do: Work.approve(id, %{}, actor), else: Work.reject(id, actor)
    end
  end

  defp action(action, id, org_id, actor) when action in ["approve_change", "reject_change"] do
    with {:ok, _} <- own_row(Work.Change, id, org_id, actor) do
      if action == "approve_change", do: Work.approve_change(id, actor), else: Work.reject_change(id, actor)
    end
  end

  defp action(action, id, org_id, actor) when action in ["start", "done", "help"] do
    with {:ok, _} <- own_row(Work.Task, id, org_id, actor) do
      attrs =
        case action do
          "start" -> %{status: :in_progress}
          "done" -> %{status: :done}
          "help" -> %{status: :blocked, blocked_reason: "Asked for help in Discord"}
        end

      Work.update_task(id, attrs, actor)
    end
  end

  defp action(_, _, _, _), do: {:error, :invalid_button}

  defp own_row(resource, id, org_id, actor) do
    with {:ok, row} <- Ash.get(resource, id, actor: actor),
         true <- row.org_id == org_id do
      {:ok, row}
    else
      _ -> {:error, :not_found}
    end
  end

  defp component_guild(%{"guild_id" => guild_id}, org_id) when not is_nil(guild_id) do
    if Connectors.org_for_guild(guild_id) == org_id, do: :ok, else: {:error, :not_found}
  end

  # Button-only DM interactions authenticate the linked account and recheck Ash policies.
  defp component_guild(_, _), do: :ok

  defp ask(org_id, question, actor) when is_binary(question) do
    cond do
      String.trim(question) == "" ->
        {:error, :empty_question}

      not RateLimit.allow?(:discord_ask, {org_id, actor.id}, 20) ->
        {:error, :rate_limited}

      true ->
        with {:ok, answer} <- Noa.Agent.ask(org_id, String.slice(question, 0, 500), actor),
             do: {:ok, Views.answer(answer)}
    end
  end

  @doc "Answer a real @Noa mention privately; never expose an actor-scoped answer to the whole Discord channel."
  def mention(raw) do
    message = Discord.normalize_payload(raw)
    bot_id = bot_id()
    mention = bot_id && Regex.run(~r/<@!?#{Regex.escape(bot_id)}>/, message["content"] || "")

    if mention && message["guild_id"] && get_in(message, ["author", "bot"]) != true &&
         RateLimit.allow?(:discord_mentions, get_in(message, ["author", "id"]), 20) do
      with {:ok, org_id} <- guild_org(message),
           {:ok, actor} <- Accounts.actor(org_id, get_in(message, ["author", "id"])),
           {:ok, _} <- mapped_channel(message, org_id, actor),
           question = String.replace(message["content"], ~r/<@!?#{Regex.escape(bot_id)}>/, "") |> String.trim(),
           {:ok, answer} <- ask(org_id, question, actor),
           {:ok, dm} <- api().dm(get_in(message, ["author", "id"])) do
        api().message(to_string(field(dm, :id)), answer)
      else
        {:duplicate, _} ->
          :ignore

        {:error, :discord_not_linked} ->
          api().message(
            message["channel_id"],
            Views.text("Use /noa link to verify your Noa account, then /noa ask for a private answer.")
          )

        {:error, :rate_limited} ->
          :ignore

        _ ->
          :ignore
      end
    else
      :ignore
    end
  end

  @doc "Explicit DM questions are answered privately, never passed to ingest or extraction."
  def direct(raw) do
    message = Discord.normalize_payload(raw)
    id = get_in(message, ["author", "id"])
    question = message["content"] || ""

    if is_binary(id) and is_nil(message["guild_id"]) and get_in(message, ["author", "bot"]) != true and
         String.trim(question) != "" and RateLimit.allow?(:discord_direct, id, 20) do
      result =
        with [org_id] <- Accounts.workspaces(id),
             {:ok, actor} <- Accounts.actor(org_id, id),
             {:ok, answer} <- ask(org_id, question, actor) do
          answer
        else
          [] ->
            Views.text("Run /noa link in your company's connected server before asking Noa privately.")

          [_ | _] ->
            Views.text(
              "You're linked to more than one workspace. Use /noa ask in the intended server so I don't mix company context."
            )

          _ ->
            Views.text("I couldn't answer right now. Try /noa ask in your server.")
        end

      api().message(message["channel_id"], result)
    else
      :ignore
    end
  rescue
    _ -> :error
  end

  defp mapped_channel(interaction, org_id, actor, require_read \\ true) do
    with {:ok, channels} <- Work.channels(org_id, actor),
         {:ok, metadata} <- api().channel(interaction["channel_id"]) do
      name = field(metadata, :name)

      channel =
        Enum.find(
          channels,
          &(&1.platform == :discord and (not require_read or &1.read) and
              (&1.external_id == interaction["channel_id"] or
                 (is_nil(&1.external_id) and &1.name in [name, "#" <> to_string(name)])))
        )

      if channel, do: {:ok, channel}, else: {:error, :channel_not_connected}
    end
  end

  defp channel_project(interaction, org_id, actor) do
    with {:ok, channel} <- mapped_channel(interaction, org_id, actor),
         id when not is_nil(id) <- channel.project_id,
         {:ok, project} <- Ash.get(Work.Project, id, actor: actor) do
      {:ok, project}
    else
      nil -> {:error, :channel_has_no_project}
      error -> error
    end
  end

  defp project_option(_org_id, _actor, nil), do: {:ok, nil}

  defp project_option(org_id, actor, key) do
    with {:ok, projects} <- Work.projects(org_id, actor) do
      case Enum.find(projects, &(&1.key == key or &1.id == key)) do
        nil -> {:error, :project_not_found}
        project -> {:ok, project.id}
      end
    end
  end

  defp guild_org(%{"guild_id" => guild_id}) when is_binary(guild_id) do
    case Connectors.org_for_guild(guild_id) do
      nil -> {:error, :server_not_connected}
      org_id -> {:ok, org_id}
    end
  end

  defp guild_org(_), do: {:error, :guild_required}

  defp admin(org_id, actor) do
    if Noa.Orgs.admin?(actor.id, org_id), do: :ok, else: {:error, :admin_required}
  end

  defp subcommand(i), do: (get_in(i, ["data", "options"]) || []) |> List.first(%{}) |> Map.get("name")

  defp options(i),
    do:
      (get_in(i, ["data", "options"]) || [])
      |> List.first(%{})
      |> Map.get("options", [])
      |> Map.new(&{&1["name"], &1["value"]})

  defp user_id(i),
    do: get_in(i, ["user", "id"]) || get_in(i, ["member", "user", "id"]) || get_in(i, ["member", "user_id"])

  defp field(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))
  defp command(name, description, options \\ []), do: %{type: 1, name: name, description: description, options: options}

  defp option(name, description, required \\ false),
    do: %{type: 3, name: name, description: description, required: required, max_length: 500}

  defp action_label(action),
    do:
      %{
        "approve" => "Proposal approved",
        "reject" => "Proposal rejected",
        "approve_change" => "Change approved",
        "reject_change" => "Change rejected",
        "start" => "Task started",
        "done" => "Task done",
        "help" => "Task marked blocked"
      }[action] || "Updated"

  defp bot_id do
    configured = Application.get_env(:noa, Discord, [])[:bot_id] || System.get_env("DISCORD_CLIENT_ID")
    if configured, do: to_string(configured), else: to_string(Nostrum.Cache.Me.get().id)
  rescue
    _ -> nil
  end

  defp help,
    do:
      "Noa · your company brain\n\n/noa link — verify your account\n/noa ask question:… — private cited answer\n/noa tasks — Start / Done / Need help\n/noa inbox — proposal and lead approval buttons\n/noa recap — today's project decisions\n/noa brief — KT brief and agent pack\n/noa connect project:veriq — org admins consent to channel ingestion\n/noa disconnect — stop reading this channel\n/noa meeting — consented voice notes, stop and cited minutes\n\nAn org admin first connects this server in Noa → Settings → Connectors. Only consented, mapped channels are ingested; DMs are never ingested. Mention @Noa in a mapped channel for a private DM answer."

  defp error_message(:voice_disabled),
    do: "Voice notes are disabled. The Noa admin must install/enable the DAVE-capable voice worker first."

  defp error_message(:llm_not_configured),
    do: "An OpenAI key is required for transcription and typed meeting minutes. No recording was started."

  defp error_message(:voice_busy), do: "Another meeting is active. Finish or cancel it first."

  defp error_message(:meeting_participants_not_linked),
    do: "Everyone in this voice channel must link their Noa account with /noa link before consenting."

  defp error_message(:meeting_source_not_enabled),
    do: "Start from a consented, project-mapped text channel while you are in the intended voice channel."

  defp error_message(:meeting_consent_required),
    do: "Every participant must explicitly consent before recording can start."

  defp error_message(:meeting_not_recording), do: "This session is not active. Use /noa meeting notes to check it."

  defp error_message(:voice_worker_failed),
    do:
      "Voice is not ready or participants changed. Check the bot's Connect permission, join the voice channel and request consent again."

  defp error_message(:discord_not_linked),
    do: "Use /noa link to verify your account first. Display names alone never grant Noa access."

  defp error_message(:server_not_connected),
    do: "An org admin must connect this server in Noa → Settings → Connectors first."

  defp error_message(:admin_required),
    do: "Only a Noa org admin can change channel consent. Discord server permissions alone don't grant that role."

  defp error_message(:guild_required), do: "Run /noa in your company's connected Discord server, not in a DM."
  defp error_message(:already_decided), do: "This item was already decided. Refresh /noa inbox."
  defp error_message(:needs_project), do: "Choose a project for this proposal in the web Inbox before approving it."

  defp error_message(:channel_not_connected),
    do: "This channel isn't enabled for Noa. Ask an org admin to run /noa connect."

  defp error_message(:channel_has_no_project),
    do: "This channel uses split routing. Open a project-mapped channel for its recap or brief."

  defp error_message(:project_not_found), do: "Project not found. Use its Noa project key, such as veriq."
  defp error_message(:person_not_found), do: "Ask an org admin to add your account to the org map in Settings → People."
  defp error_message(:empty_question), do: "Add a question, for example /noa ask question:What's blocking Veriq?"
  defp error_message(:rate_limited), do: "Too many questions. Try again in a minute."
  defp error_message(:invalid_channel), do: "Connect a text or announcement channel, not a thread or DM."

  defp error_message(_),
    do: "That item is unavailable or you don't have permission to act on it. Refresh /noa inbox or use the web app."
end
