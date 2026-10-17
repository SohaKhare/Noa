"use client";

import { BuildingsIcon, CheckIcon, CopyIcon, SignOutIcon } from "@phosphor-icons/react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState, type FormEvent } from "react";
import { Field, FormError, Notice } from "@/components/AuthCard";
import { BrandMark } from "@/components/BrandMark";
import { Badge, Button, Card } from "@/components/ui";
import { ApiError, createWorkspace, getPlatformOrgs, signOut } from "@/lib/api";
import { useMe, useSetMe } from "@/lib/session";

/* Superadmin console (3.14, first slice): create a workspace and invite its first admin. */
export default function AdminConsole() {
  const router = useRouter();
  const { user, loading } = useMe();
  const setMe = useSetMe();

  useEffect(() => {
    if (loading) return;
    if (!user) router.replace("/login?next=/admin");
    else if (!user.is_superadmin) router.replace("/");
  }, [user, loading, router]);

  const orgs = useQuery({ queryKey: ["platform-orgs"], queryFn: getPlatformOrgs, enabled: !!user?.is_superadmin });

  if (!user?.is_superadmin) return <div className="min-h-screen bg-bg" />;

  return (
    <div className="min-h-screen bg-bg">
      <header className="flex h-14 items-center gap-3 border-b border-line bg-surface px-5 sm:px-8">
        <BrandMark size={26} />
        <span className="font-wordmark text-[22px] leading-none">NOA</span>
        <span className="text-[14px] font-semibold">platform</span>
        <Badge tone="signal">Superadmin</Badge>
        <span className="ml-auto text-[13px] text-muted">{user.email}</span>
        {user.memberships.length > 0 && (
          <Link href="/" className="text-[13px] text-accent-fg hover:underline">
            Open workspace
          </Link>
        )}
        <button
          onClick={async () => {
            await signOut();
            setMe(null);
            router.replace("/login");
          }}
          className="flex items-center gap-1.5 rounded-full px-3 py-1.5 text-[13px] text-ink/70 hover:bg-bg hover:text-ink"
        >
          <SignOutIcon size={15} /> Sign out
        </button>
      </header>

      <main className="mx-auto grid max-w-6xl gap-6 px-5 py-8 sm:px-8 lg:grid-cols-[1fr_380px]">
        <section>
          <h1 className="text-[26px] font-semibold tracking-[-0.03em]">Workspaces</h1>
          <p className="mt-1 text-[14px] text-muted">Each workspace is one company. Its admin invites everyone else.</p>
          <div className="mt-5 space-y-3">
            {orgs.isLoading && <p className="text-[13px] text-muted">Loading…</p>}
            {orgs.error && <FormError>{(orgs.error as ApiError).message}</FormError>}
            {orgs.data?.length === 0 && <Notice>No workspaces yet. Create the first one on the right.</Notice>}
            {orgs.data?.map((o) => (
              <Card key={o.id} className="flex flex-wrap items-center gap-4">
                <span className="grid size-11 place-items-center rounded-2xl bg-mist text-accent">
                  <BuildingsIcon size={22} />
                </span>
                <div className="min-w-0 flex-1">
                  <p className="text-[15px] font-semibold">{o.name}</p>
                  <p className="text-[12.5px] text-muted">
                    {o.allowed_domains.map((d) => `@${d}`).join(", ")} · admin {o.admins.join(", ") || "invited, not joined yet"}
                  </p>
                </div>
                <span className="text-[12.5px] text-muted">
                  {o.member_count} {o.member_count === 1 ? "person" : "people"}
                  {o.pending_invites > 0 && ` · ${o.pending_invites} invite${o.pending_invites === 1 ? "" : "s"} pending`}
                  {o.llm_24h && (
                    <span className="block text-right">
                      AI today: {o.llm_24h.calls} {o.llm_24h.calls === 1 ? "call" : "calls"}
                      {o.llm_24h.calls > 0 && ` · ~${o.llm_24h.approx_tokens.toLocaleString()} tokens`}
                      {o.llm_24h.errors > 0 && <span className="text-bad"> · {o.llm_24h.errors} failed</span>}
                    </span>
                  )}
                </span>
              </Card>
            ))}
          </div>
        </section>

        <CreateWorkspace />
      </main>
    </div>
  );
}

function CreateWorkspace() {
  const client = useQueryClient();
  const [form, setForm] = useState({ name: "", domains: "", admin_email: "", admin_title: "" });
  const [done, setDone] = useState<{ name: string; email: string; url: string } | null>(null);
  const [copied, setCopied] = useState(false);
  const set = (k: keyof typeof form) => (e: React.ChangeEvent<HTMLInputElement>) => setForm((f) => ({ ...f, [k]: e.target.value }));

  const create = useMutation({
    mutationFn: () => createWorkspace(form),
    onSuccess: (r) => {
      setDone({ name: r.org.name, email: r.invite.email, url: r.url });
      setForm({ name: "", domains: "", admin_email: "", admin_title: "" });
      client.invalidateQueries({ queryKey: ["platform-orgs"] });
    },
  });
  const error = create.error as ApiError | null;

  const submit = (e: FormEvent) => {
    e.preventDefault();
    setCopied(false);
    create.mutate();
  };

  return (
    <Card className="h-fit">
      <p className="text-[15px] font-semibold">Create a workspace</p>
      <p className="mt-0.5 text-[12.5px] text-muted">The admin you name gets an invite email. They run the workspace and see the lead&rsquo;s view.</p>
      {done && (
        <div className="mt-4 rounded-2xl bg-mist/60 p-3.5 text-[13px]">
          <p className="flex items-center gap-1.5 font-medium">
            <CheckIcon size={14} weight="bold" className="text-good" /> {done.name} created. Invite sent to {done.email}.
          </p>
          <p className="mt-1 text-[12px] text-muted">You can also send this link yourself. It works once and expires in 7 days.</p>
          <button
            onClick={() => {
              navigator.clipboard.writeText(done.url);
              setCopied(true);
            }}
            className="mt-2 flex w-full items-center gap-2 rounded-xl bg-surface px-3 py-2 text-left font-mono text-[11.5px] ring-1 ring-line hover:bg-bg"
          >
            <span className="min-w-0 flex-1 truncate">{done.url}</span>
            {copied ? <CheckIcon size={14} className="text-good" /> : <CopyIcon size={14} />}
          </button>
        </div>
      )}
      <form onSubmit={submit} className="mt-4 space-y-3">
        <Field label="Company name" required value={form.name} onChange={set("name")} placeholder="NotYourIdea" error={error?.fields?.name} />
        <Field
          label="Work email domains"
          required
          value={form.domains}
          onChange={set("domains")}
          placeholder="notyouridea.com"
          hint="Only emails on these domains can join. Separate several with commas."
          error={error?.fields?.allowed_domains}
        />
        <Field label="First admin's work email" type="email" required value={form.admin_email} onChange={set("admin_email")} placeholder="lead@notyouridea.com" />
        <Field label="Their title (optional)" value={form.admin_title} onChange={set("admin_title")} placeholder="PM / Lead" />
        <FormError>{error && !Object.keys(error.fields ?? {}).length ? error.message : null}</FormError>
        <Button type="submit" className="w-full" disabled={create.isPending}>
          {create.isPending ? "Creating…" : "Create and send invite"}
        </Button>
      </form>
    </Card>
  );
}
