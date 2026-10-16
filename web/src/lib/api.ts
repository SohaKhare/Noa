/*
  Client for the Phoenix API (api/). Auth is an httpOnly session cookie set by the API,
  so every call sends credentials. Shapes match api/lib/noa_web/payload.ex.
  Work data (tasks, projects) still comes from lib/mock.ts until those APIs exist.
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

export const roleLabel: Record<Role, string> = { org_admin: "Admin · lead", pm: "PM / lead", member: "Member", guest: "Guest" };
