"use client";

import { CheckCircleIcon, CopyIcon, DownloadSimpleIcon, GitPullRequestIcon } from "@phosphor-icons/react";
import { useState } from "react";
import { Button, Card, PageHeader } from "@/components/ui";
import { cn } from "@/lib/cn";
import { agentPack, person, project } from "@/lib/mock";

export default function AgentPack() {
  const names = Object.keys(agentPack.files);
  const [file, setFile] = useState(names[0]);
  const [copied, setCopied] = useState(false);
  const who = person(agentPack.person)!;
  const where = project(agentPack.project)!;

  const copy = async () => {
    await navigator.clipboard?.writeText(agentPack.files[file]);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  };
  const download = () => {
    const url = URL.createObjectURL(new Blob([agentPack.files[file]], { type: "text/plain" }));
    const a = Object.assign(document.createElement("a"), { href: url, download: file });
    a.click();
    URL.revokeObjectURL(url);
  };

  return (
    <div className="mx-auto max-w-6xl">
      <PageHeader title={`Welcome to ${where.name}, ${who.name}`} sub="From Vedant, your lead · starts Monday" />
      <div className="grid gap-5 lg:grid-cols-[1fr_1.3fr]">
        <Card>
          <p className="mb-3 text-[14px] font-semibold">Set up your workspace</p>
          <ul className="space-y-2">
            {agentPack.steps.map((s) => (
              <li key={s.label} className="flex items-center gap-3 rounded-xl bg-bg px-3.5 py-3 text-[13px]">
                {s.state === "done" ? (
                  <CheckCircleIcon size={17} weight="fill" className="text-good" />
                ) : (
                  <span className="size-[17px] rounded-full ring-1 ring-line" />
                )}
                <span className="flex-1">{s.label}</span>
                {s.action && (
                  <Button size="sm" variant={s.state === "done" ? "quiet" : "mist"}>
                    {s.action}
                  </Button>
                )}
              </li>
            ))}
          </ul>
          <p className="mt-4 text-[12px] text-muted">Secrets never appear in these files. Every fetch is logged and can be revoked.</p>
        </Card>

        <Card className="flex flex-col p-0">
          <div role="tablist" className="flex gap-1 border-b border-line/70 px-4 pt-3">
            {names.map((n) => (
              <button
                key={n}
                role="tab"
                aria-selected={file === n}
                onClick={() => setFile(n)}
                className={cn(
                  "-mb-px border-b-2 px-2.5 pb-2.5 font-mono text-[12px]",
                  file === n ? "border-accent text-accent-fg" : "border-transparent text-muted hover:text-ink",
                )}
              >
                {n}
              </button>
            ))}
          </div>
          <pre className="m-4 flex-1 overflow-auto rounded-2xl bg-deep p-4 ring-1 ring-black/[0.04] font-mono text-[12px] leading-relaxed whitespace-pre-wrap text-white/90">
            {agentPack.files[file]}
          </pre>
          <div className="flex justify-end gap-2 px-4 pb-4">
            <Button size="sm" variant="ghost" onClick={copy}>
              <CopyIcon size={13} /> {copied ? "Copied" : "Copy"}
            </Button>
            <Button size="sm" variant="ghost" onClick={download}>
              <DownloadSimpleIcon size={13} /> Download
            </Button>
            <Button size="sm">
              <GitPullRequestIcon size={13} /> Add to repo (PR)
            </Button>
          </div>
        </Card>
      </div>
    </div>
  );
}
