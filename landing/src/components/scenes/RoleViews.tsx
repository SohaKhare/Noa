"use client";

import { AnimatePresence, motion } from "motion/react";
import { useLoop } from "@/lib/useLoop";
import { Window } from "../ui";

/* The same project, a different pack for each role. Cycles through them. */

const ROLES = [
  {
    role: "Developer",
    file: "CLAUDE.md + tasks.md",
    lines: ["# Veriq: conventions", "- Tests must never spend money", "- SQL migrations are hand-written", "## Live context", "- Noa MCP: veriq (your token)"],
  },
  {
    role: "Designer",
    file: "brief.md",
    lines: ["# Emmarie · storyboard screen", "Audience: writers and directors", "Decided: storyboard before motion test", "Due Mon · review with Ojas"],
  },
  {
    role: "Client servicing",
    file: "client.md",
    lines: ["# Veriq · brand client", "Promised: Board report PDF by Fri", "Moved: PDF to Mon (Prathamesh approved)", "Next call: Thu 4 pm"],
  },
  {
    role: "Ops",
    file: "runbook.md",
    lines: ["# Deploy runbook", "Fly and Cloudflare secrets: one-time link, 24h", "On failure: page Ojas", "Rotate after any shift"],
  },
  {
    role: "PM",
    file: "project-state.md",
    lines: ["# Veriq · at risk", "1 blocker · 1 unowned task", "Only Vedant knows the PDF renderer", "Slip on the PDF pushes 2 tasks"],
  },
];
const PHASES = ROLES.map(() => 2600);

export function RoleViews() {
  const { ref, step } = useLoop(PHASES);
  const current = ROLES[step];

  return (
    <div ref={ref} className="w-full">
      <Window title="Packs by role">
        <div className="h-[380px] p-5">
          <div className="flex flex-wrap gap-1.5">
            {ROLES.map((r, i) => (
              <span
                key={r.role}
                className={`rounded-full px-3 py-1.5 text-[12px] font-medium transition-colors duration-300 ${
                  i === step ? "bg-accent text-white" : "bg-bg text-ink/70"
                }`}
              >
                {r.role}
              </span>
            ))}
          </div>
          <AnimatePresence mode="wait">
            <motion.div
              key={current.role}
              initial={{ opacity: 0, y: 12, filter: "blur(6px)" }}
              animate={{ opacity: 1, y: 0, filter: "blur(0px)" }}
              exit={{ opacity: 0, y: -8, filter: "blur(4px)" }}
              transition={{ duration: 0.45, ease: [0.22, 1, 0.36, 1] }}
              className="mt-5 overflow-hidden rounded-2xl bg-deep text-white"
            >
              <p className="border-b border-white/10 px-4 py-2.5 font-mono text-[12px] text-white/80">{current.file}</p>
              <div className="space-y-1.5 px-4 py-4 font-mono text-[12.5px] leading-relaxed">
                {current.lines.map((l) => (
                  <p key={l} className={l.startsWith("#") ? "font-semibold text-white" : "text-white/80"}>
                    {l}
                  </p>
                ))}
              </div>
            </motion.div>
          </AnimatePresence>
          <p className="mt-4 text-[12px] text-muted">Regenerated whenever tasks or decisions change. Secrets never go in these files.</p>
        </div>
      </Window>
    </div>
  );
}
