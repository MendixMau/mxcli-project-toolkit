#!/usr/bin/env bash
# Usage: bash test-verify-ledger-hint.sh [path-to-verify-module.sh]
#
# Fixture for project-bin/verify-module.sh's ledger hint (resolve_ledger_hint), which the
# coverage rung passes on when coverage-preflight.sh is absent.
#
# The defect (review of #307, 2026-10-13): LEDGER_FILE is documented as a file OR a per-BRD
# directory, but verify-module tested it with `[ -f ]`, so a directory silently fell back to
# architecture/coverage-ledger.md — another ledger, measured as this module's. A module keeping
# only <Module>/coverage-ledger/ (no index file) had the same fall-back.
#
# The function is extracted from the subject and called directly (a full verify-module run
# needs a live app). Paths are a scratch tree; both layouts resolve ROOT the same way here,
# because the ledger lives under architecture/ at the project root in both.

set -uo pipefail

SUT="${1:-}"
[ -z "$SUT" ] && SUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/project-bin/verify-module.sh"
if [ ! -f "$SUT" ]; then
  echo "SKIP: subject not found at $SUT"
  echo "SCORE: 0/0 — nothing to test"
  exit 0
fi

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/verify-ledger.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

FN="$(awk '/^resolve_ledger_hint\(\) \{/{on=1} on{print} on && /^\}/{exit}' "$SUT")"
[ -n "$FN" ] || { bad "no resolve_ledger_hint() in $SUT — LEDGER_FILE is tested with [ -f ] only"; echo; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }

R="$WORK/proj"; M="$R/architecture/modules"
mkdir -p "$M/Orders/coverage-ledger" "$M/Billing"
: > "$M/Orders/coverage-ledger/F001.md"
: > "$M/Billing/coverage-ledger.md"
: > "$R/architecture/coverage-ledger.md"
# The hint delegates to the shared lookup (mxtk_resolve_ledger, #673) — load it beside the function.
HELPER="$(awk '/^mxtk_resolve_ledger\(\) \{/{on=1} on{print} on && /^\}/{exit}' "$(dirname "$SUT")/_common.sh" 2>/dev/null)"
hint() { ( ROOT="$R"; MODULE="$1"; LEDGER_FILE="${2:-}"; [ -n "$LEDGER_FILE" ] || unset LEDGER_FILE
           [ -n "$HELPER" ] && eval "$HELPER"; eval "$FN"; resolve_ledger_hint ); }

v="$(hint Orders "$M/Orders/coverage-ledger")"
[ "$v" = "$M/Orders/coverage-ledger" ] && ok "LEDGER_FILE=<directory> is kept, not replaced by the project ledger" \
  || bad "directory LEDGER_FILE fell back" "$v"
v="$(hint Orders)"
[ "$v" = "$M/Orders/coverage-ledger" ] && ok "a module with only the per-BRD directory resolves to it" \
  || bad "directory-only module fell back" "$v"
v="$(hint Billing)"
[ "$v" = "$M/Billing/coverage-ledger.md" ] && ok "a module with coverage-ledger.md still resolves to the file" \
  || bad "file ledger changed" "$v"
v="$(hint Shipping)"
[ "$v" = "$R/architecture/coverage-ledger.md" ] && ok "a module with neither falls back to the project ledger, as before" \
  || bad "project fallback changed" "$v"

# --- the coverage rung honours `Waived artifact coverage-ledger: <reason>` (review of #651) ----
# SECTION-WIDE (#641) made coverage-check exit 1 on a one-row-per-section plan; that exit reaches
# this rung through coverage-preflight on every module verify. The waiver gate-check honours must
# turn the rung informational here too.
WF="$(awk '/^coverage_waiver\(\) \{/{on=1} on{print} on && /^\}/{exit}' "$SUT")"
if [ -z "$WF" ]; then
  bad "no coverage_waiver() in $SUT — the coverage rung ignores the register's waiver"
else
  waiver() { ( ROOT="$R"; eval "$WF"; coverage_waiver ); }
  printf '# Register\n' > "$R/PROJECT.md"
  [ -z "$(waiver)" ] && ok "no waiver line: nothing (the rung gates)" || bad "phantom waiver" "$(waiver)"
  printf '<!--\nWaived artifact coverage-ledger: example\n-->\nWaived artifact coverage-ledger:\n' >> "$R/PROJECT.md"
  [ -z "$(waiver)" ] && ok "a commented-out or reasonless line is not a waiver" || bad "comment/reasonless waiver" "$(waiver)"
  mkdir -p "$R/analysis/src"; printf -- '- **Waived artifact coverage-ledger:** plan predates SECTION-WIDE, rows split in slice 2\n' > "$R/analysis/src/PROJECT.md"
  [ "$(waiver)" = "plan predates SECTION-WIDE, rows split in slice 2" ] && ok "a decorated line in analysis/<name>/PROJECT.md is read, with its reason" \
    || bad "nested register waiver" "$(waiver)"
fi
grep -q 'run_launch "\$COV_NAME" "\$OUTDIR/12-coverage.log" "\$COV_KIND"' "$SUT" \
  && grep -q '\[ -n "\$COV_WAIVE" \] && { COV_KIND=info' "$SUT" \
  && ok "the coverage rung runs as info, not gate, when waived" || bad "rung not wired to the waiver"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
