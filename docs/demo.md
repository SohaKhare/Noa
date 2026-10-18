# Demo video plan (4.7)

One end-to-end story on NYI's real workspace at `app.heynoa.xyz`, recorded in phases by the three of us, then edited with a voiceover. Nothing seeded or mocked: if a phase has nothing real to show, make it real first (post the message, assign the task).

**Length.** The rules set no limit; rule 10 only asks for "a demo video showing the working project". Aim for a **6–7 minute** main cut (judges skim) and keep raw takes so a 2-minute cut can be made from the same footage.

**What the rules want visible** (rule 10, and judging is on work done during the event): FalkorDB is central, the graph shapes what the agent does, and we can explain it. Phase 8 covers this; the README must also carry the graph data model and the Cypher the product depends on (see `docs/hackathon.md`).

## Cast and screens

| Who | Role in Noa | Screen |
| --- | --- | --- |
| Vedant | Org admin, lead | Browser profile "Vedant" on `app.heynoa.xyz`, Discord, phone (WhatsApp) |
| Saish | Member on Veriq/Emmarie | Browser profile "Saish", phone (WhatsApp, screen-mirrored), terminal with Claude Code |
| Soha | Member, runs the meeting | Browser profile "Soha", phone (WhatsApp), Google Meet |

Record at 1440×900, browser zoom 100%, bookmarks bar and extensions hidden. Narration is recorded afterwards over the edit; on camera, nobody needs to talk except in the meeting (phase 7).

## Before recording (freeze first)

Deploy everything **before** the first take, then freeze: no deploys between takes, or the UI changes under the edit. If we want deployment in the video, film it as its own short clip (phase 9).

- [ ] **Code live.** All PRs merged to `main`; API deployed (`fly deploy` from a clean copy of main); web redeployed on Vercel (Soha). `/admin` → System shows everything green.
- [ ] **WhatsApp, 24-hour window** (templates still pending with Meta). Vedant, Saish and Soha: Settings → Notifications → WhatsApp + number, then each sends "hi" to **+1 205-341-2931** within 24 hours of recording. The dot in Notifications must be green for all three.
- [ ] **Discord.** Everyone on camera has run `/noa link`. nyi-tech channels are mapped and **Load history** pressed (it reads threads and only the last 30 days).
- [ ] **GitHub.** The app is installed (Settings → Connectors) and history loaded.
- [ ] **Meetings.** For Google Meet: `ATTENDEE_API_KEY` set as a Fly secret, then Settings → Meetings works. Fallback: Discord voice (`DISCORD_VOICE_ENABLED=true`, `/noa meeting start`).
- [ ] **MCP.** Saish has Claude Code installed; **blur the token** in the edit (or create it off camera and paste from the clipboard).
- [ ] **Inbox tidy.** Decide or dismiss leftovers so the new proposals stand out.
- [ ] **Rehearse once**, then revert rehearsal changes from each task's history (every change can be reverted).

## Phases

Times are for the edited cut.

### 1. Vedant sets up the company (0:00–1:00)

| On screen | Voiceover |
| --- | --- |
| Landing page hero, then sign in as Vedant | "NotYourIdea runs four products with a small team that moves between them. Noa is our company brain." |
| `/admin` (superadmin) → the NotYourIdea workspace and its admins | "Every company gets its own workspace and its own graph." |
| Settings → People: invite a member by email; show the invite email arriving from itsupport@ | "Admins invite people; the invite comes by email." |
| Settings → Connectors: Discord connected, GitHub App installed (show the repo list), WhatsApp on | "Noa connects to where the work already happens: Discord, GitHub, WhatsApp, Gmail, Slack and meetings." |
| Settings → Channels: the server's real channels; map one to a project; press **Load history** | "Map a channel to a project and load its history, threads included. Only the last month comes in: old chat is not new work." |

### 2. Chat becomes work (1:00–1:50)

| On screen | Voiceover |
| --- | --- |
| Discord, a **thread** in a mapped channel: Vedant asks "@Soha can you take the i2v API by Friday?"; Soha: "on it" | "Work is agreed in threads, like this." |
| Inbox (Vedant): the proposal with the quote, thread, project and **for Soha**, due Friday | "Noa read the thread, routed it to Emmarie by the channel, and proposed a task for Soha, citing the message." |
| Approve. Board: the card in To do; open the drawer: source and history | "One click and it's on the board, still linked to what was said." |
| A decision said in chat appears in the Inbox; approve; project → Decisions tab | "Decisions are recorded the same way, with who made them and where." |

### 3. Vedant assigns new work (1:50–2:20)

| On screen | Voiceover |
| --- | --- |
| New task on Veriq, no owner; drawer → **Who should own this?** shows Saish with reasons and the graph route | "Not sure who should take it? Noa ranks people from the graph: who worked on this project, who finished similar work, who has room." |
| Give it to Saish with a deadline; give another to Soha | "Vedant assigns it." |

### 4. Saish hears about it on WhatsApp (2:20–2:50)

| On screen | Voiceover |
| --- | --- |
| Saish's phone: "Vedant put you on … in Veriq, due …" with **Start now / Done / Need help** | "Saish gets it on WhatsApp straight away." |
| Saish replies **tasks**: Noa lists his open tasks with project and due date | "He can ask for his list any time." |
| Tap **Start now**; the card moves to In progress on Vedant's board | "Buttons act on the board directly." |

### 5. Saish works with his coding agent (2:50–3:50)

| On screen | Voiceover |
| --- | --- |
| Saish opens Noa: the bell shows the new assignment; My day lists his tasks with deadlines | "In Noa, his day is already laid out." |
| Agent pack: `CLAUDE.md`, `AGENTS.md`, `tasks.md` for Veriq, written from the graph, with recent GitHub changes | "Every project he's on has an agent pack: context from the graph, not a stale file." |
| Create a personal token; terminal: `claude mcp add --transport http noa https://api.heynoa.xyz/mcp --header "Authorization: Bearer …"` (token blurred) | "He connects Noa to Claude Code with a personal token. It sees only what he can see." |
| Claude Code: "what am I on in Veriq?" → `my_tasks`, `project_context`; it does the work; "mark it done" → `update_task_status` | "His agent knows the task, the decisions behind it and who to ask, and closes it when it's done." |

### 6. The lead knows without asking (3:50–4:10)

| On screen | Voiceover |
| --- | --- |
| Vedant's phone: "Saish finished … in Veriq." | "No status meeting: the lead hears when work is done." |
| Vedant's board: the card in Done; drawer history shows who moved it | "The tracker updates itself, and every change has a record and can be reverted." |

### 7. Soha's meeting becomes minutes (4:10–5:00)

| On screen | Voiceover |
| --- | --- |
| Soha: Settings → Meetings, paste the Meet link, confirm everyone consented, start the **Noa Notetaker**; admit it in Meet | "Meetings count too. Soha brings Noa's notetaker into a Google Meet, with everyone's consent." |
| A short real standup: one commitment, one decision, some small talk | |
| Stop; fetch the transcript; confirm project and channel; import | |
| Minutes: discussion, blockers, tasks, decisions, each citing who said it; the Inbox has them as proposals | "Noa writes minutes that skip the small talk and files the commitments for approval, never automatically." |

Fallback if Attendee fails: the same beat with Discord voice: `/noa meeting start`, everyone consents, `/noa meeting notes`.

### 8. How FalkorDB is the brain (5:00–5:50)

| On screen | Voiceover |
| --- | --- |
| Overlay: architecture (chat, GitHub, meetings → event log → projector → one FalkorDB graph per company → @noa, MCP, agent packs) | "Everything Noa learns goes into an append-only log and is projected into a FalkorDB graph per company: people, projects, tasks, decisions and the messages they came from." |
| Project → Graph tab: click Soha, then a decision; the path lights up | "Every task and decision links back to the message it was extracted from." |
| Ask Noa: "Who knows the most about Emmarie and what's blocking it?" Answer with [1][2] sources and the **graph route** | "Answers are retrieved from the graph: Noa walks from the project and people you name, searches the graph, and runs graph algorithms as tools. Each answer shows the route it took." |
| Portfolio: PageRank (who the work runs through), bus-factor risk, bridges | "PageRank and betweenness over the graph show who the work depends on and where one person is a single point of failure." |
| Optional: a Cypher query from `docs/hackathon.md` on screen | |

### 9. Soha asks from anywhere (5:50–6:30)

| On screen | Voiceover |
| --- | --- |
| Soha's My day: her tasks, including the i2v API | "Soha's day, in Noa." |
| Discord: `/noa tasks` (private reply), then `/noa ask what did we decide about API keys?` | "The same in Discord…" |
| WhatsApp: "tasks", then a question to @noa with sources | "…and on WhatsApp. One brain, wherever the team already is." |
| Optional clip: `fly deploy` and the Vercel deploy finishing; health check green | "It's live at heynoa.xyz." |

### 10. Close (6:30–6:45)

My day, "Decided today". "That's Noa. It ran our hackathon." End card: heynoa.xyz, repo link, team names.

## Worth adding if there is time

- **Lead approval of a deadline change**: a member moves a date with a reason → "Waiting for Vedant" → approve. Shows governance; 20 seconds.
- **Shifts and KT**: drag someone to another project on People; the KT brief and agent pack follow. A strong Company Brain beat; 25 seconds.
- **Find unowned work** (triage) in the Inbox, with graph reasons.
- **Isolation and privacy**: one graph per company, consent for meetings, channels opt-in, DMs never read. A 10-second overlay.

## Fallbacks (still real)

- **WhatsApp window closed**: show the notification in the bell and as a Discord DM instead; say it reaches WhatsApp once Meta approves the templates.
- **Model slow**: record the Inbox after the proposal lands; cut the wait.
- **Meet bot fails**: Discord voice (phase 7 fallback).
- **Graph down**: skip the Graph tab; @noa still answers, and the edit says so honestly.

## After recording

- Edit, add the voiceover, upload unlisted to YouTube; link it in the README and the submission (4.9) with the track: **03 Company Brain**.
- Keep raw takes until results are out.
