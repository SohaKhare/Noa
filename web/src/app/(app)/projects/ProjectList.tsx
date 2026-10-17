"use client";

import Link from "next/link";
import { Avatar, Badge, PageHeader } from "@/components/ui";
import type { WorkProject, WorkTask } from "@/lib/api";
import { dueLabel, isLate, nameInitials, projectPeople, useDirectory, useTasks } from "@/lib/work";

/* Every project in the workspace with its health, progress and people, from the API. */

export function ProjectList() {
  const dir = useDirectory();
  const tasks = useTasks({});
  const all = tasks.data ?? [];

  return (
    <div className="mx-auto max-w-6xl">
      <PageHeader
        title="Projects"
        sub={dir.isLoading ? "Loading…" : `${dir.projects.length} active · updated from your channels`}
      />
      {!dir.isLoading && dir.projects.length === 0 && (
        <p className="rounded-[22px] bg-surface px-5 py-6 text-[13.5px] text-muted card-shadow">
          No projects yet. An admin adds them from the org map in Settings.
        </p>
      )}
      <div className="grid gap-4 sm:grid-cols-2">
        {dir.projects.map((p) => (
          <ProjectCard key={p.id} p={p} tasks={all.filter((t) => t.project_id === p.id)} />
        ))}
      </div>
    </div>
  );
}

export function health(tasks: WorkTask[]) {
  const open = tasks.filter((t) => t.status !== "done");
  if (open.some((t) => t.status === "blocked")) return { tone: "bad" as const, label: "has blockers" };
  if (open.some((t) => isLate(t.due_on))) return { tone: "warn" as const, label: "at risk" };
  return { tone: "good" as const, label: "on track" };
}

function ProjectCard({ p, tasks }: { p: WorkProject; tasks: WorkTask[] }) {
  const dir = useDirectory();
  const open = tasks.filter((t) => t.status !== "done");
  const blocked = open.filter((t) => t.status === "blocked").length;
  const next = open.filter((t) => t.due_on).sort((a, b) => a.due_on!.localeCompare(b.due_on!))[0];
  const progress = tasks.length ? Math.round(((tasks.length - open.length) / tasks.length) * 100) : 0;
  const h = health(tasks);
  const people = projectPeople(p, dir.people);
  const lead = dir.person(p.lead_id);

  return (
    <Link
      href={`/projects/${p.key}`}
      className="group rounded-[22px] wash p-5 card-shadow transition-transform duration-300 ease-soft hover:-translate-y-0.5"
    >
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="text-[16px] font-semibold tracking-tight">{p.name}</p>
          <p className="text-[12px] text-muted">{lead ? `Lead ${lead.name}` : "No lead yet"}</p>
        </div>
        <Badge tone={h.tone}>{h.label}</Badge>
      </div>
      <p className="mt-3 text-[13.5px] leading-relaxed text-ink/75">{p.about}</p>
      <div className="mt-5">
        <div className="flex justify-between text-[11.5px] text-muted">
          <span>Progress</span>
          <span className="tabular-nums">
            {tasks.length - open.length} of {tasks.length} done
          </span>
        </div>
        <div className="mt-1.5 h-1.5 rounded-full bg-bg">
          <div className="h-full rounded-full bg-accent" style={{ width: `${progress}%` }} />
        </div>
      </div>
      <div className="mt-5 flex items-center justify-between">
        <div className="flex -space-x-1.5">
          {people.map(({ person }) => (
            <span key={person.id} className="rounded-full ring-2 ring-white" title={person.name}>
              <Avatar initials={nameInitials(person.name)} size={26} />
            </span>
          ))}
        </div>
        <p className="text-[12px] text-muted">
          {open.length} open{next && ` · next ${dueLabel(next.due_on)}`}
          {blocked > 0 && <span className="text-bad"> · {blocked} blocked</span>}
        </p>
      </div>
    </Link>
  );
}
