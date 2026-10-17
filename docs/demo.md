# Demo video script (4.7)

Three minutes, recorded on NYI's real workspace after the noon freeze (4.1). One take per scene; cut together. Screen at 1440×900, browser zoom 100%, dark menu bar hidden. Narration is short and plain: say what happened, not what the feature is called.

## Before recording

- [ ] API, web and FalkorDB running against the deployed workspace (or local with `mix noa.seed` plus real chat).
- [ ] Discord bot reading `#veriq` and `#emmarie` (1.13). `OPENAI_API_KEY` set so extraction runs.
- [ ] Soha's phone on screen share or a WhatsApp Web window for the notification (1.15, 2.21).
- [ ] Inbox empty, so new proposals stand out. Vedant signed in on the web app; Saish in Discord.
- [ ] Rehearse once; delete rehearsal proposals with Dismiss.

## Scenes

| # | Time | On screen | Narration |
| --- | --- | --- | --- |
| 1 | 0:00–0:15 | Landing hero, then My day for Vedant | "NotYourIdea runs four projects with five people who move between them. Noa is our company brain: it reads our chat and keeps the work in one graph." |
| 2 | 0:15–0:45 | Discord `#veriq`: Vedant asks who can take the Board report PDF export; Saish replies "on it, by Friday". Switch to the Inbox: the proposal appears with the quote | "Nobody fills in a board. Noa read that reply, routed it to Veriq because of the channel, and proposed a task for Saish, due Friday, citing the message." |
| 3 | 0:45–1:05 | Approve. Veriq board: the card lands in To do. Open the drawer: source and history | "One click and it is on the board, still linked to what was said." |
| 4 | 1:05–1:30 | Saish (member) changes the due date to Monday with a reason. Drawer shows "Waiting for Vedant". Vedant's Inbox: "Changes waiting for you"; approve. WhatsApp to Saish | "Deadlines are shared commitments, so a member's change waits for the lead. Small edits apply at once and can be reverted." |
| 5 | 1:30–1:55 | Ask Noa: "What's blocking Emmarie?" Answer with [1] [2] and the sources listed | "Ask anything. Answers come only from what you're allowed to see, and every claim cites where it came from." |
| 6 | 1:55–2:30 | People board: drag Soha from Video Break to Emmarie. Popover: her open task, Abhishek suggested. Confirm. Emmarie KT tab: brief, people to meet. Agent pack page: her `CLAUDE.md` from the graph | "Moving someone is a drag. Noa hands over her tasks, keeps routing Video Break questions to her for two weeks, and gives her a brief built from the project graph." |
| 7 | 2:30–2:50 | Portfolio: who the work runs through (PageRank), bus-factor risk. Then the project's Graph tab: click Soha, then a decision, and the path lights up | "Under the hood it's a FalkorDB graph per company, rebuilt from an append-only event log. PageRank over it finds who the work depends on and where one person is a single point of failure." |
| 8 | 2:50–3:00 | My day again, Decided today | "That's Noa. It ran our hackathon." |

## Fallbacks

- No Discord or model on the day: start at scene 3 with a seeded proposal (`mix noa.seed --sample`) and say "Noa proposed this from our chat".
- No WhatsApp: show the pending change and the approval in the web app only.
- Graph down: skip the Graph tab in scene 7; Portfolio still shows workload and risks from Postgres.

## After recording

- Upload unlisted to YouTube; put the link in the README and the submission (4.9).
- Keep the raw takes until the results are out.
