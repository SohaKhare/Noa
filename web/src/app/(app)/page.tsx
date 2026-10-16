import { ArrowRightIcon, CalendarBlankIcon, ChatCircleDotsIcon, GavelIcon, TrayIcon, WarningCircleIcon } from "@phosphor-icons/react/ssr";
import Link from "next/link";
import { Hello } from "@/components/Hello";
import { Badge, SourceChip } from "@/components/ui";
import { decisions, me, project, projects, proposals, tasks, type Task } from "@/lib/mock";

export const metadata = { title: "My day" };

/* My day (2.12): one list across every project I'm on, grouped by project, with what's waiting on me on the right. */

const mineIds = new Set([me, "sa", "ve"]);

export default function MyDay() {
  const mine = tasks.filter((t) => t.owner && mineIds.has(t.owner) && t.status !== "done" && t.status !== "proposed");
  const byProject = projects
    .map((p) => ({ p, items: mine.filter((t) => t.project === p.id) }))
    .filter((g) => g.items.length > 0);
  const blocked = tasks.filter((t) => t.status === "blocked");

  return (
    <div className="mx-auto max-w-6xl">
      <section className="rounded-[26px] wash p-7 card-shadow">
        <p className="eyebrow text-muted">Thursday, 15 October</p>
        <h1 className="mt-2 text-[28px] leading-tight font-semibold tracking-[-0.03em]"><Hello /></h1>
        <p className="mt-1.5 text-[14.5px] text-muted">
          {mine.length} things today across {byProject.length} projects · {proposals.length} proposals waiting · {blocked.length} blocked
        </p>
        <div className="mt-5 grid gap-3 sm:grid-cols-3">
          <Stat Icon={TrayIcon} label="Waiting on you" value={`${proposals.length} proposals`} href="/inbox" />
          <Stat Icon={GavelIcon} label="Decided today" value={`${decisions.length} decisions`} href="/projects/a" />
          <Stat Icon={WarningCircleIcon} label="Blocked" value={blocked.map((b) => b.title).join(", ") || "Nothing"} href="/projects/a" tone="bad" />
        </div>
      </section>

      <div className="mt-6 grid gap-6 lg:grid-cols-[1.55fr_1fr]">
        <div className="space-y-4">
          {byProject.map(({ p, items }) => (
            <section key={p.id} className="overflow-hidden rounded-[22px] bg-surface card-shadow">
              <Link href={`/projects/${p.id}`} className="flex items-center justify-between border-b border-line px-5 py-3 hover:bg-bg">
                <span className="text-[13.5px] font-semibold">{p.name}</span>
                <span className="flex items-center gap-1 text-[12px] text-muted">
                  next {p.nextDeadline} <ArrowRightIcon size={12} />
                </span>
              </Link>
              <ul className="divide-y divide-line">
                {items.map((t) => (
                  <TaskRow key={t.id} t={t} />
                ))}
              </ul>
            </section>
          ))}
        </div>

        <aside className="space-y-4">
          <section className="rounded-[22px] bg-surface p-5 card-shadow">
            <p className="flex items-center justify-between text-[14px] font-semibold">
              Waiting on you
              <Link href="/inbox" className="text-[12px] font-normal text-muted hover:text-ink">
                Open inbox
              </Link>
            </p>
            <ul className="mt-3 space-y-2">
              {proposals.slice(0, 3).map((pr) => (
                <li key={pr.id} className="rounded-xl bg-bg px-3 py-2.5">
                  <p className="text-[13px] font-medium">{pr.summary}</p>
                  <SourceChip source={pr.source} />
                </li>
              ))}
            </ul>
          </section>

          <section className="rounded-[22px] bg-surface p-5 card-shadow">
            <p className="text-[14px] font-semibold">Decided today</p>
            <ul className="mt-3 space-y-3">
              {decisions.map((d) => (
                <li key={d.id} className="flex gap-3">
                  <span className="mt-1 grid size-6 shrink-0 place-items-center rounded-full bg-mist text-accent">
                    <GavelIcon size={12} />
                  </span>
                  <span>
                    <span className="block text-[13px] font-medium">{d.title}</span>
                    <span className="block text-[11.5px] text-muted">
                      {project(d.project)?.name} · {d.affects}
                    </span>
                  </span>
                </li>
              ))}
            </ul>
          </section>

          <section className="rounded-[22px] bg-surface p-5 card-shadow">
            <p className="text-[14px] font-semibold">Coming up</p>
            <ul className="mt-3 space-y-2.5 text-[13px]">
              {projects.map((p) => (
                <li key={p.id} className="flex items-center gap-2.5">
                  <CalendarBlankIcon size={14} className="text-muted" />
                  <span className="flex-1">{p.name}</span>
                  <span className="tabular-nums text-muted">{p.nextDeadline}</span>
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

function TaskRow({ t }: { t: Task }) {
  return (
    <li className="flex items-center gap-3 px-5 py-3.5 hover:bg-bg/60">
      <span className="size-4 shrink-0 rounded-[5px] ring-1 ring-ink/25" />
      <div className="min-w-0 flex-1">
        <p className="text-[14px] font-medium">{t.title}</p>
        <SourceChip source={t.source} />
      </div>
      {t.status === "blocked" ? <Badge tone="bad">blocked</Badge> : <Badge>{t.status === "in_progress" ? "in progress" : t.due}</Badge>}
    </li>
  );
}
