"use client";

import { CheckIcon, FileTextIcon } from "@phosphor-icons/react";
import { AnimatePresence, LayoutGroup, motion } from "motion/react";
import { useLoop, useTyping } from "@/lib/useLoop";
import { Window } from "../ui";

/*
  Prathamesh drags Soha from Video Break to Emmarie, confirms the popover,
  and Soha's agent receives a pack (CLAUDE.md) written from the Emmarie project.
*/

const CHECKS = ["Hand over 3 open tasks", "Send agent pack to Soha", "Grant repo, #emmarie, Drive", "Issue Emmarie secrets (24h link)"];
const FILE = `# Emmarie: film workspace
pnpm workspace · Hono Worker + Durable Objects

## Decisions and why
- Event log is the source of truth (Tue, #emmarie)
- Storyboard before motion test (weekly sync)

## Your tasks
- [ ] Coverage notes v2 (from Saish)

## Ask
- Workers: Ojas · Design: Saish`;

const names: Record<string, string> = { PR: "Prathamesh", OJ: "Ojas", AB: "Abhishek", VE: "Vedant", SA: "Saish", SO: "Soha" };

const PHASES = [1200, 900, 700, 650, 650, 650, 650, 900, FILE.length * 14 + 900, 2200] as const;
const [DRAG, DROPPED, C1, C4, SENT, PACK] = [1, 2, 3, 6, 7, 8];

const spring = { type: "spring" as const, stiffness: 260, damping: 28 };

export function DropIntoProject() {
  const { ref, step } = useLoop(PHASES);
  const moved = step >= DROPPED;
  const checked = Math.max(0, Math.min(CHECKS.length, step - C1 + 1));
  const showPopover = step >= DROPPED && step < PACK;
  const showPack = step >= SENT;
  const typed = useTyping(FILE, step >= PACK, 14);

  return (
    <div ref={ref} className="relative w-full">
      <Window title="People · staffing board">
        <div className="grid h-[380px] grid-cols-3 gap-3 p-4">
          <LayoutGroup>
            <Lane name="Video Break" count={moved ? 1 : 2}>
              <Person i="AB" role="Content · 50%" />
              {!moved && <Person i="SO" role="Research · 100%" id="soha" dragging={step === DRAG} />}
            </Lane>
            <Lane name="Emmarie" count={moved ? 3 : 2} highlight={step === DRAG}>
              <Person i="OJ" role="Tech lead · 60%" />
              <Person i="SA" role="Design · 50%" />
              {moved && <Person i="SO" role="Intern · from Mon" id="soha" fresh />}
            </Lane>
            <Lane name="Veriq" count={2}>
              <Person i="PR" role="Lead · 50%" />
              <Person i="VE" role="SWE · 100%" />
            </Lane>
          </LayoutGroup>
        </div>
      </Window>

      <AnimatePresence>
        {showPopover && (
          <motion.div
            key="popover"
            initial={{ opacity: 0, y: 12, scale: 0.96 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 8 }}
            transition={spring}
            className="absolute top-14 right-4 w-[250px] rounded-2xl bg-surface p-4 card-shadow sm:right-6"
          >
            <p className="text-[13px] font-semibold">Move Soha to Emmarie</p>
            <p className="text-[11px] text-muted">Starts Monday · 100%</p>
            <ul className="mt-3 space-y-2">
              {CHECKS.map((c, i) => (
                <li key={c} className="flex items-center gap-2 text-[12px]">
                  <span
                    className={`grid size-4 place-items-center rounded-[5px] transition-colors duration-300 ${
                      i < checked ? "bg-accent text-white" : "ring-1 ring-line"
                    }`}
                  >
                    {i < checked && <CheckIcon size={10} weight="bold" />}
                  </span>
                  {c}
                </li>
              ))}
            </ul>
            <span
              className={`mt-4 block rounded-full py-2 text-center text-[12px] font-medium text-white transition-colors ${
                step >= C4 ? "bg-accent" : "bg-accent/40"
              }`}
            >
              Confirm
            </span>
          </motion.div>
        )}
        {showPack && (
          <motion.div
            key="pack"
            initial={{ opacity: 0, y: 24, scale: 0.96 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 10 }}
            transition={spring}
            className="absolute -bottom-4 left-4 w-[min(320px,88%)] overflow-hidden rounded-2xl bg-deep text-white card-shadow"
          >
            <div className="flex items-center gap-2 border-b border-white/10 px-4 py-2.5 text-[12px]">
              <FileTextIcon size={14} /> CLAUDE.md
              <span className="ml-auto rounded-full bg-white/15 px-2 py-0.5 text-[10.5px]">for Soha</span>
            </div>
            <pre className="h-[170px] overflow-hidden px-4 py-3 font-mono text-[11px] leading-[1.55] whitespace-pre-wrap text-white/90">
              {typed || " "}
            </pre>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

function Lane({ name, count, highlight = false, children }: { name: string; count: number; highlight?: boolean; children: React.ReactNode }) {
  return (
    <div className={`flex flex-col gap-2 rounded-2xl p-2.5 transition-colors duration-300 ${highlight ? "bg-mist ring-2 ring-accent/25" : "bg-bg"}`}>
      <p className="px-1 text-[11px] font-semibold text-muted">
        {name} · {count}
      </p>
      {children}
    </div>
  );
}

function Person({ i, role, id, dragging = false, fresh = false }: { i: string; role: string; id?: string; dragging?: boolean; fresh?: boolean }) {
  return (
    <motion.div
      layoutId={id}
      transition={{ type: "spring", stiffness: 200, damping: 26 }}
      animate={dragging ? { rotate: -3, scale: 1.05, x: 24 } : { rotate: 0, scale: 1, x: 0 }}
      className={`flex items-center gap-2 rounded-xl bg-surface p-2 ${
        fresh ? "ring-2 ring-signal/50" : dragging ? "shadow-lg ring-1 ring-accent/30" : "ring-1 ring-line/80"
      }`}
    >
      <span className="grid size-6 place-items-center rounded-full bg-mist text-[9.5px] font-semibold text-accent">{i}</span>
      <span className="min-w-0">
        <span className="block text-[11.5px] font-medium">{names[i] ?? i}</span>
        <span className="block truncate text-[10px] text-muted">{role}</span>
      </span>
    </motion.div>
  );
}
