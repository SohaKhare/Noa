/*
  Client for the Phoenix API (api/). Auth is an httpOnly session cookie set by the API,
  so every call sends credentials. Shapes match api/lib/noa_web/payload.ex.
  Projects, people, tasks and the Inbox come from the work API (1.24). Pages not wired
  yet still read lib/mock.ts.
*/

export const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:4000";

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
export type PlatformOrg = Org & { admins: string[]; member_count: number; pending_invites: number };

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
export const getPlatformOrgs = () => api<{ orgs: PlatformOrg[] }>("/api/platform/orgs").then((r) => r.orgs);
export const createWorkspace = (data: { name: string; domains: string; admin_email: string; admin_title?: string }) =>
  post<{ org: Org; invite: Invite; url: string }>("/api/platform/orgs", data);

// Work (1.24)
export type TaskStatus = "todo" | "in_progress" | "blocked" | "done";
export type Allocation = { person_id: string; project_id: string; percent: number; role: string | null; starts_on: string };
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
export type Channel = { id: string; platform: "discord" | "slack" | "whatsapp"; name: string; project_id: string | null; split: boolean; read: boolean };
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
export type ProposalKind = "task" | "status_change" | "deadline_change" | "decision" | "scope_change";
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
  kind: "task" | "decision" | "message" | "shift";
  title: string;
  text: string;
  href: string | null;
  project_id: string | null;
  status: string | null;
  source: MessageSource | null;
};
export const ask = (orgId: string, question: string) =>
  api<{ answer: string; citations: Citation[] }>(`/api/orgs/${orgId}/ask`, { method: "POST", body: JSON.stringify({ question }) });
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
export type Experts = {
  experts: { person_id: string; name: string; weight: number; share: number }[];
  key_people: { person_id: string; name: string; score: number }[];
  bus_factor: { project_id: string; project: string; person_id: string; name: string; share: number }[];
  graph: boolean;
};
export const getExperts = (orgId: string, projectId?: string) =>
  api<Experts>(`/api/orgs/${orgId}/experts${projectId ? `?project_id=${projectId}` : ""}`);
export const getProposals = (orgId: string, status: "pending" | "approved" | "rejected" = "pending") =>
  api<{ proposals: WorkProposal[] }>(`/api/orgs/${orgId}/proposals${status === "pending" ? "" : `?status=${status}`}`).then((r) => r.proposals);
export const undoProposal = (orgId: string, id: string) =>
  api<{ proposal: WorkProposal }>(`/api/orgs/${orgId}/proposals/${id}/undo`, { method: "POST" }).then((r) => r.proposal);
export const approveProposal = (orgId: string, id: string, edits: ApproveEdits = {}) =>
  post<{ proposal: WorkProposal; task: WorkTask | null }>(`/api/orgs/${orgId}/proposals/${id}/approve`, edits);
export const rejectProposal = (orgId: string, id: string) => post<{ proposal: WorkProposal }>(`/api/orgs/${orgId}/proposals/${id}/reject`);

export const roleLabel: Record<Role, string> = { org_admin: "Admin · lead", pm: "PM / lead", member: "Member", guest: "Guest" };
