"use client";

import {
  AtIcon,
  BookOpenTextIcon,
  ChatsCircleIcon,
  CheckIcon,
  GavelIcon,
  IdentificationBadgeIcon,
  UsersThreeIcon,
  type Icon,
} from "@phosphor-icons/react";
import { AnimatePresence, animate, motion, useInView, useMotionValue, useMotionValueEvent, useReducedMotion } from "motion/react";
import { cdnAsset } from "@/lib/cdn";
import Image from "next/image";
import { useEffect, useRef, useState, type ReactNode } from "react";
import { AskNoa } from "./scenes/AskNoa";
import { ChatToTask } from "./scenes/ChatToTask";
import { DecisionsEdits } from "./scenes/DecisionsEdits";
import { DropIntoProject } from "./scenes/DropIntoProject";
import { KTBrief } from "./scenes/KTBrief";
import { RoleViews } from "./scenes/RoleViews";
import { SectionHeading } from "./SectionHeading";

/*
  Elf's "Everywhere" layout for Noa's six features, played on a clock instead of scroll:
  each tab runs for one full loop of its scene, its points light up in step, then the next tab starts.
  Tabs and points can be clicked; play pauses while the section is off screen.
*/

/* ms: one full loop of each scene (sum of its PHASES). */
type Feature = { id: string; label: string; Icon: Icon; title: string; points: string[]; scene: ReactNode; image: string; ms: number };

const features: Feature[] = [
  {
    id: "chat",
    ms: 13200,
    label: "Chat to task",
    Icon: ChatsCircleIcon,
    title: "A reply in chat becomes a task on the board.",
    points: [
      "Noa hears it in Discord, Slack, Meet or WhatsApp",
      "It proposes the task with owner, date and source",
      "Approve once and it lands on the board, live",
    ],
    scene: <ChatToTask />,
    image: cdnAsset("/night.jpg"),
  },
  {
    id: "staffing",
    ms: 13400,
    label: "Staffing",
    Icon: UsersThreeIcon,
    title: "Drag someone to a new project. They arrive briefed.",
    points: [
      "One confirm hands over their open tasks",
      "Repo, channels and Drive access from the project's bundle",
      "Their AI agent gets CLAUDE.md, tasks.md and live context",
    ],
    scene: <DropIntoProject />,
    image: cdnAsset("/night-water.jpg"),
  },
  {
    id: "kt",
    ms: 8300,
    label: "KT",
    Icon: BookOpenTextIcon,
    title: "KT without the two-hour call.",
    points: [
      "Purpose, open work, decisions, who to ask",
      "Written from real messages and meetings, never invented",
      "Sent on WhatsApp, with a day-7 check-in",
    ],
    scene: <KTBrief />,
    image: cdnAsset("/night.jpg"),
  },
  {
    id: "ask",
    ms: 8900,
    label: "Ask",
    Icon: AtIcon,
    title: "Ask anything. Get the answer and the receipt.",
    points: [
      "Tag @noa in any channel your team already uses",
      "Every claim links to the message behind it",
      "Only uses what the person asking may see",
    ],
    scene: <AskNoa />,
    image: cdnAsset("/night-water.jpg"),
  },
  {
    id: "decisions",
    ms: 9000,
    label: "Decisions",
    Icon: GavelIcon,
    title: "Everyone can edit. The right lead always knows.",
    points: [
      "What was decided today, per project and per person",
      "Small edits apply straight away, with undo",
      "Deadline and scope changes wait for the editor's lead",
    ],
    scene: <DecisionsEdits />,
    image: cdnAsset("/night.jpg"),
  },
  {
    id: "roles",
    ms: 13000,
    label: "Every role",
    Icon: IdentificationBadgeIcon,
    title: "Not just for developers.",
    points: [
      "Designers get a brief, ops a runbook",
      "Client servicing sees what was promised",
      "PMs get project state, kept current as work moves",
    ],
    scene: <RoleViews />,
    image: cdnAsset("/night-water.jpg"),
  },
];

export function Product() {
  const ref = useRef<HTMLDivElement>(null);
  const inView = useInView(ref, { amount: 0.4 });
  const reduce = useReducedMotion();
  const [fi, setFi] = useState(0);
  const [pi, setPi] = useState(0);
  const progress = useMotionValue(0);
  const feature = features[fi];

  useMotionValueEvent(progress, "change", (p) => setPi(Math.min(feature.points.length - 1, Math.floor(p * feature.points.length))));

  useEffect(() => {
    if (reduce || !inView) return;
    const controls = animate(progress, 1, {
      duration: (feature.ms * (1 - progress.get())) / 1000,
      ease: "linear",
      onComplete: () => {
        progress.set(0);
        setPi(0);
        setFi((i) => (i + 1) % features.length);
      },
    });
    return () => controls.stop();
  }, [fi, inView, reduce, feature.ms, progress]);

  function go(i: number, point = 0) {
    progress.set(point / features[i].points.length);
    setPi(point);
    setFi(i);
  }

  return (
    <section id="product" aria-labelledby="product-title" className="px-5 py-28">
      <div className="mx-auto max-w-7xl">
        <SectionHeading
          id="product-title"
          title="Everything your team says, kept live."
          body="Tasks, staffing, briefs, answers and decisions, all from the chats and meetings you already have."
        />

        <div ref={ref} className="mt-14">
          <div className="mx-auto w-fit max-w-full">
            <div role="tablist" aria-label="Feature" className="no-scrollbar flex gap-1 overflow-x-auto rounded-full bg-white p-1.5 ring-1 ring-black/5">
              {features.map(({ id, label, Icon }, i) => {
                const selected = i === fi;
                return (
                  <button
                    key={id}
                    role="tab"
                    type="button"
                    aria-selected={selected}
                    aria-controls="product-stage"
                    onClick={() => go(i)}
                    className={`flex shrink-0 items-center gap-2 rounded-full px-4 py-2 text-[14px] font-medium transition-colors duration-300 active:scale-[0.98] ${
                      selected ? "bg-accent text-white" : "text-ink/70 hover:bg-bg"
                    }`}
                  >
                    <Icon size={16} weight={selected ? "fill" : "regular"} />
                    <span className={selected ? "" : "hidden md:inline"}>{label}</span>
                  </button>
                );
              })}
            </div>
            <div className="mx-4 mt-3 flex gap-1.5" aria-hidden>
              {features.map((f, i) => (
                <div key={f.id} className="h-[3px] flex-1 overflow-hidden rounded-full bg-ink/[0.06]">
                  {i < fi && <div className="h-full w-full rounded-full bg-accent/60" />}
                  {i === fi && <motion.div className="h-full origin-left rounded-full bg-accent" style={{ scaleX: reduce ? 1 : progress }} />}
                </div>
              ))}
            </div>
          </div>

          <div id="product-stage" role="tabpanel" className="mt-10 grid items-center gap-6 lg:grid-cols-[0.8fr_1.2fr] lg:gap-10">
            <div>
              <AnimatePresence mode="wait" initial={false}>
                <motion.h3
                  key={feature.id}
                  initial={reduce ? false : { opacity: 0, y: 8 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={reduce ? undefined : { opacity: 0, y: -6 }}
                  transition={{ duration: 0.3, ease: [0.22, 1, 0.36, 1] }}
                  className="mb-5 px-5 text-center text-[clamp(1.5rem,2.2vw,1.9rem)] leading-[1.1] font-semibold tracking-[-0.03em] lg:text-left"
                >
                  {feature.title}
                </motion.h3>
              </AnimatePresence>
              <ul className="space-y-2">
                {feature.points.map((point, i) => {
                  const selected = i === pi;
                  return (
                    <li key={feature.id + i}>
                      <button
                        type="button"
                        aria-pressed={selected}
                        onClick={() => go(fi, i)}
                        className={`flex w-full items-start gap-4 rounded-[22px] p-4 text-left transition-[background-color,box-shadow] duration-500 ease-soft sm:p-5 ${
                          selected ? "bg-white shadow-[0_16px_40px_-24px_rgba(14,28,51,0.45)]" : "hover:bg-white/60"
                        }`}
                      >
                        <span
                          className={`mt-0.5 grid size-6 shrink-0 place-items-center rounded-full transition-colors duration-500 ${
                            selected ? "bg-accent text-mist" : "ring-1 ring-ink/20"
                          }`}
                        >
                          {selected && <CheckIcon size={12} weight="bold" />}
                        </span>
                        <span className={`text-[16px] leading-relaxed ${selected ? "font-medium text-ink" : "text-muted"}`}>{point}</span>
                      </button>
                    </li>
                  );
                })}
              </ul>
            </div>

            <div className="relative isolate flex h-[min(62dvh,580px)] items-center justify-center overflow-hidden rounded-card">
              <AnimatePresence initial={false}>
                <motion.div
                  key={feature.id}
                  className="absolute inset-0 flex items-center justify-center px-4 sm:px-8"
                  initial={reduce ? false : { opacity: 0 }}
                  animate={{ opacity: 1 }}
                  exit={reduce ? undefined : { opacity: 0 }}
                  transition={{ duration: 0.4, ease: [0.22, 1, 0.36, 1] }}
                >
                  <Image src={feature.image} alt="" fill sizes="(min-width: 1024px) 60vw, 100vw" className="-z-10 object-cover" />
                  <div className="w-full max-w-[760px] [zoom:0.6] sm:[zoom:0.8] xl:[zoom:0.88]">{feature.scene}</div>
                </motion.div>
              </AnimatePresence>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
