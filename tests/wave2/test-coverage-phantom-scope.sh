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
mkdir -p "$K" "$P/architecture" "$P/project-bin"
cp "$SD/_common.sh" "$SD/_claims.sh" "$SUT" "$P/project-bin/"
for i in 1 2 3 4 5 6; do printf '{"id":"F00%s","pages":[{"name":"P%s"}]}\n' "$i" "$i" > "$K/F00$i-m$i.brd.json"; done
printf '#!/usr/bin/env bash\nfor a in "$@"; do case "$a" in *plan-claims*) echo phantom >> "%s";; esac; done\nexec bash "%s" "$@"\n' \
  "$WORK/runs" "$ENGINE" > "$WORK/engine.sh"; chmod +x "$WORK/engine.sh"

run() {  # $1 = claims lines -> sets out, rc, runs
  printf '# plan\n\n| 1 | BUILD | pages |\n\n```\nclaims:\n%s\n```\n' "$1" > "$P/architecture/build-plan.md"
  : > "$WORK/runs"
  out="$(cd "$P" && COVERAGE_ENGINE="$WORK/engine.sh" bash "project-bin/$(basename "$SUT")" --summary 2>&1)"; rc=$?
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

echo ""
echo "SCORE: $PASS/$((PASS + FAIL))"
[ "$FAIL" -eq 0 ]
