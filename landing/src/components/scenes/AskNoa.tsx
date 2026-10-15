"use client";

import { AnimatePresence, motion } from "motion/react";
import { useLoop, useTyping } from "@/lib/useLoop";
import { Avatar, NoaAvatar, SourceChip, Window } from "../ui";

/* @noa answers with citations, scoped to what the asker can see. */

const Q = "@noa what's blocking the Emmarie demo?";
const PHASES = [900, Q.length * 38 + 400, 1300, 900, 900, 3000] as const;
const [TYPING, THINKING, ANSWER, CITES] = [1, 2, 3, 4];

const enter = {
  initial: { opacity: 0, y: 10 },
  animate: { opacity: 1, y: 0 },
  exit: { opacity: 0 },
  transition: { type: "spring" as const, stiffness: 320, damping: 30 },
};

export function AskNoa() {
  const { ref, step } = useLoop(PHASES);
  const draft = useTyping(Q, step === TYPING, 38);

  return (
    <div ref={ref} className="w-full">
      <Window title="Discord · #emmarie">
        <div className="flex h-[380px] flex-col justify-end gap-3 p-5">
          <div className="flex items-start gap-2.5">
            <Avatar initials="OJ" />
            <p className="pt-1 text-[13px] text-ink/80">motion-test queue timed out again on the project&apos;s Durable Object</p>
          </div>
          <AnimatePresence>
            {step >= THINKING && (
              <motion.div key="q" {...enter} className="flex items-start gap-2.5">
                <Avatar initials="AB" tone="accent" />
                <p className="pt-1 text-[13px]">
                  <span className="font-medium text-accent">@noa</span> what&apos;s blocking the Emmarie demo?
                </p>
              </motion.div>
            )}
            {step === THINKING && (
              <motion.div key="t" {...enter} className="flex items-center gap-2.5">
                <NoaAvatar />
                <span className="flex gap-1 rounded-2xl bg-bg px-3 py-2.5">
                  {[0, 1, 2].map((i) => (
                    <motion.span
                      key={i}
                      className="size-1.5 rounded-full bg-ink/40"
                      animate={{ opacity: [0.3, 1, 0.3] }}
                      transition={{ duration: 0.9, repeat: Infinity, delay: i * 0.15 }}
                    />
                  ))}
                </span>
              </motion.div>
            )}
            {step >= ANSWER && (
              <motion.div key="a" {...enter} className="flex items-start gap-2.5">
                <NoaAvatar />
                <div className="max-w-[88%] rounded-2xl rounded-tl-md bg-bg px-3.5 py-3 text-[13px] leading-relaxed">
                  <p>Two things, both before the Oct 30 demo:</p>
                  <ul className="mt-1.5 list-disc space-y-1 pl-4">
                    <li>
                      Motion tests time out on the project&apos;s Durable Object <span className="font-mono text-[11px] text-accent">[1]</span>
                    </li>
                    <li>
                      Coverage notes v2 waits on Soha, who joins Emmarie Monday <span className="font-mono text-[11px] text-accent">[2]</span>
                    </li>
                  </ul>
                  <p className="mt-1.5">Ojas knows the Workers side best. Want me to propose him for the queue fix?</p>
                  {step >= CITES && (
                    <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} className="mt-2.5 flex flex-wrap gap-1.5">
                      <SourceChip>[1] #emmarie · Tue 4:12 pm</SourceChip>
                      <SourceChip>[2] Staffing · Mon</SourceChip>
                    </motion.div>
                  )}
                </div>
              </motion.div>
            )}
          </AnimatePresence>
          <div className="mt-2 flex h-9 items-center rounded-full px-3.5 text-[13px] ring-1 ring-line">
            {draft ? <span>{draft}</span> : <span className="text-ink/40">Message #emmarie</span>}
          </div>
        </div>
      </Window>
    </div>
  );
}
