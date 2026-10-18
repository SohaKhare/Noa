import Link from "next/link";
import type { ReactNode } from "react";
import { BrandMark } from "./BrandMark";

/* Shared frame for the privacy policy and terms: plain reading width, no animation. */
export function LegalPage({ title, updated, children }: { title: string; updated: string; children: ReactNode }) {
  return (
    <div className="min-h-screen bg-bg">
      <header className="mx-auto flex max-w-3xl items-center gap-2 px-5 pt-8">
        <Link href="/" className="flex items-center gap-2">
          <BrandMark size={24} />
          <span className="font-wordmark text-[20px] leading-none">NOA</span>
        </Link>
      </header>
      <main className="mx-auto max-w-3xl px-5 pt-12 pb-20">
        <h1 className="text-[34px] leading-tight font-semibold tracking-[-0.03em]">{title}</h1>
        <p className="mt-2 text-[13px] text-muted">Last updated {updated}</p>
        <div className="legal mt-8 space-y-4 text-[15px] leading-relaxed text-ink/85 [&_h2]:mt-10 [&_h2]:text-[19px] [&_h2]:font-semibold [&_h2]:text-ink [&_li]:ml-5 [&_li]:list-disc [&_ul]:space-y-1.5">
          {children}
        </div>
      </main>
      <footer className="mx-auto max-w-3xl border-t border-line px-5 py-6 text-[12px] text-muted">
        <Link href="/" className="hover:text-ink">
          Noa
        </Link>{" "}
        · <Link href="/privacy" className="hover:text-ink">Privacy policy</Link> · <Link href="/terms" className="hover:text-ink">Terms</Link>
      </footer>
    </div>
  );
}
