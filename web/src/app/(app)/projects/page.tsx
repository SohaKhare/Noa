import { PlusIcon } from "@phosphor-icons/react/ssr";
import Link from "next/link";
import { Avatar, Badge, PageHeader } from "@/components/ui";
import { person, projectMeta, projects, tasks } from "@/lib/mock";

export const metadata = { title: "Projects" };

const healthTone = { on_track: "good", at_risk: "warn", blocked: "bad" } as const;

export default function Projects() {
  return (
    <div className="mx-auto max-w-6xl">
      <PageHeader
        title="Projects"
        sub={`${projects.length} active · updated from your channels`}
        actions={
          <button className="inline-flex items-center gap-1.5 rounded-full bg-surface px-3.5 py-1.5 text-[13px] font-medium ring-1 ring-line hover:bg-bg">
            <PlusIcon size={14} weight="bold" /> New project
          </button>
        }
      />
      <div className="grid gap-4 sm:grid-cols-2">
        {projects.map((p) => {
          const meta = projectMeta[p.id];
          const open = tasks.filter((t) => t.project === p.id && t.status !== "done").length;
          return (
            <Link
              key={p.id}
              href={`/projects/${p.id}`}
              className="group rounded-[22px] wash p-5 card-shadow transition-transform duration-300 ease-soft hover:-translate-y-0.5"
            >
              <div className="flex items-start justify-between gap-3">
                <div>
                  <p className="text-[16px] font-semibold tracking-tight">{p.name}</p>
                  <p className="text-[12px] text-muted">{meta?.client}</p>
                </div>
                <Badge tone={healthTone[p.health]}>{p.health.replace("_", " ")}</Badge>
              </div>
              <p className="mt-3 text-[13.5px] leading-relaxed text-ink/75">{meta?.description}</p>
              <div className="mt-5">
                <div className="flex justify-between text-[11.5px] text-muted">
                  <span>Progress</span>
                  <span className="tabular-nums">{meta?.progress}%</span>
                </div>
                <div className="mt-1.5 h-1.5 rounded-full bg-bg">
                  <div className="h-full rounded-full bg-accent" style={{ width: `${meta?.progress ?? 0}%` }} />
                </div>
              </div>
              <div className="mt-5 flex items-center justify-between">
                <div className="flex -space-x-1.5">
                  {meta?.members.map((m) => (
                    <span key={m} className="rounded-full ring-2 ring-white">
                      <Avatar initials={person(m)!.initials} size={26} />
                    </span>
                  ))}
                </div>
                <p className="text-[12px] text-muted">
                  {open} open · next {p.nextDeadline}
                  {p.blockers > 0 && <span className="text-bad"> · {p.blockers} blocked</span>}
                </p>
              </div>
            </Link>
          );
        })}
      </div>
    </div>
  );
}
