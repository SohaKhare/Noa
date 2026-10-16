/*
  Sample data shaped like the graph (see PLAN.md, "Graph schema").
  Pages read from here until the Phoenix API is wired (lib/api.ts).
*/

export type Role = "superadmin" | "org_admin" | "pm" | "member" | "guest";
export type Status = "proposed" | "todo" | "in_progress" | "blocked" | "done";

export type Person = { id: string; name: string; initials: string; title: string; role: Role; reportsTo?: string };
export type Project = {
  id: string;
  key: string;
  name: string;
  health: "on_track" | "at_risk" | "blocked";
  nextDeadline: string;
  blockers: number;
  lead: string;
};
export type Source = { kind: "discord" | "slack" | "meet" | "whatsapp" | "github"; where: string; when: string; quote?: string };
export type Task = {
  id: string;
  title: string;
  project: string;
  status: Status;
  owner?: string;
  due?: string;
  start?: string;
  end?: string;
  dependsOn?: string[];
  source: Source;
};
export type Decision = { id: string; title: string; project: string; by: string[]; at: string; affects: string; source: Source };
export type Proposal = {
  id: string;
  kind: "new_task" | "status" | "deadline" | "route";
  summary: string;
  project?: string;
  options?: string[];
  confidence: number;
  source: Source;
};
export type Allocation = { person: string; project: string | "bench"; percent: number; from?: string };

export const me = "ve";

export const people: Person[] = [
  { id: "oj", name: "Ojas", initials: "OJ", title: "Co-founder · Tech", role: "org_admin" },
  { id: "ab", name: "Abhishek", initials: "AB", title: "Co-founder · Content", role: "org_admin" },
  { id: "ve", name: "Vedant", initials: "VE", title: "SWE · PM / Lead", role: "pm", reportsTo: "oj" },
  { id: "sa", name: "Saish", initials: "SA", title: "Intern · Design", role: "member", reportsTo: "ve" },
  { id: "so", name: "Soha", initials: "SO", title: "Intern", role: "member", reportsTo: "ve" },
];

/* Real NYI projects (~/code/nyi). Ids stay short because routes use them. */
export const projects: Project[] = [
  { id: "a", key: "veriq", name: "Veriq", health: "at_risk", nextDeadline: "Oct 17", blockers: 1, lead: "ve" },
  { id: "b", key: "emmarie", name: "Emmarie", health: "on_track", nextDeadline: "Oct 30", blockers: 1, lead: "oj" },
  { id: "c", key: "video-break", name: "Video Break", health: "on_track", nextDeadline: "Oct 24", blockers: 0, lead: "ab" },
  { id: "d", key: "tulpa", name: "Tulpa", health: "blocked", nextDeadline: "Oct 18", blockers: 2, lead: "ve" },
];

export const allocations: Allocation[] = [
  { person: "ve", project: "a", percent: 60 },
  { person: "sa", project: "a", percent: 50 },
  { person: "oj", project: "b", percent: 60 },
  { person: "sa", project: "b", percent: 50 },
  { person: "ab", project: "c", percent: 50 },
  { person: "so", project: "c", percent: 100 },
];

const discord = (where: string, when: string, quote?: string): Source => ({ kind: "discord", where, when, quote });

export const tasks: Task[] = [
  { id: "t1", title: "Board report PDF export", project: "a", status: "proposed", owner: "sa", due: "Fri", start: "Oct 14", end: "Oct 17", source: discord("#veriq", "today 10:42", "on it, Board report PDF export by Friday") },
  { id: "t2", title: "Prompt plan review", project: "a", status: "todo", owner: "so", due: "today", start: "Oct 15", end: "Oct 16", dependsOn: ["t5"], source: discord("#veriq", "Mon") },
  { id: "t3", title: "Report share links", project: "a", status: "todo", owner: "sa", due: "Mon", start: "Oct 17", end: "Oct 20", source: { kind: "meet", where: "Weekly sync", when: "Mon 14:05" } },
  { id: "t4", title: "Score weights v2", project: "a", status: "in_progress", owner: "ve", due: "Fri", start: "Oct 13", end: "Oct 17", source: discord("#veriq", "today 09:10") },
  { id: "t5", title: "Practitioner report layout", project: "a", status: "in_progress", owner: "sa", due: "Tue", start: "Oct 14", end: "Oct 21", source: discord("#veriq", "Tue") },
  { id: "t6", title: "Brand logo pack import", project: "a", status: "blocked", owner: "sa", due: "Thu", start: "Oct 15", end: "Oct 19", source: { kind: "whatsapp", where: "Vedant", when: "Tue 16:12", quote: "still waiting on the brand's logo pack" } },
  { id: "t7", title: "AI Overview lane", project: "a", status: "done", owner: "oj", source: { kind: "github", where: "PR #88", when: "today" } },
  { id: "t8", title: "Encrypted R2 reports", project: "a", status: "done", owner: "ve", source: { kind: "github", where: "PR #81", when: "Mon" } },
  { id: "t9", title: "Motion-test queue fix", project: "b", status: "todo", owner: "oj", due: "today", source: discord("#emmarie", "Tue 16:40", "queue timed out again on the project's Durable Object") },
  { id: "t10", title: "Storyboard screen polish", project: "b", status: "todo", owner: "sa", due: "Mon", source: { kind: "meet", where: "Emmarie sync", when: "yesterday" } },
  { id: "t11", title: "Hook analysis: 20 reels", project: "c", status: "todo", owner: "so", due: "Mon", source: { kind: "whatsapp", where: "Abhishek", when: "today" } },
];

export const decisions: Decision[] = [
  { id: "d1", title: "Score all seven model families", project: "a", by: ["ve", "oj"], at: "today 11:20", affects: "2 tasks · replaces the 3-model pilot", source: discord("#veriq", "today 11:20") },
  { id: "d2", title: "Board report before Practitioner", project: "a", by: ["ve"], at: "today 14:05", affects: "Veriq timeline", source: { kind: "meet", where: "Weekly sync", when: "today 14:05" } },
  { id: "d3", title: "Hooks in the first two seconds", project: "c", by: ["ab"], at: "today 16:40", affects: "1 task", source: { kind: "whatsapp", where: "Abhishek", when: "today 16:40" } },
];

export const proposals: Proposal[] = [
  { id: "p1", kind: "new_task", summary: "Board report PDF export · Saish · due Fri", project: "a", confidence: 0.86, source: discord("#veriq", "today 10:42", "on it, Board report PDF export by Friday") },
  { id: "p2", kind: "status", summary: "AI Overview lane moves to Done", project: "a", confidence: 0.93, source: discord("#veriq", "today 10:31", "AI Overview lane is green again") },
  { id: "p3", kind: "deadline", summary: "Emmarie demo moves to Oct 30", project: "b", confidence: 0.74, source: { kind: "meet", where: "Emmarie sync", when: "14:05" } },
  { id: "p4", kind: "route", summary: "Caption style guide for reels", options: ["b", "c"], confidence: 0.55, source: { kind: "whatsapp", where: "Abhishek", when: "today", quote: "can someone write a caption style guide?" } },
];

export const person = (id?: string) => people.find((p) => p.id === id);
export const project = (id?: string) => projects.find((p) => p.id === id);

export const statusLabel: Record<Status, string> = {
  proposed: "Proposed",
  todo: "To do",
  in_progress: "In progress",
  blocked: "Blocked",
  done: "Done",
};

export const agentPack = {
  person: "so",
  project: "b",
  steps: [
    { label: "Repo invite accepted", state: "done" },
    { label: "Joined #emmarie and #dev", state: "done" },
    { label: "Get .dev.vars: one-time link, 24h", state: "open", action: "Open" },
    { label: "Connect Noa MCP to your agent", state: "open", action: "Copy" },
    { label: "Read the KT brief (6 min)", state: "open", action: "Read" },
    { label: "First task: Coverage notes v2", state: "open", action: "Start" },
  ],
  files: {
    "CLAUDE.md": `# Emmarie

Writing-first film workspace: screenplay → coverage → storyboard → motion test → final take.
pnpm workspace: React web (Vite, TanStack), Hono Worker with one Durable Object per project.

## Conventions
- Every change goes through the project's event log
- Domain commands read the clock and mint ids only via the command context

## Decisions and why
- Event log is the source of truth (Tue, #emmarie): any earlier version of a film can come back
- Storyboard before motion test (Emmarie sync): directors review frames first

## Ask
- Workers: Ojas · Design: Saish · Lead: Vedant

## Live context
- Noa MCP server: emmarie (see .mcp.json)`,
    "tasks.md": `# Your tasks · Emmarie

- [ ] Coverage notes v2 (handed over from Saish)
      Acceptance: notes per scene, linked to the screenplay version
      Source: #emmarie, Tue 16:12
- [ ] Motion-test retry (unowned; you were suggested)`,
    ".mcp.json": `{
  "mcpServers": {
    "noa": {
      "type": "http",
      "url": "https://noa.example/mcp/emmarie",
      "headers": { "Authorization": "Bearer <your personal token>" }
    }
  }
}`,
  } as Record<string, string>,
};

export const ktBrief = [
  { title: "Purpose", body: "Writing-first film workspace; demo on Oct 30", src: "Project" },
  { title: "Open work", body: "9 tasks, 1 blocked on the motion-test queue", src: "Tasks" },
  { title: "Key decisions", body: "Event log is the source of truth; storyboard before motion test", src: "#emmarie, Emmarie sync" },
  { title: "People to meet", body: "Ojas (Workers), Saish (design), Vedant (lead)", src: "KNOWS_ABOUT" },
  { title: "Read first", body: "architecture.md, docs/explainers", src: "Repo" },
];

/* ---- Additional sample data for the app layouts ---- */

export const projectMeta: Record<string, { description: string; members: string[]; progress: number; channels: string[]; client?: string }> = {
  a: { description: "AI reputation reports: how seven AI model families answer about a brand.", members: ["ve", "sa", "so", "oj"], progress: 64, channels: ["#veriq", "#dev"], client: "Brand clients" },
  b: { description: "Writing-first film workspace: screenplay to storyboard to final take.", members: ["oj", "sa"], progress: 41, channels: ["#emmarie"], client: "Internal" },
  c: { description: "Why videos hold attention: hooks, beats and edits across reels and long video.", members: ["ab", "so"], progress: 28, channels: ["#video-break", "WhatsApp: Abhishek"], client: "Research" },
  d: { description: "Chat memory and decisions with sources. Its history moves into Noa.", members: ["ve"], progress: 86, channels: ["#tulpa"], client: "Internal" },
};

export type HistoryEntry = { at: string; who: string; what: string };
export const taskHistory: Record<string, HistoryEntry[]> = {
  t1: [
    { at: "today 10:42", who: "Noa", what: "Proposed from Saish's reply in #veriq" },
    { at: "today 10:44", who: "Vedant", what: "Opened the proposal" },
  ],
  t6: [
    { at: "Tue 16:12", who: "Noa", what: "Marked blocked: “still waiting on the brand's logo pack”" },
    { at: "Mon 11:00", who: "Saish", what: "Moved to In progress" },
    { at: "Mon 09:30", who: "Noa", what: "Created from weekly sync" },
  ],
};

export type Notification = { id: string; kind: "approval" | "mention" | "shift" | "decision"; text: string; at: string; unread: boolean };
export const notifications: Notification[] = [
  { id: "n1", kind: "approval", text: "Saish wants to move Board report PDF to Monday", at: "2m", unread: true },
  { id: "n2", kind: "mention", text: "Ojas mentioned you in #emmarie", at: "18m", unread: true },
  { id: "n3", kind: "shift", text: "Soha starts on Emmarie Monday. Pack sent.", at: "1h", unread: false },
  { id: "n4", kind: "decision", text: "Decided: score all seven model families", at: "3h", unread: false },
];

export type Connector = { id: string; name: string; status: "connected" | "available" | "error"; detail: string };
export const connectors: Connector[] = [
  { id: "discord", name: "Discord", status: "connected", detail: "NotYourIdea server · 9 channels" },
  { id: "slack", name: "Slack", status: "available", detail: "Events API · read mapped channels" },
  { id: "google", name: "Google Workspace", status: "connected", detail: "Meet transcripts, Calendar" },
  { id: "whatsapp", name: "WhatsApp (Kapso)", status: "connected", detail: "1 number · 3 templates" },
  { id: "github", name: "GitHub", status: "available", detail: "Close cards when PRs merge" },
];

export const channelMap: { channel: string; source: string; project: string; ingest: boolean }[] = [
  { channel: "#veriq", source: "Discord", project: "a", ingest: true },
  { channel: "#dev", source: "Discord", project: "split", ingest: true },
  { channel: "#emmarie", source: "Discord", project: "b", ingest: true },
  { channel: "#video-break", source: "Discord", project: "c", ingest: true },
  { channel: "#tulpa", source: "Discord", project: "d", ingest: true },
  { channel: "#random", source: "Discord", project: "off", ingest: false },
];

export const roleLabel: Record<Role, string> = {
  superadmin: "Superadmin",
  org_admin: "Org admin",
  pm: "PM / lead",
  member: "Member",
  guest: "Guest",
};

export const accessBundles: Record<string, { item: string; auto: boolean }[]> = {
  b: [
    { item: "GitHub team: emmarie", auto: true },
    { item: "Discord role: Emmarie", auto: true },
    { item: "Drive folder: Emmarie / Scripts", auto: true },
    { item: "Cloudflare .dev.vars (one-time link)", auto: false },
    { item: "Figma file: Emmarie storyboard", auto: false },
  ],
};
