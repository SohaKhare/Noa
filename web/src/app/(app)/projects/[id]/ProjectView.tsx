"use client";

import { DndContext, PointerSensor, useDraggable, useDroppable, useSensor, useSensors, type DragEndEvent } from "@dnd-kit/core";
import { CheckCircleIcon, GavelIcon, XIcon } from "@phosphor-icons/react";
import { useQuery } from "@tanstack/react-query";
import { AnimatePresence, motion } from "motion/react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useId, useState } from "react";
import { FormError } from "@/components/AuthCard";
import { GraphPanel } from "@/components/GraphPanel";
import { Avatar, Badge, Button, Card, SourceChip } from "@/components/ui";
import { ApiError, downloadBrief, getBrief, type WorkDecision, type WorkProject, type WorkTask } from "@/lib/api";
import { cn } from "@/lib/cn";
import { statusLabel, type Source, type Status } from "@/lib/mock";
import { ago, changeText, dueLabel, isLate, nameInitials, projectChannels, projectPeople, startOfToday, toSource, useChanges, useDecideChange, useDecisions, useDirectory, useEditTask, useMoveTask, useProposals, useTasks } from "@/lib/work";

const tabs = ["Overview", "Board", "Timeline", "Decisions", "People", "KT", "Graph"] as const;
type Tab = (typeof tabs)[number];
const columns: Status[] = ["proposed", "todo", "in_progress", "blocked", "done"];

/* Timeline, Decisions and KT still read sample data (2.11, 2.4, 3.2), keyed by the old sample ids. */

/* A board card: a task, or a pending task proposal shown dashed in the Proposed column. */
type BoardCard = {
  id: string;
  title: string;
  status: Status;
  ownerId: string | null;
  due: string | null;
  blockedReason?: string | null;
  source: Source;
  task?: WorkTask;
};

const fromTask = (t: WorkTask): BoardCard => ({
  id: t.id,
  title: t.title,
  status: t.status,
  ownerId: t.owner_id,
  due: t.due_on,
  blockedReason: t.blocked_reason,
  source: toSource(t.source),
  task: t,
});

/* Project page (3.10): header card, tabs, and a task drawer opened from any card. */
export function ProjectView({ projectKey }: { projectKey: string }) {
  const dir = useDirectory();
  const p = dir.project(projectKey);
  const tasksQuery = useTasks({ project_id: p?.id ?? "" });
  const proposals = useProposals();
  const [tab, setTab] = useState<Tab>("Board");
  const [openTask, setOpenTask] = useState<string | null>(null);

  if (dir.isLoading || (p && tasksQuery.isLoading)) return <p className="text-[13px] text-muted">Loading…</p>;
  if (!p)
    return (
      <div className="mx-auto max-w-md py-20 text-center">
        <p className="text-[16px] font-semibold">No project called &ldquo;{projectKey}&rdquo;</p>
        <p className="mt-1 text-[13px] text-muted">It may have been renamed. Pick one from the sidebar.</p>
      </div>
    );

  const tasks = (tasksQuery.data ?? []).map(fromTask);
  const proposed: BoardCard[] = (proposals.data ?? [])
    .filter((x) => x.kind === "task" && x.project_id === p.id)
    .map((x) => ({ id: x.id, title: x.data.title ?? x.summary, status: "proposed", ownerId: x.owner_id, due: x.data.due ?? null, source: toSource(x.source) }));
  const cards = [...proposed, ...tasks];
  const open = tasks.find((t) => t.id === openTask) ?? null;
  const done = tasks.filter((t) => t.status === "done").length;
  const progress = tasks.length ? Math.round((done / tasks.length) * 100) : 0;
  const next = tasks.filter((t) => t.status !== "done" && t.due).sort((a, b) => a.due!.localeCompare(b.due!))[0];
  const team = projectPeople(p, dir.people);
  const channels = projectChannels(p, dir.channels);

  return (
    <div className="mx-auto max-w-7xl">
      <section className="rounded-[26px] wash p-6 card-shadow">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div className="min-w-0">
            <div className="flex items-center gap-2.5">
              <h1 className="text-[26px] leading-tight font-semibold tracking-[-0.03em]">{p.name}</h1>
              {tasks.some((t) => t.status === "blocked") ? <Badge tone="warn">has blockers</Badge> : <Badge tone="good">on track</Badge>}
            </div>
            <p className="mt-1.5 max-w-2xl text-[14px] text-ink/75">{p.about}</p>
            <p className="mt-2 text-[12.5px] text-muted">
              Lead {dir.person(p.lead_id)?.name ?? "not set"}
              {next && ` · next deadline ${next.title}, ${dueLabel(next.due)}`}
              {channels.length > 0 && ` · listening in ${channels.join(", ")}`}
            </p>
          </div>
          <div className="flex items-center gap-3">
            <div className="flex -space-x-1.5">
              {team.map(({ person: m }) => (
                <span key={m.id} className="rounded-full ring-2 ring-white" title={m.name}>
                  <Avatar initials={nameInitials(m.name)} size={30} />
                </span>
              ))}
            </div>
          </div>
        </div>
        <div className="mt-5 flex items-center gap-3">
          <div className="h-1.5 max-w-xs flex-1 rounded-full bg-surface">
            <div className="h-full rounded-full bg-accent" style={{ width: `${progress}%` }} />
          </div>
          <span className="text-[12px] tabular-nums text-muted">
            {done} of {tasks.length} done
          </span>
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
      {tab === "Overview" && <Overview project={p} cards={cards} onOpen={setOpenTask} />}
      {tab === "Board" && <Board cards={cards} onOpen={setOpenTask} />}
      {tab === "Timeline" && <Timeline project={p} />}
      {tab === "Decisions" && <Decisions project={p} />}
      {tab === "People" && <People project={p} tasks={tasks} />}
      {tab === "KT" && <KT project={p} />}
      {tab === "Graph" && dir.orgId && <GraphPanel orgId={dir.orgId} projectId={p.id} />}

      <TaskDrawer card={open} onClose={() => setOpenTask(null)} />
    </div>
  );
}

/* Moves a task to another status, updating the board at once and rolling back on error. */
/* Change records for the project's tasks (2.19): who changed what, and what waits for the lead. */
function RecentChanges({ project }: { project: WorkProject }) {
  const dir = useDirectory();
  const changes = useChanges({ project_id: project.id }).data ?? [];
  const tasks = useTasks({ project_id: project.id }).data ?? [];
  const title = (id: string) => tasks.find((t) => t.id === id)?.title ?? "A task";
  return (
    <Card>
      <p className="text-[14px] font-semibold">Recent changes</p>
      <p className="mt-0.5 text-[12px] text-muted">Deadline and scope changes wait for the lead. Other edits apply at once and can be reverted.</p>
      <ul className="mt-3 space-y-2">
        {changes.length === 0 && <li className="text-[13px] text-muted">No changes yet.</li>}
        {changes.slice(0, 12).map((c) => (
          <li key={c.id} className="rounded-xl bg-bg px-3 py-2.5">
            <p className="text-[13px]">
              <span className="font-medium">{title(c.task_id)}</span> · {changeText(c, (id) => dir.person(id)?.name)}
            </p>
            <p className="text-[11.5px] text-muted">
              {dir.byUser(c.requested_by_id)?.name ?? "Someone"} · {ago(c.inserted_at)}
              {c.status !== "applied" && ` · ${c.status === "pending" ? "waiting for approval" : c.status}`}
            </p>
          </li>
        ))}
      </ul>
    </Card>
  );
}

function DecisionItem({ d, replacedBy }: { d: WorkDecision; replacedBy?: WorkDecision }) {
  const dir = useDirectory();
  const who = dir.person(d.made_by_id)?.name;
  const superseded = d.status === "superseded";
  return (
    <li className="rounded-2xl bg-bg p-3.5">
      <p className={cn("text-[13.5px] font-medium", superseded && "text-muted line-through")}>{d.statement}</p>
      <p className="mt-0.5 text-[12px] text-muted">
        {[who, d.kind === "conclusion" ? "conclusion" : null, ago(d.inserted_at)].filter(Boolean).join(" · ")}
        {replacedBy && <> · replaced by &ldquo;{replacedBy.statement}&rdquo;</>}
      </p>
      {d.source && (
        <div className="mt-1.5">
          <SourceChip source={toSource(d.source)} />
        </div>
      )}
    </li>
  );
}

function Overview({ project, cards, onOpen }: { project: WorkProject; cards: BoardCard[]; onOpen: (id: string) => void }) {
  const counts = columns.map((c) => ({ c, n: cards.filter((t) => t.status === c).length }));
  const blocked = cards.filter((t) => t.status === "blocked");
  const recent = (useDecisions({ project_id: project.id }).data ?? []).filter((d) => d.status === "active").slice(0, 4);
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
                  <span className="text-[12px] text-muted">{t.blockedReason}</span>
                  <SourceChip source={t.source} />
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
            <DecisionItem key={d.id} d={d} />
          ))}
        </ul>
      </Card>
    </div>
  );
}

function People({ project, tasks }: { project: WorkProject; tasks: BoardCard[] }) {
  const dir = useDirectory();
  const team = projectPeople(project, dir.people);
  return (
    <Card className="p-0">
      <table className="w-full text-[13px]">
        <thead>
          <tr className="border-b border-line text-left text-[11.5px] text-muted">
            <th className="px-5 py-3 font-medium">Person</th>
            <th className="py-3 font-medium">Title</th>
            <th className="py-3 font-medium">Allocation</th>
            <th className="px-5 py-3 text-right font-medium">Open tasks</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-line">
          {team.length === 0 && (
            <tr>
              <td colSpan={4} className="px-5 py-6 text-muted">
                Nobody is allocated to {project.name} yet.
              </td>
            </tr>
          )}
          {team.map(({ person: who, percent }) => (
            <tr key={who.id}>
              <td className="px-5 py-3">
                <span className="flex items-center gap-2.5">
                  <Avatar initials={nameInitials(who.name)} size={28} />
                  <span className="font-medium">{who.name}</span>
                  {who.id === project.lead_id && <Badge tone="accent">Lead</Badge>}
                  {!who.joined && <span className="text-[11.5px] text-muted">not joined yet</span>}
                </span>
              </td>
              <td>{who.title}</td>
              <td>
                <span className="flex items-center gap-2">
                  <span className="h-1.5 w-20 rounded-full bg-bg">
                    <span className="block h-full rounded-full bg-accent" style={{ width: `${percent}%` }} />
                  </span>
                  <span className="tabular-nums text-muted">{percent}%</span>
                </span>
              </td>
              <td className="px-5 text-right tabular-nums">{tasks.filter((t) => t.ownerId === who.id && t.status !== "done").length}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </Card>
  );
}

function TaskDrawer({ card: task, onClose }: { card: BoardCard | null; onClose: () => void }) {
  const dir = useDirectory();
  const move = useMoveTask();
  const changes = useChanges({ task_id: task?.id }, !!task).data ?? [];
  const decide = useDecideChange();
  const owner = dir.person(task?.ownerId);
  const project = dir.project(task?.task?.project_id);
  const lead = dir.person(project?.lead_id);
  const pending = changes.filter((c) => c.status === "pending");
  const who = (userId: string | null) => dir.byUser(userId)?.name ?? "Someone";
  const personName = (id: string | null) => dir.person(id)?.name;
  const error = (move.error ?? decide.error) as ApiError | null;

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
              {pending.map((c) => (
                <div key={c.id} className="rounded-xl bg-mist/60 px-3 py-2.5 text-[12.5px]">
                  <p>
                    <span className="font-medium">{who(c.requested_by_id)}</span> asked to change the {changeText(c, personName)}
                    {c.reason && <> because &ldquo;{c.reason}&rdquo;</>}.
                  </p>
                  <p className="mt-0.5 text-muted">Waiting for {lead?.name ?? "a lead"} to approve.</p>
                </div>
              ))}
              <dl className="grid grid-cols-2 gap-3 text-[13px]">
                <div className="rounded-xl bg-bg p-3">
                  <dt className="text-[11px] text-muted">Owner</dt>
                  <dd className="mt-1 flex items-center gap-2 font-medium">
                    {owner && <Avatar initials={nameInitials(owner.name)} size={20} />} {owner?.name ?? "Unassigned"}
                  </dd>
                </div>
                <DueEditor key={task.id} card={task} />
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
                  {changes.map((c) => (
                    <li key={c.id} className="relative">
                      <span className="absolute top-1.5 -left-[21px] size-2.5 rounded-full bg-mist ring-2 ring-white" />
                      <p className={cn("text-[13px]", (c.status === "reverted" || c.status === "rejected") && "text-muted line-through")}>
                        <span className="font-medium">{who(c.requested_by_id)}</span> changed the {changeText(c, personName)}
                      </p>
                      <p className="flex items-center gap-2 text-[11.5px] text-muted">
                        {ago(c.inserted_at)}
                        {c.status !== "applied" && <span>· {c.status === "pending" ? "waiting for approval" : c.status}</span>}
                        {c.status === "applied" && (
                          <button
                            onClick={() => decide.mutate({ id: c.id, action: "revert" })}
                            disabled={decide.isPending}
                            className="font-medium text-accent-fg hover:underline"
                          >
                            Revert
                          </button>
                        )}
                      </p>
                    </li>
                  ))}
                  <li className="relative">
                    <span className="absolute top-1.5 -left-[21px] size-2.5 rounded-full bg-mist ring-2 ring-white" />
                    <p className="text-[13px]">
                      <span className="font-medium">{task.task?.source?.author ?? "Noa"}</span> said it in {task.source.where}
                    </p>
                    <p className="text-[11.5px] text-muted">{task.source.when}</p>
                  </li>
                </ol>
              </section>
            </div>
            <div className="flex flex-wrap gap-2 border-t border-line p-4">
              {error && <FormError>{error.message}</FormError>}
              {task.status === "done" ? (
                <Button size="sm" variant="ghost" disabled={move.isPending} onClick={() => move.mutate({ id: task.id, status: "todo" })}>
                  Reopen
                </Button>
              ) : (
                <Button size="sm" disabled={move.isPending} onClick={() => move.mutate({ id: task.id, status: "done" })}>
                  Mark done
                </Button>
              )}
            </div>
          </motion.aside>
        </>
      )}
    </AnimatePresence>
  );
}

/* The due date, with an editor. A member's change waits for the lead (2.20); a lead's applies at once. */
function DueEditor({ card }: { card: BoardCard }) {
  const edit = useEditTask();
  const [open, setOpen] = useState(false);
  const [due, setDue] = useState(card.due ?? "");
  const [reason, setReason] = useState("");
  const [sent, setSent] = useState<"applied" | "pending" | null>(null);

  const save = () =>
    edit.mutate(
      { id: card.id, due_on: due || null, reason: reason || undefined },
      {
        onSuccess: (r) => {
          setSent(r.pending_changes.some((c) => c.kind === "deadline") ? "pending" : "applied");
          setOpen(false);
          setReason("");
        },
      },
    );

  return (
    <div className="rounded-xl bg-bg p-3">
      <dt className="flex items-center justify-between text-[11px] text-muted">
        Due
        {!open && (
          <button onClick={() => setOpen(true)} className="font-medium text-accent-fg hover:underline">
            Change
          </button>
        )}
      </dt>
      {open ? (
        <dd className="mt-1 space-y-1.5">
          <input type="date" value={due} onChange={(e) => setDue(e.target.value)} aria-label="New due date" className="w-full rounded-lg bg-surface px-2 py-1 text-[12.5px] ring-1 ring-line focus:outline-none" />
          <input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Why? (optional)" aria-label="Reason" className="w-full rounded-lg bg-surface px-2 py-1 text-[12.5px] ring-1 ring-line focus:outline-none" />
          <div className="flex gap-1.5">
            <Button size="sm" disabled={edit.isPending} onClick={save}>
              Save
            </Button>
            <Button size="sm" variant="ghost" onClick={() => setOpen(false)}>
              Cancel
            </Button>
          </div>
          {edit.error && <FormError>{(edit.error as ApiError).message}</FormError>}
        </dd>
      ) : (
        <dd className={cn("mt-1 font-medium", isLate(card.due) && card.status !== "done" && "text-bad")}>
          {dueLabel(card.due) ?? "No date"}
          {sent === "pending" && <span className="block text-[11px] font-normal text-muted">Sent to your lead to approve</span>}
        </dd>
      )}
    </div>
  );
}

function Board({ cards, onOpen }: { cards: BoardCard[]; onOpen: (id: string) => void }) {
  const dndId = useId();
  const router = useRouter();
  const move = useMoveTask();
  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 4 } }));
  const onDragEnd = (e: DragEndEvent) => {
    const to = e.over?.id as Status | undefined;
    const card = cards.find((c) => c.id === e.active.id);
    if (!to || !card || to === card.status) return;
    // Proposals become tasks by approval in the Inbox, not by dragging.
    if (card.status === "proposed" || to === "proposed") return router.push("/inbox");
    move.mutate({ id: card.id, status: to });
  };
  const openCard = (id: string) => (cards.find((c) => c.id === id)?.status === "proposed" ? router.push("/inbox") : onOpen(id));
  return (
    <DndContext id={dndId} sensors={sensors} onDragEnd={onDragEnd}>
      {move.error && (
        <div className="mb-3">
          <FormError>{(move.error as ApiError).message}</FormError>
        </div>
      )}
      <div className="grid gap-3 overflow-x-auto pb-2 md:grid-cols-5">
        {columns.map((c) => (
          <Column key={c} status={c} cards={cards.filter((t) => t.status === c)} onOpen={openCard} />
        ))}
      </div>
      <p className="mt-3 text-[12px] text-muted">
        Dashed cards are proposals waiting in the <Link href="/inbox" className="text-accent-fg hover:underline">Inbox</Link>. Drag a card to change its status.
      </p>
    </DndContext>
  );
}

function Column({ status, cards, onOpen }: { status: Status; cards: BoardCard[]; onOpen: (id: string) => void }) {
  const { setNodeRef, isOver } = useDroppable({ id: status });
  return (
    <div ref={setNodeRef} className={cn("min-h-[460px] rounded-2xl p-2.5 transition-colors", isOver ? "bg-mist" : "bg-surface/60 ring-1 ring-line")}>
      <p className="mb-2 flex items-center justify-between px-1 text-[12px] font-semibold">
        {statusLabel[status]} <span className="font-normal text-muted">{cards.length}</span>
      </p>
      <div className="space-y-2">
        {cards.map((t) => (
          <TaskCard key={t.id} card={t} onOpen={onOpen} />
        ))}
      </div>
    </div>
  );
}

function TaskCard({ card: task, onOpen }: { card: BoardCard; onOpen: (id: string) => void }) {
  const { attributes, listeners, setNodeRef, transform, isDragging } = useDraggable({ id: task.id });
  const owner = useDirectory().person(task.ownerId);
  const late = isLate(task.due) && task.status !== "done";
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
      {task.status === "blocked" && task.blockedReason && <p className="mt-1 text-[11.5px] text-bad">{task.blockedReason}</p>}
      <div className="mt-2 flex items-center gap-2">
        {owner && <Avatar initials={nameInitials(owner.name)} size={20} />}
        {task.due && task.status !== "done" && <span className={cn("text-[11px]", late ? "font-medium text-bad" : "text-muted")}>{dueLabel(task.due)}</span>}
      </div>
      <div className="mt-2">
        <SourceChip source={task.source} />
      </div>
    </div>
  );
}

/*
  Timeline (2.11, read-only): each open task from the day it was created to its due
  date, done tasks to the day they finished, late ones stretched to today in red.
  Pending deadline changes for the project wait underneath for a lead.
*/
function Timeline({ project }: { project: WorkProject }) {
  const dir = useDirectory();
  const tasks = useTasks({ project_id: project.id }).data ?? [];
  const pending = (useChanges({ project_id: project.id, status: "pending" }).data ?? []).filter((c) => c.kind === "deadline");
  const decide = useDecideChange();
  const me = dir.person(dir.me);
  const lead = me?.role === "org_admin" || me?.role === "pm" || project.lead_id === me?.id;

  const day = (iso: string) => {
    const d = new Date(iso.length === 10 ? `${iso}T00:00:00` : iso);
    d.setHours(0, 0, 0, 0);
    return d.getTime();
  };
  const DAY = 86_400_000;
  const today = day(new Date().toISOString().slice(0, 10));
  const rows = tasks
    .map((t) => {
      const start = day(t.inserted_at);
      const end = t.status === "done" && t.done_at ? day(t.done_at) : t.due_on ? day(t.due_on) : null;
      return { t, start, end, late: t.status !== "done" && t.due_on != null && day(t.due_on) < today };
    })
    .sort((a, b) => (a.end ?? Infinity) - (b.end ?? Infinity));
  const first = Math.max(Math.min(today - 3 * DAY, ...rows.map((r) => r.start)), today - 10 * DAY);
  const last = Math.min(Math.max(today + 10 * DAY, ...rows.map((r) => r.end ?? 0)), first + 27 * DAY);
  const days = Array.from({ length: Math.round((last - first) / DAY) + 1 }, (_, i) => first + i * DAY);
  const col = (t: number) => Math.min(days.length - 1, Math.max(0, Math.round((t - first) / DAY)));
  const grid = { gridTemplateColumns: `200px repeat(${days.length}, minmax(28px, 1fr))` };
  const taskTitle = (id: string) => tasks.find((t) => t.id === id)?.title ?? "A task";

  return (
    <Card className="overflow-x-auto p-0">
      <div style={{ minWidth: 200 + days.length * 30 }}>
        <div className="grid border-b border-line/70 text-[11px] text-muted" style={grid}>
          <span className="px-4 py-2.5">Task</span>
          {days.map((d) => (
            <span key={d} className={cn("py-2.5 text-center tabular-nums", d === today && "font-semibold text-signal")}>
              {new Date(d).getDate()}
            </span>
          ))}
        </div>
        {rows.length === 0 && <p className="px-4 py-6 text-[13px] text-muted">No tasks yet.</p>}
        {rows.map(({ t, start, end, late }) => {
          const from = col(start);
          const to = end == null ? from : col(Math.max(end, start));
          return (
            <div key={t.id} className="relative grid items-center border-b border-line/50 py-2" style={grid}>
              <span className="truncate px-4 text-[12.5px] font-medium" title={t.title}>
                {t.title}
              </span>
              {end == null ? (
                <span style={{ gridColumn: `${from + 2}` }} className="mx-auto size-2.5 rounded-full bg-accent/40" title="No due date" />
              ) : (
                <span
                  style={{ gridColumn: `${from + 2} / ${to + 3}` }}
                  title={`${t.title} · ${statusLabel[t.status]}${t.due_on ? ` · due ${dueLabel(t.due_on)}` : ""}`}
                  className={cn(
                    "mx-0.5 h-5 rounded-full",
                    t.status === "blocked" ? "bg-bad/25" : t.status === "done" ? "bg-good/25" : t.status === "in_progress" ? "bg-accent/35" : "bg-accent/20",
                  )}
                />
              )}
              {late && end != null && (
                <span style={{ gridColumn: `${to + 3} / ${col(today) + 3}`, gridRow: 1 }} className="mx-0.5 h-5 rounded-r-full border border-dashed border-bad/50 bg-bad/10" title="Late" />
              )}
            </div>
          );
        })}
        {pending.map((c) => (
          <div key={c.id} className="flex flex-wrap items-center justify-between gap-3 bg-mist/50 px-4 py-3 text-[12.5px]">
            <span>
              {dir.byUser(c.requested_by_id)?.name ?? "Someone"} wants to move <span className="font-medium">{taskTitle(c.task_id)}</span>:{" "}
              {changeText(c, (id) => dir.person(id)?.name)}
              {c.reason && <> · &ldquo;{c.reason}&rdquo;</>}
            </span>
            {lead ? (
              <span className="flex gap-2">
                <Button size="sm" disabled={decide.isPending} onClick={() => decide.mutate({ id: c.id, action: "approve" })}>
                  Apply
                </Button>
                <Button size="sm" variant="ghost" disabled={decide.isPending} onClick={() => decide.mutate({ id: c.id, action: "reject" })}>
                  Reject
                </Button>
              </span>
            ) : (
              <span className="text-muted">Waiting for the lead</span>
            )}
          </div>
        ))}
      </div>
    </Card>
  );
}

/* Decisions (2.4, 2.18): decided today, earlier ones still standing, and ones a later decision replaced. */
function Decisions({ project }: { project: WorkProject }) {
  const all = useDecisions({ project_id: project.id }).data ?? [];
  const today = startOfToday();
  const active = all.filter((d) => d.status === "active");
  const groups = [
    { title: "Decided today", items: active.filter((d) => d.inserted_at >= today), empty: "No decisions today." },
    { title: "Earlier", items: active.filter((d) => d.inserted_at < today), empty: "" },
    { title: "Replaced", items: all.filter((d) => d.status === "superseded"), empty: "" },
  ];
  return (
    <div className="grid gap-5 lg:grid-cols-[1fr_1fr]">
      <Card>
        {groups.map(
          (g, i) =>
            (g.items.length > 0 || g.empty) && (
              <div key={g.title} className={i > 0 ? "mt-5" : ""}>
                <p className="mb-3 flex items-center gap-1.5 text-[14px] font-semibold">
                  {i === 0 && <GavelIcon size={16} className="text-accent-fg" />} {g.title} ({g.items.length})
                </p>
                <ul className="space-y-2.5">
                  {g.items.map((d) => (
                    <DecisionItem key={d.id} d={d} replacedBy={all.find((x) => x.id === d.superseded_by_id)} />
                  ))}
                  {g.items.length === 0 && <p className="text-[13px] text-muted">{g.empty}</p>}
                </ul>
              </div>
            ),
        )}
        <p className="mt-5 text-[12px] text-muted">Decisions come from chat. Noa proposes them in the Inbox, and they land here once approved.</p>
      </Card>
      <RecentChanges project={project} />
    </div>
  );
}

/* KT brief (3.2): what someone joining this project needs on day one, from the project's data, cited. */
function KT({ project }: { project: WorkProject }) {
  const dir = useDirectory();
  const me = dir.me;
  const brief = useQuery({ queryKey: ["brief", dir.orgId, project.id, me], queryFn: () => getBrief(dir.orgId!, project.id, me), enabled: !!dir.orgId });
  const [done, setDone] = useState<Record<string, boolean>>({});
  const sections = brief.data?.sections ?? [];
  const meet = sections.find((x) => x.title === "People to meet")?.items ?? [];
  const mine = sections.find((x) => x.title === "Your tasks")?.items ?? [];
  const checklist = [
    "Read the brief",
    ...meet.slice(0, 2).map((m) => `Meet ${m.text.split(" ")[0]}`),
    ...(mine[0] && !mine[0].text.startsWith("Nothing") ? [`Pick up ${mine[0].text.split(" · ")[0]}`] : []),
    "Day-7 check-in with the lead",
  ];

  return (
    <div className="grid gap-5 lg:grid-cols-[1.4fr_1fr]">
      <Card>
        <div className="mb-3 flex items-center justify-between gap-3">
          <p className="text-[14px] font-semibold">KT brief · for people joining {project.name}</p>
          <Button size="sm" variant="ghost" disabled={!brief.data} onClick={() => downloadBrief(dir.orgId!, project.id, me)}>
            Download brief.md
          </Button>
        </div>
        {brief.isLoading && <p className="text-[13px] text-muted">Putting the brief together…</p>}
        <div className="space-y-4">
          {sections.map((sec) => (
            <section key={sec.title}>
              <p className="mb-1.5 text-[12px] font-semibold text-muted">{sec.title}</p>
              <ul className="space-y-1.5">
                {sec.items.map((it, i) => (
                  <li key={i} className="flex items-start gap-2.5 rounded-xl bg-bg px-3 py-2.5">
                    <CheckCircleIcon size={16} weight="fill" className="mt-0.5 shrink-0 text-accent-fg" />
                    <div className="min-w-0 flex-1">
                      <p className="text-[13px]">{it.text}</p>
                      {it.source && (
                        <div className="mt-1">
                          <SourceChip source={toSource(it.source)} />
                        </div>
                      )}
                    </div>
                  </li>
                ))}
              </ul>
            </section>
          ))}
        </div>
      </Card>
      <Card className="h-fit">
        <p className="text-[14px] font-semibold">First week</p>
        <ul className="mt-3 space-y-2 text-[13px]">
          {checklist.map((c) => (
            <li key={c}>
              <button onClick={() => setDone((d) => ({ ...d, [c]: !d[c] }))} className="flex items-center gap-2 text-left">
                <span className={cn("grid size-4 place-items-center rounded-[5px]", done[c] ? "bg-accent text-white" : "ring-1 ring-line")}>
                  {done[c] && <CheckCircleIcon size={10} weight="bold" />}
                </span>
                <span className={cn(done[c] && "text-muted line-through")}>{c}</span>
              </button>
            </li>
          ))}
        </ul>
        <Link href="/ask" className="mt-4 block rounded-xl bg-mist/60 px-3 py-2.5 text-[12.5px] hover:bg-mist">
          Anything else? Ask <span className="font-medium text-accent-fg">@noa</span> about {project.name}. Answers cite their sources.
        </Link>
      </Card>
    </div>
  );
}
