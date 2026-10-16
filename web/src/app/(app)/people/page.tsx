"use client";

import { DndContext, PointerSensor, useDraggable, useDroppable, useSensor, useSensors, type DragEndEvent } from "@dnd-kit/core";
import { CheckIcon } from "@phosphor-icons/react";
import { AnimatePresence, motion } from "motion/react";
import { useId, useState } from "react";
import { Avatar, Button, PageHeader } from "@/components/ui";
import { cn } from "@/lib/cn";
import { allocations as seed, person, project, projects, type Allocation } from "@/lib/mock";

type Pending = { person: string; from: string; to: string };

const steps = (p: Pending) => [
  `Hand over open tasks in ${project(p.from)?.name ?? "bench"}`,
  `Send agent pack to ${person(p.person)?.name}`,
  `Grant repo, channels and Drive for ${project(p.to)?.name}`,
  `Issue ${project(p.to)?.name} secrets (one-time link, 24h)`,
  `Revoke ${project(p.from)?.name ?? "old"} secrets`,
];

export default function People() {
  const [allocs, setAllocs] = useState<Allocation[]>(seed);
  const [pending, setPending] = useState<Pending | null>(null);
  const [checked, setChecked] = useState<boolean[]>([]);
  const [log, setLog] = useState<string[]>([]);
  const dndId = useId();
  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 4 } }));

  const onDragEnd = (e: DragEndEvent) => {
    const to = e.over?.id as string | undefined;
    const a = allocs.find((x) => x.person === e.active.id);
    if (!to || !a || a.project === to) return;
    setPending({ person: a.person, from: a.project, to });
    setChecked([true, true, true, true, true]);
  };

  const confirm = () => {
    if (!pending) return;
    setAllocs((xs) => xs.map((x) => (x.person === pending.person ? { ...x, project: pending.to, from: "Mon" } : x)));
    setLog((l) => [`${person(pending.person)?.name} moves to ${project(pending.to)?.name ?? "Bench"} from Monday · pack sent`, ...l]);
    setPending(null);
  };

  const lanes = [...projects.map((p) => ({ id: p.id, name: p.name })), { id: "bench", name: "Bench" }];

  return (
    <div className="mx-auto max-w-7xl">
      <PageHeader title="People · staffing board" sub="Drag someone to another project. Noa handles the handover, access and their agent pack." />
      <DndContext id={dndId} sensors={sensors} onDragEnd={onDragEnd}>
        <div className="grid gap-3 md:grid-cols-3 xl:grid-cols-5">
          {lanes.map((l) => (
            <Lane key={l.id} id={l.id} name={l.name} people={allocs.filter((a) => a.project === l.id)} />
          ))}
        </div>
      </DndContext>

      {log.length > 0 && (
        <ul className="mt-5 space-y-1">
          {log.map((l) => (
            <li key={l} className="flex items-center gap-2 text-[12.5px] text-muted">
              <CheckIcon size={12} className="text-good" /> {l}
            </li>
          ))}
        </ul>
      )}

      <AnimatePresence>
        {pending && (
          <motion.div
            className="fixed inset-0 z-50 grid place-items-center bg-ink/20 p-4 backdrop-blur-[2px]"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={() => setPending(null)}
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
              className="w-full max-w-sm rounded-[22px] bg-surface p-5 card-shadow"
            >
              <p id="move-title" className="text-[16px] font-semibold">
                Move {person(pending.person)?.name} to {project(pending.to)?.name ?? "Bench"}
              </p>
              <p className="text-[12.5px] text-muted">Starts Monday · 100% allocation · lead and person are notified</p>
              <ul className="mt-4 space-y-2.5">
                {steps(pending).map((s, i) => (
                  <li key={s}>
                    <label className="flex cursor-pointer items-center gap-2.5 text-[13px]">
                      <input
                        type="checkbox"
                        checked={checked[i] ?? false}
                        onChange={() => setChecked((c) => c.map((v, j) => (j === i ? !v : v)))}
                        className="size-4 accent-[#1E3A2F]"
                      />
                      {s}
                    </label>
                  </li>
                ))}
              </ul>
              <div className="mt-5 flex justify-end gap-2">
                <Button variant="ghost" size="sm">
                  Full wizard
                </Button>
                <Button size="sm" onClick={confirm}>
                  Confirm
                </Button>
              </div>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

function Lane({ id, name, people }: { id: string; name: string; people: Allocation[] }) {
  const { setNodeRef, isOver } = useDroppable({ id });
  return (
    <div ref={setNodeRef} className={cn("min-h-[360px] rounded-2xl p-2.5 transition-colors", isOver ? "bg-mist ring-2 ring-accent/30" : "bg-surface/70")}>
      <p className="mb-2 px-1 text-[12px] font-semibold">
        {name} <span className="font-normal text-muted">· {people.length}</span>
      </p>
      <div className="space-y-2">
        {people.map((a) => (
          <PersonChip key={a.person} a={a} />
        ))}
      </div>
    </div>
  );
}

function PersonChip({ a }: { a: Allocation }) {
  const { attributes, listeners, setNodeRef, transform, isDragging } = useDraggable({ id: a.person });
  const p = person(a.person)!;
  return (
    <div
      ref={setNodeRef}
      {...listeners}
      {...attributes}
      style={transform ? { transform: `translate(${transform.x}px, ${transform.y}px) rotate(-2deg)` } : undefined}
      className={cn(
        "flex cursor-grab items-center gap-2.5 rounded-xl bg-surface p-2.5 ring-1 ring-line/80 active:cursor-grabbing",
        isDragging && "z-10 shadow-xl ring-accent/30",
      )}
    >
      <Avatar initials={p.initials} size={26} />
      <div className="leading-tight">
        <p className="text-[13px] font-medium">{p.name}</p>
        <p className="text-[11px] text-muted">
          {p.title}
          {a.percent ? ` · ${a.percent}%` : ""}
          {a.from ? ` · from ${a.from}` : ""}
        </p>
      </div>
    </div>
  );
}
