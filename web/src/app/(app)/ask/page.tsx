"use client";

import { ArrowUpIcon, ArrowsLeftRightIcon, CheckSquareIcon, ChatTextIcon, GavelIcon, GraphIcon, UserFocusIcon } from "@phosphor-icons/react";
import { useMutation } from "@tanstack/react-query";
import { AnimatePresence, motion } from "motion/react";
import Link from "next/link";
import { Fragment, useState, type FormEvent } from "react";
import { FormError } from "@/components/AuthCard";
import { Avatar, PageHeader, SourceChip } from "@/components/ui";
import { ApiError, ask, type Citation } from "@/lib/api";
import { toSource, useDirectory } from "@/lib/work";

/* Ask Noa (2.5): answers from the projects you can see, each claim with a numbered source. */

type Retrieval = { store: "falkordb" | "postgres"; routes: string[] };
type Msg = { who: "me"; text: string } | { who: "noa"; text: string; citations: Citation[]; retrieval?: Retrieval };

const kindIcon = { task: CheckSquareIcon, decision: GavelIcon, message: ChatTextIcon, shift: ArrowsLeftRightIcon, expert: UserFocusIcon, path: GraphIcon };

export default function Ask() {
  const dir = useDirectory();
  const [msgs, setMsgs] = useState<Msg[]>([]);
  const [q, setQ] = useState("");
  const send = useMutation({
    mutationFn: (question: string) => ask(dir.orgId!, question),
    onSuccess: (r) => setMsgs((m) => [...m, { who: "noa", text: r.answer, citations: r.citations, retrieval: r.retrieval }]),
  });

  const [first, second] = dir.projects;
  const suggestions = [
    first && `What's blocking ${first.name}?`,
    first && `What did we decide on ${first.name}?`,
    second && `What's late in ${second.name}?`,
    first && `Brief me on ${first.name}`,
  ].filter(Boolean) as string[];

  const submit = (text: string) => {
    if (!text.trim() || send.isPending || !dir.orgId) return;
    setMsgs((m) => [...m, { who: "me", text }]);
    setQ("");
    send.mutate(text);
  };
  const onSubmit = (e: FormEvent) => {
    e.preventDefault();
    submit(q);
  };

  return (
    <div className="mx-auto flex min-h-[calc(100vh-56px)] max-w-3xl flex-col">
      <PageHeader title="Ask Noa" sub="Answers come from your projects, with sources, limited to what you can see." />
      <div className="flex-1 space-y-4">
        {msgs.length === 0 && (
          <div className="grid gap-2 sm:grid-cols-2">
            {suggestions.map((s) => (
              <button
                key={s}
                onClick={() => submit(s)}
                className="rounded-2xl bg-surface p-4 text-left text-[13.5px] card-shadow transition-transform hover:-translate-y-0.5"
              >
                <span className="text-accent-fg">@noa</span> {s}
              </button>
            ))}
          </div>
        )}
        <AnimatePresence initial={false}>
          {msgs.map((m, i) => (
            <motion.div
              key={i}
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              className={m.who === "me" ? "flex justify-end" : "flex items-start gap-2.5"}
            >
              {m.who === "me" ? (
                <div className="max-w-[80%] rounded-2xl rounded-br-md bg-accent px-4 py-2.5 text-[13.5px] text-white">{m.text}</div>
              ) : (
                <>
                  <Avatar initials="N" tone="accent" />
                  <div className="max-w-[85%] rounded-2xl rounded-tl-md bg-surface px-4 py-3 text-[13.5px] leading-relaxed card-shadow">
                    <AnswerText text={m.text} />
                    {m.citations.length > 0 && (
                      <ol className="mt-3 space-y-1.5 border-t border-line pt-3">
                        {m.citations.map((c, j) => (
                          <CitationRow key={c.id} n={j + 1} c={c} />
                        ))}
                      </ol>
                    )}
                    {m.retrieval && (
                      <p className="mt-2 flex flex-wrap items-center gap-1.5 text-[11px] text-muted">
                        <GraphIcon size={12} />
                        {m.retrieval.store === "falkordb" ? "From the FalkorDB graph" : "From the database (graph unavailable)"}
                        {m.retrieval.routes.length > 0 && ` · ${m.retrieval.routes.join(" · ")}`}
                      </p>
                    )}
                  </div>
                </>
              )}
            </motion.div>
          ))}
          {send.isPending && (
            <motion.div key="thinking" initial={{ opacity: 0 }} animate={{ opacity: 1 }} className="flex items-center gap-2.5">
              <Avatar initials="N" tone="accent" />
              <span className="text-[13px] text-muted">Looking through your projects…</span>
            </motion.div>
          )}
        </AnimatePresence>
        {send.error && <FormError>{(send.error as ApiError).message}</FormError>}
      </div>
      <form onSubmit={onSubmit} className="sticky bottom-4 mt-6 flex items-center gap-2 rounded-full bg-surface p-1.5 pl-5 card-shadow">
        <label htmlFor="ask" className="sr-only">
          Ask Noa
        </label>
        <input
          id="ask"
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder="Ask about any project, person or decision"
          className="min-w-0 flex-1 bg-transparent text-[14px] focus:outline-none"
        />
        <button type="submit" aria-label="Send" disabled={send.isPending} className="grid size-9 place-items-center rounded-full bg-accent text-white disabled:opacity-60">
          <ArrowUpIcon size={16} weight="bold" />
        </button>
      </form>
    </div>
  );
}

/* Renders "- item [1]" lines as a list and [n] markers as small superscript links to the source list. */
function AnswerText({ text }: { text: string }) {
  const lines = text.split("\n").filter((l) => l.trim());
  const inline = (line: string) =>
    line.split(/(\[\d+\])/).map((part, i) => {
      const n = part.match(/^\[(\d+)\]$/)?.[1];
      return n ? (
        <sup key={i} className="ml-0.5 font-mono text-[10px] text-accent-fg">
          [{n}]
        </sup>
      ) : (
        <Fragment key={i}>{part}</Fragment>
      );
    });
  const bullets = lines.every((l) => l.startsWith("- "));
  return bullets ? (
    <ul className="list-disc space-y-1 pl-4">
      {lines.map((l, i) => (
        <li key={i}>{inline(l.slice(2))}</li>
      ))}
    </ul>
  ) : (
    <div className="space-y-1.5">
      {lines.map((l, i) => (
        <p key={i}>{inline(l)}</p>
      ))}
    </div>
  );
}

function CitationRow({ n, c }: { n: number; c: Citation }) {
  const Icon = kindIcon[c.kind];
  const body = (
    <span className="flex items-start gap-2">
      <span className="mt-0.5 font-mono text-[10.5px] text-muted">[{n}]</span>
      <Icon size={14} className="mt-0.5 shrink-0 text-accent-fg" />
      <span className="min-w-0 flex-1">
        <span className="block text-[12.5px] font-medium">{c.title}</span>
        {c.via && <span className="block font-mono text-[10px] text-muted">{c.via}</span>}
        {c.source && <SourceChip source={toSource(c.source)} />}
      </span>
    </span>
  );
  return <li>{c.href ? <Link href={c.href} className="block rounded-lg px-1 py-0.5 hover:bg-bg">{body}</Link> : <div className="px-1 py-0.5">{body}</div>}</li>;
}
