"use client";

import { motion, useReducedMotion, useScroll, useTransform } from "motion/react";
import { useRef, type ReactNode } from "react";

type ParallaxProps = {
  children: ReactNode;
  /** Total vertical travel in px across the element's pass through the viewport. */
  distance?: number;
  className?: string;
};

export function Parallax({ children, distance = 40, className = "" }: ParallaxProps) {
  const ref = useRef<HTMLDivElement>(null);
  const reduce = useReducedMotion();
  const { scrollYProgress } = useScroll({
    target: ref,
    offset: ["start end", "end start"],
  });
  const y = useTransform(scrollYProgress, [0, 1], [-distance / 2, distance / 2]);

  return (
    <div ref={ref} className={`absolute inset-0 overflow-hidden ${className}`}>
      <motion.div
        className="absolute -inset-y-8 inset-x-0"
        style={reduce ? undefined : { y }}
      >
        {children}
      </motion.div>
    </div>
  );
}
