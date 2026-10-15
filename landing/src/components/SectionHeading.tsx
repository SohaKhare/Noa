import { Reveal } from "./Reveal";

type SectionHeadingProps = {
  id: string;
  title: string;
  eyebrow?: string;
  body?: string;
  tone?: "ink" | "light";
  align?: "center" | "left";
};

export function SectionHeading({ id, eyebrow, title, body, tone = "ink", align = "center" }: SectionHeadingProps) {
  const light = tone === "light";
  return (
    <Reveal className={align === "center" ? "mx-auto max-w-2xl text-center" : "max-w-xl"}>
      {eyebrow && <p className={`eyebrow mb-4 ${light ? "text-white/75" : "text-muted"}`}>{eyebrow}</p>}
      <h2
        id={id}
        className={`text-[clamp(2rem,4.4vw,3.25rem)] leading-[1.05] font-semibold tracking-[-0.035em] ${
          light ? "text-white" : "text-ink"
        }`}
      >
        {title}
      </h2>
      {body && (
        <p className={`mt-4 text-lg leading-relaxed ${light ? "text-white/80" : "text-muted"}`}>{body}</p>
      )}
    </Reveal>
  );
}
