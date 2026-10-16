"use client";

import { PlusIcon } from "@phosphor-icons/react";
import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import { useId, useState } from "react";
import { Reveal } from "./Reveal";

const faqs = [
  {
    q: "What is Noa?",
    a: "A company brain. It reads the channels you choose in Discord, Slack, Meet and WhatsApp, keeps tasks, owners, deadlines and decisions in one place, and answers questions with sources.",
  },
  {
    q: "Does it change things on its own?",
    a: "Only small, confident updates, and each one can be undone. New tasks wait in your inbox, and scope or deadline changes wait for the right lead.",
  },
  {
    q: "What does it read?",
    a: "Only the channels an admin maps to projects. Direct messages are never read, and unmapped channels are never ingested.",
  },
  {
    q: "How does moving someone between projects work?",
    a: "Drag them on the staffing board and confirm. Noa drafts the handover, suggests new owners, grants access, sends a KT brief and an agent pack, and routes questions about the old project to them for two weeks.",
  },
  {
    q: "What is an agent pack?",
    a: "Files generated from the project that you paste into your AI tools: CLAUDE.md or AGENTS.md, tasks.md, and an MCP config for live context. Non-dev roles get a brief, client notes, a runbook or project state instead.",
  },
  {
    q: "Is it only for developers?",
    a: "No. Designers, client servicing, ops and PMs each get their own view, and non-tech teammates can do most things from WhatsApp.",
  },
];

export function FAQ() {
  const [open, setOpen] = useState<number | null>(0);
  const baseId = useId();
  const reduce = useReducedMotion();

  return (
    <section id="faq" aria-labelledby="faq-title" className="mx-auto max-w-7xl px-5 py-28">
      <div className="grid gap-12 lg:grid-cols-[0.8fr_1.2fr] lg:gap-20">
        <Reveal className="lg:sticky lg:top-28 lg:self-start">
          <h2 id="faq-title" className="text-[clamp(2rem,4.4vw,3.25rem)] leading-[1.05] font-semibold tracking-[-0.035em]">
            Common questions
          </h2>
          <p className="mt-4 max-w-sm text-lg leading-relaxed text-muted">Or just ask @noa once you&apos;re in.</p>
        </Reveal>

        <div className="divide-y divide-line">
          {faqs.map((item, i) => {
            const isOpen = open === i;
            const buttonId = `${baseId}-q${i}`;
            const panelId = `${baseId}-a${i}`;
            return (
              <div key={item.q}>
                <h3>
                  <button
                    id={buttonId}
                    type="button"
                    aria-expanded={isOpen}
                    aria-controls={panelId}
                    onClick={() => setOpen(isOpen ? null : i)}
                    className="flex w-full items-center justify-between gap-6 py-6 text-left text-[18px] font-medium tracking-tight"
                  >
                    {item.q}
                    <span
                      className={`grid size-8 shrink-0 place-items-center rounded-full transition-[transform,background-color] duration-300 ease-soft ${
                        isOpen ? "rotate-45 bg-accent text-white" : "bg-surface text-ink ring-1 ring-black/5"
                      }`}
                    >
                      <PlusIcon size={14} weight="bold" />
                    </span>
                  </button>
                </h3>
                <AnimatePresence initial={false}>
                  {isOpen && (
                    <motion.div
                      id={panelId}
                      role="region"
                      aria-labelledby={buttonId}
                      initial={reduce ? false : { height: 0, opacity: 0 }}
                      animate={{ height: "auto", opacity: 1 }}
                      exit={reduce ? undefined : { height: 0, opacity: 0 }}
                      transition={{ duration: 0.3, ease: [0.22, 1, 0.36, 1] }}
                      className="overflow-hidden"
                    >
                      <p className="max-w-[60ch] pr-12 pb-6 text-[16px] leading-relaxed text-muted">{item.a}</p>
                    </motion.div>
                  )}
                </AnimatePresence>
              </div>
            );
          })}
        </div>
      </div>
    </section>
  );
}
