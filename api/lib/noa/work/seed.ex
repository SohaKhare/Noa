defmodule Noa.Work.Seed do
  @moduledoc """
  Loads an org seed (docs/seeds/nyi.json) into the database (1.23). Runs as Noa, with
  no actor. Rows are matched by key, so running it again updates instead of duplicating.
  Keys starting with `_` and `confirm` marks are ignored.
  """
  require Ash.Query

  alias Noa.Orgs.Membership
  alias Noa.Repo
  alias Noa.Work.{Allocation, Channel, Person, Project, ProjectAlias}

  @doc "Loads the seed map into the org. Returns counts of what it wrote."
  def load(org_id, seed) do
    Repo.transaction(fn ->
      people = Map.new(seed["people"] || [], fn p -> {p["id"], upsert_person(org_id, p)} end)

      projects =
        Map.new(seed["projects"] || [], fn p ->
          {p["id"], upsert_project(org_id, p, people[p["lead"]])}
        end)

      for a <- seed["aliases"] || [], project = projects[a["project"]] do
        ProjectAlias
        |> Ash.Changeset.for_create(:create, %{alias: a["alias"], org_id: org_id, project_id: project.id})
        |> Ash.create!(authorize?: false, upsert?: true, upsert_identity: :unique_alias, upsert_fields: [:project_id])
      end

      for c <- seed["channels"] || [] do
        project = projects[c["project"]]

        Channel
        |> Ash.Changeset.for_create(:create, %{
          platform: String.to_existing_atom(c["platform"] || "discord"),
          name: c["name"],
          split: c["project"] == "split",
          read: Map.get(c, "read", true),
          project_id: project && project.id,
          org_id: org_id
        })
        |> Ash.create!(
          authorize?: false,
          upsert?: true,
          upsert_identity: :unique_name,
          upsert_fields: [:split, :read, :project_id]
        )
      end

      for a <- seed["allocations"] || [], person = people[a["person"]], project = projects[a["project"]] do
        upsert_allocation(org_id, person, project, a)
      end

      linked = link_people(org_id)

      %{
        people: map_size(people),
        projects: map_size(projects),
        aliases: length(seed["aliases"] || []),
        channels: length(seed["channels"] || []),
        allocations: length(seed["allocations"] || []),
        linked: linked
      }
    end)
  end

  @doc """
  Links people with no account to the org's members: by email first, then by name
  (case-insensitive). Returns how many were linked. Called after the seed loads and
  whenever someone accepts an invite.
  """
  def link_people(org_id) do
    members = Membership |> Ash.Query.filter(org_id == ^org_id) |> Ash.Query.load(:user) |> Ash.read!(authorize?: false)
    taken = Person |> Ash.Query.filter(org_id == ^org_id and not is_nil(membership_id)) |> Ash.read!(authorize?: false)
    taken = MapSet.new(taken, & &1.membership_id)

    Person
    |> Ash.Query.filter(org_id == ^org_id and is_nil(membership_id))
    |> Ash.read!(authorize?: false)
    |> Enum.reduce({0, taken}, fn person, {count, taken} ->
      match =
        Enum.find(members, &(not MapSet.member?(taken, &1.id) and same_email?(person, &1))) ||
          Enum.find(members, &(not MapSet.member?(taken, &1.id) and same_name?(person, &1)))

      if match do
        person |> Ash.Changeset.for_update(:update, %{membership_id: match.id}) |> Ash.update!(authorize?: false)
        {count + 1, MapSet.put(taken, match.id)}
      else
        {count, taken}
      end
    end)
    |> elem(0)
  end

  defp same_email?(%{email: nil}, _m), do: false
  defp same_email?(person, m), do: String.downcase(to_string(person.email)) == String.downcase(to_string(m.user.email))

  defp same_name?(_person, %{user: %{name: nil}}), do: false
  defp same_name?(person, m), do: String.downcase(person.name) == String.downcase(m.user.name)

  defp upsert_person(org_id, p) do
    Person
    |> Ash.Changeset.for_create(:create, %{
      key: p["id"],
      name: p["name"],
      title: p["title"],
      email: p["email"],
      handles: Enum.uniq((p["handles"] || []) ++ (p["git"] || [])),
      org_id: org_id
    })
    |> Ash.create!(
      authorize?: false,
      upsert?: true,
      upsert_identity: :unique_key,
      upsert_fields: [:name, :title, :email, :handles]
    )
  end

  defp upsert_project(org_id, p, lead) do
    Project
    |> Ash.Changeset.for_create(:create, %{
      key: p["id"],
      name: p["name"],
      about: p["about"],
      repo: p["repo"],
      lead_id: lead && lead.id,
      org_id: org_id
    })
    |> Ash.create!(
      authorize?: false,
      upsert?: true,
      upsert_identity: :unique_key,
      upsert_fields: [:name, :about, :repo, :lead_id]
    )
  end

  defp upsert_allocation(org_id, person, project, a) do
    current =
      Allocation
      |> Ash.Query.filter(person_id == ^person.id and project_id == ^project.id and is_nil(ends_on))
      |> Ash.read_one!(authorize?: false)

    case current do
      nil ->
        Allocation
        |> Ash.Changeset.for_create(:create, %{
          percent: a["percent"],
          role: a["role"],
          org_id: org_id,
          person_id: person.id,
          project_id: project.id
        })
        |> Ash.create!(authorize?: false)

      existing ->
        existing
        |> Ash.Changeset.for_update(:update, %{percent: a["percent"], role: a["role"]})
        |> Ash.update!(authorize?: false)
    end
  end

  @doc """
  Loads docs/seeds/nyi-sample-work.json: sample tasks and pending proposals for local
  development. Tasks are matched by project and title, proposals by summary, so it can
  run again. Run `load/2` first.
  """
  def load_sample(org_id, sample) do
    now = DateTime.utc_now()

    projects =
      Project |> Ash.Query.filter(org_id == ^org_id) |> Ash.read!(authorize?: false) |> Map.new(&{&1.key, &1.id})

    people = Person |> Ash.Query.filter(org_id == ^org_id) |> Ash.read!(authorize?: false) |> Map.new(&{&1.key, &1.id})

    Repo.transaction(fn ->
      tasks =
        for t <- sample["tasks"] || [], project_id = projects[t["project"]] do
          existing =
            Noa.Work.Task
            |> Ash.Query.filter(project_id == ^project_id and title == ^t["title"])
            |> Ash.read_one!(authorize?: false)

          existing ||
            Noa.Work.Task
            |> Ash.Changeset.for_create(:create, %{
              title: t["title"],
              status: String.to_existing_atom(t["status"]),
              due_on: t["due_in"] && Date.add(Date.utc_today(), t["due_in"]),
              source: sample_source(t["source"], now),
              org_id: org_id,
              project_id: project_id,
              owner_id: people[t["owner"]]
            })
            |> Ash.create!(authorize?: false)
            |> then(fn task ->
              if t["blocked_reason"],
                do:
                  task
                  |> Ash.Changeset.for_update(:update, %{blocked_reason: t["blocked_reason"]})
                  |> Ash.update!(authorize?: false),
                else: task
            end)
        end

      by_title = Map.new(tasks, &{&1.title, &1.id})

      proposals =
        for p <- sample["proposals"] || [],
            not (Noa.Work.Proposal
                 |> Ash.Query.filter(org_id == ^org_id and summary == ^p["summary"])
                 |> Ash.exists?(authorize?: false)) do
          data =
            (p["data"] || %{})
            |> relative("due_in", "due")
            |> relative("new_due_in", "new_due")

          Noa.Work.Proposal
          |> Ash.Changeset.for_create(:create, %{
            kind: String.to_existing_atom(p["kind"]),
            summary: p["summary"],
            confidence: p["confidence"],
            data: data,
            source: sample_source(p["source"], now),
            org_id: org_id,
            project_id: projects[p["project"]],
            owner_id: people[p["owner"]],
            task_id: by_title[p["task"]]
          })
          |> Ash.create!(authorize?: false)
        end

      %{tasks: length(tasks), proposals: length(proposals)}
    end)
  end

  defp relative(data, from, to) do
    case Map.pop(data, from) do
      {nil, data} -> data
      {days, data} -> Map.put(data, to, Date.utc_today() |> Date.add(days) |> Date.to_iso8601())
    end
  end

  defp sample_source(nil, _now), do: nil

  defp sample_source(s, now) do
    s
    |> Map.drop(["hours_ago"])
    |> Map.put(
      "at",
      now |> DateTime.add(-(s["hours_ago"] || 0) * 3600) |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    )
  end
end
