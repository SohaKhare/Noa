"use client";

import { BookOpenTextIcon, CheckCircleIcon, WhatsappLogoIcon } from "@phosphor-icons/react";
import { AnimatePresence, motion } from "motion/react";
import { useLoop } from "@/lib/useLoop";
import { SourceChip, Window } from "../ui";

/* A KT brief assembling itself from the project's history, then delivered on WhatsApp. */

const LINES = [
  { title: "Purpose", body: "Writing-first film workspace; screenplay to final take. Demo Oct 30", src: "Project" },
  { title: "Open work", body: "9 tasks, 1 blocked on the motion-test queue", src: "Board" },
  { title: "Key decisions", body: "Event log is the source of truth; storyboard before motion test", src: "#emmarie, weekly sync" },
  { title: "People to meet", body: "Ojas (Workers), Saish (design), Vedant (lead)", src: "Recent work" },
  { title: "Read first", body: "architecture.md, docs/explainers", src: "Repo" },
];
const PHASES = [900, 700, 700, 700, 700, 700, 1300, 2600] as const;

export function KTBrief() {
  const { ref, step } = useLoop(PHASES);
  const shown = Math.min(LINES.length, step + 1);
  const delivered = step >= 6;

  return (
    <div ref={ref} className="relative w-full">
      <Window title="KT brief · Emmarie" bar={<span className="text-[11px] text-muted">for Soha · 6 min read</span>}>
        <div className="h-[380px] space-y-2.5 p-5">
          <AnimatePresence>
            {LINES.slice(0, shown).map((l) => (
              <motion.div
                key={l.title}
                initial={{ opacity: 0, x: -12, filter: "blur(6px)" }}
                animate={{ opacity: 1, x: 0, filter: "blur(0px)" }}
                transition={{ duration: 0.5, ease: [0.22, 1, 0.36, 1] }}
                className="flex items-start gap-3 rounded-2xl bg-bg p-3"
              >
                <CheckCircleIcon size={18} weight="fill" className="mt-0.5 shrink-0 text-accent" />
                <div className="min-w-0 flex-1">
                  <p className="text-[12px] font-semibold">{l.title}</p>
                  <p className="text-[12.5px] text-ink/75">{l.body}</p>
                </div>
                <SourceChip>{l.src}</SourceChip>
              </motion.div>
            ))}
          </AnimatePresence>
          {shown === 0 && (
            <p className="flex h-full items-center justify-center gap-2 text-[12px] text-muted">
              <BookOpenTextIcon size={16} /> Reading the project&apos;s history…
            </p>
          )}
        </div>
      </Window>
      <AnimatePresence>
        {delivered && (
          <motion.div
            initial={{ opacity: 0, y: 16, scale: 0.95 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0 }}
            transition={{ type: "spring", stiffness: 300, damping: 28 }}
            className="glass absolute right-3 -bottom-5 flex w-[260px] items-center gap-3 rounded-2xl p-3 card-shadow"
          >
            <span className="grid size-9 place-items-center rounded-full bg-[#25D366] text-white">
              <WhatsappLogoIcon size={18} weight="fill" />
            </span>
            <div className="text-[12px]">
              <p className="font-semibold">Noa · WhatsApp</p>
              <p className="text-ink/70">Soha, your Emmarie brief is ready. Ojas is free at 4 for a walkthrough.</p>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
