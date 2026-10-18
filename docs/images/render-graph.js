// Renders NYI's production FalkorDB graph (structure only) to PNG snapshots for the README.
const fs = require("fs");
const path = require("path");
const puppeteer = require("puppeteer-core");

const data = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "graph.json"), "utf8"));
const d3src = fs.readFileSync(path.join(__dirname, "node_modules/d3/dist/d3.min.js"), "utf8");
const out = process.argv[2];

const page = (mode) => `<!doctype html><html><head><meta charset="utf-8">
<style>
  body { margin: 0; background: #fff; font-family: -apple-system, "Inter", "Helvetica Neue", Arial, sans-serif; }
  .title { position: absolute; left: 40px; top: 30px; }
  .title h1 { margin: 0; font-size: 26px; color: #0b1f3a; letter-spacing: -0.02em; }
  .title p { margin: 6px 0 0; font-size: 14px; color: #5b6b82; }
  .legend { position: absolute; left: 40px; bottom: 30px; display: flex; flex-wrap: wrap; gap: 8px 18px; max-width: 1500px; font-size: 13px; color: #33445c; }
  .legend span { display: inline-flex; align-items: center; gap: 6px; }
  .legend i { width: 11px; height: 11px; border-radius: 50%; display: inline-block; }
</style></head><body>
<div class="title" id="title"></div>
<svg id="g" width="1600" height="1000"></svg>
<div class="legend" id="legend"></div>
<script>${d3src}</script>
<script>
const MODE = ${JSON.stringify(mode)};
const raw = ${JSON.stringify(data)};
const style = {
  Person:       { c: "#0b3d91", r: 13, label: true },
  Project:      { c: "#1f6feb", r: 17, label: true },
  Channel:      { c: "#5aa9ff", r: 8,  label: true },
  Task:         { c: "#22a06b", r: 5 },
  Decision:     { c: "#e8a317", r: 7 },
  ChangeRecord: { c: "#9b6bd6", r: 3.5 },
  Episode:      { c: "#b8c9e2", r: 2.6 },
  Commit:       { c: "#7d8ba1", r: 2.6 },
  PullRequest:  { c: "#4a5a72", r: 3.2 },
  Identity:     { c: "#d0d7e2", r: 2.4 },
};
const keep = MODE === "core"
  ? new Set(["Person", "Project", "Task", "Decision", "Channel"])
  : new Set(Object.keys(style));
const relKeep = MODE === "core"
  ? new Set(["WORKS_ON", "LEADS", "KNOWS_ABOUT", "ASSIGNED_TO", "BELONGS_TO", "DECIDED", "AFFECTS", "MAPS_TO"])
  : null;
let nodes = raw.nodes.filter(n => keep.has(n.l)).map(n => ({ id: n.i, l: n.l, name: n.name }));
const ids = new Set(nodes.map(n => n.id));
let links = raw.edges.filter(e => ids.has(e.s) && ids.has(e.t) && (!relKeep || relKeep.has(e.r)))
  .map(e => ({ source: e.s, target: e.t, r: e.r }));
{
  const used = new Set(); links.forEach(l => { used.add(l.source); used.add(l.target); });
  nodes = nodes.filter(n => used.has(n.id));
}
const W = 1600, H = 1000, cx = W / 2 + 60, cy = H / 2 + 10;
const sim = d3.forceSimulation(nodes)
  .force("link", d3.forceLink(links).id(d => d.id)
    .distance(l => l.r === "KNOWS_ABOUT" ? 150 : (["WORKS_ON","LEADS"].includes(l.r) ? 120 : (MODE === "core" ? 40 : 22)))
    .strength(l => ["IN","BELONGS_TO"].includes(l.r) ? 0.6 : 0.35))
  .force("charge", d3.forceManyBody().strength(d => d.l === "Project" ? -900 : d.l === "Person" ? -600 : (MODE === "core" ? -60 : -14)))
  .force("collide", d3.forceCollide(d => style[d.l].r + 1.2))
  .force("x", d3.forceX(cx).strength(0.045))
  .force("y", d3.forceY(cy).strength(0.07))
  .stop();
for (let i = 0; i < 900; i++) sim.tick();
// fit into the frame below the title and above the legend
const xs = d3.extent(nodes, d => d.x), ys = d3.extent(nodes, d => d.y);
const box = { x0: 60, x1: W - 60, y0: 120, y1: H - 80 };
const k = Math.min((box.x1 - box.x0) / (xs[1] - xs[0] || 1), (box.y1 - box.y0) / (ys[1] - ys[0] || 1));
nodes.forEach(d => { d.x = box.x0 + (d.x - xs[0]) * k + ((box.x1 - box.x0) - (xs[1] - xs[0]) * k) / 2;
                     d.y = box.y0 + (d.y - ys[0]) * k + ((box.y1 - box.y0) - (ys[1] - ys[0]) * k) / 2; });
const svg = d3.select("#g");
const edgeColor = r => r === "KNOWS_ABOUT" ? "#1f6feb" : (["WORKS_ON","LEADS"].includes(r) ? "#0b3d91" : "#c5d3e6");
svg.append("g").selectAll("line").data(links).join("line")
  .attr("x1", d => d.source.x).attr("y1", d => d.source.y).attr("x2", d => d.target.x).attr("y2", d => d.target.y)
  .attr("stroke", d => edgeColor(d.r))
  .attr("stroke-width", d => d.r === "KNOWS_ABOUT" ? 2.2 : (["WORKS_ON","LEADS"].includes(d.r) ? 1.4 : 0.6))
  .attr("stroke-dasharray", d => d.r === "KNOWS_ABOUT" ? "5 4" : null)
  .attr("stroke-opacity", d => ["KNOWS_ABOUT","WORKS_ON","LEADS"].includes(d.r) ? 0.75 : 0.55);
const order = ["Identity","Episode","Commit","PullRequest","ChangeRecord","Task","Decision","Channel","Person","Project"];
nodes.sort((a, b) => order.indexOf(a.l) - order.indexOf(b.l));
svg.append("g").selectAll("circle").data(nodes).join("circle")
  .attr("cx", d => d.x).attr("cy", d => d.y).attr("r", d => style[d.l].r)
  .attr("fill", d => style[d.l].c).attr("stroke", "#fff").attr("stroke-width", d => style[d.l].label ? 2 : 0.6);
const lab = nodes.filter(d => style[d.l].label && d.name);
svg.append("g").selectAll("text").data(lab).join("text")
  .attr("x", d => d.x).attr("y", d => d.y - style[d.l].r - 6).attr("text-anchor", "middle")
  .attr("font-size", d => d.l === "Channel" ? 12 : 15).attr("font-weight", d => d.l === "Channel" ? 500 : 650)
  .attr("fill", "#0b1f3a").attr("paint-order", "stroke").attr("stroke", "#fff").attr("stroke-width", 4)
  .text(d => d.name);
const counts = {}; nodes.forEach(n => counts[n.l] = (counts[n.l] || 0) + 1);
document.getElementById("title").innerHTML = MODE === "core"
  ? "<h1>Who owns and knows what</h1><p>People, projects, tasks and decisions from NYI's live FalkorDB graph. Dashed blue: derived KNOWS_ABOUT weight.</p>"
  : "<h1>NotYourIdea's company graph in FalkorDB</h1><p>" + nodes.length + " nodes and " + links.length + " relationships, exported from production on Oct 19, 2026 (unlinked chat identities omitted). Message text is not shown.</p>";
document.getElementById("legend").innerHTML = order.slice().reverse().filter(l => counts[l])
  .map(l => '<span><i style="background:' + style[l].c + '"></i>' + l + " " + counts[l] + "</span>").join("") +
  '<span><i style="background:none;border-top:2px dashed #1f6feb;border-radius:0;height:0;width:18px"></i>KNOWS_ABOUT</span>';
</script></body></html>`;

(async () => {
  const browser = await puppeteer.launch({ executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", headless: true });
  for (const mode of ["full", "core"]) {
    const p = await browser.newPage();
    await p.setViewport({ width: 1600, height: 1000, deviceScaleFactor: 2 });
    await p.setContent(page(mode), { waitUntil: "load" });
    await p.screenshot({ path: path.join(out, `graph-${mode}.png`) });
  }
  await browser.close();
})();
