# Noa: the company brain we built to run our own hackathon

*Draft for 4.8. Team NotYourIdea (Saish, Soha, Vedant), WeMakeDevs × FalkorDB Graph Hacks, Company Brain track. Fill in the video link and final numbers before publishing.*

NotYourIdea is five people running four projects at once: Veriq (AI reputation reports), Emmarie (a film workspace), Tulpa and Video Break. People move between them every week, most decisions happen in Discord and WhatsApp, and nobody updates a board. When someone switches projects, they spend their first days asking "what's going on here?"

So we built Noa, and used it to run the four days we spent building it.

## What it does

Noa reads the channels you map to projects (never DMs) and turns what people say into work:

- "on it, Board report PDF export by Friday" becomes a proposed task for Saish on Veriq, due Friday, with the message quoted. One click puts it on the board. If Noa is sure, it applies the task itself, with Undo.
- "score weights v2 is merged" moves the card. "can I do it Saturday?" proposes a new deadline, which waits for the lead, because deadlines are commitments.
- "ok final: we score all seven families" becomes a decision with its source. A later decision that replaces it marks the old one superseded instead of deleting it.

Then it gives everyone one place to work: My day across all projects, an Inbox of proposals, Kanban and timeline per project, a portfolio, and `@noa`, which answers questions like "what's blocking Emmarie?" with numbered sources, only from what the asker can see.

When someone moves projects, a lead drags them on the staffing board. Noa hands over their open tasks to suggested owners, keeps routing questions about the old project to them for two weeks, and gives them a KT brief: what the project is, where it stands, what was decided and who to talk to.

## Why a graph

Everything Noa knows is a graph: people, projects, channels, messages, tasks, decisions and change records, one FalkorDB graph per company. The interesting questions are graph questions:

- **Who knows this project?** Noa weighs what each person did on it (tasks finished, decisions made, messages in its channels) into `KNOWS_ABOUT` edges and ranks them. That's "people to meet" in the KT brief.
- **Who does the work run through?** PageRank over the whole work graph. On our own data it ranked Saish first, then Vedant, which matched how the week felt.
- **Where is one person a single point of failure?** Projects where one person holds most of the knowledge. Ours flagged Video Break, where Soha held all of it, which is exactly the project we planned to move her off.
- **Where did this come from?** Every task and decision is linked to the message it was extracted from.

## An agent that acts on the graph

Noa doesn't only answer questions. Its triage agent looks for work nobody is really carrying: tasks with no owner, tasks whose owner moved to another project, overdue tasks on someone with too much on their plate. For each one it walks the graph to rank who should take it: who is on the project now (`WORKS_ON`), how much they know it (`KNOWS_ABOUT`), who finished similar work (full-text search over finished tasks), who made a decision the task depends on, and how much each person already carries. The suggestion lands in the Inbox with those reasons and the graph route behind them, and a lead approves it. Coding agents get the same ranking over MCP.

## How it's built

- **Append-only event log in Postgres is the truth.** Every write (from the API, the seed, or Noa itself) appends an event in the same transaction. FalkorDB is a projection: a projector applies new events within about two seconds, and `mix noa.graph` rebuilds a company's graph from its log in seconds.
- **Typed extraction.** Each kind of item (task, status change, deadline change, decision, scope change) is a strict JSON schema; the model can only answer in those shapes, and every item must cite the messages it came from. Low-confidence items are dropped, not guessed.
- **Permissions everywhere.** Elixir, Phoenix and Ash policies check every read and write, including what `@noa` can cite. A test calls every API route as an outsider, a guest and a member, and CI fails if anything leaks.
- **Concurrent writers.** People, chat ingest and agents write at once. A concurrency test caught a real bug here: two people editing different fields of one task could leave the log's last snapshot missing one edit, so the graph drifted from Postgres. Snapshots now re-read the committed row.
- **Web app** in Next.js, talking only to the Phoenix API.

On an NYI-sized history (3,400 events) the board loads in a few milliseconds, `@noa` retrieves in about 15 ms before the model call, and the full graph rebuilds in 2.5 seconds.

## What we learned

- Proposals beat automation for anything that's a commitment. Auto-apply is right for "I finished it", wrong for "it'll be late".
- A graph earns its place when the question is about relationships: who knows what, who the work depends on, where a fact came from. Tables are fine for the board.
- Building the tool that runs your own team is the fastest feedback loop there is.

## Try it

Code, setup and docs: github.com/SohaKhare/Noa. Video: *(link)*.
