import { CheckIcon } from "@phosphor-icons/react/ssr";
import type { ReactNode } from "react";
import { Reveal } from "../Reveal";

type FeatureBlockProps = {
  index: number;
  total: number;
  eyebrow: string;
  title: string;
  points: string[];
  scene: ReactNode;
  wide?: boolean;
};

/* One feature on the story stage: a glass copy panel and its live scene. */
export function FeatureBlock({ index, total, eyebrow, title, points, scene, wide = false }: FeatureBlockProps) {
  return (
    <div className="mx-auto grid w-full max-w-6xl items-center gap-8 lg:grid-cols-[0.72fr_1.28fr] lg:gap-12">
      <Reveal>
        <p className="text-[13px] text-muted">
          {String(index).padStart(2, "0")} / {String(total).padStart(2, "0")} {eyebrow}
        </p>
        <h2 className="mt-3 text-[clamp(1.8rem,3vw,2.6rem)] leading-[1.05] font-semibold tracking-[-0.035em]">{title}</h2>
        <ul className="mt-6 space-y-3">
          {points.map((p) => (
            <li key={p} className="flex items-start gap-3 text-[15px] leading-relaxed text-ink/80">
              <span className="mt-0.5 grid size-5 shrink-0 place-items-center rounded-full bg-accent text-mist">
                <CheckIcon size={11} weight="bold" />
              </span>
              {p}
            </li>
          ))}
        </ul>
      </Reveal>
      <Reveal delay={0.1} className={`w-full justify-self-center ${wide ? "max-w-[780px]" : "max-w-[640px]"}`}>
        {scene}
      </Reveal>
    </div>
  );
}
