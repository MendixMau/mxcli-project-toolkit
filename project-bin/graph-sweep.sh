#!/usr/bin/env bash
# graph-sweep.sh — wiring conformance over the model's dependency graph.
#
# Reads .mxcli/catalog.db (SQLite, typed reference edges) and answers the questions mxbuild
# and e2e are both blind to: is a module imported but never reached? is an element built but
# wired to nothing? does a module reach across boundaries it should not?
#
# The originating case: a workflow built with hand-rolled microflows that never wire into the
# standard module. It compiles, it behaves identically, and the graph shows the standard
# module with zero inbound edges.
#
# Relationship to `mxcli lint` QUAL004 ("Orphaned Elements"): QUAL004 answers the same
# element-level question as this script's "orphaned microflows" finding, natively, from the
# same catalog — prefer it when it's available (`mxcli lint`, or `mxcli report`) rather than
# reading this script's ORPHANS query as ground truth; the exclusion lists here (entry-point
# prefixes, RefKind set) are hand-maintained and can drift from QUAL004's. This script earns
# its keep on the "module wiring shape" finding (aggregate inbound/outbound edges per module),
# which is a different, coarser question than any single element's orphan status — that finding
# has no direct mxcli-native equivalent yet (closest is `GRAPH_MODULE_COUPLING`, which is edge-
# weighted, not this script's plain in/out counts). See `skills/process-coherence-pass.md`.
#
# Read-only: opens the catalog database. Never runs mxcli exec, never touches the .mpr.
#
# IMPORTANT — an unwired marketplace module is not a defect. Most are legitimately unused.
# This script reports the shape; deciding whether a given module was SUPPOSED to be wired in
# is an intent question, answered against the module brief, not here.
#
# Usage: bin/graph-sweep.sh [--module <Name>] [--min-elements N] [--tsv]
# Exit:  0 swept · 2 instrument fault (stale catalog, empty graph, missing db)

set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
cd "$PROJECT_ROOT" || exit 2

MPR="$(find_mpr)" || exit 2

# THE CATALOG LIVES BESIDE THE .mpr, NOT ALWAYS AT THE PROJECT ROOT (fixed 2026-09-02).
# `mxcli ... REFRESH CATALOG` writes <dir-of-mpr>/.mxcli/catalog.db. On a single-tree checkout
# that is the project root and the old hardcoded ".mxcli/catalog.db" was right; on a TWO-TREE
# checkout, where the model sits under app/, the catalog lands in app/.mxcli/ and this script
# reported "catalog.db not found -- run REFRESH CATALOG" at a project that had just run exactly
# that. Found on t-wf-migration, where the operator's fix was a hand-made symlink.
#
# This is the third time the same both-layouts assumption has been shipped in this directory
# (F-020, F-042, now this one), which is why field-proof rule 2 says to probe BOTH layouts
# before merging an instrument. Derive the path from the .mpr that find_mpr already resolved,
# and keep the root as a fallback so a project that puts it there still works.
DB="$(dirname "$MPR")/.mxcli/catalog.db"
[ -f "$DB" ] || [ ! -f ".mxcli/catalog.db" ] || DB=".mxcli/catalog.db"
MODULE=""
MIN_ELEMENTS=20
TSV=0

while [ $# -gt 0 ]; do
  case "$1" in
    --module)       MODULE="${2:-}"; shift 2 ;;
    --min-elements) MIN_ELEMENTS="${2:-20}"; shift 2 ;;
    --tsv)          TSV=1; shift ;;
    -h|--help)      sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v sqlite3 >/dev/null || { echo "FAULT: sqlite3 not on PATH" >&2; exit 2; }
[ -f "$DB" ]  || { echo "FAULT: $DB not found — run: ./mxcli -p $MPR -c 'REFRESH CATALOG FULL'" >&2; exit 2; }
[ -f "$MPR" ] || { echo "FAULT: $MPR not found" >&2; exit 2; }

q() { sqlite3 -noheader "$DB" "$1"; }

# --- guard 1: freshness ------------------------------------------------------------------
CAT_MTIME="$(q "SELECT value FROM catalog_meta WHERE key='mpr_mod_time';" | cut -c1-19)"
# `stat -c` is GNU coreutils (Linux, and Git Bash on Windows), `stat -f` is BSD/macOS.
# GNU must be tried FIRST: on GNU, `stat -f` does not fail — it reads `-f`/`-t` as
# filesystem-info flags and prints plausible-looking garbage, so a BSD-first chain's
# fallback never fires and every Linux run FAULTs as "catalog is stale" against a bogus
# mtime (found independently on two projects, 2026-08-19 and 2026-08-14). The third case
# still matters most: if NEITHER works, MPR_MTIME is empty and the freshness guard below
# reports "catalog is stale" against a blank mtime — a real fault reported as the wrong
# fault. Fail on the read instead of comparing against nothing.
MPR_MTIME="$(stat -c "%y" "$MPR" 2>/dev/null | cut -c1-19 | tr ' ' 'T')"
[ -n "$MPR_MTIME" ] || MPR_MTIME="$(stat -f "%Sm" -t "%Y-%m-%dT%H:%M:%S" "$MPR" 2>/dev/null)"
[ -n "$MPR_MTIME" ] || {
  echo "FAULT: cannot read the modification time of $MPR." >&2
  echo "       Neither 'stat -f' (BSD/macOS) nor 'stat -c' (GNU/Linux/Git Bash) worked here." >&2
  echo "       Refusing to compare catalog freshness against an unknown timestamp." >&2
  exit 2; }
BUILD_MODE="$(q "SELECT value FROM catalog_meta WHERE key='build_mode';")"

if [ "$CAT_MTIME" != "$MPR_MTIME" ]; then
  echo "FAULT: catalog is stale." >&2
  echo "       catalog built against: $CAT_MTIME" >&2
  echo "       .mpr last modified:    $MPR_MTIME" >&2
  echo "       Rebuild (~6s): ./mxcli -p $MPR -c 'REFRESH CATALOG FULL'" >&2
  echo "       Refusing to report wiring from a stale graph." >&2
  exit 2
fi

if [ "$BUILD_MODE" != "full" ]; then
  echo "FAULT: catalog build_mode is '$BUILD_MODE'; reference edges require 'full'." >&2
  echo "       Rebuild: ./mxcli -p $MPR -c 'REFRESH CATALOG FULL'" >&2
  exit 2
fi

# --- guard 2: non-vacuous ------------------------------------------------------------------
# An empty graph produces zero findings, which is indistinguishable from a clean model.
REFS=$(q "SELECT COUNT(*) FROM refs;")
OBJS=$(q "SELECT COUNT(*) FROM objects;")
if [ "${REFS:-0}" -eq 0 ] || [ "${OBJS:-0}" -eq 0 ]; then
  echo "FAULT: graph is empty (refs=$REFS objects=$OBJS). Refusing to report a clean sweep." >&2
  exit 2
fi

WIRING_FILTER=""
ORPHAN_FILTER=""
if [ -n "$MODULE" ]; then
  WIRING_FILTER="AND e.m = '$MODULE'"
  ORPHAN_FILTER="AND m.ModuleName = '$MODULE'"
fi

# --- finding 1: module wiring shape ---------------------------------------------------------
# A module carrying real weight with no inbound edges from any other module is the signature
# of "imported but never wired in". Marked * when the project owns a brief or ledger for it,
# because that is when it is supposed to be reached.
WIRING="$(q "
WITH elems AS (
  SELECT ModuleName m, COUNT(*) n FROM objects GROUP BY 1
),
inb AS (
  SELECT SUBSTR(TargetName,1,INSTR(TargetName,'.')-1) m, COUNT(*) n FROM refs
  WHERE INSTR(TargetName,'.')>0
    AND SUBSTR(TargetName,1,INSTR(TargetName,'.')-1)
     <> SUBSTR(SourceName,1,INSTR(SourceName,'.')-1)
  GROUP BY 1
),
outb AS (
  SELECT SUBSTR(SourceName,1,INSTR(SourceName,'.')-1) m, COUNT(*) n FROM refs
  WHERE INSTR(SourceName,'.')>0
    AND SUBSTR(TargetName,1,INSTR(TargetName,'.')-1)
     <> SUBSTR(SourceName,1,INSTR(SourceName,'.')-1)
  GROUP BY 1
)
SELECT e.m, e.n, COALESCE(i.n,0), COALESCE(o.n,0)
FROM elems e LEFT JOIN inb i ON i.m=e.m LEFT JOIN outb o ON o.m=e.m
WHERE e.n >= $MIN_ELEMENTS $WIRING_FILTER
ORDER BY COALESCE(i.n,0) ASC, e.n DESC;
")"

# --- finding 2: orphaned microflows -----------------------------------------------------------
# No inbound call / page action / nav item. Entry-point prefixes are excluded: they are
# legitimately unreferenced. Note SHOW REFERENCES TO misses layout snippetcalls, so this is
# strong evidence of deadness, not proof.
ORPHANS="$(q "
SELECT m.QualifiedName, m.ActivityCount
FROM microflows_data m
WHERE m.ModuleName NOT IN (
        'System','WorkflowCommons','CommunityCommons','GenAICommons','AgentCommons',
        'ConversationalUI','MxGenAIConnector','ExcelImporter','MxModelReflection',
        'MCPClient','AgentEditorCommons','Atlas_Core','Atlas_Web_Content','DataWidgets')
  AND m.Name NOT LIKE 'ACT!_%' ESCAPE '!'
  AND m.Name NOT LIKE 'SCH!_%' ESCAPE '!'
  AND m.Name NOT LIKE 'WS!_%'  ESCAPE '!'
  AND m.Name NOT LIKE 'IVK!_%' ESCAPE '!'
  AND m.Name NOT LIKE 'BE!_%'  ESCAPE '!'
  AND NOT EXISTS (
        SELECT 1 FROM refs r
        WHERE r.TargetName = m.QualifiedName
          AND r.RefKind IN ('call','action','menu_item','show_page','datasource'))
  $ORPHAN_FILTER
ORDER BY m.ModuleName, m.Name;
")"

# --- report -----------------------------------------------------------------------------------
if [ "$TSV" -eq 1 ]; then
  printf 'kind\ta\tb\tc\n'
  printf '%s\n' "$WIRING"  | awk -F'|' 'NF{print "wiring\t"$1"\t"$2"\t"$3"|"$4}'
  printf '%s\n' "$ORPHANS" | awk -F'|' 'NF{print "orphan\t"$1"\t"$2"\t"}'
  exit 0
fi

N_UNWIRED=$(printf '%s\n' "$WIRING" | awk -F'|' 'NF && $3==0' | grep -c . || true)
N_ORPH=$(printf '%s\n' "$ORPHANS" | grep -c . || true)

echo "graph-sweep · catalog $CAT_MTIME · $OBJS objects · $REFS typed edges"
echo
echo "  module wiring (>= $MIN_ELEMENTS elements)"
printf '    %-24s %8s %9s %10s\n' MODULE ELEMENTS INBOUND OUTBOUND
printf '%s\n' "$WIRING" | awk -F'|' 'NF {printf "    %-24s %8s %9s %10s%s\n", $1, $2, $3, $4, ($3==0 ? "   <- no inbound" : "")}'

echo
echo "  orphaned microflows (no call / action / nav inbound, entry-point prefixes excluded): $N_ORPH"
if [ "$N_ORPH" -gt 0 ]; then
  printf '%s\n' "$ORPHANS" | awk -F'|' 'NF {printf "    %-56s %s activities\n", $1, $2}' | head -40
  [ "$N_ORPH" -gt 40 ] && echo "    ... and $((N_ORPH-40)) more"
fi

echo
echo "  $N_UNWIRED module(s) with no inbound references."
echo "  Whether that is a defect is an intent question — check the module brief."
exit 0
