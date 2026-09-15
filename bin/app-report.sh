#!/bin/bash
# app-report.sh — render the app dossier and its facts as ONE page: analysis/app-report.html
#
# WHAT THIS IS. The reading surface for skills/app-analysis.md. It takes the facts that
# project-bin/app-facts.sh collected (analysis/app-facts/*.json) and the dossier a person or
# agent wrote from them (architecture/app-dossier.md) and puts both on a page a stakeholder can
# open without a repository, a terminal, or Studio Pro.
#
# WHAT THIS IS NOT. Not a gate, not a judge. Per skills-over-scripts.md this file does
# arithmetic and layout only. Every threshold and every finding lives in the dossier; this page
# shows the facts next to what the dossier says about them. Where the dossier says nothing
# about a section, the page says so, in the fault colour, because a blank section on a report
# reads as "nothing wrong" to everyone who did not write it.
#
# What it WILL do without a dossier: render the facts alone, with every section marked
# `manual: no dossier yet`. That is the state right after the first bin/app-facts.sh run, and it
# is a legitimate page to hand to the person about to write the dossier.
#
# Usage:
#   bin/app-report.sh [project-dir]                      # -> <project>/analysis/app-report.html
#   bin/app-report.sh --facts DIR --dossier FILE -o OUT  # explicit paths (tests)
#   bin/app-report.sh --json                             # summary to stdout, no HTML (tests)
#
# Exit: 0 rendered · 2 no facts directory or unreadable manifest (nothing to render from)
#
# portability-ok: bash 3.2, Python 3 resolved through portable.sh

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/lib/portable.sh"
require_py

PROJECT=""; FACTS=""; DOSSIER=""; OUT=""; JSON=0
while [ $# -gt 0 ]; do
  case "$1" in
    --facts)   FACTS="$2"; shift 2 ;;
    --dossier) DOSSIER="$2"; shift 2 ;;
    -o|--out)  OUT="$2"; shift 2 ;;
    --json)    JSON=1; shift ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    -*)        echo "app-report: unknown option $1" >&2; exit 2 ;;
    *)         PROJECT="$1"; shift ;;
  esac
done
[ -n "$PROJECT" ] || PROJECT="."
PROJECT="$(cd "$PROJECT" 2>/dev/null && pwd)" || { echo "app-report: no such directory" >&2; exit 2; }
[ -n "$FACTS" ]   || FACTS="$PROJECT/analysis/app-facts"
[ -n "$DOSSIER" ] || DOSSIER="$PROJECT/architecture/app-dossier.md"
[ -n "$OUT" ]     || OUT="$PROJECT/analysis/app-report.html"

if [ ! -f "$FACTS/manifest.json" ]; then
  echo "app-report: no facts at $FACTS/manifest.json — run bin/app-facts.sh in the project first" >&2
  exit 2
fi

FACTS="$FACTS" DOSSIER="$DOSSIER" OUT="$OUT" JSON="$JSON" "$PY" - <<'PY'
import json, os, sys, html, re, datetime

F = os.environ["FACTS"]; DOSSIER = os.environ["DOSSIER"]; OUT = os.environ["OUT"]; JSON = os.environ["JSON"] == "1"
def load(name):
    p = os.path.join(F, name)
    if not os.path.exists(p): return None
    try: return json.load(open(p, encoding="utf-8"))
    except ValueError as e:
        print("app-report: %s is not valid JSON: %s" % (p, e), file=sys.stderr); sys.exit(2)
man = load("manifest.json"); inv = load("inventory.json") or {}; dep = load("dependencies.json") or {}; loops = load("loops.json")
if man is None: sys.exit(2)

# ---- the dossier: split by "## N. Title" headings; keep the text under each ------------------
DOSSIER_SECTIONS = ["Verdict summary", "Inventory", "Dependency shape", "Flow risk patterns", "Security posture",
                    "Lint baseline", "Dead elements", "Dispositions", "Method"]
dossier_text = open(DOSSIER, encoding="utf-8").read() if os.path.exists(DOSSIER) else None
dossier = {}
if dossier_text:
    parts = re.split(r"^##\s+(?:\d+\.\s*)?(.+?)\s*$", dossier_text, flags=re.M)
    for i in range(1, len(parts), 2):
        dossier[parts[i].strip().lower()] = parts[i + 1].strip()

# dossier verdicts: a table row "| Dependency shape | fail | ..." in the summary, or a
# "Status: fail" line at the top of the section. Whatever is absent is `manual`.
VERDICTS = ("pass", "fail", "fault", "manual", "skipped")
def dossier_verdict(title):
    key = title.lower()
    summ = dossier.get("verdict summary", "")
    for line in summ.splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        # accept "2. Inventory" and "**Inventory**" as well as the bare title
        if cells: cells[0] = re.sub(r"^\d+\.\s*", "", cells[0].strip("*").strip()).strip("*").strip()
        if len(cells) >= 2 and cells[0].lower() == key and cells[1].lower().strip("*") in VERDICTS:
            cells[1] = cells[1].strip("*")
            return cells[1].lower(), (cells[2] if len(cells) > 2 else "")
    body = dossier.get(key, "")
    m = re.search(r"^\**status\**\s*:\s*\**\s*(\w+)", body, flags=re.I | re.M)
    if m and m.group(1).lower() in VERDICTS:
        return m.group(1).lower(), ""
    if not dossier_text: return "manual", "no dossier yet: architecture/app-dossier.md not written"
    if key not in dossier: return "fault", "section missing from the dossier"
    return "manual", "section present, no verdict stated"

# ---- verdict per section = worst of (instrument status, dossier verdict) ----------------------
# The instrument's fault beats any dossier pass: you cannot pass a section on facts that were
# not collected. The dossier's fail beats an instrument pass: the instrument never fails.
RANK = {"fault": 0, "fail": 1, "manual": 2, "skipped": 3, "pass": 4}
def combine(instr, doss):
    # A dossier that honestly says "skipped" (lint deliberately not run this milestone) is not
    # a claim the instrument needs to back up, so an unrelated instrument fault (lint_baseline
    # is permanently "fault" until folded in) must not override it. A dossier "pass" IS such a
    # claim, so instrument fault still beats that.
    if doss == "skipped": return "skipped"
    if instr in ("fault", "partial"): return "fault"
    return doss if RANK.get(doss, 2) <= RANK.get("pass") else "pass"
secs = man.get("sections", {})
section_status = {
  "Inventory":          (secs.get("inventory", {}).get("status", "fault"),    secs.get("inventory", {}).get("reason", "")),
  "Dependency shape":   (secs.get("dependencies", {}).get("status", "fault"), secs.get("dependencies", {}).get("reason", "")),
  "Flow risk patterns": (secs.get("loops", {}).get("status", "fault"),        secs.get("loops", {}).get("reason", "")),
  "Security posture":   (secs.get("security", {}).get("status", "fault"),     secs.get("security", {}).get("reason", "")),
  "Lint baseline":      (secs.get("lint_baseline", {}).get("status", "fault"),secs.get("lint_baseline", {}).get("reason", "")),
  "Dead elements":      ("pass" if dep else "fault", "" if dep else "dependencies.json missing"),
}
rows = []
for title in ["Inventory", "Dependency shape", "Flow risk patterns", "Security posture", "Lint baseline", "Dead elements", "Dispositions"]:
    instr, ireason = section_status.get(title, ("pass", ""))
    dv, dreason = dossier_verdict(title)
    if title == "Dispositions":
        v = "manual" if dossier.get("dispositions") else ("fault" if dossier_text else "manual")
        reason = "hand-written; never derived" if dossier.get("dispositions") else ("dossier has no Dispositions section" if dossier_text else "no dossier yet")
    else:
        v = combine(instr, dv)
        reason = ireason if instr in ("fault", "partial") else (dreason or ("instrument: %s · dossier: %s" % (instr, dv)))
    rows.append({"section": title, "verdict": v, "instrument": instr, "dossier": dv, "reason": reason})

# Loop shape counts from facts (no thresholds applied here; counts only)
loop_shape = {}
if loops:
    mfs = loops.get("microflows", {})
    def has(r, *k): return any(x in r.get("in_loop", {}) for x in k)
    loop_shape = {
      "loop_microflows": len(mfs),
      "with_db_retrieve": sum(1 for r in mfs.values() if has(r, "RETRIEVE_DB")),
      "with_commit": sum(1 for r in mfs.values() if has(r, "COMMIT")),
      "with_delete": sum(1 for r in mfs.values() if has(r, "DELETE")),
      "with_rest_call": sum(1 for r in mfs.values() if has(r, "REST_CALL")),
      "with_nested_loop": sum(1 for r in mfs.values() if r.get("nested_loop_lines")),
      # a microflow call and nothing else the parser records in the body, and no nested loop
      # (the skill's LOOP_CALL-only shape; Java calls and association retrieves disqualify)
      "with_microflow_call_only": sum(1 for r in mfs.values() if set(r.get("in_loop", {})) == {"MICROFLOW_CALL"} and not r.get("nested_loop_lines")),
      "with_transaction_actions": sum(1 for r in mfs.values() if r.get("transaction_action_lines")),
      "scheduled_reachable": sum(1 for r in mfs.values() if r.get("reachable_from_scheduled_events")),
      # older facts have no enabled split; then every reachable loop counts as enabled-reachable
      "scheduled_reachable_enabled": sum(1 for r in mfs.values() if r.get("reachable_from_scheduled_events_enabled", r.get("reachable_from_scheduled_events"))),
      "catalog_undercount": loops.get("_meta", {}).get("catalog_undercount", 0),
      "parse_mismatch": len(loops.get("_meta", {}).get("parse_mismatch", [])),
    }

summary = {"generated": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
           "mpr": man.get("mpr"), "mxcli": man.get("mxcli"), "dossier_present": bool(dossier_text),
           "verdicts": {r["section"]: r["verdict"] for r in rows}, "loop_shape": loop_shape,
           "dependency_counts": dep.get("counts", {}), "totals": inv.get("totals", {})}
if JSON:
    json.dump(summary, sys.stdout, indent=1, sort_keys=True); print(); sys.exit(0)

# ---- HTML -----------------------------------------------------------------------------------
E = html.escape
def badge(v):
    cls = {"pass": "pass", "fail": "fail", "fault": "fault", "manual": "warn", "skipped": "skip", "partial": "fault"}.get(v, "warn")
    return '<span class="badge %s">%s</span>' % (cls, E(v))
def table(headers, body_rows, cls=""):
    if not body_rows: return '<p class="empty">nothing to show: zero rows. Check this is a real zero (see Method).</p>'
    h = "".join("<th>%s</th>" % E(str(x)) for x in headers)
    b = "".join("<tr>%s</tr>" % "".join("<td>%s</td>" % (c if isinstance(c, Raw) else E(str(c))) for c in r) for r in body_rows)
    return '<div class="tw"><table class="%s"><thead><tr>%s</tr></thead><tbody>%s</tbody></table></div>' % (cls, h, b)
class Raw(str): pass
def md_min(text):
    # minimal, safe markdown: headings ###, tables, bullets, paragraphs. Escaped first.
    out, in_tbl, in_ul = [], False, False
    for line in (text or "").splitlines():
        s = line.rstrip()
        if s.startswith("|"):
            cells = [c.strip() for c in s.strip("|").split("|")]
            if all(re.fullmatch(r":?-{2,}:?", c) for c in cells if c): continue
            if not in_tbl: out.append('<div class="tw"><table>'); in_tbl = True
            out.append("<tr>%s</tr>" % "".join("<td>%s</td>" % inline(c) for c in cells)); continue
        if in_tbl: out.append("</table></div>"); in_tbl = False
        if s.startswith("- ") or s.startswith("* "):
            if not in_ul: out.append("<ul>"); in_ul = True
            out.append("<li>%s</li>" % inline(s[2:])); continue
        if in_ul: out.append("</ul>"); in_ul = False
        if s.startswith("### "): out.append("<h4>%s</h4>" % inline(s[4:])); continue
        if s.startswith("```"): continue
        if s.strip(): out.append("<p>%s</p>" % inline(s))
    if in_tbl: out.append("</table></div>")
    if in_ul: out.append("</ul>")
    return "\n".join(out)
def inline(s):
    s = E(s)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
    return s
def dossier_block(title):
    body = dossier.get(title.lower())
    if body is None:
        return '<div class="note fault">The dossier has no "%s" section. Per skills/app-analysis.md an absent section is a fault, not a clean result.</div>' % E(title) if dossier_text \
            else '<div class="note warn">No dossier yet. Facts below are unjudged; write architecture/app-dossier.md from them (skills/app-analysis.md).</div>'
    return '<div class="dossier">%s</div>' % md_min(body)

P = inv.get("project", {}); T = inv.get("totals", {}); C = dep.get("counts", {})
own_mods = [m for m in inv.get("modules", []) if m.get("kind") == "own"]
mkt_mods = [m for m in inv.get("modules", []) if m.get("kind") == "marketplace"]

parts = []
parts.append('<header><h1>App dossier: %s</h1><p class="sub">%s · Mendix %s · %s · facts %s · rendered %s</p></header>' % (
    E(P.get("name") or man.get("mpr", "")), E(man.get("mpr", "")), E(P.get("mendix_version", "?")), E(man.get("mxcli", "")),
    E(man.get("generated", "")), E(summary["generated"])))

# 1 verdict summary
parts.append('<section id="s1"><h2>1. Verdict summary</h2>')
parts.append(table(["section", "verdict", "instrument", "dossier", "why"],
                   [[r["section"], Raw(badge(r["verdict"])), r["instrument"], r["dossier"], r["reason"]] for r in rows], "summary"))
parts.append('<p class="legend">pass: collected and judged clean · fail: finding without disposition · fault: not collected or not trustworthy · manual: needs a person · skipped: deliberately not run</p></section>')

# 2 inventory
parts.append('<section id="s2"><h2>2. Inventory %s</h2>' % badge(summary["verdicts"]["Inventory"]))
parts.append('<div class="kpis">%s</div>' % "".join('<div class="kpi"><b>%s</b><span>%s</span></div>' % (E(str(T.get(k, "?"))), E(k.replace("_", " ")))
             for k in ["modules_own", "modules_marketplace", "entities", "microflows", "nanoflows", "pages", "scheduled_events", "refs"]))
parts.append(dossier_block("Inventory"))
parts.append('<h3>Own modules</h3>')
parts.append(table(["module", "entities (P / NP / V)", "microflows", "nanoflows", "pages", "loop activities", "mf ≥25 act.", "entities ≥20 attr."],
    [[m["name"], "%d (%s / %s / %s)" % (m["entities_total"], m["entities"].get("PERSISTENT", 0), m["entities"].get("NON_PERSISTENT", 0), m["entities"].get("VIEW", 0)),
      m["microflows"], m["nanoflows"], m["pages"], m["loop_activities"], m["microflows_25plus_activities"], m["entities_20plus_attributes"]] for m in own_mods]))
parts.append('<h3>Marketplace modules</h3>')
parts.append(table(["module", "version", "entities", "microflows"], [[m["name"], m["marketplace_version"] or m["source"], m["entities_total"], m["microflows"]] for m in mkt_mods]))
parts.append('<h3>Scheduled events</h3>')
parts.append(table(["event", "microflow", "enabled", "interval (s)", "repeat"],
    [[s.get("QualifiedName"), s.get("Microflow"), s.get("Enabled"), s.get("IntervalSeconds"), s.get("RepeatDescription")] for s in inv.get("scheduled_events", [])]))
parts.append('</section>')

# 3 dependency shape
parts.append('<section id="s3"><h2>3. Dependency shape %s</h2>' % badge(summary["verdicts"]["Dependency shape"]))
parts.append('<div class="kpis">%s</div>' % "".join('<div class="kpi"><b>%s</b><span>%s</span></div>' % (E(str(C.get(k, "?"))), E(k.replace("_", " ")))
             for k in ["own_edges", "bidirectional_pairs", "tangles", "largest_tangle", "three_cycles", "dead_assets_own"]))
parts.append(dossier_block("Dependency shape"))
parts.append('<h3>Tangles (strongly connected components)</h3>')
parts.append(table(["#", "modules", "members"], [[i + 1, len(t), ", ".join(t)] for i, t in enumerate(dep.get("tangles", {}).get("list", []))]))
parts.append('<h3>Bidirectional pairs</h3>')
parts.append(table(["A", "B", "A→B", "kinds", "B→A", "kinds"],
    [[p["a"], p["b"], p["a_to_b"], ", ".join("%s %d" % kv for kv in sorted(p["a_to_b_kinds"].items(), key=lambda x: -x[1])),
      p["b_to_a"], ", ".join("%s %d" % kv for kv in sorted(p["b_to_a_kinds"].items(), key=lambda x: -x[1]))] for p in dep.get("bidirectional_pairs", [])]))
parts.append('<h3>Cohesion (own modules, lowest first)</h3>')
parts.append(table(["module", "cohesion %", "intra", "outbound", "inbound"],
    [[c["module"], c["cohesion_pct"] if c["cohesion_pct"] is not None else "n/a", c["intra_edges"], c["outbound_edges"], c["inbound_edges"]] for c in dep.get("cohesion", [])]))
parts.append('<h3>Most referenced assets (own modules)</h3>')
parts.append(table(["asset", "type", "in", "out"], [[g["asset"], g["type"], g["in_degree"], g["out_degree"]] for g in dep.get("god_nodes", [])[:20]]))
parts.append('<h3>Own → marketplace</h3>')
parts.append(table(["from", "to", "refs"], [[e["from"], e["to"], e["edges"]] for e in dep.get("edges_to_marketplace", [])[:40]]))
parts.append('</section>')

# 4 loops
parts.append('<section id="s4"><h2>4. Flow risk patterns %s</h2>' % badge(summary["verdicts"]["Flow risk patterns"]))
ls = secs.get("loops", {})
parts.append('<p class="sub">instrument: %s · candidates %s · described %s · failed %s · parse mismatch %s</p>' % (
    E(str(ls.get("status"))), ls.get("candidates", "?"), ls.get("described", "?"), ls.get("failed", "?"), ls.get("parse_mismatch", "?")))
if loop_shape:
    parts.append('<div class="kpis">%s</div>' % "".join('<div class="kpi"><b>%s</b><span>%s</span></div>' % (v, E(k.replace("_", " "))) for k, v in loop_shape.items()))
parts.append(dossier_block("Flow risk patterns"))
if loops:
    lrows = []
    for qn, r in sorted(loops.get("microflows", {}).items(), key=lambda kv: (not kv[1].get("reachable_from_scheduled_events"), kv[0])):
        il = r.get("in_loop", {})
        if not il and not r.get("nested_loop_lines") and not r.get("transaction_action_lines"): continue
        lrows.append([qn, ", ".join("%s×%d" % kv for kv in sorted(il.items())), len(r.get("nested_loop_lines", [])),
                      len(r.get("transaction_action_lines", [])), ", ".join(r.get("reachable_from_scheduled_events", [])),
                      "%s/%s" % (r.get("loops_parsed"), r.get("loops_catalog", "?"))])
    parts.append('<h3>Loop microflows whose loop bodies do something (%d of %d)</h3>' % (len(lrows), len(loops.get("microflows", {}))))
    parts.append(table(["microflow", "in loop body", "nested", "tx actions", "scheduled events", "loops parsed/catalog"], lrows, "loops"))
    mm = loops.get("_meta", {}).get("parse_mismatch", [])
    if mm:
        parts.append('<h3>Parse mismatches (read by hand)</h3>')
        parts.append(table(["microflow", "catalog", "parsed"], [[m["microflow"], m["catalog"], m["parsed"]] for m in mm]))
parts.append('</section>')

# 5, 6
for n, title, key in [(5, "Security posture", "security"), (6, "Lint baseline", "lint_baseline")]:
    parts.append('<section id="s%d"><h2>%d. %s %s</h2><p class="sub">instrument: %s</p>%s</section>' % (
        n, n, title, badge(summary["verdicts"][title]), E(secs.get(key, {}).get("reason", "not in manifest")), dossier_block(title)))

# 7 dead
parts.append('<section id="s7"><h2>7. Dead elements %s</h2>' % badge(summary["verdicts"]["Dead elements"]))
parts.append(dossier_block("Dead elements"))
parts.append(table(["asset", "type", "module"], [[d["QualifiedName"], d["ObjectType"], d["ModuleName"]] for d in dep.get("dead_assets_own", [])]))
parts.append('<p class="legend">Candidates only: the catalog cannot see Java, published REST, workflows or page URLs. Confirm in Studio Pro before any delete.</p></section>')

# 8 dispositions, 9 method
parts.append('<section id="s8"><h2>8. Dispositions %s</h2>%s</section>' % (badge(summary["verdicts"]["Dispositions"]), dossier_block("Dispositions")))
tm = man.get("timings_s", {}); cat = man.get("catalog", {})
parts.append('<section id="s9"><h2>9. Method</h2>%s<h3>Instrument run</h3>%s</section>' % (
    dossier_block("Method"),
    table(["item", "value"], [["mxcli", man.get("mxcli")], ["mpr sha256 (16)", man.get("mpr_sha256_16")], ["catalog build mode", cat.get("build_mode")],
                              ["catalog modules / refs / activities", "%s / %s / %s" % (cat.get("modules"), cat.get("refs"), cat.get("activities"))],
                              ["timings (s)", ", ".join("%s %s" % kv for kv in tm.items())], ["options", json.dumps(man.get("options", {}))]])))

page = """<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>App dossier: %(title)s</title>
<style>
  :root { --bg:#f8fafc; --surface:#fff; --ink:#1e293b; --ink-soft:#64748b; --ink-faint:#94a3b8; --line:#e2e8f0; --accent:#0f4c81;
          --pass-bg:#dcfce7; --pass-ink:#166534; --fail-bg:#fee2e2; --fail-ink:#991b1b; --warn-bg:#fef3c7; --warn-ink:#92400e;
          --fault-bg:#fce7f3; --fault-ink:#9d174d; --skip-bg:#e2e8f0; --skip-ink:#334155; --radius:10px;
          --font:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif; --mono:ui-monospace,'SF Mono',Menlo,monospace; }
  body { margin:0; background:var(--bg); color:var(--ink); font:14px/1.5 var(--font); }
  header, section { max-width:1200px; margin:0 auto; padding:20px 24px; }
  header h1 { margin:0 0 4px; font-size:24px; } .sub { color:var(--ink-soft); margin:0 0 8px; font-size:13px; }
  section { background:var(--surface); border:1px solid var(--line); border-radius:var(--radius); margin:16px auto; }
  h2 { font-size:18px; margin:0 0 12px; display:flex; align-items:center; gap:10px; } h3 { font-size:14px; color:var(--ink-soft); margin:18px 0 6px; text-transform:uppercase; letter-spacing:.04em; } h4 { margin:12px 0 4px; }
  .badge { font:600 11px/1 var(--mono); padding:4px 8px; border-radius:999px; text-transform:uppercase; }
  .badge.pass { background:var(--pass-bg); color:var(--pass-ink); } .badge.fail { background:var(--fail-bg); color:var(--fail-ink); }
  .badge.fault { background:var(--fault-bg); color:var(--fault-ink); } .badge.warn { background:var(--warn-bg); color:var(--warn-ink); } .badge.skip { background:var(--skip-bg); color:var(--skip-ink); }
  .kpis { display:flex; flex-wrap:wrap; gap:10px; margin:6px 0 12px; } .kpi { background:var(--bg); border:1px solid var(--line); border-radius:8px; padding:8px 12px; min-width:110px; }
  .kpi b { display:block; font-size:20px; } .kpi span { color:var(--ink-soft); font-size:11px; text-transform:uppercase; letter-spacing:.04em; }
  .tw { overflow-x:auto; } table { border-collapse:collapse; width:100%%; font-size:13px; } th, td { text-align:left; padding:6px 8px; border-bottom:1px solid var(--line); vertical-align:top; }
  th { color:var(--ink-soft); font-weight:600; font-size:12px; } td:first-child { font-family:var(--mono); font-size:12px; }
  .note { padding:10px 12px; border-radius:8px; margin:8px 0; } .note.fault { background:var(--fault-bg); color:var(--fault-ink); } .note.warn { background:var(--warn-bg); color:var(--warn-ink); }
  .dossier { border-left:3px solid var(--accent); padding:4px 14px; margin:8px 0 14px; background:var(--bg); border-radius:0 8px 8px 0; }
  .empty { color:var(--ink-faint); font-style:italic; } .legend { color:var(--ink-soft); font-size:12px; } code { font-family:var(--mono); font-size:12px; background:var(--bg); padding:1px 4px; border-radius:4px; }
</style></head><body>%(body)s
<footer style="text-align:center;color:var(--ink-faint);font-size:12px;padding:16px">rendered by bin/app-report.sh · facts by project-bin/app-facts.sh · judgement per skills/app-analysis.md</footer>
</body></html>""" % {"title": E(P.get("name") or man.get("mpr", "")), "body": "\n".join(parts)}

os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
open(OUT, "w", encoding="utf-8").write(page)
print("==> wrote %s" % OUT)
print("    verdicts: " + ", ".join("%s=%s" % (k, v) for k, v in summary["verdicts"].items()))
PY
