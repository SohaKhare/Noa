import type { ReactNode } from "react";
import { cdnAsset } from "@/lib/cdn";
import Image from "next/image";
import { Reveal } from "./Reveal";
import { SectionHeading } from "./SectionHeading";
import { ApproveChip, ConnectChip, TalkChip } from "./StepChips";

function StepCard({
  number,
  title,
  body,
  chip,
  image,
  delay = 0,
  className = "",
}: {
  number: string;
  title: string;
  body: string;
  chip: ReactNode;
  image: string;
  delay?: number;
  className?: string;
}) {
  return (
    <Reveal delay={delay} className={className}>
      <article>
        <div className="relative isolate aspect-square overflow-hidden rounded-card">
          <Image src={image} alt="" fill sizes="(min-width: 1024px) 33vw, (min-width: 640px) 50vw, 100vw" className="object-cover" />
          <div className="absolute inset-x-5 bottom-5">{chip}</div>
        </div>
        <div className="mt-6 flex items-baseline gap-3">
          <span className="font-mono text-[13px] text-accent-fg">{number}</span>
          <h3 className="text-2xl font-semibold tracking-tight">{title}</h3>
        </div>
        <p className="mt-2 max-w-sm text-[15px] leading-relaxed text-muted">{body}</p>
      </article>
    </Reveal>
  );
}

export function Steps() {
  return (
    <section id="how" aria-labelledby="how-title" className="mx-auto max-w-7xl px-5 py-28">
      <SectionHeading
        id="how-title"
        eyebrow="How it works"
        title="Set up Noa in ten minutes."
        body="Map your channels to projects. Then keep talking the way you already do."
      />
      <div className="mt-12 grid gap-12 sm:grid-cols-2 lg:grid-cols-3 lg:gap-8">
        <StepCard
          number="01"
          title="Connect"
          body="Discord, Slack, Meet and WhatsApp. Pick which channels belong to which project. DMs are never read."
          image={cdnAsset("/night.jpg")}
          chip={<ConnectChip />}
        />
        <StepCard
          number="02"
          title="Talk as usual"
          body="Noa turns replies, meetings and voice notes into tasks, deadlines and decisions. Ask @noa anything, anywhere."
          image={cdnAsset("/night-water.jpg")}
          chip={<TalkChip />}
          delay={0.08}
          className="lg:mt-20"
        />
        <StepCard
          number="03"
          title="Stay in control"
          body="Small updates apply with undo. Scope and deadline changes wait for the right lead."
          image={cdnAsset("/night.jpg")}
          chip={<ApproveChip />}
          delay={0.16}
          className="sm:col-span-2 sm:mx-auto sm:max-w-md lg:col-span-1 lg:mt-40 lg:max-w-none"
        />
      </div>
    </section>
  );
}
