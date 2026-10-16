"use client";

import { BellRingingIcon, CheckIcon, GavelIcon } from "@phosphor-icons/react";
import { AnimatePresence, motion } from "motion/react";
import { useLoop } from "@/lib/useLoop";
import { SourceChip, Window } from "../ui";

/* "Decided today" fills in; a shared deadline edit goes to the editor's lead for approval. */

const DECISIONS = [
  { title: "Score all seven model families", src: "Discord #veriq · VE, OJ" },
  { title: "Board report before Practitioner", src: "Meet · weekly sync" },
  { title: "Hooks in the first two seconds", src: "WhatsApp · AB" },
];
const PHASES = [700, 700, 700, 1100, 1400, 1100, 900, 2400] as const;
const [EDIT, NOTIFY, APPROVE, DONE] = [3, 4, 5, 6];

export function DecisionsEdits() {
  const { ref, step } = useLoop(PHASES);
  const shown = Math.min(DECISIONS.length, step + 1);

  return (
    <div ref={ref} className="relative w-full">
      <Window title="NotYourIdea · Decisions" bar={<span className="text-[11px] text-muted">Today</span>}>
        <div className="grid h-[380px] gap-4 p-5 sm:grid-cols-2">
          <div>
            <p className="mb-2 flex items-center gap-1.5 text-[12px] font-semibold">
              <GavelIcon size={14} className="text-accent" /> Decided today ({shown})
            </p>
            <div className="space-y-2">
              <AnimatePresence>
                {DECISIONS.slice(0, shown).map((d) => (
                  <motion.div
                    key={d.title}
                    initial={{ opacity: 0, y: 10 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ duration: 0.45, ease: [0.22, 1, 0.36, 1] }}
                    className="rounded-2xl bg-bg p-3"
                  >
                    <p className="text-[12.5px] font-medium">{d.title}</p>
                    <SourceChip>{d.src}</SourceChip>
                  </motion.div>
                ))}
              </AnimatePresence>
            </div>
          </div>

          <div className={`rounded-2xl p-3.5 transition-colors duration-500 ${step >= EDIT ? "bg-mist/70" : "bg-bg"}`}>
            <p className="text-[12px] font-semibold">Edit shared item</p>
            <p className="mt-2 text-[11px] text-muted">Board report PDF · deadline</p>
            <p className="mt-1 text-[14px] font-semibold">
              Fri <span className="text-muted">→</span>{" "}
              <motion.span animate={{ color: step >= EDIT ? "#1B4F8A" : "#6B6B6B" }}>Mon</motion.span>
            </p>
            <p className="mt-2 text-[11px] text-muted">Reason</p>
            <p className="rounded-lg bg-surface px-2.5 py-1.5 text-[12px]">Waiting on the brand&apos;s logo pack</p>
            <div
              className={`mt-3 rounded-lg px-2.5 py-2 text-[11.5px] transition-colors ${
                step >= DONE ? "bg-good/10 text-good" : "bg-surface text-ink/75"
              }`}
            >
              {step >= DONE ? (
                <span className="flex items-center gap-1.5">
                  <CheckIcon size={12} weight="bold" /> Approved by Vedant · Saish notified
                </span>
              ) : (
                "Needs approval from Vedant, your lead"
              )}
            </div>
          </div>
        </div>
      </Window>

      <AnimatePresence>
        {step >= NOTIFY && step < DONE && (
          <motion.div
            initial={{ opacity: 0, y: -12, scale: 0.95 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: -8 }}
            transition={{ type: "spring", stiffness: 300, damping: 26 }}
            className="absolute -top-4 right-4 w-[270px] rounded-2xl bg-surface p-3.5 card-shadow"
          >
            <p className="flex items-center gap-1.5 text-[11px] font-medium text-muted">
              <BellRingingIcon size={13} className="text-signal" /> Noa · to Vedant
            </p>
            <p className="mt-1 text-[12.5px]">Saish wants to move Board report PDF to Monday.</p>
            <div className="mt-2.5 flex gap-2">
              <span
                className={`flex-1 rounded-full bg-accent py-1.5 text-center text-[11.5px] font-medium text-white transition-transform ${
                  step === APPROVE ? "scale-95 ring-4 ring-accent/20" : ""
                }`}
              >
                Approve
              </span>
              <span className="flex-1 rounded-full bg-bg py-1.5 text-center text-[11.5px] font-medium">Discuss</span>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
