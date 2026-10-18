defmodule Noa.Work.Digest do
  @moduledoc """
  The daily digest (2.9): once a day, at the time each person picked in Settings →
  Notifications (in their own time zone), a short summary on their channel: their open
  tasks with what is due or late, what waits on them, what is blocked where they work,
  and what was decided there since yesterday. Nothing is sent on a day with nothing to say.

  `Dispatch` runs every 15 minutes (Oban cron) and queues one `Send` per person whose
  digest time falls in that window; `Send` jobs are unique per person and day, so a
  restart or a retry never sends twice.
  """
  require Ash.Query

  alias Noa.Work.{Change, Decision, Person, Project, Proposal, Task}

  @doc "The digest text for a person, or nil when there is nothing to tell them."
  def build(%Person{} = person, today \\ Date.utc_today()) do
    org_id = person.org_id
    projects = Project |> Ash.Query.filter(org_id == ^org_id) |> Ash.read!(authorize?: false) |> Map.new(&{&1.id, &1})
    person = Ash.load!(person, [:allocations, :membership], authorize?: false)

    mine_projects =
      MapSet.new(
        Enum.map(person.allocations, & &1.project_id) ++
          (projects |> Map.values() |> Enum.filter(&(&1.lead_id == person.id)) |> Enum.map(& &1.id))
      )

    lead? = (person.membership && person.membership.role in [:org_admin, :pm]) || false
    open = Task |> Ash.Query.filter(org_id == ^org_id and status != :done) |> Ash.read!(authorize?: false)
    mine = open |> Enum.filter(&(&1.owner_id == person.id)) |> Enum.sort_by(&(&1.due_on || ~D[9999-12-31]), Date)

    blocked =
      Enum.filter(open, &(&1.status == :blocked and &1.project_id in mine_projects and &1.owner_id != person.id))

    waiting =
      Proposal
      |> Ash.Query.filter(org_id == ^org_id and status == :pending)
      |> Ash.read!(authorize?: false)
      |> Enum.count(&(lead? or &1.owner_id == person.id))

    changes =
      Change
      |> Ash.Query.filter(org_id == ^org_id and status == :pending)
      |> Ash.read!(authorize?: false)
      |> Enum.count(&(lead? or (projects[&1.project_id] && projects[&1.project_id].lead_id == person.id)))

    since = today |> Date.add(-1) |> DateTime.new!(~T[00:00:00])

    decided =
      Decision
      |> Ash.Query.filter(org_id == ^org_id and status == :active and inserted_at >= ^since)
      |> Ash.read!(authorize?: false)
      |> Enum.filter(&(is_nil(&1.project_id) or &1.project_id in mine_projects))

    task_line = fn t ->
      due =
        cond do
          is_nil(t.due_on) -> ""
          Date.compare(t.due_on, today) == :lt -> ", late since #{t.due_on}"
          t.due_on == today -> ", due today"
          true -> ", due #{t.due_on}"
        end

      "• #{t.title} (#{name(projects, t.project_id)}#{due}#{if t.status == :blocked, do: ", blocked", else: ""})"
    end

    sections =
      [
        mine != [] &&
          "Your open tasks (#{length(mine)}):\n" <> (mine |> Enum.take(6) |> Enum.map_join("\n", task_line)),
        (waiting > 0 or changes > 0) &&
          "Waiting on you: " <>
            ([plural(waiting, "proposal"), changes > 0 && plural(changes, "change to approve")]
             |> Enum.filter(& &1)
             |> Enum.join(", ")),
        blocked != [] &&
          "Blocked where you work:\n" <>
            Enum.map_join(Enum.take(blocked, 4), "\n", &"• #{&1.title} (#{name(projects, &1.project_id)})"),
        decided != [] &&
          "Decided since yesterday:\n" <>
            Enum.map_join(Enum.take(decided, 4), "\n", &"• #{&1.statement} (#{name(projects, &1.project_id)})")
      ]
      |> Enum.filter(& &1)

    if sections != [] do
      "Good morning, #{first_name(person.name)}. Your day in Noa:\n\n" <>
        Enum.join(sections, "\n\n") <> "\n\n" <> Noa.Mailer.web_url("/")
    end
  end

  @doc "Sends the person's digest on their channel. Returns `:sent`, `:nothing` or `{:error, _}`."
  def deliver(%Person{} = person, today \\ Date.utc_today()) do
    case build(person, today) do
      nil ->
        :nothing

      text ->
        case Noa.Notify.deliver(person, text, subject: "Your day in Noa", context: %{"kind" => "digest"}) do
          {:ok, _channel} -> :sent
          :skipped -> :nothing
          error -> error
        end
    end
  end

  @doc "People whose digest time (in their local time) falls in the 15 minutes starting at `at` (UTC)."
  def due(at \\ DateTime.utc_now()) do
    Person
    |> Ash.Query.filter(not is_nil(digest_at))
    |> Ash.read!(authorize?: false)
    |> Enum.filter(fn p ->
      local = at |> DateTime.add(p.utc_offset * 60, :second) |> DateTime.to_time()
      diff = Time.diff(local, p.digest_at, :second)
      diff >= 0 and diff < 15 * 60
    end)
  end

  defp name(projects, id), do: (projects[id] && projects[id].name) || "no project"
  defp first_name(name), do: name |> to_string() |> String.split(" ") |> hd()
  defp plural(1, word), do: "1 #{word}"
  defp plural(n, word), do: "#{n} #{word}s"

  defmodule Dispatch do
    @moduledoc "Every 15 minutes: queue a digest for each person whose time it is."
    use Oban.Worker, queue: :whatsapp, max_attempts: 1

    @impl Oban.Worker
    def perform(_job) do
      now = DateTime.utc_now()

      for p <- Noa.Work.Digest.due(now) do
        local_day = now |> DateTime.add(p.utc_offset * 60, :second) |> DateTime.to_date() |> Date.to_iso8601()
        %{person_id: p.id, day: local_day} |> Noa.Work.Digest.Send.new() |> Oban.insert()
      end

      :ok
    end
  end

  defmodule Send do
    @moduledoc "Sends one person's digest for one day (unique per person and day)."
    use Oban.Worker, queue: :whatsapp, max_attempts: 3, unique: [period: 2 * 86_400, keys: [:person_id, :day]]

    @impl Oban.Worker
    def perform(%Oban.Job{args: %{"person_id" => id, "day" => day}}) do
      case Ash.get(Noa.Work.Person, id, authorize?: false) do
        {:ok, person} ->
          case Noa.Work.Digest.deliver(person, Date.from_iso8601!(day)) do
            {:error, error} -> {:error, error}
            _ -> :ok
          end

        _ ->
          :ok
      end
    end
  end
end
