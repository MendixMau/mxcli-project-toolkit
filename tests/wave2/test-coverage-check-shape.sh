#!/usr/bin/env bash
# Usage: bash test-coverage-check-shape.sh [path-to-coverage-check.sh]
#
# Fixture for #208 and #209 in bin/coverage-check.sh, plus the PHANTOM CLAIM summary that
# project-bin/coverage-preflight.sh builds on it.
#
#   #208  a ledger written one row per MODEL ELEMENT (| Element | Kind | Status |) used to score
#         as "N UNCLAIMED" — read as "some work left" — instead of "cannot be measured". FAULT, rc 2.
#   #209  a BRD-prefixed pointer (F003/domainEntities/*) was always PHANTOM, because leaves are
#         enumerated as /domainEntities/...; and a plan claim matching nothing was never named.
#
# The BRDs and ledgers here are SYNTHETIC and hand-written. That is allowed for this shape of
# test: nothing here parses tool output, it lays out files and asserts verdicts. The field run
# (real plan, 8 real BRDs, 136 prefixed claims) is cited in the commit that shipped this.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUT="${1:-$ROOT/bin/coverage-check.sh}"
[ -f "$SUT" ] || { echo "usage: $0 /path/to/coverage-check.sh" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }

PASS=0; FAIL=0
ok()  { echo "  ok   — $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL — $1${2:+ ($2)}"; FAIL=$((FAIL + 1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/cov-shape.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
P="$WORK/proj"; K="$P/analysis/kb/knowledge-base/brd"
mkdir -p "$K" "$P/architecture" "$P/project-bin"
printf '{"id":"F003","domainEntities":[{"name":"A","persistent":true},{"name":"B","persistent":false}]}\n' > "$K/F003-orders.brd.json"
printf '{"id":"F001","pages":[{"name":"Home"}]}\n' > "$K/F001-home.brd.json"
B="$K/F003-orders.brd.json"
HDR='| pointer | type | title | slice | writeMode | acceptance | status |
|---|---|---|---|---|---|---|'

# --- 1. wrong-shape ledger: FAULT, not UNCLAIMED ----------------------------------------------
printf '| Element | Kind | Status |\n|---|---|---|\n| Mod.A | entity | built |\n| Mod.ACT_Save | microflow | built |\n' > "$WORK/wrong.md"
out="$(bash "$SUT" "$B" "$WORK/wrong.md" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'WRONG-SHAPE LEDGER (0 of 2 table rows' \
  && ok "element-per-row ledger faults rc 2 and says 0 of 2 rows are pointers" || bad "wrong-shape ledger" "rc=$rc"
printf '%s' "$out" | grep -q 'UNCLAIMED:' && bad "wrong-shape ledger still printed an UNCLAIMED count" || ok "no UNCLAIMED count for an unmeasurable ledger"

# --- 2. an empty but correctly-headed ledger is NOT wrong-shape -------------------------------
printf '%s\n' "$HDR" > "$WORK/empty.md"
bash "$SUT" --summary "$B" "$WORK/empty.md" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && ok "empty pointer ledger stays an ordinary finding (rc 1)" || bad "empty ledger" "rc=$rc"

# --- 3. prefixed claims: own id resolves, another BRD is skipped, unknown is PHANTOM ----------
{ printf '%s\n' "$HDR"
  printf '| F003/domainEntities/* (4) | e | t | 1 | x | a | s |\n'
  printf '| F001/pages/* | e | t | 1 | x | a | s |\n'
  printf '| F009/bogus | e | t | 1 | x | a | s |\n'; } > "$WORK/prefixed.md"
out="$(bash "$SUT" "$B" "$WORK/prefixed.md" 2>&1)"; rc=$?
printf '%s' "$out" | grep -q 'CLAIMED: *4$' && ok "F003/domainEntities/* (4) claims all 4 leaves of F003-orders" || bad "own-prefix claim" "$(printf '%s' "$out" | grep CLAIMED:)"
printf '%s' "$out" | grep -q 'OTHER-BRD: *1 ' && ok "F001/pages/* counted as OTHER-BRD, not PHANTOM" || bad "other-BRD claim"
printf '%s' "$out" | grep -q '^    F009/bogus$' && [ "$rc" -eq 1 ] && ok "F009/bogus (no such BRD) is PHANTOM, rc 1" || bad "unknown prefix" "rc=$rc"

# --- 4. preflight names a plan claim that matches nothing -------------------------------------
PRE="$ROOT/project-bin/coverage-preflight.sh"
if [ -f "$PRE" ]; then
  cp "$ROOT/project-bin/_common.sh" "$ROOT/project-bin/_claims.sh" "$PRE" "$P/project-bin/"
  printf '# plan\n\n| 1 | BUILD | entities |\nclaims: F003/domainEntities/* (4)\n\n| 2 | BUILD | typo |\nclaims: F003/domainEntity/*\n' > "$P/architecture/build-plan.md"
  out="$(cd "$P" && COVERAGE_ENGINE="$SUT" bash project-bin/coverage-preflight.sh --summary 2>&1)"; rc=$?
  printf '%s' "$out" | grep -q 'PHANTOM CLAIM: F003/domainEntity/\* matches no leaf in' && [ "$rc" -eq 1 ] \
    && ok "preflight: PHANTOM CLAIM names the typo'd plan claim, rc 1" || bad "preflight phantom claim" "rc=$rc"
  printf '%s' "$out" | grep -q 'PHANTOM CLAIM: F003/domainEntities' && bad "preflight flagged a valid claim" || ok "preflight: the valid claim is not flagged"
fi

echo ""
echo "SCORE: $PASS/$((PASS + FAIL))"
[ "$FAIL" -eq 0 ]
