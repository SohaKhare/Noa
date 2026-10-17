"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { decideChange, getChanges, getDecisions, getDirectory, getProposals, getTasks, updateTask, type WorkChange, type MessageSource, type TaskStatus, type WorkPerson, type WorkProject, type WorkTask } from "./api";
import type { Source } from "./mock";
import { currentMembership, useMe } from "./session";

/* Work data from the API (1.24): the directory (people, projects, channels), tasks and the Inbox. */

export function useOrgId() {
  const { user } = useMe();
  return currentMembership(user)?.org.id ?? null;
}

export function useDirectory() {
  const orgId = useOrgId();
  const query = useQuery({ queryKey: ["directory", orgId], queryFn: () => getDirectory(orgId!), enabled: !!orgId, staleTime: 60_000 });
  const data = query.data;
  return {
    ...query,
    orgId,
    me: data?.me ?? null,
    people: data?.people ?? [],
    projects: data?.projects ?? [],
    channels: data?.channels ?? [],
    person: (id?: string | null) => data?.people.find((p) => p.id === id),
    /* The person behind a user account (change records name users). */
    byUser: (userId?: string | null) => data?.people.find((p) => p.user_id === userId),
    project: (id?: string | null) => data?.projects.find((p) => p.id === id || p.key === id),
  };
}

export function useTasks(filters: { project_id?: string; owner_id?: string; open?: boolean } = {}) {
  const orgId = useOrgId();
  return useQuery({
    queryKey: ["tasks", orgId, filters],
    queryFn: () => getTasks(orgId!, filters),
    enabled: !!orgId && Object.values(filters).every((v) => v !== ""),
  });
}

export function useDecisions(filters: { project_id?: string; since?: string } = {}) {
  const orgId = useOrgId();
  return useQuery({ queryKey: ["decisions", orgId, filters], queryFn: () => getDecisions(orgId!, filters), enabled: !!orgId });
}

/* Midnight today, local time, as ISO: "decided today" means since then. */
export const startOfToday = () => {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return d.toISOString();
};

export function useProposals() {
  const orgId = useOrgId();
  return useQuery({ queryKey: ["proposals", orgId], queryFn: () => getProposals(orgId!), enabled: !!orgId });
}

/* Moves a card (board drag, My day checkbox), updating every cached task list at once. */
export function useMoveTask() {
  const orgId = useOrgId();
  const client = useQueryClient();
  return useMutation({
    mutationFn: ({ id, status }: { id: string; status: TaskStatus }) => updateTask(orgId!, id, { status }),
    onMutate: async ({ id, status }) => {
      await client.cancelQueries({ queryKey: ["tasks", orgId] });
      const before = client.getQueriesData<WorkTask[]>({ queryKey: ["tasks", orgId] });
      client.setQueriesData<WorkTask[]>({ queryKey: ["tasks", orgId] }, (ts) => ts?.map((t) => (t.id === id ? { ...t, status } : t)));
      return { before };
    },
    onError: (_e, _v, ctx) => ctx?.before.forEach(([key, data]) => client.setQueryData(key, data)),
    onSettled: () => {
      client.invalidateQueries({ queryKey: ["tasks", orgId] });
      client.invalidateQueries({ queryKey: ["changes", orgId] });
    },
  });
}

/* Edits a task's shared fields. A member's deadline change comes back as a pending change for their lead (2.20). */
export function useEditTask() {
  const orgId = useOrgId();
  const client = useQueryClient();
  return useMutation({
    mutationFn: ({ id, ...data }: { id: string; due_on?: string | null; title?: string; owner_id?: string | null; reason?: string }) => updateTask(orgId!, id, data),
    onSettled: () => {
      client.invalidateQueries({ queryKey: ["tasks", orgId] });
      client.invalidateQueries({ queryKey: ["changes", orgId] });
    },
  });
}

export function useChanges(filters: { task_id?: string; project_id?: string; status?: WorkChange["status"] } = {}, enabled = true) {
  const orgId = useOrgId();
  return useQuery({ queryKey: ["changes", orgId, filters], queryFn: () => getChanges(orgId!, filters), enabled: !!orgId && enabled });
}

/* Approve, reject or revert a change record. */
export function useDecideChange() {
  const orgId = useOrgId();
  const client = useQueryClient();
  return useMutation({
    mutationFn: ({ id, action }: { id: string; action: "approve" | "reject" | "revert" }) => decideChange(orgId!, id, action),
    onSettled: () => {
      client.invalidateQueries({ queryKey: ["tasks", orgId] });
      client.invalidateQueries({ queryKey: ["changes", orgId] });
    },
  });
}

const statusName: Record<string, string> = { todo: "To do", in_progress: "In progress", blocked: "Blocked", done: "Done" };
const shortDate = (iso: string | null) => (iso ? new Date(`${iso}T00:00:00`).toLocaleDateString("en", { month: "short", day: "numeric" }) : "no date");

/* "deadline Oct 17 → Oct 20", "status To do → Blocked", "owner Saish → Soha". */
export function changeText(c: WorkChange, personName: (id: string | null) => string | undefined) {
  switch (c.kind) {
    case "deadline":
      return `deadline ${shortDate(c.old_value)} → ${shortDate(c.new_value)}`;
    case "status":
      return `status ${statusName[c.old_value ?? ""] ?? c.old_value} → ${statusName[c.new_value ?? ""] ?? c.new_value}`;
    case "owner":
      return `owner ${personName(c.old_value) ?? "nobody"} → ${personName(c.new_value) ?? "nobody"}`;
    case "title":
      return `title → “${c.new_value}”`;
    case "scope":
      return "scope changed";
  }
}

/* "VE" for Vedant, like the chat avatars on the landing page. */
export const nameInitials = (name?: string | null) => (name ?? "?").trim().slice(0, 2).toUpperCase();

export const projectChannels = (project: WorkProject, channels: { name: string; project_id: string | null }[]) =>
  channels.filter((c) => c.project_id === project.id).map((c) => c.name);

export const projectPeople = (project: WorkProject, people: WorkPerson[]) =>
  project.allocations.map((a) => ({ person: people.find((p) => p.id === a.person_id), percent: a.percent })).filter((x) => x.person) as {
    person: WorkPerson;
    percent: number;
  }[];

/* A stored message source as the SourceChip shows it. */
export function toSource(s: MessageSource | null | undefined): Source {
  const where = s?.channel ?? "Noa";
  const kind = /whatsapp/i.test(where) ? "whatsapp" : /slack/i.test(where) ? "slack" : /meet|sync/i.test(where) ? "meet" : "discord";
  return { kind, where, when: s?.at ? ago(s.at) : "", quote: s?.quote };
}

export function ago(iso: string, now = Date.now()) {
  const mins = Math.round((now - new Date(iso).getTime()) / 60_000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.round(mins / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.round(hours / 24);
  return days === 1 ? "yesterday" : `${days}d ago`;
}

const day = (d: Date) => Date.UTC(d.getFullYear(), d.getMonth(), d.getDate());

/* "today", "tomorrow", "Fri" within the week, "Oct 24" after, "2d late" when overdue. */
export function dueLabel(iso?: string | null, now = new Date()) {
  if (!iso) return null;
  const [y, m, d] = iso.split("-").map(Number);
  const date = new Date(y, m - 1, d);
  const diff = Math.round((day(date) - day(now)) / 86_400_000);
  if (diff < 0) return `${-diff}d late`;
  if (diff === 0) return "today";
  if (diff === 1) return "tomorrow";
  if (diff < 7) return date.toLocaleDateString("en", { weekday: "short" });
  return date.toLocaleDateString("en", { month: "short", day: "numeric" });
}

export const isLate = (iso?: string | null) => !!iso && (dueLabel(iso)?.endsWith("late") ?? false);
