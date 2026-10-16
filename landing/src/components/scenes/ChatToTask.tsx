"use client";

import { CheckIcon, HashIcon, LightningIcon, WhatsappLogoIcon } from "@phosphor-icons/react";
import { AnimatePresence, LayoutGroup, motion } from "motion/react";
import { useLoop, useTyping } from "@/lib/useLoop";
import { Avatar, LiveDot, NoaAvatar, SourceChip, Window } from "../ui";

/*
  The whole loop, with NYI's real team: Vedant (the lead) asks in #veriq, Saish replies,
  Noa pops a proposal, Vedant approves, the card lands on the Veriq board,
  and Saish gets a WhatsApp from Noa.
*/

const REPLY = "on it, Board report PDF export by Friday";
const PHASES = [1400, REPLY.length * 42 + 500, 1300, 2200, 500, 1700, 3000, 900] as const;
const [TYPING, HEARD, PROPOSED, APPROVING, LANDED, PINGED] = [1, 2, 3, 4, 5, 6];

const spring = { type: "spring" as const, stiffness: 320, damping: 32 };
const enter = {
  initial: { opacity: 0, y: 10, scale: 0.97 },
  animate: { opacity: 1, y: 0, scale: 1 },
  exit: { opacity: 0, transition: { duration: 0.18 } },
  transition: spring,
};

export function ChatToTask() {
  const { ref, step } = useLoop(PHASES);
  const draft = useTyping(REPLY, step === TYPING, 42);
  const sent = step >= HEARD;
  const proposed = step >= PROPOSED;
  const landed = step >= LANDED;
  const pinged = step >= PINGED;

  return (
    <div ref={ref} className="relative grid w-full gap-3 md:grid-cols-[1fr_1.15fr]">
      <LayoutGroup>
        <Window title="Discord · NotYourIdea" bar={<span className="text-[11px] text-muted">#veriq</span>}>
          <div className="flex h-[360px] flex-col">
            <div className="flex items-center gap-1.5 border-b border-line/70 px-4 py-2.5 text-[13px] font-medium">
              <HashIcon size={14} className="text-muted" /> veriq
              <span className="ml-auto flex items-center gap-1.5 text-[11px] font-normal text-muted">
                <LiveDot /> Noa is listening
              </span>
            </div>
            <div className="flex flex-1 flex-col justify-end gap-3 p-4">
              <Message who="OJ" name="Ojas" time="10:31" text="AI Overview lane is green again 🎉" />
              <Message who="VE" name="Vedant" time="10:40" tone="accent" text="who can take the Board report PDF export? client wants it this week" />
              <AnimatePresence>
                {sent && (
                  <motion.div key="reply" {...enter}>
                    <Message who="SA" name="Saish" time="10:42" text={REPLY} highlight={step >= HEARD && step < LANDED} />
                  </motion.div>
                )}
                {landed && (
                  <motion.div key="noa" {...enter} className="flex items-start gap-2.5">
                    <NoaAvatar />
                    <div className="rounded-2xl rounded-tl-md bg-bg px-3 py-2 text-[12.5px]">
                      <span className="font-medium">Added to Veriq</span> · Saish · due Fri.{" "}
                      <span className="text-accent underline decoration-accent/30">Undo</span>
                    </div>
                  </motion.div>
                )}
              </AnimatePresence>
            </div>
            <div className="border-t border-line/70 p-3">
              <div className="flex h-9 items-center rounded-full px-3.5 text-[13px] ring-1 ring-line">
                {draft ? (
                  <span>
                    {draft}
                    <span className="ml-px inline-block h-4 w-px animate-pulse bg-accent align-middle" />
                  </span>
                ) : (
                  <span className="text-ink/40">Message #veriq</span>
                )}
              </div>
            </div>
          </div>
        </Window>

        <Window title="Noa · Veriq" bar={<span className="text-[11px] text-muted">Inbox · Board</span>}>
          <div className="grid h-[360px] grid-rows-[auto_1fr]">
            <div className="border-b border-line/70 p-4">
              <p className="mb-2 flex items-center gap-1.5 text-[11px] font-medium text-muted">
                <LightningIcon size={12} weight="fill" className="text-signal" /> Inbox
              </p>
              <div className="min-h-[76px]">
                <AnimatePresence mode="popLayout">
                  {proposed && !landed ? (
                    <motion.div key="proposal" layoutId="task-card" {...enter} className="flex items-center gap-3 rounded-2xl bg-bg p-3">
                      <span className="rounded-full bg-mist px-2 py-0.5 text-[10.5px] font-medium text-accent">New task</span>
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-[13px] font-medium">Board report PDF export · Saish · Fri</p>
                        <SourceChip>#veriq · &ldquo;on it, Board report…&rdquo;</SourceChip>
                      </div>
                      <span
                        className={`rounded-full bg-accent px-3 py-1.5 text-[12px] font-medium text-white transition-transform ${
                          step === APPROVING ? "scale-95 ring-4 ring-accent/20" : ""
                        }`}
                      >
                        Approve
                      </span>
                    </motion.div>
                  ) : step < PROPOSED ? (
                    <motion.div key="waiting" initial={{ opacity: 0 }} animate={{ opacity: 1 }} className="flex items-center gap-3 rounded-2xl bg-bg p-3">
                      <span className="rounded-full bg-mist px-2 py-0.5 text-[10.5px] font-medium text-accent">Due today</span>
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-[13px] font-medium">Prompt plan review · Soha</p>
                        <SourceChip>#veriq · this morning</SourceChip>
                      </div>
                    </motion.div>
                  ) : (
                    <motion.p key="empty" initial={{ opacity: 0 }} animate={{ opacity: 1 }} className="pt-5 text-center text-[12px] text-muted">
                      All caught up
                    </motion.p>
                  )}
                </AnimatePresence>
              </div>
            </div>
            <div className="grid grid-cols-3 gap-2.5 p-4">
              <Column name="To do">
                {landed && (
                  <motion.div layoutId="task-card" transition={spring} className="rounded-xl bg-surface p-2.5 ring-2 ring-signal/50">
                    <p className="text-[12px] font-medium">Board report PDF</p>
                    <p className="text-[10.5px] text-muted">SA · Fri</p>
                  </motion.div>
                )}
                <Card title="Prompt plan review" meta="SO · today" />
              </Column>
              <Column name="In progress">
                <Card title="Score weights v2" meta="VE · Fri" />
                <Card title="Report share links" meta="OJ · Mon" />
              </Column>
              <Column name="Done">
                <Card title="AI Overview lane" meta="OJ · merged" done />
              </Column>
            </div>
          </div>
        </Window>
      </LayoutGroup>

      <AnimatePresence>
        {pinged && (
          <motion.div
            key="whatsapp"
            initial={{ opacity: 0, y: 18, scale: 0.96 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 8, transition: { duration: 0.2 } }}
            transition={spring}
            className="absolute right-3 bottom-3 z-10 w-[290px] rounded-[18px] bg-white/95 p-3 shadow-[0_24px_60px_-20px_rgba(8,16,32,0.55)] ring-1 ring-black/5 backdrop-blur"
          >
            <p className="flex items-center gap-1.5 text-[10.5px] font-medium text-muted">
              <span className="grid size-4 place-items-center rounded-[5px] bg-[#25D366] text-white">
                <WhatsappLogoIcon size={11} weight="fill" />
              </span>
              WhatsApp · now
            </p>
            <p className="mt-1.5 text-[12.5px] font-semibold">Noa</p>
            <p className="text-[12.5px] leading-snug">
              Saish, you&rsquo;re on <span className="font-medium">Board report PDF export</span> for Veriq, due Fri. Vedant approved it from #veriq.
            </p>
            <div className="mt-2 flex gap-1.5">
              <span className="flex-1 rounded-full bg-bg py-1 text-center text-[11px] font-medium">Start now</span>
              <span className="flex-1 rounded-full bg-bg py-1 text-center text-[11px] font-medium">Need help</span>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

function Message({
  who,
  name,
  time,
  text,
  tone = "mist",
  highlight = false,
}: {
  who: string;
  name: string;
  time: string;
  text: string;
  tone?: "mist" | "accent";
  highlight?: boolean;
}) {
  return (
    <div className="flex items-start gap-2.5">
      <Avatar initials={who} tone={tone} />
      <div>
        <p className="text-[12px] font-semibold">
          {name} <span className="font-normal text-muted">{time}</span>
        </p>
        <p
          className={`mt-0.5 rounded-md text-[13px] transition-colors duration-500 ${
            highlight ? "bg-mist shadow-[0_0_0_4px_var(--color-mist)]" : ""
          }`}
        >
          {text}
        </p>
      </div>
    </div>
  );
}

function Column({ name, children }: { name: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-2 rounded-2xl bg-bg p-2">
      <p className="px-1 text-[11px] font-semibold text-muted">{name}</p>
      {children}
    </div>
  );
}

function Card({ title, meta, done = false }: { title: string; meta: string; done?: boolean }) {
  return (
    <div className="rounded-xl bg-surface p-2.5 ring-1 ring-line/80">
      <p className="flex items-center gap-1 text-[12px] font-medium">
        {done && <CheckIcon size={11} weight="bold" className="text-good" />}
        {title}
      </p>
      <p className="text-[10.5px] text-muted">{meta}</p>
    </div>
  );
}
