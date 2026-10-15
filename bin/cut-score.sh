#!/bin/bash
# cut-score.sh: score a proposed decomposition of an existing app into several apps:
#              analysis/cut-score.html + analysis/cut-score.json
#
# WHAT THIS IS. The Stage 3 instrument for scoring a decomposition (the decompose-and-rehost plan;
# split out of #293 and landing separately — skills/layering-review.md judges the result). Given a
# CUT — a partition of the own modules into would-be apps — it lists every module-level edge that
# would cross an app boundary, names the integration LANE each ref kind would have to become
# (an OData external entity, a published OData action or REST call, or nothing at all because the
# platform has no lane for it), and sums that per partition into a verdict: clean / costly /
# blocked. Business Events is not a lane here: the project this was written for holds no Event
# Broker licence, so a crossing can only become OData or REST, or it blocks.
#
# WHAT IT READS. analysis/app-facts/dependencies.json, written by project-bin/app-facts.sh (the
# mandatory Stage 0 facts step) — the edges array with its per-ref-kind counts, and
# scope.own_modules. Optionally .mxcli/catalog.db, which app-facts.sh leaves behind (graph-report
# builds it in full mode): that is the only place an AGGREGATE over a foreign entity can be seen,
# because dependencies.json records that a microflow retrieves Billing.Invoice but not what it
# then does with the list. With no catalog the aggregate column reads NOT DETECTED and says why;
# it is never silently blank. The default cut (one app per layer-map level) reads
# analysis/app-layer-map.json, written by bin/app-layer-map.sh; without it, --cut is required.
#
# WHAT THIS IS NOT. Not a judge. The lane table below is platform fact (an external entity cannot
# own an association, cannot be aggregated server-side, cannot be the subject of a workflow; a
# synchronous call across apps is a published action or a REST operation and the transaction no
# longer spans), and the verdict is arithmetic over that table. Whether a costly partition is
# worth it is skills/layering-review.md and the Stage 3 interview, not this file.
#
# WHAT IT CANNOT SEE, and prints on the page: Java and JavaScript actions, published REST called
# by name, workflow references, page URLs (same blind spots as app-layer-map.sh); an aggregate
# over a list that came back from a cross-partition CALL (the catalog has no variable linkage, so
# the aggregate is attributed to the retrieve in the same microflow, never to the call); the
# volume of data an OData hop would move at runtime.
#
# Usage:
#   bin/cut-score.sh [project-dir] --cut "Core,Util|Orders|Billing|Reporting"
#   bin/cut-score.sh [project-dir]                      # default cut: one app per layer-map level
#   bin/cut-score.sh --facts DIR --catalog DB --cut ... -o OUT
#   bin/cut-score.sh ... --json                         # the same numbers to stdout, no HTML
#
# A module in scope.own_modules that --cut does not name lands in a partition called "_unassigned"
# and is reported as a gap; a name in --cut that is not an own module is reported as a gap too.
# Neither is ever inferred into a neighbouring partition.
#
# Exit: 0 rendered · 2 no dependencies.json, no cut (no --cut and no app-layer-map.json), or
#       malformed --cut
#
# Field run: lab checkout lab/decompose (CutFixture, Mendix 10.24.0, mxcli v0.26.0, 2026-10-12) —
# 7 own edges, 6 crossing on the four-way cut; found the Orders<->Billing call tangle as the
# blocker and the Reporting->Billing retrieve+aggregate from the catalog.
# Field run: public field-service template app (Mendix Marketplace, 9.24.2, MPR v1; mxcli v0.26.0,
# 2026-10-12) — 42 own modules, 312 own edges, 4,508 refs; app-facts 25 s, each cut-score run <= 1 s.
# Seven cuts scored, all `blocked`: one-app-per-level 312/4,508 crossing (meaningless on its
# 36-module tangle); best web | mobile landscape found 132 edges / 1,442 refs, 2 bidirectional pairs.
# Six blocker rows spot-checked with `describe`: all six real references, two of them mis-laned.
# Known from that run, not fixed here: `call` mixes client-side nanoflow/JavaScript calls (lane: copy)
# with server-side ones (~30 % of the main seam's blocker mass); the catalog kinds sync, widget,
# schedule, event and publish never reach dependencies.json (a synced foreign entity is a blocker this
# cannot see); nanoflows aggregating the device store are false aggregate hits. The run also caused
# the per-partition blocker cap (one cell was 10 KB) and app-facts' sqlite3-CLI fallback.
#
# portability-ok: bash 3.2, Python 3 resolved through portable.sh

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib/portable.sh"
require_py

PROJECT=""; FACTS=""; OUT=""; JSON=0; CUT=""; CATALOG=""; LAYERMAP=""
while [ $# -gt 0 ]; do
  case "$1" in
    --facts)    FACTS="$2"; shift 2 ;;
    --catalog)  CATALOG="$2"; shift 2 ;;
    --layer-map) LAYERMAP="$2"; shift 2 ;;
    --cut)      CUT="$2"; shift 2 ;;
    -o|--out)   OUT="$2"; shift 2 ;;
    --json)     JSON=1; shift ;;
    -h|--help)  sed -n '2,50p' "$0"; exit 0 ;;
    -*)         echo "cut-score: unknown option $1" >&2; exit 2 ;;
    *)          PROJECT="$1"; shift ;;
  esac
done
[ -n "$PROJECT" ] || PROJECT="."
PROJECT="$(cd "$PROJECT" 2>/dev/null && pwd)" || { echo "cut-score: no such directory" >&2; exit 2; }
[ -n "$FACTS" ]    || FACTS="$PROJECT/analysis/app-facts"
[ -n "$OUT" ]      || OUT="$PROJECT/analysis/cut-score.html"
[ -n "$LAYERMAP" ] || LAYERMAP="$PROJECT/analysis/app-layer-map.json"
if [ -z "$CATALOG" ]; then
  # The catalog sits beside the .mpr: single-tree (project root) or two-tree (app/).
  for c in "$PROJECT/.mxcli/catalog.db" "$PROJECT/app/.mxcli/catalog.db"; do
    [ -f "$c" ] && { CATALOG="$c"; break; }
  done
  [ -n "$CATALOG" ] || CATALOG="$PROJECT/.mxcli/catalog.db"
fi

if [ ! -f "$FACTS/dependencies.json" ]; then
  echo "cut-score: no $FACTS/dependencies.json. Run project-bin/app-facts.sh in the project first" >&2
  exit 2
fi
if [ -z "$CUT" ] && [ ! -f "$LAYERMAP" ]; then
  echo "cut-score: no --cut given and no $LAYERMAP to take the default cut from." >&2
  echo "           Run bin/app-layer-map.sh first (one app per level) or pass --cut \"A,B|C|D\"." >&2
  exit 2
fi

FACTS="$FACTS" OUT="$OUT" JSON="$JSON" CUT="$CUT" CATALOG="$CATALOG" LAYERMAP="$LAYERMAP" \
  "$PY" - <<'PY'
import json, os, sys, html, datetime, collections, sqlite3

F = os.environ["FACTS"]; OUT = os.environ["OUT"]; JSON = os.environ["JSON"] == "1"
CUT = os.environ["CUT"]; CATALOG = os.environ["CATALOG"]; LAYERMAP = os.environ["LAYERMAP"]

def load(path, required=False):
    if not os.path.exists(path):
        if required:
            print("cut-score: %s is missing" % path, file=sys.stderr); sys.exit(2)
        return None
    try:
        return json.load(open(path, encoding="utf-8"))
    except ValueError as e:
        if required:
            print("cut-score: %s is not valid JSON: %s" % (path, e), file=sys.stderr); sys.exit(2)
        return None

dep = load(os.path.join(F, "dependencies.json"), required=True)
man = load(os.path.join(F, "manifest.json")) or {}

gaps = []   # every fact this page wanted and did not get; printed, never swallowed
if not man:
    gaps.append("manifest.json is missing or unreadable, so the page cannot say when the facts were collected")

edges_raw = dep.get("edges") or []
if not edges_raw:
    gaps.append("dependencies.json carries no edges array: nothing can cross a boundary that nothing crosses")
own = sorted(set(x for x in (dep.get("scope", {}).get("own_modules") or []) if x))
if not own:
    own = sorted(({e.get("from") for e in edges_raw} | {e.get("to") for e in edges_raw}) - {None})
    gaps.append("scope.own_modules is absent, so the module set was derived from the edges; "
                "a module with no edge at all is missing from this page")

# ---- the cut ----------------------------------------------------------------------------------
partitions = collections.OrderedDict()   # name -> [modules]
cut_source = ""
if CUT.strip():
    cut_source = "--cut"
    for i, part in enumerate(CUT.split("|")):
        mods = [m.strip() for m in part.split(",") if m.strip()]
        if not mods:
            print("cut-score: --cut has an empty partition at position %d" % (i + 1), file=sys.stderr); sys.exit(2)
        name = "+".join(mods) if len(mods) <= 2 else "%s+%d more" % (mods[0], len(mods) - 1)
        if name in partitions:
            name = "%s#%d" % (name, i + 1)
        partitions[name] = mods
else:
    lm = load(LAYERMAP, required=True)
    levels = lm.get("levels_by_module") or {}
    if not levels:
        print("cut-score: %s has no levels_by_module" % LAYERMAP, file=sys.stderr); sys.exit(2)
    cut_source = "default: one app per level of %s" % LAYERMAP
    by_level = collections.defaultdict(list)
    for m, lv in levels.items():
        by_level[int(lv)].append(m)
    for lv in sorted(by_level):
        partitions["L%d" % lv] = sorted(by_level[lv])

part_of = {}
for name, mods in partitions.items():
    for m in mods:
        if m in part_of:
            gaps.append("module %s is named in two partitions (%s and %s); the first wins" % (m, part_of[m], name))
            continue
        part_of[m] = name
unknown = sorted(m for m in part_of if m not in own)
if unknown:
    gaps.append("named in the cut but not an own module of this app (typo, marketplace, or dropped): %s"
                % ", ".join(unknown))
unassigned = sorted(m for m in own if m not in part_of)
if unassigned:
    partitions["_unassigned"] = unassigned
    for m in unassigned:
        part_of[m] = "_unassigned"
    gaps.append("own modules the cut does not place: %s — scored as a partition of their own named "
                "_unassigned; decide where they go, nothing here guesses" % ", ".join(unassigned))

# ---- lane table (platform fact) ---------------------------------------------------------------
# kind -> (lane, cost, class, why)
LANES = {
    "associate":  ("odata-external-entity", "medium", "acceptable",
                   "the referenced entity becomes an external entity in the referencing app; the local "
                   "side keeps the association (an external entity cannot own one); the data stays with the owner"),
    "retrieve":   ("odata-external-entity", "medium", "acceptable",
                   "a database retrieve becomes an OData read; XPath is limited to what the service exposes"),
    "datasource": ("odata-external-entity", "medium", "acceptable",
                   "a page datasource over a foreign entity reads an external entity; no client-side XPath beyond the service"),
    "xpath":      ("odata-external-entity", "medium", "acceptable",
                   "an XPath constraint over a foreign attribute must be expressible as an OData filter"),
    "member":     ("odata-external-entity", "low", "acceptable",
                   "attribute access on a foreign entity rides on the external entity; exposed attributes only"),
    "parameter":  ("odata-external-entity", "low", "acceptable",
                   "a parameter typed on a foreign entity retypes to the external entity"),
    "return":     ("odata-external-entity", "low", "acceptable",
                   "a return typed on a foreign entity retypes to the external entity"),
    "type":       ("odata-external-entity", "low", "acceptable",
                   "a type reference to a foreign entity retypes to the external entity"),
    "create":     ("odata-external-entity (write)", "high", "costly",
                   "creating a foreign object needs a writable external entity (OData v4) or an action in the owning app"),
    "change":     ("odata-external-entity (write)", "high", "costly",
                   "changing a foreign object needs a writable external entity or an action in the owning app"),
    "commit":     ("odata-external-entity (write)", "high", "costly",
                   "committing a foreign object needs a writable external entity; the transaction no longer spans both apps"),
    "delete":     ("odata-external-entity (write)", "high", "costly",
                   "deleting a foreign object needs a writable external entity or an action in the owning app"),
    "call":       ("odata-action-or-rest", "high", "costly",
                   "an in-process microflow call becomes a published OData action or a REST operation; "
                   "synchronous, no shared transaction, error handling changes"),
    "action":     ("odata-action-or-rest", "high", "costly",
                   "a widget action on a foreign microflow becomes a published action or REST call"),
    "show_page":  ("deep-link", "high", "costly",
                   "a page in another app cannot be shown in-process; the navigation becomes a URL"),
    "home_page":  ("deep-link", "high", "costly", "a home page in another app becomes a URL"),
    "menu_item":  ("deep-link", "high", "costly", "a menu item into another app becomes a URL"),
    "layout":     ("copy", "low", "acceptable", "a layout cannot be shared across apps; copy it or take Atlas"),
    "mapping":    ("copy", "low", "acceptable", "an import/export mapping cannot be shared; copy it"),
    "value":      ("copy", "low", "acceptable", "a constant/enum value reference; copy the document"),
    "generalize": ("none", "blocker", "blocker",
                   "inheritance cannot cross an app boundary: an external entity has no specializations"),
    "workflow":   ("none", "blocker", "blocker", "a workflow cannot reference documents in another app"),
    "user_task":  ("none", "blocker", "blocker", "a user task cannot target a page or microflow in another app"),
    "security_role": ("none", "blocker", "blocker", "a module role cannot be granted by another app's user roles"),
    "role":       ("none", "blocker", "blocker", "a role reference cannot cross an app boundary"),
}
UNKNOWN = ("unclassified", "unknown", "unclassified",
           "this ref kind is not in the lane table; it is counted in the denominator and must be read by hand")
COST_RANK = {"low": 1, "medium": 2, "high": 3, "blocker": 4, "unknown": 3}

# ---- crossing edges ---------------------------------------------------------------------------
rows = []
total_edges = 0; total_weight = 0
calls_between = collections.defaultdict(int)    # (P,Q) -> call weight
for e in edges_raw:
    a, b = e.get("from"), e.get("to")
    if not a or not b or a == b:
        continue
    kinds = e.get("kinds") or {}
    w_edge = int(e.get("edges") or sum(kinds.values()) or 0)
    total_edges += 1; total_weight += w_edge
    pa, pb = part_of.get(a), part_of.get(b)
    if pa is None or pb is None:
        gaps.append("edge %s -> %s has an endpoint outside the own-module set; skipped" % (a, b))
        continue
    if pa == pb:
        continue
    if not kinds:
        kinds = {"(kinds not recorded)": w_edge}
    for kind, n in sorted(kinds.items()):
        lane, cost, cls, why = LANES.get(kind, UNKNOWN)
        if kind not in LANES:
            gaps.append("ref kind %r on %s -> %s is not in the lane table" % (kind, a, b))
        rows.append({"from": a, "to": b, "from_partition": pa, "to_partition": pb, "kind": kind,
                     "weight": int(n), "lane": lane, "cost": cost, "class": cls, "why": why,
                     "aggregate": "NOT DETECTED"})
        if kind in ("call", "action"):
            calls_between[(pa, pb)] += int(n)

crossing_edges = len({(r["from"], r["to"]) for r in rows})
crossing_weight = sum(r["weight"] for r in rows)

# ---- bidirectional call pairs at partition level: the blocker ---------------------------------
bidir = []
seen = set()
for (pa, pb), w in sorted(calls_between.items()):
    if (pb, pa) in calls_between and (pb, pa) not in seen:
        seen.add((pa, pb))
        bidir.append({"a": pa, "b": pb, "a_to_b_calls": w, "b_to_a_calls": calls_between[(pb, pa)],
                      "edges": sorted({"%s -> %s" % (r["from"], r["to"]) for r in rows
                                       if r["kind"] in ("call", "action")
                                       and {r["from_partition"], r["to_partition"]} == {pa, pb}})})
bidir_pairs = {frozenset((x["a"], x["b"])) for x in bidir}
for r in rows:
    if r["kind"] in ("call", "action") and frozenset((r["from_partition"], r["to_partition"])) in bidir_pairs:
        r["lane"] = "none"; r["cost"] = "blocker"; r["class"] = "blocker"
        r["why"] = ("part of a bidirectional call pair between %s and %s: each side would publish an action the "
                    "other consumes, and neither can deploy first" % (r["from_partition"], r["to_partition"]))

# ---- aggregate detection from the catalog -----------------------------------------------------
aggregate = {"status": "NOT DETECTED", "reason": "", "catalog": CATALOG, "hits": []}
if not os.path.exists(CATALOG):
    aggregate["short"] = 'no catalog'
    aggregate["reason"] = ("no catalog at %s; app-facts.sh leaves one beside the .mpr after graph-report, "
                           "pass --catalog to point at it" % CATALOG)
else:
    try:
        db = sqlite3.connect("file:%s?mode=ro" % CATALOG, uri=True)
        names = {r[0] for r in db.execute("select name from sqlite_master where type='table'")}
        if "activities_data" not in names:
            aggregate["short"] = 'catalog has no activities_data table'
            aggregate["reason"] = "catalog has no activities_data table; this mxcli wrote a catalog this script cannot read"
        else:
            cols = {r[1] for r in db.execute("pragma table_info(activities_data)")}
            need = {"MicroflowQualifiedName", "ModuleName", "ActionType", "EntityRef"}
            if not need <= cols:
                aggregate["short"] = 'catalog activities_data lacks columns'
                aggregate["reason"] = "activities_data lacks columns %s" % ", ".join(sorted(need - cols))
            else:
                # The build_mode LABEL is recorded, never tested (master #259): mxcli v0.24+ labels a
                # complete catalog 'source', so `!= full` would read every current catalog as untrustworthy.
                # What this needs is checked instead: activities_data has rows.
                mode = db.execute("select Value from catalog_meta where Key='build_mode'").fetchone() \
                    if "catalog_meta" in names else None
                aggregate["build_mode"] = mode[0] if mode else None
                n_acts = db.execute("select count(*) from activities_data").fetchone()[0]
                if n_acts == 0:
                    aggregate["short"] = 'catalog activities_data is empty'
                    aggregate["reason"] = ("catalog activities_data is empty (build_mode %r); an empty table is not a "
                                           "clean app. Rerun app-facts.sh" % (mode[0] if mode else None))
                else:
                    per_mf = collections.defaultdict(lambda: {"module": None, "aggregates": 0, "retrieves": []})
                    for mf, mod, at, ent in db.execute(
                            "select MicroflowQualifiedName, ModuleName, ActionType, EntityRef from activities_data "
                            "where ActionType in ('AggregateListAction','RetrieveAction')"):
                        d = per_mf[mf]; d["module"] = mod
                        if at == "AggregateListAction":
                            d["aggregates"] += 1
                        elif ent:
                            d["retrieves"].append(ent)
                    hits = []
                    for mf, d in sorted(per_mf.items()):
                        if d["aggregates"] == 0 or not d["retrieves"]:
                            continue
                        pa = part_of.get(d["module"])
                        for ent in sorted(set(d["retrieves"])):
                            emod = ent.split(".")[0]
                            pb = part_of.get(emod)
                            if pa and pb and pa != pb:
                                hits.append({"microflow": mf, "from": d["module"], "to": emod, "entity": ent,
                                             "aggregates": d["aggregates"], "from_partition": pa, "to_partition": pb})
                    aggregate["hits"] = hits
                    aggregate["status"] = "DETECTED" if hits else "none found"
                    aggregate["reason"] = ("basis: a microflow with a RetrieveAction on a foreign entity and an "
                                           "AggregateListAction in the same microflow; the catalog stores no "
                                           "variable linkage, so an aggregate over a list returned by a foreign CALL "
                                           "is invisible here")
                    for h in hits:
                        for r in rows:
                            if r["from"] == h["from"] and r["to"] == h["to"] and r["kind"] == "retrieve":
                                r["aggregate"] = "yes (%s, %d aggregate%s)" % (h["microflow"], h["aggregates"],
                                                                                "" if h["aggregates"] == 1 else "s")
                                r["cost"] = "high"; r["class"] = "costly"
                                r["why"] = ("the retrieved list is aggregated in %s: over an external entity that pulls "
                                            "the whole set across the wire or moves the aggregation into the owning app"
                                            % h["microflow"])
        db.close()
    except sqlite3.Error as e:
        aggregate["short"] = 'catalog unreadable'
        aggregate["reason"] = "catalog could not be read: %s" % e
if aggregate["status"] == "NOT DETECTED":
    gaps.append("aggregate detection: NOT DETECTED — %s" % aggregate["reason"])
for r in rows:
    if r["aggregate"] == "NOT DETECTED":
        if aggregate["status"] == "NOT DETECTED":
            r["aggregate"] = "NOT DETECTED (%s)" % aggregate.get("short", "see gaps")
        elif r["kind"] in ("retrieve", "datasource"):
            r["aggregate"] = "no" if r["kind"] == "retrieve" else "n/a (page)"
        else:
            r["aggregate"] = "n/a"

# ---- per partition ----------------------------------------------------------------------------
parts = collections.OrderedDict()
for name, mods in partitions.items():
    out_rows = [r for r in rows if r["from_partition"] == name]
    in_rows = [r for r in rows if r["to_partition"] == name]
    blockers = [r for r in out_rows + in_rows if r["class"] == "blocker"]
    costly = [r for r in out_rows if r["class"] in ("costly", "unclassified")]
    acceptable = [r for r in out_rows if r["class"] == "acceptable"]
    # blocked: a blocker touches this partition in either direction (a tangle has no side).
    # costly: something going OUT needs a published action, REST, a write, a deep link, or carries
    #         an aggregate. clean: nothing goes out, or only external-entity reads/types/copies do.
    if blockers:
        verdict = "blocked"
    elif costly:
        verdict = "costly"
    else:
        verdict = "clean"
    parts[name] = {
        "modules": mods,
        "out_edges": len({(r["from"], r["to"]) for r in out_rows}), "out_weight": sum(r["weight"] for r in out_rows),
        "in_edges": len({(r["from"], r["to"]) for r in in_rows}), "in_weight": sum(r["weight"] for r in in_rows),
        "lanes": dict(collections.Counter(r["lane"] for r in out_rows)),
        "blockers": sorted({"%s -> %s (%s): %s" % (r["from"], r["to"], r["kind"], r["why"]) for r in blockers}),
        "costly": sorted({"%s -> %s (%s)" % (r["from"], r["to"], r["kind"]) for r in costly}),
        "acceptable": sorted({"%s -> %s (%s)" % (r["from"], r["to"], r["kind"]) for r in acceptable}),
        "aggregates_out": [h for h in aggregate["hits"] if h["from_partition"] == name],
        "verdict": verdict,
    }

overall = "blocked" if any(p["verdict"] == "blocked" for p in parts.values()) else \
          "costly" if any(p["verdict"] == "costly" for p in parts.values()) else "clean"

summary = {
    "generated": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "facts": F, "catalog": CATALOG, "cut_source": cut_source,
    "cut": [{"name": n, "modules": m} for n, m in partitions.items()],
    "own_modules": len(own), "own_edges": total_edges, "own_edge_weight": total_weight,
    "crossing_edges": crossing_edges, "crossing_weight": crossing_weight, "crossing_rows": len(rows),
    "denominator": "%d of %d own edges cross a partition boundary, carrying %d of %d refs" % (
        crossing_edges, total_edges, crossing_weight, total_weight),
    "rows": rows, "bidirectional_partition_pairs": bidir, "aggregate": aggregate,
    "partitions": parts, "verdict": overall, "gaps": gaps,
    "lanes_excluded": ["business-events (no Event Broker licence)"],
}

if JSON:
    print(json.dumps(summary, indent=2, sort_keys=True)); sys.exit(0)

# ---- HTML -------------------------------------------------------------------------------------
E_ = html.escape
app_name = man.get("mpr") or os.path.basename(os.path.dirname(os.path.dirname(F))) or "app"

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
.kpi{border:1px solid var(--line);border-radius:8px;padding:8px 12px;min-width:112px;background:var(--card)}
.kpi b{display:block;font-size:21px;line-height:1.15}
.kpi span{color:var(--mut);font-size:11.5px}
.kpi.k-bad b{color:var(--bad)} .kpi.k-ok b{color:var(--ok)} .kpi.k-warn b{color:var(--warn)}
.note{border-radius:8px;padding:9px 12px;margin:10px 0;font-size:13px}
.note.fault{background:#fdecea;border:1px solid #f3b7b1;color:var(--crit)}
.note.warn{background:#fdf5e4;border:1px solid #efd9a4;color:var(--warn)}
.legend{color:var(--mut);font-size:12.2px;margin-top:10px}
.tw{overflow-x:auto;margin:6px 0}
table{border-collapse:collapse;width:100%;font-size:12.8px}
th,td{text-align:left;padding:5px 9px;border-bottom:1px solid var(--line);vertical-align:top}
th{color:var(--mut);font-weight:600;font-size:11.5px;text-transform:uppercase;letter-spacing:.04em}
td.why{white-space:normal;color:var(--mut);font-size:12px}
code{font:12px/1.4 ui-monospace,SFMono-Regular,Menlo,monospace;background:#f1f2f6;padding:1px 4px;border-radius:4px}
.v{display:inline-block;padding:1px 8px;border-radius:10px;font-size:11.5px;font-weight:600;color:#fff}
.v.clean{background:var(--ok)} .v.costly{background:var(--warn)} .v.blocked{background:var(--bad)}
.c-blocker{color:var(--bad);font-weight:600} .c-costly{color:var(--warn);font-weight:600} .c-acceptable{color:var(--ok)} .c-unclassified{color:var(--bad)}
.empty{color:var(--mut);font-style:italic}
@media(prefers-color-scheme:dark){
:root{--bg:#131519;--fg:#e8eaee;--mut:#98a0b0;--line:#2b2f38;--card:#191c21}
.note.fault{background:#33191a;border-color:#6b2b26;color:#ffb3a8}
.note.warn{background:#2e2716;border-color:#6a5527;color:#f0cf8a}
code{background:#23262d}}
"""

def table(headers, body_rows, cls=None):
    if not body_rows:
        return '<p class="empty">none</p>'
    out = ['<div class="tw"><table><thead><tr>%s</tr></thead><tbody>' % "".join("<th>%s</th>" % E_(h) for h in headers)]
    for r in body_rows:
        cells = []
        for i, c in enumerate(r):
            if isinstance(c, tuple):
                cells.append('<td class="%s">%s</td>' % (c[1], c[0]))
            else:
                cells.append("<td%s>%s</td>" % (' class="why"' if cls and cls[i] == "why" else "", E_(str(c))))
        out.append("<tr>%s</tr>" % "".join(cells))
    out.append("</tbody></table></div>")
    return "".join(out)

def vbadge(v):
    return '<span class="v %s">%s</span>' % (v, v)

# The per-partition cell names each blocking edge once, without its "why": that sentence is on the
# edge's own row below. On a real monolith (FSM 9.24.2, 2026-10-12: 80 blocking rows on one cut) the
# full text made one cell of 10 KB and the stdout summary a 16 KB line nobody could read.
def edge_only(b):
    return b.split(": ", 1)[0]

def blockers_cell(blockers, cap=12):
    if not blockers:
        return "-"
    out = ["<b>%d blocking edge%s</b>" % (len(blockers), "" if len(blockers) == 1 else "s")]
    out += [E_(edge_only(b)) for b in blockers[:cap]]
    if len(blockers) > cap:
        out.append("… %d more, all in the rows below" % (len(blockers) - cap))
    return "<br>".join(out)

p = []
p.append('<header><h1>Cut score: %s</h1><p class="sub">%s%s · facts %s · rendered %s · '
         'the judgement for this page is skills/layering-review.md and the Stage 3 interview</p></header>' % (
    E_(app_name), E_(man.get("mpr") or "mpr not named"),
    (" · " + E_(man.get("mxcli"))) if man.get("mxcli") else "",
    E_(man.get("generated") or "collection date unknown"), E_(summary["generated"])))

for g in gaps:
    p.append('<div class="note warn">%s</div>' % E_(g))

p.append('<section><h2>Verdict %s</h2>' % vbadge(overall))
p.append('<p class="lede">Cut (%s): %s.</p>' % (E_(cut_source), " | ".join(
    "<b>%s</b> = %s" % (E_(n), E_(", ".join(m))) for n, m in partitions.items())))
p.append('<p>%s. Lanes available: OData external entity, published OData action or REST. '
         'Excluded: Business Events (no Event Broker licence).</p>' % E_(summary["denominator"]))
kp = [("%d" % len(partitions), "partitions", ""),
      ("%d / %d" % (crossing_edges, total_edges), "crossing edges / own edges", ""),
      ("%d / %d" % (crossing_weight, total_weight), "crossing refs / own refs", ""),
      ("%d" % len(bidir), "bidirectional call pairs", "k-bad" if bidir else "k-ok"),
      ("%d" % sum(1 for r in rows if r["class"] == "blocker"), "blocker rows", "k-bad" if any(r["class"] == "blocker" for r in rows) else "k-ok"),
      (("%d" % len(aggregate["hits"])) if aggregate["status"] != "NOT DETECTED" else "n/d",
       "cross-partition aggregates" + ("" if aggregate["status"] != "NOT DETECTED" else " (NOT DETECTED)"),
       "k-warn" if aggregate["hits"] or aggregate["status"] == "NOT DETECTED" else "k-ok")]
p.append('<div class="kpis">%s</div>' % "".join('<div class="kpi %s"><b>%s</b><span>%s</span></div>' % (c, E_(v), E_(l)) for v, l, c in kp))
p.append('</section>')

p.append('<section><h2>Per partition</h2>')
p.append(table(["Partition", "Modules", "Out edges (refs)", "In edges (refs)", "Lanes out", "Blockers", "Verdict"],
               [[n, ", ".join(d["modules"]), "%d (%d)" % (d["out_edges"], d["out_weight"]),
                 "%d (%d)" % (d["in_edges"], d["in_weight"]),
                 ", ".join("%s x%d" % (k, v) for k, v in sorted(d["lanes"].items())) or "-",
                 (blockers_cell(d["blockers"]), "why"),
                 (vbadge(d["verdict"]), "")] for n, d in parts.items()]))
if bidir:
    p.append('<h3>Bidirectional call pairs (blocker)</h3>')
    p.append(table(["A", "B", "A->B calls", "B->A calls", "Edges"],
                   [[b["a"], b["b"], b["a_to_b_calls"], b["b_to_a_calls"], "; ".join(b["edges"])] for b in bidir]))
p.append('</section>')

p.append('<section><h2>Every crossing edge (%d rows over %d module edges)</h2>' % (len(rows), crossing_edges))
p.append(table(["From", "To", "Partitions", "Ref kind", "Refs", "Lane", "Cost", "Class", "Aggregate", "Why"],
               [[r["from"], r["to"], "%s -> %s" % (r["from_partition"], r["to_partition"]), r["kind"], r["weight"],
                 r["lane"], r["cost"], (E_(r["class"]), "c-" + r["class"]), r["aggregate"], r["why"]] for r in
                sorted(rows, key=lambda r: (-COST_RANK.get(r["cost"], 0), r["from"], r["to"], r["kind"]))],
               cls=[None, None, None, None, None, None, None, None, None, "why"]))
p.append('</section>')

p.append('<section><h2>Aggregates over foreign entities: %s</h2>' % E_(aggregate["status"]))
p.append('<p>%s</p>' % E_(aggregate["reason"]))
p.append('<p class="legend">catalog: <code>%s</code></p>' % E_(CATALOG))
if aggregate["hits"]:
    p.append(table(["Microflow", "From", "Retrieves", "Aggregates in microflow", "Partitions"],
                   [[h["microflow"], h["from"], h["entity"], h["aggregates"],
                     "%s -> %s" % (h["from_partition"], h["to_partition"])] for h in aggregate["hits"]]))
p.append('</section>')

p.append('<section><h2>Method, and what this page cannot see</h2><ul>')
for line in [
    "Source: analysis/app-facts/dependencies.json (edges with per-kind counts, scope.own_modules) and, for "
    "aggregates, the mxcli catalog beside the .mpr. Nothing here re-reads the model.",
    "A crossing edge is a module-to-module edge whose endpoints sit in different partitions. Edges inside a "
    "partition are not listed; they are in the denominator above.",
    "Lanes are platform facts, not judgement: an external entity cannot own an association, be specialised, "
    "be aggregated server-side, or be the subject of a workflow; a call across apps is a published action or "
    "REST operation with no shared transaction. Business Events is excluded by licence.",
    "Blocker = bidirectional call pair between two partitions, or a generalize/workflow/security-role crossing. "
    "Costly = a call, a write to a foreign object, a page shown across apps, or a retrieve that feeds an aggregate. "
    "Acceptable = association, read, type or copy over an external entity (the owner keeps the data). "
    "A partition is blocked if a blocker touches it in either direction, costly if anything costly leaves it, "
    "clean if nothing or only acceptable edges leave it.",
    "Aggregate detection attributes an AggregateListAction to a RetrieveAction in the same microflow. It cannot "
    "see an aggregate over a list returned by a cross-partition call, nor how many objects an OData hop would move.",
    "Not visible at all: Java and JavaScript actions, published REST called by name, workflow references, page URLs. "
    "An edge that only exists through one of those is missing here, which is why a cut is confirmed in Studio Pro "
    "before it becomes a slice.",
]:
    p.append("<li>%s</li>" % E_(line))
p.append('</ul><p class="legend">An agent reading this later should take the JSON, not the page: '
         '<code>bin/cut-score.sh &lt;project&gt; --cut "..." --json</code> emits every row with its lane, cost and aggregate flag.</p>')
p.append('</section>')

doc = ("<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">"
       "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
       "<title>Cut score: %s</title><style>%s</style></head><body><div class=\"wrap\">%s</div></body></html>"
       % (E_(app_name), CSS, "\n".join(p)))

d = os.path.dirname(OUT)
if d and not os.path.isdir(d):
    os.makedirs(d)
open(OUT, "w", encoding="utf-8").write(doc)
json_out = os.path.splitext(OUT)[0] + ".json"
open(json_out, "w", encoding="utf-8").write(json.dumps(summary, indent=2, sort_keys=True))
print("cut-score: %s" % OUT)
print("cut-score: %s" % json_out)
print("  verdict %s; %s; %d bidirectional call pair(s); aggregates %s (%d)" % (
    overall, summary["denominator"], len(bidir), aggregate["status"], len(aggregate["hits"])))
for n, d_ in parts.items():
    print("  %-28s %-8s out %d(%d) in %d(%d)%s" % (n, d_["verdict"], d_["out_edges"], d_["out_weight"],
                                                  d_["in_edges"], d_["in_weight"],
                                                  ("  blockers: %d (%s%s)" % (len(d_["blockers"]),
                                                   "; ".join(edge_only(b) for b in d_["blockers"][:3]),
                                                   " …" if len(d_["blockers"]) > 3 else "")) if d_["blockers"] else ""))
for g in gaps:
    print("  gap: %s" % g)
PY
