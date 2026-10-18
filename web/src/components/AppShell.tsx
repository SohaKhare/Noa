"use client";

import {
  ArrowsLeftRightIcon,
  AtIcon,
  RobotIcon,
  BellIcon,
  CaretDownIcon,
  ChartBarIcon,
  ChatCircleDotsIcon,
  CheckCircleIcon,
  FolderSimpleIcon,
  GavelIcon,
  GearSixIcon,
  MagnifyingGlassIcon,
  PackageIcon,
  PlusIcon,
  ShieldCheckIcon,
  SignOutIcon,
  SquaresFourIcon,
  SunHorizonIcon,
  TrayIcon,
  UsersThreeIcon,
  type Icon,
} from "@phosphor-icons/react";
import { useQuery } from "@tanstack/react-query";
import { AnimatePresence, motion } from "motion/react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useRef, useState, type ReactNode } from "react";
import { cn } from "@/lib/cn";
import { getFeed, roleLabel, signOut, type ApiError, type FeedItem } from "@/lib/api";
import { ago, useDirectory, useOrgId, useProposals } from "@/lib/work";
import { currentMembership, initials, isOrgAdmin, useMe, useSetMe } from "@/lib/session";
import { BrandMark } from "./BrandMark";
import { Avatar } from "./ui";

/* App shell: white sidebar (workspace, search, grouped nav, projects), sticky top bar (breadcrumbs, notifications, new task). */

type NavItem = { href: string; label: string; Icon: Icon; count?: number };

const work: NavItem[] = [
  { href: "/", label: "My day", Icon: SunHorizonIcon },
  { href: "/inbox", label: "Inbox", Icon: TrayIcon },
  { href: "/ask", label: "Ask Noa", Icon: ChatCircleDotsIcon },
];
const team: NavItem[] = [
  { href: "/people", label: "People", Icon: UsersThreeIcon },
  { href: "/portfolio", label: "Portfolio", Icon: ChartBarIcon },
  { href: "/pack", label: "Agent pack", Icon: PackageIcon },
];

const titles: Record<string, string> = {
  "": "My day",
  inbox: "Inbox",
  ask: "Ask Noa",
  projects: "Projects",
  people: "People",
  portfolio: "Portfolio",
  pack: "Agent pack",
  settings: "Settings",
};

export function AppShell({ children }: { children: ReactNode }) {
  const path = usePathname();
  const active = (href: string) => (href === "/" ? path === "/" : path === href || path.startsWith(`${href}/`));
  const router = useRouter();
  const { user, loading, error } = useMe();
  const setMe = useSetMe();
  const membership = currentMembership(user);
  const admin = isOrgAdmin(user);
  const { projects, error: dirError, refetch: refetchDir } = useDirectory();
  const inbox = useProposals().data?.length ?? 0;

  // Invite-only: signed-out people go to sign in; a superadmin with no workspace goes to the console.
  useEffect(() => {
    if (loading || error) return;
    if (!user) router.replace(`/login?next=${encodeURIComponent(path)}`);
    else if (!membership && user.is_superadmin) router.replace("/admin");
  }, [user, loading, error, membership, path, router]);

  if (error) return <ApiDown message={error.message} />;
  if (!user || !membership) return <div className="min-h-screen bg-bg" aria-busy="true" />;

  // The lead's (PM) side: Portfolio and Agent pack are for admins and PMs.
  const teamItems = admin || membership.role === "pm" ? team : team.filter((t) => t.href === "/people");

  return (
    <div className="flex min-h-screen bg-bg">
      <aside className="sticky top-0 hidden h-screen w-[248px] shrink-0 flex-col border-r border-line bg-surface md:flex">
        <Link href="/" className="mx-5 mt-4 flex items-center gap-2">
          <BrandMark size={26} />
          <span className="font-wordmark text-[22px] leading-none">NOA</span>
        </Link>
        <button className="mx-3 mt-3 flex items-center gap-2.5 rounded-xl px-2 py-2 text-left hover:bg-bg">
          <span className="min-w-0 flex-1 leading-tight">
            <span className="block truncate text-[13.5px] font-semibold">{membership.org.name}</span>
            <span className="block text-[11px] text-muted">{membership.title || roleLabel[membership.role]}</span>
          </span>
          <CaretDownIcon size={13} className="text-muted" />
        </button>

        <button className="mx-3 mt-2 flex items-center gap-2 rounded-xl bg-bg px-3 py-2 text-[13px] text-muted ring-1 ring-line hover:text-ink">
          <MagnifyingGlassIcon size={15} />
          Search or ask
          <kbd className="ml-auto rounded-md bg-surface px-1.5 font-mono text-[10.5px] ring-1 ring-line">⌘K</kbd>
        </button>

        <nav aria-label="App" className="mt-4 flex-1 overflow-y-auto px-3 pb-3">
          <NavGroup items={work.map((w) => (w.href === "/inbox" ? { ...w, count: inbox } : w))} active={active} />

          <SectionLabel
            action={
              <Link href="/projects" className="text-muted hover:text-ink" aria-label="All projects">
                <SquaresFourIcon size={13} />
              </Link>
            }
          >
            Projects
          </SectionLabel>
          <ul className="space-y-0.5">
            {projects.map((p) => (
              <li key={p.id}>
                <Link
                  href={`/projects/${p.key}`}
                  className={cn(
                    "flex items-center gap-2.5 rounded-lg px-2.5 py-1.5 text-[13px] transition-colors",
                    path.startsWith(`/projects/${p.key}`) ? "bg-mist font-medium text-ink" : "text-ink/70 hover:bg-bg hover:text-ink",
                  )}
                >
                  <FolderSimpleIcon size={15} className="text-muted" />
                  <span className="truncate">{p.name}</span>
                </Link>
              </li>
            ))}
          </ul>

          <SectionLabel>Team</SectionLabel>
          <NavGroup items={teamItems} active={active} />
        </nav>

        <div className="border-t border-line p-3">
          <Link
            href="/settings"
            className={cn(
              "flex items-center gap-2.5 rounded-lg px-2.5 py-2 text-[13.5px] transition-colors",
              active("/settings") ? "bg-mist font-medium" : "text-ink/70 hover:bg-bg hover:text-ink",
            )}
          >
            <GearSixIcon size={17} /> Settings
          </Link>
          {user.is_superadmin && (
            <Link href="/admin" className="flex items-center gap-2.5 rounded-lg px-2.5 py-2 text-[13.5px] text-ink/70 hover:bg-bg hover:text-ink">
              <ShieldCheckIcon size={17} /> Platform
            </Link>
          )}
          <div className="mt-1 flex items-center gap-2.5 rounded-lg px-2.5 py-2">
            <Avatar initials={initials(user)} tone="accent" />
            <div className="min-w-0 flex-1 leading-tight">
              <p className="truncate text-[13px] font-medium">{user.name || user.email}</p>
              <p className="text-[11px] text-muted">{roleLabel[membership.role]}</p>
            </div>
            <button
              aria-label="Sign out"
              title="Sign out"
              onClick={async () => {
                await signOut().catch(() => undefined);
                setMe(null);
                router.replace("/login");
              }}
              className="grid size-8 shrink-0 place-items-center rounded-full text-ink/55 hover:bg-bg hover:text-ink"
            >
              <SignOutIcon size={15} />
            </button>
          </div>
        </div>
      </aside>

      <div className="flex min-w-0 flex-1 flex-col">
        <TopBar path={path} />
        <main className="min-w-0 flex-1 px-5 pt-6 pb-12 sm:px-8">
          {dirError && (
            <div role="alert" className="mx-auto mb-5 flex max-w-6xl flex-wrap items-center gap-3 rounded-2xl bg-bad/10 px-4 py-3 text-[13px] text-bad ring-1 ring-bad/20">
              <span className="min-w-0 flex-1">
                {(dirError as ApiError).status === 0 ? "Noa can't reach its server right now. Your changes won't save until it's back." : (dirError as ApiError).message}
              </span>
              <button onClick={() => refetchDir()} className="rounded-full bg-surface px-3 py-1 font-medium ring-1 ring-bad/20 hover:bg-bg">
                Try again
              </button>
            </div>
          )}
          {children}
        </main>
      </div>
    </div>
  );
}

function NavGroup({ items, active }: { items: NavItem[]; active: (href: string) => boolean }) {
  return (
    <ul className="space-y-0.5">
      {items.map(({ href, label, Icon, count }) => (
        <li key={href}>
          <Link
            href={href}
            className={cn(
              "flex items-center gap-2.5 rounded-lg px-2.5 py-2 text-[13.5px] transition-colors",
              active(href) ? "bg-mist font-medium text-ink" : "text-ink/70 hover:bg-bg hover:text-ink",
            )}
          >
            <Icon size={17} weight={active(href) ? "fill" : "regular"} className={active(href) ? "text-accent" : undefined} />
            {label}
            {count ? <span className="ml-auto rounded-full bg-accent px-1.5 text-[10.5px] font-semibold text-white">{count}</span> : null}
          </Link>
        </li>
      ))}
    </ul>
  );
}

function SectionLabel({ children, action }: { children: ReactNode; action?: ReactNode }) {
  return (
    <p className="eyebrow mt-6 mb-1.5 flex items-center justify-between px-2.5 text-muted">
      {children}
      {action}
    </p>
  );
}

function TopBar({ path }: { path: string }) {
  const { project } = useDirectory();
  const parts = path.split("/").filter(Boolean);
  const crumbs: { label: string; href?: string }[] = [
    { label: titles[parts[0] ?? ""] ?? "Noa", href: parts.length > 1 ? `/${parts[0]}` : undefined },
  ];
  if (parts[0] === "projects" && parts[1]) crumbs.push({ label: project(parts[1])?.name ?? parts[1] });

  return (
    <header className="sticky top-0 z-30 flex h-14 items-center gap-3 border-b border-line bg-bg/85 px-5 backdrop-blur-md sm:px-8">
      <Link href="/" className="flex items-center gap-1.5 md:hidden">
        <BrandMark size={22} />
        <span className="font-wordmark text-[18px] leading-none">NOA</span>
      </Link>
      <nav aria-label="Breadcrumb" className="flex min-w-0 items-center gap-2 text-[13.5px]">
        {crumbs.map((c, i) => (
          <span key={c.label} className="flex items-center gap-2">
            {i > 0 && <span className="text-ink/25">/</span>}
            {c.href ? (
              <Link href={c.href} className="text-muted hover:text-ink">
                {c.label}
              </Link>
            ) : (
              <span className="truncate font-medium">{c.label}</span>
            )}
          </span>
        ))}
      </nav>
      <div className="ml-auto flex items-center gap-2">
        <Notifications />
        <button className="inline-flex items-center gap-1.5 rounded-full bg-accent px-3.5 py-1.5 text-[13px] font-medium text-white hover:bg-accent-soft">
          <PlusIcon size={14} weight="bold" /> New task
        </button>
      </div>
    </header>
  );
}

const notifIcon: Record<FeedItem["kind"], Icon> = {
  approval: GavelIcon,
  change: AtIcon,
  shift: ArrowsLeftRightIcon,
  decision: CheckCircleIcon,
  pack: RobotIcon,
};

const SEEN = "noa.feed.seen";
const readSeen = () => {
  try {
    return localStorage.getItem(SEEN) ?? "";
  } catch {
    return "";
  }
};

/* The bell: what waits on you and what changed around you, from /feed. Unread = newer than when you last opened it. */
function Notifications() {
  const [open, setOpen] = useState(false);
  const [seen, setSeen] = useState(readSeen);
  const ref = useRef<HTMLDivElement>(null);
  const router = useRouter();
  const orgId = useOrgId();
  const feed = useQuery({ queryKey: ["feed", orgId], queryFn: () => getFeed(orgId!), enabled: !!orgId, refetchInterval: 30_000 });
  const items = feed.data ?? [];
  const unread = items.filter((n) => n.at > seen).length;

  const markRead = () => {
    const now = new Date().toISOString();
    setSeen(now);
    try {
      localStorage.setItem(SEEN, now);
    } catch {
      /* private mode: unread resets on reload */
    }
  };

  useEffect(() => {
    if (!open) return;
    const close = (e: MouseEvent) => {
      if (!ref.current?.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("mousedown", close);
    return () => document.removeEventListener("mousedown", close);
  }, [open]);

  return (
    <div ref={ref} className="relative">
      <button
        aria-label={`Notifications, ${unread} unread`}
        aria-expanded={open}
        onClick={() => setOpen((v) => !v)}
        className="relative grid size-9 place-items-center rounded-full text-ink/70 hover:bg-surface hover:text-ink"
      >
        <BellIcon size={18} />
        {unread > 0 && <span className="absolute top-2 right-2 size-2 rounded-full bg-signal ring-2 ring-bg" />}
      </button>
      <AnimatePresence>
        {open && (
          <motion.div
            initial={{ opacity: 0, y: -6, scale: 0.98 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: -4 }}
            transition={{ duration: 0.16 }}
            className="absolute right-0 z-50 mt-2 w-[360px] overflow-hidden rounded-2xl bg-surface card-shadow"
          >
            <p className="flex items-center justify-between border-b border-line px-4 py-3 text-[13px] font-semibold">
              Notifications
              <button onClick={markRead} className="text-[12px] font-normal text-muted hover:text-ink">
                Mark all read
              </button>
            </p>
            <ul className="max-h-[380px] divide-y divide-line overflow-y-auto">
              {items.length === 0 && <li className="px-4 py-6 text-center text-[13px] text-muted">All quiet. Nothing waits on you.</li>}
              {items.map((n) => {
                const I = notifIcon[n.kind];
                const fresh = n.at > seen;
                return (
                  <li key={n.id}>
                    <button
                      onClick={() => {
                        setOpen(false);
                        if (n.href) router.push(n.href);
                      }}
                      className="flex w-full gap-3 px-4 py-3 text-left hover:bg-bg"
                    >
                      <span className="grid size-8 shrink-0 place-items-center rounded-full bg-mist text-accent">
                        <I size={15} />
                      </span>
                      <span className="min-w-0 flex-1">
                        <span className={cn("block text-[13px]", fresh && "font-medium")}>{n.text}</span>
                        <span className="text-[11.5px] text-muted">{ago(n.at)}</span>
                      </span>
                      {fresh && <span className="mt-1.5 size-2 shrink-0 rounded-full bg-signal" />}
                    </button>
                  </li>
                );
              })}
            </ul>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

function ApiDown({ message }: { message: string }) {
  return (
    <div className="grid min-h-screen place-items-center bg-bg p-6 text-center">
      <div className="max-w-sm">
        <div className="mb-4 flex items-center justify-center gap-2">
          <BrandMark size={28} />
          <span className="font-wordmark text-[26px] leading-none">NOA</span>
        </div>
        <p className="text-[18px] font-semibold">Noa can&rsquo;t reach its server</p>
        <p className="mt-1.5 text-[13.5px] text-muted">{message}</p>
        <button onClick={() => location.reload()} className="mt-4 rounded-full bg-accent px-4 py-2 text-[13.5px] font-medium text-white hover:bg-accent-soft">
          Try again
        </button>
      </div>
    </div>
  );
}
