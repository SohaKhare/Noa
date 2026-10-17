"use client";

import { DndContext, PointerSensor, useDraggable, useDroppable, useSensor, useSensors, type DragEndEvent } from "@dnd-kit/core";
import { ArrowRightIcon, CheckIcon } from "@phosphor-icons/react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { AnimatePresence, motion } from "motion/react";
import { useId, useState } from "react";
import { FormError } from "@/components/AuthCard";
import { Avatar, Button, PageHeader } from "@/components/ui";
import { ApiError, createShift, getShifts, planShift, type WorkPerson } from "@/lib/api";
import { cn } from "@/lib/cn";
import { ago, dueLabel, nameInitials, useDirectory } from "@/lib/work";

/*
  Staffing board (3.17, 3.1): one chip per person per project they work on; the bench
  holds people with no allocation. A lead drags someone to another project, checks the
  handover in the popover and confirms; the API moves the allocation and hands over
  their open tasks in one go.
*/

type Chip = { key: string; person: string; project: string; percent: number };
type Pending = { person: string; from: string; to: string; percent: number };

const BENCH = "bench";
const today = () => new Date().toISOString().slice(0, 10);

export default function People() {
  const dir = useDirectory();
  const client = useQueryClient();
  const me = dir.person(dir.me);
  const lead = me?.role === "org_admin" || me?.role === "pm";
  const [pending, setPending] = useState<Pending | null>(null);
  const dndId = useId();
  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 4 } }));
  const shifts = useQuery({ queryKey: ["shifts", dir.orgId], queryFn: () => getShifts(dir.orgId!), enabled: !!dir.orgId });

  const chips: Chip[] = dir.people.flatMap((p) =>
    p.allocations.length
      ? p.allocations.map((a) => ({ key: `${p.id}:${a.project_id}`, person: p.id, project: a.project_id, percent: a.percent }))
      : [{ key: `${p.id}:${BENCH}`, person: p.id, project: BENCH, percent: 0 }],
  );
  const lanes = [...dir.projects.map((p) => ({ id: p.id, name: p.name })), { id: BENCH, name: "Bench" }];
  const projectName = (id: string | null) => (id && id !== BENCH ? (dir.project(id)?.name ?? "?") : "the bench");

  const onDragEnd = (e: DragEndEvent) => {
    const to = e.over?.id as string | undefined;
    const chip = chips.find((c) => c.key === e.active.id);
    if (!to || !chip || chip.project === to) return;
    setPending({ person: chip.person, from: chip.project, to, percent: chip.percent || 100 });
  };

  return (
    <div className="mx-auto max-w-7xl">
      <PageHeader
        title="People · staffing board"
        sub={lead ? "Drag someone to another project. Noa hands over their open tasks and keeps routing questions to them for two weeks." : "Who works where. Admins and PMs move people from here."}
      />
      <DndContext id={dndId} sensors={sensors} onDragEnd={onDragEnd}>
        <div className="grid gap-3 md:grid-cols-3 xl:grid-cols-5">
          {lanes.map((l) => (
            <Lane key={l.id} id={l.id} name={l.name} chips={chips.filter((c) => c.project === l.id)} person={dir.person} draggable={lead} />
          ))}
        </div>
      </DndContext>

      {(shifts.data?.length ?? 0) > 0 && (
        <section className="mt-6">
          <p className="text-[13px] font-semibold">Recent moves</p>
          <ul className="mt-2 space-y-1">
            {shifts.data!.slice(0, 6).map((s) => (
              <li key={s.id} className="flex items-center gap-2 text-[12.5px] text-muted">
                <CheckIcon size={12} className="text-good" />
                {dir.person(s.person_id)?.name} moved from {projectName(s.from_project_id)} to {projectName(s.to_project_id)}
                {s.handover.length > 0 && ` · ${s.handover.length} ${s.handover.length === 1 ? "task" : "tasks"} handed over`} · {ago(s.inserted_at)}
              </li>
            ))}
          </ul>
        </section>
      )}

      <AnimatePresence>
        {pending && (
          <ShiftPopover
            key={`${pending.person}:${pending.to}`}
            pending={pending}
            projectName={projectName}
            onClose={() => setPending(null)}
            onDone={() => {
              setPending(null);
              for (const key of ["directory", "tasks", "changes", "shifts"]) client.invalidateQueries({ queryKey: [key, dir.orgId] });
            }}
          />
        )}
      </AnimatePresence>
    </div>
  );
}

function ShiftPopover({
  pending,
  projectName,
  onClose,
  onDone,
}: {
  pending: Pending;
  projectName: (id: string | null) => string;
  onClose: () => void;
  onDone: () => void;
}) {
  const dir = useDirectory();
  const person = dir.person(pending.person);
  const from = pending.from === BENCH ? null : pending.from;
  const to = pending.to === BENCH ? null : pending.to;
  const plan = useQuery({ queryKey: ["shift-plan", pending.person, from], queryFn: () => planShift(dir.orgId!, pending.person, from) });
  const [owners, setOwners] = useState<Record<string, string>>({});
  const [startsOn, setStartsOn] = useState(today);
  const [percent, setPercent] = useState(pending.percent);
  const ownerOf = (taskId: string, suggested: string | null) => owners[taskId] ?? suggested ?? "";
  const others = dir.people.filter((p) => p.id !== pending.person);

  const move = useMutation({
    mutationFn: () =>
      createShift(dir.orgId!, {
        person_id: pending.person,
        from_project_id: from,
        to_project_id: to,
        percent,
        starts_on: startsOn,
        handover: Object.fromEntries((plan.data ?? []).map((t) => [t.task_id, ownerOf(t.task_id, t.to_owner_id)])),
      }),
    onSuccess: onDone,
  });

  return (
    <motion.div
      className="fixed inset-0 z-50 grid place-items-center bg-ink/20 p-4 backdrop-blur-[2px]"
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      onClick={onClose}
    >
      <motion.div
        role="dialog"
        aria-modal
        aria-labelledby="move-title"
        initial={{ y: 16, scale: 0.97 }}
        animate={{ y: 0, scale: 1 }}
        exit={{ y: 8, opacity: 0 }}
        transition={{ type: "spring", stiffness: 320, damping: 28 }}
        onClick={(e) => e.stopPropagation()}
        className="w-full max-w-md rounded-[22px] bg-surface p-5 card-shadow"
      >
        <p id="move-title" className="flex items-center gap-2 text-[16px] font-semibold">
          Move {person?.name}
        </p>
        <p className="mt-0.5 flex items-center gap-1.5 text-[13px] text-muted">
          {projectName(pending.from)} <ArrowRightIcon size={12} /> {projectName(pending.to)}
        </p>

        <div className="mt-4 grid grid-cols-2 gap-3">
          <label className="block text-[11.5px] text-muted">
            Starts
            <input type="date" value={startsOn} onChange={(e) => setStartsOn(e.target.value)} className="mt-1 w-full rounded-xl bg-bg px-3 py-2 text-[13px] text-ink focus:outline-none" />
          </label>
          {to && (
            <label className="block text-[11.5px] text-muted">
              Allocation
              <span className="mt-1 flex items-center rounded-xl bg-bg px-3 py-2 text-[13px] text-ink">
                <input
                  type="number"
                  min={5}
                  max={100}
                  step={5}
                  value={percent}
                  onChange={(e) => setPercent(Number(e.target.value))}
                  className="w-full bg-transparent focus:outline-none"
                  aria-label="Allocation percent"
                />
                %
              </span>
            </label>
          )}
        </div>

        {from && (
          <section className="mt-4">
            <p className="text-[12px] font-semibold">Hand over their open {projectName(pending.from)} tasks</p>
            {plan.isLoading && <p className="mt-2 text-[12.5px] text-muted">Checking their tasks…</p>}
            {plan.data?.length === 0 && <p className="mt-2 text-[12.5px] text-muted">Nothing open. Nothing to hand over.</p>}
            <ul className="mt-2 space-y-2">
              {plan.data?.map((t) => (
                <li key={t.task_id} className="flex items-center gap-2 rounded-xl bg-bg px-3 py-2">
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-[13px] font-medium">{t.title}</span>
                    {t.due_on && <span className="text-[11px] text-muted">due {dueLabel(t.due_on)}</span>}
                  </span>
                  <select
                    value={ownerOf(t.task_id, t.to_owner_id)}
                    onChange={(e) => setOwners((o) => ({ ...o, [t.task_id]: e.target.value }))}
                    aria-label={`New owner for ${t.title}`}
                    className="rounded-lg bg-surface px-2 py-1 text-[12.5px] ring-1 ring-line focus:outline-none"
                  >
                    <option value="">Unassigned</option>
                    {others.map((p) => (
                      <option key={p.id} value={p.id}>
                        {p.name}
                        {p.id === t.to_owner_id ? " (suggested)" : ""}
                      </option>
                    ))}
                  </select>
                </li>
              ))}
            </ul>
          </section>
        )}

        <ul className="mt-4 space-y-1.5 text-[12.5px] text-muted">
          {from && (
            <li className="flex gap-2">
              <CheckIcon size={13} className="mt-0.5 text-good" /> Questions about {projectName(pending.from)} still go to {person?.name} for two weeks
            </li>
          )}
          <li className="flex gap-2">
            <CheckIcon size={13} className="mt-0.5 text-good" /> Every handover is recorded on the task and can be reverted
          </li>
        </ul>

        {move.error && (
          <div className="mt-3">
            <FormError>{(move.error as ApiError).message}</FormError>
          </div>
        )}
        <div className="mt-5 flex justify-end gap-2">
          <Button variant="ghost" size="sm" onClick={onClose}>
            Cancel
          </Button>
          <Button size="sm" disabled={move.isPending || plan.isLoading} onClick={() => move.mutate()}>
            {move.isPending ? "Moving…" : `Move ${person?.name}`}
          </Button>
        </div>
      </motion.div>
    </motion.div>
  );
}

function Lane({
  id,
  name,
  chips,
  person,
  draggable,
}: {
  id: string;
  name: string;
  chips: Chip[];
  person: (id: string) => WorkPerson | undefined;
  draggable: boolean;
}) {
  const { setNodeRef, isOver } = useDroppable({ id });
  return (
    <div ref={setNodeRef} className={cn("min-h-[360px] rounded-2xl p-2.5 transition-colors", isOver ? "bg-mist ring-2 ring-accent/30" : "bg-surface/70")}>
      <p className="mb-2 px-1 text-[12px] font-semibold">
        {name} <span className="font-normal text-muted">· {chips.length}</span>
      </p>
      <div className="space-y-2">
        {chips.map((c) => (
          <PersonChip key={c.key} chip={c} p={person(c.person)} draggable={draggable} />
        ))}
      </div>
    </div>
  );
}

function PersonChip({ chip, p, draggable }: { chip: Chip; p?: WorkPerson; draggable: boolean }) {
  const { attributes, listeners, setNodeRef, transform, isDragging } = useDraggable({ id: chip.key, disabled: !draggable });
  if (!p) return null;
  return (
    <div
      ref={setNodeRef}
      {...listeners}
      {...attributes}
      style={transform ? { transform: `translate(${transform.x}px, ${transform.y}px) rotate(-2deg)` } : undefined}
      className={cn(
        "flex items-center gap-2.5 rounded-xl bg-surface p-2.5 ring-1 ring-line/80",
        draggable && "cursor-grab active:cursor-grabbing",
        isDragging && "z-10 shadow-xl ring-accent/30",
      )}
    >
      <Avatar initials={nameInitials(p.name)} size={26} />
      <div className="leading-tight">
        <p className="text-[13px] font-medium">{p.name}</p>
        <p className="text-[11px] text-muted">
          {p.title}
          {chip.percent ? ` · ${chip.percent}%` : ""}
        </p>
      </div>
    </div>
  );
}
