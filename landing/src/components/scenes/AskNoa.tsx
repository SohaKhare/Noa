"use client";

import { HashIcon } from "@phosphor-icons/react";
import { AnimatePresence, motion } from "motion/react";
import { useLoop, useTyping } from "@/lib/useLoop";
import { LiveDot } from "../ui";

/* @noa answers in Discord, with citations, scoped to what the asker can see. */

const Q = "@noa what's blocking the Emmarie demo?";
const PHASES = [900, Q.length * 38 + 400, 1300, 900, 900, 3000] as const;
const [TYPING, THINKING, ANSWER, CITES] = [1, 2, 3, 4];

const enter = {
  initial: { opacity: 0, y: 10 },
  animate: { opacity: 1, y: 0 },
  exit: { opacity: 0 },
  transition: { type: "spring" as const, stiffness: 320, damping: 30 },
};

const roles = {
  OJ: { initials: "OJ", color: "#5865f2", name: "Ojas" },
  AB: { initials: "AB", color: "#eb459e", name: "Abhishek" },
  NOA: { initials: "N", color: "#5865f2", name: "Noa" },
} as const;

export function AskNoa() {
  const { ref, step } = useLoop(PHASES);
  const draft = useTyping(Q, step === TYPING, 38);

  return (
    <div ref={ref} className="w-full">
      <div className="flex overflow-hidden rounded-[22px] bg-[#313338] text-[#dbdee1] shadow-[0_18px_50px_-24px_rgba(8,16,32,0.7)]">
        <div className="flex w-[52px] shrink-0 flex-col items-center gap-2 bg-[#1e1f22] py-3">
          <span className="grid size-9 place-items-center rounded-2xl bg-[#5865f2] text-[12px] font-semibold text-white">N</span>
          <span className="h-px w-6 bg-white/10" />
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex h-11 items-center gap-2 border-b border-black/30 px-4">
            <HashIcon size={16} className="text-[#949ba4]" />
            <span className="text-[14px] font-semibold text-white">emmarie</span>
            <span className="ml-auto flex items-center gap-1.5 text-[11px] text-[#949ba4]">
              <LiveDot /> Noa is listening
            </span>
          </div>
          <div className="flex h-[380px] flex-col justify-end gap-3.5 px-4 py-3">
            <DiscordLine who="OJ" time="4:02" text="motion-test queue timed out again on the project's Durable Object" />
            <AnimatePresence>
              {step >= THINKING && (
                <motion.div key="q" {...enter}>
                  <DiscordLine who="AB" time="4:11" text={Q} mention />
                </motion.div>
              )}
              {step === THINKING && (
                <motion.div key="t" {...enter} className="flex items-center gap-3 px-2">
                  <Mark who="NOA" />
                  <span className="flex gap-1">
                    {[0, 1, 2].map((i) => (
                      <motion.span
                        key={i}
                        className="size-1.5 rounded-full bg-[#949ba4]"
                        animate={{ opacity: [0.3, 1, 0.3] }}
                        transition={{ duration: 0.9, repeat: Infinity, delay: i * 0.15 }}
                      />
                    ))}
                  </span>
                </motion.div>
              )}
              {step >= ANSWER && (
                <motion.div key="a" {...enter}>
                  <div className="-mx-2 flex items-start gap-3 rounded px-2 py-0.5">
                    <Mark who="NOA" />
                    <div className="min-w-0 text-[14px] leading-snug">
                      <p className="leading-none">
                        <span className="font-medium text-[#5865f2]">Noa</span>
                        <span className="ml-1.5 rounded bg-[#5865f2] px-1 py-px align-middle text-[9px] font-bold tracking-wide text-white">BOT</span>
                        <span className="ml-2 text-[11px] text-[#949ba4]">4:11</span>
                      </p>
                      <div className="mt-1.5">
                        <p>Two things, both before the Oct 30 demo:</p>
                        <ul className="mt-1.5 list-disc space-y-1 pl-4">
                          <li>
                            Motion tests time out on the project&apos;s Durable Object <Cite n={1} />
                          </li>
                          <li>
                            Coverage notes v2 waits on Soha, who joins Emmarie Monday <Cite n={2} />
                          </li>
                        </ul>
                        <p className="mt-1.5">Ojas knows the Workers side best. Want me to propose him for the queue fix?</p>
                        {step >= CITES && (
                          <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} className="mt-2.5 flex flex-wrap gap-1.5">
                            <span className="rounded bg-[#2b2d31] px-2 py-0.5 text-[11px] text-[#00a8fc]">[1] #emmarie · Tue 4:12 pm</span>
                            <span className="rounded bg-[#2b2d31] px-2 py-0.5 text-[11px] text-[#00a8fc]">[2] Staffing · Mon</span>
                          </motion.div>
                        )}
                      </div>
                    </div>
                  </div>
                </motion.div>
              )}
            </AnimatePresence>
            <div className="mt-1 flex h-11 items-center rounded-lg bg-[#383a40] px-4 text-[14px]">
              {draft ? (
                <span className="text-[#dbdee1]">
                  {draft}
                  <span className="ml-px inline-block h-4 w-px animate-pulse bg-white align-middle" />
                </span>
              ) : (
                <span className="text-[#949ba4]">Message #emmarie</span>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function DiscordLine({ who, time, text, mention = false }: { who: keyof typeof roles; time: string; text: string; mention?: boolean }) {
  const role = roles[who];
  return (
    <div className="-mx-2 flex items-start gap-3 rounded px-2 py-0.5">
      <Mark who={who} />
      <div className="min-w-0">
        <p className="text-[14px] leading-none">
          <span className="font-medium" style={{ color: role.color }}>
            {role.name}
          </span>
          <span className="ml-2 text-[11px] text-[#949ba4]">{time}</span>
        </p>
        <p className="mt-1 text-[14px] leading-snug text-[#dbdee1]">
          {mention ? (
            <>
              <span className="rounded bg-[#5865f2]/30 px-0.5 font-medium text-[#c9cdfb]">@noa</span>
              {text.replace("@noa", "")}
            </>
          ) : (
            text
          )}
        </p>
      </div>
    </div>
  );
}

function Mark({ who }: { who: keyof typeof roles }) {
  const role = roles[who];
  return (
    <span
      className="grid size-9 shrink-0 place-items-center rounded-full text-[11px] font-semibold text-white"
      style={{ backgroundColor: role.color }}
    >
      {role.initials}
    </span>
  );
}

function Cite({ n }: { n: number }) {
  return <span className="font-medium text-[#00a8fc]">[{n}]</span>;
}
