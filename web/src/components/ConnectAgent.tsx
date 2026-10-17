"use client";

import { CheckIcon, CopyIcon, PlugsConnectedIcon } from "@phosphor-icons/react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { FormError } from "@/components/AuthCard";
import { Button, Card } from "@/components/ui";
import { ApiError, createMcpToken, getMcpTokens, revokeMcpToken } from "@/lib/api";
import { ago } from "@/lib/work";

/*
  Connect your agent (3.6, 3.22): create a personal token for Noa's MCP server. The token
  is shown once; after that only its name and last use are listed, and it can be revoked.
*/
export function ConnectAgent({ orgId }: { orgId: string }) {
  const client = useQueryClient();
  const tokens = useQuery({ queryKey: ["mcp-tokens", orgId], queryFn: () => getMcpTokens(orgId) });
  const [name, setName] = useState("Claude Code");
  const [fresh, setFresh] = useState<{ token: string; url: string } | null>(null);
  const [copied, setCopied] = useState<string | null>(null);

  const create = useMutation({
    mutationFn: () => createMcpToken(orgId, name || "My agent"),
    onSuccess: (r) => {
      setFresh({ token: r.token, url: r.url });
      client.invalidateQueries({ queryKey: ["mcp-tokens", orgId] });
    },
  });
  const revoke = useMutation({
    mutationFn: (id: string) => revokeMcpToken(orgId, id),
    onSettled: () => client.invalidateQueries({ queryKey: ["mcp-tokens", orgId] }),
  });

  const copy = async (key: string, text: string) => {
    await navigator.clipboard?.writeText(text);
    setCopied(key);
    setTimeout(() => setCopied(null), 1500);
  };

  const command = fresh && `claude mcp add --transport http noa ${fresh.url} --header "Authorization: Bearer ${fresh.token}"`;

  return (
    <Card className="h-fit">
      <p className="flex items-center gap-2 text-[14px] font-semibold">
        <PlugsConnectedIcon size={16} className="text-accent-fg" /> Connect your agent
      </p>
      <p className="mt-0.5 text-[12.5px] text-muted">
        Give Claude Code, Cursor or any MCP client live context from Noa: project context, your tasks, cited answers, who knows what. It acts as you and sees only what you can.
      </p>

      {fresh ? (
        <div className="mt-3 space-y-2 rounded-xl bg-mist/50 p-3 text-[12.5px]">
          <p className="font-medium">Copy your token now. Noa won&rsquo;t show it again.</p>
          <CopyRow label="Claude Code" value={command!} copied={copied === "cmd"} onCopy={() => copy("cmd", command!)} />
          <CopyRow label="Token (for .mcp.json as NOA_TOKEN)" value={fresh.token} copied={copied === "token"} onCopy={() => copy("token", fresh.token)} />
          <button onClick={() => setFresh(null)} className="text-[12px] font-medium text-accent-fg hover:underline">
            Done
          </button>
        </div>
      ) : (
        <div className="mt-3 flex gap-2">
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            aria-label="Token name"
            className="min-w-0 flex-1 rounded-xl bg-bg px-3 py-2 text-[13px] focus:outline-none"
          />
          <Button size="sm" disabled={create.isPending} onClick={() => create.mutate()}>
            Create token
          </Button>
        </div>
      )}
      {(create.error || revoke.error) && (
        <div className="mt-2">
          <FormError>{((create.error ?? revoke.error) as ApiError).message}</FormError>
        </div>
      )}

      {(tokens.data?.tokens.length ?? 0) > 0 && (
        <ul className="mt-3 divide-y divide-line text-[12.5px]">
          {tokens.data!.tokens.map((t) => (
            <li key={t.id} className="flex items-center gap-2 py-2">
              <span className="min-w-0 flex-1">
                <span className="font-medium">{t.name}</span>
                <span className="block text-[11.5px] text-muted">
                  created {ago(t.inserted_at)} · {t.last_used_at ? `last used ${ago(t.last_used_at)}` : "never used"}
                </span>
              </span>
              <button disabled={revoke.isPending} onClick={() => revoke.mutate(t.id)} className="text-[12px] font-medium text-bad hover:underline">
                Revoke
              </button>
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}

function CopyRow({ label, value, copied, onCopy }: { label: string; value: string; copied: boolean; onCopy: () => void }) {
  return (
    <div>
      <p className="text-[11px] text-muted">{label}</p>
      <button onClick={onCopy} className="mt-0.5 flex w-full items-center gap-2 rounded-lg bg-surface px-2.5 py-1.5 text-left font-mono text-[11px] ring-1 ring-line hover:bg-bg">
        <span className="min-w-0 flex-1 truncate">{value}</span>
        {copied ? <CheckIcon size={13} className="text-good" /> : <CopyIcon size={13} />}
      </button>
    </div>
  );
}
