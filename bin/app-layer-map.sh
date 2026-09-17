#!/bin/bash
# app-layer-map.sh: render the layer map of an existing app: analysis/app-layer-map.html
#
# WHAT THIS IS. A second reading surface over the same facts bin/app-report.sh reads
# (analysis/app-facts/dependencies.json, optionally inventory.json and manifest.json). It answers
# one question the dossier's dependency section states but cannot show: **if these modules were
# meant to be layered, what order would they stack in, and which edges break it?**
#
# WHY NOT A DEPENDENCY GRAPH. A few hundred edges between a few dozen nodes is a hairball, and a
# hairball is read as "complicated" and closed. A tangle of mutually reachable modules cannot be
# drawn as a shape at all: every module reaches every other, so every layout is equally wrong. So
# this page draws the ORDER, not the graph. Forward edges are implied by the order and are never
# drawn individually; only the edges that point the wrong way are drawn, and on a large app
# measured 2026-09-16 that was under a quarter of them, carrying under a tenth of the weight.
#
# WHAT THIS IS NOT. Not a gate, not a judge, and not an untangling plan. Per skills-over-scripts.md
# this file does arithmetic and layout only. The order is a heuristic (greedy feedback-arc
# ordering plus a sifting pass), not the architecture; the cut ladder is a measurement of what
# removing a module's upward edges would do, not advice to remove them. skills/layering-review.md
# holds every judgement, every threshold and the disposition rules.
#
# WHAT IT COMPUTES, all from dependencies.json and all deterministic:
#   1. strongly connected components of the own-module graph  (cross-checked against
#      counts.largest_tangle; a disagreement is printed, never silently reconciled)
#   2. a linear order that minimises the weight of backward edges
#   3. levels: the longest path in the DAG that is left once the backward edges are set aside
#   4. the backward edges themselves, with their weight and ref kinds
#   5. a cut ladder: per source module, what removing only its upward edges does to the tangle
#
# DEGRADES. No dependencies.json at all is exit 2, because there is nothing to draw. Everything
# else degrades to a printed note on the page: no inventory.json means no module sizes, no
# scope.own_modules means the module set is derived from the edges, no manifest.json means the
# page cannot say how old the facts are. A missing fact is stated on the page, never omitted.
#
# Usage:
#   bin/app-layer-map.sh [project-dir]                 # -> <project>/analysis/app-layer-map.html
#   bin/app-layer-map.sh --facts DIR -o OUT            # explicit paths
#   bin/app-layer-map.sh --facts DIR --json            # the same numbers to stdout, no HTML
#
# Exit: 0 rendered · 2 no facts directory, or dependencies.json missing or unreadable
#
# portability-ok: bash 3.2, Python 3 resolved through portable.sh

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib/portable.sh"
require_py

PROJECT=""; FACTS=""; OUT=""; JSON=0
while [ $# -gt 0 ]; do
  case "$1" in
    --facts)   FACTS="$2"; shift 2 ;;
    -o|--out)  OUT="$2"; shift 2 ;;
    --json)    JSON=1; shift ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    -*)        echo "app-layer-map: unknown option $1" >&2; exit 2 ;;
    *)         PROJECT="$1"; shift ;;
  esac
done
[ -n "$PROJECT" ] || PROJECT="."
PROJECT="$(cd "$PROJECT" 2>/dev/null && pwd)" || { echo "app-layer-map: no such directory" >&2; exit 2; }
[ -n "$FACTS" ] || FACTS="$PROJECT/analysis/app-facts"
[ -n "$OUT" ]   || OUT="$PROJECT/analysis/app-layer-map.html"

if [ ! -f "$FACTS/dependencies.json" ]; then
  echo "app-layer-map: no $FACTS/dependencies.json. Run bin/app-facts.sh in the project first" >&2
  exit 2
fi

FACTS="$FACTS" OUT="$OUT" JSON="$JSON" "$PY" - <<'PY'
import json, os, sys, html, datetime, collections

F = os.environ["FACTS"]; OUT = os.environ["OUT"]; JSON = os.environ["JSON"] == "1"

def load(name, required=False):
    p = os.path.join(F, name)
    if not os.path.exists(p):
        if required:
            print("app-layer-map: %s is missing" % p, file=sys.stderr); sys.exit(2)
        return None
    try:
        return json.load(open(p, encoding="utf-8"))
    except ValueError as e:
        if required:
            print("app-layer-map: %s is not valid JSON: %s" % (p, e), file=sys.stderr); sys.exit(2)
        return None

dep = load("dependencies.json", required=True)
inv = load("inventory.json") or {}
man = load("manifest.json") or {}

# Every fact this page wanted and did not get. Printed on the page, never swallowed.
gaps = []
if not inv:  gaps.append("inventory.json is missing or unreadable, so the module size column is blank")
if not man:  gaps.append("manifest.json is missing or unreadable, so the page cannot say when the facts were collected or which sections faulted")

# ---- the own-module graph -------------------------------------------------------------------
edges_raw = dep.get("edges") or []
if not edges_raw:
    gaps.append("dependencies.json carries no edges array: there is no graph to order")

own = list(dep.get("scope", {}).get("own_modules") or [])
if not own:
    own = sorted({e.get("from") for e in edges_raw} | {e.get("to") for e in edges_raw} - {None})
    gaps.append("scope.own_modules is absent, so the module set was derived from the edges; "
                "a module with no edge at all is missing from this page")
own = sorted(set(x for x in own if x))

E = []          # (from, to, weight, kinds)
selfloops = 0
for e in edges_raw:
    a, b = e.get("from"), e.get("to")
    if not a or not b or a not in own or b not in own:
        continue
    if a == b:
        selfloops += 1
        continue
    E.append((a, b, int(e.get("edges") or 0), e.get("kinds") or {}))

# ---- 1. strongly connected components (iterative Tarjan; deterministic order) ----------------
def sccs(nodes, edges):
    adj = collections.defaultdict(list)
    for a, b, w, k in edges:
        adj[a].append(b)
    for a in adj:
        adj[a].sort()
    idx, low, stack, onstack, out, counter = {}, {}, [], set(), [], [0]
    for root in nodes:
        if root in idx:
            continue
        work = [(root, 0)]
        while work:
            v, pi = work[-1]
            if pi == 0:
                idx[v] = low[v] = counter[0]; counter[0] += 1
                stack.append(v); onstack.add(v)
            recursed = False
            for i in range(pi, len(adj[v])):
                w = adj[v][i]
                if w not in idx:
                    work[-1] = (v, i + 1); work.append((w, 0)); recursed = True; break
                if w in onstack:
                    low[v] = min(low[v], idx[w])
            if recursed:
                continue
            work.pop()
            if low[v] == idx[v]:
                comp = []
                while True:
                    x = stack.pop(); onstack.discard(x); comp.append(x)
                    if x == v: break
                out.append(sorted(comp))
            if work:
                low[work[-1][0]] = min(low[work[-1][0]], low[v])
    return sorted(out, key=lambda c: (-len(c), c[0]))

comps = sccs(own, E)
tangles = [c for c in comps if len(c) > 1]
tangle_of = {}
for i, c in enumerate(tangles):
    for m in c:
        tangle_of[m] = i
largest = max([len(c) for c in tangles] + [0])

# Cross-check against what the instrument already claimed. A disagreement is a fact, not a bug
# to paper over: it means the graph this page ordered is not the graph the dossier described.
claimed = (dep.get("counts") or {}).get("largest_tangle")
mismatch = None
if claimed is not None and int(claimed) != largest:
    mismatch = ("dependencies.json counts.largest_tangle says %s; recomputing the components from "
                "the edges array gives %s. The two disagree, so neither number is usable until "
                "the instrument is checked." % (claimed, largest))

# ---- 2. an order with as little backward weight as possible ----------------------------------
# Greedy feedback-arc ordering (Eades, Lin and Smyth), then a sifting pass that moves one module
# at a time to its best position. Both are heuristics. They are deterministic given the same
# facts, which is what a document that gets refreshed needs; they are not an optimum, which is
# why skills/layering-review.md tells you to read the cut list, not the row numbers.
def greedy_order(nodes, edges):
    out_w = collections.defaultdict(int); in_w = collections.defaultdict(int)
    adj_o = collections.defaultdict(list); adj_i = collections.defaultdict(list)
    for a, b, w, k in edges:
        out_w[a] += w; in_w[b] += w
        adj_o[a].append((b, w)); adj_i[b].append((a, w))
    V = set(nodes); s1, s2 = [], []
    def drop(v):
        V.discard(v)
        for u, w in adj_o[v]:
            if u in V: in_w[u] -= w
        for u, w in adj_i[v]:
            if u in V: out_w[u] -= w
    while V:
        moved = True
        while moved:
            moved = False
            for v in sorted(x for x in V if out_w[x] == 0):
                if v in V: s2.insert(0, v); drop(v); moved = True
            for v in sorted(x for x in V if in_w[x] == 0 and out_w[x] > 0):
                if v in V: s1.append(v); drop(v); moved = True
        if V:
            v = max(sorted(V), key=lambda x: out_w[x] - in_w[x])
            s1.append(v); drop(v)
    return s1 + s2

def back_cost(order, edges):
    p = {m: i for i, m in enumerate(order)}
    bw = sum(w for a, b, w, k in edges if p[a] > p[b])
    bn = sum(1 for a, b, w, k in edges if p[a] > p[b])
    return (bw, bn)

order = greedy_order(own, E)
SIFT_ROUNDS = 12          # a bound, not a tuning knob: the pass converges in 3 on the probe apps
for _ in range(SIFT_ROUNDS):
    improved = False
    base_cost = back_cost(order, E)
    for m in list(order):
        i = order.index(m)
        rest = order[:i] + order[i + 1:]
        best_pos, best = i, back_cost(order, E)
        for j in range(len(rest) + 1):
            c = back_cost(rest[:j] + [m] + rest[j:], E)
            if c < best:
                best, best_pos = c, j
        if best < back_cost(order, E):
            order = rest[:best_pos] + [m] + rest[best_pos:]; improved = True
    if not improved or back_cost(order, E) == base_cost:
        break

pos = {m: i for i, m in enumerate(order)}
back = sorted([(a, b, w, k) for a, b, w, k in E if pos[a] > pos[b]], key=lambda t: (-t[2], t[0], t[1]))
fwd  = [(a, b, w, k) for a, b, w, k in E if pos[a] < pos[b]]
total_w = sum(w for a, b, w, k in E) or 1
back_w = sum(w for a, b, w, k in back)
layered_pct = round(100.0 * (total_w - back_w) / total_w, 1)

# ---- 3. levels: longest path in the DAG that is left ------------------------------------------
adj_f = collections.defaultdict(list)
for a, b, w, k in fwd:
    adj_f[a].append(b)
level = {}
for m in sorted(order, key=lambda x: -pos[x]):
    level[m] = 0 if not adj_f[m] else 1 + max(level[t] for t in adj_f[m])
max_level = max(level.values()) if level else 0
# rows top to bottom: highest level first (the consumers), then the linear order inside a level
rows = sorted(own, key=lambda m: (-level[m], pos[m]))
row_of = {m: i for i, m in enumerate(rows)}

# ---- 4. per-module coupling ------------------------------------------------------------------
out_n = collections.Counter(); in_n = collections.Counter()
out_w = collections.Counter(); in_w = collections.Counter()
for a, b, w, k in E:
    out_n[a] += 1; in_n[b] += 1; out_w[a] += w; in_w[b] += w
back_src = collections.Counter(); back_src_w = collections.Counter()
for a, b, w, k in back:
    back_src[a] += 1; back_src_w[a] += w

sizes = {}
for m in (inv.get("modules") or []):
    if m.get("kind") == "own":
        sizes[m.get("name")] = m

# ---- 5. the cut ladder -----------------------------------------------------------------------
# For each module that is the source of at least one upward edge, in descending count: what does
# the largest tangle become when ONLY that module's upward edges are set aside, and what does it
# become cumulatively. This is a measurement of the graph, not a recommendation: the skill decides
# whether the cheapest cut or the most effective one is the slice worth taking.
ladder = []
remaining = list(E)
cum_removed = []
for m, n in sorted(back_src.items(), key=lambda kv: (-kv[1], -back_src_w[kv[0]], kv[0])):
    rem = {(a, b) for a, b, w, k in back if a == m}
    alone = [e for e in E if (e[0], e[1]) not in rem]
    alone_largest = max([len(c) for c in sccs(own, alone) if len(c) > 1] + [0])
    remaining = [e for e in remaining if (e[0], e[1]) not in rem]
    cum_removed.append(m)
    cum = [c for c in sccs(own, remaining) if len(c) > 1]
    ladder.append({
        "module": m, "edges": n, "weight": back_src_w[m],
        "largest_tangle_if_only_this": alone_largest,
        "largest_tangle_cumulative": max([len(c) for c in cum] + [0]),
        "tangles_cumulative": len(cum),
    })

summary = {
    "generated": datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
    "facts_generated": man.get("generated"),
    "mpr": man.get("mpr"), "mxcli": man.get("mxcli"),
    "own_modules": len(own), "own_edges": len(E), "own_edge_weight": total_w,
    "self_loops_ignored": selfloops,
    "tangles": len(tangles), "largest_tangle": largest,
    "modules_in_tangles": sum(len(c) for c in tangles),
    "levels": max_level + 1,
    "back_edges": len(back), "back_edge_weight": back_w, "layered_weight_pct": layered_pct,
    "back_edge_sources": len(back_src),
    "cut_ladder": ladder,
    "back_edges_list": [{"from": a, "to": b, "weight": w, "kinds": k} for a, b, w, k in back],
    "order": rows,
    "levels_by_module": {m: level[m] for m in rows},
    "mismatch": mismatch,
    "gaps": gaps,
}

if JSON:
    print(json.dumps(summary, indent=2, sort_keys=True)); sys.exit(0)

# ---- SVG -------------------------------------------------------------------------------------
E_ = html.escape
ROW_H   = 20
PAD_T   = 34
CNT_R   = 54           # "3 up" counter, right-aligned here
NAME_R  = 322          # module names are right-aligned here
DOT_X   = 334          # the node
ARC_MAX = 372          # how far right an arc may bulge
BAR_X   = 742          # coupling bars start here
BAR_W   = 250
NUM_X   = BAR_X + BAR_W + 14
SVG_W   = 1240
SVG_H   = PAD_T + len(rows) * ROW_H + 18

def wclass(w):
    return "b3" if w > 20 else ("b2" if w > 5 else "b1")

svg = ['<svg viewBox="0 0 %d %d" width="100%%" role="img" aria-label="layer map" '
       'xmlns="http://www.w3.org/2000/svg" class="lm">' % (SVG_W, SVG_H)]

# level bands, so a reader sees the stack before reading a single name
band_start = 0
for i in range(len(rows) + 1):
    if i == len(rows) or level[rows[i]] != level[rows[band_start]]:
        y = PAD_T + band_start * ROW_H - 3
        h = (i - band_start) * ROW_H
        lv = level[rows[band_start]]
        if lv % 2 == 0:
            svg.append('<rect x="0" y="%d" width="%d" height="%d" class="band"/>' % (y, SVG_W, h))
        svg.append('<text x="4" y="%d" class="lvl">L%d</text>' % (y + 13, lv))
        band_start = i

# column headings
svg.append('<text x="%d" y="16" class="hd" text-anchor="end">own module, stacked by dependency level</text>' % NAME_R)
svg.append('<text x="%d" y="16" class="hd">edges that point back up the stack</text>' % (DOT_X + 14))
svg.append('<text x="%d" y="16" class="hd" text-anchor="middle">coupling weight out / in</text>' % (BAR_X + BAR_W / 2))
svg.append('<text x="%d" y="16" class="hd">refs out / in%s</text>' % (NUM_X, " · size" if sizes else ""))

# the arcs: only the edges that break the order. The bulge grows with the square root of the
# span, not linearly: a linear bulge pins every long arc against the right edge and stacks them
# on top of each other, which is the hairball this page exists to avoid.
max_span = max([abs(row_of[a] - row_of[b]) for a, b, w, k in back] + [1]) * ROW_H
for a, b, w, k in back:
    y1 = PAD_T + row_of[a] * ROW_H + 7
    y2 = PAD_T + row_of[b] * ROW_H + 7
    span = abs(y1 - y2)
    bulge = 24 + (ARC_MAX - 24) * ((span / float(max_span)) ** 0.5)
    svg.append('<path d="M%d,%d C%d,%d %d,%d %d,%d" class="arc %s"><title>%s depends back up on %s '
               '(%d refs: %s)</title></path>' % (
        DOT_X + 4, y1, DOT_X + 4 + bulge, y1, DOT_X + 4 + bulge, y2, DOT_X + 4, y2,
        wclass(w), E_(a), E_(b), w,
        E_(", ".join("%s %d" % (kk, vv) for kk, vv in sorted((k or {}).items())) or "kinds not recorded")))

maxbar = max([max(out_w[m], in_w[m]) for m in rows] + [1])
for m in rows:
    y = PAD_T + row_of[m] * ROW_H
    ty = y + 11
    cls = "tangled" if m in tangle_of else "clean"
    label = m if len(m) <= 40 else m[:38] + "…"
    svg.append('<text x="%d" y="%d" class="mod %s" text-anchor="end">%s</text>' % (NAME_R, ty, cls, E_(label)))
    svg.append('<circle cx="%d" cy="%d" r="3.4" class="dot %s"><title>%s at level %d, %s</title></circle>' % (
        DOT_X, y + 7, cls, E_(m), level[m],
        ("in the tangle of %d" % len(tangles[tangle_of[m]])) if m in tangle_of else "not in any tangle"))
    if back_src[m]:
        svg.append('<text x="%d" y="%d" class="bsrc">%d↑</text>' % (CNT_R, ty, back_src[m]))
    ow = int(BAR_W / 2 * (out_w[m] / float(maxbar)))
    iw = int(BAR_W / 2 * (in_w[m] / float(maxbar)))
    mid = BAR_X + BAR_W / 2
    svg.append('<rect x="%d" y="%d" width="%d" height="8" class="bo"/>' % (mid - ow, y + 3, ow))
    svg.append('<rect x="%d" y="%d" width="%d" height="8" class="bi"/>' % (mid, y + 3, iw))
    sz = sizes.get(m)
    extra = ("  %se %sm %sp" % (sz.get("entities_total", "?"), sz.get("microflows", "?"), sz.get("pages", "?"))) if sz else ""
    svg.append('<text x="%d" y="%d" class="num">%d / %d%s</text>' % (NUM_X, ty, out_w[m], in_w[m], E_(extra)))
svg.append("</svg>")
svg = "\n".join(svg)

# ---- page ------------------------------------------------------------------------------------
def table(headers, body):
    if not body:
        return '<p class="empty">nothing to show: zero rows. Check this is a real zero before reading it as a clean result.</p>'
    h = "".join("<th>%s</th>" % E_(str(x)) for x in headers)
    b = "".join("<tr>%s</tr>" % "".join("<td>%s</td>" % E_(str(c)) for c in r) for r in body)
    return '<div class="tw"><table><thead><tr>%s</tr></thead><tbody>%s</tbody></table></div>' % (h, b)

app_name = (inv.get("project") or {}).get("name") or man.get("mpr") or "this app"
CSS = """
:root{--bg:#fbfbfd;--fg:#16181d;--mut:#606878;--line:#e2e5ec;--card:#fff;
--ok:#1a7f52;--warn:#a2650a;--bad:#b3261e;--crit:#7a1710;--acc:#2b5bd7}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);
font:14px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif}
.wrap{max-width:1300px;margin:0 auto;padding:22px 20px 60px}
header h1{font-size:23px;margin:0 0 3px}
.sub{color:var(--mut);margin:0 0 16px;font-size:12.5px}
section{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:16px 18px;margin:0 0 16px}
h2{font-size:16px;margin:0 0 10px}
h3{font-size:13.5px;margin:18px 0 7px;text-transform:uppercase;letter-spacing:.05em;color:var(--mut)}
p{margin:0 0 9px}
.lede{font-size:14.5px}
.kpis{display:flex;flex-wrap:wrap;gap:9px;margin:12px 0 4px}
.kpi{border:1px solid var(--line);border-radius:8px;padding:8px 12px;min-width:112px;background:#fff}
.kpi b{display:block;font-size:21px;line-height:1.15}
.kpi span{color:var(--mut);font-size:11.5px}
.kpi.k-bad b{color:var(--bad)} .kpi.k-ok b{color:var(--ok)}
.note{border-radius:8px;padding:9px 12px;margin:10px 0;font-size:13px}
.note.fault{background:#fdecea;border:1px solid #f3b7b1;color:var(--crit)}
.note.warn{background:#fdf5e4;border:1px solid #efd9a4;color:var(--warn)}
.legend{color:var(--mut);font-size:12.2px;margin-top:10px}
.tw{overflow-x:auto;margin:6px 0}
table{border-collapse:collapse;width:100%;font-size:12.8px}
th,td{text-align:left;padding:5px 9px;border-bottom:1px solid var(--line);vertical-align:top}
th{color:var(--mut);font-weight:600;font-size:11.5px;text-transform:uppercase;letter-spacing:.04em}
td:nth-child(n+2){white-space:nowrap}
code{font:12px/1.4 ui-monospace,SFMono-Regular,Menlo,monospace;background:#f1f2f6;padding:1px 4px;border-radius:4px}
details{margin:8px 0}summary{cursor:pointer;color:var(--acc);font-size:13px}
.empty{color:var(--mut);font-style:italic}
svg.lm{display:block;width:100%;height:auto;background:#fff}
.lm .band{fill:#f5f6fa}
.lm .lvl{font:9.5px ui-monospace,Menlo,monospace;fill:#aeb4c2}
.lm .hd{font:10.5px -apple-system,sans-serif;fill:#8b93a3;letter-spacing:.03em}
.lm .mod{font:11.5px -apple-system,sans-serif;fill:#3b4150}
.lm .mod.tangled{fill:#7a1710;font-weight:600}
.lm .dot{fill:#b7bdc9}
.lm .dot.tangled{fill:#b3261e}
.lm .bsrc{font:9.5px ui-monospace,Menlo,monospace;fill:#b3261e;text-anchor:end}
.lm .arc{fill:none}
.lm .arc.b1{stroke:#c9ccd6;stroke-width:1}
.lm .arc.b2{stroke:#e0904a;stroke-width:1.5}
.lm .arc.b3{stroke:#b3261e;stroke-width:2.2;opacity:.85}
.lm .bo{fill:#8fa4d8} .lm .bi{fill:#cfd5e2}
.lm .num{font:9.5px ui-monospace,Menlo,monospace;fill:#8b93a3}
.key{display:flex;gap:16px;flex-wrap:wrap;color:var(--mut);font-size:12px;margin:8px 0 2px}
.key i{display:inline-block;width:20px;height:0;border-top-style:solid;vertical-align:middle;margin-right:5px}
@media(prefers-color-scheme:dark){
:root{--bg:#131519;--fg:#e8eaee;--mut:#98a0b0;--line:#2b2f38;--card:#191c21}
svg.lm{background:#191c21}
.lm .band{fill:#1f232a}.lm .mod{fill:#c6ccd8}.lm .mod.tangled{fill:#ff9b8f}
.lm .dot{fill:#4a5060}.lm .dot.tangled{fill:#e0574a}.lm .arc.b1{stroke:#3a3f4a}
.lm .bo{fill:#5570b8}.lm .bi{fill:#39404e}
.note.fault{background:#33191a;border-color:#6b2b26;color:#ffb3a8}
.note.warn{background:#2e2716;border-color:#6a5527;color:#f0cf8a}
code{background:#23262d}}
"""

p = []
p.append('<header><h1>Layer map: %s</h1><p class="sub">%s%s · facts %s · rendered %s · '
         'the judgement for this page is skills/layering-review.md</p></header>' % (
    E_(app_name), E_(man.get("mpr") or "mpr not named"),
    (" · " + E_(man.get("mxcli"))) if man.get("mxcli") else "",
    E_(man.get("generated") or "collection date unknown"), E_(summary["generated"])))

if mismatch:
    p.append('<div class="note fault"><b>The facts disagree with themselves.</b> %s</div>' % E_(mismatch))
for g in gaps:
    p.append('<div class="note warn"><b>Not collected.</b> %s</div>' % E_(g))

def plural(n, one, many):
    return "%d %s" % (n, one if n == 1 else many)

p.append('<section><h2>What this says</h2>')
p.append('<p class="lede">%s carry %s between them, %s references in all. '
         'Put in the order that breaks the fewest of them, %s of that reference weight already points one '
         'way, down the stack.%s</p>' % (
    plural(len(own), "own module", "own modules"), plural(len(E), "dependency edge", "dependency edges"),
    "{:,}".format(total_w), "%.1f%%" % layered_pct,
    (" The remaining <b>%s</b> point back up, across <b>%s from %s</b>. Those %d, not the %d, are what "
     "holds this app together the wrong way round." % (
         "{:,}".format(back_w), plural(len(back), "edge", "edges"),
         plural(len(back_src), "module", "modules"), len(back), len(E)))
    if back else " Nothing points back up: every edge in the app already runs down the stack."))
if tangles:
    p.append('<p class="lede">The components confirm it: %s sit in %s, the largest holding <b>%d</b>. '
             'Inside it every module can reach every other, so no drawing of those %d modules as a shape '
             'can be right; the order below and the cut ladder under it are the two things that can be '
             'read.</p>' % (
        plural(summary["modules_in_tangles"], "module", "modules"),
        plural(len(tangles), "strongly connected component", "strongly connected components"),
        largest, largest))
else:
    p.append('<p class="lede">No strongly connected component holds more than one module: the own-module '
             'graph is already acyclic. Every arc below is a violation of the computed order only, not of '
             'the architecture, and the cut ladder is empty by construction.</p>')
p.append('<div class="kpis">%s</div>' % "".join(
    '<div class="kpi %s"><b>%s</b><span>%s</span></div>' % (c, v, E_(k)) for k, v, c in [
        ("own modules", len(own), ""), ("levels in the stack", max_level + 1, ""),
        ("dependency edges", len(E), ""), ("edges pointing back up", len(back), "k-bad"),
        ("modules that source them", len(back_src), "k-bad"),
        ("weight already layered", "%.1f%%" % layered_pct, "k-ok"),
        ("largest tangle", largest, "k-bad" if largest > 1 else "k-ok")]))
p.append('</section>')

p.append('<section><h2>The stack, and the edges that break it</h2>')
p.append('<p>Each row is one own module. Rows are grouped into levels: a module sits one level above '
         'everything it depends on, once the backward edges are set aside. Forward edges are not drawn, '
         'because the order already says them and drawing %d lines says nothing. Every line you can see '
         'is an edge that points the wrong way, and the number in red beside a module is how many of them '
         'start there. The bars are reference weight out (left, darker) and in (right).</p>' % len(fwd))
p.append('<div class="key"><span><i style="border-top-width:1px;border-color:#c9ccd6"></i>1 to 5 refs</span>'
         '<span><i style="border-top-width:1.5px;border-color:#e0904a"></i>6 to 20</span>'
         '<span><i style="border-top-width:2.2px;border-color:#b3261e"></i>over 20</span>'
         '<span style="color:#b3261e;font-weight:600">red name = in a tangle</span></div>')
p.append(svg)
p.append('<p class="legend">The order is computed, not declared: a greedy feedback-arc ordering with a '
         'sifting pass, which minimises backward weight and is deterministic but is not proven minimal. '
         'It is a reading of the app, not its intended architecture. When the app HAS a declared layering, '
         'compare the two and the difference is the finding.</p>')
p.append('</section>')

if ladder:
    p.append('<section><h2>Cut ladder: what it would take to untangle</h2>')
    p.append('<p>One row per module that sources a backward edge, heaviest source first. '
             '<b>Tangle if only this is cut</b> sets aside that module\'s upward edges alone. '
             '<b>Cumulative</b> sets aside this row and every row above it. Reading down the table is '
             'reading an untangling backlog in the order that shrinks the tangle fastest, which is not '
             'necessarily the order that is cheapest to build: weight and ref kinds decide that, and '
             'skills/layering-review.md decides which one this project wants.</p>')
    p.append(table(["module", "upward edges", "refs", "tangle if only this is cut",
                    "cumulative largest", "cumulative tangles"],
                   [[r["module"], r["edges"], r["weight"], r["largest_tangle_if_only_this"],
                     r["largest_tangle_cumulative"], r["tangles_cumulative"]] for r in ladder]))
    p.append('<p class="legend">Cutting an edge is not free and this table does not price it. An edge whose '
             'kinds are all <code>call</code> into utility microflows is usually a move to a shared module; '
             'one carrying <code>associate</code> is a domain-model decision about which side owns the data. '
             'The kinds are in the list below.</p>')
    p.append('</section>')

p.append('<section><h2>Every backward edge</h2>')
p.append('<p>Heaviest first. This is the evidence behind the arcs and the ladder, and it is the list a '
         'change slice is written from.</p>')
p.append('<details open><summary>%s</summary>%s</details>' % (plural(len(back), "edge", "edges"), table(
    ["from (higher in the stack)", "to (lower)", "refs", "kinds", "rows apart", "both in the same tangle"],
    [[a, b, w, ", ".join("%s %d" % (kk, vv) for kk, vv in sorted((k or {}).items())) or "not recorded",
      abs(row_of[a] - row_of[b]),
      "yes" if (a in tangle_of and tangle_of.get(a) == tangle_of.get(b)) else "no"]
     for a, b, w, k in back])))
p.append('</section>')

p.append('<section><h2>Method, and what this page cannot see</h2><ul>')
for line in [
    "Source: analysis/app-facts/dependencies.json, the edges array and scope.own_modules. Nothing here "
    "re-reads the model, so this page is exactly as old as the facts and no older.",
    "Marketplace, System and framework modules are excluded, per the same scope rule the dossier uses. "
    "A marketplace module imported without metadata reads as own and will appear here as a row.",
    "%d self-referencing edge%s ignored: a module depending on itself is not a layering statement."
    % (selfloops, " was" if selfloops == 1 else "s were"),
    "The order minimises backward REFERENCE WEIGHT, then backward edge count. A different tie-break "
    "gives a different order with the same cost, so a module moving a few rows between refreshes is "
    "noise; a module changing level, or an arc appearing, is not.",
    "Levels are the longest path in the remaining acyclic graph. A module with no outbound own-module "
    "edge sits at level 0 whether it is a shared kernel or an orphan; the inbound bar tells them apart.",
    "Not visible here at all: Java actions, JavaScript actions, published REST operations called by "
    "name, workflow references and page URLs. An edge that only exists through one of those is missing "
    "from this picture, which is why a cut is confirmed in Studio Pro before it becomes a slice.",
    "Not measured by this page: security, lint, loop risk, dead elements. Those are the dossier's "
    "sections, and this page neither replaces nor scores them.",
]:
    p.append("<li>%s</li>" % E_(line))
p.append('</ul>')
p.append('<p class="legend">An agent reading this later should take the JSON, not the page: '
         '<code>bin/app-layer-map.sh --facts &lt;dir&gt; --json</code> emits the order, the levels, every '
         'backward edge with its kinds, and the cut ladder.</p>')
p.append('</section>')

doc = ("<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">"
       "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
       "<title>Layer map: %s</title><style>%s</style></head><body><div class=\"wrap\">%s</div></body></html>"
       % (E_(app_name), CSS, "\n".join(p)))

d = os.path.dirname(OUT)
if d and not os.path.isdir(d):
    os.makedirs(d)
open(OUT, "w", encoding="utf-8").write(doc)
json_out = os.path.splitext(OUT)[0] + ".json"
open(json_out, "w", encoding="utf-8").write(json.dumps(summary, indent=2, sort_keys=True))
print("app-layer-map: %s" % OUT)
print("app-layer-map: %s" % json_out)
print("  %d own modules, %d edges, %d levels; %d backward edges from %d modules carrying %d of %d refs (%.1f%% already layered); largest tangle %d"
      % (len(own), len(E), max_level + 1, len(back), len(back_src), back_w, total_w, layered_pct, largest))
PY
