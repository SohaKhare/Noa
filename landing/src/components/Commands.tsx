import { Reveal } from "./Reveal";
import { SectionHeading } from "./SectionHeading";

/* "Just @noa it": the nine asks as a quiet, divided list instead of nine cards. */

const cases = [
  { cmd: "What did we decide about Veriq scoring?", what: "The decision, who made it, and the message it came from." },
  { cmd: "Move Soha to Emmarie from Monday", what: "Handover, new owners, KT brief and agent pack." },
  { cmd: "What's blocking the Emmarie demo?", what: "Blockers across tasks and chats, with suggested owners." },
  { cmd: "Brief me on Video Break", what: "A KT brief in under a minute, for anyone joining late." },
  { cmd: "Who knows the Durable Objects setup?", what: "People ranked by what they've actually worked on." },
  { cmd: "Push the Board report to Monday", what: "Proposes the change and routes it to the right lead." },
  { cmd: "What's on my plate today?", what: "One list across every project, at your digest time." },
  { cmd: "Recap today's sync to the team", what: "Decisions and action items from the Meet transcript." },
  { cmd: "What changed while I was out?", what: "Decisions, moved deadlines and new tasks since you left." },
];

export function Commands() {
  return (
    <section id="use-cases" aria-labelledby="use-cases-title" className="mx-auto max-w-7xl px-5 py-28">
      <SectionHeading id="use-cases-title" title="Just @noa it." body="Plain words in the chat you're already in. Noa does the rest, and shows its sources." />
      <ul className="mt-14 grid gap-x-10 sm:grid-cols-2 lg:grid-cols-3">
        {cases.map((c, i) => (
          <li key={c.cmd} className="border-t border-line py-6">
            <Reveal delay={(i % 3) * 0.05}>
              <p className="text-[17px] leading-snug font-medium tracking-tight">
                <span className="text-accent-fg">@noa</span> {c.cmd}
              </p>
              <p className="mt-1.5 text-[14.5px] leading-relaxed text-muted">{c.what}</p>
            </Reveal>
          </li>
        ))}
      </ul>
    </section>
  );
}
