"use client";

import { useQuery } from "@tanstack/react-query";
import { useMemo, useState } from "react";
import { Card } from "@/components/ui";
import { getGraph, getGraphPath, type GraphView } from "@/lib/api";
import { cn } from "@/lib/cn";

/*
  Graph panel (3.13): the project's neighbourhood straight from FalkorDB, drawn with a
  small force layout (no chart library). Click two nodes to see how they connect: the
  shortest path lights up.
*/

const W = 900;
const H = 560;

const style: Record<string, { r: number; fill: string; text: boolean }> = {
  Project: { r: 18, fill: "var(--color-accent)", text: true },
  Person: { r: 12, fill: "#5b8fd1", text: true },
  Decision: { r: 10, fill: "var(--color-signal)", text: true },
  Task: { r: 8, fill: "#9db7dc", text: false },
  Channel: { r: 8, fill: "#7c8aa0", text: true },
  Episode: { r: 5, fill: "#c3ccd8", text: false },
};
const fallback = { r: 6, fill: "#c3ccd8", text: false };

type Pos = Record<string, { x: number; y: number }>;

/* Deterministic: same graph, same picture. Repulsion between all nodes, springs on edges, a pull to the centre. */
function layout(view: GraphView): Pos {
  const n = view.nodes.length;
  const pos: Pos = {};
  view.nodes.forEach((node, i) => {
    const a = (i / Math.max(n, 1)) * Math.PI * 2;
    const ring = node.label === "Project" ? 0 : node.label === "Person" ? 150 : 240;
    pos[node.id] = { x: W / 2 + Math.cos(a) * ring, y: H / 2 + Math.sin(a) * ring * 0.8 };
  });
  for (let step = 0; step < 300; step++) {
    const force: Pos = Object.fromEntries(view.nodes.map((v) => [v.id, { x: 0, y: 0 }]));
    for (let i = 0; i < n; i++) {
      for (let j = i + 1; j < n; j++) {
        const a = pos[view.nodes[i].id];
        const b = pos[view.nodes[j].id];
        const dx = a.x - b.x;
        const dy = a.y - b.y;
        const d2 = Math.max(dx * dx + dy * dy, 25);
        const f = 9000 / d2;
        const d = Math.sqrt(d2);
        force[view.nodes[i].id].x += (dx / d) * f;
        force[view.nodes[i].id].y += (dy / d) * f;
        force[view.nodes[j].id].x -= (dx / d) * f;
        force[view.nodes[j].id].y -= (dy / d) * f;
      }
    }
    for (const e of view.edges) {
      const a = pos[e.from];
      const b = pos[e.to];
      if (!a || !b) continue;
      const dx = b.x - a.x;
      const dy = b.y - a.y;
      const d = Math.max(Math.sqrt(dx * dx + dy * dy), 1);
      const f = (d - 140) * 0.02;
      force[e.from].x += (dx / d) * f;
      force[e.from].y += (dy / d) * f;
      force[e.to].x -= (dx / d) * f;
      force[e.to].y -= (dy / d) * f;
    }
    const cool = 1 - step / 300;
    for (const v of view.nodes) {
      const p = pos[v.id];
      const f = force[v.id];
      f.x += (W / 2 - p.x) * 0.004;
      f.y += (H / 2 - p.y) * 0.006;
      p.x = Math.min(W - 30, Math.max(30, p.x + Math.max(-12, Math.min(12, f.x)) * cool));
      p.y = Math.min(H - 24, Math.max(24, p.y + Math.max(-12, Math.min(12, f.y)) * cool));
    }
  }
  return pos;
}

export function GraphPanel({ orgId, projectId }: { orgId: string; projectId: string }) {
  const view = useQuery({ queryKey: ["graph", orgId, projectId], queryFn: () => getGraph(orgId, projectId) });
  const [picked, setPicked] = useState<string[]>([]);
  const path = useQuery({
    queryKey: ["graph-path", orgId, picked[0], picked[1]],
    queryFn: () => getGraphPath(orgId, picked[0], picked[1]),
    enabled: picked.length === 2,
  });
  const pos = useMemo(() => (view.data ? layout(view.data) : {}), [view.data]);
  const onPath = new Set(path.data ?? []);
  const pathEdge = (a: string, b: string) => {
    const p = path.data ?? [];
    const i = p.indexOf(a);
    return i >= 0 && (p[i + 1] === b || p[i - 1] === b);
  };
  const byId = new Map((view.data?.nodes ?? []).map((n) => [n.id, n]));

  const pick = (id: string) => setPicked((p) => (p.length === 2 || p.includes(id) ? [id] : [...p, id]));

  if (view.isLoading) return <Card>Reading the graph…</Card>;
  if (!view.data?.graph) return <Card>The graph isn&rsquo;t available right now. Boards and answers still work.</Card>;

  return (
    <Card className="p-0">
      <div className="flex flex-wrap items-center gap-3 border-b border-line px-5 py-3 text-[12.5px]">
        <span className="font-semibold">FalkorDB · this project&rsquo;s graph</span>
        <span className="text-muted">
          {view.data.nodes.length} nodes · {view.data.edges.length} edges
        </span>
        <span className="ml-auto text-muted">
          {picked.length === 0 && "Click two things to see how they connect."}
          {picked.length === 1 && <>From <b className="text-ink">{byId.get(picked[0])?.name}</b>. Now click another.</>}
          {picked.length === 2 &&
            (path.isLoading
              ? "Finding the path…"
              : path.data?.length
                ? path.data.map((id) => byId.get(id)?.name ?? "…").join(" → ")
                : "Not connected within 5 steps.")}
        </span>
        {picked.length > 0 && (
          <button onClick={() => setPicked([])} className="font-medium text-accent-fg hover:underline">
            Clear
          </button>
        )}
      </div>
      <svg viewBox={`0 0 ${W} ${H}`} className="block h-auto w-full" role="img" aria-label="Project graph">
        {view.data.edges.map((e) => {
          const a = pos[e.from];
          const b = pos[e.to];
          if (!a || !b) return null;
          const hot = pathEdge(e.from, e.to);
          return (
            <line
              key={`${e.from}-${e.type}-${e.to}`}
              x1={a.x}
              y1={a.y}
              x2={b.x}
              y2={b.y}
              stroke={hot ? "var(--color-signal)" : "#c7d2e0"}
              strokeWidth={hot ? 3 : 1}
              opacity={path.data?.length && !hot ? 0.35 : 1}
            >
              <title>{e.type}</title>
            </line>
          );
        })}
        {view.data.nodes.map((n) => {
          const p = pos[n.id];
          const s = style[n.label] ?? fallback;
          const hot = onPath.has(n.id) || picked.includes(n.id);
          const dim = (path.data?.length ?? 0) > 0 && !hot;
          return (
            <g key={n.id} transform={`translate(${p.x},${p.y})`} onClick={() => pick(n.id)} className="cursor-pointer" opacity={dim ? 0.35 : 1}>
              <title>{`${n.label}: ${n.name}`}</title>
              <circle r={s.r + (hot ? 3 : 0)} fill={s.fill} stroke={hot ? "var(--color-signal)" : "white"} strokeWidth={hot ? 3 : 1.5} />
              {(s.text || hot) && (
                <text y={s.r + 13} textAnchor="middle" className={cn("fill-ink text-[11px]", n.label === "Project" && "font-semibold")}>
                  {n.name.length > 28 ? `${n.name.slice(0, 26)}…` : n.name}
                </text>
              )}
            </g>
          );
        })}
      </svg>
      <div className="flex flex-wrap gap-3 border-t border-line px-5 py-2.5 text-[11.5px] text-muted">
        {Object.entries(style).map(([label, s]) => (
          <span key={label} className="flex items-center gap-1.5">
            <span className="inline-block size-2.5 rounded-full" style={{ background: s.fill }} /> {label === "Episode" ? "Message" : label}
          </span>
        ))}
      </div>
    </Card>
  );
}
