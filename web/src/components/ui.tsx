import {
  ChatsCircleIcon,
  DiscordLogoIcon,
  GithubLogoIcon,
  SlackLogoIcon,
  VideoCameraIcon,
  WhatsappLogoIcon,
} from "@phosphor-icons/react/ssr";
import type { ComponentProps, ReactNode } from "react";
import { cn } from "@/lib/cn";
import type { Source } from "@/lib/mock";

/* Design kit primitives (item 0.18). Built on the shared tokens in @noa/theme. */

type ButtonProps = ComponentProps<"button"> & { variant?: "primary" | "ghost" | "mist" | "quiet"; size?: "sm" | "md" };

export function Button({ variant = "primary", size = "md", className, ...props }: ButtonProps) {
  return (
    <button
      className={cn(
        "inline-flex items-center justify-center gap-1.5 rounded-full font-medium whitespace-nowrap transition-[background-color,transform,color] duration-200 active:scale-[0.98] disabled:opacity-50",
        size === "sm" ? "px-3 py-1.5 text-[12px]" : "px-4 py-2 text-[13.5px]",
        variant === "primary" && "bg-accent text-white hover:bg-accent-soft",
        variant === "ghost" && "bg-surface text-ink ring-1 ring-line hover:bg-bg",
        variant === "mist" && "bg-mist text-accent-fg hover:bg-white",
        variant === "quiet" && "text-ink/70 hover:bg-black/5 hover:text-ink",
        className,
      )}
      {...props}
    />
  );
}

export function Card({ className, children }: { className?: string; children: ReactNode }) {
  return <div className={cn("rounded-[22px] bg-surface p-5 card-shadow", className)}>{children}</div>;
}

export function Avatar({ initials, size = 28, tone = "mist" }: { initials: string; size?: number; tone?: "mist" | "accent" }) {
  return (
    <span
      style={{ width: size, height: size, fontSize: size * 0.36 }}
      className={cn(
        "grid shrink-0 place-items-center rounded-full font-semibold",
        tone === "accent" ? "bg-accent text-white" : "bg-mist text-accent-fg",
      )}
    >
      {initials}
    </span>
  );
}

const tones = {
  neutral: "bg-bg text-ink/75",
  accent: "bg-mist text-accent-fg",
  good: "bg-good/10 text-good",
  warn: "bg-warn/12 text-warn",
  bad: "bg-bad/10 text-bad",
  signal: "bg-signal/12 text-signal",
};

export function Badge({ tone = "neutral", children, className }: { tone?: keyof typeof tones; children: ReactNode; className?: string }) {
  return <span className={cn("inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-[11px] font-medium", tones[tone], className)}>{children}</span>;
}

const sourceIcon = {
  discord: DiscordLogoIcon,
  slack: SlackLogoIcon,
  meet: VideoCameraIcon,
  whatsapp: WhatsappLogoIcon,
  github: GithubLogoIcon,
};

export function SourceChip({ source, withQuote = false }: { source: Source; withQuote?: boolean }) {
  const Icon = sourceIcon[source.kind] ?? ChatsCircleIcon;
  return (
    <span className="inline-flex max-w-full items-center gap-1.5 rounded-full bg-bg px-2 py-0.5 font-mono text-[10.5px] text-muted">
      <Icon size={11} />
      <span className="truncate">
        {source.where} · {source.when}
        {withQuote && source.quote ? ` · “${source.quote}”` : ""}
      </span>
    </span>
  );
}

export function PageHeader({ title, sub, actions }: { title: string; sub?: string; actions?: ReactNode }) {
  return (
    <div className="mb-6 flex flex-wrap items-end justify-between gap-4">
      <div>
        <h1 className="text-[26px] leading-tight font-semibold tracking-[-0.03em]">{title}</h1>
        {sub && <p className="mt-1 text-[14px] text-muted">{sub}</p>}
      </div>
      {actions && <div className="flex items-center gap-2">{actions}</div>}
    </div>
  );
}

export function Eyebrow({ children }: { children: ReactNode }) {
  return <p className="eyebrow mb-2 text-muted">{children}</p>;
}
