"use client";

import { CheckIcon, DiscordLogoIcon, SlackLogoIcon, VideoCameraIcon, WhatsappLogoIcon } from "@phosphor-icons/react";
import { AnimatePresence, motion } from "motion/react";
import { useLoop, useTyping } from "@/lib/useLoop";

/* Live chips for the three step cards. Each loops while on screen and rests on its last frame for reduced motion. */

const sources = [
  { label: "Discord", Icon: DiscordLogoIcon, project: "Veriq" },
  { label: "Slack", Icon: SlackLogoIcon, project: "Emmarie" },
  { label: "Meet", Icon: VideoCameraIcon, project: "Weekly sync" },
  { label: "WhatsApp", Icon: WhatsappLogoIcon, project: "Video Break" },
];

const pop = { type: "spring" as const, stiffness: 420, damping: 22 };

export function ConnectChip() {
  // 0 idle, 1-4 each source connects, 5 all mapped (hold)
  const { ref, step } = useLoop([900, 650, 650, 650, 650, 2600]);
  const connected = Math.min(step, sources.length);
  return (
    <div ref={ref} className="glass rounded-chip p-3">
      <p className="flex items-center justify-between px-1 text-[11px] font-medium text-ink/65">
        Channels mapped to projects
        <span className="tabular-nums">
          {connected}/{sources.length}
        </span>
      </p>
      <ul className="mt-2 grid grid-cols-4 gap-2">
        {sources.map(({ label, Icon, project }, i) => {
          const on = i < connected;
          return (
            <li
              key={label}
              className={`flex flex-col items-center gap-1 rounded-xl py-2.5 transition-colors duration-300 ${on ? "bg-white" : "bg-white/50"}`}
            >
              <span className="relative">
                <Icon size={20} className={on ? "text-accent" : "text-ink/35"} />
                <AnimatePresence>
                  {on && (
                    <motion.span
                      key="check"
                      initial={{ scale: 0 }}
                      animate={{ scale: 1 }}
                      exit={{ scale: 0 }}
                      transition={pop}
                      className="absolute -right-2 -bottom-1 grid size-3.5 place-items-center rounded-full bg-accent text-white"
                    >
                      <CheckIcon size={9} weight="bold" />
                    </motion.span>
                  )}
                </AnimatePresence>
              </span>
              <span className="text-[10px] text-ink/70">{label}</span>
              <span className={`text-[9px] transition-opacity duration-300 ${on ? "text-accent opacity-100" : "opacity-0"}`}>→ {project}</span>
            </li>
          );
        })}
      </ul>
    </div>
  );
}

const Q = "@noa what did we decide about Veriq scoring?";

export function TalkChip() {
  // 0 idle, 1 typing, 2 sent + thinking, 3 answer, 4 hold
  const { ref, step } = useLoop([700, Q.length * 40 + 300, 1100, 900, 2600]);
  const typed = useTyping(Q, step === 1, 40);
  return (
    <div ref={ref} className="glass min-h-[132px] space-y-2 rounded-chip p-3">
      <AnimatePresence>
        {step >= 2 && (
          <motion.p
            key="q"
            initial={{ opacity: 0, y: 6 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0 }}
            className="ml-auto w-fit rounded-[14px] rounded-br-sm bg-accent px-3 py-2 text-[13px] text-white"
          >
            {Q}
          </motion.p>
        )}
        {step === 2 && (
          <motion.span key="dots" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} className="flex w-fit gap-1 rounded-[14px] bg-white/80 px-3 py-2.5">
            {[0, 1, 2].map((i) => (
              <motion.span
                key={i}
                className="size-1.5 rounded-full bg-ink/40"
                animate={{ opacity: [0.3, 1, 0.3] }}
                transition={{ duration: 0.9, repeat: Infinity, delay: i * 0.15 }}
              />
            ))}
          </motion.span>
        )}
        {step >= 3 && (
          <motion.p
            key="a"
            initial={{ opacity: 0, y: 6 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0 }}
            className="w-fit rounded-[14px] rounded-bl-sm bg-white/90 px-3 py-2 text-[13px]"
          >
            All seven model families, decided Tuesday in #veriq. <span className="font-mono text-[11px] text-muted">[1]</span>
          </motion.p>
        )}
      </AnimatePresence>
      {step < 2 && (
        <p className="flex h-9 items-center rounded-full bg-white/70 px-3 text-[13px]">
          {typed ? (
            <span>
              {typed}
              <span className="ml-px inline-block h-4 w-px animate-pulse bg-accent align-middle" />
            </span>
          ) : (
            <span className="text-ink/45">Message #veriq</span>
          )}
        </p>
      )}
    </div>
  );
}

export function ApproveChip() {
  // 0 card in, 1 hover, 2 press, 3 approved, 4 hold
  const { ref, step } = useLoop([1300, 700, 350, 2400, 600]);
  const approved = step >= 3 && step < 4;
  return (
    <div ref={ref} className="glass rounded-chip p-3.5">
      <p className="text-[11px] font-medium text-ink/65">Deadline change · needs your lead</p>
      <p className="mt-1 text-[14px] font-medium">
        Board report PDF: <span className={approved ? "text-ink/45 line-through" : ""}>Fri</span> → Mon
      </p>
      <p className="mt-0.5 text-[12px] text-ink/65">Saish: &ldquo;waiting on the logo pack&rdquo; · #veriq</p>
      <div className="mt-3 flex h-9 gap-2">
        <AnimatePresence mode="wait" initial={false}>
          {approved ? (
            <motion.span
              key="done"
              initial={{ opacity: 0, scale: 0.9 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0 }}
              transition={pop}
              className="flex flex-1 items-center justify-center gap-1.5 rounded-full bg-mist text-[12px] font-medium text-accent"
            >
              <CheckIcon size={13} weight="bold" /> Approved · owners notified
            </motion.span>
          ) : (
            <motion.span key="btns" className="flex flex-1 gap-2" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
              <span
                className={`flex flex-1 items-center justify-center rounded-full bg-accent text-[12px] font-medium text-white transition-transform duration-200 ${
                  step === 1 ? "ring-4 ring-accent/20" : ""
                } ${step === 2 ? "scale-95" : ""}`}
              >
                Approve
              </span>
              <span className="flex flex-1 items-center justify-center rounded-full bg-white/80 text-[12px] font-medium">Edit</span>
            </motion.span>
          )}
        </AnimatePresence>
      </div>
    </div>
  );
}
