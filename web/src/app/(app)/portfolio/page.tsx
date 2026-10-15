import Link from "next/link";
import { Badge, Card, PageHeader } from "@/components/ui";
import { allocations, person, projects } from "@/lib/mock";

export const metadata = { title: "Portfolio" };

const load = [
  { id: "pr", pct: 110 },
  { id: "ve", pct: 115 },
  { id: "oj", pct: 85 },
  { id: "ab", pct: 70 },
  { id: "sa", pct: 90 },
  { id: "so", pct: 60 },
];

const risks = [
  "Only Vedant knows the Veriq PDF renderer (bus factor 1)",
  "Board report PDF slip pushes 2 tasks in Veriq",
  "Saish is split across Veriq and Emmarie at 140% this week",
];

export default function Portfolio() {
  return (
    <div className="mx-auto max-w-6xl">
      <PageHeader title={`Portfolio · ${projects.length} active projects`} sub={`${allocations.length} people allocated this week`} />
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
              {projects.map((p) => (
                <tr key={p.id}>
                  <td className="px-5 py-3.5 font-medium">
                    <Link href={`/projects/${p.id}`} className="hover:text-accent-fg">
                      {p.name}
                    </Link>
                  </td>
                  <td>
                    <Badge tone={p.health === "on_track" ? "good" : p.health === "at_risk" ? "warn" : "bad"}>
                      {p.health.replace("_", " ")}
                    </Badge>
                  </td>
                  <td>{p.nextDeadline}</td>
                  <td className="px-5 text-right tabular-nums">{p.blockers}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </Card>
        <Card>
          <p className="text-[14px] font-semibold">Workload</p>
          <ul className="mt-4 space-y-3">
            {load.map((l) => (
              <li key={l.id} className="grid grid-cols-[64px_1fr_40px] items-center gap-3 text-[12.5px]">
                <span>{person(l.id)?.name}</span>
                <span className="relative h-2 rounded-full bg-bg">
                  <span
                    className={`absolute inset-y-0 left-0 rounded-full ${l.pct > 100 ? "bg-bad/70" : "bg-accent/70"}`}
                    style={{ width: `${Math.min(l.pct, 120) / 1.2}%` }}
                  />
                  <span className="absolute inset-y-[-3px] left-[83.3%] w-px bg-ink/30" title="100%" />
                </span>
                <span className="text-right tabular-nums text-muted">{l.pct}%</span>
              </li>
            ))}
          </ul>
        </Card>
      </div>
      <Card className="mt-5">
        <p className="text-[14px] font-semibold">Risks from the graph</p>
        <ul className="mt-3 space-y-2 text-[13.5px]">
          {risks.map((r) => (
            <li key={r} className="flex items-start gap-2">
              <span className="mt-1.5 size-1.5 shrink-0 rounded-full bg-signal" />
              {r}
            </li>
          ))}
        </ul>
      </Card>
    </div>
  );
}
