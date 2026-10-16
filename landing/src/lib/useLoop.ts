"use client";

import { useInView, useReducedMotion } from "motion/react";
import { useEffect, useRef, useState } from "react";

/*
  Drives a scripted, looping UI scene. Pass phase durations in ms.
  Runs only while the scene is on screen; under reduced motion it rests on the last phase.
*/
export function useLoop(durations: readonly number[]) {
  const ref = useRef<HTMLDivElement>(null);
  const inView = useInView(ref, { amount: 0.35 });
  const reduce = useReducedMotion();
  const [step, setStep] = useState(0);
  const last = durations.length - 1;

  useEffect(() => {
    if (reduce || !inView) return;
    const timer = setTimeout(() => setStep((s) => (s >= last ? 0 : s + 1)), durations[step]);
    return () => clearTimeout(timer);
  }, [step, inView, reduce, durations, last]);

  return { ref, step: reduce ? last : step, reduce: !!reduce };
}

/* Types `text` one character at a time while `active`. */
export function useTyping(text: string, active: boolean, charMs = 45) {
  const [n, setN] = useState(0);
  useEffect(() => {
    if (!active) return;
    const timer = setInterval(() => setN((v) => (v >= text.length ? v : v + 1)), charMs);
    return () => {
      clearInterval(timer);
      setN(0);
    };
  }, [active, text, charMs]);
  return active ? text.slice(0, n) : "";
}
