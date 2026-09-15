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
# TWO QUESTIONS, TWO ANSWERS. The section table answers "how far has the review got", in the
# toolkit verdict vocabulary, and a first run with no decisions written is honestly `fail`
# there. That says nothing about the app, so this page also answers "how healthy is the app"
# from the facts alone: every finding is scored (pattern class + scheduled reach + blast
# radius), the scores roll up to ok / watch / at risk, and that state is the same on a first
# run and a tenth. The weights are the "Severity" table in skills/app-analysis.md; this file
# only adds them up. Health never needs a decision to exist, review progress never needs a
# finding to be fixed, and neither one can hide behind the other.
#
# It also writes app-report.json next to the page: the same summary, the scored findings and
# the top of the fix-first list, so the next agent reads one file instead of 27 HTML tables.
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

# ---- severity: score every finding from facts only ------------------------------------------
# Three inputs, all already collected. The weights are the "Severity" table in
# skills/app-analysis.md; change them there and here together, never here alone.
#   pattern class   what the finding costs per iteration or per change
#   reach           enabled scheduled event +2, disabled-only +1, neither 0
#   blast radius    the module is depended on by WIDE_BLAST_INBOUND or more others, +1
# 6 is critical, 4 to 5 high, 2 to 3 medium, 1 and under low. The four words are the severity
# vocabulary the expert-services reviews already use; they are a per-finding property and do
# not touch the pass/fail/fault/manual/skipped section vocabulary, which means something else.
WIDE_BLAST_INBOUND = 6
MIN_COHESION_PCT = 60
PATTERN_W = {"REST_IN_LOOP": 3, "END_TRANSACTION": 3, "LOOP_TQ": 2, "LOOP_COMMIT_DEFERRED": 2,
             "LOOP_NESTED": 1, "DEP_TANGLE": 3, "DEP_PAIR": 2, "DEP_COHESION": 1, "DEAD_CANDIDATES": 1}
SEVS = ("critical", "high", "medium", "low")
def sev_of(score): return "critical" if score >= 6 else ("high" if score >= 4 else ("medium" if score >= 2 else "low"))
# one short remediation per pattern, so the fix-first table says what to do, not only what is wrong
FIX_OF = {
  "LOOP_TQ": "retrieve once before the loop, change inside it, commit the list once after",
  "LOOP_COMMIT_DEFERRED": "collect the changed objects and commit the list once after the loop",
  "REST_IN_LOOP": "use a batch endpoint, or a task queue with one task per item",
  "END_TRANSACTION": "one transaction around the batch, never start or end one per iteration",
  "LOOP_NESTED": "read the inner loop; if it retrieves or calls, flatten it to one pass over a map",
  "DEP_TANGLE": "pick one pair at a time, move the shared part into a module both can depend on",
  "DEP_PAIR": "choose an owner for the shared data and make the other direction an interface",
  "DEP_COHESION": "name it as a facade or API module in the disposition, or move work into it",
  "DEAD_CANDIDATES": "Find usages in Studio Pro on a sample first, then delete in one slice",
}

inbound = {c["module"]: c.get("inbound_edges", 0) for c in dep.get("cohesion", [])}
own_names = {m["name"] for m in inv.get("modules", []) if m.get("kind") == "own"}
def blast(module): return 1 if inbound.get(module, 0) >= WIDE_BLAST_INBOUND else 0

# decisions: one line per finding in the dossier's Dispositions section, carrying the target
# name in brackets. A `later` is a decision only with a slice or a date (skills/app-analysis.md).
disp_lines, decided_lines = [], 0
for line in (dossier.get("dispositions", "") or "").splitlines():
    s = line.strip()
    if not (s.startswith("- ") or s.startswith("* ")): continue
    m = re.search(r"\b(fix|accept|later|undecided)\b", s, flags=re.I)
    if not m: continue
    word = m.group(1).lower()
    dec = word in ("fix", "accept") or (word == "later" and bool(re.search(r"\d{4}-\d{2}-\d{2}|slice", s, re.I)))
    if "undecided" in s.lower(): dec = False
    if re.search(r"\bclosed\b", s, re.I): dec = True
    disp_lines.append({"text": s, "decision": word, "decided": dec})
    decided_lines += 1 if dec else 0
def decision_for(*names):
    for d in disp_lines:
        if any(n and n in d["text"] for n in names):
            return ("decided: " + d["decision"]) if d["decided"] else (d["decision"] + ", no decision")
    return "none"

findings = []
def add(kind, pattern, target, module, score, why, evidence):
    findings.append({"kind": kind, "pattern": pattern, "target": target, "module": module,
                     "score": score, "severity": sev_of(score), "why": why, "evidence": evidence,
                     "recommended_fix": FIX_OF.get(pattern, ""),
                     "decision": decision_for(target, module if kind == "dependency" else "")})

if loops:
    for qn, r in sorted(loops.get("microflows", {}).items()):
        mod = qn.split(".", 1)[0]
        if own_names and mod not in own_names: continue   # marketplace loops are not ours
        il = r.get("in_loop", {})
        en = r.get("reachable_from_scheduled_events_enabled", r.get("reachable_from_scheduled_events") or [])
        dis = r.get("reachable_from_scheduled_events_disabled", [])
        reach, rwhy = (2, "runs from an enabled scheduled event") if en else \
                      ((1, "reachable only from a disabled scheduled event") if dis else (0, "not on a scheduled path"))
        pats = []
        if "RETRIEVE_DB" in il or "DELETE" in il: pats.append("LOOP_TQ")
        if "COMMIT" in il: pats.append("LOOP_COMMIT_DEFERRED")
        if "REST_CALL" in il: pats.append("REST_IN_LOOP")
        if r.get("transaction_action_lines"): pats.append("END_TRANSACTION")
        if r.get("nested_loop_lines"): pats.append("LOOP_NESTED")
        for p in pats:
            b = blast(mod)
            why = "%s in a loop body; %s%s" % (p, rwhy, "; module is depended on by %d others" % inbound.get(mod, 0) if b else "")
            add("loop", p, qn, mod, PATTERN_W[p] + reach + b, why, "mdl/%s.mdl" % qn)

tangled = set()
for t in dep.get("tangles", {}).get("list", []):
    tangled |= set(t)
    if len(t) < 2: continue
    big = 1 if len(t) >= WIDE_BLAST_INBOUND else 0
    add("dependency", "DEP_TANGLE", "tangle of %d modules" % len(t), t[0], PATTERN_W["DEP_TANGLE"] + 1 + big,
        "%d own modules can each reach every other, so a change in one can surface in any of them" % len(t),
        "dependencies.json tangles")
for p in dep.get("bidirectional_pairs", []):
    if p["a"] in tangled and p["b"] in tangled: continue   # the tangle finding already covers it
    add("dependency", "DEP_PAIR", "%s <-> %s" % (p["a"], p["b"]), p["a"],
        PATTERN_W["DEP_PAIR"] + max(blast(p["a"]), blast(p["b"])),
        "the two modules reference each other in both directions", "dependencies.json bidirectional_pairs")
for c in dep.get("cohesion", []):
    pct = c.get("cohesion_pct")
    if pct is None or pct >= MIN_COHESION_PCT: continue
    add("dependency", "DEP_COHESION", c["module"], c["module"], PATTERN_W["DEP_COHESION"] + blast(c["module"]),
        "%.0f%% of its references leave the module, below MIN_COHESION_PCT %d" % (pct, MIN_COHESION_PCT),
        "dependencies.json cohesion")
dead_n = len(dep.get("dead_assets_own", []))
if dead_n:
    add("dead", "DEAD_CANDIDATES", "%d unreferenced asset%s in own modules" % (dead_n, "" if dead_n == 1 else "s"), "", PATTERN_W["DEAD_CANDIDATES"],
        "no inbound reference in the catalog; candidates only, the catalog cannot see Java, REST or page URLs",
        "dependencies.json dead_assets_own")

findings.sort(key=lambda f: (-f["score"], f["pattern"], f["target"]))
sev_counts = {s: sum(1 for f in findings if f["severity"] == s) for s in SEVS}
nightly = sum(1 for f in findings if "enabled scheduled event" in f["why"])
undecided = sum(1 for f in findings if f["decision"] == "none" or "no decision" in f["decision"])

blind = [k for k, v in secs.items() if v.get("status") not in ("pass", "skipped")]
core_fault = any(secs.get(k, {}).get("status") != "pass" for k in ("inventory", "dependencies", "loops"))
top_n = sev_counts["critical"] + sev_counts["high"]
health_state = "unknown" if core_fault else ("at risk" if top_n else ("watch" if sev_counts["medium"] else "ok"))
health_line = {
  "unknown": "The instrument did not collect enough to judge this app. Fix the collection before reading anything below.",
  "at risk": "%d critical and %d high severity findings, %d of them on the nightly path. These are what breaks first under load." % (sev_counts["critical"], sev_counts["high"], nightly),
  "watch":   "No critical or high severity finding. %d medium ones: real, but none of them both costly per iteration and scheduled." % sev_counts["medium"],
  "ok":      "No medium or worse finding in what was collected. %d low ones remain as candidates." % sev_counts["low"],
}[health_state]
review_state = "not started" if decided_lines == 0 else ("complete" if undecided == 0 else "in progress")

summary = {"generated": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
           "mpr": man.get("mpr"), "mxcli": man.get("mxcli"), "dossier_present": bool(dossier_text),
           "verdicts": {r["section"]: r["verdict"] for r in rows}, "loop_shape": loop_shape,
           "dependency_counts": dep.get("counts", {}), "totals": inv.get("totals", {}),
           "health": {"state": health_state, "line": health_line, "severity": sev_counts,
                      "findings_total": len(findings), "on_nightly_path": nightly,
                      "not_measured": sorted(blind)},
           "review_progress": {"state": review_state, "disposition_lines": len(disp_lines),
                               "lines_with_a_decision": decided_lines, "findings_without_a_decision": undecided},
           "fix_first": findings[:5], "findings": findings}
if JSON:
    json.dump(summary, sys.stdout, indent=1, sort_keys=True); print(); sys.exit(0)

# ---- HTML -----------------------------------------------------------------------------------
E = html.escape
def badge(v):
    cls = {"pass": "pass", "fail": "fail", "fault": "fault", "manual": "warn", "skipped": "skip", "partial": "fault"}.get(v, "warn")
    return '<span class="badge %s">%s</span>' % (cls, E(v))
def hbadge(state):
    return '<span class="hstate %s">%s</span>' % ({"ok": "pass", "watch": "warn", "at risk": "fail"}.get(state, "fault"), E(state))
def sevbadge(s):
    return '<span class="badge %s">%s</span>' % ({"critical": "crit", "high": "fail", "medium": "warn", "low": "skip"}[s], s)
def table(headers, body_rows, cls=""):
    if not body_rows: return '<p class="empty">nothing to show: zero rows. Check this is a real zero (see Method).</p>'
    h = "".join("<th>%s</th>" % E(str(x)) for x in headers)
    b = "".join("<tr>%s</tr>" % "".join("<td>%s</td>" % (c if isinstance(c, Raw) else E(str(c))) for c in r) for r in body_rows)
    return '<div class="tw"><table class="%s"><thead><tr>%s</tr></thead><tbody>%s</tbody></table></div>' % (cls, h, b)
# Anything longer than this folds away. The page must have a skeleton a person can see in one
# screen; the rows are evidence, and evidence belongs one click down, not in the way.
COLLAPSE_ROWS = 12
def fold(label, body_rows, headers, rows_html=None, cls="", note=""):
    inner = rows_html if rows_html is not None else table(headers, body_rows, cls)
    n = len(body_rows)
    if n <= COLLAPSE_ROWS: return '<h3>%s</h3>%s' % (E(label), inner)
    return '<details><summary><b>%s</b> <span class="count">%d rows</span>%s</summary>%s</details>' % (
        E(label), n, (' <span class="count">%s</span>' % E(note)) if note else "", inner)
class Raw(str): pass
def md_min(text):
    # minimal, safe markdown: headings ###, tables, bullets, paragraphs. Escaped first.
    # A dossier table longer than COLLAPSE_ROWS folds like every other long table: the page
    # keeps a skeleton a person can see, the rows stay one click away.
    out, in_tbl, in_ul, buf = [], False, False, []
    def close_tbl():
        n = len(buf)
        t = '<div class="tw"><table>%s</table></div>' % "".join(buf)
        out.append(t if n <= COLLAPSE_ROWS else
                   '<details><summary><b>table from the dossier</b> <span class="count">%d rows</span></summary>%s</details>' % (n, t))
        del buf[:]
    for line in (text or "").splitlines():
        s = line.rstrip()
        if s.startswith("|"):
            cells = [c.strip() for c in s.strip("|").split("|")]
            if all(re.fullmatch(r":?-{2,}:?", c) for c in cells if c): continue
            in_tbl = True
            buf.append("<tr>%s</tr>" % "".join("<td>%s</td>" % inline(c) for c in cells)); continue
        if in_tbl: close_tbl(); in_tbl = False
        if s.startswith("- ") or s.startswith("* "):
            if not in_ul: out.append("<ul>"); in_ul = True
            out.append("<li>%s</li>" % inline(s[2:])); continue
        if in_ul: out.append("</ul>"); in_ul = False
        if s.startswith("### "): out.append("<h4>%s</h4>" % inline(s[4:])); continue
        if s.startswith("```"): continue
        if s.strip(): out.append("<p>%s</p>" % inline(s))
    if in_tbl: close_tbl()
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

# 0 executive summary, fixed shape: what it is, how healthy, what to fix first, how far the
# review got, what was not measured. Nothing here needs a dossier: it is all derived from facts.
NOT_MEASURED = {"security": "security posture", "lint_baseline": "lint baseline"}
parts.append('<section id="s0" class="exec"><h2>Executive summary %s</h2>' % hbadge(health_state))
parts.append('<p class="lede"><b>What this app is.</b> %s own modules and %s marketplace modules on Mendix %s, holding %s entities, %s microflows, %s pages and %s scheduled events (%s of them enabled).</p>' % (
    T.get("modules_own", "?"), T.get("modules_marketplace", "?"), E(P.get("mendix_version", "?")),
    T.get("entities", "?"), T.get("microflows", "?"), T.get("pages", "?"), T.get("scheduled_events", "?"),
    sum(1 for s in inv.get("scheduled_events", []) if s.get("Enabled") in (True, "true", "True", 1))))
parts.append('<p class="lede"><b>Health: %s.</b> %s</p>' % (E(health_state), E(health_line)))
parts.append('<div class="kpis">%s</div>' % "".join('<div class="kpi %s"><b>%s</b><span>%s</span></div>' % (c, v, E(k)) for k, v, c in [
    ("critical", sev_counts["critical"], "k-crit"), ("high", sev_counts["high"], "k-fail"),
    ("medium", sev_counts["medium"], "k-warn"), ("low", sev_counts["low"], ""),
    ("on the nightly path", nightly, "k-fail"), ("findings without a decision", undecided, ""),
    ("not measured", len(blind), "k-fault")]))
parts.append('<h3>Fix first</h3>')
parts.append(table(["severity", "finding", "where", "why it scores", "recommended fix", "decision"],
    [[Raw(sevbadge(f["severity"])), f["pattern"], f["target"], f["why"], f["recommended_fix"], f["decision"]] for f in findings[:5]], "fixfirst"))
parts.append('<p class="legend">Score = pattern class + scheduled reach (enabled +2, disabled only +1) + blast radius (+1 when the module is depended on by %d or more others). 6 is critical, 4 to 5 high, 2 to 3 medium. Derived from the facts alone, so it reads the same on a first run and a tenth, and the same way on another app. Weights: skills/app-analysis.md, table "Severity".</p>' % WIDE_BLAST_INBOUND)
parts.append('<p class="lede"><b>Review progress: %s.</b> %d of %d disposition lines carry a decision; %d of %d scored findings still have none. This is a fact about the document, not about the app: an app can be healthy with nothing decided, and fully decided while still at risk.</p>' % (
    E(review_state), decided_lines, len(disp_lines), undecided, len(findings)))
parts.append('<p class="lede"><b>Not measured.</b> %s. Nothing below covers those; treat them as unknown, not clean.</p>' % (
    E(", ".join(NOT_MEASURED.get(b, b) for b in sorted(blind))) if blind else "Every section this version collects was collected"))
parts.append('<p class="legend">For an agent picking this up later: read <code>app-report.json</code> next to this page, or the <code>app-report-data</code> script block in it. Same numbers, no table parsing.</p>')
parts.append('</section>')

# 1 verdict summary
parts.append('<section id="s1"><h2>1. Verdict summary: how far the review has got</h2>')
parts.append(table(["section", "verdict", "instrument", "dossier", "why"],
                   [[r["section"], Raw(badge(r["verdict"])), r["instrument"], r["dossier"], r["reason"]] for r in rows], "summary"))
parts.append('<p class="legend">These five words are the toolkit verdict vocabulary and they judge the REVIEW, not the app: pass: collected and judged clean · fail: finding without a disposition · fault: not collected or not trustworthy · manual: needs a person · skipped: deliberately not run. A first run has no dispositions, so `fail` here is expected and says nothing about health. The app verdict is the one at the top of the page.</p></section>')

# 2 inventory
parts.append('<section id="s2"><h2>2. Inventory %s</h2>' % badge(summary["verdicts"]["Inventory"]))
parts.append('<div class="kpis">%s</div>' % "".join('<div class="kpi"><b>%s</b><span>%s</span></div>' % (E(str(T.get(k, "?"))), E(k.replace("_", " ")))
             for k in ["modules_own", "modules_marketplace", "entities", "microflows", "nanoflows", "pages", "scheduled_events", "refs"]))
parts.append(dossier_block("Inventory"))
own_rows = [[m["name"], "%d (%s / %s / %s)" % (m["entities_total"], m["entities"].get("PERSISTENT", 0), m["entities"].get("NON_PERSISTENT", 0), m["entities"].get("VIEW", 0)),
             m["microflows"], m["nanoflows"], m["pages"], m["loop_activities"], m["microflows_25plus_activities"], m["entities_20plus_attributes"]] for m in own_mods]
parts.append(fold("Own modules", own_rows, ["module", "entities (P / NP / V)", "microflows", "nanoflows", "pages", "loop activities", "mf ≥25 act.", "entities ≥20 attr."]))
mkt_rows = [[m["name"], m["marketplace_version"] or m["source"], m["entities_total"], m["microflows"]] for m in mkt_mods]
parts.append(fold("Marketplace modules", mkt_rows, ["module", "version", "entities", "microflows"]))
sev_rows = [[s.get("QualifiedName"), s.get("Microflow"), s.get("Enabled"), s.get("IntervalSeconds"), s.get("RepeatDescription")] for s in inv.get("scheduled_events", [])]
parts.append(fold("Scheduled events", sev_rows, ["event", "microflow", "enabled", "interval (s)", "repeat"],
                  note="the enabled ones are the nightly path"))
parts.append('</section>')

# 3 dependency shape
parts.append('<section id="s3"><h2>3. Dependency shape %s</h2>' % badge(summary["verdicts"]["Dependency shape"]))
parts.append('<div class="kpis">%s</div>' % "".join('<div class="kpi"><b>%s</b><span>%s</span></div>' % (E(str(C.get(k, "?"))), E(k.replace("_", " ")))
             for k in ["own_edges", "bidirectional_pairs", "tangles", "largest_tangle", "three_cycles", "dead_assets_own"]))
parts.append(dossier_block("Dependency shape"))
parts.append(fold("Tangles (strongly connected components)", [[i + 1, len(t), ", ".join(t)] for i, t in enumerate(dep.get("tangles", {}).get("list", []))],
                  ["#", "modules", "members"]))
parts.append(fold("Bidirectional pairs",
    [[p["a"], p["b"], p["a_to_b"], ", ".join("%s %d" % kv for kv in sorted(p["a_to_b_kinds"].items(), key=lambda x: -x[1])),
      p["b_to_a"], ", ".join("%s %d" % kv for kv in sorted(p["b_to_a_kinds"].items(), key=lambda x: -x[1]))] for p in dep.get("bidirectional_pairs", [])],
    ["A", "B", "A→B", "kinds", "B→A", "kinds"]))
coh = dep.get("cohesion", [])
below = [c for c in coh if c["cohesion_pct"] is not None and c["cohesion_pct"] < MIN_COHESION_PCT]
parts.append('<h3>Cohesion: %d of %d own modules sit below MIN_COHESION_PCT %d</h3>' % (len(below), len(coh), MIN_COHESION_PCT))
parts.append(fold("Cohesion (own modules, lowest first)", [[c["module"], c["cohesion_pct"] if c["cohesion_pct"] is not None else "n/a", c["intra_edges"], c["outbound_edges"], c["inbound_edges"]] for c in coh],
                  ["module", "cohesion %", "intra", "outbound", "inbound"], note="inbound is the blast radius used in the score"))
parts.append(fold("Most referenced assets (own modules)", [[g["asset"], g["type"], g["in_degree"], g["out_degree"]] for g in dep.get("god_nodes", [])[:20]],
                  ["asset", "type", "in", "out"]))
parts.append(fold("Own → marketplace", [[e["from"], e["to"], e["edges"]] for e in dep.get("edges_to_marketplace", [])[:40]], ["from", "to", "refs"]))
parts.append('</section>')

# 4 loops
parts.append('<section id="s4"><h2>4. Flow risk patterns %s</h2>' % badge(summary["verdicts"]["Flow risk patterns"]))
ls = secs.get("loops", {})
parts.append('<p class="sub">instrument: %s · candidates %s · described %s · failed %s · parse mismatch %s</p>' % (
    E(str(ls.get("status"))), ls.get("candidates", "?"), ls.get("described", "?"), ls.get("failed", "?"), ls.get("parse_mismatch", "?")))
if loop_shape:
    parts.append('<div class="kpis">%s</div>' % "".join('<div class="kpi"><b>%s</b><span>%s</span></div>' % (v, E(k.replace("_", " "))) for k, v in loop_shape.items()))
if loops:
    # five columns, not eight: the recommended fix and the full evidence path are in the
    # fix-first table and in app-report.json, and a column nobody can read is not evidence.
    LH = ["severity", "pattern", "microflow", "why it scores", "decision"]
    def lrow(f): return [Raw(sevbadge(f["severity"])), f["pattern"],
                         Raw("%s<br><span class='count'>%s</span>" % (E(f["target"]), E(f["evidence"]))),
                         f["why"], f["decision"]]
    lf = [f for f in findings if f["kind"] == "loop"]
    hi = [f for f in lf if f["severity"] in ("critical", "high")]
    parts.append('<h3>Scored loop findings: %d, of which %d critical or high</h3>' % (len(lf), len(hi)))
    if hi: parts.append(table(LH, [lrow(f) for f in hi], "loops"))
    parts.append(fold("Every scored loop finding, worst first", lf, [], rows_html=table(LH, [lrow(f) for f in lf], "loops")))
# the dossier's reading comes after the scored list: the list says what to fix, the reading says why
parts.append(dossier_block("Flow risk patterns"))
if loops:
    lrows = []
    for qn, r in sorted(loops.get("microflows", {}).items(), key=lambda kv: (not kv[1].get("reachable_from_scheduled_events"), kv[0])):
        il = r.get("in_loop", {})
        if not il and not r.get("nested_loop_lines") and not r.get("transaction_action_lines"): continue
        lrows.append([qn, ", ".join("%s×%d" % kv for kv in sorted(il.items())), len(r.get("nested_loop_lines", [])),
                      len(r.get("transaction_action_lines", [])), ", ".join(r.get("reachable_from_scheduled_events", [])),
                      "%s/%s" % (r.get("loops_parsed"), r.get("loops_catalog", "?"))])
    parts.append(fold("Raw facts: loop microflows whose loop bodies do something (%d of %d)" % (len(lrows), len(loops.get("microflows", {}))),
        lrows, ["microflow", "in loop body", "nested", "tx actions", "scheduled events", "loops parsed/catalog"], cls="loops",
        note="marketplace modules included; the scored table above is own modules only"))
    mm = loops.get("_meta", {}).get("parse_mismatch", [])
    if mm:
        parts.append(fold("Parse mismatches (read by hand)", [[m["microflow"], m["catalog"], m["parsed"]] for m in mm], ["microflow", "catalog", "parsed"]))
parts.append('</section>')

# 5, 6
for n, title, key in [(5, "Security posture", "security"), (6, "Lint baseline", "lint_baseline")]:
    parts.append('<section id="s%d"><h2>%d. %s %s</h2><p class="sub">instrument: %s</p>%s</section>' % (
        n, n, title, badge(summary["verdicts"][title]), E(secs.get(key, {}).get("reason", "not in manifest")), dossier_block(title)))

# 7 dead
parts.append('<section id="s7"><h2>7. Dead elements %s</h2>' % badge(summary["verdicts"]["Dead elements"]))
parts.append(dossier_block("Dead elements"))
dead = dep.get("dead_assets_own", [])
by_type, by_mod = {}, {}
for d in dead:
    by_type[d["ObjectType"]] = by_type.get(d["ObjectType"], 0) + 1
    by_mod[d["ModuleName"]] = by_mod.get(d["ModuleName"], 0) + 1
parts.append('<h3>%d candidates in %d own modules</h3>' % (len(dead), len(by_mod)))
parts.append(table(["asset type", "candidates"], sorted(by_type.items(), key=lambda kv: -kv[1])))
parts.append(fold("Top modules by candidate count", sorted(by_mod.items(), key=lambda kv: -kv[1])[:20], ["module", "candidates"]))
parts.append(fold("Every candidate asset", [[d["QualifiedName"], d["ObjectType"], d["ModuleName"]] for d in dead], ["asset", "type", "module"],
                  note="one Find usages check each before any delete"))
parts.append('<p class="legend">Candidates only: the catalog cannot see Java, published REST, workflows or page URLs. Confirm in Studio Pro before any delete.</p></section>')

# 8 dispositions, 9 method
parts.append('<section id="s8"><h2>8. Dispositions %s</h2>%s</section>' % (badge(summary["verdicts"]["Dispositions"]), dossier_block("Dispositions")))
tm = man.get("timings_s", {}); cat = man.get("catalog", {})
parts.append('<section id="s9"><h2>9. Method</h2>%s<h3>Instrument run</h3>%s</section>' % (
    dossier_block("Method"),
    table(["item", "value"], [["mxcli", man.get("mxcli")], ["mpr sha256 (16)", man.get("mpr_sha256_16")], ["catalog build mode", cat.get("build_mode")],
                              ["catalog modules / refs / activities", "%s / %s / %s" % (cat.get("modules"), cat.get("refs"), cat.get("activities"))],
                              ["timings (s)", ", ".join("%s %s" % kv for kv in tm.items())], ["options", json.dumps(man.get("options", {}))]])))

# the same summary as a script block, so the next agent reads one object instead of 27 tables
parts.append('<script type="application/json" id="app-report-data">%s</script>' %
             json.dumps(summary, sort_keys=True).replace("</", "<\\/"))

page = """<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>App dossier: %(title)s</title>
<style>
  :root { --bg:#f8fafc; --surface:#fff; --ink:#1e293b; --ink-soft:#64748b; --ink-faint:#94a3b8; --line:#e2e8f0; --accent:#0f4c81;
          --pass-bg:#dcfce7; --pass-ink:#166534; --fail-bg:#fee2e2; --fail-ink:#991b1b; --warn-bg:#fef3c7; --warn-ink:#92400e;
          --fault-bg:#fce7f3; --fault-ink:#9d174d; --skip-bg:#e2e8f0; --skip-ink:#334155; --radius:10px;
          --crit-bg:#7f1d1d; --crit-ink:#fff;
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
  .badge.crit { background:var(--crit-bg); color:var(--crit-ink); }
  .exec { border:2px solid var(--accent); } .exec h2 { font-size:20px; } .lede { margin:6px 0; max-width:95ch; }
  .hstate { font:700 13px/1 var(--font); padding:6px 12px; border-radius:999px; text-transform:uppercase; letter-spacing:.06em; }
  .hstate.pass { background:var(--pass-bg); color:var(--pass-ink); } .hstate.fail { background:var(--crit-bg); color:var(--crit-ink); }
  .hstate.warn { background:var(--warn-bg); color:var(--warn-ink); } .hstate.fault { background:var(--fault-bg); color:var(--fault-ink); }
  .kpi.k-crit b { color:var(--crit-bg); } .kpi.k-fail b { color:var(--fail-ink); } .kpi.k-warn b { color:var(--warn-ink); } .kpi.k-fault b { color:var(--fault-ink); }
  details { border-top:1px solid var(--line); margin:10px 0 0; } details summary { cursor:pointer; padding:10px 2px; font-size:14px; color:var(--ink-soft); text-transform:uppercase; letter-spacing:.04em; }
  details summary b { color:var(--ink); font-weight:600; } details[open] summary { border-bottom:1px solid var(--line); }
  .count { font:400 12px var(--mono); color:var(--ink-faint); text-transform:none; letter-spacing:0; }
  table.fixfirst td:first-child, table.loops td:first-child { font-family:var(--font); }
</style></head><body>%(body)s
<footer style="text-align:center;color:var(--ink-faint);font-size:12px;padding:16px">rendered by bin/app-report.sh · facts by project-bin/app-facts.sh · judgement per skills/app-analysis.md</footer>
</body></html>""" % {"title": E(P.get("name") or man.get("mpr", "")), "body": "\n".join(parts)}

os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
open(OUT, "w", encoding="utf-8").write(page)
SIDE = re.sub(r"\.html?$", "", OUT) + ".json"
json.dump(summary, open(SIDE, "w", encoding="utf-8"), indent=1, sort_keys=True)
print("==> wrote %s" % OUT)
print("==> wrote %s" % SIDE)
print("    health: %s (%s) · review progress: %s" % (health_state, ", ".join("%s %d" % (s, sev_counts[s]) for s in SEVS), review_state))
print("    verdicts: " + ", ".join("%s=%s" % (k, v) for k, v in summary["verdicts"].items()))
PY
