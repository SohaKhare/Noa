import { ArrowRightIcon } from "@phosphor-icons/react/ssr";
import { cdnAsset } from "@/lib/cdn";
import { APP_URL } from "@/lib/links";
import Image from "next/image";
import { BrandMark } from "./BrandMark";
import { Reveal } from "./Reveal";

/* Elf's closing card: same size, night water behind a light wash. */
export function ClosingCTA() {
  return (
    <section aria-labelledby="cta-title" className="px-2 pt-8 pb-6 sm:px-3">
      <div className="relative isolate mx-auto max-w-4xl overflow-hidden rounded-card px-5 py-14 text-center sm:py-16">
        <Image src={cdnAsset("/night-water.jpg")} alt="" fill sizes="(min-width: 1024px) 896px, 100vw" className="object-cover -z-20" />
        <div aria-hidden className="absolute inset-0 -z-10 bg-[linear-gradient(180deg,rgba(238,243,248,0.78),rgba(238,243,248,0.5)_45%,rgba(238,243,248,0.7))]" />
        <Reveal className="flex flex-col items-center">
          <div className="mb-5 flex items-center gap-2">
            <BrandMark size={32} />
            <span className="font-wordmark text-[28px] leading-none">NOA</span>
          </div>
          <h2 id="cta-title" className="max-w-2xl text-[clamp(2.1rem,5vw,3.75rem)] leading-[0.98] font-bold tracking-[-0.05em] text-ink">
            Just @noa. It&apos;s handled.
          </h2>
          <p className="mt-4 max-w-md text-lg text-ink/70">Connect one channel and see your first tasks in ten minutes.</p>
          <a
            href={APP_URL}
            className="group mt-7 inline-flex items-center gap-2 rounded-full bg-accent py-1.5 pr-1.5 pl-6 text-[15px] font-medium text-white transition-colors hover:bg-accent-soft"
          >
            Open Noa
            <span className="grid size-9 place-items-center rounded-full bg-white/15 transition-transform duration-300 ease-soft group-hover:translate-x-0.5">
              <ArrowRightIcon size={15} weight="bold" />
            </span>
          </a>
        </Reveal>
      </div>
    </section>
  );
}
