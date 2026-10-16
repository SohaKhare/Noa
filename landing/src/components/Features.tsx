import {
  CheckIcon,
  DiscordLogoIcon,
  LockSimpleIcon,
  QuotesIcon,
  SlackLogoIcon,
  UsersThreeIcon,
  VideoCameraIcon,
  WhatsappLogoIcon,
} from "@phosphor-icons/react/ssr";
import type { ReactNode } from "react";
import { LiveFeed } from "./LiveFeed";
import { Reveal } from "./Reveal";
import { SectionHeading } from "./SectionHeading";

/* Elf's FeatureBento layout on clean panels: no photos. Washed cells, a tinted proposal cell, a facts cell. */

export function Cell({ className = "", children, delay = 0 }: { className?: string; children: ReactNode; delay?: number }) {
  return (
    <Reveal delay={delay} className={`relative isolate flex min-h-[380px] flex-col overflow-hidden rounded-card p-7 sm:p-9 ${className}`}>
      {children}
    </Reveal>
  );
}

export function CellText({ title, body, tone = "ink" }: { title: string; body: string; tone?: "ink" | "light" | "accent" }) {
  const t = tone === "light" ? "text-white" : tone === "accent" ? "text-accent-fg" : "text-ink";
  const b = tone === "light" ? "text-white/80" : tone === "accent" ? "text-accent-fg/75" : "text-muted";
  return (
    <div>
      <h3 className={`text-2xl font-semibold tracking-tight ${t}`}>{title}</h3>
      <p className={`mt-2 max-w-md text-[15px] leading-relaxed ${b}`}>{body}</p>
    </div>
  );
}

/* Clean wash used where Elf had a photo. */
export function Wash() {
  return (
    <>
      <div aria-hidden className="absolute inset-0 -z-10 bg-[linear-gradient(180deg,#dbe6f3,#f3f5f8_80%)]" />
      <div aria-hidden className="dot-grid absolute inset-0 -z-10" />
    </>
  );
}

const sources = [
  { label: "Discord", Icon: DiscordLogoIcon },
  { label: "Slack", Icon: SlackLogoIcon },
  { label: "Meet", Icon: VideoCameraIcon },
  { label: "WhatsApp", Icon: WhatsappLogoIcon },
];

const learned = [
  { k: "Who knows the PDF renderer", v: "Saish" },
  { k: "“The film app” means", v: "Emmarie" },
  { k: "Decided today", v: "3 decisions" },
];

const privacy = [
  { Icon: UsersThreeIcon, title: "Only mapped channels", body: "Admins choose what Noa reads. Direct messages, never." },
  { Icon: QuotesIcon, title: "Every answer cited", body: "Each task and decision links to the message it came from." },
  { Icon: LockSimpleIcon, title: "Permission-aware", body: "Answers only use what the person asking may see." },
];

export function FeatureBento() {
  return (
    <section id="features" aria-labelledby="bento-title" className="mx-auto max-w-7xl px-5 py-28">
      <SectionHeading
        id="bento-title"
        title="Always current. Never in the way."
        body="The brain that knows every project and gets sharper the more your team talks."
      />

      <div className="mt-14 grid gap-4 lg:grid-cols-12">
        <Cell className="lg:col-span-7">
          <Wash />
          <LiveFeed size="sm" className="max-w-md" />
          <div className="glass mt-6 w-fit max-w-full rounded-chip p-2 text-ink">
            <ul className="flex flex-wrap gap-1.5">
              {sources.map(({ label, Icon }) => (
                <li key={label} className="flex items-center gap-1.5 rounded-[12px] bg-white/80 px-3 py-2 text-[12px] font-medium">
                  <Icon size={15} className="text-accent-fg" /> {label}
                </li>
              ))}
            </ul>
          </div>
          <div className="mt-6">
            <CellText title="Always up to speed" body="Chats, meetings and voice notes become tasks, owners, deadlines and decisions as they happen." />
          </div>
        </Cell>

        <Cell className="bg-mist lg:col-span-5" delay={0.06}>
          <div className="rounded-[20px] bg-surface p-4 card-shadow">
            <p className="text-[12px] font-medium text-muted">Deadline change · needs your approval</p>
            <p className="mt-1 text-[15px] font-semibold">Board report PDF: Fri → Mon?</p>
            <p className="text-[13px] text-muted">Saish: &ldquo;waiting on the logo pack&rdquo; · #veriq</p>
            <div className="mt-3 flex gap-2">
              <span className="flex-1 rounded-full bg-accent py-2 text-center text-[13px] font-medium text-white">Approve</span>
              <span className="flex-1 rounded-full bg-bg py-2 text-center text-[13px] font-medium">Discuss</span>
            </div>
          </div>
          <div className="mt-auto pt-8">
            <CellText tone="accent" title="Never in the way" body="Small updates apply with undo. Scope and deadline changes wait for the right lead." />
          </div>
        </Cell>

        <Cell className="bg-surface ring-1 ring-black/[0.04] lg:col-span-5" delay={0.04}>
          <ul className="space-y-2">
            {learned.map((row) => (
              <li key={row.k} className="flex items-center justify-between gap-3 rounded-[14px] bg-bg px-4 py-3 text-[14px]">
                <span className="text-muted">{row.k}</span>
                <span className="flex items-center gap-1.5 font-semibold">
                  <CheckIcon size={14} weight="bold" className="text-accent-fg" /> {row.v}
                </span>
              </li>
            ))}
          </ul>
          <div className="mt-auto pt-8">
            <CellText title="Smarter every day" body="It learns who knows what, the names your team uses, and what changed while you were out." />
          </div>
        </Cell>

        <Cell className="lg:col-span-7" delay={0.1}>
          <div id="privacy" className="absolute -top-24" aria-hidden />
          <Wash />
          <h3 className="text-2xl font-semibold tracking-tight">Your team&apos;s context stays yours.</h3>
          <ul className="mt-auto grid gap-3 pt-8 sm:grid-cols-3">
            {privacy.map(({ Icon, title, body }) => (
              <li key={title} className="rounded-[20px] bg-surface p-4 card-shadow">
                <Icon size={22} className="text-accent" />
                <p className="mt-3 text-[15px] font-semibold">{title}</p>
                <p className="mt-1 text-[13px] leading-relaxed text-muted">{body}</p>
              </li>
            ))}
          </ul>
        </Cell>
      </div>
    </section>
  );
}
