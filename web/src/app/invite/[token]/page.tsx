"use client";

import { useQuery } from "@tanstack/react-query";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useState, type FormEvent } from "react";
import { AuthCard, Field, FormError, Notice } from "@/components/AuthCard";
import { Button } from "@/components/ui";
import { acceptInvite, ApiError, getInvite, roleLabel } from "@/lib/api";
import { useSetMe } from "@/lib/session";

/* Accept an invite (1.5): name and password, then straight into the workspace. */
export default function AcceptInvite() {
  const { token } = useParams<{ token: string }>();
  const router = useRouter();
  const setMe = useSetMe();
  const invite = useQuery({ queryKey: ["invite", token], queryFn: () => getInvite(token), retry: false });
  const [name, setName] = useState("");
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);

  if (invite.isLoading) return <AuthCard title="Checking your invite…">{null}</AuthCard>;

  if (invite.error) {
    const err = invite.error as ApiError;
    return (
      <AuthCard title="This invite can't be used" sub={err.message}>
        <Link href="/login" className="block w-full rounded-full bg-accent py-2.5 text-center text-[14px] font-medium text-white hover:bg-accent-soft">
          Go to sign in
        </Link>
      </AuthCard>
    );
  }

  const info = invite.data!;
  const mismatch = !info.has_account && confirm.length > 0 && confirm !== password;

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    if (mismatch) return;
    setBusy(true);
    setError(null);
    try {
      const user = await acceptInvite(token, name, password);
      setMe(user);
      router.replace(user.home);
    } catch (err) {
      setError(err instanceof ApiError ? err : new ApiError(0, "error", "Something went wrong. Try again."));
      setBusy(false);
    }
  };

  return (
    <AuthCard
      title={`Join ${info.org.name}`}
      sub={
        <>
          You&rsquo;re invited as <strong className="text-ink">{info.title || roleLabel[info.role]}</strong> with <strong className="text-ink">{info.email}</strong>.
        </>
      }
      footer={
        <>
          Wrong person? <Link href="/login" className="text-accent-fg hover:underline">Sign in with another account</Link>
        </>
      }
    >
      <form onSubmit={submit} className="space-y-3">
        {info.has_account ? (
          <Notice>You already have a Noa account with this email. Accepting adds you to {info.org.name}.</Notice>
        ) : (
          <>
            <Field label="Your name" autoComplete="name" required value={name} onChange={(e) => setName(e.target.value)} error={error?.fields?.name} />
            <Field
              label="Password"
              type="password"
              autoComplete="new-password"
              required
              minLength={10}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              hint="At least 10 characters."
              error={error?.fields?.password}
            />
            <Field
              label="Confirm password"
              type="password"
              autoComplete="new-password"
              required
              value={confirm}
              onChange={(e) => setConfirm(e.target.value)}
              error={mismatch ? "Passwords don't match." : undefined}
            />
          </>
        )}
        <FormError>{error && !Object.keys(error.fields ?? {}).length ? error.message : null}</FormError>
        <Button type="submit" className="w-full" disabled={busy || mismatch}>
          {busy ? "Setting up…" : info.has_account ? `Join ${info.org.name}` : "Create account and join"}
        </Button>
      </form>
    </AuthCard>
  );
}
