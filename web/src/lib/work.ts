"use client";

import { useQuery } from "@tanstack/react-query";
import { getDirectory, getProposals, getTasks, type MessageSource, type WorkPerson, type WorkProject } from "./api";
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

export function useProposals() {
  const orgId = useOrgId();
  return useQuery({ queryKey: ["proposals", orgId], queryFn: () => getProposals(orgId!), enabled: !!orgId });
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
