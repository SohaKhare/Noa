/*
  Client for the Phoenix API (api/). Auth is an httpOnly session cookie set by the API,
  so every call sends credentials. Shapes match api/lib/noa_web/payload.ex.
  Projects, people, tasks and the Inbox come from the work API (1.24). Pages not wired
  yet still read lib/mock.ts.
*/

// Tolerate a trailing slash in the setting ("https://api.example.com/").
export const API_URL = (process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:4000").replace(/\/+$/, "");

export type Role = "org_admin" | "pm" | "member" | "guest";
export type Org = { id: string; name: string; slug: string; allowed_domains: string[] };
export type Membership = { id: string; role: Role; title: string | null; org: Org };
export type User = {
  id: string;
  email: string;
  name: string | null;
  is_superadmin: boolean;
  home: string;
  memberships: Membership[];
};
export type Member = {
  id: string;
  role: Role;
  title: string | null;
  reports_to_id: string | null;
  reports_to_name: string | null;
  user: { id: string; email: string; name: string | null };
};
export type Invite = { id: string; email: string; role: Role; title: string | null; status: string; expires_at: string };
export type InviteInfo = {
  email: string;
  role: Role;
  title: string | null;
  expires_at: string;
  org: { name: string };
  has_account: boolean;
};
export type PlatformOrg = Org & {
  admins: string[];
  member_count: number;
  pending_invites: number;
  llm_24h?: { calls: number; errors: number; avg_ms: number | null; approx_tokens: number };
};

export class ApiError extends Error {
  constructor(
    public status: number,
    public code: string,
    message: string,
    public fields: Record<string, string> = {},
  ) {
    super(message);
  }
}

export async function api<T>(path: string, init: RequestInit = {}): Promise<T> {
  let res: Response;
  try {
    res = await fetch(`${API_URL}${path}`, {
      ...init,
      credentials: "include",
      headers: { accept: "application/json", "content-type": "application/json", ...(init.headers ?? {}) },
    });
  } catch {
    throw new ApiError(0, "offline", "Can't reach the Noa API. Is it running on " + API_URL + "?");
  }
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new ApiError(res.status, body.error ?? "error", body.message ?? `Request failed (${res.status})`, body.fields);
  return body as T;
}

const post = <T>(path: string, data?: unknown) => api<T>(path, { method: "POST", body: JSON.stringify(data ?? {}) });

// Session
export const getMe = () => api<{ user: User }>("/api/me").then((r) => r.user);
export const signIn = (email: string, password: string) =>
  post<{ user: User }>("/auth/user/password/sign_in", { user: { email, password } }).then((r) => r.user);
export const requestMagicLink = (email: string) => post("/auth/user/magic_link/request", { user: { email } });
export const requestPasswordReset = (email: string) => post("/auth/user/password/reset_request", { user: { email } });
export const resetPassword = (token: string, password: string) =>
  post<{ user: User }>("/auth/user/password/reset", { user: { reset_token: token, password } }).then((r) => r.user);
export const signOut = () => api("/api/session", { method: "DELETE" });

// Invites (before sign-in)
export const getInvite = (token: string) => api<{ invite: InviteInfo }>(`/api/invites/${token}`).then((r) => r.invite);
export const acceptInvite = (token: string, name: string, password: string) =>
  post<{ user: User }>(`/api/invites/${token}/accept`, { name, password }).then((r) => r.user);

// Org people
export const getMembers = (orgId: string) => api<{ org: Org; members: Member[] }>(`/api/orgs/${orgId}/members`);
export const updateMember = (orgId: string, id: string, data: Partial<Pick<Member, "role" | "title" | "reports_to_id">>) =>
  api<{ member: Member }>(`/api/orgs/${orgId}/members/${id}`, { method: "PATCH", body: JSON.stringify(data) });
export const removeMember = (orgId: string, id: string) => api(`/api/orgs/${orgId}/members/${id}`, { method: "DELETE" });
export const getInvites = (orgId: string) => api<{ invites: Invite[] }>(`/api/orgs/${orgId}/invites`).then((r) => r.invites);
export const createInvite = (orgId: string, data: { email: string; role: Role; title?: string }) =>
  post<{ invite: Invite; url: string }>(`/api/orgs/${orgId}/invites`, data);
export const revokeInvite = (orgId: string, id: string) => api(`/api/orgs/${orgId}/invites/${id}`, { method: "DELETE" });

// Platform (superadmin)
export type Connectors = {
  discord: { connected: boolean; bot: boolean; guild_id: string | null; invite_url: string | null; channels: number };
  whatsapp: { connected: boolean; webhook: string };
  github: {
    connected: boolean;
    app: boolean;
    installed: boolean;
    install_url: string | null;
    secret_set: boolean;
    token_set: boolean;
    webhook: string;
    repos: { project: string; repo: string }[];
  };
  email: { connected: boolean };
  openai: { connected: boolean };
};
export const getConnectors = (orgId: string) => api<Connectors>(`/api/orgs/${orgId}/connectors`);
export const connectDiscord = (orgId: string, guildId: string) =>
  api<{ ok: true }>(`/api/orgs/${orgId}/connectors/discord`, { method: "PUT", body: JSON.stringify({ guild_id: guildId }) });
export const getGithubRepos = (orgId: string) => api<{ repos: string[]; error?: string }>(`/api/orgs/${orgId}/connectors/github/repos`);
export const disconnectConnector = (orgId: string, kind: "discord" | "github" | "github_app") => api<{ ok: true }>(`/api/orgs/${orgId}/connectors/${kind}`, { method: "DELETE" });
export const rotateGithubSecret = (orgId: string) => post<{ secret: string; webhook: string }>(`/api/orgs/${orgId}/connectors/github/secret`);
export const setGithubToken = (orgId: string, token: string) =>
  api<{ ok: true }>(`/api/orgs/${orgId}/connectors/github/token`, { method: "PUT", body: JSON.stringify({ token }) });
export const backfillGithub = (orgId: string) =>
  post<{ results: { project: string; recorded?: number; error?: string }[] }>(`/api/orgs/${orgId}/connectors/github/backfill`);
export const getPlatformOrgs = () => api<{ orgs: PlatformOrg[] }>("/api/platform/orgs").then((r) => r.orgs);
export type PlatformStatus = {
  services: Record<"database" | "graph" | "openai" | "whatsapp" | "whatsapp_webhook" | "discord" | "github" | "email", boolean>;
  readers: { name: string; label: string; running: boolean; position: number; latest: number; behind: number }[];
  jobs: Record<string, Record<string, number>>;
};
export const getPlatformStatus = () => api<PlatformStatus>("/api/platform/status");
export const createWorkspace = (data: { name: string; domains: string; admin_email: string; admin_title?: string }) =>
  post<{ org: Org; invite: Invite; url: string }>("/api/platform/orgs", data);

// Visible Google Meet bot; transcripts hand off to the shared Meetings minutes/review pipeline.
export type MeetingLine = { speaker: string; seq: number; start_ms: number; end_ms: number; text: string };
export type MeetingSession = {
  id: string; status: "joining" | "running" | "stopped" | "ready" | "imported" | "failed";
  meeting_url: string; consent_at: string; suggested_project_id: string | null;
  transcript: MeetingLine[]; imported_meeting_id: string | null;
  channels: { id: string; name: string; project_id: string | null; read: boolean }[];
};
export const getMeetings = (orgId: string) => api<{ meetings: MeetingSession[] }>(`/api/orgs/${orgId}/google_meetings`).then((r) => r.meetings);
export const startMeeting = (orgId: string, meeting_url: string) =>
  post<{ meeting: MeetingSession }>(`/api/orgs/${orgId}/google_meetings`, { meeting_url, consent: true }).then((r) => r.meeting);
export const meetingAction = (orgId: string, id: string, action: "stop" | "sync" | "import", data: Record<string, string> = {}) =>
  post<{ meeting: MeetingSession; imported_meeting_id?: string; pipeline_status?: string }>(`/api/orgs/${orgId}/google_meetings/${id}/${action}`, data);

// Work (1.24)
export type TaskStatus = "todo" | "in_progress" | "blocked" | "done";
export type Allocation = { person_id: string; project_id: string; percent: number; role: string | null; starts_on: string; ends_on?: string | null };
export type WorkPerson = {
  id: string;
  key: string;
  name: string;
  title: string | null;
  handles: string[];
  joined: boolean;
  role: Role | null;
  user_id: string | null;
  allocations: Allocation[];
};
export type WorkProject = {
  id: string;
  key: string;
  name: string;
  about: string | null;
  repo: string | null;
  status: "active" | "paused" | "done";
  lead_id: string | null;
  aliases: string[];
  allocations: Allocation[];
};
export type Channel = { id: string; platform: "discord" | "slack" | "whatsapp" | "email"; name: string; project_id: string | null; split: boolean; read: boolean };
export type Directory = { me: string | null; people: WorkPerson[]; projects: WorkProject[]; channels: Channel[] };
export type MessageSource = { channel?: string; author?: string; at?: string; quote?: string; episode_id?: string };
export type WorkTask = {
  id: string;
  title: string;
  detail: string | null;
  status: TaskStatus;
  due_on: string | null;
  blocked_reason: string | null;
  project_id: string;
  owner_id: string | null;
  source: MessageSource | null;
  done_at: string | null;
  inserted_at: string;
};
export type ProposalKind = "task" | "status_change" | "deadline_change" | "decision" | "scope_change" | "assignment";
export type WorkProposal = {
  id: string;
  kind: ProposalKind;
  summary: string;
  data: Record<string, unknown> & {
    title?: string;
    due?: string;
    new_due?: string;
    status?: TaskStatus;
    route?: { rule: string; candidates?: string[] };
    duplicate_of?: { task_id: string; title: string };
    auto?: boolean;
    undone?: boolean;
    /* Assignment proposals from the triage agent (3.24). */
    trigger?: "unowned" | "moved" | "overdue";
    reason?: string;
    why?: string[];
    graph_route?: string[];
    graph?: boolean;
    from_owner_id?: string | null;
    candidates?: { person_id: string; name: string; score: number }[];
  };
  confidence: number | null;
  source: MessageSource | null;
  status: "pending" | "approved" | "rejected";
  project_id: string | null;
  owner_id: string | null;
  task_id: string | null;
  inserted_at: string;
};
export type ApproveEdits = { summary?: string; project_id?: string; owner_id?: string; data?: { title?: string; due?: string; new_due?: string } };

export const getDirectory = (orgId: string) => api<Directory>(`/api/orgs/${orgId}/directory`);
export const getTasks = (orgId: string, filters: { project_id?: string; owner_id?: string; open?: boolean } = {}) => {
  const q = new URLSearchParams(Object.entries(filters).filter(([, v]) => v !== undefined && v !== false).map(([k, v]) => [k, String(v)]));
  return api<{ tasks: WorkTask[] }>(`/api/orgs/${orgId}/tasks${q.size ? `?${q}` : ""}`).then((r) => r.tasks);
};
export const createTask = (orgId: string, data: Partial<WorkTask> & { title: string; project_id: string }) =>
  post<{ task: WorkTask }>(`/api/orgs/${orgId}/tasks`, data).then((r) => r.task);
export const updateTask = (
  orgId: string,
  id: string,
  data: Partial<Pick<WorkTask, "title" | "detail" | "status" | "due_on" | "blocked_reason" | "owner_id" | "project_id">> & { reason?: string },
) => api<{ task: WorkTask; pending_changes: WorkChange[] }>(`/api/orgs/${orgId}/tasks/${id}`, { method: "PATCH", body: JSON.stringify(data) });
export type ChangeKind = "deadline" | "scope" | "owner" | "status" | "title";
export type WorkChange = {
  id: string;
  kind: ChangeKind;
  old_value: string | null;
  new_value: string | null;
  reason: string | null;
  status: "applied" | "pending" | "rejected" | "reverted";
  source: MessageSource | null;
  task_id: string;
  project_id: string;
  requested_by_id: string | null;
  decided_by_id: string | null;
  decided_at: string | null;
  inserted_at: string;
};
export const getChanges = (orgId: string, filters: { task_id?: string; project_id?: string; status?: WorkChange["status"] } = {}) => {
  const q = new URLSearchParams(Object.entries(filters).filter(([, v]) => v) as [string, string][]).toString();
  return api<{ changes: WorkChange[] }>(`/api/orgs/${orgId}/changes${q ? `?${q}` : ""}`).then((r) => r.changes);
};
export const decideChange = (orgId: string, id: string, action: "approve" | "reject" | "revert") =>
  api<{ change: WorkChange }>(`/api/orgs/${orgId}/changes/${id}/${action}`, { method: "POST" }).then((r) => r.change);
/* Workspace setup (1.18): org admins and PMs; channels and imports are admins only. */
export const createProject = (orgId: string, data: { name: string; about?: string; repo?: string; lead_id?: string }) =>
  post<{ project: WorkProject }>(`/api/orgs/${orgId}/projects`, data).then((r) => r.project);
export const updateProject = (orgId: string, id: string, data: { name?: string; about?: string | null; repo?: string | null; lead_id?: string | null }) =>
  api<{ project: WorkProject }>(`/api/orgs/${orgId}/projects/${id}`, { method: "PATCH", body: JSON.stringify(data) }).then((r) => r.project);
export const createPerson = (orgId: string, data: { name: string; title?: string; email?: string; handles?: string[] }) =>
  post<{ person: WorkPerson }>(`/api/orgs/${orgId}/people`, data).then((r) => r.person);
export const addMembersAsPeople = (orgId: string) => post<{ added: number }>(`/api/orgs/${orgId}/people/from_members`).then((r) => r.added);
export const setAllocation = (orgId: string, data: { person_id: string; project_id: string; percent: number }) =>
  api<{ allocation: Allocation | null }>(`/api/orgs/${orgId}/allocations`, { method: "PUT", body: JSON.stringify(data) }).then((r) => r.allocation);
export const createChannel = (orgId: string, data: { name: string; external_id?: string; project_id?: string | null; split?: boolean; backfill?: boolean }) =>
  post<{ channel: Channel }>(`/api/orgs/${orgId}/channels`, data).then((r) => r.channel);
export type ServerChannel = {
  id: string;
  name: string;
  mapped: boolean;
  channel_id: string | null;
  project_id: string | null;
  split: boolean;
  read: boolean;
  messages: number;
};
export const getDiscordChannels = (orgId: string) =>
  api<{ connected: boolean; channels: ServerChannel[]; stale: { channel_id: string; name: string; messages: number }[] }>(`/api/orgs/${orgId}/discord/channels`);
export const backfillChannel = (orgId: string, channelId: string) =>
  post<{ backfill: "queued" | "already_queued" | "discord_off" | "skipped" | "failed" }>(`/api/orgs/${orgId}/channels/${channelId}/backfill`);
export const deleteChannel = (orgId: string, channelId: string) => api<{ ok: true }>(`/api/orgs/${orgId}/channels/${channelId}`, { method: "DELETE" });
export const importOrgMap = (orgId: string, seed: unknown) => post<{ loaded: Record<string, number> }>(`/api/orgs/${orgId}/import`, { seed }).then((r) => r.loaded);

export const updateChannel = (orgId: string, id: string, data: Partial<Pick<Channel, "project_id" | "split" | "read">>) =>
  api<{ channel: Channel }>(`/api/orgs/${orgId}/channels/${id}`, { method: "PATCH", body: JSON.stringify(data) }).then((r) => r.channel);
export type WorkDecision = {
  id: string;
  statement: string;
  kind: "decision" | "conclusion";
  status: "active" | "superseded";
  affects: string[];
  source: MessageSource | null;
  project_id: string | null;
  made_by_id: string | null;
  superseded_by_id: string | null;
  inserted_at: string;
};
export const getDecisions = (orgId: string, filters: { project_id?: string; since?: string; status?: "active" | "superseded" } = {}) => {
  const q = new URLSearchParams(Object.entries(filters).filter(([, v]) => v) as [string, string][]).toString();
  return api<{ decisions: WorkDecision[] }>(`/api/orgs/${orgId}/decisions${q ? `?${q}` : ""}`).then((r) => r.decisions);
};
export type Citation = {
  id: string;
  kind: "task" | "decision" | "message" | "shift" | "expert" | "path";
  via?: string | null;
  title: string;
  text: string;
  href: string | null;
  project_id: string | null;
  status: string | null;
  source: MessageSource | null;
};
export const ask = (orgId: string, question: string) =>
  api<{ answer: string; citations: Citation[]; retrieval?: { store: "falkordb" | "postgres"; routes: string[] } }>(`/api/orgs/${orgId}/ask`, { method: "POST", body: JSON.stringify({ question }) });
export type ShiftPlanTask = { task_id: string; title: string; status: TaskStatus; due_on: string | null; to_owner_id: string | null };
export type WorkShift = {
  id: string;
  person_id: string;
  from_project_id: string | null;
  to_project_id: string | null;
  percent: number;
  starts_on: string;
  routes_until: string | null;
  handover: { task_id: string; title: string; to_owner_id: string | null }[];
  note: string | null;
  inserted_at: string;
};
export const planShift = (orgId: string, personId: string, fromProjectId: string | null) =>
  api<{ tasks: ShiftPlanTask[] }>(
    `/api/orgs/${orgId}/shifts/plan?person_id=${personId}&from_project_id=${fromProjectId ?? ""}`,
  ).then((r) => r.tasks);
export const createShift = (
  orgId: string,
  body: { person_id: string; from_project_id: string | null; to_project_id: string | null; percent?: number; starts_on?: string; handover: Record<string, string>; note?: string },
) => api<{ shift: WorkShift }>(`/api/orgs/${orgId}/shifts`, { method: "POST", body: JSON.stringify(body) }).then((r) => r.shift);
export const getShifts = (orgId: string) => api<{ shifts: WorkShift[] }>(`/api/orgs/${orgId}/shifts`).then((r) => r.shifts);
export type BriefItem = { text: string; href: string | null; source: MessageSource | null };
export type Brief = { project_id: string; person_id: string | null; sections: { title: string; items: BriefItem[] }[] };
export const getBrief = (orgId: string, projectId: string, personId?: string | null) =>
  api<Brief>(`/api/orgs/${orgId}/projects/${projectId}/brief${personId ? `?person_id=${personId}` : ""}`);
/* Downloads brief.md (3.19) through the browser, with the session cookie. */
export async function downloadBrief(orgId: string, projectId: string, personId?: string | null) {
  const q = new URLSearchParams({ format: "md", ...(personId ? { person_id: personId } : {}) });
  const res = await fetch(`${API_URL}/api/orgs/${orgId}/projects/${projectId}/brief?${q}`, { credentials: "include" });
  if (!res.ok) throw new ApiError(res.status, "error", "Couldn't download the brief.");
  const name = res.headers.get("content-disposition")?.match(/filename="([^"]+)"/)?.[1] ?? "brief.md";
  const url = URL.createObjectURL(await res.blob());
  const a = Object.assign(document.createElement("a"), { href: url, download: name });
  a.click();
  URL.revokeObjectURL(url);
}
export type Pack = {
  project: { id: string; key: string; name: string };
  person: { id: string; name: string } | null;
  store: "falkordb" | "postgres";
  files: { path: string; content: string }[];
  steps: { label: string; kind: string }[];
};
export const getPack = (orgId: string, projectId: string, personId?: string | null) =>
  api<Pack>(`/api/orgs/${orgId}/projects/${projectId}/pack${personId ? `?person_id=${personId}` : ""}`);
export type FeedItem = { id: string; kind: "approval" | "change" | "decision" | "shift" | "pack"; text: string; at: string; href: string | null };
export const getFeed = (orgId: string) => api<{ items: FeedItem[] }>(`/api/orgs/${orgId}/feed`).then((r) => r.items);
export type McpToken = { id: string; name: string; inserted_at: string; last_used_at: string | null };
export const getMcpTokens = (orgId: string) => api<{ tokens: McpToken[]; url: string }>(`/api/orgs/${orgId}/mcp_tokens`);
export const createMcpToken = (orgId: string, name: string) =>
  api<{ token: string; info: McpToken; url: string }>(`/api/orgs/${orgId}/mcp_tokens`, { method: "POST", body: JSON.stringify({ name }) });
export const revokeMcpToken = (orgId: string, id: string) => api<unknown>(`/api/orgs/${orgId}/mcp_tokens/${id}`, { method: "DELETE" });
export type WhatsAppMessage = {
  id: string;
  person_id: string | null;
  direction: "in" | "out";
  kind: string;
  body: string | null;
  buttons: Record<string, string> | null;
  status: "sent" | "simulated" | "failed" | "received";
  inserted_at: string;
};
export const getWhatsApp = (orgId: string) =>
  api<{ configured: boolean; scope: "workspace" | "you"; messages: WhatsAppMessage[] }>(`/api/orgs/${orgId}/whatsapp`);
export type GraphNode = { id: string; label: string; name: string };
export type GraphView = { nodes: GraphNode[]; edges: { from: string; to: string; type: string }[]; graph: boolean };
export const getGraph = (orgId: string, projectId: string) => api<GraphView>(`/api/orgs/${orgId}/graph?project_id=${projectId}`);
export const getGraphPath = (orgId: string, from: string, to: string) =>
  api<{ path: string[] }>(`/api/orgs/${orgId}/graph/path?from=${encodeURIComponent(from)}&to=${encodeURIComponent(to)}`).then((r) => r.path);
export const getDiscordAccount = (orgId: string) =>
  api<{ discord_id: string | null }>(`/api/orgs/${orgId}/me/discord`);
export const linkDiscordAccount = (orgId: string, code: string) =>
  post<{ discord_id: string }>(`/api/orgs/${orgId}/me/discord`, { code });
export const unlinkDiscordAccount = (orgId: string) =>
  api<{ discord_id: null }>(`/api/orgs/${orgId}/me/discord`, { method: "DELETE" });
export type NotifyVia = "whatsapp" | "discord" | "email" | "in_app";
export type NotificationPrefs = {
  notify_via: NotifyVia;
  phone: string | null;
  digest_at: string | null;
  quiet_from: string | null;
  quiet_to: string | null;
  utc_offset: number;
};
export const getNotifications = (orgId: string) =>
  api<{ notifications: NotificationPrefs }>(`/api/orgs/${orgId}/me/notifications`).then((r) => r.notifications);
/* Noa's WhatsApp number and whether your 24-hour window is open (you wrote to Noa in the last day). */
export const getWhatsAppWindow = (orgId: string) =>
  api<{ whatsapp: { number: string | null; window_open: boolean; sending: boolean } }>(`/api/orgs/${orgId}/me/notifications`).then((r) => r.whatsapp);
export const updateNotifications = (orgId: string, data: Partial<NotificationPrefs>) =>
  api<{ notifications: NotificationPrefs }>(`/api/orgs/${orgId}/me/notifications`, { method: "PATCH", body: JSON.stringify(data) }).then(
    (r) => r.notifications,
  );
export type Experts = {
  experts: { person_id: string; name: string; weight: number; share: number }[];
  key_people: { person_id: string; name: string; score: number }[];
  bus_factor: { project_id: string; project: string; person_id: string; name: string; share: number }[];
  groups?: { people: string[]; projects: string[] }[];
  bridges?: { person_id: string; name: string; score: number }[];
  graph: boolean;
};
export const getExperts = (orgId: string, projectId?: string) =>
  api<Experts>(`/api/orgs/${orgId}/experts${projectId ? `?project_id=${projectId}` : ""}`);
/* Triage agent (3.24): file assignment proposals for work nobody is carrying; rank owners for one task. */
export const runTriage = (orgId: string, projectId?: string) =>
  post<{ proposals: WorkProposal[]; checked: number }>(`/api/orgs/${orgId}/triage`, projectId ? { project_id: projectId } : {});
export type OwnerSuggestion = { person_id: string; name: string; score: number; why: string[]; route: string[]; graph: boolean };
export const getOwnerSuggestions = (orgId: string, taskId: string) =>
  api<{ owners: OwnerSuggestion[] }>(`/api/orgs/${orgId}/tasks/${taskId}/owners`).then((r) => r.owners);
export const getProposals = (orgId: string, status: "pending" | "approved" | "rejected" = "pending") =>
  api<{ proposals: WorkProposal[] }>(`/api/orgs/${orgId}/proposals${status === "pending" ? "" : `?status=${status}`}`).then((r) => r.proposals);
export const undoProposal = (orgId: string, id: string) =>
  api<{ proposal: WorkProposal }>(`/api/orgs/${orgId}/proposals/${id}/undo`, { method: "POST" }).then((r) => r.proposal);
export const approveProposal = (orgId: string, id: string, edits: ApproveEdits = {}) =>
  post<{ proposal: WorkProposal; task: WorkTask | null }>(`/api/orgs/${orgId}/proposals/${id}/approve`, edits);
export const rejectProposal = (orgId: string, id: string) => post<{ proposal: WorkProposal }>(`/api/orgs/${orgId}/proposals/${id}/reject`);

/* Joining from the workspace's shared link (1.5): ask with a work email; an org admin approves. */
export type JoinRequest = { id: string; email: string; name: string; note: string | null; inserted_at: string };
export const getJoinInfo = (slug: string) => api<{ org: { name: string; slug: string; domains: string[] } }>(`/api/join/${slug}`).then((r) => r.org);
export const requestToJoin = (slug: string, data: { name: string; email: string; note?: string }) => post<{ ok: true }>(`/api/join/${slug}`, data);
export const getJoinRequests = (orgId: string) => api<{ requests: JoinRequest[] }>(`/api/orgs/${orgId}/join_requests`).then((r) => r.requests);
export const approveJoinRequest = (orgId: string, id: string, role: Role) => post<{ url: string }>(`/api/orgs/${orgId}/join_requests/${id}/approve`, { role });
export const rejectJoinRequest = (orgId: string, id: string) => post<{ ok: true }>(`/api/orgs/${orgId}/join_requests/${id}/reject`);
export const roleLabel: Record<Role, string> = { org_admin: "Admin · lead", pm: "PM / lead", member: "Member", guest: "Guest" };
