"use client";

import Link from "next/link";
import { Badge, Card, PageHeader } from "@/components/ui";
import { useQuery } from "@tanstack/react-query";
import { getExperts } from "@/lib/api";
import { dueLabel, isLate, projectPeople, useDirectory, useTasks } from "@/lib/work";
import { health } from "../projects/ProjectList";

/* Portfolio (3.9, first slice): every project's health, everyone's load, and risks read from the data. */

export function Portfolio() {
  const dir = useDirectory();
  const tasks = useTasks({}).data ?? [];
  const open = tasks.filter((t) => t.status !== "done");
  const graph = useQuery({ queryKey: ["experts", dir.orgId], queryFn: () => getExperts(dir.orgId!), enabled: !!dir.orgId }).data;

  const load = dir.people
    .map((p) => ({ p, pct: p.allocations.reduce((sum, a) => sum + a.percent, 0) }))
    .filter((l) => l.pct > 0)
    .sort((a, b) => b.pct - a.pct);

  const rows = dir.projects.map((p) => {
    const mine = tasks.filter((t) => t.project_id === p.id);
    const next = mine.filter((t) => t.status !== "done" && t.due_on).sort((a, b) => a.due_on!.localeCompare(b.due_on!))[0];
    return { p, h: health(mine), next, blockers: mine.filter((t) => t.status === "blocked").length };
  });

  const risks = [
    ...load.filter((l) => l.pct > 100).map((l) => `${l.p.name} is allocated ${l.pct}% across projects`),
    ...(graph?.graph
      ? graph.bus_factor.map((b) => `${b.name} holds ${Math.round(b.share * 100)}% of what Noa has seen on ${b.project} (bus factor 1)`)
      : dir.projects
          .filter((p) => projectPeople(p, dir.people).length === 1)
          .map((p) => `Only ${projectPeople(p, dir.people)[0].person.name} works on ${p.name} (bus factor 1)`)),
    ...open
      .filter((t) => t.status === "blocked")
      .map((t) => `${t.title} in ${dir.project(t.project_id)?.name} is blocked${t.blocked_reason ? `: ${t.blocked_reason}` : ""}`),
    ...open.filter((t) => isLate(t.due_on)).map((t) => `${t.title} in ${dir.project(t.project_id)?.name} is ${dueLabel(t.due_on)}`),
  ];

  return (
    <div className="mx-auto max-w-6xl">
      <PageHeader title={`Portfolio · ${dir.projects.length} active projects`} sub={`${load.length} people allocated`} />
      <div className="grid gap-5 lg:grid-cols-[1.4fr_1fr]">
        <Card className="p-0">
          <table className="w-full text-[13px]">
            <thead>
              <tr className="border-b border-line/70 text-left text-[11.5px] text-muted">
                <th className="px-5 py-3 font-medium">Project</th>
                <th className="py-3 font-medium">Health</th>
                <th className="py-3 font-medium">Next deadline</th>
                <th className="px-5 py-3 text-right font-medium">Blockers</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-line/60">
              {rows.map(({ p, h, next, blockers }) => (
                <tr key={p.id}>
                  <td className="px-5 py-3.5 font-medium">
                    <Link href={`/projects/${p.key}`} className="hover:text-accent-fg">
                      {p.name}
                    </Link>
                  </td>
                  <td>
                    <Badge tone={h.tone}>{h.label}</Badge>
                  </td>
                  <td className={next && isLate(next.due_on) ? "text-bad" : ""}>
                    {next ? `${next.title} · ${dueLabel(next.due_on)}` : <span className="text-muted">none</span>}
                  </td>
                  <td className="px-5 text-right tabular-nums">{blockers}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </Card>
        <Card>
          <p className="text-[14px] font-semibold">Workload</p>
          <ul className="mt-4 space-y-3">
            {load.map(({ p, pct }) => (
              <li key={p.id} className="grid grid-cols-[72px_1fr_40px] items-center gap-3 text-[12.5px]">
                <span className="truncate">{p.name}</span>
                <span className="relative h-2 rounded-full bg-bg">
                  <span
                    className={`absolute inset-y-0 left-0 rounded-full ${pct > 100 ? "bg-bad/70" : "bg-accent/70"}`}
                    style={{ width: `${Math.min(pct, 120) / 1.2}%` }}
                  />
                  <span className="absolute inset-y-[-3px] left-[83.3%] w-px bg-ink/30" title="100%" />
                </span>
                <span className="text-right tabular-nums text-muted">{pct}%</span>
              </li>
            ))}
          </ul>
        </Card>
      </div>
      {graph?.graph && graph.key_people.length > 0 && (
        <Card className="mt-5">
          <p className="text-[14px] font-semibold">Who the work runs through</p>
          <p className="mt-0.5 text-[12px] text-muted">PageRank over the project graph: tasks, decisions and messages.</p>
          <div className="mt-3 flex flex-wrap gap-2">
            {graph.key_people.map((k, i) => (
              <span key={k.person_id} className="rounded-full bg-bg px-3 py-1.5 text-[12.5px]">
                <span className="mr-1.5 font-mono text-[11px] text-muted">{i + 1}</span>
                {k.name}
              </span>
            ))}
          </div>
        </Card>
      )}
      <Card className="mt-5">
        <p className="text-[14px] font-semibold">Risks</p>
        {risks.length === 0 ? (
          <p className="mt-3 text-[13.5px] text-muted">Nothing stands out right now.</p>
        ) : (
          <ul className="mt-3 space-y-2 text-[13.5px]">
            {risks.map((r) => (
              <li key={r} className="flex items-start gap-2">
                <span className="mt-1.5 size-1.5 shrink-0 rounded-full bg-signal" />
                {r}
              </li>
            ))}
          </ul>
        )}
      </Card>
    </div>
  );
}
