"use client";

import { DndContext, PointerSensor, useDraggable, useDroppable, useSensor, useSensors, type DragEndEvent } from "@dnd-kit/core";
import { CheckCircleIcon, GavelIcon, XIcon } from "@phosphor-icons/react";
import { AnimatePresence, motion } from "motion/react";
import { useId, useState } from "react";
import { Avatar, Badge, Button, Card, SourceChip } from "@/components/ui";
import { cn } from "@/lib/cn";
import { allocations, decisions, ktBrief, person, project, projectMeta, statusLabel, taskHistory, tasks as seed, type Status, type Task } from "@/lib/mock";

const tabs = ["Overview", "Board", "Timeline", "Decisions", "People", "KT"] as const;
type Tab = (typeof tabs)[number];
const columns: Status[] = ["proposed", "todo", "in_progress", "blocked", "done"];
const healthTone = { on_track: "good", at_risk: "warn", blocked: "bad" } as const;

/* Project page (3.10): header card, tabs, and a task drawer opened from any card. */
export function ProjectView({ id }: { id: string }) {
  const p = project(id)!;
  const meta = projectMeta[id];
  const [tab, setTab] = useState<Tab>("Board");
  const [tasks, setTasks] = useState(() => seed.filter((t) => t.project === id));
  const [openTask, setOpenTask] = useState<string | null>(null);
  const open = tasks.find((t) => t.id === openTask) ?? null;

  return (
    <div className="mx-auto max-w-7xl">
      <section className="rounded-[26px] wash p-6 card-shadow">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div className="min-w-0">
            <div className="flex items-center gap-2.5">
              <h1 className="text-[26px] leading-tight font-semibold tracking-[-0.03em]">{p.name}</h1>
              <Badge tone={healthTone[p.health]}>{p.health.replace("_", " ")}</Badge>
            </div>
            <p className="mt-1.5 max-w-2xl text-[14px] text-ink/75">{meta?.description}</p>
            <p className="mt-2 text-[12.5px] text-muted">
              Lead {person(p.lead)?.name} · next deadline {p.nextDeadline} · listening in {meta?.channels.join(", ")}
            </p>
          </div>
          <div className="flex items-center gap-3">
            <div className="flex -space-x-1.5">
              {meta?.members.map((m) => (
                <span key={m} className="rounded-full ring-2 ring-white" title={person(m)?.name}>
                  <Avatar initials={person(m)!.initials} size={30} />
                </span>
              ))}
            </div>
            <Button size="sm">+ Task</Button>
          </div>
        </div>
        <div className="mt-5 flex items-center gap-3">
          <div className="h-1.5 max-w-xs flex-1 rounded-full bg-surface">
            <div className="h-full rounded-full bg-accent" style={{ width: `${meta?.progress ?? 0}%` }} />
          </div>
          <span className="text-[12px] tabular-nums text-muted">{meta?.progress}% done</span>
        </div>
      </section>

      <div role="tablist" className="no-scrollbar my-5 flex gap-1 overflow-x-auto rounded-full bg-surface p-1 ring-1 ring-line sm:w-fit">
        {tabs.map((t) => (
          <button
            key={t}
            role="tab"
            aria-selected={tab === t}
            onClick={() => setTab(t)}
            className={cn(
              "shrink-0 rounded-full px-4 py-1.5 text-[13px] font-medium transition-colors",
              tab === t ? "bg-accent text-white" : "text-ink/70 hover:bg-bg hover:text-ink",
            )}
          >
            {t}
          </button>
        ))}
      </div>
      {tab === "Overview" && <Overview id={id} tasks={tasks} onOpen={setOpenTask} />}
      {tab === "Board" && <Board tasks={tasks} setTasks={setTasks} onOpen={setOpenTask} />}
      {tab === "Timeline" && <Timeline tasks={tasks} />}
      {tab === "Decisions" && <Decisions id={id} />}
      {tab === "People" && <People id={id} />}
      {tab === "KT" && <KT />}

      <TaskDrawer task={open} onClose={() => setOpenTask(null)} />
    </div>
  );
}

function Overview({ id, tasks, onOpen }: { id: string; tasks: Task[]; onOpen: (id: string) => void }) {
  const counts = columns.map((c) => ({ c, n: tasks.filter((t) => t.status === c).length }));
  const blocked = tasks.filter((t) => t.status === "blocked");
  const recent = decisions.filter((d) => d.project === id);
  return (
    <div className="grid gap-5 lg:grid-cols-[1.4fr_1fr]">
      <div className="space-y-5">
        <Card>
          <p className="text-[14px] font-semibold">Where things stand</p>
          <div className="mt-4 grid grid-cols-5 gap-2">
            {counts.map(({ c, n }) => (
              <div key={c} className="rounded-xl bg-bg px-3 py-3">
                <p className="text-[20px] font-semibold tabular-nums">{n}</p>
                <p className="text-[11.5px] text-muted">{statusLabel[c]}</p>
              </div>
            ))}
          </div>
        </Card>
        <Card>
          <p className="text-[14px] font-semibold">Needs attention</p>
          <ul className="mt-3 space-y-2">
            {blocked.length === 0 && <li className="text-[13px] text-muted">Nothing blocked.</li>}
            {blocked.map((t) => (
              <li key={t.id}>
                <button onClick={() => onOpen(t.id)} className="flex w-full items-center gap-3 rounded-xl bg-bad/5 px-3 py-2.5 text-left ring-1 ring-bad/15 hover:bg-bad/10">
                  <span className="size-2 rounded-full bg-bad" />
                  <span className="flex-1 text-[13.5px] font-medium">{t.title}</span>
                  <SourceChip source={t.source} withQuote />
                </button>
              </li>
            ))}
          </ul>
        </Card>
      </div>
      <Card>
        <p className="text-[14px] font-semibold">Recent decisions</p>
        <ul className="mt-3 space-y-3">
          {recent.length === 0 && <li className="text-[13px] text-muted">No decisions yet.</li>}
          {recent.map((d) => (
            <li key={d.id} className="rounded-xl bg-bg p-3">
              <p className="text-[13.5px] font-medium">{d.title}</p>
              <p className="mt-0.5 text-[12px] text-muted">{d.affects}</p>
              <div className="mt-1.5">
                <SourceChip source={d.source} />
              </div>
            </li>
          ))}
        </ul>
      </Card>
    </div>
  );
}

function People({ id }: { id: string }) {
  const meta = projectMeta[id];
  return (
    <Card className="p-0">
      <table className="w-full text-[13px]">
        <thead>
          <tr className="border-b border-line text-left text-[11.5px] text-muted">
            <th className="px-5 py-3 font-medium">Person</th>
            <th className="py-3 font-medium">Role</th>
            <th className="py-3 font-medium">Reports to</th>
            <th className="py-3 font-medium">Allocation</th>
            <th className="px-5 py-3 text-right font-medium">Open tasks</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-line">
          {meta?.members.map((m) => {
            const who = person(m)!;
            const alloc = allocations.find((a) => a.person === m);
            return (
              <tr key={m}>
                <td className="px-5 py-3">
                  <span className="flex items-center gap-2.5">
                    <Avatar initials={who.initials} size={28} />
                    <span className="font-medium">{who.name}</span>
                  </span>
                </td>
                <td>{who.title}</td>
                <td className="text-muted">{person(who.reportsTo)?.name ?? "—"}</td>
                <td>
                  <span className="flex items-center gap-2">
                    <span className="h-1.5 w-20 rounded-full bg-bg">
                      <span className="block h-full rounded-full bg-accent" style={{ width: `${alloc?.percent ?? 0}%` }} />
                    </span>
                    <span className="tabular-nums text-muted">{alloc?.percent ?? 0}%</span>
                  </span>
                </td>
                <td className="px-5 text-right tabular-nums">{seed.filter((t) => t.project === id && t.owner === m && t.status !== "done").length}</td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </Card>
  );
}

function TaskDrawer({ task, onClose }: { task: Task | null; onClose: () => void }) {
  const history = task ? taskHistory[task.id] ?? [{ at: task.source.when, who: "Noa", what: `Created from ${task.source.where}` }] : [];
  const owner = person(task?.owner);
  return (
    <AnimatePresence>
      {task && (
        <>
          <motion.div className="fixed inset-0 z-40 bg-ink/15" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} onClick={onClose} />
          <motion.aside
            role="dialog"
            aria-modal
            aria-label={task.title}
            initial={{ x: 40, opacity: 0 }}
            animate={{ x: 0, opacity: 1 }}
            exit={{ x: 40, opacity: 0 }}
            transition={{ type: "spring", stiffness: 340, damping: 34 }}
            className="fixed inset-y-2 right-2 z-50 flex w-[min(440px,calc(100%-1rem))] flex-col overflow-hidden rounded-[22px] bg-surface card-shadow"
          >
            <div className="flex items-start gap-3 border-b border-line p-5">
              <div className="min-w-0 flex-1">
                <Badge tone={task.status === "blocked" ? "bad" : "accent"}>{statusLabel[task.status]}</Badge>
                <h2 className="mt-2 text-[18px] font-semibold tracking-tight">{task.title}</h2>
              </div>
              <button aria-label="Close" onClick={onClose} className="grid size-8 place-items-center rounded-full hover:bg-bg">
                <XIcon size={16} />
              </button>
            </div>
            <div className="flex-1 space-y-5 overflow-y-auto p-5">
              <dl className="grid grid-cols-2 gap-3 text-[13px]">
                <div className="rounded-xl bg-bg p-3">
                  <dt className="text-[11px] text-muted">Owner</dt>
                  <dd className="mt-1 flex items-center gap-2 font-medium">
                    {owner && <Avatar initials={owner.initials} size={20} />} {owner?.name ?? "Unassigned"}
                  </dd>
                </div>
                <div className="rounded-xl bg-bg p-3">
                  <dt className="text-[11px] text-muted">Due</dt>
                  <dd className="mt-1 font-medium">{task.due ?? "No date"}</dd>
                </div>
              </dl>
              <section>
                <p className="text-[12px] font-semibold text-muted">Source</p>
                <div className="mt-2 rounded-xl bg-bg p-3">
                  {task.source.quote && <p className="text-[13.5px]">&ldquo;{task.source.quote}&rdquo;</p>}
                  <div className="mt-2">
                    <SourceChip source={task.source} />
                  </div>
                </div>
              </section>
              <section>
                <p className="text-[12px] font-semibold text-muted">History</p>
                <ol className="mt-2 space-y-3 border-l border-line pl-4">
                  {history.map((h) => (
                    <li key={h.at + h.what} className="relative">
                      <span className="absolute top-1.5 -left-[21px] size-2.5 rounded-full bg-mist ring-2 ring-white" />
                      <p className="text-[13px]">
                        <span className="font-medium">{h.who}</span> {h.what}
                      </p>
                      <p className="text-[11.5px] text-muted">{h.at}</p>
                    </li>
                  ))}
                </ol>
              </section>
            </div>
            <div className="flex gap-2 border-t border-line p-4">
              <Button size="sm">Mark done</Button>
              <Button size="sm" variant="ghost">
                Change deadline
              </Button>
              <Button size="sm" variant="quiet" className="ml-auto">
                Undo last change
              </Button>
            </div>
          </motion.aside>
        </>
      )}
    </AnimatePresence>
  );
}

function Board({ tasks, setTasks, onOpen }: { tasks: Task[]; setTasks: (fn: (t: Task[]) => Task[]) => void; onOpen: (id: string) => void }) {
  const dndId = useId();
  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 4 } }));
  const onDragEnd = (e: DragEndEvent) => {
    const to = e.over?.id as Status | undefined;
    if (!to) return;
    setTasks((ts) => ts.map((t) => (t.id === e.active.id ? { ...t, status: to } : t)));
  };
  return (
    <DndContext id={dndId} sensors={sensors} onDragEnd={onDragEnd}>
      <div className="grid gap-3 overflow-x-auto pb-2 md:grid-cols-5">
        {columns.map((c) => (
          <Column key={c} status={c} tasks={tasks.filter((t) => t.status === c)} onOpen={onOpen} />
        ))}
      </div>
      <p className="mt-3 text-[12px] text-muted">Dashed cards are proposals. Drag a card to change its status; Noa records who moved it.</p>
    </DndContext>
  );
}

function Column({ status, tasks, onOpen }: { status: Status; tasks: Task[]; onOpen: (id: string) => void }) {
  const { setNodeRef, isOver } = useDroppable({ id: status });
  return (
    <div ref={setNodeRef} className={cn("min-h-[460px] rounded-2xl p-2.5 transition-colors", isOver ? "bg-mist" : "bg-surface/60 ring-1 ring-line")}>
      <p className="mb-2 flex items-center justify-between px-1 text-[12px] font-semibold">
        {statusLabel[status]} <span className="font-normal text-muted">{tasks.length}</span>
      </p>
      <div className="space-y-2">
        {tasks.map((t) => (
          <TaskCard key={t.id} task={t} onOpen={onOpen} />
        ))}
      </div>
    </div>
  );
}

function TaskCard({ task, onOpen }: { task: Task; onOpen: (id: string) => void }) {
  const { attributes, listeners, setNodeRef, transform, isDragging } = useDraggable({ id: task.id });
  const owner = person(task.owner);
  return (
    <div
      ref={setNodeRef}
      {...listeners}
      {...attributes}
      onClick={() => onOpen(task.id)}
      style={transform ? { transform: `translate(${transform.x}px, ${transform.y}px)` } : undefined}
      className={cn(
        "cursor-grab rounded-xl bg-surface p-3 text-left ring-1 ring-line/80 active:cursor-grabbing",
        task.status === "proposed" && "ring-accent/40 [border:1px_dashed_var(--color-accent)]",
        task.status === "blocked" && "ring-bad/40",
        isDragging && "z-10 shadow-xl",
      )}
    >
      <p className="text-[13px] font-medium">{task.title}</p>
      <div className="mt-2 flex items-center gap-2">
        {owner && <Avatar initials={owner.initials} size={20} />}
        {task.due && <span className="text-[11px] text-muted">{task.due}</span>}
      </div>
      <div className="mt-2">
        <SourceChip source={task.source} />
      </div>
    </div>
  );
}

const DAYS = ["Oct 13", "Oct 14", "Oct 15", "Oct 16", "Oct 17", "Oct 18", "Oct 19", "Oct 20", "Oct 21", "Oct 22"];
function Timeline({ tasks }: { tasks: Task[] }) {
  const rows = tasks.filter((t) => t.start && t.end);
  const col = (d?: string) => Math.max(0, DAYS.indexOf(d ?? ""));
  return (
    <Card className="overflow-x-auto p-0">
      <div className="min-w-[760px]">
        <div className="grid grid-cols-[180px_repeat(10,1fr)] border-b border-line/70 text-[11px] text-muted">
          <span className="px-4 py-2.5">Task</span>
          {DAYS.map((d) => (
            <span key={d} className={cn("py-2.5 text-center", d === "Oct 15" && "font-semibold text-signal")}>
              {d.slice(4)}
            </span>
          ))}
        </div>
        {rows.map((t) => (
          <div key={t.id} className="grid grid-cols-[180px_repeat(10,1fr)] items-center border-b border-line/50 py-2">
            <span className="truncate px-4 text-[12.5px] font-medium">{t.title}</span>
            <span
              style={{ gridColumn: `${col(t.start) + 2} / ${col(t.end) + 3}` }}
              className={cn(
                "mx-0.5 h-5 rounded-full",
                t.status === "blocked" ? "bg-bad/25" : t.status === "done" ? "bg-good/25" : "bg-accent/20",
              )}
              title={t.dependsOn ? `Depends on ${t.dependsOn.join(", ")}` : undefined}
            />
          </div>
        ))}
        <div className="flex items-center justify-between gap-4 bg-mist/50 px-4 py-3 text-[12.5px]">
          <span>Noa heard &ldquo;push share links to next week&rdquo; in the weekly sync.</span>
          <span className="flex gap-2">
            <Button size="sm">Apply</Button>
            <Button size="sm" variant="ghost">
              Ignore
            </Button>
          </span>
        </div>
      </div>
    </Card>
  );
}

function Decisions({ id }: { id: string }) {
  const list = decisions.filter((d) => d.project === id);
  return (
    <div className="grid gap-5 lg:grid-cols-[1fr_1fr]">
      <Card>
        <p className="mb-3 flex items-center gap-1.5 text-[14px] font-semibold">
          <GavelIcon size={16} className="text-accent-fg" /> Decided today ({list.length})
        </p>
        <ul className="space-y-2.5">
          {list.map((d) => (
            <li key={d.id} className="rounded-2xl bg-bg p-3.5">
              <p className="text-[13.5px] font-medium">{d.title}</p>
              <p className="mt-0.5 text-[12px] text-muted">
                {d.by.map((b) => person(b)?.name).join(", ")} · {d.affects}
              </p>
              <div className="mt-1.5">
                <SourceChip source={d.source} />
              </div>
            </li>
          ))}
          {list.length === 0 && <p className="text-[13px] text-muted">No decisions today.</p>}
        </ul>
      </Card>
      <Card>
        <p className="text-[14px] font-semibold">Edit shared item</p>
        <p className="mt-3 text-[11px] text-muted">Item</p>
        <p className="text-[13.5px]">Board report PDF · deadline</p>
        <div className="mt-3 flex gap-2">
          {["Deadline", "Scope", "Owner", "Status"].map((c, i) => (
            <Badge key={c} tone={i === 0 ? "accent" : "neutral"}>
              {c}
            </Badge>
          ))}
        </div>
        <p className="mt-3 text-[15px] font-semibold">Fri → Mon</p>
        <p className="mt-3 text-[11px] text-muted">Reason</p>
        <p className="rounded-xl bg-bg px-3 py-2 text-[13px]">Waiting on the brand&apos;s logo pack</p>
        <p className="mt-3 rounded-xl bg-mist/60 px-3 py-2 text-[12.5px]">Needs approval from Prathamesh, your lead. Owners are notified once approved.</p>
        <div className="mt-4 flex justify-end gap-2">
          <Button variant="ghost" size="sm">
            Cancel
          </Button>
          <Button size="sm">Submit</Button>
        </div>
      </Card>
    </div>
  );
}

function KT() {
  return (
    <div className="grid gap-5 lg:grid-cols-[1.4fr_1fr]">
      <Card>
        <p className="mb-3 text-[14px] font-semibold">KT brief · for people joining this project</p>
        <ul className="space-y-2.5">
          {ktBrief.map((l) => (
            <li key={l.title} className="flex items-start gap-3 rounded-2xl bg-bg p-3.5">
              <CheckCircleIcon size={18} weight="fill" className="mt-0.5 shrink-0 text-accent-fg" />
              <div className="flex-1">
                <p className="text-[12.5px] font-semibold">{l.title}</p>
                <p className="text-[13px] text-ink/75">{l.body}</p>
              </div>
              <span className="font-mono text-[10.5px] text-muted">{l.src}</span>
            </li>
          ))}
        </ul>
      </Card>
      <Card>
        <p className="text-[14px] font-semibold">Checklist</p>
        <ul className="mt-3 space-y-2 text-[13px]">
          {["Read the brief", "Meet Prathamesh", "Meet Ojas about Workers", "Pick up Coverage notes v2", "Day-7 check-in"].map((c, i) => (
            <li key={c} className="flex items-center gap-2">
              <span className={cn("grid size-4 place-items-center rounded-[5px]", i < 3 ? "bg-accent text-white" : "ring-1 ring-line")}>
                {i < 3 && <CheckCircleIcon size={10} weight="bold" />}
              </span>
              {c}
            </li>
          ))}
        </ul>
        <p className="mt-4 text-[12px] text-muted">Questions about the old project still reach the previous owner for 2 weeks.</p>
      </Card>
    </div>
  );
}
