#!/usr/bin/env bash
# Usage: bash test-coverage-phantom-scope.sh [path-to-coverage-preflight.sh]
#
# Fixture for #446: coverage-preflight.sh's PHANTOM CLAIM pass ran the engine once per BRD with
# every claim in the plan, so 12 BRDs cost ~290 s after the measurement itself and the coverage
# rung of verify-module.sh timed out with a complete, clean log. Each BRD now gets only the
# claims it can resolve; a BRD named by no claim is not run.
#
#   S1  6 BRDs, claims naming F001 and F002 only: the phantom pass runs the engine for 2 BRDs, not
#       6, with the same verdicts (F002/bogus is a PHANTOM CLAIM, the valid F001 claim is not, rc 1);
#       a /slash claim and a claim naming no BRD file still go to every BRD and are still flagged
#   S2  BRDs in two source folders, and one named only by its .id: valid claims F002/... (other
#       folder) and F007/... (orders.brd.json, "id": "F007") are not PHANTOM, rc 0 (the engine's
#       OTHER-BRD test looks in its own folder only, so both used to be false PHANTOMs, rc 1)
#
# BRDs and plan are synthetic and hand-written: nothing here parses tool output (the engine's own
# output is parsed by the subject, as before).
set -uo pipefail
TK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUT="${1:-$TK/project-bin/coverage-preflight.sh}"
[ -f "$SUT" ] || { echo "usage: $0 /path/to/coverage-preflight.sh" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }
SD="$(cd "$(dirname "$SUT")" && pwd)"
ENGINE="$SD/../bin/coverage-check.sh"; [ -x "$ENGINE" ] || ENGINE="$TK/bin/coverage-check.sh"

PASS=0; FAIL=0
ok()  { echo "  ok   — $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL — $1${2:+ ($2)}"; FAIL=$((FAIL + 1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/cov-phantom.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
P="$WORK/proj"; K="$P/analysis/kb/knowledge-base/brd"
HDR='| pointer | type | title | slice | writeMode | acceptance | status |
|---|---|---|---|---|---|---|'
mkdir -p "$K" "$P/architecture" "$P/project-bin"
cp "$SD/_common.sh" "$SD/_claims.sh" "$SUT" "$P/project-bin/"
for i in 1 2 3 4 5 6; do printf '{"id":"F00%s","pages":[{"name":"P%s"}]}\n' "$i" "$i" > "$K/F00$i-m$i.brd.json"; done
printf '#!/usr/bin/env bash\nfor a in "$@"; do case "$a" in *plan-claims*) echo phantom >> "%s";; esac; done\nexec bash "%s" "$@"\n' \
  "$WORK/runs" "$ENGINE" > "$WORK/engine.sh"; chmod +x "$WORK/engine.sh"

run() {  # $1 = claims lines [$2.. extra args] -> sets out, rc, runs
  printf '# plan\n\n| 1 | BUILD | pages |\n\n```\nclaims:\n%s\n```\n' "$1" > "$P/architecture/build-plan.md"
  : > "$WORK/runs"
  out="$(cd "$P" && COVERAGE_ENGINE="$WORK/engine.sh" bash "project-bin/$(basename "$SUT")" --summary "${@:2}" 2>&1)"; rc=$?
  runs="$(grep -c . "$WORK/runs")"
}

run '  F001/pages/* (1)
  F002/bogus'
runs1="$runs"
v1=0; { printf '%s' "$out" | grep -q 'PHANTOM CLAIM: F002/bogus matches no leaf in .*F002-m2.brd.json' \
    && ! printf '%s' "$out" | grep -q 'PHANTOM CLAIM: F001' && [ "$rc" = 1 ]; } && v1=1

run '  F001/pages/* (1)
  /nothing/here
  F009/nope'
v2=0; { [ "$runs" = 6 ] && printf '%s' "$out" | grep -q 'PHANTOM CLAIM: /nothing/here matches no leaf in any of the 6 BRD(s)' \
    && printf '%s' "$out" | grep -q 'PHANTOM CLAIM: F009/nope matches no leaf'; } && v2=1
{ [ "$runs1" = 2 ] && [ "$v1" = 1 ] && [ "$v2" = 1 ]; } \
  && ok "S1: phantom pass ran the engine for 2 of 6 BRDs, same verdicts; /slash and unknown-prefix claims still reach all 6" \
  || bad "S1: engine runs $runs1 (want 2), verdicts F00x $v1, slash/unknown $v2" "$(printf '%s' "$out" | grep 'PHANTOM CLAIM')"

# S2: cross-folder + .id-only
rm -rf "$P/analysis"; K1="$P/analysis/a/brd"; K2="$P/analysis/b/brd"; mkdir -p "$K1" "$K2"
printf '{"id":"F001","pages":[{"name":"P1"}]}\n' > "$K1/F001-a.brd.json"
printf '{"id":"F002","pages":[{"name":"P2"}]}\n' > "$K2/F002-b.brd.json"
printf '{"id":"F007","pages":[{"name":"P7"}]}\n' > "$K1/orders.brd.json"
L="$P/architecture/modules/M/coverage-ledger"; mkdir -p "$L"   # each BRD measured clean against its own
for b in F001-a F002-b orders; do printf '%s\n| /id | e | t | 1 | x | a | s |\n| /pages/* (1) | e | t | 1 | x | a | s |\n' "$HDR" > "$L/$b.md"; done
run '  F001/pages/* (1)
  F002/pages/* (1)
  F007/pages/* (1)' --module M
{ [ "$rc" = 0 ] && ! printf '%s' "$out" | grep -q 'PHANTOM CLAIM'; } \
  && ok "S2: claims on a BRD in another folder and on a BRD named by .id are not PHANTOM, rc 0" \
  || bad "S2: rc=$rc" "$out"

echo ""
echo "SCORE: $PASS/$((PASS + FAIL))"
[ "$FAIL" -eq 0 ]
