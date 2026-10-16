defmodule Noa.Work do
  @moduledoc """
  Projects, people, tasks and the Inbox (1.24). Contract: docs/schema.md.

  Every function that acts for a person takes the `actor` and goes through Ash
  policies. `save_proposals/3` and `load_seed/2` run as Noa itself, without an actor.

  Writes go through the functions here, not straight to the resources, so the event
  log (1.8) can wrap each one and append its event in the same transaction.
  """
  use Ash.Domain, otp_app: :noa

  require Ash.Query
  import Ecto.Query, only: [from: 2]

  alias Noa.Extraction
  alias Noa.Repo
  alias Noa.Work.{Allocation, Channel, Identity, Person, Project, ProjectAlias, Proposal, Task}

  resources do
    resource(Person)
    resource(Project)
    resource(ProjectAlias)
    resource(Allocation)
    resource(Channel)
    resource(Task)
    resource(Proposal)
    resource(Identity)
  end

  ## Reads

  @doc "People in the org with their current allocations."
  def people(org_id, actor) do
    Person
    |> Ash.Query.filter(org_id == ^org_id)
    |> Ash.Query.load([:allocations, :membership])
    |> Ash.Query.sort(:name)
    |> Ash.read(actor: actor)
    |> current_allocations()
  end

  @doc "Projects in the org with lead, aliases and current allocations."
  def projects(org_id, actor) do
    Project
    |> Ash.Query.filter(org_id == ^org_id)
    |> Ash.Query.load([:lead, :aliases, :allocations])
    |> Ash.Query.sort(:name)
    |> Ash.read(actor: actor)
    |> current_allocations()
  end

  # Allocations are kept after they end (a shift sets `ends_on`); lists show current ones.
  defp current_allocations({:ok, rows}) do
    today = Date.utc_today()
    current? = &(is_nil(&1.ends_on) or Date.compare(&1.ends_on, today) != :lt)
    {:ok, Enum.map(rows, &%{&1 | allocations: Enum.filter(&1.allocations, current?)})}
  end

  defp current_allocations(error), do: error

  def channels(org_id, actor) do
    Channel |> Ash.Query.filter(org_id == ^org_id) |> Ash.Query.sort(:name) |> Ash.read(actor: actor)
  end

  @doc "Tasks in the org. Filters: `project_id`, `owner_id`, `open: true` (not done)."
  def tasks(org_id, actor, filters \\ []) do
    Task
    |> Ash.Query.filter(org_id == ^org_id)
    |> then(fn q -> if id = filters[:project_id], do: Ash.Query.filter(q, project_id == ^id), else: q end)
    |> then(fn q -> if id = filters[:owner_id], do: Ash.Query.filter(q, owner_id == ^id), else: q end)
    |> then(fn q -> if filters[:open], do: Ash.Query.filter(q, status != :done), else: q end)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read(actor: actor)
  end

  @doc "Inbox: proposals in the org, newest first. `status` defaults to `:pending`."
  def proposals(org_id, actor, status \\ :pending) do
    Proposal
    |> Ash.Query.filter(org_id == ^org_id and status == ^status)
    |> Ash.Query.load([:project, :owner])
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read(actor: actor)
  end

  @doc "The person record linked to the user's membership in the org, or nil."
  def person_for(%{id: user_id}, org_id) do
    Person
    |> Ash.Query.filter(org_id == ^org_id and membership.user_id == ^user_id)
    |> Ash.read_one!(authorize?: false)
  end

  ## Tasks

  def create_task(org_id, attrs, actor) do
    Task
    |> Ash.Changeset.for_create(:create, Map.merge(attrs, %{org_id: org_id, created_by_id: actor.id}), actor: actor)
    |> Ash.create()
  end

  def update_task(task_id, attrs, actor) do
    with {:ok, task} <- Ash.get(Task, task_id, actor: actor) do
      task |> Ash.Changeset.for_update(:update, attrs, actor: actor) |> Ash.update()
    end
  end

  ## Inbox

  @doc """
  Approves a pending proposal and applies it, in one transaction. `edits` may change
  `summary`, `project_id`, `owner_id` and fields in `data` (title, due) first, so
  "edit, then approve" is one step. Returns `{:ok, proposal}` with `task` loaded.

  A task proposal needs a project; without one this returns `{:error, :needs_project}`.
  Decisions and scope changes are recorded as approved; they get their own records in
  2.4 and 2.19.
  """
  def approve(proposal_id, edits, actor) do
    with {:ok, proposal} <- pending(proposal_id, actor) do
      Repo.transaction(fn ->
        attrs =
          edits
          |> Map.take([:summary, :project_id, :owner_id])
          |> Map.put(:data, Map.merge(proposal.data, Map.get(edits, :data, %{})))

        merged = struct(proposal, attrs)

        with {:ok, task} <- apply_proposal(merged, actor),
             {:ok, decided} <-
               decide(proposal, Map.merge(attrs, %{status: :approved, task_id: task && task.id}), actor) do
          Ash.load!(decided, [:task, :project, :owner], authorize?: false)
        else
          {:error, error} -> Repo.rollback(error)
        end
      end)
    end
  end

  def reject(proposal_id, actor) do
    with {:ok, proposal} <- pending(proposal_id, actor) do
      decide(proposal, %{status: :rejected}, actor)
    end
  end

  defp pending(proposal_id, actor) do
    case Ash.get(Proposal, proposal_id, actor: actor) do
      {:ok, %{status: :pending} = p} -> {:ok, p}
      {:ok, _} -> {:error, :already_decided}
      error -> error
    end
  end

  defp decide(proposal, attrs, actor) do
    proposal
    |> Ash.Changeset.for_update(:decide, Map.put(attrs, :decided_by_id, actor.id), actor: actor)
    |> Ash.update()
  end

  # The approval was authorized above, so applying it runs as Noa.
  defp apply_proposal(%{kind: :task, project_id: nil}, _actor), do: {:error, :needs_project}

  defp apply_proposal(%{kind: :task} = p, actor) do
    Task
    |> Ash.Changeset.for_create(:create, %{
      title: p.data["title"] || p.summary,
      detail: p.data["detail"],
      due_on: p.data["due"],
      source: p.source,
      org_id: p.org_id,
      project_id: p.project_id,
      owner_id: p.owner_id,
      created_by_id: actor.id
    })
    |> Ash.create(authorize?: false)
  end

  defp apply_proposal(%{kind: kind, task_id: task_id} = p, _actor)
       when kind in [:status_change, :deadline_change] and not is_nil(task_id) do
    changes =
      case kind do
        :status_change -> %{status: p.data["status"], blocked_reason: p.data["blocker"]}
        :deadline_change -> %{due_on: p.data["new_due"]}
      end

    Task
    |> Ash.get!(task_id, authorize?: false)
    |> Ash.Changeset.for_update(:update, changes)
    |> Ash.update(authorize?: false)
  end

  defp apply_proposal(_proposal, _actor), do: {:ok, nil}

  ## From chat

  @doc """
  The person behind a chat account (1.11). Looks up the stored identity; for a new
  account, matches a person whose handles include the account id or display name, or
  whose name is the display name, then stores the identity (with no person if none
  matched, for an admin to link). Returns `{:ok, identity}`; `identity.person_id` may
  be nil.
  """
  def identify(org_id, platform, external_id, display_name \\ nil) do
    existing =
      Identity
      |> Ash.Query.filter(org_id == ^org_id and platform == ^platform and external_id == ^external_id)
      |> Ash.read_one!(authorize?: false)

    case existing do
      nil ->
        person = match_person(org_id, external_id, display_name)

        Identity
        |> Ash.Changeset.for_create(:create, %{
          platform: platform,
          external_id: external_id,
          display_name: display_name,
          person_id: person && person.id,
          org_id: org_id
        })
        |> Ash.create(authorize?: false, upsert?: true, upsert_identity: :unique_account)

      %{person_id: nil} ->
        person = match_person(org_id, external_id, display_name || existing.display_name)
        changes = %{display_name: display_name || existing.display_name, person_id: person && person.id}
        update_identity(existing, changes)

      _linked ->
        update_identity(existing, %{display_name: display_name || existing.display_name})
    end
  end

  defp update_identity(identity, changes) do
    if Enum.all?(changes, fn {k, v} -> Map.get(identity, k) == v end) do
      {:ok, identity}
    else
      identity |> Ash.Changeset.for_update(:update, changes) |> Ash.update(authorize?: false)
    end
  end

  defp match_person(org_id, external_id, display_name) do
    wanted = [external_id, display_name] |> Enum.reject(&is_nil/1) |> Enum.map(&String.downcase/1)
    people = Person |> Ash.Query.filter(org_id == ^org_id) |> Ash.read!(authorize?: false)

    Enum.find(people, fn p -> Enum.any?(p.handles, &(String.downcase(&1) in wanted)) end) ||
      Enum.find(people, fn p -> String.downcase(p.name) in wanted end)
  end

  @doc """
  Records a chat message from a mapped channel as a `message.received` event (the
  Episode). Ingest (1.13, 1.15) calls this for every message it reads. `message`:

      %{platform: :discord, channel: "veriq", channel_id: "123", message_id: "456",
        author_id: "789", author: "Saish", text: "...", at: ~U[...]}

  A new message queues extraction for its channel (`Noa.Work.Extract`, 1.17).

  Returns `{:ok, event}`, `{:duplicate, event}` for a message seen before, or
  `{:error, :not_read}` when the channel is unknown or not read. DMs never get here:
  they have no channel row.
  """
  def record_message(org_id, message) do
    platform = message.platform

    channel =
      Channel
      |> Ash.Query.filter(
        org_id == ^org_id and platform == ^platform and
          (name in ^[message.channel, "#" <> message.channel] or
             (not is_nil(external_id) and external_id == ^(message[:channel_id] || "")))
      )
      |> Ash.read!(authorize?: false)
      |> List.first()

    if channel && channel.read do
      {:ok, identity} = identify(org_id, platform, to_string(message.author_id), message[:author])
      key = "#{platform}:#{message.message_id}"

      Noa.Events.append(
        org_id,
        "message.received",
        %{
          episode_id: key,
          platform: platform,
          channel: channel.name,
          channel_id: channel.id,
          project_id: if(channel.split, do: nil, else: channel.project_id),
          author: message[:author],
          person_id: identity.person_id,
          identity_id: identity.id,
          text: message.text,
          at: message[:at] || DateTime.utc_now()
        },
        key: key,
        occurred_at: message[:at]
      )
      |> tap(fn
        {:ok, _event} -> Noa.Work.Extract.enqueue(org_id, channel.id)
        _duplicate -> :ok
      end)
    else
      {:error, :not_read}
    end
  end

  ## From extraction

  @doc """
  Stores routed extraction proposals in the org's Inbox. `lines` are the window's
  lines, used to quote the source message. Project and person keys from the model are
  resolved to ids; unknown ones are left empty for the Inbox to ask about.
  """
  def save_proposals(org_id, proposals, lines) do
    by_line = Map.new(lines, &{&1.id, &1})

    projects =
      Project |> Ash.Query.filter(org_id == ^org_id) |> Ash.read!(authorize?: false) |> Map.new(&{&1.key, &1.id})

    vocab = vocabulary(org_id)
    people = Person |> Ash.Query.filter(org_id == ^org_id) |> Ash.read!(authorize?: false) |> Map.new(&{&1.key, &1.id})

    Enum.map(proposals, fn %Extraction.Proposal{} = p ->
      first = by_line[List.first(p.evidence)]
      data = p.item |> Map.from_struct() |> Map.drop([:evidence_sequences, :confidence, :project]) |> stringify()
      owner = Extraction.Vocabulary.person(vocab, owner_name(p, first))

      Proposal
      |> Ash.Changeset.for_create(:create, %{
        kind: p.type,
        summary: summary(p.type, p.item),
        data:
          Map.put(data, "route", %{
            "rule" => p.route.rule,
            "suggest" => p.route.suggest,
            "candidates" => p.route.candidates
          }),
        confidence: p.confidence,
        source: first && source(first),
        org_id: org_id,
        project_id: projects[p.route.project],
        owner_id: owner && people[owner.id],
        task_id: task_ref(p)
      })
      |> Ash.create!(authorize?: false)
    end)
  end

  defp owner_name(%{type: :task, item: %{owner: owner}}, _first) when is_binary(owner), do: owner
  defp owner_name(_p, %{author: author}), do: author
  defp owner_name(_p, _), do: nil

  defp task_ref(%{item: %{task_ref: ref}}) when is_binary(ref) do
    case Ecto.UUID.cast(ref) do
      {:ok, id} -> id
      :error -> nil
    end
  end

  defp task_ref(_), do: nil

  defp summary(:task, i), do: i.title
  defp summary(:status_change, i), do: "#{i.task_ref} → #{i.status}"
  defp summary(:deadline_change, i), do: "#{i.task_ref} due #{i.new_due}"
  defp summary(:decision, i), do: i.statement
  defp summary(:scope_change, i), do: i.summary

  defp source(line) do
    %{
      "channel" => line.channel,
      "author" => line.author,
      "at" => line.at,
      "quote" => line.body,
      "episode_id" => line.id
    }
  end

  defp stringify(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)

  ## Vocabulary for extraction

  @doc "What extraction may answer with for this org, built from the database."
  def vocabulary(org_id) do
    projects =
      Project |> Ash.Query.filter(org_id == ^org_id) |> Ash.Query.load(:aliases) |> Ash.read!(authorize?: false)

    people = Person |> Ash.Query.filter(org_id == ^org_id) |> Ash.read!(authorize?: false)
    project_key = Map.new(projects, &{&1.id, &1.key})
    person_key = Map.new(people, &{&1.id, &1.key})

    allocations =
      Allocation |> Ash.Query.for_read(:current) |> Ash.Query.filter(org_id == ^org_id) |> Ash.read!(authorize?: false)

    channels = Channel |> Ash.Query.filter(org_id == ^org_id) |> Ash.read!(authorize?: false)
    open = Task |> Ash.Query.filter(org_id == ^org_id and status != :done) |> Ash.read!(authorize?: false)

    %Extraction.Vocabulary{
      projects:
        Enum.map(
          projects,
          &%{id: &1.key, name: &1.name, about: &1.about, aliases: Enum.map(&1.aliases, fn a -> to_string(a.alias) end)}
        ),
      people: Enum.map(people, &%{id: &1.key, name: &1.name, title: &1.title, handles: &1.handles}),
      channels:
        Map.new(channels, fn c ->
          route =
            cond do
              not c.read -> nil
              c.split -> :split
              true -> project_key[c.project_id]
            end

          {c.name, route}
        end),
      works_on: allocations |> Enum.group_by(&person_key[&1.person_id], &project_key[&1.project_id]),
      open_tasks:
        Enum.map(
          open,
          &%{id: &1.id, project: project_key[&1.project_id], title: &1.title, owner: person_key[&1.owner_id]}
        )
    }
  end

  ## Event log

  @doc """
  Appends a `.saved` event for every row in the org that has none yet: rows written
  before the event log existed (1.8). Safe to run again. Returns how many it appended.
  """
  def backfill_events(org_id) do
    logged = MapSet.new(Noa.Repo.all(from(e in Noa.Events.Event, where: e.org_id == ^org_id, select: e.subject_id)))

    # Parents before children, so the replay builds nodes before edges point at them.
    [{Person, "person"}, {Project, "project"}, {ProjectAlias, "alias"}, {Channel, "channel"}, {Identity, "identity"}]
    |> Kernel.++([{Allocation, "allocation"}, {Task, "task"}, {Proposal, "proposal"}])
    |> Enum.flat_map(fn {resource, name} ->
      resource
      |> Ash.Query.filter(org_id == ^org_id)
      |> Ash.read!(authorize?: false)
      |> Enum.reject(&MapSet.member?(logged, &1.id))
      |> Enum.map(&Noa.Events.append(org_id, "#{name}.saved", Noa.Events.Record.snapshot(&1), subject_id: &1.id))
    end)
    |> length()
  end

  ## Seed

  @doc """
  Loads an org seed (the format of docs/seeds/nyi.json) into the org: people,
  projects, aliases, channels and allocations. Safe to run again: rows are matched by
  key and updated. People are linked to members whose email or name matches.
  """
  defdelegate load_seed(org_id, seed), to: Noa.Work.Seed, as: :load

  @doc "Links people with no account to the org's members, by email, then by name."
  defdelegate link_people(org_id), to: Noa.Work.Seed
end
