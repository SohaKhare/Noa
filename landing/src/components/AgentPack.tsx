import { FileTextIcon, KeyIcon, PlugsConnectedIcon } from "@phosphor-icons/react/ssr";
import { Reveal } from "./Reveal";
import { SectionHeading } from "./SectionHeading";

/* For coding agents: the agent pack and Noa's MCP server, with a Claude Code session that asks the graph who should take a task. */

const steps = [
  {
    Icon: FileTextIcon,
    title: "An agent pack for every project you're on",
    body: "CLAUDE.md, AGENTS.md and tasks.md, written from the company graph: who knows what, what was decided and why, where work stands, what changed on GitHub this week.",
  },
  {
    Icon: KeyIcon,
    title: "Connect once",
    body: "Create a personal token on your Agent pack page and add Noa to Claude Code, Cursor or any MCP client. It sees only what you can see.",
  },
  {
    Icon: PlugsConnectedIcon,
    title: "Live context, and it can act",
    body: "project_context, my_tasks, ask, who_knows, suggest_owner, assign_task. Answers cite their sources; writes follow your lead rules and can be reverted.",
  },
];

export function AgentPack() {
  return (
    <section id="agents" aria-labelledby="agents-title" className="mx-auto max-w-7xl px-5 py-28">
      <SectionHeading
        id="agents-title"
        eyebrow="For coding agents"
        title="Your agent already knows the project."
        body="No more stale CLAUDE.md. Noa gives every coding agent the team's context, live from the graph, and lets it pick up work the right way."
      />

      <div className="mt-14 grid items-start gap-10 lg:grid-cols-[1fr_1.15fr]">
        <ol className="space-y-7">
          {steps.map(({ Icon, title, body }, i) => (
            <li key={title}>
              <Reveal delay={i * 0.05} className="flex gap-4">
                <span className="grid size-10 shrink-0 place-items-center rounded-2xl bg-mist text-accent-fg">
                  <Icon size={20} />
                </span>
                <div>
                  <h3 className="text-[17px] font-semibold tracking-tight">{title}</h3>
                  <p className="mt-1 text-[14.5px] leading-relaxed text-muted">{body}</p>
                </div>
              </Reveal>
            </li>
          ))}
        </ol>

        <Reveal delay={0.1}>
          <div className="overflow-hidden rounded-card bg-ink text-white shadow-[0_30px_80px_-30px_rgba(10,30,60,0.45)]">
            <div className="flex items-center gap-1.5 border-b border-white/10 px-4 py-3">
              <span className="size-2.5 rounded-full bg-white/20" />
              <span className="size-2.5 rounded-full bg-white/20" />
              <span className="size-2.5 rounded-full bg-white/20" />
              <span className="ml-3 font-mono text-[11.5px] text-white/50">claude · veriq</span>
            </div>
            <pre className="overflow-x-auto px-5 py-5 font-mono text-[12.5px] leading-[1.75] whitespace-pre-wrap text-white/85">
              <span className="text-white/45">$ </span>claude mcp add --transport http noa https://api.heynoa.xyz/mcp \{"\n"}
              {"    "}--header &quot;Authorization: Bearer noa_••••&quot;{"\n"}
              <span className="text-sky-200">✓</span> Added noa{"\n\n"}
              <span className="text-sky-300">&gt;</span> who should take &quot;Board report PDF export&quot;?{"\n"}
              <span className="text-white/45">⏺ noa · suggest_owner</span>{"\n"}
              {"  "}Saish, best fit (score 5.8){"\n"}
              {"  "}· Has worked on Veriq (KNOWS_ABOUT weight 6){"\n"}
              {"  "}· Finished similar work: &quot;Board report PDF layout&quot;{"\n"}
              {"  "}· 40% on Veriq, 4 open tasks{"\n"}
              <span className="text-white/45">{"  "}graph: (Saish)-[:WORKS_ON]-&gt;(Veriq) · (Saish)-[:KNOWS_ABOUT]-&gt;(Veriq){"\n\n"}</span>
              <span className="text-sky-300">&gt;</span> give it to Saish and start the layout{"\n"}
              <span className="text-white/45">⏺ noa · assign_task</span>{"\n"}
              {"  "}&quot;Board report PDF export&quot; is now Saish&apos;s. Saved in its history, and Saish was told.
            </pre>
          </div>
          <p className="mt-3 text-[12.5px] text-muted">Works with Claude Code, Cursor and any client that speaks MCP over HTTP.</p>
        </Reveal>
      </div>
    </section>
  );
}
