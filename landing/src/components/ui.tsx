import type { ReactNode } from "react";

/* Small presentational pieces shared by the animated scenes. */

export function Window({
  title,
  children,
  className = "",
  bar,
}: {
  title?: string;
  children: ReactNode;
  className?: string;
  bar?: ReactNode;
}) {
  return (
    <div className={`overflow-hidden rounded-[22px] bg-surface card-shadow ${className}`}>
      <div className="flex h-10 items-center gap-2 border-b border-line/80 px-4">
        <span className="size-2.5 rounded-full bg-line" />
        <span className="size-2.5 rounded-full bg-line" />
        <span className="size-2.5 rounded-full bg-line" />
        {title && <span className="ml-3 text-[12px] font-medium text-muted">{title}</span>}
        <span className="ml-auto">{bar}</span>
      </div>
      {children}
    </div>
  );
}

export function Avatar({ initials, tone = "mist" }: { initials: string; tone?: "mist" | "accent" | "signal" }) {
  const cls =
    tone === "accent" ? "bg-accent text-white" : tone === "signal" ? "bg-signal text-white" : "bg-mist text-accent-fg";
  return (
    <span className={`grid size-7 shrink-0 place-items-center rounded-full text-[10px] font-semibold ${cls}`}>
      {initials}
    </span>
  );
}

export function Pill({ children, tone = "ghost" }: { children: ReactNode; tone?: "accent" | "ghost" | "mist" }) {
  const cls =
    tone === "accent" ? "bg-accent text-white" : tone === "mist" ? "bg-mist text-accent-fg" : "bg-bg text-ink";
  return <span className={`rounded-full px-3 py-1.5 text-center text-[12px] font-medium ${cls}`}>{children}</span>;
}

export function SourceChip({ children }: { children: ReactNode }) {
  return (
    <span className="inline-flex items-center gap-1 rounded-full bg-bg px-2 py-0.5 font-mono text-[10.5px] text-muted">
      {children}
    </span>
  );
}

export function LiveDot({ className = "" }: { className?: string }) {
  return <span className={`inline-block size-1.5 animate-pulse-dot rounded-full bg-signal ${className}`} />;
}

export function NoaAvatar() {
  return (
    <span className="grid size-7 shrink-0 place-items-center rounded-full bg-accent text-[11px] font-semibold text-white">
      N
    </span>
  );
}
