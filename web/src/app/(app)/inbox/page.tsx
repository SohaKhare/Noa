"use client";

import {
  ArrowRightIcon,
  CalendarBlankIcon,
  CheckIcon,
  FolderSimpleIcon,
  LightningIcon,
  QuotesIcon,
  UserIcon,
  XIcon,
} from "@phosphor-icons/react";
import { AnimatePresence, motion } from "motion/react";
import { useEffect, useState } from "react";
import { Avatar, Badge, Button, SourceChip } from "@/components/ui";
import { cn } from "@/lib/cn";
import { people, project, projects, proposals as seed, type Proposal } from "@/lib/mock";

/* Inbox (1.19): two panes. Left: proposals with filters. Right: the source and the fields Noa extracted, editable before approval. */

const kindLabel: Record<Proposal["kind"], string> = {
  new_task: "New task",
  status: "Status",
  deadline: "Deadline",
  route: "Which project?",
};
const filters = ["All", "New task", "Status", "Deadline", "Which project?"] as const;

export default function Inbox() {
  const [items, setItems] = useState(seed);
  const [filter, setFilter] = useState<(typeof filters)[number]>("All");
  const [selected, setSelected] = useState(seed[0]?.id);
  const [log, setLog] = useState<string[]>([]);

  const visible = items.filter((p) => filter === "All" || kindLabel[p.kind] === filter);
  const current = items.find((p) => p.id === selected) ?? visible[0];
  const confident = items.filter((p) => p.confidence >= 0.8);

  const resolve = (id: string, verb: string) => {
    const p = items.find((x) => x.id === id);
    if (!p) return;
    setLog((l) => [`${verb}: ${p.summary}`, ...l].slice(0, 4));
    const rest = items.filter((x) => x.id !== id);
    setItems(rest);
    setSelected(rest[0]?.id);
  };

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const t = e.target as HTMLElement;
      if (!current || e.metaKey || e.ctrlKey || ["INPUT", "SELECT", "TEXTAREA"].includes(t.tagName)) return;
      if (e.key === "a") resolve(current.id, current.kind === "route" ? `Routed to ${project(current.project ?? current.options?.[0])?.name}` : "Approved");
      if (e.key === "r") resolve(current.id, "Rejected");
      if (e.key === "j" || e.key === "k") {
        const i = visible.findIndex((x) => x.id === current.id);
        const next = visible[Math.min(visible.length - 1, Math.max(0, i + (e.key === "j" ? 1 : -1)))];
        if (next) setSelected(next.id);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  });

  return (
    <div className="mx-auto max-w-6xl">
      <div className="mb-5 flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-[26px] leading-tight font-semibold tracking-[-0.03em]">Inbox</h1>
          <p className="mt-1 text-[14px] text-muted">
            {items.length} proposals from your channels and meetings. Confident status updates skip the inbox, with undo.
          </p>
        </div>
        <Button disabled={confident.length === 0} onClick={() => confident.forEach((p) => resolve(p.id, "Approved"))}>
          <LightningIcon size={14} weight="fill" /> Approve high-confidence ({confident.length})
        </Button>
      </div>

      <div className="grid min-h-[560px] overflow-hidden rounded-[22px] bg-surface card-shadow lg:grid-cols-[380px_1fr]">
        <div className="flex flex-col border-b border-line lg:border-r lg:border-b-0">
          <div className="no-scrollbar flex gap-1 overflow-x-auto border-b border-line p-2">
            {filters.map((f) => (
              <button
                key={f}
                onClick={() => setFilter(f)}
                className={cn(
                  "shrink-0 rounded-full px-3 py-1.5 text-[12px] font-medium transition-colors",
                  filter === f ? "bg-mist text-ink" : "text-muted hover:bg-bg hover:text-ink",
                )}
              >
                {f}
              </button>
            ))}
          </div>
          <ul className="flex-1 divide-y divide-line overflow-y-auto">
            <AnimatePresence initial={false}>
              {visible.map((p) => (
                <motion.li key={p.id} layout exit={{ opacity: 0, x: -20, transition: { duration: 0.18 } }}>
                  <button
                    onClick={() => setSelected(p.id)}
                    className={cn(
                      "flex w-full flex-col gap-1.5 px-4 py-3.5 text-left transition-colors",
                      current?.id === p.id ? "bg-mist/60" : "hover:bg-bg",
                    )}
                  >
                    <span className="flex items-center gap-2">
                      <Badge tone={p.kind === "route" ? "warn" : "accent"}>{kindLabel[p.kind]}</Badge>
                      <span className="ml-auto font-mono text-[10.5px] text-muted">{Math.round(p.confidence * 100)}%</span>
                    </span>
                    <span className="text-[13.5px] font-medium">{p.summary}</span>
                    <SourceChip source={p.source} />
                  </button>
                </motion.li>
              ))}
            </AnimatePresence>
            {visible.length === 0 && <li className="px-4 py-10 text-center text-[13px] text-muted">Nothing here. Noa will add proposals as people talk.</li>}
          </ul>
        </div>

        <div className="wash p-6">
          {current ? (
            <Detail key={current.id} p={current} onResolve={resolve} />
          ) : (
            <div className="grid h-full place-items-center text-center">
              <div>
                <p className="text-[16px] font-semibold">All caught up</p>
                <p className="mt-1 text-[13px] text-muted">New proposals appear here as people talk.</p>
              </div>
            </div>
          )}
        </div>
      </div>

      {log.length > 0 && (
        <ul className="mt-4 space-y-1">
          {log.map((l) => (
            <li key={l} className="flex items-center gap-2 text-[12.5px] text-muted">
              <CheckIcon size={12} className="text-good" /> {l}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function Detail({ p, onResolve }: { p: Proposal; onResolve: (id: string, verb: string) => void }) {
  const [owner, setOwner] = useState("ve");
  const [due, setDue] = useState("Fri");
  const [proj, setProj] = useState(p.project ?? p.options?.[0] ?? "a");

  return (
    <div className="mx-auto max-w-xl">
      <Badge tone={p.kind === "route" ? "warn" : "accent"}>{kindLabel[p.kind]}</Badge>
      <h2 className="mt-3 text-[20px] font-semibold tracking-tight">{p.summary}</h2>

      <div className="mt-5 rounded-2xl bg-surface p-4 ring-1 ring-line">
        <p className="flex items-center gap-1.5 text-[11.5px] font-medium text-muted">
          <QuotesIcon size={13} /> From the conversation
        </p>
        <div className="mt-2.5 flex items-start gap-2.5">
          <Avatar initials={p.source.kind === "whatsapp" ? "AB" : "VE"} size={26} />
          <div>
            <p className="text-[12px] font-semibold">
              {p.source.kind === "whatsapp" ? "Abhishek" : "Vedant"} <span className="font-normal text-muted">{p.source.when}</span>
            </p>
            <p className="mt-0.5 text-[13.5px]">{p.source.quote ?? "Message text from the source thread."}</p>
          </div>
        </div>
        <div className="mt-3">
          <SourceChip source={p.source} />
        </div>
      </div>

      <div className="mt-5 grid gap-3 sm:grid-cols-3">
        <Field label="Project" Icon={FolderSimpleIcon}>
          <select value={proj} onChange={(e) => setProj(e.target.value)} className="w-full bg-transparent text-[13px] font-medium focus:outline-none">
            {projects.map((x) => (
              <option key={x.id} value={x.id}>
                {x.name}
              </option>
            ))}
          </select>
        </Field>
        <Field label="Owner" Icon={UserIcon}>
          <select value={owner} onChange={(e) => setOwner(e.target.value)} className="w-full bg-transparent text-[13px] font-medium focus:outline-none">
            {people.map((x) => (
              <option key={x.id} value={x.id}>
                {x.name}
              </option>
            ))}
          </select>
        </Field>
        <Field label="Due" Icon={CalendarBlankIcon}>
          <input value={due} onChange={(e) => setDue(e.target.value)} className="w-full bg-transparent text-[13px] font-medium focus:outline-none" />
        </Field>
      </div>

      <p className="mt-4 text-[12px] text-muted">
        Noa is {Math.round(p.confidence * 100)}% sure. Approving adds it to {project(proj)?.name} and notifies the owner. Every change keeps a link to this message.
      </p>

      <div className="mt-6 flex flex-wrap gap-2">
        <Button onClick={() => onResolve(p.id, p.kind === "route" ? `Routed to ${project(proj)?.name}` : "Approved")}>
          <CheckIcon size={14} weight="bold" /> {p.kind === "route" ? "Route" : "Approve"} <ArrowRightIcon size={13} />
        </Button>
        <Button variant="ghost" onClick={() => onResolve(p.id, "Rejected")}>
          <XIcon size={14} /> Reject
        </Button>
        <span className="ml-auto self-center text-[11.5px] text-muted">
          <kbd className="rounded bg-surface px-1.5 font-mono ring-1 ring-line">A</kbd> approve · <kbd className="rounded bg-surface px-1.5 font-mono ring-1 ring-line">R</kbd> reject · <kbd className="rounded bg-surface px-1.5 font-mono ring-1 ring-line">J</kbd>/<kbd className="rounded bg-surface px-1.5 font-mono ring-1 ring-line">K</kbd> move
        </span>
      </div>
    </div>
  );
}

function Field({ label, Icon, children }: { label: string; Icon: typeof UserIcon; children: React.ReactNode }) {
  return (
    <label className="block rounded-xl bg-surface px-3 py-2.5 ring-1 ring-line focus-within:ring-accent/40">
      <span className="flex items-center gap-1 text-[11px] text-muted">
        <Icon size={12} /> {label}
      </span>
      <span className="mt-1 block">{children}</span>
    </label>
  );
}
