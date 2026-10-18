"use client";

import {
  CheckCircleIcon,
  DiscordLogoIcon,
  EnvelopeSimpleIcon,
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
import { Badge, Card, PageHeader } from "@/components/ui";
import { PeopleSettings } from "@/components/PeopleSettings";
import {
  ApiError,
  backfillGithub,
  connectDiscord,
  disconnectConnector,
  getGithubRepos,
  rotateGithubSecret,
  setGithubToken,
  type Channel,
  type Connectors as ConnectorStatus,
  type NotificationPrefs,
  type NotifyVia,
  type WhatsAppMessage,
  getConnectors,
  getNotifications,
  getWhatsApp,
  roleLabel,
  updateChannel,
  updateNotifications,
} from "@/lib/api";
import { cn } from "@/lib/cn";
import { currentMembership, useMe } from "@/lib/session";
import { accessBundles } from "@/lib/mock";
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
  email: EnvelopeSimpleIcon,
};

export default function Settings() {
  // Coming back from installing the GitHub App lands on Connectors.
  const [section, setSection] = useState<Section>(() =>
    typeof window !== "undefined" && new URLSearchParams(window.location.search).has("github") ? "Connectors" : "People and roles",
  );
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
  const c = useQuery({ queryKey: ["connectors", dir.orgId], queryFn: () => getConnectors(dir.orgId!), enabled: !!dir.orgId }).data;
  const { user } = useMe();
  const admin = currentMembership(user)?.role === "org_admin" || !!user?.is_superadmin;
  const [returned] = useState(() => (typeof window === "undefined" ? null : new URLSearchParams(window.location.search).get("github")));
  const cards: { id: string; name: string; on: boolean; detail: string; off: string }[] = c
    ? [
        {
          id: "discord",
          name: "Discord",
          on: c.discord.connected,
          detail: `Reading ${c.discord.channels} mapped ${c.discord.channels === 1 ? "channel" : "channels"}`,
          off: c.discord.guild_id ? "Server connected; waiting for Noa's bot to run" : "Not connected: an org admin connects your server below",
        },
        { id: "whatsapp", name: "WhatsApp (Kapso)", on: c.whatsapp.connected, detail: "Sending and receiving through Kapso", off: "Not connected: messages stay in the outbox below" },
        {
          id: "github",
          name: "GitHub",
          on: c.github.connected,
          detail: c.github.repos.length ? `Commits, PRs and CI from ${c.github.repos.map((r) => r.repo).join(", ")}` : "No project has a repo yet",
          off: "Not connected: an org admin sets it up below",
        },
        { id: "email", name: "Email (Resend)", on: c.email.connected, detail: "Invites, sign-in links and notifications", off: "No RESEND_API_KEY: emails go to the API log" },
        { id: "slack", name: "Slack", on: false, detail: "", off: "Not built yet" },
        { id: "google", name: "Google Meet", on: false, detail: "", off: "Not built yet" },
      ]
    : [];

  return (
    <div className="space-y-4">
      <div className="grid gap-3 sm:grid-cols-2">
        {cards.map((card) => {
          const I = connectorIcon[card.id];
          return (
            <Card key={card.id} className="flex items-center gap-4 p-4">
              <span className="grid size-11 place-items-center rounded-2xl bg-mist text-accent">
                <I size={22} />
              </span>
              <div className="min-w-0 flex-1">
                <p className="text-[14px] font-semibold">{card.name}</p>
                <p className="text-[12.5px] break-words text-muted">{card.on ? card.detail : card.off}</p>
              </div>
              {card.on ? (
                <Badge tone="good">
                  <CheckCircleIcon size={12} weight="fill" /> Connected
                </Badge>
              ) : (
                <Badge tone={card.id === "whatsapp" ? "warn" : "neutral"}>{card.id === "whatsapp" ? "Simulated" : "Off"}</Badge>
              )}
            </Card>
          );
        })}
      </div>
      {returned && (
        <p className={cn("rounded-2xl px-4 py-3 text-[13px] ring-1", returned === "installed" ? "bg-good/10 text-good ring-good/20" : "bg-bad/10 text-bad ring-bad/20")}>
          {returned === "installed"
            ? "GitHub is connected. Commits, pull requests and CI from the repos you picked now flow into Noa."
            : returned === "installation_taken"
              ? "That GitHub installation is already connected to another workspace."
              : "GitHub didn't finish connecting. Try Install again from here."}
        </p>
      )}
      {c && admin && <DiscordSetup c={c} />}
      {c && admin && <GitHubSetup c={c} />}
      <WhatsAppLog messages={wa.data?.messages ?? []} scope={wa.data?.scope} />
    </div>
  );
}

/* The company's own Discord server (1.18): add Noa's bot, then connect the server. Org admins. */
function DiscordSetup({ c }: { c: ConnectorStatus }) {
  const dir = useDirectory();
  const client = useQueryClient();
  const [guild, setGuild] = useState("");
  const refresh = () => client.invalidateQueries({ queryKey: ["connectors", dir.orgId] });
  const connect = useMutation({ mutationFn: () => connectDiscord(dir.orgId!, guild), onSuccess: refresh });
  const remove = useMutation({ mutationFn: () => disconnectConnector(dir.orgId!, "discord"), onSuccess: refresh });
  const error = (connect.error ?? remove.error) as ApiError | null;

  return (
    <Card>
      <p className="text-[14px] font-semibold">Connect your Discord server</p>
      {c.discord.guild_id ? (
        <div className="mt-2 flex flex-wrap items-center gap-3 text-[13px]">
          <span className="flex-1">
            Server <span className="font-mono">{c.discord.guild_id}</span> is connected. Map its channels under Channels.
            {!c.discord.bot && " Noa's bot is not running yet, so nothing is read until the Noa admin turns it on."}
          </span>
          <button onClick={() => remove.mutate()} disabled={remove.isPending} className="rounded-full px-3 py-1.5 text-[12.5px] font-medium ring-1 ring-line hover:bg-bg">
            Disconnect
          </button>
        </div>
      ) : (
        <ol className="mt-2 space-y-3 text-[13px]">
          <li>
            1. Add Noa&rsquo;s bot to your server.{" "}
            {c.discord.invite_url ? (
              <a href={c.discord.invite_url} target="_blank" rel="noreferrer" className="font-medium text-accent-fg underline">
                Add to Discord
              </a>
            ) : (
              <span className="text-muted">The Noa admin hasn&rsquo;t set up the bot yet.</span>
            )}
          </li>
          <li>
            2. Paste your server&rsquo;s id (Discord → Settings → Advanced → Developer Mode on, then right-click the server → Copy Server ID).
            <form
              className="mt-2 flex gap-2"
              onSubmit={(e) => {
                e.preventDefault();
                if (guild.trim()) connect.mutate();
              }}
            >
              <input
                value={guild}
                onChange={(e) => setGuild(e.target.value)}
                placeholder="123456789012345678"
                aria-label="Discord server id"
                className="min-w-0 flex-1 rounded-xl bg-bg px-3 py-2 font-mono text-[13px] ring-1 ring-line focus:outline-none"
              />
              <button disabled={connect.isPending || !guild.trim()} className="rounded-full bg-accent px-4 py-2 text-[13px] font-medium text-white disabled:opacity-60">
                Connect
              </button>
            </form>
          </li>
        </ol>
      )}
      {error && <FormError>{error.message}</FormError>}
    </Card>
  );
}

/* The company's own GitHub (3.7): a webhook secret (shown once), an optional token, and past history. Org admins. */
function GitHubSetup({ c }: { c: ConnectorStatus }) {
  const dir = useDirectory();
  const client = useQueryClient();
  const [fresh, setFresh] = useState<string | null>(null);
  const [token, setToken] = useState("");
  const refresh = () => client.invalidateQueries({ queryKey: ["connectors", dir.orgId] });
  const rotate = useMutation({ mutationFn: () => rotateGithubSecret(dir.orgId!), onSuccess: (r) => (setFresh(r.secret), refresh()) });
  const saveToken = useMutation({ mutationFn: () => setGithubToken(dir.orgId!, token), onSuccess: () => (setToken(""), refresh()) });
  const backfill = useMutation({ mutationFn: () => backfillGithub(dir.orgId!) });
  const repos = useQuery({ queryKey: ["github-repos", dir.orgId], queryFn: () => getGithubRepos(dir.orgId!), enabled: !!dir.orgId && c.github.installed });
  const uninstall = useMutation({ mutationFn: () => disconnectConnector(dir.orgId!, "github_app"), onSuccess: refresh });
  const error = (rotate.error ?? saveToken.error ?? backfill.error ?? uninstall.error) as ApiError | null;

  const history = (
    <>
      <button onClick={() => backfill.mutate()} disabled={backfill.isPending || !c.github.repos.length} className="font-medium text-accent-fg underline disabled:opacity-60">
        {backfill.isPending ? "Loading history…" : "Load recent history"}
      </button>
      {backfill.data && (
        <ul className="mt-1 text-[12.5px] text-muted">
          {backfill.data.results.map((r) => (
            <li key={r.project}>
              {r.project}: {r.error ?? `${r.recorded} new`}
            </li>
          ))}
        </ul>
      )}
    </>
  );

  if (c.github.app)
    return (
      <Card>
        <p className="text-[14px] font-semibold">Connect GitHub</p>
        <p className="mt-0.5 text-[12.5px] text-muted">
          Commits, pull requests and CI from your projects&rsquo; repos go into the graph and every agent pack.{" "}
          <a href="/onboarding" className="font-medium text-accent-fg underline">
            {c.github.repos.length ? "Change each project's repo" : "Set each project's repo"}
          </a>
        </p>
        {c.github.installed ? (
          <div className="mt-3 space-y-2 text-[13px]">
            <p className="flex items-center gap-2">
              <CheckCircleIcon size={14} weight="fill" className="text-good" /> Noa&rsquo;s GitHub App is installed.
              {c.github.install_url && (
                <a href={c.github.install_url} className="font-medium text-accent-fg underline">
                  Change repos
                </a>
              )}
            </p>
            <p className="text-[12.5px] text-muted">
              It can see: {repos.isLoading ? "…" : repos.data?.repos.length ? repos.data.repos.join(", ") : repos.data?.error ?? "no repos yet"}
            </p>
            <div className="flex flex-wrap items-center gap-4">
              {history}
              <button onClick={() => uninstall.mutate()} disabled={uninstall.isPending} className="text-[12.5px] text-muted underline">
                Disconnect
              </button>
            </div>
          </div>
        ) : (
          <div className="mt-3">
            {c.github.install_url ? (
              <a href={c.github.install_url} className="inline-flex items-center gap-2 rounded-full bg-ink px-4 py-2 text-[13px] font-medium text-white">
                <GithubLogoIcon size={15} /> Install Noa on GitHub
              </a>
            ) : (
              <p className="text-[12.5px] text-muted">Only org admins can install it.</p>
            )}
            <p className="mt-2 text-[12px] text-muted">Pick your organization and the repos to share. GitHub brings you back here.</p>
          </div>
        )}
        <details className="mt-4 text-[12.5px] text-muted">
          <summary className="cursor-pointer">Set it up by hand instead</summary>
          <p className="mt-2">
            Generate a webhook secret, add a webhook to <span className="font-mono break-all">{c.github.webhook}</span> (JSON; Pushes, Pull requests, Workflow runs).{" "}
            <button onClick={() => rotate.mutate()} disabled={rotate.isPending} className="font-medium text-accent-fg underline">
              {c.github.secret_set ? "Make a new secret" : "Generate a secret"}
            </button>
          </p>
          {fresh && <p className="mt-1 font-mono break-all text-ink">{fresh}</p>}
        </details>
        {error && <FormError>{error.message}</FormError>}
      </Card>
    );

  return (
    <Card>
      <p className="text-[14px] font-semibold">Connect GitHub</p>
      <p className="mt-0.5 text-[12.5px] text-muted">
        Commits, pull requests and CI from {c.github.repos.length ? c.github.repos.map((r) => r.repo).join(", ") : "your projects' repos"} go into the graph and every agent pack.{" "}
        <a href="/onboarding" className="font-medium text-accent-fg underline">
          {c.github.repos.length ? "Change repos" : "Set each project's repo"}
        </a>
      </p>
      <ol className="mt-3 space-y-3 text-[13px]">
        <li>
          1. {c.github.secret_set ? "A webhook secret is set." : "Generate a webhook secret."}{" "}
          <button onClick={() => rotate.mutate()} disabled={rotate.isPending} className="font-medium text-accent-fg underline">
            {c.github.secret_set ? "Make a new one" : "Generate"}
          </button>
          {fresh && (
            <div className="mt-2 rounded-xl bg-mist/60 p-3 text-[12.5px]">
              <p>Copy it now; it won&rsquo;t be shown again.</p>
              <p className="mt-1 font-mono break-all">{fresh}</p>
            </div>
          )}
        </li>
        <li>
          2. In each repo (or your GitHub organization): Settings → Webhooks → Add webhook. Payload URL <span className="font-mono break-all">{c.github.webhook}</span>, content type{" "}
          <span className="font-mono">application/json</span>, the secret above, and the events Pushes, Pull requests and Workflow runs.
        </li>
        <li>
          3. Optional, to load history from before the webhook (needed for private repos): a fine-grained token with read access to contents and pull requests.{" "}
          {c.github.token_set && <span className="text-good">A token is set.</span>}
          <form
            className="mt-2 flex gap-2"
            onSubmit={(e) => {
              e.preventDefault();
              if (token.trim()) saveToken.mutate();
            }}
          >
            <input
              type="password"
              value={token}
              onChange={(e) => setToken(e.target.value)}
              placeholder="github_pat_…"
              aria-label="GitHub token"
              className="min-w-0 flex-1 rounded-xl bg-bg px-3 py-2 font-mono text-[13px] ring-1 ring-line focus:outline-none"
            />
            <button disabled={saveToken.isPending || !token.trim()} className="rounded-full px-4 py-2 text-[13px] font-medium ring-1 ring-line disabled:opacity-60">
              Save token
            </button>
          </form>
          <div className="mt-2">{history}</div>
        </li>
      </ol>
      {error && <FormError>{error.message}</FormError>}
    </Card>
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
  email: "Email",
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
        {p.notify_via === "discord" && (
          <p className="text-[12px] text-muted">
            Noa&rsquo;s bot DMs the Discord account you post from in a channel
            it reads. Discord has no buttons, so messages link to the app.
          </p>
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
