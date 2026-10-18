# Demo video script (4.7)

Three minutes, recorded on NYI's real workspace after the noon freeze (4.1). One take per scene; cut together. Screen at 1440×900, browser zoom 100%, dark menu bar hidden. Narration is short and plain: say what happened, not what the feature is called.

## Before recording

Everything on screen is NYI's real workspace on `app.heynoa.xyz`: real channels, real commits, real people. Nothing seeded or mocked; if a scene has nothing real to show yet, make it real first (post the message, assign the task) rather than faking it.

- [ ] **Model key.** `fly secrets set --app heynoa-api OPENAI_API_KEY=…` so chat becomes proposals and `@noa` writes answers. Check `/admin` → System: OpenAI on.
- [ ] **Discord.** nyi-tech is connected. In Settings → Channels map the real channels (`#tulpa` → Tulpa, `#emmarie-video` → Emmarie, `#video-gen-edit` → Video Break, `#ai-services` → Veriq or as decided, `#core` → Split) and press **Load history** on each. Everyone appearing on camera runs `/noa link` once.
- [ ] **WhatsApp (templates still pending with Meta, so use the 24-hour window).** Each person who receives a message on camera: Settings → Notifications → WhatsApp + their number, then sends "hi" to **+1 205-341-2931** within 24 hours of recording. The dot in Notifications turns green when the window is open. Kapso's webhook points at `https://api.heynoa.xyz/webhooks/kapso` (set Oct 18), so replies and button taps reach production.
- [ ] **GitHub.** The app is installed and history loaded (150 commits, 90 PRs on Oct 18). Agent packs already show "Recent changes on GitHub".
- [ ] **Email.** Gmail SMTP is on: invites, sign-in links and notifications really send from itsupport@notyouridea.com.
- [ ] **One real piece of unowned work** on a project (someone leaves, or a new task nobody took) so "Find unowned work" has something true to file.
- [ ] Screen: Vedant or Prathamesh signed in on the web app; Saish in Discord; a phone on WhatsApp Web for the notification shot.
- [ ] Rehearse once; dismiss rehearsal proposals and revert rehearsal changes (every change can be reverted) so the recorded take starts clean.

## Scenes

| # | Time | On screen | Narration |
| --- | --- | --- | --- |
| 1 | 0:00–0:15 | Landing hero, then My day for Vedant | "NotYourIdea runs four projects with five people who move between them. Noa is our company brain: it reads our chat and keeps the work in one graph." |
| 2 | 0:15–0:45 | A mapped nyi-tech channel: a real ask and a real reply ("on it, by Friday"). Switch to the Inbox: the proposal appears with the quote | "Nobody fills in a board. Noa read that reply, routed it to Veriq because of the channel, and proposed a task for Saish, due Friday, citing the message." |
| 3 | 0:45–1:05 | Approve. Veriq board: the card lands in To do. Open the drawer: source and history | "One click and it is on the board, still linked to what was said." |
| 4 | 1:05–1:30 | Saish (member) changes the due date to Monday with a reason. Drawer shows "Waiting for Vedant". Vedant's Inbox: "Changes waiting for you"; approve. WhatsApp to Saish | "Deadlines are shared commitments, so a member's change waits for the lead. Small edits apply at once and can be reverted." |
| 5 | 1:30–1:55 | Ask Noa: "What's blocking Emmarie?" Answer with [1] [2] and the sources listed | "Ask anything. Answers come only from what you're allowed to see, and every claim cites where it came from." |
| 6 | 1:55–2:30 | People board: drag Soha from Video Break to Emmarie. Popover: her open task, Abhishek suggested. Confirm. Emmarie KT tab: brief, people to meet. Agent pack page: her `CLAUDE.md` from the graph | "Moving someone is a drag. Noa hands over her tasks, keeps routing Video Break questions to her for two weeks, and gives her a brief built from the project graph." |
| 7 | 2:30–2:45 | Portfolio: who the work runs through (PageRank), bus-factor risk. Then the project's Graph tab: click Soha, then a decision, and the path lights up | "Under the hood it's a FalkorDB graph per company, rebuilt from an append-only event log. PageRank over it finds who the work depends on and where one person is a single point of failure." |
| 8 | 2:45–2:55 | Inbox: "Find unowned work". Open one suggestion: the reasons and the graph route (WORKS_ON, KNOWS_ABOUT, similar finished work). Approve | "Noa also acts on the graph. It finds work nobody is carrying and says who should take it, and why, from what the graph shows. Coding agents get the same tools over MCP." |
| 9 | 2:55–3:00 | My day again, Decided today | "That's Noa. It ran our hackathon." |

## Fallbacks

- No Discord or model on the day: start at scene 3 with a seeded proposal (`mix noa.seed --sample`) and say "Noa proposed this from our chat".
- No WhatsApp: show the pending change and the approval in the web app only.
- Graph down: skip the Graph tab in scene 7; Portfolio still shows workload and risks from Postgres.

## After recording

- Upload unlisted to YouTube; put the link in the README and the submission (4.9).
- Keep the raw takes until the results are out.
