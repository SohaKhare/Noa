"use client";

import { ArrowRightIcon, CalendarBlankIcon, ChatCircleDotsIcon, CheckIcon, CheckCircleIcon, TrayIcon, WarningCircleIcon } from "@phosphor-icons/react";
import Link from "next/link";
import { useState } from "react";
import { Hello } from "@/components/Hello";
import { Badge, SourceChip } from "@/components/ui";
import type { WorkProject, WorkTask } from "@/lib/api";
import { cn } from "@/lib/cn";
import { dueLabel, isLate, toSource, useDirectory, useMoveTask, useProposals, useTasks } from "@/lib/work";

/*
  My day (2.12): my open tasks across every project, by project or by date, what is
  waiting on me, what is blocked where I work, and what I finished today.
*/

type View = "project" | "date";

const byDue = (a: WorkTask, b: WorkTask) => (a.due_on ?? "9999").localeCompare(b.due_on ?? "9999");
const isToday = (iso?: string | null) => !!iso && new Date(iso).toDateString() === new Date().toDateString();

export function MyDay() {
  const dir = useDirectory();
  const tasks = useTasks({});
  const proposals = useProposals();
  const [view, setView] = useState<View>("project");

  const me = dir.person(dir.me);
  const all = tasks.data ?? [];
  const lead = me?.role === "org_admin" || me?.role === "pm";
  const myProjects = new Set([
    ...(me?.allocations.map((a) => a.project_id) ?? []),
    ...dir.projects.filter((p) => p.lead_id === me?.id).map((p) => p.id),
  ]);

  const mine = all.filter((t) => t.owner_id === me?.id && t.status !== "done").sort(byDue);
  const doneToday = all.filter((t) => t.owner_id === me?.id && t.status === "done" && isToday(t.done_at));
  const blocked = all.filter((t) => t.status === "blocked" && myProjects.has(t.project_id));
  const waiting = (proposals.data ?? []).filter((p) => lead || p.owner_id === me?.id);
  const groups = dir.projects.map((p) => ({ p, items: mine.filter((t) => t.project_id === p.id) })).filter((g) => g.items.length);
  const loading = dir.isLoading || tasks.isLoading;

  return (
    <div className="mx-auto max-w-6xl">
      <section className="rounded-[26px] wash p-7 card-shadow">
        <p className="eyebrow text-muted">{new Date().toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long" })}</p>
        <h1 className="mt-2 text-[28px] leading-tight font-semibold tracking-[-0.03em]">
          <Hello />
        </h1>
        <p className="mt-1.5 text-[14.5px] text-muted">
          {loading
            ? "Getting your day ready…"
            : `${plural(mine.length, "open task")} across ${plural(groups.length, "project")} · ${plural(waiting.length, "proposal")} waiting · ${blocked.length} blocked`}
        </p>
        <div className="mt-5 grid gap-3 sm:grid-cols-3">
          <Stat Icon={TrayIcon} label="Waiting on you" value={plural(waiting.length, "proposal")} href="/inbox" />
          <Stat Icon={CheckCircleIcon} label="Done today" value={doneToday.length ? doneToday.map((t) => t.title).join(", ") : "Nothing yet"} href="#done" />
          <Stat
            Icon={WarningCircleIcon}
            label="Blocked where you work"
            value={blocked.map((b) => b.title).join(", ") || "Nothing"}
            href={blocked[0] ? `/projects/${dir.project(blocked[0].project_id)?.key}` : "#"}
            tone={blocked.length ? "bad" : undefined}
          />
        </div>
      </section>

      <div className="mt-6 grid gap-6 lg:grid-cols-[1.55fr_1fr]">
        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <p className="text-[14px] font-semibold">Your work</p>
            <div className="flex rounded-full bg-surface p-0.5 text-[12.5px] ring-1 ring-line">
              {(["project", "date"] as const).map((v) => (
                <button
                  key={v}
                  onClick={() => setView(v)}
                  className={cn("rounded-full px-3 py-1", view === v ? "bg-accent text-white" : "text-muted hover:text-ink")}
                >
                  By {v}
                </button>
              ))}
            </div>
          </div>

          {!loading && !me && (
            <Empty>Your account isn&rsquo;t linked to a person in this workspace yet. Ask your admin to add you to the org map.</Empty>
          )}
          {!loading && me && mine.length === 0 && (
            <Empty>Nothing on your plate. New work shows up here when someone hands it to you in chat and it&rsquo;s approved.</Empty>
          )}

          {view === "project"
            ? groups.map(({ p, items }) => (
                <TaskGroup key={p.id} title={p.name} href={`/projects/${p.key}`} hint={items[0].due_on ? `next ${dueLabel(items[0].due_on)}` : undefined}>
                  {items.map((t) => (
                    <TaskRow key={t.id} t={t} />
                  ))}
                </TaskGroup>
              ))
            : dateBuckets(mine).map(({ label, items }) => (
                <TaskGroup key={label} title={label}>
                  {items.map((t) => (
                    <TaskRow key={t.id} t={t} project={dir.project(t.project_id)} />
                  ))}
                </TaskGroup>
              ))}

          {doneToday.length > 0 && (
            <div id="done">
              <TaskGroup title="Done today">
                {doneToday.map((t) => (
                  <TaskRow key={t.id} t={t} project={dir.project(t.project_id)} />
                ))}
              </TaskGroup>
            </div>
          )}
        </div>

        <aside className="space-y-4">
          <section className="rounded-[22px] bg-surface p-5 card-shadow">
            <p className="flex items-center justify-between text-[14px] font-semibold">
              Waiting on you
              <Link href="/inbox" className="text-[12px] font-normal text-muted hover:text-ink">
                Open inbox
              </Link>
            </p>
            {waiting.length === 0 ? (
              <p className="mt-3 text-[13px] text-muted">All caught up.</p>
            ) : (
              <ul className="mt-3 space-y-2">
                {waiting.slice(0, 4).map((pr) => (
                  <li key={pr.id}>
                    <Link href="/inbox" className="block rounded-xl bg-bg px-3 py-2.5 hover:bg-mist/50">
                      <p className="text-[13px] font-medium">{pr.summary}</p>
                      <SourceChip source={toSource(pr.source)} />
                    </Link>
                  </li>
                ))}
              </ul>
            )}
          </section>

          <section className="rounded-[22px] bg-surface p-5 card-shadow">
            <p className="text-[14px] font-semibold">Coming up</p>
            <ul className="mt-3 space-y-2.5 text-[13px]">
              {dir.projects
                .filter((p) => myProjects.has(p.id))
                .map((p) => ({ p, next: nextDue(all, p) }))
                .map(({ p, next }) => (
                  <li key={p.id}>
                    <Link href={`/projects/${p.key}`} className="flex items-center gap-2.5 hover:text-accent">
                      <CalendarBlankIcon size={14} className="text-muted" />
                      <span className="min-w-0 flex-1 truncate">
                        {p.name}
                        {next && <span className="text-muted"> · {next.title}</span>}
                      </span>
                      <span className={cn("tabular-nums", next && isLate(next.due_on) ? "text-bad" : "text-muted")}>
                        {next ? dueLabel(next.due_on) : "no dates"}
                      </span>
                    </Link>
                  </li>
                ))}
            </ul>
          </section>

          <Link
            href="/ask"
            className="flex items-center gap-3 rounded-[22px] bg-accent px-5 py-4 text-[13.5px] text-white card-shadow hover:bg-accent-soft"
          >
            <ChatCircleDotsIcon size={18} />
            Ask Noa anything about your projects
            <ArrowRightIcon size={14} className="ml-auto" />
          </Link>
        </aside>
      </div>
    </div>
  );
}

const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? "" : "s"}`;

function nextDue(tasks: WorkTask[], p: WorkProject) {
  return tasks.filter((t) => t.project_id === p.id && t.status !== "done" && t.due_on).sort(byDue)[0];
}

function dateBuckets(tasks: WorkTask[]) {
  const buckets: { label: string; items: WorkTask[] }[] = [
    { label: "Late", items: [] },
    { label: "Today", items: [] },
    { label: "This week", items: [] },
    { label: "Later", items: [] },
    { label: "No date", items: [] },
  ];
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  for (const t of tasks) {
    if (!t.due_on) buckets[4].items.push(t);
    else {
      const [y, m, d] = t.due_on.split("-").map(Number);
      const days = Math.round((new Date(y, m - 1, d).getTime() - today.getTime()) / 86_400_000);
      buckets[days < 0 ? 0 : days === 0 ? 1 : days < 7 ? 2 : 3].items.push(t);
    }
  }
  return buckets.filter((b) => b.items.length);
}

function TaskGroup({ title, href, hint, children }: { title: string; href?: string; hint?: string; children: React.ReactNode }) {
  const head = (
    <>
      <span className="text-[13.5px] font-semibold">{title}</span>
      {hint && (
        <span className="flex items-center gap-1 text-[12px] text-muted">
          {hint} {href && <ArrowRightIcon size={12} />}
        </span>
      )}
    </>
  );
  return (
    <section className="overflow-hidden rounded-[22px] bg-surface card-shadow">
      {href ? (
        <Link href={href} className="flex items-center justify-between border-b border-line px-5 py-3 hover:bg-bg">
          {head}
        </Link>
      ) : (
        <div className="flex items-center justify-between border-b border-line px-5 py-3">{head}</div>
      )}
      <ul className="divide-y divide-line">{children}</ul>
    </section>
  );
}

function TaskRow({ t, project }: { t: WorkTask; project?: WorkProject }) {
  const move = useMoveTask();
  const done = t.status === "done";
  return (
    <li className="flex items-center gap-3 px-5 py-3.5 hover:bg-bg/60">
      <button
        aria-label={done ? `Reopen ${t.title}` : `Mark ${t.title} done`}
        onClick={() => move.mutate({ id: t.id, status: done ? "todo" : "done" })}
        className={cn(
          "grid size-4 shrink-0 place-items-center rounded-[5px] ring-1 transition-colors",
          done ? "bg-good text-white ring-good" : "ring-ink/25 hover:ring-accent",
        )}
      >
        {done && <CheckIcon size={11} weight="bold" />}
      </button>
      <div className="min-w-0 flex-1">
        <p className={cn("text-[14px] font-medium", done && "text-muted line-through")}>{t.title}</p>
        <div className="flex flex-wrap items-center gap-x-2">
          {project && <span className="text-[11.5px] text-muted">{project.name}</span>}
          {t.source && <SourceChip source={toSource(t.source)} />}
        </div>
        {t.status === "blocked" && t.blocked_reason && <p className="mt-0.5 text-[12px] text-bad">{t.blocked_reason}</p>}
      </div>
      {t.status === "blocked" ? (
        <Badge tone="bad">blocked</Badge>
      ) : t.status === "in_progress" ? (
        <Badge>in progress</Badge>
      ) : t.due_on && !done ? (
        <Badge tone={isLate(t.due_on) ? "bad" : "neutral"}>{dueLabel(t.due_on)}</Badge>
      ) : null}
    </li>
  );
}

function Empty({ children }: { children: React.ReactNode }) {
  return <p className="rounded-[22px] bg-surface px-5 py-6 text-[13.5px] text-muted card-shadow">{children}</p>;
}

function Stat({
  Icon,
  label,
  value,
  href,
  tone,
}: {
  Icon: typeof TrayIcon;
  label: string;
  value: string;
  href: string;
  tone?: "bad";
}) {
  return (
    <Link href={href} className="flex items-center gap-3 rounded-2xl bg-surface/85 px-4 py-3 ring-1 ring-line hover:bg-surface">
      <span className={`grid size-9 shrink-0 place-items-center rounded-full ${tone === "bad" ? "bg-bad/10 text-bad" : "bg-mist text-accent"}`}>
        <Icon size={17} />
      </span>
      <span className="min-w-0">
        <span className="block text-[11.5px] text-muted">{label}</span>
        <span className="block truncate text-[13.5px] font-medium">{value}</span>
      </span>
    </Link>
  );
}
