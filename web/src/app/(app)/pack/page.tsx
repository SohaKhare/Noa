"use client";

import {
  CheckCircleIcon,
  CopyIcon,
  DownloadSimpleIcon,
  GraphIcon,
} from "@phosphor-icons/react";
import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { FormError } from "@/components/AuthCard";
import { ConnectAgent } from "@/components/ConnectAgent";
import { Button, Card, PageHeader } from "@/components/ui";
import { ApiError, getPack, getShifts } from "@/lib/api";
import { cn } from "@/lib/cn";
import { useDirectory } from "@/lib/work";

/*
  Agent pack (3.18): the files someone joining a project gives their coding agent
  (CLAUDE.md, AGENTS.md, tasks.md) and brief.md for everyone else, generated from the
  project graph on request, so they are always current. Plus a day-one checklist.
*/

const download = (name: string, content: string) => {
  const url = URL.createObjectURL(
    new Blob([content], { type: "text/markdown" }),
  );
  const a = Object.assign(document.createElement("a"), {
    href: url,
    download: name,
  });
  a.click();
  URL.revokeObjectURL(url);
};

export default function AgentPack() {
  const dir = useDirectory();
  const me = dir.person(dir.me);
  const lead = me?.role === "org_admin" || me?.role === "pm";
  const shifts = useQuery({
    queryKey: ["shifts", dir.orgId],
    queryFn: () => getShifts(dir.orgId!),
    enabled: !!dir.orgId,
  });

  const [personId, setPersonId] = useState<string | null>(null);
  const [projectId, setProjectId] = useState<string | null>(null);
  const person = personId ?? dir.me;
  // Default: the project this person most recently moved to, else their first project.
  const moved = shifts.data?.find(
    (s) => s.person_id === person && s.to_project_id,
  )?.to_project_id;
  const project =
    projectId ??
    moved ??
    dir.person(person)?.allocations[0]?.project_id ??
    dir.projects[0]?.id ??
    null;

  const pack = useQuery({
    queryKey: ["pack", dir.orgId, project, person],
    queryFn: () => getPack(dir.orgId!, project!, person),
    enabled: !!dir.orgId && !!project,
  });
  const [file, setFile] = useState("CLAUDE.md");
  const [done, setDone] = useState<Record<string, boolean>>({});
  const [copied, setCopied] = useState(false);
  const current =
    pack.data?.files.find((f) => f.path === file) ?? pack.data?.files[0];

  const copy = async () => {
    if (!current) return;
    await navigator.clipboard?.writeText(current.content);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  };

  const who = pack.data?.person?.name ?? me?.name;
  const where = pack.data?.project.name ?? dir.project(project)?.name;

  return (
    <div className="mx-auto max-w-6xl">
      <PageHeader
        title={
          where ? `${who ? `${who}'s` : "Your"} ${where} pack` : "Agent pack"
        }
        sub="What to give your coding agent on day one, built from the project graph. Always current; secrets never go in these files."
        actions={
          <div className="flex flex-wrap gap-2">
            {lead && (
              <select
                value={person ?? ""}
                onChange={(e) => setPersonId(e.target.value)}
                aria-label="Person"
                className="rounded-full bg-surface px-3 py-1.5 text-[13px] ring-1 ring-line focus:outline-none"
              >
                {dir.people.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.name}
                  </option>
                ))}
              </select>
            )}
            <select
              value={project ?? ""}
              onChange={(e) => setProjectId(e.target.value)}
              aria-label="Project"
              className="rounded-full bg-surface px-3 py-1.5 text-[13px] ring-1 ring-line focus:outline-none"
            >
              {dir.projects.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name}
                </option>
              ))}
            </select>
          </div>
        }
      />
      {pack.error && <FormError>{(pack.error as ApiError).message}</FormError>}
      <div className="grid gap-5 lg:grid-cols-[1fr_1.4fr]">
        <div className="space-y-5">
          <Card className="h-fit">
            <p className="mb-3 text-[14px] font-semibold">Day one</p>
            {pack.isLoading && (
              <p className="text-[13px] text-muted">Building the pack…</p>
            )}
            <ul className="space-y-2">
              {pack.data?.steps.map((s) => (
                <li key={s.label}>
                  <button
                    onClick={() =>
                      setDone((d) => ({ ...d, [s.label]: !d[s.label] }))
                    }
                    className="flex w-full items-center gap-3 rounded-xl bg-bg px-3.5 py-3 text-left text-[13px]"
                  >
                    {done[s.label] ? (
                      <CheckCircleIcon
                        size={17}
                        weight="fill"
                        className="text-good"
                      />
                    ) : (
                      <span className="size-[17px] rounded-full ring-1 ring-line" />
                    )}
                    <span
                      className={cn(
                        "flex-1",
                        done[s.label] && "text-muted line-through",
                      )}
                    >
                      {s.label}
                    </span>
                  </button>
                </li>
              ))}
            </ul>
            {pack.data && (
              <p className="mt-4 flex items-center gap-1.5 text-[12px] text-muted">
                <GraphIcon size={13} />{" "}
                {pack.data.store === "falkordb"
                  ? "Built from the FalkorDB project graph."
                  : "Built from the database (graph unavailable)."}
              </p>
            )}
          </Card>
          {dir.orgId && person === dir.me && <ConnectAgent orgId={dir.orgId} />}
        </div>

        <Card className="flex flex-col p-0">
          <div
            role="tablist"
            className="flex gap-1 overflow-x-auto border-b border-line/70 px-4 pt-3"
          >
            {pack.data?.files.map((f) => (
              <button
                key={f.path}
                role="tab"
                aria-selected={current?.path === f.path}
                onClick={() => setFile(f.path)}
                className={cn(
                  "-mb-px shrink-0 border-b-2 px-2.5 pb-2.5 font-mono text-[12px]",
                  current?.path === f.path
                    ? "border-accent text-accent-fg"
                    : "border-transparent text-muted hover:text-ink",
                )}
              >
                {f.path}
              </button>
            ))}
          </div>
          <pre className="m-4 max-h-[560px] flex-1 overflow-auto rounded-2xl bg-deep p-4 font-mono text-[12px] leading-relaxed whitespace-pre-wrap text-white/90 ring-1 ring-black/[0.04]">
            {current?.content ?? " "}
          </pre>
          <div className="flex flex-wrap justify-end gap-2 px-4 pb-4">
            <Button
              size="sm"
              variant="ghost"
              disabled={!current}
              onClick={copy}
            >
              <CopyIcon size={13} /> {copied ? "Copied" : "Copy"}
            </Button>
            <Button
              size="sm"
              variant="ghost"
              disabled={!current}
              onClick={() => current && download(current.path, current.content)}
            >
              <DownloadSimpleIcon size={13} /> Download {current?.path}
            </Button>
            <Button
              size="sm"
              disabled={!pack.data}
              onClick={() =>
                pack.data?.files.forEach((f) => download(f.path, f.content))
              }
            >
              <DownloadSimpleIcon size={13} /> Download all
            </Button>
          </div>
        </Card>
      </div>
    </div>
  );
}
