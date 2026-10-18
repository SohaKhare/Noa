import Link from "next/link";
import { BrandMark } from "./BrandMark";
import { navLinks } from "@/lib/links";

export function Footer() {
  return (
    <footer className="mx-auto max-w-7xl px-5 pt-16 pb-12">
      <div className="flex flex-col justify-between gap-10 md:flex-row md:items-start">
        <div>
          <a href="#top" className="flex items-center gap-2">
            <BrandMark size={26} />
            <span className="font-wordmark text-[22px] leading-none">NOA</span>
          </a>
          <p className="mt-4 max-w-xs text-[14px] leading-relaxed text-muted">
            The company brain for teams that live in chat.
          </p>
        </div>
        <nav aria-label="Footer">
          <ul className="flex flex-wrap gap-x-7 gap-y-3">
            {navLinks.map((link) => (
              <li key={link.label}>
                <a href={link.href} className="text-[14px] text-ink/75 transition-colors hover:text-ink">
                  {link.label}
                </a>
              </li>
            ))}
          </ul>
        </nav>
      </div>
      <div className="mt-14 flex flex-col justify-between gap-3 border-t border-line pt-6 text-[12px] text-muted sm:flex-row">
        <p>Built by NotYourIdea for Graph Hacks 2026. Powered by FalkorDB.</p>
        <p className="flex gap-5">
          <Link href="/privacy" className="hover:text-ink">
            Privacy policy
          </Link>
          <Link href="/terms" className="hover:text-ink">
            Terms
          </Link>
        </p>
      </div>
    </footer>
  );
}
