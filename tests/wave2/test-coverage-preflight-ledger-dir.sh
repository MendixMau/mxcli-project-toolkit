#!/usr/bin/env bash
# Usage: bash test-coverage-preflight-ledger-dir.sh [path-to-coverage-preflight.sh]
#
# Fixture for project-bin/coverage-preflight.sh's ledger discovery — the per-BRD directory form
# `architecture/modules/<Module>/coverage-ledger/<BRDID>.md` (project-bin/coverage-check-all.sh's
# convention) at LEVEL 1.
#
# The defect (card-disbursement requirements-driven build, 2026-09-26): a module that splits its
# ledger per BRD keeps coverage-ledger.md beside the directory as an index. find_ledger() only
# tested for files, found the index, and ran EVERY BRD against it — 9 of 9 BRDs UNCLAIMED for a
# module that owns one, while coverage-check-all.sh reported all 9 clean from the same files.
# Case 1 below is that project's shape in miniature, including the index file.
#
# The BRDs and ledgers here are SYNTHETIC and hand-written. That is deliberate and allowed: the
# field-proof rule's "golden input is captured" governs parsers of tool output, and nothing below
# parses tool output — it lays out files and asserts which ledger the script measures against.
# The field run that motivated it is cited in CHANGELOG.md.

set -uo pipefail

SUT="${1:-}"
[ -z "$SUT" ] && SUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/project-bin/coverage-preflight.sh"
if [ ! -f "$SUT" ]; then
  echo "SKIP: subject not found at $SUT"
  echo "SCORE: 0/0 — nothing to test"
  exit 0
fi
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed (the engine needs it)"; exit 0; }
export MXTK_ROOT="${MXTK_ROOT:-$(cd "$(dirname "$SUT")/.." && pwd)}"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/cov-ledger-dir.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# Two BRDs, 4 leaves each; Orders owns FA01, Billing owns FB02.
mk_project() {
  local r="$1"
  mkdir -p "$r/analysis/src/knowledge-base/brd" "$r/architecture/modules/Orders" "$r/architecture/modules/Billing"
  printf '{"id":"FA01","title":"Alpha","useCases":[{"id":"UC1","name":"Place order"}]}\n' \
    > "$r/analysis/src/knowledge-base/brd/FA01-alpha.brd.json"
  printf '{"id":"FB02","title":"Beta","useCases":[{"id":"UC1","name":"Send invoice"}]}\n' \
    > "$r/analysis/src/knowledge-base/brd/FB02-beta.brd.json"
}
ledger() {   # ledger <file> [omit-usecase]
  {
    echo "## BUILDABLE"; echo ""
    echo "| pointer | type | title | slice | writeMode | acceptance | status |"
    echo "|---|---|---|---|---|---|---|"
    [ "${2:-}" = "omit-usecase" ] || echo "| \`/useCases/0/*\` (2) | usecase | UC1 | 1.1 | test | e2e | not-built |"
    echo ""; echo "## NON-BUILDABLE"; echo ""
    echo "| pointer | category | reason |"
    echo "|---|---|---|"
    echo "| \`/id\` | provenance | metadata |"
    echo "| \`/title\` | provenance | metadata |"
  } > "$1"
}
run() { PROJECT_ROOT="$1" bash "$SUT" --summary --module "$2" >"$WORK/out" 2>&1; echo $?; }

# --- 1. directory form beside an index file: each BRD against its own ledger ------------------
P="$WORK/p1"; mk_project "$P"
mkdir -p "$P/architecture/modules/Orders/coverage-ledger"
ledger "$P/architecture/modules/Orders/coverage-ledger/FA01-alpha.md"
printf '# Coverage ledger — Orders (index)\n\n- FA01 → coverage-ledger/FA01-alpha.md\n' \
  > "$P/architecture/modules/Orders/coverage-ledger.md"
rc=$(run "$P" Orders)
[ "$rc" -eq 0 ] && ok "dir form beside an index file is clean (rc 0)" || bad "dir form not clean" "rc=$rc $(tr '\n' ' ' < "$WORK/out" | cut -c1-300)"
grep -q 'ledger: architecture/modules/Orders/coverage-ledger$' "$WORK/out" \
  && ok "the directory is chosen over the index file" || bad "index file measured instead of the directory"
grep -q '1 of 2 BRD(s) measured' "$WORK/out" \
  && ok "denominator stated: 1 of 2 BRDs measured" || bad "no measured-of denominator"
grep -q 'no ledger here.*FB02-beta' "$WORK/out" \
  && ok "the other module's BRD is named, not measured" || bad "other module's BRD not named"
if grep -qE 'UNCLAIMED: +[1-9]' "$WORK/out"; then
  bad "a BRD was measured against the wrong ledger (the 2026-09-26 false red)"
else
  ok "no BRD measured against the index"
fi

# --- 2. a finding in a per-BRD ledger passes through as rc 1 ---------------------------------
ledger "$P/architecture/modules/Orders/coverage-ledger/FA01-alpha.md" omit-usecase
rc=$(run "$P" Orders)
[ "$rc" -eq 1 ] && ok "an UNCLAIMED leaf in a per-BRD ledger reports rc 1" || bad "finding did not pass through" "rc=$rc"

# --- 3. a ledger file named after no BRD is a fault ------------------------------------------
ledger "$P/architecture/modules/Orders/coverage-ledger/FA01-alpha.md"
ledger "$P/architecture/modules/Orders/coverage-ledger/FZ99-ghost.md"
rc=$(run "$P" Orders)
[ "$rc" -eq 2 ] && grep -q 'FZ99-ghost' "$WORK/out" \
  && ok "orphan ledger file faults (rc 2) and is named" || bad "orphan ledger not faulted" "rc=$rc"
rm -f "$P/architecture/modules/Orders/coverage-ledger/FZ99-ghost.md"

# --- 4. a directory matching no BRD cannot evaluate ------------------------------------------
P4="$WORK/p4"; mk_project "$P4"
mkdir -p "$P4/architecture/modules/Billing/coverage-ledger"
ledger "$P4/architecture/modules/Billing/coverage-ledger/FA01-alpha.md"
mv "$P4/analysis/src/knowledge-base/brd/FA01-alpha.brd.json" "$P4/analysis/src/knowledge-base/brd/FC03-gamma.brd.json"
rc=$(run "$P4" Billing)
[ "$rc" -eq 2 ] && ok "a directory with no ledger for any BRD faults (rc 2), never a clean 0" || bad "unmatched directory read as clean" "rc=$rc"

# --- 5. the single-file form still works (regression) ----------------------------------------
P5="$WORK/p5"; mk_project "$P5"
ledger "$P5/architecture/modules/Orders/coverage-ledger.md"
rm "$P5/analysis/src/knowledge-base/brd/FB02-beta.brd.json"
rc=$(run "$P5" Orders)
[ "$rc" -eq 0 ] && grep -q 'ledger: architecture/modules/Orders/coverage-ledger.md' "$WORK/out" \
  && ok "single-file ledger still measured (rc 0)" || bad "single-file form regressed" "rc=$rc"

# --- 6. an empty directory is not a ledger: falls through to the file ------------------------
mkdir -p "$P5/architecture/modules/Orders/coverage-ledger"
rc=$(run "$P5" Orders)
[ "$rc" -eq 0 ] && grep -q 'ledger: architecture/modules/Orders/coverage-ledger.md' "$WORK/out" \
  && ok "empty directory falls through to the file" || bad "empty directory shadowed the file" "rc=$rc"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
