"use client";

import { useSyncExternalStore } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ApiError, getDiscordAccount, linkDiscordAccount, unlinkDiscordAccount } from "@/lib/api";
import { useMe } from "@/lib/session";
import { useDirectory } from "@/lib/work";
import { FormError } from "./AuthCard";
import { Card } from "./ui";

function subscribe(listener: () => void) {
  window.addEventListener("hashchange", listener);
  return () => window.removeEventListener("hashchange", listener);
}
const fragment = () => window.location.hash;
const serverFragment = () => "";

export function DiscordLinkConfirmation() {
  const hash = useSyncExternalStore(subscribe, fragment, serverFragment);
  const params = new URLSearchParams(hash.slice(1));
  const code = params.get("discord-link");
  const orgId = params.get("discord-org");
  const { user } = useMe();
  const org = user?.memberships.find((m) => m.org.id === orgId)?.org;
  const client = useQueryClient();
  const link = useMutation({
    mutationFn: () => linkDiscordAccount(orgId!, code!),
    onSuccess: () => {
      client.invalidateQueries({ queryKey: ["discord-account", orgId] });
      window.history.replaceState(null, "", window.location.pathname + window.location.search);
      window.dispatchEvent(new HashChangeEvent("hashchange"));
    },
  });

  if (!code && !link.isSuccess) return null;
  return (
    <Card className="mb-4">
      <p className="text-[14px] font-semibold">Link your Discord account</p>
      {link.isSuccess ? (
        <p className="mt-2 text-[13px]">Discord is linked. Try /noa ask, /noa tasks or /noa inbox in your server.</p>
      ) : (
        <>
          <p className="mt-2 text-[13px] text-muted">
            {org ? `Confirm linking the Discord account that requested this link to your Noa account in ${org.name}.` : "Sign in with a member account for this workspace, then reopen your private Discord link."}
            {" "}Only confirm if you just ran /noa link yourself. Your Noa role controls what you can do.
          </p>
          <button onClick={() => link.mutate()} disabled={!org || !code || link.isPending} className="mt-3 rounded-full bg-accent px-4 py-2 text-[13px] font-medium text-white disabled:opacity-60">
            {link.isPending ? "Linking…" : "Confirm my Discord account"}
          </button>
          {link.error && <div className="mt-2"><FormError>{(link.error as ApiError).message}</FormError></div>}
        </>
      )}
    </Card>
  );
}

export function DiscordAccount() {
  const { orgId } = useDirectory();
  const client = useQueryClient();
  const account = useQuery({
    queryKey: ["discord-account", orgId],
    queryFn: () => getDiscordAccount(orgId!),
    enabled: !!orgId,
  });
  const unlink = useMutation({
    mutationFn: () => unlinkDiscordAccount(orgId!),
    onSuccess: () => client.invalidateQueries({ queryKey: ["discord-account", orgId] }),
  });
  return (
    <Card>
      <p className="text-[14px] font-semibold">Your Discord account</p>
      <p className="mt-2 text-[13px] text-muted">
        {account.data?.discord_id
          ? `Verified account: ${account.data.discord_id}. Commands and approval buttons use your Noa permissions.`
          : "Run /noa link in your connected server, then confirm the private link here while signed in. Matching a display name is not enough."}
      </p>
      <p className="mt-2 text-[12.5px] text-muted">Choose Discord in Notifications for task, approval, digest and handover DMs. Direct messages are never ingested.</p>
      {account.data?.discord_id && (
        <button onClick={() => unlink.mutate()} disabled={unlink.isPending} className="mt-3 text-[13px] font-medium text-accent-fg underline">
          {unlink.isPending ? "Unlinking…" : "Unlink my account"}
        </button>
      )}
      {(account.error || unlink.error) && <div className="mt-2"><FormError>{((account.error || unlink.error) as ApiError).message}</FormError></div>}
    </Card>
  );
}
