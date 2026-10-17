"use client";

import {
  CheckCircleIcon,
  DiscordLogoIcon,
  GithubLogoIcon,
  GoogleLogoIcon,
  KeyIcon,
  SlackLogoIcon,
  WhatsappLogoIcon,
  type Icon,
} from "@phosphor-icons/react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { FormError } from "@/components/AuthCard";
import { Badge, Button, Card, PageHeader } from "@/components/ui";
import { PeopleSettings } from "@/components/PeopleSettings";
import { ApiError, type Channel, type NotificationPrefs, type NotifyVia, type WhatsAppMessage, getNotifications, getWhatsApp, roleLabel, updateChannel, updateNotifications } from "@/lib/api";
import { cn } from "@/lib/cn";
import { currentMembership, useMe } from "@/lib/session";
import { accessBundles, connectors } from "@/lib/mock";
import { ago, useDirectory } from "@/lib/work";

/* Settings: org admin surfaces (1.5, 1.6, 1.18, 1.22, 2.15, 3.20). */

const sections = [
  "Connectors",
  "Channels",
  "People and roles",
  "Access bundles",
  "Notifications",
] as const;
type Section = (typeof sections)[number];

const connectorIcon: Record<string, Icon> = {
  discord: DiscordLogoIcon,
  slack: SlackLogoIcon,
  google: GoogleLogoIcon,
  whatsapp: WhatsappLogoIcon,
  github: GithubLogoIcon,
};

export default function Settings() {
  const [section, setSection] = useState<Section>("People and roles");
  const membership = currentMembership(useMe().user);
  return (
    <div className="mx-auto max-w-6xl">
      <PageHeader
        title="Settings"
        sub={
          membership
            ? `${membership.org.name} · you're ${roleLabel[membership.role].toLowerCase()}`
            : undefined
        }
      />
      <div className="grid gap-6 lg:grid-cols-[220px_1fr]">
        <nav
          aria-label="Settings"
          className="flex gap-1 overflow-x-auto lg:flex-col"
        >
          {sections.map((s) => (
            <button
              key={s}
              onClick={() => setSection(s)}
              className={cn(
                "shrink-0 rounded-xl px-3 py-2 text-left text-[13.5px] transition-colors",
                section === s
                  ? "bg-surface font-medium card-shadow"
                  : "text-ink/70 hover:bg-surface/70 hover:text-ink",
              )}
            >
              {s}
            </button>
          ))}
        </nav>
        <div>
          {section === "Connectors" && <Connectors />}
          {section === "Channels" && <Channels />}
          {section === "People and roles" && <PeopleRoles />}
          {section === "Access bundles" && <Bundles />}
          {section === "Notifications" && <NotificationPrefs />}
        </div>
      </div>
    </div>
  );
}

function Connectors() {
  const dir = useDirectory();
  const wa = useQuery({ queryKey: ["whatsapp", dir.orgId], queryFn: () => getWhatsApp(dir.orgId!), enabled: !!dir.orgId, refetchInterval: 15_000 });
  return (
    <div className="space-y-4">
      <div className="grid gap-3 sm:grid-cols-2">
        {connectors.map((c) => {
          const I = connectorIcon[c.id];
          const whatsapp = c.id === "whatsapp";
          const connected = whatsapp ? wa.data?.configured : c.status === "connected";
          return (
            <Card key={c.id} className="flex items-center gap-4 p-4">
              <span className="grid size-11 place-items-center rounded-2xl bg-mist text-accent">
                <I size={22} />
              </span>
              <div className="min-w-0 flex-1">
                <p className="text-[14px] font-semibold">{whatsapp ? "WhatsApp (Kapso)" : c.name}</p>
                <p className="truncate text-[12.5px] text-muted">
                  {whatsapp ? (connected ? "Sending and receiving through Kapso" : "Not connected: messages stay in the outbox below") : c.detail}
                </p>
              </div>
              {connected ? (
                <Badge tone="good">
                  <CheckCircleIcon size={12} weight="fill" /> Connected
                </Badge>
              ) : whatsapp ? (
                <Badge tone="warn">Simulated</Badge>
              ) : (
                <Button size="sm" variant="ghost">
                  Connect
                </Button>
              )}
            </Card>
          );
        })}
      </div>
      <WhatsAppLog messages={wa.data?.messages ?? []} scope={wa.data?.scope} />
    </div>
  );
}

/* What Noa sent and received on WhatsApp (1.15): admins see the workspace's, others their own. */
function WhatsAppLog({ messages, scope }: { messages: WhatsAppMessage[]; scope?: "workspace" | "you" }) {
  const dir = useDirectory();
  return (
    <Card className="p-0">
      <div className="border-b border-line px-5 py-3">
        <p className="text-[14px] font-semibold">WhatsApp messages</p>
        <p className="text-[12.5px] text-muted">
          {scope === "workspace" ? "Everything Noa sent and received in this workspace." : "Messages between Noa and you."} People choose WhatsApp and add their
          number under Notifications.
        </p>
      </div>
      <ul className="max-h-[420px] divide-y divide-line overflow-y-auto">
        {messages.length === 0 && <li className="px-5 py-5 text-[13px] text-muted">No WhatsApp messages yet.</li>}
        {messages.map((m) => (
          <li key={m.id} className="flex gap-3 px-5 py-3 text-[13px]">
            <span
              className={cn(
                "mt-0.5 shrink-0 rounded-full px-2 py-0.5 text-[10.5px] font-medium",
                m.direction === "out" ? "bg-mist text-accent-fg" : "bg-bg text-ink/70",
              )}
            >
              {m.direction === "out" ? "Noa →" : "→ Noa"}
            </span>
            <div className="min-w-0 flex-1">
              <p className="whitespace-pre-wrap">{m.body}</p>
              {m.buttons && Object.keys(m.buttons).length > 0 && (
                <p className="mt-1 flex flex-wrap gap-1.5">
                  {Object.values(m.buttons).map((b) => (
                    <span key={b} className="rounded-full bg-bg px-2 py-0.5 text-[11px] ring-1 ring-line">
                      {b}
                    </span>
                  ))}
                </p>
              )}
              <p className="mt-1 text-[11.5px] text-muted">{[dir.person(m.person_id)?.name, ago(m.inserted_at), m.status].filter(Boolean).join(" · ")}</p>
            </div>
          </li>
        ))}
      </ul>
    </Card>
  );
}

const platformName = {
  discord: "Discord",
  slack: "Slack",
  whatsapp: "WhatsApp",
} as const;

/* Channel to project map (1.18), saved to the API. Only org admins can change it. */
function Channels() {
  const dir = useDirectory();
  const client = useQueryClient();
  const admin = currentMembership(useMe().user)?.role === "org_admin";
  const save = useMutation({
    mutationFn: ({
      id,
      data,
    }: {
      id: string;
      data: Partial<Pick<Channel, "project_id" | "split" | "read">>;
    }) => updateChannel(dir.orgId!, id, data),
    onSuccess: () =>
      client.invalidateQueries({ queryKey: ["directory", dir.orgId] }),
  });

  const route = (c: Channel) =>
    !c.read ? "off" : c.split ? "split" : (c.project_id ?? "off");
  const setRoute = (c: Channel, value: string) =>
    save.mutate({
      id: c.id,
      data:
        value === "off"
          ? { read: false }
          : value === "split"
            ? { read: true, split: true }
            : { read: true, split: false, project_id: value },
    });

  return (
    <Card className="p-0">
      <div className="border-b border-line px-5 py-4">
        <p className="text-[14px] font-semibold">Channel to project</p>
        <p className="text-[12.5px] text-muted">
          Noa only reads mapped channels. Direct messages are never read.
          &ldquo;Split by message&rdquo; routes each message on its own.
          {!admin && " Only workspace admins can change this."}
        </p>
      </div>
      {save.error && (
        <div className="px-5 pt-3">
          <FormError>{(save.error as ApiError).message}</FormError>
        </div>
      )}
      <table className="w-full text-[13px]">
        <thead>
          <tr className="border-b border-line text-left text-[11.5px] text-muted">
            <th className="px-5 py-2.5 font-medium">Channel</th>
            <th className="py-2.5 font-medium">Source</th>
            <th className="py-2.5 font-medium">Project</th>
            <th className="px-5 py-2.5 text-right font-medium">Read</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-line">
          {dir.channels.length === 0 && (
            <tr>
              <td colSpan={4} className="px-5 py-4 text-muted">
                No channels yet. They appear here once a connector is set up.
              </td>
            </tr>
          )}
          {dir.channels.map((c) => (
            <tr key={c.id}>
              <td className="px-5 py-3 font-medium">{c.name}</td>
              <td className="text-muted">{platformName[c.platform]}</td>
              <td>
                <select
                  value={route(c)}
                  disabled={!admin || save.isPending}
                  onChange={(e) => setRoute(c, e.target.value)}
                  aria-label={`Project for ${c.name}`}
                  className="rounded-lg bg-bg px-2 py-1.5 text-[12.5px] focus:outline-none disabled:opacity-70"
                >
                  {dir.projects.map((p) => (
                    <option key={p.id} value={p.id}>
                      {p.name}
                    </option>
                  ))}
                  <option value="split">Split by message</option>
                  <option value="off">Not read</option>
                </select>
              </td>
              <td className="px-5 text-right">
                <button
                  role="switch"
                  aria-checked={c.read}
                  aria-label={`Read ${c.name}`}
                  disabled={!admin || save.isPending}
                  onClick={() =>
                    save.mutate({ id: c.id, data: { read: !c.read } })
                  }
                  className={cn(
                    "relative inline-block h-5 w-9 rounded-full transition-colors disabled:opacity-70",
                    c.read ? "bg-accent" : "bg-line",
                  )}
                >
                  <span
                    className={cn(
                      "absolute top-0.5 size-4 rounded-full bg-white shadow transition-all",
                      c.read ? "left-[18px]" : "left-0.5",
                    )}
                  />
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </Card>
  );
}

function PeopleRoles() {
  return <PeopleSettings />;
}

function Bundles() {
  const bundle = accessBundles.b;
  return (
    <Card>
      <p className="text-[14px] font-semibold">Emmarie · access bundle</p>
      <p className="text-[12.5px] text-muted">
        Granted when someone joins the project, revoked when they leave. Noa
        grants what the apps allow and lists the rest.
      </p>
      <ul className="mt-4 space-y-2">
        {bundle.map((b) => (
          <li
            key={b.item}
            className="flex items-center gap-3 rounded-xl bg-bg px-3.5 py-2.5 text-[13px]"
          >
            {b.item.includes("keys") ? (
              <KeyIcon size={15} className="text-muted" />
            ) : (
              <CheckCircleIcon size={15} className="text-accent" />
            )}
            <span className="flex-1">{b.item}</span>
            <Badge tone={b.auto ? "good" : "neutral"}>
              {b.auto ? "Automatic" : "Checklist"}
            </Badge>
          </li>
        ))}
      </ul>
      <p className="mt-4 text-[12px] text-muted">
        Secrets are sent as one-time links that expire in 24 hours. Every fetch
        is logged.
      </p>
    </Card>
  );
}

const viaLabel: Record<NotifyVia, string> = {
  whatsapp: "WhatsApp",
  discord: "Discord DM",
  email: "Email",
  in_app: "In app only",
};
const hhmm = (t: string | null) => (t ? t.slice(0, 5) : "");

/* Notification preferences (2.15): where Noa reaches you, the digest time and quiet hours. */
function NotificationPrefs() {
  const dir = useDirectory();
  const client = useQueryClient();
  const prefs = useQuery({
    queryKey: ["notifications", dir.orgId],
    queryFn: () => getNotifications(dir.orgId!),
    enabled: !!dir.orgId,
  });
  const save = useMutation({
    mutationFn: (data: Partial<NotificationPrefs>) =>
      updateNotifications(dir.orgId!, data),
    onSuccess: (n) => client.setQueryData(["notifications", dir.orgId], n),
  });
  const p = prefs.data;
  const [phone, setPhone] = useState<string | null>(null);

  if (prefs.error)
    return <FormError>{(prefs.error as ApiError).message}</FormError>;
  if (!p) return <Card>Loading…</Card>;

  return (
    <Card>
      <p className="text-[14px] font-semibold">Your notifications</p>
      <p className="mt-0.5 text-[12.5px] text-muted">
        Approvals, changes to your work and the daily digest go here.
      </p>
      <div className="mt-4 grid gap-4 sm:grid-cols-2">
        <label className="block text-[12px] text-muted">
          Send to
          <select
            value={p.notify_via}
            onChange={(e) =>
              save.mutate({ notify_via: e.target.value as NotifyVia })
            }
            className="mt-1 w-full rounded-xl bg-bg px-3 py-2 text-[13px] text-ink focus:outline-none"
          >
            {(Object.keys(viaLabel) as NotifyVia[]).map((v) => (
              <option key={v} value={v}>
                {viaLabel[v]}
              </option>
            ))}
          </select>
        </label>
        {p.notify_via === "whatsapp" && (
          <label className="block text-[12px] text-muted">
            WhatsApp number
            <input
              value={phone ?? p.phone ?? ""}
              onChange={(e) => setPhone(e.target.value)}
              onBlur={() =>
                phone !== null &&
                phone !== p.phone &&
                save.mutate({ phone: phone || null })
              }
              placeholder="+91 98000 00000"
              className="mt-1 w-full rounded-xl bg-bg px-3 py-2 text-[13px] text-ink focus:outline-none"
            />
          </label>
        )}
        <label className="block text-[12px] text-muted">
          Daily digest
          <input
            type="time"
            value={hhmm(p.digest_at)}
            onChange={(e) => save.mutate({ digest_at: e.target.value || null })}
            className="mt-1 w-full rounded-xl bg-bg px-3 py-2 text-[13px] text-ink focus:outline-none"
          />
        </label>
        <div className="block text-[12px] text-muted">
          Quiet hours
          <div className="mt-1 flex items-center gap-2">
            <input
              type="time"
              aria-label="Quiet from"
              value={hhmm(p.quiet_from)}
              onChange={(e) =>
                save.mutate({ quiet_from: e.target.value || null })
              }
              className="w-full rounded-xl bg-bg px-3 py-2 text-[13px] text-ink focus:outline-none"
            />
            <span>to</span>
            <input
              type="time"
              aria-label="Quiet to"
              value={hhmm(p.quiet_to)}
              onChange={(e) =>
                save.mutate({ quiet_to: e.target.value || null })
              }
              className="w-full rounded-xl bg-bg px-3 py-2 text-[13px] text-ink focus:outline-none"
            />
          </div>
        </div>
      </div>
      {save.error && (
        <div className="mt-3">
          <FormError>{(save.error as ApiError).message}</FormError>
        </div>
      )}
      <p className="mt-4 text-[12px] text-muted">
        {save.isPending ? "Saving…" : "Saved as you change it."} Approvals that
        need you still arrive during quiet hours only if they block someone.
        Times are in India time.
      </p>
    </Card>
  );
}
