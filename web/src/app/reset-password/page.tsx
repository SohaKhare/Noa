"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useState, type FormEvent } from "react";
import { AuthCard, Field, FormError } from "@/components/AuthCard";
import { Button } from "@/components/ui";
import { ApiError, resetPassword } from "@/lib/api";
import { useSetMe } from "@/lib/session";

export default function ResetPasswordPage() {
  return (
    <Suspense>
      <Reset />
    </Suspense>
  );
}

function Reset() {
  const token = useSearchParams().get("token") ?? "";
  const router = useRouter();
  const setMe = useSetMe();
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(token ? null : "This reset link is missing its token. Ask for a new one from the sign-in page.");

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const user = await resetPassword(token, password);
      setMe(user);
      router.replace(user.home);
    } catch (err) {
      setError(err instanceof ApiError && err.status === 401 ? "This reset link has expired or was already used. Ask for a new one." : err instanceof ApiError ? err.message : "Something went wrong.");
      setBusy(false);
    }
  };

  return (
    <AuthCard title="Choose a new password" footer={<Link href="/login" className="text-accent-fg hover:underline">Back to sign in</Link>}>
      <form onSubmit={submit} className="space-y-3">
        <Field label="New password" type="password" autoComplete="new-password" required minLength={10} value={password} onChange={(e) => setPassword(e.target.value)} hint="At least 10 characters." />
        <FormError>{error}</FormError>
        <Button type="submit" className="w-full" disabled={busy || !token}>
          {busy ? "Saving…" : "Save and sign in"}
        </Button>
      </form>
    </AuthCard>
  );
}
