"use client";

import {
  ArrowRightIcon,
  CalendarBlankIcon,
  CheckIcon,
  FolderSimpleIcon,
  LightningIcon,
  GraphIcon,
  QuotesIcon,
  SparkleIcon,
  UserIcon,
  XIcon,
} from "@phosphor-icons/react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { AnimatePresence, motion } from "motion/react";
import { useEffect, useState } from "react";
import { FormError } from "@/components/AuthCard";
import { Avatar, Badge, Button, SourceChip } from "@/components/ui";
import { ApiError, approveProposal, getProposals, rejectProposal, runTriage, undoProposal, type ApproveEdits, type WorkProposal, type WorkTask } from "@/lib/api";
import { cn } from "@/lib/cn";
import { ago, changeText, dueLabel, nameInitials, toSource, useChanges, useDecideChange, useDirectory, useProposals, useTasks } from "@/lib/work";

/* Inbox (1.19): two panes. Left: proposals with filters. Right: the source and the fields Noa extracted, editable before approval. */

type Label = "New task" | "Status" | "Deadline" | "Decision" | "Scope" | "Assign" | "Which project?";
const label = (p: WorkProposal): Label =>
  !p.project_id && p.kind === "task"
    ? "Which project?"
    : ({ task: "New task", status_change: "Status", deadline_change: "Deadline", decision: "Decision", scope_change: "Scope", assignment: "Assign" } as const)[p.kind];
const filters = ["All", "New task", "Status", "Deadline", "Assign", "Which project?"] as const;

export default function Inbox() {
  const { orgId, project } = useDirectory();
  const { data: items = [], isLoading, error } = useProposals();
  const client = useQueryClient();
  const [filter, setFilter] = useState<(typeof filters)[number]>("All");
  const [selected, setSelected] = useState<string>();
  const [log, setLog] = useState<string[]>([]);

  const visible = items.filter((p) => filter === "All" || label(p) === filter);
  const current = items.find((p) => p.id === selected) ?? visible[0];
  const confident = items.filter((p) => (p.confidence ?? 0) >= 0.8 && p.project_id);

  const decide = useMutation({
    mutationFn: ({ p, verb, edits }: { p: WorkProposal; verb: "approve" | "reject"; edits?: ApproveEdits }) =>
      verb === "approve" ? approveProposal(orgId!, p.id, edits) : rejectProposal(orgId!, p.id),
    onSuccess: (r, { p, verb }) => {
      const task = (r as { task?: WorkTask | null }).task ?? null;
      const where = task ? ` · ${project(task.project_id)?.name}` : "";
      setLog((l) => [`${verb === "approve" ? "Approved" : "Dismissed"}: ${p.summary}${where}`, ...l].slice(0, 4));
      const rest = visible.filter((x) => x.id !== p.id);
      setSelected(rest[0]?.id);
      client.invalidateQueries({ queryKey: ["proposals", orgId] });
      client.invalidateQueries({ queryKey: ["tasks", orgId] });
      client.invalidateQueries({ queryKey: ["decisions", orgId] });
    },
  });

  const resolve = (p: WorkProposal, verb: "approve" | "reject", edits?: ApproveEdits) => decide.mutate({ p, verb, edits });

  /* Triage (3.24): leads ask Noa to find work nobody is carrying and suggest owners from the graph. */
  const dir = useDirectory();
  const me = dir.person(dir.me);
  const canTriage = me?.role === "org_admin" || me?.role === "pm" || dir.projects.some((x) => x.lead_id === me?.id);
  const bulk = confident.filter((p) => p.kind !== "assignment");
  const triage = useMutation({
    mutationFn: () => runTriage(orgId!),
    onSuccess: (r) => {
      const n = r.proposals.length;
      setLog((l) => [n ? `Noa filed ${n} owner ${n === 1 ? "suggestion" : "suggestions"}` : "Every open task has an owner who is on its project", ...l].slice(0, 4));
      if (r.proposals[0]) setSelected(r.proposals[0].id);
      client.invalidateQueries({ queryKey: ["proposals", orgId] });
    },
  });

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const t = e.target as HTMLElement;
      if (!current || decide.isPending || e.metaKey || e.ctrlKey || ["INPUT", "SELECT", "TEXTAREA"].includes(t.tagName)) return;
      if (e.key === "a" && current.project_id) resolve(current, "approve");
      if (e.key === "r") resolve(current, "reject");
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
            {isLoading ? "Loading…" : `${items.length} ${items.length === 1 ? "proposal" : "proposals"} from your channels and meetings.`} Approving one puts it on the
            project&rsquo;s board.
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          {canTriage && (
            <Button variant="ghost" disabled={triage.isPending} onClick={() => triage.mutate()}>
              <SparkleIcon size={14} weight="fill" /> {triage.isPending ? "Looking…" : "Find unowned work"}
            </Button>
          )}
          <Button disabled={bulk.length === 0 || decide.isPending} onClick={() => bulk.forEach((p) => resolve(p, "approve"))}>
            <LightningIcon size={14} weight="fill" /> Approve high-confidence ({bulk.length})
          </Button>
        </div>
      </div>

      {(error || decide.error || triage.error) && (
        <div className="mb-4">
          <FormError>{((decide.error ?? triage.error ?? error) as ApiError).message}</FormError>
        </div>
      )}

      <ChangeRequests />
      <AutoApplied />

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
                      <Badge tone={label(p) === "Which project?" ? "warn" : "accent"}>{label(p)}</Badge>
                      {p.data.duplicate_of && <Badge tone="warn">Duplicate?</Badge>}
                      {project(p.project_id) && <span className="text-[11.5px] text-muted">{project(p.project_id)!.name}</span>}
                      {p.confidence != null && <span className="ml-auto font-mono text-[10.5px] text-muted">{Math.round(p.confidence * 100)}%</span>}
                    </span>
                    <span className="text-[13.5px] font-medium">{p.summary}</span>
                    <SourceChip source={toSource(p.source)} />
                  </button>
                </motion.li>
              ))}
            </AnimatePresence>
            {!isLoading && visible.length === 0 && <li className="px-4 py-10 text-center text-[13px] text-muted">Nothing here. Noa will add proposals as people talk.</li>}
          </ul>
        </div>

        <div className="wash p-6">
          {current ? (
            <Detail key={current.id} p={current} busy={decide.isPending} onResolve={resolve} />
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

function Detail({
  p,
  busy,
  onResolve,
}: {
  p: WorkProposal;
  busy: boolean;
  onResolve: (p: WorkProposal, verb: "approve" | "reject", edits?: ApproveEdits) => void;
}) {
  const { projects, people, project, person } = useDirectory();
  const isTask = p.kind === "task";
  const isAssign = p.kind === "assignment";
  const dueKey = p.kind === "deadline_change" ? "new_due" : "due";
  const [title, setTitle] = useState(p.data.title ?? p.summary);
  const [owner, setOwner] = useState(p.owner_id ?? "");
  const [due, setDue] = useState((p.data[dueKey] as string | undefined) ?? "");
  const [proj, setProj] = useState(p.project_id ?? "");
  const source = toSource(p.source);
  const candidates = p.data.route?.candidates ?? [];
  const lbl = label(p);

  const edits = (): ApproveEdits => ({
    project_id: proj || undefined,
    owner_id: owner || undefined,
    ...(isTask ? { summary: title, data: { title, due: due || undefined } } : {}),
    ...(p.kind === "deadline_change" && due ? { data: { new_due: due } } : {}),
  });

  return (
    <div className="mx-auto max-w-xl">
      <Badge tone={lbl === "Which project?" ? "warn" : "accent"}>{lbl}</Badge>
      {isTask ? (
        <input
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          aria-label="Title"
          className="mt-3 w-full rounded-lg bg-transparent text-[20px] font-semibold tracking-tight hover:bg-surface/60 focus:bg-surface focus:ring-2 focus:ring-accent/30 focus:outline-none"
        />
      ) : (
        <h2 className="mt-3 text-[20px] font-semibold tracking-tight">{p.summary}</h2>
      )}

      {p.data.duplicate_of && (
        <div className="mt-4 flex flex-wrap items-center gap-3 rounded-2xl bg-warn/10 px-4 py-3 text-[13px] ring-1 ring-warn/20">
          <span className="min-w-0 flex-1">
            Looks like <span className="font-medium">{p.data.duplicate_of.title}</span>, which is already on the board.
          </span>
          <Button size="sm" variant="ghost" disabled={busy} onClick={() => onResolve(p, "reject")}>
            Same task, dismiss
          </Button>
        </div>
      )}

      {isAssign ? (
        <Why p={p} />
      ) : (
        <div className="mt-5 rounded-2xl bg-surface p-4 ring-1 ring-line">
          <p className="flex items-center gap-1.5 text-[11.5px] font-medium text-muted">
            <QuotesIcon size={13} /> From the conversation
          </p>
          <div className="mt-2.5 flex items-start gap-2.5">
            <Avatar initials={nameInitials(p.source?.author)} size={26} />
            <div>
              <p className="text-[12px] font-semibold">
                {p.source?.author ?? "Someone"} <span className="font-normal text-muted">{source.when}</span>
              </p>
              <p className="mt-0.5 text-[13.5px]">{p.source?.quote ?? "No message text was kept for this one."}</p>
            </div>
          </div>
          <div className="mt-3">
            <SourceChip source={source} />
          </div>
        </div>
      )}

      {lbl === "Which project?" && candidates.length > 0 && (
        <p className="mt-4 text-[12.5px] text-muted">
          Noa couldn&rsquo;t tell which project this is for. It might be {candidates.map((c) => project(c)?.name ?? c).join(" or ")}.
        </p>
      )}

      <div className="mt-5 grid gap-3 sm:grid-cols-3">
        <Field label="Project" Icon={FolderSimpleIcon}>
          <select value={proj} onChange={(e) => setProj(e.target.value)} className="w-full bg-transparent text-[13px] font-medium focus:outline-none">
            <option value="">Pick a project</option>
            {projects.map((x) => (
              <option key={x.id} value={x.id}>
                {x.name}
              </option>
            ))}
          </select>
        </Field>
        <Field label="Owner" Icon={UserIcon}>
          <select value={owner} onChange={(e) => setOwner(e.target.value)} className="w-full bg-transparent text-[13px] font-medium focus:outline-none">
            <option value="">Nobody yet</option>
            {people.map((x) => (
              <option key={x.id} value={x.id}>
                {x.name}
              </option>
            ))}
          </select>
        </Field>
        {(isTask || p.kind === "deadline_change") && (
          <Field label={p.kind === "deadline_change" ? "New due date" : "Due"} Icon={CalendarBlankIcon}>
            <input type="date" value={due} onChange={(e) => setDue(e.target.value)} className="w-full bg-transparent text-[13px] font-medium focus:outline-none" />
          </Field>
        )}
      </div>

      <p className="mt-4 text-[12px] text-muted">
        {p.confidence != null && `Noa is ${Math.round(p.confidence * 100)}% sure. `}
        {!proj
          ? "Pick a project to approve it."
          : isAssign
            ? `Approving gives it to ${person(owner)?.name ?? "nobody"} and tells them. It\u2019s recorded as an owner change and can be reverted.`
            : p.kind === "decision"
              ? `Approving records this decision in ${project(proj)?.name}${owner ? `, made by ${person(owner)?.name}` : ""}.`
            : `Approving ${isTask ? "adds it to" : "updates"} ${project(proj)?.name}${owner ? ` and tells ${person(owner)?.name}` : ""}${due ? `, due ${dueLabel(due)}` : ""}.`}{" "}
        {isAssign ? null : p.kind === "decision" ? "It keeps a link to this message." : "The task keeps a link to this message."}
      </p>

      <div className="mt-6 flex flex-wrap gap-2">
        <Button disabled={busy || !proj} onClick={() => onResolve(p, "approve", edits())}>
          <CheckIcon size={14} weight="bold" /> Approve <ArrowRightIcon size={13} />
        </Button>
        <Button variant="ghost" disabled={busy} onClick={() => onResolve(p, "reject")}>
          <XIcon size={14} /> Dismiss
        </Button>
        <span className="ml-auto self-center text-[11.5px] text-muted">
          <kbd className="rounded bg-surface px-1.5 font-mono ring-1 ring-line">A</kbd> approve · <kbd className="rounded bg-surface px-1.5 font-mono ring-1 ring-line">R</kbd> dismiss · <kbd className="rounded bg-surface px-1.5 font-mono ring-1 ring-line">J</kbd>/<kbd className="rounded bg-surface px-1.5 font-mono ring-1 ring-line">K</kbd> move
        </span>
      </div>
    </div>
  );
}

/* Why Noa suggests this owner: the trigger, the reasons, and the graph route behind them (3.24). */
function Why({ p }: { p: WorkProposal }) {
  const { person } = useDirectory();
  const others = (p.data.candidates ?? []).filter((c) => c.person_id !== p.owner_id);
  const route = p.data.graph_route ?? [];
  return (
    <div className="mt-5 rounded-2xl bg-surface p-4 ring-1 ring-line">
      <p className="flex items-center gap-1.5 text-[11.5px] font-medium text-muted">
        <SparkleIcon size={13} /> Why Noa suggests {person(p.owner_id)?.name ?? "this"}
      </p>
      <p className="mt-2 text-[13.5px]">{p.data.reason}</p>
      <ul className="mt-2.5 space-y-1">
        {(p.data.why ?? []).map((w) => (
          <li key={w} className="flex gap-2 text-[13px]">
            <CheckIcon size={13} className="mt-0.5 shrink-0 text-accent" /> {w}
          </li>
        ))}
      </ul>
      {route.length > 0 && (
        <div className="mt-3 rounded-xl bg-bg px-3 py-2.5">
          <p className="flex items-center gap-1.5 text-[11px] font-medium text-muted">
            <GraphIcon size={12} /> {p.data.graph ? "Graph route (FalkorDB)" : "From allocations (graph not built yet)"}
          </p>
          <ul className="mt-1.5 space-y-0.5 font-mono text-[11px] break-words text-muted">
            {route.map((r) => (
              <li key={r}>{r}</li>
            ))}
          </ul>
        </div>
      )}
      {others.length > 0 && <p className="mt-3 text-[12px] text-muted">Next best: {others.map((c) => c.name).join(", ")}. Pick someone else under Owner.</p>}
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

/* Changes waiting for a lead (2.20): deadline and scope edits made by someone else. */
function ChangeRequests() {
  const dir = useDirectory();
  const me = dir.person(dir.me);
  const pending = useChanges({ status: "pending" }).data ?? [];
  const tasks = useTasks({}).data ?? [];
  const decide = useDecideChange();
  const orgLead = me?.role === "org_admin" || me?.role === "pm";
  const mine = pending.filter((c) => orgLead || dir.project(c.project_id)?.lead_id === me?.id);
  if (mine.length === 0) return null;

  return (
    <section className="mb-5 rounded-[22px] bg-surface p-5 card-shadow">
      <p className="text-[14px] font-semibold">Changes waiting for you ({mine.length})</p>
      <p className="mt-0.5 text-[12.5px] text-muted">Deadline and scope changes need a lead. Nothing moves until you approve.</p>
      {decide.error && (
        <div className="mt-2">
          <FormError>{(decide.error as ApiError).message}</FormError>
        </div>
      )}
      <ul className="mt-3 space-y-2">
        {mine.map((c) => (
          <li key={c.id} className="flex flex-wrap items-center gap-3 rounded-xl bg-bg px-3.5 py-3">
            <div className="min-w-0 flex-1">
              <p className="text-[13.5px]">
                <span className="font-medium">{tasks.find((t) => t.id === c.task_id)?.title ?? "A task"}</span> ·{" "}
                {changeText(c, (id) => dir.person(id)?.name)}
              </p>
              <p className="text-[12px] text-muted">
                {dir.byUser(c.requested_by_id)?.name ?? "Someone"} · {dir.project(c.project_id)?.name} · {ago(c.inserted_at)}
                {c.reason && <> · &ldquo;{c.reason}&rdquo;</>}
              </p>
            </div>
            <Button size="sm" disabled={decide.isPending} onClick={() => decide.mutate({ id: c.id, action: "approve" })}>
              <CheckIcon size={13} weight="bold" /> Approve
            </Button>
            <Button size="sm" variant="ghost" disabled={decide.isPending} onClick={() => decide.mutate({ id: c.id, action: "reject" })}>
              Reject
            </Button>
          </li>
        ))}
      </ul>
    </section>
  );
}

/* Applied automatically in the last day (2.2), each with Undo. */
function AutoApplied() {
  const dir = useDirectory();
  const client = useQueryClient();
  const approved = useQuery({ queryKey: ["proposals", dir.orgId, "approved"], queryFn: () => getProposals(dir.orgId!, "approved"), enabled: !!dir.orgId });
  const undo = useMutation({
    mutationFn: (id: string) => undoProposal(dir.orgId!, id),
    onSettled: () => {
      for (const key of ["proposals", "tasks", "changes"]) client.invalidateQueries({ queryKey: [key, dir.orgId] });
    },
  });
  const [since] = useState(() => Date.now() - 86_400_000);
  const auto = (approved.data ?? []).filter((p) => p.data.auto && new Date(p.inserted_at).getTime() > since);
  if (auto.length === 0) return null;

  return (
    <section className="mb-5 rounded-[22px] bg-surface p-5 card-shadow">
      <p className="flex items-center gap-1.5 text-[14px] font-semibold">
        <LightningIcon size={14} weight="fill" className="text-signal" /> Applied automatically ({auto.length})
      </p>
      <p className="mt-0.5 text-[12.5px] text-muted">Noa was sure enough to apply these. Undo puts one back in your Inbox.</p>
      {undo.error && (
        <div className="mt-2">
          <FormError>{(undo.error as ApiError).message}</FormError>
        </div>
      )}
      <ul className="mt-3 space-y-2">
        {auto.map((p) => (
          <li key={p.id} className="flex flex-wrap items-center gap-3 rounded-xl bg-bg px-3.5 py-2.5">
            <div className="min-w-0 flex-1">
              <p className="text-[13.5px] font-medium">{p.summary}</p>
              <p className="text-[12px] text-muted">
                {[dir.project(p.project_id)?.name, dir.person(p.owner_id)?.name, ago(p.inserted_at)].filter(Boolean).join(" · ")}
              </p>
            </div>
            <Button size="sm" variant="ghost" disabled={undo.isPending} onClick={() => undo.mutate(p.id)}>
              Undo
            </Button>
          </li>
        ))}
      </ul>
    </section>
  );
}
