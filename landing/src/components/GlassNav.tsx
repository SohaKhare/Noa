"use client";

import { useLenis } from "lenis/react";
import { AnimatePresence, motion, useMotionValueEvent, useReducedMotion, useScroll } from "motion/react";
import { useEffect, useState } from "react";
import { APP_URL, navLinks as links } from "@/lib/links";

export function GlassNav() {
  const reduce = useReducedMotion();
  const { scrollY } = useScroll();
  const [floating, setFloating] = useState(false);
  const [open, setOpen] = useState(false);
  useMotionValueEvent(scrollY, "change", (y) => setFloating(y > 64));

  const lenis = useLenis();
  useEffect(() => {
    document.body.style.overflow = open ? "hidden" : "";
    if (open) lenis?.stop();
    else lenis?.start();
    return () => {
      document.body.style.overflow = "";
    };
  }, [open, lenis]);

  const solid = floating || open;
  const spring = reduce ? { duration: 0 } : { type: "spring" as const, stiffness: 240, damping: 30, mass: 0.9 };

  return (
    <>
      <header className="fixed inset-x-0 top-0 z-50 flex justify-center">
        <motion.nav
          layout
          aria-label="Main"
          transition={spring}
          style={{ borderRadius: 28 }}
          className={`flex items-center justify-between transition-[background-color,color,box-shadow] duration-500 ease-soft ${
            solid
              ? "liquid-glass mt-3 h-14 w-[min(26rem,calc(100%-1.5rem))] pr-2 pl-6 text-ink lg:w-[min(62rem,calc(100%-1.5rem))]"
              : "mt-2 h-[76px] w-[calc(100%-1rem)] bg-transparent px-5 text-white sm:mt-3 sm:w-[calc(100%-1.5rem)] sm:px-8"
          }`}
        >
          <motion.a
            layout="position"
            transition={spring}
            href="#top"
            className="flex items-center gap-2 rounded-full text-[16px] font-semibold tracking-tight"
          >
            Noa
          </motion.a>

          <motion.ul layout="position" transition={spring} className="hidden items-center gap-0.5 lg:flex">
            {links.map((link) => (
              <li key={link.href}>
                <a
                  href={link.href}
                  className={`rounded-full px-3.5 py-2 text-[14px] transition-colors duration-300 ${
                    solid ? "text-ink/70 hover:bg-black/5 hover:text-ink" : "text-white/85 hover:bg-white/10 hover:text-white"
                  }`}
                >
                  {link.label}
                </a>
              </li>
            ))}
          </motion.ul>

          <motion.div layout="position" transition={spring} className="flex items-center gap-2">
            <a
              href={APP_URL}
              className={`rounded-full px-4 py-2 text-[14px] font-medium transition-[background-color,color,transform] duration-300 active:scale-[0.98] ${
                solid ? "bg-accent text-white hover:bg-accent-soft" : "bg-white text-accent hover:bg-mist"
              }`}
            >
              Open Noa
            </a>
            <button
              type="button"
              aria-label={open ? "Close menu" : "Open menu"}
              aria-expanded={open}
              onClick={() => setOpen((v) => !v)}
              className={`relative grid size-10 place-items-center rounded-full transition-colors lg:hidden ${
                solid ? "hover:bg-black/5" : "hover:bg-white/10"
              }`}
            >
              <span
                className={`absolute h-[1.5px] w-4 rounded-full bg-current transition-transform duration-300 ease-soft ${
                  open ? "rotate-45" : "-translate-y-[4px]"
                }`}
              />
              <span
                className={`absolute h-[1.5px] w-4 rounded-full bg-current transition-transform duration-300 ease-soft ${
                  open ? "-rotate-45" : "translate-y-[4px]"
                }`}
              />
            </button>
          </motion.div>
        </motion.nav>
      </header>

      <AnimatePresence>
        {open && (
          <motion.div
            key="menu"
            className="fixed inset-0 z-40 flex flex-col justify-center bg-bg/90 px-8 backdrop-blur-3xl lg:hidden"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: reduce ? 0 : 0.3 }}
          >
            <ul className="space-y-2">
              {links.map((link, i) => (
                <motion.li
                  key={link.href}
                  initial={reduce ? false : { opacity: 0, y: 32 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, y: 12 }}
                  transition={{ duration: 0.5, delay: reduce ? 0 : 0.06 + i * 0.05, ease: [0.22, 1, 0.36, 1] }}
                >
                  <a
                    href={link.href}
                    onClick={() => setOpen(false)}
                    className="block py-2 text-[34px] leading-tight font-semibold tracking-[-0.03em] text-ink"
                  >
                    {link.label}
                  </a>
                </motion.li>
              ))}
            </ul>
          </motion.div>
        )}
      </AnimatePresence>
    </>
  );
}
