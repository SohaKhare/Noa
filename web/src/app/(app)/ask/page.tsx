"use client";

import { ArrowUpIcon } from "@phosphor-icons/react";
import { AnimatePresence, motion } from "motion/react";
import { useState, type FormEvent } from "react";
import { Avatar, PageHeader, SourceChip } from "@/components/ui";
import type { Source } from "@/lib/mock";

type Msg = { who: "me" | "noa"; text: string; sources?: Source[] };

const suggestions = [
  "What's blocking the Emmarie demo?",
  "What did we decide about Veriq scoring?",
  "Who knows the Durable Objects setup?",
  "Brief me on Video Break",
];

// Placeholder answer until the agent (item 2.5) is wired to the API.
const answer = (q: string): Msg => ({
  who: "noa",
  text: q.toLowerCase().includes("block")
    ? "Two things before the Oct 30 demo: motion tests time out on the project's Durable Object [1], and coverage notes v2 waits on Soha, who joins Emmarie on Monday [2]. Ojas knows the Workers side best. Want me to propose him for the queue fix?"
    : "Here's what I found in the project graph, with sources. (Sample answer: the agent connects in item 2.5.)",
  sources: [
    { kind: "discord", where: "#emmarie", when: "Tue 16:12" },
    { kind: "discord", where: "Staffing · Soha", when: "Mon" },
  ],
});

export default function Ask() {
  const [msgs, setMsgs] = useState<Msg[]>([]);
  const [q, setQ] = useState("");

  const send = (text: string) => {
    if (!text.trim()) return;
    setMsgs((m) => [...m, { who: "me", text }]);
    setQ("");
    setTimeout(() => setMsgs((m) => [...m, answer(text)]), 700);
  };
  const onSubmit = (e: FormEvent) => {
    e.preventDefault();
    send(q);
  };

  return (
    <div className="mx-auto flex min-h-[calc(100vh-56px)] max-w-3xl flex-col">
      <PageHeader title="Ask Noa" sub="Answers come from the graph, with sources, limited to what you can see." />
      <div className="flex-1 space-y-4">
        {msgs.length === 0 && (
          <div className="grid gap-2 sm:grid-cols-2">
            {suggestions.map((s) => (
              <button
                key={s}
                onClick={() => send(s)}
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
              {m.who === "noa" && <Avatar initials="N" tone="accent" />}
              <div
                className={
                  m.who === "me"
                    ? "max-w-[80%] rounded-2xl rounded-br-md bg-accent px-4 py-2.5 text-[13.5px] text-white"
                    : "max-w-[85%] rounded-2xl rounded-tl-md bg-surface px-4 py-3 text-[13.5px] leading-relaxed card-shadow"
                }
              >
                {m.text}
                {m.sources && (
                  <div className="mt-2.5 flex flex-wrap gap-1.5">
                    {m.sources.map((s, j) => (
                      <SourceChip key={j} source={{ ...s, where: `[${j + 1}] ${s.where}` }} />
                    ))}
                  </div>
                )}
              </div>
            </motion.div>
          ))}
        </AnimatePresence>
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
        <button type="submit" aria-label="Send" className="grid size-9 place-items-center rounded-full bg-accent text-white">
          <ArrowUpIcon size={16} weight="bold" />
        </button>
      </form>
    </div>
  );
}
