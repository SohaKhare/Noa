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
import { useState } from "react";
import { Avatar, Badge, Button, Card, PageHeader } from "@/components/ui";
import { cn } from "@/lib/cn";
import { accessBundles, channelMap, connectors, people, person, projects, roleLabel, type Role } from "@/lib/mock";

/* Settings: org admin surfaces (1.5, 1.6, 1.18, 1.22, 2.15, 3.20). */

const sections = ["Connectors", "Channels", "People and roles", "Access bundles", "Notifications"] as const;
type Section = (typeof sections)[number];

const connectorIcon: Record<string, Icon> = {
  discord: DiscordLogoIcon,
  slack: SlackLogoIcon,
  google: GoogleLogoIcon,
  whatsapp: WhatsappLogoIcon,
  github: GithubLogoIcon,
};

export default function Settings() {
  const [section, setSection] = useState<Section>("Connectors");
  return (
    <div className="mx-auto max-w-6xl">
      <PageHeader title="Settings" sub="NotYourIdea · you're a PM / lead" />
      <div className="grid gap-6 lg:grid-cols-[220px_1fr]">
        <nav aria-label="Settings" className="flex gap-1 overflow-x-auto lg:flex-col">
          {sections.map((s) => (
            <button
              key={s}
              onClick={() => setSection(s)}
              className={cn(
                "shrink-0 rounded-xl px-3 py-2 text-left text-[13.5px] transition-colors",
                section === s ? "bg-surface font-medium card-shadow" : "text-ink/70 hover:bg-surface/70 hover:text-ink",
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
  return (
    <div className="grid gap-3 sm:grid-cols-2">
      {connectors.map((c) => {
        const I = connectorIcon[c.id];
        return (
          <Card key={c.id} className="flex items-center gap-4 p-4">
            <span className="grid size-11 place-items-center rounded-2xl bg-mist text-accent">
              <I size={22} />
            </span>
            <div className="min-w-0 flex-1">
              <p className="text-[14px] font-semibold">{c.name}</p>
              <p className="truncate text-[12.5px] text-muted">{c.detail}</p>
            </div>
            {c.status === "connected" ? (
              <Badge tone="good">
                <CheckCircleIcon size={12} weight="fill" /> Connected
              </Badge>
            ) : (
              <Button size="sm" variant="ghost">
                Connect
              </Button>
            )}
          </Card>
        );
      })}
    </div>
  );
}

function Channels() {
  const [rows, setRows] = useState(channelMap);
  return (
    <Card className="p-0">
      <div className="border-b border-line px-5 py-4">
        <p className="text-[14px] font-semibold">Channel to project</p>
        <p className="text-[12.5px] text-muted">Noa only reads mapped channels. Direct messages are never read. &ldquo;Split by message&rdquo; routes each message on its own.</p>
      </div>
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
          {rows.map((r, i) => (
            <tr key={r.channel}>
              <td className="px-5 py-3 font-medium">{r.channel}</td>
              <td className="text-muted">{r.source}</td>
              <td>
                <select
                  value={r.project}
                  onChange={(e) => setRows((xs) => xs.map((x, j) => (j === i ? { ...x, project: e.target.value, ingest: e.target.value !== "off" } : x)))}
                  className="rounded-lg bg-bg px-2 py-1.5 text-[12.5px] focus:outline-none"
                >
                  {projects.map((p) => (
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
                  aria-checked={r.ingest}
                  aria-label={`Read ${r.channel}`}
                  onClick={() => setRows((xs) => xs.map((x, j) => (j === i ? { ...x, ingest: !x.ingest } : x)))}
                  className={cn("relative inline-block h-5 w-9 rounded-full transition-colors", r.ingest ? "bg-accent" : "bg-line")}
                >
                  <span className={cn("absolute top-0.5 size-4 rounded-full bg-white shadow transition-all", r.ingest ? "left-[18px]" : "left-0.5")} />
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
  return (
    <Card className="p-0">
      <div className="flex items-center justify-between border-b border-line px-5 py-4">
        <div>
          <p className="text-[14px] font-semibold">People and roles</p>
          <p className="text-[12.5px] text-muted">Reporting lines decide who approves deadline and scope changes.</p>
        </div>
        <Button size="sm">Invite</Button>
      </div>
      <table className="w-full text-[13px]">
        <thead>
          <tr className="border-b border-line text-left text-[11.5px] text-muted">
            <th className="px-5 py-2.5 font-medium">Person</th>
            <th className="py-2.5 font-medium">Role</th>
            <th className="py-2.5 font-medium">Reports to</th>
            <th className="px-5 py-2.5 text-right font-medium">Identities</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-line">
          {people.map((p) => (
            <tr key={p.id}>
              <td className="px-5 py-3">
                <span className="flex items-center gap-2.5">
                  <Avatar initials={p.initials} size={28} />
                  <span>
                    <span className="block font-medium">{p.name}</span>
                    <span className="block text-[11.5px] text-muted">{p.title}</span>
                  </span>
                </span>
              </td>
              <td>
                <select defaultValue={p.role} className="rounded-lg bg-bg px-2 py-1.5 text-[12.5px] focus:outline-none">
                  {(Object.keys(roleLabel) as Role[]).map((r) => (
                    <option key={r} value={r}>
                      {roleLabel[r]}
                    </option>
                  ))}
                </select>
              </td>
              <td className="text-muted">{person(p.reportsTo)?.name ?? "—"}</td>
              <td className="px-5 text-right">
                <span className="inline-flex gap-1.5 text-ink/45">
                  <DiscordLogoIcon size={15} />
                  <WhatsappLogoIcon size={15} />
                  <GoogleLogoIcon size={15} />
                </span>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </Card>
  );
}

function Bundles() {
  const bundle = accessBundles.b;
  return (
    <Card>
      <p className="text-[14px] font-semibold">Emmarie · access bundle</p>
      <p className="text-[12.5px] text-muted">Granted when someone joins the project, revoked when they leave. Noa grants what the apps allow and lists the rest.</p>
      <ul className="mt-4 space-y-2">
        {bundle.map((b) => (
          <li key={b.item} className="flex items-center gap-3 rounded-xl bg-bg px-3.5 py-2.5 text-[13px]">
            {b.item.includes("keys") ? <KeyIcon size={15} className="text-muted" /> : <CheckCircleIcon size={15} className="text-accent" />}
            <span className="flex-1">{b.item}</span>
            <Badge tone={b.auto ? "good" : "neutral"}>{b.auto ? "Automatic" : "Checklist"}</Badge>
          </li>
        ))}
      </ul>
      <p className="mt-4 text-[12px] text-muted">Secrets are sent as one-time links that expire in 24 hours. Every fetch is logged.</p>
    </Card>
  );
}

function NotificationPrefs() {
  const [channel, setChannel] = useState("WhatsApp");
  return (
    <Card>
      <p className="text-[14px] font-semibold">Your notifications</p>
      <div className="mt-4 grid gap-4 sm:grid-cols-3">
        <label className="block text-[12px] text-muted">
          Send to
          <select value={channel} onChange={(e) => setChannel(e.target.value)} className="mt-1 w-full rounded-xl bg-bg px-3 py-2 text-[13px] text-ink focus:outline-none">
            {["WhatsApp", "Discord DM", "Slack DM", "Email", "In app only"].map((c) => (
              <option key={c}>{c}</option>
            ))}
          </select>
        </label>
        <label className="block text-[12px] text-muted">
          Daily digest
          <input type="time" defaultValue="09:30" className="mt-1 w-full rounded-xl bg-bg px-3 py-2 text-[13px] text-ink focus:outline-none" />
        </label>
        <label className="block text-[12px] text-muted">
          Quiet hours
          <input defaultValue="21:00 to 08:00" className="mt-1 w-full rounded-xl bg-bg px-3 py-2 text-[13px] text-ink focus:outline-none" />
        </label>
      </div>
      <p className="mt-4 text-[12px] text-muted">Approvals that need you still arrive during quiet hours only if they block someone.</p>
    </Card>
  );
}
