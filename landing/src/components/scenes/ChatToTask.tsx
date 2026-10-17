"use client";

import { CheckIcon, HashIcon, LightningIcon, WhatsappLogoIcon } from "@phosphor-icons/react";
import { AnimatePresence, LayoutGroup, motion } from "motion/react";
import { useLoop, useTyping } from "@/lib/useLoop";
import { LiveDot, SourceChip, Window } from "../ui";

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
        <div className="flex overflow-hidden rounded-[22px] bg-[#313338] text-[#dbdee1] shadow-[0_18px_50px_-24px_rgba(8,16,32,0.7)]">
          <div className="flex w-[52px] shrink-0 flex-col items-center gap-2 bg-[#1e1f22] py-3">
            <span className="grid size-9 place-items-center rounded-2xl bg-[#5865f2] text-[12px] font-semibold text-white">N</span>
            <span className="h-px w-6 bg-white/10" />
          </div>
          <div className="min-w-0 flex-1">
          <div className="flex h-11 items-center gap-2 border-b border-black/30 px-4">
            <HashIcon size={16} className="text-[#949ba4]" />
            <span className="text-[14px] font-semibold text-white">veriq</span>
            <span className="ml-auto flex items-center gap-1.5 text-[11px] text-[#949ba4]">
              <LiveDot /> Noa is listening
            </span>
          </div>
          <div className="flex h-[360px] flex-col">
            <div className="flex flex-1 flex-col justify-end gap-3.5 px-4 py-3">
              <DiscordMessage who="OJ" name="Ojas" time="10:31" text="AI Overview lane is green again 🎉" />
              <DiscordMessage who="VE" name="Vedant" time="10:40" text="who can take the Board report PDF export? client wants it this week" />
              <AnimatePresence>
                {sent && (
                  <motion.div key="reply" {...enter}>
                    <DiscordMessage who="SA" name="Saish" time="10:42" text={REPLY} highlight={step >= HEARD && step < LANDED} />
                  </motion.div>
                )}
                {landed && (
                  <motion.div key="noa" {...enter}>
                    <DiscordMessage who="NOA" name="Noa" time="10:42" bot text="Added to Veriq · Saish · due Fri." />
                  </motion.div>
                )}
              </AnimatePresence>
            </div>
            <div className="px-4 pb-4">
              <div className="flex h-11 items-center rounded-lg bg-[#383a40] px-4 text-[14px]">
                {draft ? (
                  <span className="text-[#dbdee1]">
                    {draft}
                    <span className="ml-px inline-block h-4 w-px animate-pulse bg-white align-middle" />
                  </span>
                ) : (
                  <span className="text-[#949ba4]">Message #veriq</span>
                )}
              </div>
            </div>
          </div>
          </div>
        </div>

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

const roles = {
  OJ: { initials: "OJ", color: "#5865f2" },
  VE: { initials: "VE", color: "#f0b232" },
  SA: { initials: "SA", color: "#23a559" },
  NOA: { initials: "N", color: "#5865f2" },
} as const;

function DiscordMessage({
  who,
  name,
  time,
  text,
  highlight = false,
  bot = false,
}: {
  who: keyof typeof roles;
  name: string;
  time: string;
  text: string;
  highlight?: boolean;
  bot?: boolean;
}) {
  const role = roles[who];
  return (
    <div className={`-mx-2 flex items-start gap-3 rounded px-2 py-0.5 ${highlight ? "bg-[#5865f2]/20" : ""}`}>
      <span
        className="grid size-9 shrink-0 place-items-center rounded-full text-[11px] font-semibold text-white"
        style={{ backgroundColor: role.color }}
      >
        {role.initials}
      </span>
      <div className="min-w-0">
        <p className="text-[14px] leading-none">
          <span className="font-medium" style={{ color: role.color }}>
            {name}
          </span>
          {bot && <span className="ml-1.5 rounded bg-[#5865f2] px-1 py-px align-middle text-[9px] font-bold tracking-wide text-white">BOT</span>}
          <span className="ml-2 text-[11px] font-normal text-[#949ba4]">{time}</span>
        </p>
        <p className="mt-1 text-[14px] leading-snug text-[#dbdee1]">
          {text}
          {bot && <span className="text-[#00a8fc]"> Undo</span>}
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
