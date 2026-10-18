"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { Card } from "@/components/ui";
import { ApiError, getMeetings, meetingAction, startMeeting } from "@/lib/api";
import { useDirectory } from "@/lib/work";
import { currentMembership, useMe } from "@/lib/session";

export function MeetingNotetaker() {
  const { orgId, projects } = useDirectory();
  const { user } = useMe();
  const role = currentMembership(user)?.role;
  const canManage = user?.is_superadmin || role === "pm" || role === "org_admin";
  const [url, setUrl] = useState("");
  const [consent, setConsent] = useState(false);
  const [chosen, setChosen] = useState<Record<string, string>>({});
  const [channel, setChannel] = useState<Record<string, string>>({});
  const client = useQueryClient();
  const meetings = useQuery({ queryKey: ["meetings", orgId], queryFn: () => getMeetings(orgId!), enabled: !!orgId, refetchInterval: 10000 });
  const start = useMutation({
    mutationFn: () => startMeeting(orgId!, url.trim()),
    onSuccess: () => { setUrl(""); setConsent(false); client.invalidateQueries({ queryKey: ["meetings", orgId] }); },
  });
  const act = useMutation({
    mutationFn: ({ id, action, data }: { id: string; action: "stop" | "sync" | "import"; data?: Record<string, string> }) => meetingAction(orgId!, id, action, data),
    onSuccess: () => client.invalidateQueries({ queryKey: ["meetings", orgId] }),
  });
  const error = start.error || act.error;

  return <div className="space-y-4">
    <Card className="space-y-4 p-5">
      <h2 className="font-semibold">Noa Notetaker · Google Meet</h2>
      <p className="text-sm text-muted">A visible bot joins only when you start it. Participants must be informed before recording. Transcripts are visible to workspace members. The Attendee five-hour trial is limited; usage after that may be billed to your Attendee account.</p>
      {canManage ? <form onSubmit={(e) => { e.preventDefault(); if (consent) start.mutate(); }} className="space-y-3">
        <label className="block text-sm">Google Meet link
          <input required type="url" pattern="https://meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}" placeholder="https://meet.google.com/abc-defg-hij" value={url} onChange={(e) => setUrl(e.target.value)} className="mt-1 w-full rounded-xl border border-line bg-surface px-3 py-2" />
        </label>
        <label className="flex gap-2 text-sm"><input type="checkbox" checked={consent} onChange={(e) => setConsent(e.target.checked)} /> I have told participants and confirmed they consent to the notetaker joining and capturing meeting content.</label>
        <button type="submit" disabled={!consent || start.isPending} className="rounded-xl bg-accent px-4 py-2 text-white disabled:opacity-50">{start.isPending ? "Joining…" : "Start notetaker"}</button>
      </form> : <p className="text-sm text-muted">An org admin or PM can start a notetaker.</p>}
      {error && <p role="alert" className="text-sm text-bad">{error instanceof ApiError ? error.message : "That action failed. Try again."}</p>}
    </Card>
    {meetings.isError && <p role="alert" className="text-sm text-bad">Could not load meetings.</p>}
    {meetings.data?.map((meeting) => <Card key={meeting.id} className="space-y-3 p-5">
      <p className="text-sm font-semibold">{meeting.meeting_url} <span className="text-muted">· {meeting.status}</span></p>
      <p className="text-xs text-muted">Consent recorded {new Date(meeting.consent_at).toLocaleString()}. Attendee may require the host to admit the visible bot.</p>
      {canManage && <div className="flex flex-wrap gap-2 text-sm">
        {["joining", "running"].includes(meeting.status) && <button type="button" onClick={() => act.mutate({ id: meeting.id, action: "stop" })} disabled={act.isPending} className="rounded-lg border border-line px-3 py-1">Stop bot</button>}
        {["running", "stopped"].includes(meeting.status) && <button type="button" onClick={() => act.mutate({ id: meeting.id, action: "sync" })} disabled={act.isPending} className="rounded-lg border border-line px-3 py-1">Fetch final transcript</button>}
      </div>}
      {meeting.transcript.length > 0 && <details className="text-sm"><summary>Transcript ({meeting.transcript.length} lines)</summary>
        <div className="mt-2 max-h-80 space-y-2 overflow-auto">{meeting.transcript.map((line, i) => <p key={i}><span className="text-muted">{Math.floor(line.start_ms / 60000)}:{String(Math.floor(line.start_ms / 1000) % 60).padStart(2, "0")} · {line.speaker || "Unknown speaker"}</span> {line.text}</p>)}</div>
      </details>}
      {meeting.status === "ready" && canManage && <div className="space-y-2 text-sm">
        <p>Noa suggests a project based on names mentioned. Confirm a project and a consented source channel. The existing Minutes workflow will propose cited tasks and decisions for Inbox review.</p>
        <select aria-label="Project for meeting" value={chosen[meeting.id] ?? meeting.suggested_project_id ?? ""} onChange={(e) => setChosen({ ...chosen, [meeting.id]: e.target.value })} className="rounded-lg border border-line bg-surface px-3 py-2">
          <option value="">Choose project</option>{projects.map((p) => <option key={p.id} value={p.id}>{p.name}{p.id === meeting.suggested_project_id ? " (suggested)" : ""}</option>)}
        </select>{" "}
        <select aria-label="Consent channel" value={channel[meeting.id] ?? ""} onChange={(e) => setChannel({ ...channel, [meeting.id]: e.target.value })} className="rounded-lg border border-line bg-surface px-3 py-2">
          <option value="">Choose source channel</option>{meeting.channels.filter((c) => c.read && c.project_id === (chosen[meeting.id] ?? meeting.suggested_project_id)).map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
        </select>{" "}
        <button type="button" disabled={act.isPending || !(chosen[meeting.id] ?? meeting.suggested_project_id) || !channel[meeting.id]} onClick={() => act.mutate({ id: meeting.id, action: "import", data: { project_id: chosen[meeting.id] ?? meeting.suggested_project_id!, channel_id: channel[meeting.id]!, title: "Google Meet" } })} className="rounded-lg bg-accent px-3 py-2 text-white disabled:opacity-50">Confirm project &amp; create meeting minutes</button>
      </div>}
      {meeting.status === "imported" && <p className="text-sm text-muted">Transcript sent to Noa&apos;s existing meeting minutes workflow. Resulting tasks and decisions will appear as separate pending Inbox proposals. Meeting ID: {meeting.imported_meeting_id}</p>}
    </Card>)}
  </div>;
}
