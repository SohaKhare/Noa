"use client";

import { useQuery } from "@tanstack/react-query";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useState, type FormEvent } from "react";
import { AuthCard, Field, FormError } from "@/components/AuthCard";
import { Button } from "@/components/ui";
import { ApiError, getJoinInfo, requestToJoin } from "@/lib/api";

/* Ask to join a workspace from its shared link (1.5). An org admin approves; the invite email follows. */
export default function Join() {
  const { slug } = useParams<{ slug: string }>();
  const org = useQuery({ queryKey: ["join", slug], queryFn: () => getJoinInfo(slug), retry: false });
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);

  if (org.isLoading) return <AuthCard title="Opening…">{null}</AuthCard>;
  if (org.error)
    return (
      <AuthCard title="This join link isn't valid" sub="Ask someone in your team for the right link.">
        <Link href="/login" className="block w-full rounded-full bg-accent py-2.5 text-center text-[14px] font-medium text-white hover:bg-accent-soft">
          Go to sign in
        </Link>
      </AuthCard>
    );

  const info = org.data!;
  if (sent)
    return (
      <AuthCard title="Request sent" sub={`An admin of ${info.name} will look at it. When they approve, you'll get an invite at ${email} to set up your account.`}>
        <Link href="/login" className="block w-full rounded-full bg-surface py-2.5 text-center text-[14px] font-medium ring-1 ring-line hover:bg-bg">
          Already have an account? Sign in
        </Link>
      </AuthCard>
    );

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await requestToJoin(slug, { name, email, note: note || undefined });
      setSent(true);
    } catch (err) {
      setError(err instanceof ApiError ? err : new ApiError(0, "error", "Something went wrong. Try again."));
    } finally {
      setBusy(false);
    }
  };

  return (
    <AuthCard title={`Join ${info.name} on Noa`} sub={`Use your ${info.domains.map((d) => `@${d}`).join(" or ")} email. An admin approves new people.`}>
      <form onSubmit={submit} className="space-y-3">
        <Field label="Your name" value={name} onChange={(e) => setName(e.target.value)} required autoComplete="name" />
        <Field label="Work email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} required autoComplete="email" />
        <Field label="Note for the admin (optional)" value={note} onChange={(e) => setNote(e.target.value)} placeholder="e.g. joining the Veriq team" />
        {error && <FormError>{error.message}</FormError>}
        <Button className="w-full justify-center" disabled={busy || !name.trim() || !email.trim()}>
          {busy ? "Sending…" : "Ask to join"}
        </Button>
      </form>
    </AuthCard>
  );
}
