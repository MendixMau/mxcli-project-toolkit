#!/usr/bin/env bash
# app-facts.sh — collect the FACTS an app dossier is written from. No opinions.
#
# WHAT THIS IS. The instrument behind skills/app-analysis.md. It rebuilds the catalog, then
# writes a small set of JSON/TSV files under analysis/app-facts/ that the dossier author (an
# agent following the skill, or a person) turns into verdicts. Per skills-over-scripts.md, every
# threshold, every "this is bad" and every disposition lives in the skill, not here. This
# script only does what a reader cannot do by hand: rebuild a catalog, walk thousands of edges,
# describe hundreds of microflows and parse their loop bodies.
#
# WHY THESE FACTS AND NOT `mxcli graph-report` ALONE (probed on four projects, 2026-09-15):
#   - The catalog is silently EMPTY in fast build mode and silently INCOMPLETE after an mxcli
#     upgrade (21 tables missing on one project, no error anywhere). Only a full rebuild fixes
#     both, so step 1 always forces one and step 2 refuses to run on a schema that is short.
#   - The stock graph_module_* views derive the module from the text before the first dot.
#     That invents a phantom "Navigation" module from navigation profiles and breaks on a
#     widget ref whose target has no dot. Everything here joins through the real module column.
#   - graph_cycles is asset-level and was EMPTY on a project with four mutually dependent
#     module pairs. Module-level cycles are computed here, each elementary cycle once.
#   - Loop BODIES are not in the catalog: activities are a flat list per microflow with no
#     containment column. `mxcli describe microflow` renders proper `loop ... end loop;`
#     blocks, so step 3 describes only the microflows the catalog says contain a loop and
#     parses those. A describe is NOT cheap on a big model: ~31 s each on a 17,500-unit app
#     (1,917 described in 2 h 45 at 6 workers, field report #297), because each call loads the
#     model. So step 3 is incremental (below).
#
# INCREMENTAL SWEEP (#297). manifest.json keeps a {UnitID: ContentsHash} snapshot of the .mpr
# Unit table (the hash taken from the .mxunit bytes, which the column normally equals; see
# mx-metadata-note.py units for why the bytes win), and an index of which unit state each mdl/ file was described from. A refresh
# re-describes only a candidate whose unit is new, changed (hash), moved (module/folder path)
# or has no output yet; it keeps every other mdl/ file and deletes the outputs of units that are
# gone or no longer loop. UnitID -> name comes from mx-metadata-note.py (beside this script):
# the same mapping that writes the Studio Pro History note. A full sweep runs when asked
# (--full), on the first run, when the mxcli version changed, or when the unit table cannot be
# read (MPR v1, helper missing); the manifest says which and why. Incremental output is
# byte-identical to a full sweep on the same model (tests/wave2/test-app-facts-incremental.sh).
#
# Read-only for the model. Runs `mxcli graph-report` (rewrites .mxcli/catalog.db, never the
# .mpr) and `mxcli describe` (pure read). Never `exec`, never `apply`.
#
# Usage:
#   bin/app-facts.sh                         # everything, facts to analysis/app-facts/
#   bin/app-facts.sh --facts-dir DIR         # elsewhere
#   bin/app-facts.sh --skip-loops            # steps 1-2 only (seconds, not minutes)
#   bin/app-facts.sh --workers N             # parallel describe calls for step 3 (default 4)
#   bin/app-facts.sh --max-loops N           # cap the loop sweep (a first look at a huge app)
#   bin/app-facts.sh --full                  # re-describe every candidate, ignoring the index
#   bin/app-facts.sh --freshness             # one line: units changed since the last map (status.sh)
#   bin/app-facts.sh --parse-only DIR        # re-parse already-described MDL in DIR/mdl (tests)
#
# Outputs (all under the facts dir):
#   manifest.json        what ran, versions, counts, timings, and a status per section:
#                        pass | fault | skipped — a section that did not run is never absent;
#                        plus units.snapshot {UnitID: ContentsHash} and mdl_index (incremental)
#   graph-report.json    mxcli's own report, kept verbatim for cross-checking
#   inventory.json       project, modules (kind, sizes), scheduled events
#   dependencies.json    module edges, bidirectional pairs, cycles, god nodes, cohesion, dead
#   loops.json           per loop-containing microflow: what its loop bodies do
#   mdl/*.mdl            the described microflows (kept: the evidence behind loops.json)
#
# Exit: 0 facts written · 2 instrument fault (nothing to trust — fix the cause, rerun)
# There is deliberately no exit 1: this script measures, it never judges.

set -uo pipefail

if [ -f "$(dirname "${BASH_SOURCE[0]}")/_common.sh" ]; then
  . "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
fi
if ! type require_py >/dev/null 2>&1; then
  require_py() {
    _c=""
    for _c in python3 python py; do  # portability-ok: this IS the interpreter probe
      case "$(command -v "$_c" 2>/dev/null)" in *[Ww]indows[Aa]pps*) continue ;; esac
      if "$_c" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then
        PY="$_c"; export PY; return 0
      fi
    done
    echo "app-facts: Python 3 is required and was not found (tried python3, python, py)." >&2  # portability-ok: names in a diagnostic
    exit 2
  }
fi
require_py

FACTS_DIR=""
SKIP_LOOPS=0
WORKERS=4
MAX_LOOPS=0
PARSE_ONLY=""
FULL=0
FRESHNESS=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNITS_PY="$SCRIPT_DIR/mx-metadata-note.py"
while [ $# -gt 0 ]; do
  case "$1" in
    --facts-dir)  FACTS_DIR="${2:-}"; shift 2 ;;
    --skip-loops) SKIP_LOOPS=1; shift ;;
    --workers)    WORKERS="${2:-4}"; shift 2 ;;
    --max-loops)  MAX_LOOPS="${2:-0}"; shift 2 ;;
    --parse-only) PARSE_ONLY="${2:-}"; shift 2 ;;
    --full)       FULL=1; shift ;;
    --freshness)  FRESHNESS=1; shift ;;
    -h|--help)    sed -n '2,62p' "$0"; exit 0 ;;
    *) echo "app-facts: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------------------------
# The loop-body parser. One Python program, used by step 3 and by --parse-only, so the test
# suite can run it on captured MDL with no mxcli and no .mpr. It records WHAT a loop body
# contains; the skill says which of those are a problem and when.
# ---------------------------------------------------------------------------------------------
PARSER='
import json, os, re, sys

MDL_DIR   = sys.argv[1]
EXPECTED  = json.load(open(sys.argv[2])) if len(sys.argv) > 2 and os.path.exists(sys.argv[2]) else {}
SCHEDULED = json.load(open(sys.argv[3])) if len(sys.argv) > 3 and os.path.exists(sys.argv[3]) else {}

STRIP_ASSIGN = re.compile(r"^\$\w+\s*=\s*")
KIND_RULES = [
    # (kind, test) — first match wins; tests run on the statement with a leading "$x = " removed
    ("REST_CALL",     lambda s: "rest call" in s),
    ("MICROFLOW_CALL",lambda s: s.startswith("call microflow")),
    ("JAVA_CALL",     lambda s: s.startswith("call java action")),
    ("JS_CALL",       lambda s: s.startswith("call javascript action")),
    ("COMMIT",        lambda s: s.startswith("commit ")),
    ("COMMIT",        lambda s: (s.startswith("change ") or s.startswith("create ")) and re.search(r"\bcommit\b", s) is not None),
    ("ROLLBACK",      lambda s: s.startswith("rollback")),
    ("DELETE",        lambda s: s.startswith("delete ")),
    ("RETRIEVE_DB",   lambda s: s.startswith("retrieve ") and not re.search(r"\bfrom\s+\$", s)),
    ("RETRIEVE_ASSOC",lambda s: s.startswith("retrieve ") and re.search(r"\bfrom\s+\$", s) is not None),
]
TX_RE = re.compile(r"(Start|End)Transaction", re.I)

def parse(text):
    depth = 0
    loops = 0
    body = {}           # kind -> [line numbers]
    nested = []
    tx = []
    for n, raw in enumerate(text.splitlines(), 1):
        s = raw.strip()
        if not s or s[0] in "@/*":       # positions, captions, comments
            continue
        # Two loop syntaxes: `loop $x in $list ... end loop;` and the Studio Pro 10 while loop,
        # `while <condition> ... end while;` (found 2026-09-15 as the only two parsed < catalog cases
        # on a real app; the catalog counts both as LoopedActivity).
        if s.startswith("end loop") or s.startswith("end while"):
            depth = max(0, depth - 1)
            continue
        if s.startswith("loop ") or s.startswith("while "):
            loops += 1
            depth += 1
            if depth >= 2:
                nested.append(n)
            continue
        if TX_RE.search(s):
            tx.append(n)
        if depth == 0:
            continue
        st = STRIP_ASSIGN.sub("", s)
        for kind, test in KIND_RULES:
            if test(st):
                body.setdefault(kind, []).append(n)
                break
    return loops, body, nested, tx

out = {"_meta": {"files": 0, "parsed": 0, "parse_mismatch": [], "catalog_undercount": 0, "unreadable": []}, "microflows": {}}
for fn in sorted(os.listdir(MDL_DIR)):
    if not fn.endswith(".mdl"):
        continue
    qn = fn[:-4]
    out["_meta"]["files"] += 1
    try:
        text = open(os.path.join(MDL_DIR, fn), encoding="utf-8", errors="replace").read()
    except OSError as e:
        out["_meta"]["unreadable"].append(qn); continue
    if "create or modify" not in text and "loop " not in text and "while " not in text:
        out["_meta"]["unreadable"].append(qn); continue
    loops, body, nested, tx = parse(text)
    rec = {"loops_parsed": loops, "in_loop": {k: len(v) for k, v in body.items()},
           "in_loop_lines": body, "nested_loop_lines": nested, "transaction_action_lines": tx}
    exp = EXPECTED.get(qn)
    if exp is not None:
        rec["loops_catalog"] = exp
        # The catalog holds TOP-LEVEL activities only (verified 2026-09-15: a microflow with a
        # nested loop has one LoopedActivity row and none of the body activities). So parsed >
        # catalog is expected whenever loops nest; only parsed < catalog means the parser missed one.
        # mxcli v0.25.0 also catalogs loop-body activities, so there the two can match; the
        # check holds on either version. The loop parser reads v0.25 DESCRIBE unchanged.
        if loops < exp:
            out["_meta"]["parse_mismatch"].append({"microflow": qn, "catalog": exp, "parsed": loops})
        elif loops > exp:
            out["_meta"]["catalog_undercount"] += 1
    if qn in SCHEDULED:
        # loops-scheduled.json is either a plain list (older facts) or {"enabled": [...], "disabled": [...]}.
        # A loop that only a disabled event reaches is a different risk from one a live event runs nightly.
        s = SCHEDULED[qn]
        if isinstance(s, dict):
            rec["reachable_from_scheduled_events"] = sorted(set(s.get("enabled", [])) | set(s.get("disabled", [])))
            rec["reachable_from_scheduled_events_enabled"] = sorted(s.get("enabled", []))
            rec["reachable_from_scheduled_events_disabled"] = sorted(s.get("disabled", []))
        else:
            rec["reachable_from_scheduled_events"] = s
    out["microflows"][qn] = rec
    out["_meta"]["parsed"] += 1
json.dump(out, sys.stdout, indent=1, sort_keys=True)
print()
'

if [ -n "$PARSE_ONLY" ]; then
  [ -d "$PARSE_ONLY/mdl" ] || { echo "app-facts: $PARSE_ONLY/mdl not found" >&2; exit 2; }
  "$PY" -c "$PARSER" "$PARSE_ONLY/mdl" "$PARSE_ONLY/loops-expected.json" "$PARSE_ONLY/loops-scheduled.json" > "$PARSE_ONLY/loops.json" || exit 2
  echo "==> parsed $(ls "$PARSE_ONLY"/mdl/*.mdl 2>/dev/null | wc -l | tr -d ' ') MDL files -> $PARSE_ONLY/loops.json"
  exit 0
fi

# ---------------------------------------------------------------------------------------------
# Discovery
# ---------------------------------------------------------------------------------------------
cd "${PROJECT_ROOT:-.}" || exit 2
if type find_mpr >/dev/null 2>&1; then
  MPR="$(find_mpr)" || exit 2
else
  MPR="$(ls ./*.mpr 2>/dev/null | head -1)"
  [ -n "$MPR" ] || { echo "app-facts: no .mpr here" >&2; exit 2; }
fi
MODEL_DIR="$(cd "$(dirname "$MPR")" && pwd)"
MPR_BASE="$(basename "$MPR")"
DB="$MODEL_DIR/.mxcli/catalog.db"
[ -n "$FACTS_DIR" ] || FACTS_DIR="${PROJECT_ROOT:-.}/analysis/app-facts"

# ---------------------------------------------------------------------------------------------
# --freshness: one line for bin/status.sh. Compares the Unit table now with the snapshot the
# last map stored. No mxcli, no catalog, writes nothing. Silent when there is no map yet.
# ---------------------------------------------------------------------------------------------
if [ "$FRESHNESS" -eq 1 ]; then
  [ -f "$FACTS_DIR/manifest.json" ] || exit 0
  # The unit list goes through a temp file, never an env var or argv: one env string is capped at
  # 128 KB on Linux, ~1,600 units' worth, and the line vanished on exactly the large apps (#297 review).
  NOW_FILE="$(mktemp "${TMPDIR:-/tmp}/app-facts-units.XXXXXX")" || exit 0
  trap 'rm -f "$NOW_FILE"' EXIT
  if "$PY" "$UNITS_PY" units "$MODEL_DIR/$MPR_BASE" --hashes-only > "$NOW_FILE" 2>/dev/null; then NOW_OK=1; else NOW_OK=0; fi
  "$PY" - "$FACTS_DIR/manifest.json" "$NOW_FILE" "$NOW_OK" <<'PY'
import json, sys
try:
    man = json.load(open(sys.argv[1]))
except (OSError, ValueError):
    print("app map: manifest.json unreadable — rerun bin/app-facts.sh"); sys.exit(0)
units = man.get("units") or {}
# The snapshot's own date: a --skip-loops run carries the last loop sweep's snapshot forward.
when = (units.get("snapshot_taken") or man.get("generated") or "?")[:16].replace("T", " ")
snap = units.get("snapshot")
if not snap:
    print("app map: built %s with no unit snapshot — rerun bin/app-facts.sh to track freshness" % when)
elif sys.argv[3] != "1":
    print("app map: built %s; unit table unreadable, freshness unknown" % when)
else:
    cur = dict(l.rstrip("\n").split("\t", 1) for l in open(sys.argv[2], encoding="utf-8") if "\t" in l)
    n = sum(1 for u, h in cur.items() if snap.get(u) != h) + sum(1 for u in snap if u not in cur)
    print("app map: fresh (built %s)" % when if n == 0 else "app map: %d units changed since %s" % (n, when))
PY
  rm -f "$NOW_FILE"; trap - EXIT
  exit 0
fi
mkdir -p "$FACTS_DIR/mdl" || exit 2
FACTS_DIR="$(cd "$FACTS_DIR" && pwd)"

MXCLI="${MXCLI:-}"
if [ -z "$MXCLI" ]; then
  if [ -x "./mxcli" ]; then MXCLI="./mxcli"
  elif command -v mxcli >/dev/null 2>&1; then MXCLI="mxcli"
  else echo "app-facts: mxcli not found (./mxcli or on PATH); set MXCLI=/path/to/mxcli" >&2; exit 2; fi
fi
command -v sqlite3 >/dev/null || { echo "app-facts: sqlite3 not on PATH" >&2; exit 2; }
MX_VERSION="$("$MXCLI" --version 2>/dev/null | head -1)"
# A project-local ./mxcli is often an older pin; its catalog can lack whole tables (seen 2026-09-15:
# a v0.17 pin had no scheduled_events_data and the guard below exits 2). Say so up front.
if [ "$MXCLI" = "./mxcli" ] && command -v mxcli >/dev/null 2>&1; then
  PATH_VERSION="$(mxcli --version 2>/dev/null | head -1)"
  [ "$PATH_VERSION" = "$MX_VERSION" ] || echo "app-facts: using ./mxcli ($MX_VERSION); PATH has $PATH_VERSION. If the catalog guard fails, rerun with MXCLI=mxcli" >&2
fi

START_ALL=$(date +%s)
log() { printf '==> %s\n' "$*"; }

# ---------------------------------------------------------------------------------------------
# Step 1 — full catalog build, via graph-report (one call: the rebuild AND mxcli's own report).
# First run on a cold catalog: ~20-30 s on 1,000-2,700 microflows, 7 min on a 17,500-unit app
# (#297), measured. Not a hang.
# ---------------------------------------------------------------------------------------------
log "step 1: full catalog build + mxcli graph-report ($MPR_BASE)"
T1=$(date +%s)
( cd "$MODEL_DIR" && "$MXCLI" graph-report -p "$MPR_BASE" --format json -o "$FACTS_DIR/graph-report.json" ) > "$FACTS_DIR/graph-report.log" 2>&1
RC=$?
T1=$(( $(date +%s) - T1 ))
if [ $RC -ne 0 ] || [ ! -s "$FACTS_DIR/graph-report.json" ]; then
  echo "FAULT: mxcli graph-report exited $RC — see $FACTS_DIR/graph-report.log" >&2
  tail -5 "$FACTS_DIR/graph-report.log" >&2
  exit 2
fi
[ -f "$DB" ] || { echo "FAULT: $DB not written by graph-report" >&2; exit 2; }

q() { sqlite3 -noheader "$DB" "$1"; }
BUILD_MODE="$(q "SELECT Value FROM catalog_meta WHERE Key='build_mode';")"
# The build_mode LABEL is not checked (fixed 2026-10-13, field report 2026-10-11): mxcli v0.24.0
# labels a complete catalog 'source', and the old `!= full` test refused it on every run. What
# this script needs is checked instead, below: the tables by name, non-empty refs/activities,
# and at least one refs row that carries a RefKind (the dependency facts group by it). The label
# is recorded in manifest.json as found, so a reader can still see it. Zero 'call' edges is NOT a
# fault: an early module reached only from pages and buttons has none, and its call graph is
# legitimately empty — requiring them (the first cut of this fix) refused such apps.
MISSING=""
for t in modules_data entities_data microflows_data activities_data pages_data scheduled_events_data refs catalog_meta projects; do
  [ "$(q "SELECT count(*) FROM sqlite_master WHERE name='$t';")" = "1" ] || MISSING="$MISSING $t"
done
if [ -n "$MISSING" ]; then
  echo "FAULT: catalog schema is missing:$MISSING" >&2
  echo "       This mxcli ($MX_VERSION) wrote a catalog without tables this script reads." >&2
  echo "       A missing table is not zero rows. Refusing to write facts from it." >&2
  exit 2
fi
N_MODULES=$(q "SELECT count(*) FROM modules_data;")
N_REFS=$(q "SELECT count(*) FROM refs;")
N_ACTS=$(q "SELECT count(*) FROM activities_data;")
if [ "${N_MODULES:-0}" -eq 0 ] || [ "${N_REFS:-0}" -eq 0 ] || [ "${N_ACTS:-0}" -eq 0 ]; then
  echo "FAULT: catalog is vacuous (modules=$N_MODULES refs=$N_REFS activities=$N_ACTS, build_mode '${BUILD_MODE:-unset}'). An empty graph is not a clean app." >&2
  exit 2
fi
KINDS="$(q "SELECT k || '=' || n FROM (SELECT COALESCE(NULLIF(RefKind,''),'(none)') k, count(*) n FROM refs GROUP BY k ORDER BY n DESC LIMIT 8);" | paste -sd' ' -)"
N_KINDED=$(q "SELECT count(*) FROM refs WHERE COALESCE(RefKind,'') <> '';")
if [ "${N_KINDED:-0}" -eq 0 ]; then
  echo "FAULT: catalog refs carry no RefKind (build_mode '${BUILD_MODE:-unset}', $N_REFS refs by kind: ${KINDS:-none})." >&2
  echo "       The dependency and call-graph facts are read by kind. Refusing to write facts without one." >&2
  exit 2
fi
log "catalog ok: build_mode=${BUILD_MODE:-unset} modules=$N_MODULES refs=$N_REFS (${KINDS:-none}) activities=$N_ACTS (${T1}s)"

# ---------------------------------------------------------------------------------------------
# Step 2 — inventory + dependencies, straight from the catalog through the REAL module column.
# ---------------------------------------------------------------------------------------------
log "step 2: inventory + dependency facts"
T2=$(date +%s)
# The catalog is opened through mxtk_sqlite_ro_uri (_common.sh): a bare "file:%s?mode=ro" cut the
# path at a '#' or '?' in a folder name, lost mode=ro, and SQLite created and opened an empty file
# beside the model folder. A _common.sh older than this script (or none) lacks the helper: build
# the same URI inline, as require_py and find_mpr fall back above. native_path (when present)
# turns an MSYS /c/... path into C:/... first, as mxtk_model_version does.
DB_NATIVE="$DB"
if type native_path >/dev/null 2>&1; then DB_NATIVE="$(native_path "$DB")"; fi
if type mxtk_sqlite_ro_uri >/dev/null 2>&1; then
  DB_URI="$(mxtk_sqlite_ro_uri "$DB_NATIVE")"
else
  DB_URI="$("$PY" -c "import os,sys,urllib.request as u
print('file:'+u.pathname2url(os.path.abspath(sys.argv[1]))+'?mode=ro')" "$DB_NATIVE" | tr -d '\r')"
fi
[ -n "$DB_URI" ] || { echo "FAULT: could not build a read-only URI for $DB" >&2; exit 2; }
DB="$DB" DB_URI="$DB_URI" FACTS_DIR="$FACTS_DIR" MX_VERSION="$MX_VERSION" MPR_BASE="$MPR_BASE" MAX_LOOPS="$MAX_LOOPS" "$PY" - <<'PY' || exit 2
import json, os, sqlite3, sys, collections

db = sqlite3.connect(os.environ["DB_URI"], uri=True)
db.row_factory = sqlite3.Row
# The shell checked the catalog with the sqlite3 CLI on the plain path; this is a second open. If
# it reached a different file, an empty graph must not be written as the app's facts.
if db.execute("SELECT count(*) FROM sqlite_master WHERE type='table'").fetchone()[0] == 0:
    sys.stderr.write("FAULT: %s opened with 0 tables (URI %s), though the catalog check passed. Refusing to write facts.\n"
                     % (os.environ["DB"], os.environ["DB_URI"]))
    sys.exit(2)
F = os.environ["FACTS_DIR"]
def rows(sql, *a): return [dict(r) for r in db.execute(sql, a)]
def one(sql, *a):  return db.execute(sql, a).fetchone()[0]

# --- modules and their kind -------------------------------------------------------------------
# Source is '' for app-authored modules AND for System (framework, not marketplace). Marketplace
# modules carry 'Marketplace vX.Y.Z'. Atlas_* are normally marketplace-tagged; the name fallback
# is for the project that imported them without metadata (seen: five GenAI modules, blank Source).
FRAMEWORK_BY_NAME = {"System"}
# A marketplace module imported without metadata has a blank Source and would count as own,
# inflating tangles and the low-cohesion list (six or seven such modules on the first real app).
# The project's lint vendor list (.claude/lint-vendor-modules.txt, the same file lint-gate.sh
# excludes) is the one place a team already names them; honour it here too.
VENDOR = set()
vf = os.path.join(os.environ.get("PROJECT_ROOT") or ".", ".claude", "lint-vendor-modules.txt")
if os.path.exists(vf):
    for line in open(vf, encoding="utf-8"):
        line = line.split("#", 1)[0].strip()
        if line: VENDOR.update(x.strip() for x in line.split(",") if x.strip())
def kind(name, source):
    if name in FRAMEWORK_BY_NAME: return "framework"
    if source or name in VENDOR: return "marketplace"
    if name.startswith("Atlas_"): return "framework"
    return "own"

mods = rows("SELECT Name, Source, AppStoreVersion, AppStoreGuid FROM modules_data ORDER BY Name")
kinds = {m["Name"]: kind(m["Name"], m["Source"] or "") for m in mods}
own = sorted(n for n, k in kinds.items() if k == "own")

ent_by_mod = collections.defaultdict(lambda: collections.Counter())
for r in rows("SELECT ModuleName, EntityType, count(*) n FROM entities_data GROUP BY 1,2"):
    ent_by_mod[r["ModuleName"]][r["EntityType"] or "UNKNOWN"] += r["n"]
flow_by_mod = collections.defaultdict(lambda: collections.Counter())
for r in rows("SELECT ModuleName, MicroflowType, count(*) n FROM microflows_data GROUP BY 1,2"):
    flow_by_mod[r["ModuleName"]][r["MicroflowType"] or "UNKNOWN"] += r["n"]
pages_by_mod = {r["ModuleName"]: r["n"] for r in rows("SELECT ModuleName, count(*) n FROM pages_data GROUP BY 1")}
loops_by_mod = {r["ModuleName"]: r["n"] for r in rows(
    "SELECT ModuleName, count(*) n FROM activities_data WHERE ActivityType='LoopedActivity' GROUP BY 1")}
big_flows = {r["ModuleName"]: r["n"] for r in rows(
    "SELECT ModuleName, count(*) n FROM microflows_data WHERE ActivityCount >= 25 GROUP BY 1")}
wide_ents = {r["ModuleName"]: r["n"] for r in rows(
    "SELECT ModuleName, count(*) n FROM entities_data WHERE AttributeCount >= 20 GROUP BY 1")}

modules = []
for m in mods:
    n = m["Name"]
    modules.append({
        "name": n, "kind": kinds[n], "source": m["Source"] or "",
        "marketplace_version": m["AppStoreVersion"] or "", "marketplace_guid": m["AppStoreGuid"] or "",
        "entities": dict(ent_by_mod.get(n, {})), "entities_total": sum(ent_by_mod.get(n, {}).values()),
        "microflows": flow_by_mod.get(n, {}).get("MICROFLOW", 0),
        "nanoflows": flow_by_mod.get(n, {}).get("NANOFLOW", 0),
        "pages": pages_by_mod.get(n, 0), "loop_activities": loops_by_mod.get(n, 0),
        "microflows_25plus_activities": big_flows.get(n, 0), "entities_20plus_attributes": wide_ents.get(n, 0),
    })

proj = rows("SELECT ProjectName, MendixVersion FROM projects LIMIT 1")
sched = rows("SELECT QualifiedName, ModuleName, Microflow, Enabled, IntervalSeconds, RepeatDescription FROM scheduled_events_data ORDER BY 1")

inventory = {
    "project": {"mpr": os.environ["MPR_BASE"], "name": proj[0]["ProjectName"] if proj else "",
                "mendix_version": proj[0]["MendixVersion"] if proj else "", "mxcli": os.environ["MX_VERSION"]},
    "totals": {"modules": len(mods), "modules_own": len(own),
               "modules_marketplace": sum(1 for k in kinds.values() if k == "marketplace"),
               "entities": one("SELECT count(*) FROM entities_data"),
               "microflows": one("SELECT count(*) FROM microflows_data WHERE MicroflowType='MICROFLOW'"),
               "nanoflows": one("SELECT count(*) FROM microflows_data WHERE MicroflowType='NANOFLOW'"),
               "pages": one("SELECT count(*) FROM pages_data"),
               "activities": one("SELECT count(*) FROM activities_data"),
               "refs": one("SELECT count(*) FROM refs"),
               "scheduled_events": len(sched)},
    "modules": modules,
    "scheduled_events": sched,
}
json.dump(inventory, open(os.path.join(F, "inventory.json"), "w"), indent=1, sort_keys=True)

# --- module dependency graph, own modules only, through the real module column ---------------
# refs.ModuleName is the source document's module (blank for navigation). The target's module
# comes from objects.ModuleName by qualified name. Neither is a string split.
edge_rows = rows("""
  SELECT r.ModuleName s, o.ModuleName t, r.RefKind k, count(*) n
  FROM refs r JOIN objects o ON o.QualifiedName = r.TargetName
  WHERE r.ModuleName <> '' AND o.ModuleName <> '' AND r.ModuleName <> o.ModuleName
  GROUP BY 1,2,3""")
edges = collections.defaultdict(lambda: {"edges": 0, "kinds": collections.Counter()})
edges_all = collections.defaultdict(int)          # including marketplace/framework, for context
for r in edge_rows:
    edges_all[(r["s"], r["t"])] += r["n"]
    if kinds.get(r["s"]) == "own" and kinds.get(r["t"]) == "own":
        e = edges[(r["s"], r["t"])]; e["edges"] += r["n"]; e["kinds"][r["k"]] += r["n"]

adj = collections.defaultdict(set)
for (s, t) in edges: adj[s].add(t)

bidir = []
for (s, t), e in edges.items():
    if s < t and (t, s) in edges:
        bidir.append({"a": s, "b": t, "a_to_b": e["edges"], "b_to_a": edges[(t, s)]["edges"],
                      "a_to_b_kinds": dict(e["kinds"]), "b_to_a_kinds": dict(edges[(t, s)]["kinds"])})
bidir.sort(key=lambda x: -(x["a_to_b"] + x["b_to_a"]))

# Cycles. Two facts, because raw cycle enumeration explodes: one probe app had 59 bidirectional
# pairs and 720 distinct cycles of length <= 4, which tells a reader nothing. So:
#   (a) strongly connected components with more than one module: the real "tangle" units,
#       each module listed once, no double counting (Tarjan, iterative);
#   (b) elementary 3-cycles, each ONCE (found only from its smallest module, walking through
#       larger ones), listed; 2-cycles are the bidirectional pairs above.
def tarjan(nodes, adj):
    index = {}; low = {}; onstack = set(); st = []; out = []; counter = [0]
    for root in nodes:
        if root in index: continue
        work = [(root, iter(sorted(adj.get(root, ()))))]
        index[root] = low[root] = counter[0]; counter[0] += 1; st.append(root); onstack.add(root)
        while work:
            v, it = work[-1]
            advanced = False
            for w in it:
                if w not in index:
                    index[w] = low[w] = counter[0]; counter[0] += 1; st.append(w); onstack.add(w)
                    work.append((w, iter(sorted(adj.get(w, ()))))); advanced = True; break
                elif w in onstack:
                    low[v] = min(low[v], index[w])
            if advanced: continue
            work.pop()
            if work: low[work[-1][0]] = min(low[work[-1][0]], low[v])
            if low[v] == index[v]:
                comp = []
                while True:
                    w = st.pop(); onstack.discard(w); comp.append(w)
                    if w == v: break
                if len(comp) > 1: out.append(sorted(comp))
    return sorted(out, key=lambda c: (-len(c), c))
sccs = tarjan(own, adj)

three_cycles = []
for s in own:
    for b in sorted(adj.get(s, ())):
        if b <= s: continue
        for c in sorted(adj.get(b, ())):
            if c > s and c != b and s in adj.get(c, ()):
                three_cycles.append([s, b, c])
three_cycles.sort()

# god nodes and cohesion, own modules, module resolved by join not by split
god = rows("""
  WITH deg AS (
    SELECT TargetName AS a, count(*) AS i, 0 AS o FROM refs WHERE TargetName <> '' GROUP BY 1
    UNION ALL
    SELECT SourceName AS a, 0 AS i, count(*) AS o FROM refs WHERE SourceName <> '' GROUP BY 1)
  SELECT d.a AS asset, ob.ObjectType AS type, ob.ModuleName AS module,
         sum(d.i) AS in_degree, sum(d.o) AS out_degree, sum(d.i)+sum(d.o) AS degree
  FROM deg d JOIN objects ob ON ob.QualifiedName = d.a
  GROUP BY d.a ORDER BY degree DESC LIMIT 200""")
god = [g for g in god if kinds.get(g["module"]) == "own"][:40]

coh = []
for m in own:
    intra = one("SELECT count(*) FROM refs r JOIN objects o ON o.QualifiedName=r.TargetName WHERE r.ModuleName=? AND o.ModuleName=?", m, m)
    inter = one("SELECT count(*) FROM refs r JOIN objects o ON o.QualifiedName=r.TargetName WHERE r.ModuleName=? AND o.ModuleName<>'' AND o.ModuleName<>?", m, m)
    inbound = sum(n for (s, t), n in edges_all.items() if t == m)
    tot = intra + inter
    coh.append({"module": m, "intra_edges": intra, "outbound_edges": inter, "inbound_edges": inbound,
                "cohesion_pct": round(100.0 * intra / tot, 1) if tot else None})
coh.sort(key=lambda c: (c["cohesion_pct"] if c["cohesion_pct"] is not None else 101))

dead = [d for d in rows("SELECT QualifiedName, ObjectType, ModuleName FROM graph_dead_assets ORDER BY 3,2,1")
        if kinds.get(d["ModuleName"]) == "own"]

deps = {
    "scope": {"own_modules": own, "rule": "own = Source blank and not System/Atlas_*; marketplace = Source set; framework = System, Atlas_*"},
    "edges": sorted(({"from": s, "to": t, "edges": e["edges"], "kinds": dict(e["kinds"])} for (s, t), e in edges.items()),
                    key=lambda x: -x["edges"]),
    "edges_to_marketplace": sorted(({"from": s, "to": t, "edges": n} for (s, t), n in edges_all.items()
                                     if kinds.get(s) == "own" and kinds.get(t) == "marketplace"), key=lambda x: -x["edges"]),
    "bidirectional_pairs": bidir,
    "tangles": {"note": "strongly connected components of the own-module graph with >1 module; every module in one can reach every other",
                "count": len(sccs), "modules_in_tangles": sum(len(c) for c in sccs), "list": sccs},
    "three_cycles": {"count": len(three_cycles), "list": three_cycles[:100]},
    "god_nodes": god,
    "cohesion": coh,
    "dead_assets_own": dead,
    "counts": {"own_edges": len(edges), "own_edge_weight": sum(e["edges"] for e in edges.values()),
               "bidirectional_pairs": len(bidir), "tangles": len(sccs), "modules_in_tangles": sum(len(c) for c in sccs),
               "largest_tangle": len(sccs[0]) if sccs else 0, "three_cycles": len(three_cycles), "dead_assets_own": len(dead)},
}
json.dump(deps, open(os.path.join(F, "dependencies.json"), "w"), indent=1, sort_keys=True)

# --- loop candidates + scheduled-event reachability, for step 3 --------------------------------
cand = rows("""SELECT a.MicroflowQualifiedName qn, count(*) n, m.ModuleName mod, m.MicroflowType typ
               FROM activities_data a JOIN microflows_data m ON m.QualifiedName = a.MicroflowQualifiedName
               WHERE a.ActivityType='LoopedActivity' GROUP BY 1 ORDER BY n DESC, qn""")
maxl = int(os.environ.get("MAX_LOOPS") or 0)
if maxl > 0: cand = cand[:maxl]
json.dump({c["qn"]: c["n"] for c in cand}, open(os.path.join(F, "loops-expected.json"), "w"), indent=1, sort_keys=True)
# Columns: qualified name, top-level loop count, module kind, document type. Rules (type RULE)
# are listed but never described: mxcli v0.21.0 has no `describe rule` (bug-logs, 2026-09-15).
with open(os.path.join(F, "loops-candidates.tsv"), "w") as fh:
    for c in cand: fh.write("%s\t%d\t%s\t%s\n" % (c["qn"], c["n"], kinds.get(c["mod"], "?"), c["typ"] or "?"))

# which microflows are reachable from a scheduled event, over call edges
calls = collections.defaultdict(set)
for r in rows("SELECT SourceName s, TargetName t FROM refs WHERE RefKind='call' AND SourceType IN ('MICROFLOW','NANOFLOW')"):
    calls[r["s"]].add(r["t"])
# Split by the event's Enabled flag: on the first real app 24 of 40 events were disabled, and a
# loop only a disabled event reaches is dormant, not nightly load.
reach = collections.defaultdict(lambda: {"enabled": set(), "disabled": set()})
for se in sched:
    bucket = "enabled" if str(se["Enabled"]).lower() in ("1", "true", "yes") else "disabled"
    root = se["Microflow"]
    seen, stack = set(), [root]
    while stack:
        n = stack.pop()
        if n in seen: continue
        seen.add(n); reach[n][bucket].add(se["QualifiedName"]); stack.extend(calls.get(n, ()))
json.dump({k: {b: sorted(v[b]) for b in v} for k, v in reach.items()},
          open(os.path.join(F, "loops-scheduled.json"), "w"), indent=1, sort_keys=True)
print("    own modules: %d   own edges: %d   bidirectional pairs: %d   tangles: %d (largest %d modules)   loop microflows: %d"
      % (len(own), len(edges), len(bidir), len(sccs), len(sccs[0]) if sccs else 0, len(cand)))
PY
T2=$(( $(date +%s) - T2 ))

# ---------------------------------------------------------------------------------------------
# Step 2b — unit snapshot: {UnitID: ContentsHash} from the .mpr Unit table, with each unit's
# type, qualified name and folder path. One read of each .mxunit file, no mxcli. A model
# whose table cannot be read gets a full sweep, never a guessed incremental one.
# ---------------------------------------------------------------------------------------------
UNITS_TSV="$FACTS_DIR/.units.tsv"; UNITS_STATUS="fault"; UNITS_REASON=""
rm -f "$UNITS_TSV"
if [ ! -f "$UNITS_PY" ]; then
  UNITS_REASON="mx-metadata-note.py not beside app-facts.sh"
elif "$PY" "$UNITS_PY" units "$MODEL_DIR/$MPR_BASE" > "$UNITS_TSV" 2> "$FACTS_DIR/.units.err" && [ -s "$UNITS_TSV" ]; then
  UNITS_STATUS="pass"; UNITS_REASON="$(wc -l < "$UNITS_TSV" | tr -d ' ') units read from the Unit table"
  [ -s "$FACTS_DIR/.units.err" ] && UNITS_REASON="$UNITS_REASON; $(tail -1 "$FACTS_DIR/.units.err" | cut -c1-160)"
else
  UNITS_REASON="unit table unreadable: $(tail -1 "$FACTS_DIR/.units.err" 2>/dev/null | cut -c1-160)"
  rm -f "$UNITS_TSV"
fi
rm -f "$FACTS_DIR/.units.err"

# ---------------------------------------------------------------------------------------------
# Step 3 — describe the loop-containing microflows whose unit changed since their mdl/ file was
# written (all of them on a full sweep), in parallel, then parse every loop body.
# ---------------------------------------------------------------------------------------------
LOOP_STATUS="skipped"; LOOP_REASON="--skip-loops"; T3=0; N_CAND=0; N_DESC=0; N_FAILED=0; N_RULES=0
SWEEP_MODE="none"; SWEEP_REASON="--skip-loops"
N_CAND=$(wc -l < "$FACTS_DIR/loops-candidates.tsv" | tr -d ' ')
PLAN="$FACTS_DIR/.sweep-plan.json"; TODO="$FACTS_DIR/.describe-todo.txt"
rm -f "$PLAN" "$TODO"
if [ "$SKIP_LOOPS" -eq 0 ]; then
  T3=$(date +%s)
  # The plan: which candidates to describe, which outputs to keep, which to delete. It also
  # deletes every mdl/ file that is about to be rewritten or no longer belongs, so a describe
  # that fails leaves no stale file behind.
  FACTS_DIR="$FACTS_DIR" UNITS_TSV="$UNITS_TSV" FULL="$FULL" MX_VERSION="$MX_VERSION" PLAN="$PLAN" TODO="$TODO" \
  UNITS_REASON="$UNITS_REASON" "$PY" - <<'PY' || exit 2
import json, os
F = os.environ["FACTS_DIR"]; MDL = os.path.join(F, "mdl")
by_qn = {}
if os.path.exists(os.environ["UNITS_TSV"]):
    for line in open(os.environ["UNITS_TSV"], encoding="utf-8"):
        p = line.rstrip("\n").split("\t")
        if len(p) == 5 and p[3]:
            by_qn[p[3]] = {"unit": p[0], "hash": p[1], "path": p[4]}
cands = []
for line in open(os.path.join(F, "loops-candidates.tsv"), encoding="utf-8"):
    p = line.rstrip("\n").split("\t")
    if len(p) >= 4 and p[3] != "RULE":
        cands.append(p[0])
try:
    prev = json.load(open(os.path.join(F, "manifest.json")))
except (OSError, ValueError):
    prev = {}
prev_idx = prev.get("mdl_index") or {}
if os.environ["FULL"] == "1":
    mode, why = "full", "--full"
elif not by_qn:
    mode, why = "full", "no unit snapshot (%s)" % os.environ["UNITS_REASON"]
elif not prev_idx:
    mode, why = "full", "no mdl_index from an earlier run (first run, or facts written before incremental sweeps)"
elif prev.get("mdl_index_mxcli") != os.environ["MX_VERSION"]:
    mode, why = "full", "mxcli changed since the last sweep (%s -> %s)" % (prev.get("mdl_index_mxcli"), os.environ["MX_VERSION"])
else:
    mode, why = "incremental", "unit hashes compared with mdl_index"
want = set(cands)
have = {fn[:-4] for fn in os.listdir(MDL) if fn.endswith(".mdl")}
todo, reused, removed = [], [], []
for qn in sorted(have):
    if mode == "full" or qn not in want:
        os.unlink(os.path.join(MDL, qn + ".mdl"))
        if qn not in want: removed.append(qn)
for qn in cands:
    cur = by_qn.get(qn)
    if mode == "incremental" and qn in have and cur is not None and prev_idx.get(qn) == cur:
        reused.append(qn); continue
    if qn in have and mode == "incremental":
        os.unlink(os.path.join(MDL, qn + ".mdl"))
    todo.append(qn)
with open(os.environ["TODO"], "w", encoding="utf-8") as fh:
    for qn in todo: fh.write(qn + "\n")
json.dump({"mode": mode, "reason": why, "describe": len(todo), "reused": len(reused), "removed": len(removed),
           "index": {qn: by_qn[qn] for qn in cands if qn in by_qn}}, open(os.environ["PLAN"], "w"))
PY
  SWEEP_MODE="$("$PY" -c 'import json,sys; print(json.load(open(sys.argv[1]))["mode"])' "$PLAN")"
  SWEEP_REASON="$("$PY" -c 'import json,sys; print(json.load(open(sys.argv[1]))["reason"])' "$PLAN")"
  N_TODO=$(wc -l < "$TODO" | tr -d ' ')
  if [ "${N_CAND:-0}" -eq 0 ]; then
    LOOP_STATUS="pass"; LOOP_REASON="no LoopedActivity in the catalog; nothing to describe"
    echo '{"_meta":{"files":0,"parsed":0,"parse_mismatch":[],"unreadable":[]},"microflows":{}}' > "$FACTS_DIR/loops.json"
  else
    log "step 3: $SWEEP_MODE sweep ($SWEEP_REASON): describing $N_TODO of $N_CAND loop-containing microflows with $WORKERS workers"
    : > "$FACTS_DIR/describe-failures.txt"
    # -n 1 with the name as $1, not -I{}: BSD xargs refuses -I when the replacement string
    # appears more than a few times in the command ("command line cannot be assembled").
    # No type word: the candidates are microflows, nanoflows AND rules (all three carry loops
    # and all three live in microflows_data), and `describe microflow` says "not found" for the
    # other two. 11 of 425 on the first real run, all nanoflows and rules.
    N_RULES=$(awk -F'\t' '$4=="RULE"' "$FACTS_DIR/loops-candidates.tsv" | wc -l | tr -d ' ')
    if [ "$N_TODO" -gt 0 ]; then
      MXCLI="$MXCLI" MODEL_DIR="$MODEL_DIR" MPR_BASE="$MPR_BASE" OUT="$FACTS_DIR" \
        xargs -P "$WORKERS" -n 1 sh -c '
          cd "$MODEL_DIR" && "$MXCLI" describe "$1" -p "$MPR_BASE" > "$OUT/mdl/$1.mdl" 2>/dev/null \
            || { echo "$1" >> "$OUT/describe-failures.txt"; rm -f "$OUT/mdl/$1.mdl"; }' _ < "$TODO"
    fi
    N_DESC=$(ls "$FACTS_DIR"/mdl/*.mdl 2>/dev/null | wc -l | tr -d ' ')
    N_FAILED=$(wc -l < "$FACTS_DIR/describe-failures.txt" | tr -d ' ')
    if [ "${N_DESC:-0}" -eq 0 ]; then
      echo "FAULT: $N_CAND microflows contain loops and not one could be described. See $FACTS_DIR/describe-failures.txt" >&2
      exit 2
    fi
    "$PY" -c "$PARSER" "$FACTS_DIR/mdl" "$FACTS_DIR/loops-expected.json" "$FACTS_DIR/loops-scheduled.json" > "$FACTS_DIR/loops.json" || exit 2
    LOOP_STATUS="pass"; LOOP_REASON="described $N_DESC of $N_CAND ($N_TODO this run, $SWEEP_MODE); $N_FAILED failed; $N_RULES rules not describable by this mxcli"
    # A rule with a loop is a known blind spot (no `describe rule` in mxcli v0.21.0), reported as a
    # count so the dossier can name it under Method. A microflow or nanoflow that failed is partial.
    [ "$N_FAILED" -gt 0 ] && LOOP_STATUS="partial"
  fi
  T3=$(( $(date +%s) - T3 ))
  log "loops: $LOOP_REASON (${T3}s)"
fi

# ---------------------------------------------------------------------------------------------
# Manifest — every section has a status, so absence can never read as clean.
# ---------------------------------------------------------------------------------------------
FACTS_DIR="$FACTS_DIR" MX_VERSION="$MX_VERSION" MPR_BASE="$MPR_BASE" DB="$DB" \
T1="$T1" T2="$T2" T3="$T3" TALL="$(( $(date +%s) - START_ALL ))" \
LOOP_STATUS="$LOOP_STATUS" LOOP_REASON="$LOOP_REASON" N_CAND="$N_CAND" N_DESC="$N_DESC" N_FAILED="$N_FAILED" N_RULES="$N_RULES" \
BUILD_MODE="$BUILD_MODE" N_MODULES="$N_MODULES" N_REFS="$N_REFS" N_ACTS="$N_ACTS" WORKERS="$WORKERS" MAX_LOOPS="$MAX_LOOPS" \
UNITS_TSV="$UNITS_TSV" UNITS_STATUS="$UNITS_STATUS" UNITS_REASON="$UNITS_REASON" PLAN="$PLAN" FULL="$FULL" \
SWEEP_MODE="$SWEEP_MODE" SWEEP_REASON="$SWEEP_REASON" SKIP_LOOPS="$SKIP_LOOPS" "$PY" - <<'PY'
import json, os, datetime, hashlib
F = os.environ["FACTS_DIR"]
try:
    prev = json.load(open(os.path.join(F, "manifest.json")))
except (OSError, ValueError):
    prev = {}
# Unit snapshot: the state of the model this map was built from. bin/status.sh compares it with
# the Unit table now (app-facts.sh --freshness).
snap = {}
if os.path.exists(os.environ["UNITS_TSV"]):
    for line in open(os.environ["UNITS_TSV"], encoding="utf-8"):
        p = line.rstrip("\n").split("\t")
        if len(p) >= 2: snap[p[0]] = p[1]
prev_snap = (prev.get("units") or {}).get("snapshot") or {}
changed = None
if snap and prev_snap:
    changed = {"previous_map": prev.get("generated", ""),
               "changed": sum(1 for u, h in snap.items() if u in prev_snap and prev_snap[u] != h),
               "added": sum(1 for u in snap if u not in prev_snap),
               "removed": sum(1 for u in prev_snap if u not in snap)}
# The snapshot dates the map, and the loop section is its slowest part. A --skip-loops run leaves
# mdl/ as it was, so it keeps the snapshot (and its date) of the last loop sweep: otherwise
# --freshness would say "fresh" over stale loop outputs (#297 review). None yet: none stored.
gen = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
units_note = ""
if os.environ["SKIP_LOOPS"] == "1":
    snap_out = prev_snap
    snap_taken = (prev.get("units") or {}).get("snapshot_taken") or prev.get("generated", "") if prev_snap else ""
    units_note = ("; snapshot carried from the last loop sweep (--skip-loops)" if prev_snap
                  else "; no snapshot stored: --skip-loops and no earlier loop sweep")
else:
    snap_out, snap_taken = snap, (gen if snap else "")
# mdl_index: which unit state each mdl/ file was described from. Only files that exist now are
# indexed, so a failed describe is retried next run. --skip-loops leaves mdl/ alone and carries the
# previous index forward unchanged.
plan = json.load(open(os.environ["PLAN"])) if os.path.exists(os.environ["PLAN"]) else None
if plan is not None:
    mdl_index = {qn: v for qn, v in plan["index"].items() if os.path.exists(os.path.join(F, "mdl", qn + ".mdl"))}
    mdl_index_mxcli = os.environ["MX_VERSION"]
else:
    mdl_index, mdl_index_mxcli = prev.get("mdl_index") or {}, prev.get("mdl_index_mxcli", "")
def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""): h.update(chunk)
    return h.hexdigest()[:16]
mp = os.path.join(os.path.dirname(os.environ["DB"]), "..", os.environ["MPR_BASE"])
mp = os.path.normpath(mp)
loops = json.load(open(os.path.join(F, "loops.json"))) if os.path.exists(os.path.join(F, "loops.json")) else None
mismatch = len(loops["_meta"]["parse_mismatch"]) if loops else 0
man = {
  "schema": "app-facts/1",
  "generated": gen,
  "mpr": os.environ["MPR_BASE"], "mpr_sha256_16": sha(mp) if os.path.exists(mp) else "",
  "mxcli": os.environ["MX_VERSION"],
  "catalog": {"modules": int(os.environ["N_MODULES"]), "refs": int(os.environ["N_REFS"]), "activities": int(os.environ["N_ACTS"]), "build_mode": os.environ.get("BUILD_MODE", "")},
  "timings_s": {"catalog_and_graph_report": int(os.environ["T1"]), "inventory_and_dependencies": int(os.environ["T2"]), "loops": int(os.environ["T3"]), "total": int(os.environ["TALL"])},
  "options": {"workers": int(os.environ["WORKERS"]), "max_loops": int(os.environ["MAX_LOOPS"]), "full": os.environ["FULL"] == "1"},
  "units": {"status": os.environ["UNITS_STATUS"], "reason": os.environ["UNITS_REASON"] + units_note, "count": len(snap_out),
            "source": "the .mpr Unit table; ContentsHash format, computed from each .mxunit's bytes", "changed_since_previous_map": changed,
            "snapshot_taken": snap_taken, "snapshot": snap_out},
  "mdl_index": mdl_index, "mdl_index_mxcli": mdl_index_mxcli,
  "sections": {
    "inventory":    {"status": "pass", "file": "inventory.json"},
    "dependencies": {"status": "pass", "file": "dependencies.json"},
    "loops":        {"status": os.environ["LOOP_STATUS"], "file": "loops.json", "reason": os.environ["LOOP_REASON"],
                     "candidates": int(os.environ["N_CAND"]), "described": int(os.environ["N_DESC"]), "failed": int(os.environ["N_FAILED"]),
                     "rules_not_describable": int(os.environ["N_RULES"]), "parse_mismatch": mismatch,
                     "catalog_undercount": int(loops["_meta"].get("catalog_undercount", 0)) if loops else 0,
                     "sweep": {"mode": os.environ["SWEEP_MODE"], "reason": os.environ["SWEEP_REASON"],
                               "described_this_run": plan["describe"] if plan else 0,
                               "reused": plan["reused"] if plan else 0,
                               "removed_outputs": plan["removed"] if plan else 0}},
    "security":     {"status": "fault", "reason": "not collected by this version of app-facts.sh"},
    "lint_baseline":{"status": "fault", "reason": "run project-bin/lint-gate.sh separately; not folded in yet"},
  },
}
json.dump(man, open(os.path.join(F, "manifest.json"), "w"), indent=1, sort_keys=True)
print("==> facts written to %s (total %ss)" % (F, os.environ["TALL"]))
if changed is not None:
    print("    units since the previous map (%s): %d changed, %d added, %d removed"
          % (changed["previous_map"][:16].replace("T", " "), changed["changed"], changed["added"], changed["removed"]))
if mismatch:
    print("    NOTE: %d microflow(s) where the parser found FEWER loops than the catalog, see loops.json _meta.parse_mismatch" % mismatch)
uc = int(loops["_meta"].get("catalog_undercount", 0)) if loops else 0
if uc:
    print("    note: %d microflow(s) where the parser found MORE loops than the catalog (nested loops; the catalog holds top-level activities only)" % uc)
PY
RC=$?
rm -f "$UNITS_TSV" "$PLAN" "$TODO"
[ "$RC" -eq 0 ] || exit 2
exit 0
