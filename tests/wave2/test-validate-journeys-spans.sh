#!/usr/bin/env bash
# Usage: bash test-validate-journeys-spans.sh [path-to-validate-journeys.js]
#
# Fixture for examples/validate-journeys.js's `spans` rules after #150: the runner now
# evaluates a negative-only claim (`mustNotFire` with no `ordered`) against a liveness
# reference, so the validator must accept it — it used to reject it as "NEVER checked", which
# made the contract checker contradict the runner. `spans.liveness` is the new optional field
# (read only for a negative-only claim); a spans block declaring neither field is still a
# problem, and the runner now records it INVALID instead of skipping it.
#
# Input: journey files shaped like the toolkit's own journeys (the validator's selftest base),
# written here and checked through the real CLI. Also runs the validator's --selftest, which
# watches every rule go red. T4 (#520): --brd prefers the .brd.json over a derived
# .mx-brd.json with the same id; a derived file alone still answers for its id.

set -uo pipefail

SUT="${1:-}"
[ -z "$SUT" ] && SUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/examples/validate-journeys.js"
if [ ! -f "$SUT" ]; then
  echo "SKIP: subject not found at $SUT"
  echo "SCORE: 0/0 — nothing to test"
  exit 0
fi
command -v node >/dev/null 2>&1 || { echo "SKIP: node not installed"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/         got: /'; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/validate-spans.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# One journey per case; only the step's `spans` differs.
mk() {
  cat > "$WORK/$1.journey.json" <<EOF
{ "id": "J-$1", "requirement": [],
  "seeds": [{ "name": "a", "sql": "SELECT X AS x FROM M.E LIMIT 1" }],
  "steps": [{ "name": "Cancel reset", "actions": [{ "do": "click", "widget": "btnCancel" }],
              "ui": { "ready": ".mx-name-dvSettings", "textPresent": ["{{a}}"] },
              "spans": $2 }] }
EOF
}
mk negonly   '{ "mustNotFire": ["ACT_Settings_ResetAll"] }'
mk negempty  '{ "ordered": [], "mustNotFire": ["ACT_Settings_ResetAll"] }'
mk negdecl   '{ "mustNotFire": ["ACT_Settings_ResetAll"], "liveness": "Settings.DS_Settings_Get" }'
mk positive  '{ "ordered": ["Settings.ACT_Save"], "mustNotFire": ["ACT_Settings_ResetAll"] }'
mk nothing   '{ "ordered": [] }'
mk legacy    '[{ "mf": "Settings.ACT_Save", "status": "OK" }]'
mk livenum   '{ "mustNotFire": ["ACT_Settings_ResetAll"], "liveness": 5 }'
mk livepos   '{ "ordered": ["Settings.ACT_Save"], "liveness": "Settings.DS_Settings_Get" }'
mk badre     '{ "mustNotFire": ["ACT_(Reset"] }'

run() { OUT="$(node "$SUT" "$WORK/$1.journey.json" 2>&1)"; RC=$?; }

echo "== T1: negative-only claims are accepted (the runner evaluates them since #150) =="
for c in negonly negempty negdecl positive; do
  run "$c"
  [ "$RC" -eq 0 ] && ok "$c → no problems" || bad "$c rejected" "$OUT"
done
run negonly
grep -q 'NEVER checked' <<< "$OUT" && bad "still claims the negative-only claim is never checked" "$OUT" || ok "no 'NEVER checked' message"

echo "== T2: what the runner cannot read is still a problem =="
run nothing; { [ "$RC" -eq 1 ] && grep -q 'declares nothing the runner reads' <<< "$OUT"; } \
  && ok "empty spans block → problem, says the runner records it INVALID" || bad "empty spans block accepted" "$OUT"
grep -q 'records it INVALID' <<< "$OUT" && ok "message matches the runner's loud INVALID" || bad "message does not mention INVALID" "$OUT"
run legacy; { [ "$RC" -eq 1 ] && grep -q 'is an array — the old shape' <<< "$OUT"; } && ok "array-shaped spans → problem naming the old shape" || bad "legacy array shape accepted or not named" "$OUT"
run livenum; { [ "$RC" -eq 1 ] && grep -q 'liveness: must be a non-empty string' <<< "$OUT"; } \
  && ok "liveness of the wrong type → problem" || bad "bad liveness accepted" "$OUT"
run livepos; { [ "$RC" -eq 1 ] && grep -q 'only read for a negative-only claim' <<< "$OUT"; } \
  && ok "liveness beside ordered → problem (never read)" || bad "unread liveness accepted" "$OUT"
run badre; { [ "$RC" -eq 1 ] && grep -q 'not a valid regex' <<< "$OUT"; } \
  && ok "mustNotFire that is not a regex → problem" || bad "invalid regex accepted" "$OUT"

echo "== T4: --brd with a derived .mx-brd.json of the same id beside the .brd.json (#520) =="
# The issue's three-file repro. The .mx-brd.json lists after the .brd.json, which is how it used to win.
B="$WORK/brd"; mkdir -p "$B"
printf '%s\n' '{"id":"F101","useCases":[{"mainFlow":["1. go"]}]}' > "$B/F101-x.brd.json"
printf '%s\n' '{"id":"F101","kind":"mx","generated":"2026-10-21"}' > "$B/F101-x.mx-brd.json"
printf '%s\n' '{"id":"F102","kind":"mx","useCases":[{"mainFlow":["1. only derived"]}]}' > "$B/F102-y.mx-brd.json"
printf '%s\n' '{"id":"J","requirement":["F101#/useCases/0/mainFlow/0","F102#/useCases/0/mainFlow/0"],"steps":[{"name":"s","actions":[{"do":"wait","ms":1}]}]}' > "$WORK/ptr.journey.json"
printf '%s\n' '{"id":"J2","requirement":["F101#/useCases/3/mainFlow/0"],"steps":[{"name":"s","actions":[{"do":"wait","ms":1}]}]}' > "$WORK/dangling.journey.json"
OUT="$(node "$SUT" --brd "$B" "$WORK/ptr.journey.json" 2>&1)"; RC=$?
{ [ "$RC" -eq 0 ] && ! grep -q DANGLING <<< "$OUT"; } && ok "valid pointer into the .brd.json resolves with the .mx-brd.json beside it" || bad "pointer read DANGLING with a .mx-brd.json beside the BRD" "$OUT"
grep -q '1 .mx-brd.json file(s) not read' <<< "$OUT" && ok "one notice names the derived file left unread" || bad "no notice for the derived file left unread" "$OUT"
OUT="$(node "$SUT" --brd "$B" "$WORK/dangling.journey.json" 2>&1)"; RC=$?
{ [ "$RC" -eq 1 ] && grep -q 'DANGLING' <<< "$OUT"; } && ok "a pointer that does not resolve in the BRD is still DANGLING" || bad "real DANGLING pointer not reported" "$OUT"

echo "== T3: the validator's own selftest =="
ST="$(node "$SUT" --selftest 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && ok "--selftest: every rule watched going red, clean cases green" || bad "--selftest failed" "$(printf '%s' "$ST" | grep -A2 '^FAIL' | head -12)"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
