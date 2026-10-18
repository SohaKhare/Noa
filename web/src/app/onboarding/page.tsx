"use client";

import { CheckIcon, DiscordLogoIcon, FileArrowUpIcon, PlusIcon, SlackLogoIcon, UsersIcon } from "@phosphor-icons/react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { FormError } from "@/components/AuthCard";
import { BrandMark } from "@/components/BrandMark";
import { Avatar, Badge, Button } from "@/components/ui";
import { addMembersAsPeople, ApiError, createChannel, createPerson, createProject, getDiscordChannels, getSlackChannels, importOrgMap, setAllocation, updateProject, type WorkProject } from "@/lib/api";
import { cn } from "@/lib/cn";
import { currentMembership, useMe } from "@/lib/session";
import { nameInitials, useDirectory } from "@/lib/work";

/* Workspace setup (1.18): projects, the org map and who works where, the channels Noa reads. Each step saves as you go. */

const STEPS = ["Projects", "People", "Channels", "Done"] as const;
const input = "w-full rounded-xl bg-bg px-3 py-2 text-[13px] ring-1 ring-line focus:ring-2 focus:ring-accent/30 focus:outline-none";

export default function Onboarding() {
  const router = useRouter();
  const { user, loading } = useMe();
  const membership = currentMembership(user);
  const dir = useDirectory();
  const [step, setStep] = useState(0);
  const lead = !!user?.is_superadmin || membership?.role === "org_admin" || membership?.role === "pm";

  useEffect(() => {
    if (!loading && !user) router.replace("/login?next=/onboarding");
  }, [loading, user, router]);

  if (loading || !user) return null;

  return (
    <div className="min-h-screen mist-wash px-4 py-10">
      <div className="mx-auto max-w-4xl">
        <div className="flex items-center gap-2">
          <BrandMark />
          <span className="font-wordmark text-[24px] leading-none">NOA</span>
        </div>
        <h1 className="mt-8 text-[28px] font-semibold tracking-[-0.03em]">Set up {membership?.org.name ?? "your workspace"}</h1>
        <p className="mt-1 text-[14px] text-muted">Everything saves as you go. You can change any of it later in Settings and on the People board.</p>

        {!lead ? (
          <div className="mt-6 rounded-[28px] bg-surface p-6 card-shadow">
            <p className="text-[14px]">Only workspace admins and PMs can set up the workspace. Ask yours to finish setup, then open My day.</p>
            <Link href="/" className="mt-4 inline-block rounded-full bg-accent px-4 py-2 text-[13.5px] font-medium text-white">
              Open My day
            </Link>
          </div>
        ) : (
          <>
            <ol className="mt-5 flex flex-wrap gap-2">
              {STEPS.map((s, i) => (
                <li key={s}>
                  <button
                    onClick={() => setStep(i)}
                    className={cn(
                      "flex items-center gap-2 rounded-full py-1 pr-3.5 pl-1 text-[12.5px]",
                      i === step ? "bg-accent text-white" : i < step ? "bg-surface text-ink" : "bg-surface/60 text-muted",
                    )}
                  >
                    <span className={cn("grid size-6 place-items-center rounded-full font-mono text-[11px]", i === step ? "bg-white/15" : "bg-bg")}>
                      {i < step ? <CheckIcon size={11} weight="bold" /> : i + 1}
                    </span>
                    {s}
                  </button>
                </li>
              ))}
            </ol>

            <div className="mt-6 rounded-[28px] bg-surface p-6 card-shadow">
              {step === 0 && <Projects />}
              {step === 1 && <People />}
              {step === 2 && <Channels admin={!!user.is_superadmin || membership?.role === "org_admin"} />}
              {step === 3 && <Done />}
            </div>

            {step === 0 && (user.is_superadmin || membership?.role === "org_admin") && <Import />}

            <div className="mt-5 flex justify-end gap-2">
              {step > 0 && (
                <Button variant="ghost" onClick={() => setStep((s) => s - 1)}>
                  Back
                </Button>
              )}
              {step < STEPS.length - 1 && (
                <Button disabled={step === 0 && dir.projects.length === 0} onClick={() => setStep((s) => s + 1)}>
                  Continue
                </Button>
              )}
            </div>
          </>
        )}
      </div>
    </div>
  );
}

function useRefresh() {
  const client = useQueryClient();
  const { orgId } = useDirectory();
  return () => client.invalidateQueries({ queryKey: ["directory", orgId] });
}

function Projects() {
  const dir = useDirectory();
  const refresh = useRefresh();
  const [name, setName] = useState("");
  const [about, setAbout] = useState("");
  const [leadId, setLeadId] = useState("");
  const [repo, setRepo] = useState("");
  const add = useMutation({
    mutationFn: () => createProject(dir.orgId!, { name: name.trim(), about: about.trim() || undefined, lead_id: leadId || undefined, repo: repo.trim() || undefined }),
    onSuccess: () => {
      setName("");
      setAbout("");
      setRepo("");
      refresh();
    },
  });

  return (
    <div className="grid gap-6 md:grid-cols-[1fr_1.1fr]">
      <div>
        <p className="text-[15px] font-semibold">Projects</p>
        <p className="mt-1 text-[12.5px] text-muted">What your team works on. Noa routes each message, task and decision to one of these.</p>
        <ul className="mt-4 space-y-2">
          {dir.projects.map((p) => (
            <li key={p.id} className="rounded-2xl bg-bg px-4 py-3">
              <p className="text-[13.5px] font-medium">{p.name}</p>
              <p className="text-[12px] text-muted">
                {p.about ?? "No description"}
                {p.lead_id && ` · lead ${dir.person(p.lead_id)?.name}`}
              </p>
              <RepoField project={p} />
            </li>
          ))}
          {dir.projects.length === 0 && <li className="text-[13px] text-muted">No projects yet. Add your first one.</li>}
        </ul>
      </div>
      <form
        className="space-y-3 rounded-2xl p-4 ring-1 ring-line"
        onSubmit={(e) => {
          e.preventDefault();
          if (name.trim()) add.mutate();
        }}
      >
        <p className="text-[13px] font-semibold">Add a project</p>
        <input className={input} placeholder="Name, e.g. Rocket Site" value={name} onChange={(e) => setName(e.target.value)} aria-label="Project name" />
        <input className={input} placeholder="What it is, in one line" value={about} onChange={(e) => setAbout(e.target.value)} aria-label="About" />
        <input className={input} placeholder="GitHub repo, e.g. acme/rocket-site (optional)" value={repo} onChange={(e) => setRepo(e.target.value)} aria-label="GitHub repo" />
        <select className={input} value={leadId} onChange={(e) => setLeadId(e.target.value)} aria-label="Lead">
          <option value="">No lead yet</option>
          {dir.people.map((p) => (
            <option key={p.id} value={p.id}>
              {p.name}
            </option>
          ))}
        </select>
        {add.error && <FormError>{(add.error as ApiError).message}</FormError>}
        <Button disabled={!name.trim() || add.isPending}>
          <PlusIcon size={13} weight="bold" /> Add project
        </Button>
      </form>
    </div>
  );
}

/* A project's GitHub repo (3.7): commits, PRs and CI from it go into the graph and the agent pack. */
function RepoField({ project }: { project: WorkProject }) {
  const dir = useDirectory();
  const refresh = useRefresh();
  const [value, setValue] = useState(project.repo ?? "");
  const save = useMutation({ mutationFn: () => updateProject(dir.orgId!, project.id, { repo: value.trim() || null }), onSuccess: refresh });
  const dirty = value.trim() !== (project.repo ?? "");
  return (
    <form
      className="mt-2 flex gap-2"
      onSubmit={(e) => {
        e.preventDefault();
        if (dirty) save.mutate();
      }}
    >
      <input
        value={value}
        onChange={(e) => setValue(e.target.value)}
        placeholder="GitHub repo (owner/name)"
        aria-label={`GitHub repo for ${project.name}`}
        className="min-w-0 flex-1 rounded-lg bg-surface px-2.5 py-1.5 font-mono text-[12px] ring-1 ring-line focus:outline-none"
      />
      {dirty && (
        <button disabled={save.isPending} className="rounded-full px-3 text-[12px] font-medium ring-1 ring-line hover:bg-surface">
          Save
        </button>
      )}
      {save.error && <FormError>{(save.error as ApiError).message}</FormError>}
    </form>
  );
}

function People() {
  const dir = useDirectory();
  const refresh = useRefresh();
  const [name, setName] = useState("");
  const [title, setTitle] = useState("");
  const [handles, setHandles] = useState("");
  const members = useMutation({ mutationFn: () => addMembersAsPeople(dir.orgId!), onSuccess: refresh });
  const add = useMutation({
    mutationFn: () =>
      createPerson(dir.orgId!, {
        name: name.trim(),
        title: title.trim() || undefined,
        handles: handles
          .split(",")
          .map((h) => h.trim())
          .filter(Boolean),
      }),
    onSuccess: () => {
      setName("");
      setTitle("");
      setHandles("");
      refresh();
    },
  });
  const allocate = useMutation({
    mutationFn: (a: { person_id: string; project_id: string; percent: number }) => setAllocation(dir.orgId!, a),
    onSuccess: refresh,
  });
  const percent = (personId: string, projectId: string) => dir.person(personId)?.allocations.find((a) => a.project_id === projectId)?.percent ?? 0;

  return (
    <div>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="text-[15px] font-semibold">People and who works where</p>
          <p className="mt-1 max-w-xl text-[12.5px] text-muted">
            Everyone Noa should know about, with or without an account. Their share of time on each project tells Noa who to route work and questions to.
          </p>
        </div>
        <Button variant="ghost" disabled={members.isPending} onClick={() => members.mutate()}>
          <UsersIcon size={14} /> {members.data != null ? `Added ${members.data}` : "Add everyone who has joined"}
        </Button>
      </div>
      {(members.error || allocate.error) && <FormError>{((members.error ?? allocate.error) as ApiError).message}</FormError>}

      <div className="mt-4 overflow-x-auto rounded-2xl ring-1 ring-line">
        <table className="w-full text-[13px]">
          <thead>
            <tr className="border-b border-line text-left text-[11.5px] text-muted">
              <th className="px-4 py-2.5 font-medium">Person</th>
              {dir.projects.map((p) => (
                <th key={p.id} className="px-2 py-2.5 font-medium">
                  {p.name} %
                </th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-line">
            {dir.people.map((p) => (
              <tr key={p.id}>
                <td className="px-4 py-2.5">
                  <span className="flex items-center gap-2">
                    <Avatar initials={nameInitials(p.name)} size={22} />
                    <span className="font-medium">{p.name}</span>
                    {!p.joined && <Badge>No account</Badge>}
                  </span>
                </td>
                {dir.projects.map((proj) => (
                  <td key={proj.id} className="px-2 py-2">
                    <input
                      type="number"
                      min={0}
                      max={100}
                      step={10}
                      key={`${p.id}-${proj.id}-${percent(p.id, proj.id)}`}
                      defaultValue={percent(p.id, proj.id) || ""}
                      placeholder="0"
                      aria-label={`${p.name} on ${proj.name}`}
                      onBlur={(e) => {
                        const n = Math.max(0, Math.min(100, Number(e.target.value) || 0));
                        if (n !== percent(p.id, proj.id)) allocate.mutate({ person_id: p.id, project_id: proj.id, percent: n });
                      }}
                      className="w-16 rounded-lg bg-bg px-2 py-1.5 text-[12.5px] focus:ring-2 focus:ring-accent/30 focus:outline-none"
                    />
                  </td>
                ))}
              </tr>
            ))}
            {dir.people.length === 0 && (
              <tr>
                <td colSpan={dir.projects.length + 1} className="px-4 py-4 text-muted">
                  Nobody yet. Add everyone who has joined, or add people below.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      <form
        className="mt-4 grid gap-2 sm:grid-cols-[1fr_1fr_1fr_auto]"
        onSubmit={(e) => {
          e.preventDefault();
          if (name.trim()) add.mutate();
        }}
      >
        <input className={input} placeholder="Name" value={name} onChange={(e) => setName(e.target.value)} aria-label="Name" />
        <input className={input} placeholder="Title (optional)" value={title} onChange={(e) => setTitle(e.target.value)} aria-label="Title" />
        <input className={input} placeholder="Chat handles, comma separated" value={handles} onChange={(e) => setHandles(e.target.value)} aria-label="Handles" />
        <Button disabled={!name.trim() || add.isPending}>
          <PlusIcon size={13} weight="bold" /> Add
        </Button>
      </form>
      {add.error && <FormError>{(add.error as ApiError).message}</FormError>}
    </div>
  );
}

function Channels({ admin }: { admin: boolean }) {
  const dir = useDirectory();
  const refresh = useRefresh();
  const discord = useQuery({ queryKey: ["discord-channels", dir.orgId], queryFn: () => getDiscordChannels(dir.orgId!), enabled: !!dir.orgId && admin });
  const slack = useQuery({ queryKey: ["slack-channels", dir.orgId], queryFn: () => getSlackChannels(dir.orgId!), enabled: !!dir.orgId && admin });
  const [discordPick, setDiscordPick] = useState<Record<string, string>>({});
  const [slackPick, setSlackPick] = useState<Record<string, string>>({});
  const [platform, setPlatform] = useState<"discord" | "slack">("discord");
  const [name, setName] = useState("");
  const [externalId, setExternalId] = useState("");
  const [project, setProject] = useState("");
  const add = useMutation({
    mutationFn: (c: { platform?: "discord" | "slack"; name: string; external_id?: string; project_id?: string | null; split?: boolean }) => createChannel(dir.orgId!, c),
    onSuccess: () => {
      setName("");
      setExternalId("");
      refresh();
      discord.refetch();
      slack.refetch();
    },
  });
  const target = (value: string) => (value === "split" ? { split: true, project_id: null } : { project_id: value || null });

  if (!admin) return <p className="text-[13px] text-muted">Only workspace admins choose which channels Noa reads.</p>;

  return (
    <div>
      <p className="text-[15px] font-semibold">Channels Noa reads</p>
      <p className="mt-1 max-w-xl text-[12.5px] text-muted">
        Noa reads only the channels you map here, never direct messages. Map a channel to one project, or split it so each message is routed on its own.
      </p>
      {add.error && <FormError>{(add.error as ApiError).message}</FormError>}

      <div className="mt-4 grid gap-4 md:grid-cols-2">
        <div className="rounded-2xl p-4 ring-1 ring-line">
          <p className="flex items-center gap-2 text-[13px] font-semibold">
            <DiscordLogoIcon size={16} className="text-accent-fg" /> Discord
            {discord.data?.connected ? <Badge tone="good">Bot connected</Badge> : <Badge>Bot not connected</Badge>}
          </p>
          {!discord.data?.connected && (
            <p className="mt-2 text-[12px] text-muted">
              Set DISCORD_BOT_TOKEN, DISCORD_GUILD_ID and DISCORD_ORG_ID on the API to list your server&rsquo;s channels here. You can add them by hand meanwhile.
            </p>
          )}
          <ul className="mt-3 space-y-1.5">
            {(discord.data?.channels ?? []).map((c) => (
              <li key={c.id} className="flex items-center gap-2 text-[13px]">
                <span className="min-w-0 flex-1 truncate">#{c.name}</span>
                {c.mapped ? (
                  <span className="text-[12px] text-good">Reading</span>
                ) : (
                  <>
                    <select
                      value={discordPick[c.id] ?? ""}
                      onChange={(e) => setDiscordPick((m) => ({ ...m, [c.id]: e.target.value }))}
                      aria-label={`Project for #${c.name}`}
                      className="rounded-lg bg-bg px-2 py-1 text-[12px] focus:outline-none"
                    >
                      <option value="">Project…</option>
                      {dir.projects.map((p) => (
                        <option key={p.id} value={p.id}>
                          {p.name}
                        </option>
                      ))}
                      <option value="split">Split by message</option>
                    </select>
                    <Button size="sm" disabled={!discordPick[c.id] || add.isPending} onClick={() => add.mutate({ platform: "discord", name: `#${c.name}`, external_id: c.id, ...target(discordPick[c.id]) })}>
                      Read
                    </Button>
                  </>
                )}
              </li>
            ))}
          </ul>
        </div>

        <div className="rounded-2xl p-4 ring-1 ring-line">
          <p className="flex items-center gap-2 text-[13px] font-semibold">
            <SlackLogoIcon size={16} className="text-accent-fg" /> Slack
            {slack.data?.connected ? <Badge tone="good">Workspace connected</Badge> : <Badge>Not connected</Badge>}
          </p>
          {!slack.data?.connected && (
            <p className="mt-2 text-[12px] text-muted">
              Install Slack under Settings → Connectors, then return here. Only public and private channels Noa has joined will appear.
            </p>
          )}
          <ul className="mt-3 space-y-1.5">
            {(slack.data?.channels ?? []).map((c) => (
              <li key={c.id} className="flex items-center gap-2 text-[13px]">
                <span className="min-w-0 flex-1 truncate">{c.private ? "🔒 " : "#"}{c.name}</span>
                {c.mapped ? (
                  <span className="text-[12px] text-good">Reading</span>
                ) : (
                  <>
                    <select
                      value={slackPick[c.id] ?? ""}
                      onChange={(e) => setSlackPick((m) => ({ ...m, [c.id]: e.target.value }))}
                      aria-label={`Project for Slack #${c.name}`}
                      className="rounded-lg bg-bg px-2 py-1 text-[12px] focus:outline-none"
                    >
                      <option value="">Project…</option>
                      {dir.projects.map((p) => (
                        <option key={p.id} value={p.id}>{p.name}</option>
                      ))}
                      <option value="split">Split by message</option>
                    </select>
                    <Button
                      size="sm"
                      disabled={!slackPick[c.id] || add.isPending}
                      onClick={() => add.mutate({ platform: "slack", name: `#${c.name}`, external_id: c.id, ...target(slackPick[c.id]) })}
                    >
                      Read
                    </Button>
                  </>
                )}
              </li>
            ))}
          </ul>
        </div>

        <form
          className="space-y-2.5 rounded-2xl p-4 ring-1 ring-line"
          onSubmit={(e) => {
            e.preventDefault();
            const n = name.trim();
            if (n) add.mutate({ platform, name: n.startsWith("#") ? n : `#${n}`, external_id: externalId.trim() || undefined, ...target(project) });
          }}
        >
          <p className="text-[13px] font-semibold">Add a channel by hand</p>
          <select className={input} value={platform} onChange={(e) => setPlatform(e.target.value as "discord" | "slack")} aria-label="Channel platform">
            <option value="discord">Discord</option>
            <option value="slack">Slack</option>
          </select>
          <input className={input} placeholder="#channel-name" value={name} onChange={(e) => setName(e.target.value)} aria-label="Channel name" />
          <input className={input} placeholder={`${platform === "slack" ? "Slack" : "Discord"} channel id (optional)`} value={externalId} onChange={(e) => setExternalId(e.target.value)} aria-label="Channel id" />
          <select className={input} value={project} onChange={(e) => setProject(e.target.value)} aria-label="Project">
            <option value="">Pick a project</option>
            {dir.projects.map((p) => (
              <option key={p.id} value={p.id}>
                {p.name}
              </option>
            ))}
            <option value="split">Split by message</option>
          </select>
          <Button disabled={!name.trim() || !project || add.isPending}>
            <PlusIcon size={13} weight="bold" /> Add channel
          </Button>
        </form>
      </div>

      {dir.channels.length > 0 && (
        <div className="mt-4">
          <p className="text-[12px] font-semibold text-muted">Reading now</p>
          <ul className="mt-2 flex flex-wrap gap-2">
            {dir.channels
              .filter((c) => c.read)
              .map((c) => (
                <li key={c.id} className="rounded-full bg-bg px-3 py-1 text-[12px]">
                  {c.name} → {c.split ? "split" : (dir.project(c.project_id)?.name ?? "no project")}
                </li>
              ))}
          </ul>
        </div>
      )}
    </div>
  );
}

function Done() {
  const dir = useDirectory();
  const allocated = dir.people.filter((p) => p.allocations.length > 0).length;
  const reading = dir.channels.filter((c) => c.read).length;
  return (
    <div>
      <p className="text-[15px] font-semibold">You&rsquo;re set</p>
      <ul className="mt-3 space-y-1.5 text-[13.5px]">
        <li>
          {dir.projects.length} {dir.projects.length === 1 ? "project" : "projects"}
        </li>
        <li>
          {dir.people.length} people, {allocated} on a project
        </li>
        <li>
          {reading} {reading === 1 ? "channel" : "channels"} read
        </li>
      </ul>
      <p className="mt-3 text-[12.5px] text-muted">
        Noa builds the company graph from this as it happens. Proposals from your channels appear in the Inbox; invite the rest of the team from Settings.
      </p>
      <div className="mt-5 flex gap-2">
        <Link href="/" className="rounded-full bg-accent px-4 py-2 text-[13.5px] font-medium text-white">
          Open My day
        </Link>
        <Link href="/settings" className="rounded-full px-4 py-2 text-[13.5px] font-medium ring-1 ring-line">
          Invite people
        </Link>
      </div>
    </div>
  );
}

/* An org map in one go (the shape of docs/seeds/nyi.json): projects, people, allocations, channels and aliases. */
function Import() {
  const dir = useDirectory();
  const refresh = useRefresh();
  const run = useMutation({
    mutationFn: async (file: File) => importOrgMap(dir.orgId!, JSON.parse(await file.text())),
    onSuccess: refresh,
  });
  return (
    <div className="mt-4 flex flex-wrap items-center gap-3 rounded-2xl bg-surface/70 px-5 py-4 text-[12.5px] ring-1 ring-line">
      <FileArrowUpIcon size={18} className="text-accent-fg" />
      <span className="min-w-0 flex-1 text-muted">Have an org map as JSON? Load projects, people, allocations and channels at once. Safe to load again.</span>
      <label className="cursor-pointer rounded-full bg-bg px-3 py-1.5 font-medium ring-1 ring-line hover:bg-mist">
        {run.isPending ? "Loading…" : run.data ? `Loaded ${run.data.projects} projects, ${run.data.people} people` : "Choose file"}
        <input type="file" accept="application/json,.json" className="hidden" onChange={(e) => e.target.files?.[0] && run.mutate(e.target.files[0])} />
      </label>
      {run.error && <FormError>{run.error instanceof SyntaxError ? "That file isn't valid JSON." : (run.error as ApiError).message}</FormError>}
    </div>
  );
}
