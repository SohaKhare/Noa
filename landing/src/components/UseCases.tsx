import { SectionHeading } from "./SectionHeading";
import { Reveal } from "./Reveal";

const cases = [
  { cmd: "What did we decide about payments?", what: "Answers with the decision, who made it, and the message it came from.", tags: ["Discord", "Meet"] },
  { cmd: "Move Riya to Project B from Monday", what: "Opens the shift: handover, new owners, KT brief, agent pack.", tags: ["Staffing", "KT"] },
  { cmd: "What's blocking the launch?", what: "Lists blockers across tasks and chats, with suggested owners.", tags: ["Graph", "Slack"] },
  { cmd: "Brief me on Client Portal", what: "A KT brief in under a minute, for anyone joining late.", tags: ["KT", "WhatsApp"] },
  { cmd: "Who knows the Stripe integration?", what: "Ranks people by what they've actually worked on and discussed.", tags: ["PageRank"] },
  { cmd: "Push pricing to next week", what: "Proposes the date change and routes it to the right lead.", tags: ["Timeline", "Approval"] },
  { cmd: "What's on my plate today?", what: "One list across every project you're on, sent at your digest time.", tags: ["My day", "WhatsApp"] },
  { cmd: "Recap today's sync to the team", what: "Turns the Meet transcript into decisions and action items.", tags: ["Meet", "Decisions"] },
  { cmd: "What changed while I was out?", what: "Decisions, moved deadlines and new tasks since you last looked.", tags: ["Digest"] },
];

export function UseCases() {
  return (
    <section id="use-cases" aria-labelledby="use-cases-title" className="mx-auto max-w-7xl px-5 py-28">
      <SectionHeading
        id="use-cases-title"
        eyebrow="Use cases"
        title="Just @noa it."
        body="Plain words in the chat you're already in. Noa does the rest, and shows its sources."
      />
      <div className="mt-14 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {cases.map((c, i) => (
          <Reveal key={c.cmd} delay={(i % 3) * 0.06}>
            <article className="group h-full rounded-[24px] bg-surface p-6 card-shadow transition-transform duration-500 ease-soft hover:-translate-y-1">
              <p className="text-[17px] leading-snug font-semibold tracking-tight">
                <span className="text-accent-fg">@noa</span> {c.cmd}
              </p>
              <p className="mt-2.5 text-[14px] leading-relaxed text-muted">{c.what}</p>
              <ul className="mt-5 flex flex-wrap gap-1.5">
                {c.tags.map((t) => (
                  <li key={t} className="rounded-full bg-bg px-2.5 py-1 font-mono text-[10.5px] text-muted">
                    {t}
                  </li>
                ))}
              </ul>
            </article>
          </Reveal>
        ))}
      </div>
    </section>
  );
}
