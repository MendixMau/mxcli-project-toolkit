#!/bin/bash
# test-context-pack.sh — pin context-pack.sh against real mxcli output.
#
# No mxcli and no real .mpr: MXCLI points at fixtures/context-pack/fake-mxcli, which replays
# DESCRIBE and impact output captured verbatim from mxcli v0.23.0 on a cook-off
# model (see the stub's header). The brief is fixtures/context-pack/module-brief.md. Pinned:
#
#   1. A CHANGE STEP: every Reads element described with its real kind, the built document shown
#      as "already in the model" with its impact table, the example included, the folder taken
#      from the folder plan, and the microflow rules named. Exit 0.
#   2. A PAGE STEP: the DateTime/Boolean/Enumeration watch-out names the real Boolean attribute.
#   3. A TYPO in Reads: the pack is still written, the name is listed under "Not found", exit 1.
#   4. NO ROW for the step: exit 2.
#   5. THE SWITCH: `Context packs: off` exits 3 and writes nothing; MXTK_CONTEXT_PACKS wins over
#      PROJECT.md; `no-brain` leaves out the brain even when docs/brain/ exists; `on` includes it;
#      an unrecognised value warns and runs as on.
#   6. BOTH LAYOUTS: the .mpr at the root, and under app/ (two-tree).
#
# Usage: bash test-context-pack.sh [path-to-context-pack.sh]

set -u

TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
CP="${1:-$TOOLKIT/project-bin/context-pack.sh}"
CP="$(cd "$(dirname "$CP")" && pwd)/$(basename "$CP")"   # run() cds into the project
FIX="$TOOLKIT/tests/wave2/fixtures/context-pack"
export MXCLI="$FIX/fake-mxcli"
unset MXTK_CONTEXT_PACKS MPR_FILE

PASS=0; FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$3', got '$2'"; fi; }
has()  { if grep -qF -- "$2" "$3"; then ok "$1"; else bad "$1" "missing: $2"; fi; }
hasnt(){ if grep -qF -- "$2" "$3"; then bad "$1" "unexpected: $2"; else ok "$1"; fi; }

# mkproj <dir> <root|app> — a project with the fixture brief and an empty .mpr
mkproj() {
  mkdir -p "$1/architecture/modules/Procurement"
  cp "$FIX/module-brief.md" "$1/architecture/modules/Procurement/module-brief.md"
  if [ "$2" = app ]; then mkdir -p "$1/app"; : > "$1/app/App.mpr"; else : > "$1/App.mpr"; fi
}
run() { ( cd "$1" && PROJECT_ROOT="$1" bash "$CP" Procurement "$2" --out "$1/pack.md" ) 2>"$1/err"; echo $?; }

for layout in root app; do
  P="$TMP/$layout"; mkproj "$P" "$layout"
  echo "== layout: $layout =="

  check "5.1 change step exits 0" "$(run "$P" 5.1)" "0"
  has "5.1 entity described with its kind"      "### Procurement.ApprovalStep (entity)" "$P/pack.md"
  has "5.1 enumeration described with its kind" "### Procurement.ApprovalStatus (enumeration)" "$P/pack.md"
  has "5.1 built document shown as existing"    "Already in the model" "$P/pack.md"
  has "5.1 impact table carried"                "Procurement.RequisitionDetail" "$P/pack.md"
  has "5.1 example included"                    "### Procurement.ACT_ApprovalStep_Reject (microflow)" "$P/pack.md"
  has "5.1 folder from the folder plan"         "| Procurement.ACT_ApprovalStep_Approve | Requisition/Microflows |" "$P/pack.md"
  has "5.1 microflow rules named"               "learned-microflow-patterns.md" "$P/pack.md"
  has "5.1 arch constraints carried"            "audit row in the same transaction" "$P/pack.md"
  has "5.1 no brain dir → says so"              "No docs/brain/ yet" "$P/pack.md"

  check "5.2 page step exits 0" "$(run "$P" 5.2)" "0"
  has "5.2 widget watch-out present"            "Widget watch-out" "$P/pack.md"
  has "5.2 watch-out names the Boolean attr"    "Procurement.CatalogItem: Active" "$P/pack.md"
  has "5.2 page rules named"                    "ui-preflight-pages.md" "$P/pack.md"

  check "5.3 typo in Reads exits 1" "$(run "$P" 5.3)" "1"
  has "5.3 typo listed under Not found"         "- Procurement.ApprovalStepp" "$P/pack.md"
  has "5.3 stderr names it"                     "Procurement.ApprovalStepp" "$P/err"

  check "unknown step exits 2" "$(run "$P" 9.9)" "2"
done

echo "== switch =="
P="$TMP/root"; mkdir -p "$P/docs/brain"

check "on (no PROJECT.md line) with docs/brain → exit 0" "$(run "$P" 5.1)" "0"
has "on → brain section included" "FAKE-BRAIN-MARKER" "$P/pack.md"
has "on → brain brief asked for the step's slice" "--slice 02-approvals" "$P/pack.md"

printf '# Project\n- **Context packs:** `no-brain`\n' > "$P/PROJECT.md"
check "no-brain → exit 0" "$(run "$P" 5.1)" "0"
hasnt "no-brain → brain left out" "FAKE-BRAIN-MARKER" "$P/pack.md"
has "no-brain → says why" "Context packs: no-brain" "$P/pack.md"

rm -f "$P/pack.md"
printf '# Project\nContext packs: off\n' > "$P/PROJECT.md"
check "off → exit 3" "$(run "$P" 5.1)" "3"
if [ -e "$P/pack.md" ]; then bad "off → no pack written" "pack.md exists"; else ok "off → no pack written"; fi
has "off → stderr names the fallback" "reading list" "$P/err"

check "env MXTK_CONTEXT_PACKS=on beats PROJECT.md off" \
  "$( ( cd "$P" && PROJECT_ROOT="$P" MXTK_CONTEXT_PACKS=on bash "$CP" Procurement 5.1 --out "$P/pack.md" ) 2>/dev/null; echo $?)" "0"

printf '# Project\nContext packs: banana\n' > "$P/PROJECT.md"
check "unrecognised value → runs as on (exit 0)" "$(run "$P" 5.1)" "0"
has "unrecognised value → warns" "unrecognised" "$P/err"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
