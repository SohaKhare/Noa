"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useEffect, useState, type FormEvent } from "react";
import { AuthCard, Field, FormError, Notice } from "@/components/AuthCard";
import { Button } from "@/components/ui";
import { API_URL, ApiError, requestMagicLink, requestPasswordReset, signIn } from "@/lib/api";
import { useMe, useSetMe } from "@/lib/session";

/* Invite-only sign-in (1.4): password, an emailed one-time link, or a password reset. No sign-up. */

type Mode = "password" | "link" | "reset";

export default function LoginPage() {
  return (
    <Suspense>
      <Login />
    </Suspense>
  );
}

function Login() {
  const router = useRouter();
  const params = useSearchParams();
  const { user } = useMe();
  const setMe = useSetMe();
  const [mode, setMode] = useState<Mode>("password");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(
    params.get("error") === "link_expired" ? "That sign-in link has expired or was already used. Ask for a new one." : null,
  );
  const [sent, setSent] = useState<Mode | null>(null);

  useEffect(() => {
    if (user) router.replace(params.get("next") ?? user.home);
  }, [user, router, params]);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      if (mode === "password") {
        const signedIn = await signIn(email, password);
        setMe(signedIn);
        router.replace(params.get("next") ?? signedIn.home);
        return;
      }
      await (mode === "link" ? requestMagicLink(email) : requestPasswordReset(email));
      setSent(mode);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Something went wrong. Try again.");
    } finally {
      setBusy(false);
    }
  };

  const switchTo = (m: Mode) => {
    setMode(m);
    setError(null);
    setSent(null);
  };

  return (
    <AuthCard
      title={mode === "reset" ? "Reset your password" : "Sign in"}
      sub="Noa is invite-only. Use the work email your invite was sent to."
      footer={
        <>
          No account? Ask your workspace admin for an invite.
          {process.env.NODE_ENV === "development" && (
            <>
              {" "}
              <a href={`${API_URL}/dev/mailbox`} target="_blank" rel="noreferrer" className="text-accent-fg underline-offset-2 hover:underline">
                Dev mailbox
              </a>
            </>
          )}
        </>
      }
    >
      {sent ? (
        <div className="space-y-4">
          <Notice>
            If <strong>{email}</strong> has a Noa account, {sent === "link" ? "a sign-in link" : "a reset link"} is on its way. It works once and expires soon.
          </Notice>
          <Button variant="ghost" className="w-full" onClick={() => switchTo("password")}>
            Back to sign in
          </Button>
        </div>
      ) : (
        <form onSubmit={submit} className="space-y-3">
          <Field label="Work email" type="email" autoComplete="email" required value={email} onChange={(e) => setEmail(e.target.value)} placeholder="you@company.com" />
          {mode === "password" && (
            <Field label="Password" type="password" autoComplete="current-password" required value={password} onChange={(e) => setPassword(e.target.value)} />
          )}
          <FormError>{error}</FormError>
          <Button type="submit" className="w-full" disabled={busy}>
            {busy ? "One moment…" : mode === "password" ? "Sign in" : mode === "link" ? "Email me a sign-in link" : "Email me a reset link"}
          </Button>
          <div className="flex justify-between pt-1 text-[12.5px]">
            <button type="button" onClick={() => switchTo(mode === "link" ? "password" : "link")} className="text-accent-fg hover:underline">
              {mode === "link" ? "Use my password" : "Email me a link instead"}
            </button>
            {mode !== "reset" && (
              <button type="button" onClick={() => switchTo("reset")} className="text-muted hover:text-ink">
                Forgot password?
              </button>
            )}
          </div>
        </form>
      )}
    </AuthCard>
  );
}
