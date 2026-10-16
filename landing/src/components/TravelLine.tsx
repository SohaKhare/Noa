"use client";

import { motion, useReducedMotion } from "motion/react";

/* The reference's traveling line: a curve draws, a dot rides it, a sentence sits on top. */
export function TravelLine({ text }: { text: string }) {
  const reduce = useReducedMotion();

  return (
    <div className="relative mx-auto h-32 max-w-5xl px-5 sm:h-36">
      <svg viewBox="0 0 1000 140" className="h-full w-full" aria-hidden>
        <motion.path
          d="M30 90 C 180 90, 240 28, 480 36 S 760 118, 970 48"
          fill="none"
          stroke="currentColor"
          strokeWidth="1.5"
          strokeLinecap="round"
          className="text-accent/35"
          initial={reduce ? false : { pathLength: 0 }}
          whileInView={{ pathLength: 1 }}
          viewport={{ once: true, amount: 0.6 }}
          transition={{ duration: 1.6, ease: [0.22, 1, 0.36, 1] }}
        />
        <motion.circle
          r="4.5"
          className="fill-accent"
          style={{ offsetPath: 'path("M30 90 C 180 90, 240 28, 480 36 S 760 118, 970 48")' }}
          initial={reduce ? { offsetDistance: "100%" } : { offsetDistance: "0%" }}
          whileInView={{ offsetDistance: "100%" }}
          viewport={{ once: true, amount: 0.6 }}
          transition={{ duration: 1.6, ease: [0.22, 1, 0.36, 1] }}
        />
      </svg>
      <p className="absolute inset-x-0 top-1/2 -translate-y-1/2 text-center text-[clamp(1.15rem,2.4vw,1.7rem)] font-medium tracking-[-0.03em] text-ink/80">
        {text}
      </p>
    </div>
  );
}
