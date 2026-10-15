"use client";

import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { Suspense, useState } from "react";
import { Button } from "@/components/ui";

export default function InvitePage() {
  return (
    <Suspense>
      <Invite />
    </Suspense>
  );
}

function Invite() {
  const params = useSearchParams();
  const email = params.get("email") ?? "you@notyouridea.com";
  const [name, setName] = useState("");

  return (
    <div className="grid min-h-screen place-items-center p-4 mist-wash">
      <div className="w-full max-w-sm rounded-[28px] bg-surface p-8 card-shadow">
        <p className="text-[17px] font-semibold tracking-tight">Noa</p>
        <h1 className="mt-6 text-[24px] font-semibold tracking-[-0.03em]">Join NotYourIdea</h1>
        <p className="mt-1 text-[13.5px] text-muted">Prathamesh invited {email} as a member.</p>
        <form action="/" className="mt-6 space-y-3">
          <label className="block">
            <span className="text-[12px] text-muted">Your name</span>
            <input
              name="name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              autoComplete="name"
              required
              className="mt-1 w-full rounded-xl bg-bg px-3.5 py-2.5 text-[14px] focus:ring-2 focus:ring-accent/30 focus:outline-none"
            />
          </label>
          <Button type="submit" className="w-full" disabled={name.trim().length === 0}>
            Accept invite
          </Button>
        </form>
        <p className="mt-6 text-center text-[12px] text-muted">
          Already on the team?{" "}
          <Link href="/login" className="text-accent-fg">
            Sign in
          </Link>
        </p>
      </div>
    </div>
  );
}
