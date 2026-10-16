"use client";

import { CheckIcon, CopyIcon, PaperPlaneTiltIcon, XIcon } from "@phosphor-icons/react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState, type FormEvent } from "react";
import {
  ApiError,
  createInvite,
  getInvites,
  getMembers,
  revokeInvite,
  roleLabel,
  updateMember,
  type Member,
  type Role,
} from "@/lib/api";
import { currentMembership, initials, isOrgAdmin, useMe } from "@/lib/session";
import { FormError } from "./AuthCard";
import { Avatar, Badge, Button, Card } from "./ui";

/* People and roles (1.5, 1.6, 1.22): members, their roles and reporting lines, and invites. */

const roles: Role[] = ["org_admin", "pm", "member", "guest"];
const select = "rounded-lg bg-bg px-2 py-1.5 text-[12.5px] focus:ring-2 focus:ring-accent/30 focus:outline-none disabled:opacity-60";

export function PeopleSettings() {
  const { user } = useMe();
  const membership = currentMembership(user);
  const orgId = membership?.org.id;
  const admin = isOrgAdmin(user);
  const client = useQueryClient();

  const members = useQuery({ queryKey: ["members", orgId], queryFn: () => getMembers(orgId!), enabled: !!orgId });
  const invites = useQuery({ queryKey: ["invites", orgId], queryFn: () => getInvites(orgId!), enabled: !!orgId && admin });

  const update = useMutation({
    mutationFn: ({ id, data }: { id: string; data: Parameters<typeof updateMember>[2] }) => updateMember(orgId!, id, data),
    onSuccess: () => client.invalidateQueries({ queryKey: ["members", orgId] }),
  });

  if (!orgId) return null;
  const list = members.data?.members ?? [];
  const domains = members.data?.org.allowed_domains ?? membership.org.allowed_domains;

  return (
    <div className="space-y-5">
      {admin && <InviteForm orgId={orgId} domains={domains} />}

      <Card className="p-0">
        <div className="border-b border-line px-5 py-4">
          <p className="text-[14px] font-semibold">People in {membership.org.name}</p>
          <p className="text-[12.5px] text-muted">Reporting lines decide who approves deadline and scope changes.</p>
        </div>
        {members.isLoading && <p className="px-5 py-6 text-[13px] text-muted">Loading…</p>}
        {members.error && (
          <div className="p-5">
            <FormError>{(members.error as ApiError).message}</FormError>
          </div>
        )}
        {update.error && (
          <div className="px-5 pt-3">
            <FormError>{(update.error as ApiError).message}</FormError>
          </div>
        )}
        {list.length > 0 && (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[640px] text-[13px]">
              <thead>
                <tr className="border-b border-line text-left text-[11.5px] text-muted">
                  <th className="px-5 py-2.5 font-medium">Person</th>
                  <th className="py-2.5 font-medium">Role</th>
                  <th className="py-2.5 font-medium">Title</th>
                  <th className="px-5 py-2.5 font-medium">Reports to</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-line">
                {list.map((m) => (
                  <MemberRow key={m.id} m={m} all={list} admin={admin} self={m.user.id === user!.id} onChange={(data) => update.mutate({ id: m.id, data })} />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      {admin && (invites.data?.length ?? 0) > 0 && (
        <Card className="p-0">
          <p className="border-b border-line px-5 py-4 text-[14px] font-semibold">Pending invites</p>
          <ul className="divide-y divide-line">
            {invites.data!.map((i) => (
              <li key={i.id} className="flex flex-wrap items-center gap-3 px-5 py-3 text-[13px]">
                <span className="min-w-0 flex-1 truncate font-medium">{i.email}</span>
                <Badge>{i.title || roleLabel[i.role]}</Badge>
                <span className="text-[12px] text-muted">expires {new Date(i.expires_at).toLocaleDateString(undefined, { day: "numeric", month: "short" })}</span>
                <button
                  onClick={async () => {
                    await revokeInvite(orgId, i.id);
                    client.invalidateQueries({ queryKey: ["invites", orgId] });
                  }}
                  className="flex items-center gap-1 rounded-full px-2.5 py-1 text-[12px] text-muted hover:bg-bg hover:text-bad"
                >
                  <XIcon size={12} /> Revoke
                </button>
              </li>
            ))}
          </ul>
        </Card>
      )}
    </div>
  );
}

function MemberRow({
  m,
  all,
  admin,
  self,
  onChange,
}: {
  m: Member;
  all: Member[];
  admin: boolean;
  self: boolean;
  onChange: (data: Partial<Pick<Member, "role" | "title" | "reports_to_id">>) => void;
}) {
  const [title, setTitle] = useState(m.title ?? "");
  const name = m.user.name || m.user.email;

  return (
    <tr>
      <td className="px-5 py-3">
        <span className="flex items-center gap-2.5">
          <Avatar initials={initials(m.user)} size={28} />
          <span className="min-w-0">
            <span className="block truncate font-medium">
              {name}
              {self && <span className="font-normal text-muted"> (you)</span>}
            </span>
            <span className="block truncate text-[11.5px] text-muted">{m.user.email}</span>
          </span>
        </span>
      </td>
      <td>
        {admin && !self ? (
          <select value={m.role} onChange={(e) => onChange({ role: e.target.value as Role })} className={select} aria-label={`Role for ${name}`}>
            {roles.map((r) => (
              <option key={r} value={r}>
                {roleLabel[r]}
              </option>
            ))}
          </select>
        ) : (
          <Badge tone={m.role === "org_admin" ? "accent" : "neutral"}>{roleLabel[m.role]}</Badge>
        )}
      </td>
      <td>
        {admin ? (
          <input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            onBlur={() => title !== (m.title ?? "") && onChange({ title: title || null })}
            placeholder="Add a title"
            aria-label={`Title for ${name}`}
            className="w-40 rounded-lg bg-transparent px-2 py-1.5 text-[12.5px] hover:bg-bg focus:bg-bg focus:ring-2 focus:ring-accent/30 focus:outline-none"
          />
        ) : (
          <span className="text-muted">{m.title ?? "—"}</span>
        )}
      </td>
      <td className="px-5">
        {admin ? (
          <select
            value={m.reports_to_id ?? ""}
            onChange={(e) => onChange({ reports_to_id: e.target.value || null })}
            className={select}
            aria-label={`${name} reports to`}
          >
            <option value="">Nobody</option>
            {all
              .filter((o) => o.id !== m.id)
              .map((o) => (
                <option key={o.id} value={o.id}>
                  {o.user.name || o.user.email}
                </option>
              ))}
          </select>
        ) : (
          <span className="text-muted">{m.reports_to_name ?? "—"}</span>
        )}
      </td>
    </tr>
  );
}

function InviteForm({ orgId, domains }: { orgId: string; domains: string[] }) {
  const client = useQueryClient();
  const [email, setEmail] = useState("");
  const [role, setRole] = useState<Role>("member");
  const [title, setTitle] = useState("");
  const [sent, setSent] = useState<{ email: string; url: string } | null>(null);
  const [copied, setCopied] = useState(false);

  const invite = useMutation({
    mutationFn: () => createInvite(orgId, { email, role, title: title || undefined }),
    onSuccess: (r) => {
      setSent({ email: r.invite.email, url: r.url });
      setEmail("");
      setTitle("");
      setCopied(false);
      client.invalidateQueries({ queryKey: ["invites", orgId] });
    },
  });

  const submit = (e: FormEvent) => {
    e.preventDefault();
    invite.mutate();
  };

  return (
    <Card>
      <p className="text-[14px] font-semibold">Invite someone</p>
      <p className="text-[12.5px] text-muted">
        Work emails only: {domains.map((d) => `@${d}`).join(", ")}. They get an email to set their password.
      </p>
      <form onSubmit={submit} className="mt-4 flex flex-wrap items-end gap-2">
        <label className="min-w-[220px] flex-[2]">
          <span className="text-[11.5px] text-muted">Work email</span>
          <input
            type="email"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder={`name@${domains[0] ?? "company.com"}`}
            className="mt-1 w-full rounded-xl bg-bg px-3 py-2 text-[13.5px] focus:ring-2 focus:ring-accent/30 focus:outline-none"
          />
        </label>
        <label className="min-w-[140px] flex-1">
          <span className="text-[11.5px] text-muted">Title</span>
          <input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="SWE"
            className="mt-1 w-full rounded-xl bg-bg px-3 py-2 text-[13.5px] focus:ring-2 focus:ring-accent/30 focus:outline-none"
          />
        </label>
        <label>
          <span className="block text-[11.5px] text-muted">Role</span>
          <select value={role} onChange={(e) => setRole(e.target.value as Role)} className={`${select} mt-1 py-2`}>
            {roles.map((r) => (
              <option key={r} value={r}>
                {roleLabel[r]}
              </option>
            ))}
          </select>
        </label>
        <Button type="submit" disabled={invite.isPending}>
          <PaperPlaneTiltIcon size={14} /> {invite.isPending ? "Sending…" : "Send invite"}
        </Button>
      </form>
      <div className="mt-3">
        <FormError>{invite.error ? (invite.error as ApiError).message : null}</FormError>
      </div>
      {sent && (
        <div className="mt-1 rounded-2xl bg-mist/60 p-3 text-[12.5px]">
          <p className="flex items-center gap-1.5 font-medium">
            <CheckIcon size={13} weight="bold" className="text-good" /> Invite sent to {sent.email}
          </p>
          <button
            onClick={() => {
              navigator.clipboard.writeText(sent.url);
              setCopied(true);
            }}
            className="mt-2 flex w-full items-center gap-2 rounded-xl bg-surface px-3 py-2 text-left font-mono text-[11.5px] ring-1 ring-line hover:bg-bg"
          >
            <span className="min-w-0 flex-1 truncate">{sent.url}</span>
            {copied ? <CheckIcon size={13} className="text-good" /> : <CopyIcon size={13} />}
          </button>
        </div>
      )}
    </Card>
  );
}
