defmodule Noa.Work.Feed do
  @moduledoc """
  The in-app notification feed, newest first, built from what already happened (no
  table of its own), read as the person signed in:

  - proposals waiting on them (all for leads, their own for members)
  - deadline and scope changes waiting on them (leads)
  - changes someone else made to their tasks, and changes of theirs a lead decided
  - decisions made today in their projects
  - moves involving them or their projects

  Delivery to WhatsApp and Discord (2.21) can send the same items.
  """
  alias Noa.Work

  @days 7

  def build(org_id, actor) do
    me_id = (p = Work.person_for(actor, org_id)) && p.id
    since = DateTime.add(DateTime.utc_now(), -@days * 86_400, :second)

    with {:ok, people} <- Work.people(org_id, actor),
         {:ok, projects} <- Work.projects(org_id, actor),
         {:ok, proposals} <- Work.proposals(org_id, actor),
         {:ok, changes} <- Work.changes(org_id, actor),
         {:ok, tasks} <- Work.tasks(org_id, actor),
         {:ok, decisions} <- Work.decisions(org_id, actor, since: since, status: :active),
         {:ok, shifts} <- Work.shifts(org_id, actor) do
      me = Enum.find(people, &(&1.id == me_id))
      lead = Map.get(actor, :is_superadmin) || Noa.Orgs.role(actor.id, org_id) in [:org_admin, :pm]
      name = Map.new(people, &{&1.id, &1.name})
      by_user = Map.new(people, &{&1.membership && &1.membership.user_id, &1.name})
      project = Map.new(projects, &{&1.id, &1})
      task = Map.new(tasks, &{&1.id, &1})
      mine = MapSet.new((me && Enum.map(me.allocations, & &1.project_id)) || [])
      mine = Enum.reduce(projects, mine, &if(me && &1.lead_id == me.id, do: MapSet.put(&2, &1.id), else: &2))
      href = fn id -> project[id] && "/projects/#{project[id].key}" end
      recent = &(DateTime.compare(&1, since) == :gt)

      items =
        for(
          p <- proposals,
          lead or (me && p.owner_id == me.id),
          do: %{
            id: "proposal:#{p.id}",
            kind: "approval",
            text: "Waiting on you: #{p.summary}",
            at: p.inserted_at,
            href: "/inbox"
          }
        ) ++
          for(
            c <- changes,
            c.status == :pending and (lead or (me && project[c.project_id] && project[c.project_id].lead_id == me.id)),
            do: %{
              id: "change:#{c.id}",
              kind: "approval",
              text:
                "#{by_user[c.requested_by_id] || "Someone"} wants to change the #{c.kind} of #{title(task, c.task_id)}",
              at: c.inserted_at,
              href: "/inbox"
            }
          ) ++
          for(
            c <- changes,
            recent.(c.inserted_at),
            (me && task[c.task_id] && task[c.task_id].owner_id == me.id) and c.requested_by_id != actor.id and
              c.status == :applied,
            do: %{
              id: "changed:#{c.id}",
              kind: "change",
              text: "#{by_user[c.requested_by_id] || "Someone"} changed the #{c.kind} of #{title(task, c.task_id)}",
              at: c.inserted_at,
              href: href.(c.project_id)
            }
          ) ++
          for(
            c <- changes,
            (c.requested_by_id == actor.id and c.status in [:rejected] and c.decided_at) && recent.(c.decided_at),
            do: %{
              id: "decided:#{c.id}",
              kind: "change",
              text:
                "#{by_user[c.decided_by_id] || "Your lead"} turned down your #{c.kind} change to #{title(task, c.task_id)}",
              at: c.decided_at,
              href: href.(c.project_id)
            }
          ) ++
          for(
            d <- decisions,
            is_nil(d.project_id) or MapSet.member?(mine, d.project_id),
            do: %{
              id: "decision:#{d.id}",
              kind: "decision",
              text: "Decided#{project[d.project_id] && " in #{project[d.project_id].name}"}: #{d.statement}",
              at: d.inserted_at,
              href: href.(d.project_id)
            }
          ) ++
          for(
            s <- shifts,
            recent.(s.inserted_at),
            (me && s.person_id == me.id) or MapSet.member?(mine, s.from_project_id) or
              MapSet.member?(mine, s.to_project_id),
            do: %{
              id: "shift:#{s.id}",
              kind: "shift",
              text:
                "#{if me && s.person_id == me.id, do: "You move", else: "#{name[s.person_id]} moves"} " <>
                  "from #{(project[s.from_project_id] && project[s.from_project_id].name) || "the bench"} " <>
                  "to #{(project[s.to_project_id] && project[s.to_project_id].name) || "the bench"} on #{s.starts_on}",
              at: s.inserted_at,
              href: "/people"
            }
          )

      {:ok, items |> Enum.sort_by(& &1.at, {:desc, DateTime}) |> Enum.take(30)}
    end
  end

  defp title(task, id), do: (task[id] && "\"#{task[id].title}\"") || "a task"
end
