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
      # the denominator the old page never printed: most loop bodies do nothing worth a finding
      "bodies_doing_nothing_scored": sum(1 for r in mfs.values()
          if not ({"RETRIEVE_DB", "DELETE", "COMMIT", "REST_CALL"} & set(r.get("in_loop", {})))
          and not r.get("transaction_action_lines") and not r.get("nested_loop_lines")),
      "scheduled_reachable": sum(1 for r in mfs.values() if r.get("reachable_from_scheduled_events")),
      # older facts have no enabled split; then every reachable loop counts as enabled-reachable
      "scheduled_reachable_enabled": sum(1 for r in mfs.values() if r.get("reachable_from_scheduled_events_enabled", r.get("reachable_from_scheduled_events"))),
      "catalog_undercount": loops.get("_meta", {}).get("catalog_undercount", 0),
      "parse_mismatch": len(loops.get("_meta", {}).get("parse_mismatch", [])),
    }

# ---- plain language: every code this page can print, in words a reader can use ---------------
# The page is read by a Mendix developer who has never seen this tool and by a manager who
# reads the first screen. A code printed without its sentence is not a finding, it is a
# password. Nothing may reach the HTML unless it has a line here, and the test enforces that.
TERMS = {
  # the one word the whole loop section rests on
  "loop body": "The actions inside a loop. A loop repeats them once for every item in a list, so an action in the loop body with 10,000 items runs 10,000 times.",
  "loop": "An activity that walks a list and repeats the same actions for every item in it.",
  # patterns, loops
  "LOOP_TQ": "A database query inside a loop body. Each item in the list becomes its own round trip to the database.",
  "LOOP_COMMIT_DEFERRED": "A save inside a loop body. Each item is written to the database on its own instead of the whole list at once.",
  "REST_IN_LOOP": "A web service call inside a loop body. Each item waits for a network round trip, and one slow remote answer stalls the whole run.",
  "END_TRANSACTION": "A transaction started or ended inside a loop body. The run stops being one unit of work, so a failure halfway leaves the data half changed.",
  "LOOP_NESTED": "A loop inside another loop. The inner actions run once per outer item per inner item, so the cost multiplies rather than adds.",
  # patterns, dependencies and dead code
  "DEP_TANGLE": "A group of modules that can all reach each other, directly or through the others. None of them can be understood, tested or taken out on its own.",
  "DEP_PAIR": "Two modules that reference each other in both directions, so neither one can be built or reviewed without the other.",
  "DEP_COHESION": "A module that spends most of its references on other modules rather than on itself, so its name no longer says where its work happens.",
  "DEAD_CANDIDATES": "Assets with no reference anywhere in the catalog. Candidates for deletion, not proof: the catalog cannot see Java code, published web services or page URLs.",
  # what the parser records inside a loop body
  "RETRIEVE_DB": "A retrieve from the database.",
  "RETRIEVE_ASSOC": "A retrieve over an association from an object already in memory. Usually cheap, so it is not scored.",
  "COMMIT": "An object written to the database.",
  "DELETE": "An object deleted from the database.",
  "REST_CALL": "A call out to a web service.",
  "ROLLBACK": "An object rolled back, which undoes uncommitted changes to it.",
  "JS_CALL": "A call to a JavaScript action. This tool cannot see inside JavaScript, so it is counted and not judged.",
  "MICROFLOW_CALL": "A call to another microflow. What it costs depends on that microflow, which this tool did not follow.",
  "JAVA_CALL": "A call to a Java action. This tool cannot see inside Java, so it is counted and not judged.",
  # instrument vocabulary the page prints
  "catalog_undercount": "Loops the text of the microflow shows but the catalog does not list. The catalog only records top level activities, so a loop nested inside another loop is invisible to it. Expected, not an error.",
  "parse_mismatch": "Microflows where the parser found FEWER loops than the catalog lists. The only direction worth reading by hand, because it means the parser missed something.",
  "rules_not_describable": "Rules this version of mxcli cannot print, so their loop bodies were not read at all.",
  "scheduled event": "A timer inside the app that runs a microflow on its own, with nobody watching. An enabled one is the nightly path.",
  "blast radius": "How many other own modules reference the module a finding sits in. The more there are, the more places a change here can surface.",
  "cohesion": "The share of a module's references that stay inside the module. High means self contained, low means it mostly drives other modules.",
  "god node": "An asset the rest of the app leans on heavily, counted by how many references point at it.",
  "own module": "A module this team wrote. Marketplace modules are context, never findings.",
  "marketplace module": "A module imported from the Mendix Marketplace or another vendor. Not ours to fix.",
  # named thresholds a reader meets in the text. A constant printed without its meaning is a
  # code like any other, and the page prints several of them.
  "MIN_COHESION_PCT": "The share of a module's references that must stay inside it before this tool stops calling it low cohesion. Default 60 percent.",
  "MAX_ATTRIBUTES_PER_ENTITY": "The point at which an entity is counted as wide and worth a look. Default 20 attributes.",
  "MAX_ENTITIES_PER_MODULE": "The point at which a module is counted as a candidate to split. Default 15 entities.",
  "MAX_ACTIVITIES_PER_MICROFLOW": "The point at which a microflow is counted as long and worth a look. Default 25 activities.",
  "WIDE_BLAST_MODULES": "How many distinct own modules must reference a module before a finding inside it scores an extra point. Default 10.",
  "REPEAT_IN_BODY": "How many times the same statement must appear in one loop body before it scores an extra point. Default 3.",
  "BIG_TANGLE_PCT": "The share of own modules a tangle must cover before it scores as a structural decision rather than a defect. Default 25 percent.",
  "LOOP_DB_CALLS_MAX": "How many database calls are tolerated inside a loop body before it is a finding. Default 0.",
  "MAX_PARSE_MISMATCH_PCT": "The share of documents where the parser may read fewer loops than the catalog before the loop section is marked fault. Default 5 percent.",
  "MAX_FANOUT_MODULES": "How many own modules one module may depend on before it counts as a hub. Default 6.",
  "AMPLIFIER_CEILING": "The highest score the amplifiers can produce on their own. It is what stops nesting, repetition and blast radius from making a finding high when nothing runs it unattended.",
  "health": "How risky the app is today, scored from the facts alone. It is the same on a first run and a tenth, and it needs no dossier.",
  "review progress": "How much of the dossier has been decided. A fact about the document, not about the app.",
  "severity": "How bad one finding is: critical, high, medium or low. Scored from the facts, never a decision.",
  "verdict": "One of pass, fail, fault, manual, skipped. These five judge the REVIEW, not the app.",
}
def term(code):
    return TERMS.get(code, "")
# short plain names for the codes that get a table cell of their own
PLAIN = {
  "LOOP_TQ": "database query inside a loop",
  "LOOP_COMMIT_DEFERRED": "save inside a loop",
  "REST_IN_LOOP": "web service call inside a loop",
  "END_TRANSACTION": "transaction control inside a loop",
  "LOOP_NESTED": "a loop inside a loop",
  "DEP_TANGLE": "modules that all reach each other",
  "DEP_PAIR": "two modules referencing each other both ways",
  "DEP_COHESION": "module whose work is mostly elsewhere",
  "DEAD_CANDIDATES": "assets nothing appears to reference",
}

# ---- severity: score every finding from facts only ------------------------------------------
# The weights are the "Severity" table in skills/app-analysis.md; change them there and here
# together, never here alone.
#
# WHY THESE WEIGHTS AND NOT THE FIRST SET. The first version put 187 of 229 findings in one
# band, which is a shrug rather than a finding. Three things caused it, all fixed here:
#
#   1. Blast radius counted REFERENCE EDGES, not modules, and the page then said "depended on
#      by 1707 others" of an app with 73 own modules. It also fired for 43 of those 73, so it
#      lifted nearly every finding equally. It now counts DISTINCT own modules that reference
#      the module, at a bar (WIDE_BLAST_MODULES) only a real hub clears.
#   2. A nested loop was its own finding. A loop inside a loop with nothing in either body
#      costs nothing; nesting is an AMPLIFIER of a query or a save, so that is what it is now.
#   3. A single database query in a loop weighed the same as a web service call in a loop.
#      It does not. A query is a backlog item; a network round trip per item is an outage.
#
#   pattern class   what one iteration costs
#   reach           enabled scheduled event +3, disabled-only +1, neither 0
#   amplifiers      nested loop +1, the same statement 3+ times in one body +1, wide blast +1
#
# AND ONE CEILING, which is what makes the bands mean something: amplifiers alone never reach
# `high`. A finding is high or worse only when something runs it unattended, or when every
# iteration costs a network round trip or a transaction. Everything else tops out at medium,
# which is the honest word for "put it on the backlog".
WIDE_BLAST_MODULES = 10     # distinct OWN modules referencing this one, not reference edges
REPEAT_IN_BODY = 3          # the same statement this many times in one loop body is an amplifier
BIG_TANGLE_PCT = 25         # a tangle covering this share of own modules is a structural decision
MIN_COHESION_PCT = 60
AMPLIFIER_CEILING = 3       # highest score amplifiers alone may produce (top of the medium band)
PATTERN_W = {"REST_IN_LOOP": 4, "END_TRANSACTION": 4, "LOOP_TQ": 1, "LOOP_COMMIT_DEFERRED": 1,
             "DEP_TANGLE": 3, "DEP_PAIR": 2, "DEP_COHESION": 1, "DEAD_CANDIDATES": 1}
UNATTENDED_COST = ("REST_IN_LOOP", "END_TRANSACTION")   # costly per iteration whether scheduled or not
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

own_names = {m["name"] for m in inv.get("modules", []) if m.get("kind") == "own"}
# Distinct own modules referencing this one. `cohesion.inbound_edges` is a WEIGHT (how many
# references), which is why the old page claimed a module was "depended on by 1707 others" in
# an app with 73 own modules. The module count comes from the edge list, one entry per pair.
inbound_mods = {}
for _e in dep.get("edges", []):
    if not own_names or (_e.get("from") in own_names and _e.get("to") in own_names):
        inbound_mods.setdefault(_e["to"], set()).add(_e["from"])
inbound_n = {k: len(v) for k, v in inbound_mods.items()}
def blast(module): return 1 if inbound_n.get(module, 0) >= WIDE_BLAST_MODULES else 0

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
def add(kind, pattern, target, module, score, why, evidence, capped=False):
    if capped: score = min(score, AMPLIFIER_CEILING)
    findings.append({"kind": kind, "pattern": pattern, "target": target, "module": module,
                     "plain": PLAIN.get(pattern, pattern), "means": term(pattern),
                     "score": score, "severity": sev_of(score), "why": why, "evidence": evidence,
                     "recommended_fix": FIX_OF.get(pattern, ""),
                     "decision": decision_for(target, module if kind == "dependency" else "")})

nightly = 0
if loops:
    for qn, r in sorted(loops.get("microflows", {}).items()):
        mod = qn.split(".", 1)[0]
        if own_names and mod not in own_names: continue   # marketplace loops are not ours
        il = r.get("in_loop", {})
        en = r.get("reachable_from_scheduled_events_enabled", r.get("reachable_from_scheduled_events") or [])
        dis = r.get("reachable_from_scheduled_events_disabled", [])
        reach, rwhy = (3, "a timer runs it unattended (enabled scheduled event)") if en else \
                      ((1, "only a switched-off timer reaches it") if dis else (0, "nothing runs it unattended"))
        nested = 1 if r.get("nested_loop_lines") else 0
        b = blast(mod)
        # a nested loop is not a finding on its own: a loop inside a loop with nothing in either
        # body costs nothing. It multiplies whatever the body does, so it is an amplifier here.
        pats = []
        n_tq = il.get("RETRIEVE_DB", 0) + il.get("DELETE", 0)
        if n_tq: pats.append(("LOOP_TQ", n_tq))
        if il.get("COMMIT"): pats.append(("LOOP_COMMIT_DEFERRED", il["COMMIT"]))
        if il.get("REST_CALL"): pats.append(("REST_IN_LOOP", il["REST_CALL"]))
        if r.get("transaction_action_lines"): pats.append(("END_TRANSACTION", len(r["transaction_action_lines"])))
        for p, n in pats:
            rep = 1 if n >= REPEAT_IN_BODY else 0
            amps = []
            if nested: amps.append("the loop sits inside another loop, so the cost multiplies")
            if rep: amps.append("it happens %d times in the same loop body" % n)
            if b: amps.append("%d other own modules reference this module" % inbound_n.get(mod, 0))
            why = "%s, and %s%s" % (PLAIN.get(p, p), rwhy, ("; " + "; ".join(amps)) if amps else "")
            # the ceiling, stated exactly as the page states it: high or worse needs an ENABLED
            # timer or a per-iteration network or transaction cost. A switched-off timer is a
            # loaded gun, worth a medium, but nothing is running it today.
            add("loop", p, qn, mod, PATTERN_W[p] + reach + b + nested + rep, why, "mdl/%s.mdl" % qn,
                capped=(not en and p not in UNATTENDED_COST))
            if en: nightly += 1

tangled = set()
n_own = len(own_names) or len(dep.get("cohesion", []))
for t in dep.get("tangles", {}).get("list", []):
    tangled |= set(t)
    if len(t) < 2: continue
    share = (100.0 * len(t) / n_own) if n_own else 0
    big = (1 if len(t) >= WIDE_BLAST_MODULES else 0) + (1 if share >= BIG_TANGLE_PCT else 0)
    add("dependency", "DEP_TANGLE", "tangle of %d modules" % len(t), t[0], PATTERN_W["DEP_TANGLE"] + 1 + big,
        "%d own modules can each reach every other, %.0f%% of the app. None of them can be tested, "
        "versioned or lifted out on its own, and a change in any one can surface in any of the others."
        % (len(t), share), "dependencies.json tangles")
for p in dep.get("bidirectional_pairs", []):
    if p["a"] in tangled and p["b"] in tangled: continue   # the tangle finding already covers it
    add("dependency", "DEP_PAIR", "%s <-> %s" % (p["a"], p["b"]), p["a"],
        PATTERN_W["DEP_PAIR"] + max(blast(p["a"]), blast(p["b"])),
        "the two modules reference each other in both directions, so neither can be built or reviewed alone",
        "dependencies.json bidirectional_pairs")
for c in dep.get("cohesion", []):
    pct = c.get("cohesion_pct")
    if pct is None or pct >= MIN_COHESION_PCT: continue
    add("dependency", "DEP_COHESION", c["module"], c["module"], PATTERN_W["DEP_COHESION"] + blast(c["module"]),
        "%.0f%% of its references leave the module, below MIN_COHESION_PCT %d, so most of what it does happens elsewhere" % (pct, MIN_COHESION_PCT),
        "dependencies.json cohesion")
dead_n = len(dep.get("dead_assets_own", []))
if dead_n:
    add("dead", "DEAD_CANDIDATES", "%d unreferenced asset%s in own modules" % (dead_n, "" if dead_n == 1 else "s"), "", PATTERN_W["DEAD_CANDIDATES"],
        "nothing in the catalog references them; candidates only, because the catalog cannot see Java, web services or page URLs",
        "dependencies.json dead_assets_own")

findings.sort(key=lambda f: (-f["score"], f["pattern"], f["target"]))
sev_counts = {s: sum(1 for f in findings if f["severity"] == s) for s in SEVS}
undecided = sum(1 for f in findings if f["decision"] == "none" or "no decision" in f["decision"])

# ---- checks: what was looked for, including what was NOT there ------------------------------
# A zero is a result. The old page printed "0 with REST call" as an unlabelled tile among
# fourteen others, so the two patterns that actually take a Mendix runtime down were absent AND
# invisible, and a reader counting 229 findings concluded the app was on fire. Every check
# below renders as a row whether it found something or nothing, with the method that produced
# it, so absence is stated rather than left to be inferred from a missing row.
mfs_all = (loops or {}).get("microflows", {})
def count_loop(pred): return sum(1 for r in mfs_all.values() if pred(r))
loop_described = secs.get("loops", {}).get("described", len(mfs_all))
METHOD_MDL = "every loop-containing microflow was printed as text and its loop bodies read, %s of %s documents" % (
    loop_described, secs.get("loops", {}).get("candidates", loop_described))
checks = []
if loops:
    checks = [
      {"check": "Web service call inside a loop body", "code": "REST_IN_LOOP",
       "count": count_loop(lambda r: "REST_CALL" in r.get("in_loop", {})),
       "reading": "This is the pattern that takes a Mendix runtime down: one network round trip per item, and one slow remote answer stalls the whole run.",
       "method": METHOD_MDL},
      {"check": "Transaction started or ended inside a loop body", "code": "END_TRANSACTION",
       "count": count_loop(lambda r: r.get("transaction_action_lines")),
       "reading": "The other pattern that takes a runtime down: the run stops being one unit of work, so a failure halfway leaves the data half changed.",
       "method": METHOD_MDL + ", including the Java actions that start and end transactions"},
      {"check": "Database query inside a loop body", "code": "LOOP_TQ",
       "count": count_loop(lambda r: "RETRIEVE_DB" in r.get("in_loop", {}) or "DELETE" in r.get("in_loop", {})),
       "reading": "One round trip to the database per item. Costly at scale, survivable, a backlog item unless a timer runs it.",
       "method": METHOD_MDL},
      {"check": "Save inside a loop body", "code": "LOOP_COMMIT_DEFERRED",
       "count": count_loop(lambda r: "COMMIT" in r.get("in_loop", {})),
       "reading": "Each item written on its own instead of the list at once. Same shape as the query above.",
       "method": METHOD_MDL},
      {"check": "A loop inside a loop", "code": "LOOP_NESTED",
       "count": count_loop(lambda r: r.get("nested_loop_lines")),
       "reading": "Not a finding on its own. It multiplies whatever the bodies do, so here it raises the severity of a query or a save in the same microflow.",
       "method": METHOD_MDL},
      {"check": "Loop bodies with nothing in them this tool scores", "code": "",
       "count": count_loop(lambda r: not ({"RETRIEVE_DB", "DELETE", "COMMIT", "REST_CALL"} & set(r.get("in_loop", {})))
                                     and not r.get("transaction_action_lines") and not r.get("nested_loop_lines")),
       "reading": "Loops that only build a list, change objects in memory, or call something this tool did not follow. Not findings.",
       "method": METHOD_MDL},
      {"check": "Microflows where the parser found FEWER loops than the catalog", "code": "parse_mismatch",
       "count": len(loops.get("_meta", {}).get("parse_mismatch", [])),
       "reading": "The only mismatch direction worth reading by hand. Anything above zero means the loop section is blind somewhere.",
       "method": "parsed loop count compared against the catalog for every described document"},
      {"check": "Documents this mxcli could not print at all", "code": "rules_not_describable",
       "count": secs.get("loops", {}).get("rules_not_describable", 0) + secs.get("loops", {}).get("failed", 0),
       "reading": "Their loop bodies were never read, so this section says nothing about them. Open them in Studio Pro.",
       "method": "mxcli describe, per qualified name"},
    ]
worst_absent = [c for c in checks if c["count"] == 0 and c["code"] in UNATTENDED_COST]

blind = [k for k, v in secs.items() if v.get("status") not in ("pass", "skipped")]
core_fault = any(secs.get(k, {}).get("status") != "pass" for k in ("inventory", "dependencies", "loops"))
top_n = sev_counts["critical"] + sev_counts["high"]
# Proportionality. A severity count on its own tells a reader nothing about scale, so the line
# says how big the reading pile is next to how big the app is, and names what was checked and
# found absent. Danger that is not there has to be visible AS absence or the page overstates.
absent_line = ""
if worst_absent:
    names = ", ".join(c["check"].lower() for c in worst_absent)
    absent_line = (" Checked and absent: %s. Those are the two patterns that take a Mendix runtime down, and neither one is in this app." % names
                   if len(worst_absent) == 2 else " Checked and absent: %s." % names)
scale_line = ""
if loop_shape:
    scale_line = " For scale: %s microflows contain a loop, %s of their loop bodies do nothing this tool scores, and %s findings sit on the unattended path." % (
        loop_shape.get("loop_microflows", "?"), loop_shape.get("bodies_doing_nothing_scored", "?"), nightly)
health_state = "unknown" if core_fault else ("at risk" if top_n else ("watch" if sev_counts["medium"] else "ok"))
health_line = {
  "unknown": "The instrument did not collect enough to judge this app. Fix the collection before reading anything below.",
  "at risk": "%d critical and %d high severity findings: that is the reading pile, and it is the whole of it. %d medium ones are a backlog, not an alarm.%s%s" % (
      sev_counts["critical"], sev_counts["high"], sev_counts["medium"], absent_line, scale_line),
  "watch":   "Nothing critical or high. %d medium findings: real, but none of them is run unattended and none costs a network round trip per item.%s%s" % (
      sev_counts["medium"], absent_line, scale_line),
  "ok":      "No medium or worse finding in what was collected. %d low ones remain as candidates.%s" % (sev_counts["low"], absent_line),
}[health_state]
review_state = "not started" if decided_lines == 0 else ("complete" if undecided == 0 else "in progress")

summary = {"generated": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
           "mpr": man.get("mpr"), "mxcli": man.get("mxcli"), "dossier_present": bool(dossier_text),
           "verdicts": {r["section"]: r["verdict"] for r in rows}, "loop_shape": loop_shape,
           "dependency_counts": dep.get("counts", {}), "totals": inv.get("totals", {}),
           "health": {"state": health_state, "line": health_line, "severity": sev_counts,
                      "findings_total": len(findings), "on_nightly_path": nightly,
                      "not_measured": sorted(blind)},
           "checks": checks, "glossary": TERMS,
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
    if not body_rows: return '<p class="empty">Zero rows. This check ran and found nothing, which is a result. If you expected rows here, read section 9, Method, for what this version does not collect.</p>'
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
# The structural finding, if there is one, gets its own paragraph. A tangle covering most of an
# app is a bigger story than any single loop, and as one row among 229 it reads like all the
# others. It is a decision about how the app is built, not a bug someone forgot to fix.
struct = [f for f in findings if f["pattern"] == "DEP_TANGLE"]
if struct:
    s0 = struct[0]
    parts.append('<div class="callout"><b>The structural decision, ahead of every loop on this page.</b> '
                 '%s %s <span class="count">%s</span><br>%s<br><b>What it costs.</b> Every one of those modules '
                 'needs the others to compile, to test and to deploy, so none of them can be released, reused or '
                 'handed to another team on its own. No amount of loop fixing changes that; it is undone one pair '
                 'at a time. <b>Where to start.</b> %s.</div>' % (
                 sevbadge(s0["severity"]), E(s0["plain"]), E(s0["pattern"]), E(s0["why"]),
                 E(s0["recommended_fix"][:1].upper() + s0["recommended_fix"][1:])))
parts.append('<h3>Fix first</h3>')
parts.append(table(["severity", "what it is", "where", "why it scores that", "recommended fix", "decision"],
    [[Raw(sevbadge(f["severity"])),
      Raw("%s<br><span class='count'>%s</span>" % (E(f["plain"]), E(f["pattern"]))),
      f["target"], f["why"], f["recommended_fix"], f["decision"]] for f in findings[:5]], "fixfirst"))
parts.append('<p class="legend"><b>How the score is built,</b> from the facts alone, so it reads the same on a first run and a tenth and the same way on another app. '
             'Start with what one turn of the loop costs (a web service call or transaction control %d, a database query or a save %d), '
             'add +3 when an enabled scheduled event runs it unattended or +1 when only a switched-off one does, '
             'then +1 each for a loop inside a loop, for the same statement %d or more times in one body, and for a module that %d or more other own modules reference. '
             '6 or more is critical, 4 to 5 high, 2 to 3 medium, 1 and under low. '
             '<b>One ceiling makes the bands mean something:</b> those last three never reach high on their own. '
             'A finding is high or worse only when an enabled timer actually runs it today, or when every turn of the loop costs a network round trip or a transaction. '
             'A switched-off timer is a loaded gun and scores a medium; nothing is running it. '
             'Weights: skills/app-analysis.md, table "Severity".</p>' % (
             PATTERN_W["REST_IN_LOOP"], PATTERN_W["LOOP_TQ"], REPEAT_IN_BODY, WIDE_BLAST_MODULES))
# what was looked for and not found. A zero is a result, and it renders as a row.
if checks:
    parts.append('<h3>What was checked, including what was not there</h3>')
    parts.append('<p class="lede"><b>Method, once, for every row below it applies to:</b> %s. Every one of those documents was read whether it turned out to hold anything or not.</p>' % E(METHOD_MDL))
    parts.append(table(["check", "found", "what the number means", "method, where it differs"],
        [[Raw("%s%s" % (E(c["check"]), (" <span class='count'>%s</span>" % E(c["code"])) if c["code"] else "")),
          Raw('<b class="%s">%d</b>' % ("zero" if c["count"] == 0 else "nonzero", c["count"])),
          c["reading"], "" if c["method"] == METHOD_MDL else c["method"]] for c in checks], "checks"))
    parts.append('<p class="legend">A count of 0 is a measured result, not a missing row. It means the check ran over every document named above and found none.</p>')
parts.append('<p class="lede"><b>Review progress: %s.</b> %d of %d disposition lines carry a decision; %d of %d scored findings still have none. This is a fact about the document, not about the app: an app can be healthy with nothing decided, and fully decided while still at risk.</p>' % (
    E(review_state), decided_lines, len(disp_lines), undecided, len(findings)))
parts.append('<p class="lede"><b>Not measured.</b> %s. Nothing below covers those; treat them as unknown, not clean.</p>' % (
    E(", ".join(NOT_MEASURED.get(b, b) for b in sorted(blind))) if blind else "Every section this version collects was collected"))
parts.append('<p class="legend">For an agent picking this up later: read <code>app-report.json</code> next to this page, or the <code>app-report-data</code> script block in it. Same numbers, no table parsing.</p>')
parts.append('</section>')

# 0b the words. Every code this page can print has a sentence here, and the sentence is also
# carried next to the code where it appears. A reader met LOOP_TQ and had to ask what a loop
# body was; that is the defect this section and the plain-name columns exist to close.
parts.append('<section id="s0b"><h2>The words this report uses</h2>')
parts.append('<p class="lede">Every code on this page is listed here with what it means. '
             'The one to read first: <b>loop body</b>. %s</p>' % E(TERMS["loop body"]))
GLOSS_ORDER = ["loop", "loop body", "scheduled event", "own module", "marketplace module",
               "LOOP_TQ", "LOOP_COMMIT_DEFERRED", "REST_IN_LOOP", "END_TRANSACTION", "LOOP_NESTED",
               "RETRIEVE_DB", "RETRIEVE_ASSOC", "COMMIT", "DELETE", "ROLLBACK", "REST_CALL", "MICROFLOW_CALL", "JAVA_CALL", "JS_CALL",
               "DEP_TANGLE", "DEP_PAIR", "DEP_COHESION", "cohesion", "god node", "blast radius",
               "DEAD_CANDIDATES", "catalog_undercount", "parse_mismatch", "rules_not_describable",
               "health", "review progress", "severity", "verdict"]
gloss = [k for k in GLOSS_ORDER if k in TERMS] + [k for k in sorted(TERMS) if k not in GLOSS_ORDER]
parts.append('<div class="tw"><table class="gloss"><thead><tr><th>term</th><th>what it means</th></tr></thead><tbody>%s</tbody></table></div>' %
    "".join('<tr id="t-%s"><td>%s%s</td><td>%s</td></tr>' % (
        re.sub(r"[^a-z0-9]+", "-", k.lower()), E(k),
        ("<br><span class='count'>%s</span>" % E(PLAIN[k])) if k in PLAIN else "", E(v))
        for k, v in ((g, TERMS[g]) for g in gloss)))
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
parts.append('<section id="s3"><h2>3. Dependency shape: how modules lean on each other %s</h2>' % badge(summary["verdicts"]["Dependency shape"]))
DEP_KPI = {"own_edges": "module pairs that reference each other", "bidirectional_pairs": "pairs referencing both ways",
           "tangles": "groups where every module reaches every other", "largest_tangle": "modules in the largest such group",
           "three_cycles": "loops of three modules or fewer", "dead_assets_own": "assets nothing references"}
parts.append('<div class="kpis">%s</div>' % "".join('<div class="kpi"><b>%s</b><span>%s</span></div>' % (E(str(C.get(k, "?"))), E(DEP_KPI.get(k, k.replace("_", " "))))
             for k in ["own_edges", "bidirectional_pairs", "tangles", "largest_tangle", "three_cycles", "dead_assets_own"]))
parts.append(dossier_block("Dependency shape"))
parts.append('<p class="lede"><b>What a tangle is.</b> %s</p>' % E(TERMS["DEP_TANGLE"]))
parts.append(fold("Tangles (groups of modules that can all reach each other)", [[i + 1, len(t), ", ".join(t)] for i, t in enumerate(dep.get("tangles", {}).get("list", []))],
                  ["#", "modules", "members"]))
parts.append(fold("Bidirectional pairs",
    [[p["a"], p["b"], p["a_to_b"], ", ".join("%s %d" % kv for kv in sorted(p["a_to_b_kinds"].items(), key=lambda x: -x[1])),
      p["b_to_a"], ", ".join("%s %d" % kv for kv in sorted(p["b_to_a_kinds"].items(), key=lambda x: -x[1]))] for p in dep.get("bidirectional_pairs", [])],
    ["A", "B", "A→B", "kinds", "B→A", "kinds"]))
coh = dep.get("cohesion", [])
below = [c for c in coh if c["cohesion_pct"] is not None and c["cohesion_pct"] < MIN_COHESION_PCT]
parts.append('<h3>Cohesion: %d of %d own modules sit below MIN_COHESION_PCT %d</h3>' % (len(below), len(coh), MIN_COHESION_PCT))
parts.append(fold("Cohesion (own modules, lowest first)",
                  [[c["module"], c["cohesion_pct"] if c["cohesion_pct"] is not None else "n/a", c["intra_edges"], c["outbound_edges"],
                    c["inbound_edges"], inbound_n.get(c["module"], 0)] for c in coh],
                  ["module", "cohesion %", "references inside it", "references it makes outward", "references pointing at it", "modules pointing at it"],
                  note="the last column, not the one before it, is the blast radius in the score"))
parts.append('<p class="legend">The two right-hand columns are different things and the earlier version of this page confused them. '
             '"references pointing at it" counts individual references and runs into the thousands; "modules pointing at it" counts distinct own modules and cannot exceed %d. '
             'Only the second one is used in the severity score, at %d or more. %s</p>' % (len(own_names) or len(coh), WIDE_BLAST_MODULES, E(TERMS["blast radius"])))
parts.append(fold("Most referenced assets (own modules)", [[g["asset"], g["type"], g["in_degree"], g["out_degree"]] for g in dep.get("god_nodes", [])[:20]],
                  ["asset", "type", "references pointing at it", "references it makes"], note=TERMS["god node"]))
parts.append(fold("Own → marketplace", [[e["from"], e["to"], e["edges"]] for e in dep.get("edges_to_marketplace", [])[:40]], ["from", "to", "refs"]))
parts.append('</section>')

# 4 loops
parts.append('<section id="s4"><h2>4. Flow risk patterns: what loops do %s</h2>' % badge(summary["verdicts"]["Flow risk patterns"]))
ls = secs.get("loops", {})
# the definition goes where the reader meets the thing, not in a skill file they will not open
parts.append('<p class="lede"><b>Read this first.</b> %s %s A microflow that loops is not a problem. '
             'What matters is what sits in the loop body, because that is what repeats.</p>' % (E(TERMS["loop"]), E(TERMS["loop body"])))
parts.append('<p class="sub">instrument: %s · loop-containing documents found %s · read as text %s · could not be read %s · read fewer loops than the catalog lists %s</p>' % (
    E(str(ls.get("status"))), ls.get("candidates", "?"), ls.get("described", "?"), ls.get("failed", "?"), ls.get("parse_mismatch", "?")))
if loop_shape:
    # plain labels, and the two that mean nothing without a sentence carry one
    KPI_LABEL = {
      "loop_microflows": "documents containing a loop", "with_db_retrieve": "with a database query in the loop body",
      "with_commit": "with a save in the loop body", "with_delete": "with a delete in the loop body",
      "with_rest_call": "with a web service call in the loop body", "with_nested_loop": "with a loop inside a loop",
      "with_microflow_call_only": "whose loop body only calls another microflow",
      "with_transaction_actions": "with transaction control in the loop body",
      "bodies_doing_nothing_scored": "whose loop body does nothing scored here",
      "scheduled_reachable": "reachable from any scheduled event", "scheduled_reachable_enabled": "reachable from an ENABLED scheduled event",
      "catalog_undercount": "loops the catalog cannot see (expected)", "parse_mismatch": "parser read fewer loops than the catalog",
    }
    KPI_TERM = {"with_db_retrieve": "LOOP_TQ", "with_commit": "LOOP_COMMIT_DEFERRED", "with_delete": "DELETE",
                "with_rest_call": "REST_IN_LOOP", "with_nested_loop": "LOOP_NESTED",
                "with_transaction_actions": "END_TRANSACTION", "with_microflow_call_only": "MICROFLOW_CALL",
                "catalog_undercount": "catalog_undercount", "parse_mismatch": "parse_mismatch",
                "scheduled_reachable": "scheduled event", "scheduled_reachable_enabled": "scheduled event",
                "loop_microflows": "loop", "bodies_doing_nothing_scored": "loop body"}
    parts.append('<div class="kpis">%s</div>' % "".join(
        '<div class="kpi %s" title="%s"><b>%s</b><span>%s</span></div>' % (
            "k-zero" if v == 0 else "", E(term(KPI_TERM.get(k, ""))), v, E(KPI_LABEL.get(k, k.replace("_", " "))))
        for k, v in loop_shape.items()))
    parts.append('<p class="legend">A tile reading 0 is a measured zero, not a gap: the check ran over every document that was read. '
                 '<code>catalog undercount</code> is not a defect: %s</p>' % E(TERMS["catalog_undercount"]))
if loops:
    # five columns, not eight: the recommended fix and the full evidence path are in the
    # fix-first table and in app-report.json, and a column nobody can read is not evidence.
    LH = ["severity", "what it is", "microflow", "why it scores that", "decision"]
    def lrow(f): return [Raw(sevbadge(f["severity"])),
                         Raw("%s<br><span class='count'>%s</span>" % (E(f["plain"]), E(f["pattern"]))),
                         Raw("%s<br><span class='count'>%s</span>" % (E(f["target"]), E(f["evidence"]))),
                         f["why"], f["decision"]]
    lf = [f for f in findings if f["kind"] == "loop"]
    hi = [f for f in lf if f["severity"] in ("critical", "high")]
    parts.append('<h3>The %d loop findings worth reading, out of %d scored</h3>' % (len(hi), len(lf)))
    if hi:
        parts.append('<p class="lede">These are the only loop findings that are run unattended or that cost a network round trip or a transaction per item. The rest are a backlog.</p>')
        parts.append(table(LH, [lrow(f) for f in hi], "loops"))
    else:
        parts.append('<p class="lede">None. Every scored loop finding is medium or low, which means no loop in an own module is both costly per turn and run unattended. That is a measured result over %s, not an empty section.</p>' % E(METHOD_MDL))
    parts.append(fold("The backlog: every scored loop finding, worst first", lf, [], rows_html=table(LH, [lrow(f) for f in lf], "loops")))
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
        lrows, ["microflow", "in the loop body", "loops inside loops", "transaction actions", "scheduled events reaching it", "loops read / loops the catalog lists"], cls="loops",
        note="marketplace modules included; the scored table above is own modules only"))
    parts.append('<p class="legend">Codes in the "in the loop body" column: %s</p>' %
                 E(" · ".join("%s: %s" % (k, TERMS[k]) for k in ["RETRIEVE_DB", "RETRIEVE_ASSOC", "COMMIT", "DELETE", "ROLLBACK", "REST_CALL", "MICROFLOW_CALL", "JAVA_CALL", "JS_CALL"])))
    mm = loops.get("_meta", {}).get("parse_mismatch", [])
    parts.append('<h3>Where this section is blind</h3>')
    parts.append(table(["blind spot", "count", "what it means"], [
        [Raw("parse_mismatch"), len(mm), TERMS["parse_mismatch"]],
        [Raw("rules_not_describable"), ls.get("rules_not_describable", 0), TERMS["rules_not_describable"]],
        [Raw("catalog_undercount"), loops.get("_meta", {}).get("catalog_undercount", 0), TERMS["catalog_undercount"]],
        [Raw("inside Java and JavaScript actions"), "not readable", "This tool reads microflow text. It cannot see what a Java or JavaScript action does, so a query hidden inside one is invisible here."],
    ]))
    if mm:
        parts.append(fold("Parse mismatches (read by hand)", [[m["microflow"], m["catalog"], m["parsed"]] for m in mm], ["microflow", "loops the catalog lists", "loops the parser read"]))
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
  table.fixfirst td:first-child, table.loops td:first-child, table.checks td:first-child, table.gloss td:first-child { font-family:var(--font); }
  .callout { border:2px solid var(--crit-bg); background:#fff1f2; border-radius:8px; padding:12px 14px; margin:12px 0; max-width:95ch; }
  .callout b { color:var(--crit-bg); }
  table.checks b.zero { color:var(--pass-ink); font-size:18px; } table.checks b.nonzero { color:var(--warn-ink); font-size:18px; }
  table.checks td:nth-child(2) { text-align:center; } table.gloss td:first-child { font-weight:600; white-space:nowrap; }
  table.gloss td:last-child { max-width:80ch; } .kpi.k-zero b { color:var(--pass-ink); }
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
