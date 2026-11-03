#!/usr/bin/env bash
# Usage: bash test-journey-rerun.sh [path-to-journey-runner.js]
#
# Fixture for #492: fix-loop reruns. `--only=<id,...>` and `--rerun-failed[=<findings.json>]` walk a
# subset of the journeys, plus every journey that leaves a token a chosen one requires (so declared
# state is rebuilt), and write a separate *-rerun.json slot: a partial run must never replace the full
# run's findings (the stale-slot defect the runner already guards against for the positive control).
#
# Part A runs failedJourneyIds / selectJourneys on stand-in findings. Part B runs the real CLI with
# no TEST_USER, so the suite preflight aborts before any browser opens: the selection line, the exit
# code and which slot the aborted findings land in are all observable without an app.

set -uo pipefail

SUT="${1:-}"
[ -z "$SUT" ] && SUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/project-tests/e2e/journey-runner.js"
if [ ! -f "$SUT" ]; then
  echo "SKIP: subject not found at $SUT"
  echo "SCORE: 0/0 — nothing to test"
  exit 0
fi
command -v node >/dev/null 2>&1 || { echo "SKIP: node not installed"; exit 0; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
E2E="$(cd "$(dirname "$SUT")" && pwd)"
CFG="$E2E/project.config.template.js"
[ -f "$CFG" ] || CFG="$HERE/../../project-tests/e2e/project.config.template.js"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/         got: /'; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/journey-rerun.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/tests/e2e/artifacts" "$WORK/journeys"; : > "$WORK/Fixture.mpr"
cp "$SUT" "$E2E/helpers.js" "$E2E/settle.js" "$E2E/otel.js" "$E2E/config.js" "$WORK/tests/e2e/"
cp "$CFG" "$WORK/tests/e2e/project.config.js"

J="$WORK/journeys"
printf '%s' '{"id":"J-MAKE","leaves":["order-open"],"steps":[{"name":"make","actions":[]}]}' > "$J/a.journey.json"
printf '%s' '{"id":"J-SHIP","requires":["order-open"],"steps":[{"name":"ship","actions":[]}]}' > "$J/b.journey.json"
printf '%s' '{"id":"J-LIST","steps":[{"name":"list","actions":[]}]}' > "$J/c.journey.json"
# The last full run: J-SHIP failed a step check, the other two were clean.
cat > "$WORK/tests/e2e/artifacts/journey-findings.json" <<'EOF'
{"capturedAt":"2026-10-26T00:00:00Z","results":[
 {"rung":"ui","name":"make: reached","verdict":"PASS"},
 {"rung":"ui","name":"ship: reached","verdict":"FAIL"},
 {"rung":"ui","name":"list: reached","verdict":"PASS"}],
 "walks":[{"journey":"J-MAKE","steps":[{"checks":[{"verdict":"PASS"}]}]},
          {"journey":"J-SHIP","steps":[{"checks":[{"verdict":"FAIL"}]}]},
          {"journey":"J-LIST","steps":[{"checks":[{"verdict":"PASS"}]}]}]}
EOF
FULL_BEFORE="$(cat "$WORK/tests/e2e/artifacts/journey-findings.json")"

echo "A. selection, as functions"
IFS= read -r -d '' JS <<'JSEOF' || true
const R = require('./journey-runner.js');
if (typeof R.failedJourneyIds !== 'function' || typeof R.selectJourneys !== 'function') { console.log('NOFN'); process.exit(0); }
const out = (k, v) => console.log(`${k} ${JSON.stringify(v)}`);
const f = JSON.parse(require('fs').readFileSync('artifacts/journey-findings.json', 'utf8'));
out('F:ids', [...R.failedJourneyIds(f).ids]);
out('F:never', [...R.failedJourneyIds({ results: [{ rung: 'setup', name: 'J-X: app up', verdict: 'INVALID' },
  { rung: 'ui', name: 'J-Y: persona', verdict: 'INVALID' }, { rung: 'ui', name: 'step one: reached', verdict: 'FAIL' }], walks: [] }).ids]);
out('F:outcome', [...R.failedJourneyIds({ results: [{ rung: 'outcome', name: 'J-A end state: paid', verdict: 'FAIL' }],
                                          walks: [{ journey: 'J-A', steps: [] }] }).ids]);
out('F:dataword', [...R.failedJourneyIds({ results: [{ rung: 'data', name: 'Submit: Order +1', verdict: 'FAIL' },
  { rung: 'setup', name: 'Locate: geolocation', verdict: 'INVALID' }, { rung: 'setup', name: 'J-Z: precondition', verdict: 'INVALID' }],
  walks: [{ journey: 'J-W', steps: [] }] }).ids]);
out('F:aborted', !!R.failedJourneyIds({ aborted: 'preflight', results: [], walks: [] }).error);
const js = [{ id: 'J-MAKE', leaves: ['order-open'] }, { id: 'J-SHIP', requires: ['order-open'], leaves: ['shipped'] },
            { id: 'J-INVOICE', requires: ['shipped'] }, { id: 'J-LIST' }];
const s = R.selectJourneys(js, new Set(['J-INVOICE']));
out('S:closure', [s.selected.map(j => j.id), s.added]);
out('S:unknown', R.selectJourneys(js, new Set(['J-NOPE'])).unknown);
out('S:fixture', R.selectJourneys([{ id: 'J-B', requires: ['seeded'] }], new Set(['J-B'])).selected.map(j => j.id));
JSEOF
OUT="$(cd "$WORK/tests/e2e" && printf '%s' "$JS" | APP_PORT=1 timeout 30 node - 2>&1)"
get() { printf '%s\n' "$OUT" | sed -n "s/^$1 //p"; }
if printf '%s\n' "$OUT" | grep -qx NOFN || [ -z "$(get F:ids)" ]; then
  bad "journey-runner.js exports no failedJourneyIds / selectJourneys (#492)" "$(printf '%s\n' "$OUT" | tail -3)"
else
  [ "$(get F:ids)" = '["J-SHIP"]' ] && ok "a journey with a non-PASS step check is the one to rerun; clean ones are not" || bad "failed ids" "$(get F:ids)"
  [ "$(get F:never)" = '["J-X","J-Y"]' ] && ok "journeys never walked (APP-DOWN setup row, persona refusal) are rerun too; a step row is not read as a journey" || bad "never-walked journey" "$(get F:never)"
  [ "$(get F:outcome)" = '["J-A"]' ] && ok "a failed outcome row reruns its journey" || bad "outcome row" "$(get F:outcome)"
  [ "$(get F:dataword)" = '["J-Z"]' ] && ok "a non-PASS data/setup row whose step name is one word (Submit:, Locate:) is not read as a journey id" || bad "single-word step name read as a journey" "$(get F:dataword)"
  [ "$(get F:aborted)" = true ] && ok "an aborted findings file is refused — nothing to rerun from" || bad "aborted file accepted" "$(get F:aborted)"
  [ "$(get S:closure)" = '[["J-MAKE","J-SHIP","J-INVOICE"],["J-SHIP","J-MAKE"]]' ] && ok "the journeys that leave what a chosen one requires are walked too, transitively, in run order" || bad "requires closure" "$(get S:closure)"
  [ "$(get S:unknown)" = '["J-NOPE"]' ] && ok "an unknown id is named, never dropped" || bad "unknown id" "$(get S:unknown)"
  [ "$(get S:fixture)" = '["J-B"]' ] && ok "a token no journey leaves stays the fixture's job (no refusal)" || bad "fixture token" "$(get S:fixture)"
fi

echo "B. the CLI: selection line, exit code, separate slot"
run() { (cd "$WORK/tests/e2e" && env -u TEST_USER -u TEST_PASS APP_PORT=1 APP_PROBE=0 timeout 60 node journey-runner.js "$J/a.journey.json" "$J/b.journey.json" "$J/c.journey.json" "$@" 2>&1); }
O1="$(run --rerun-failed)"; R1=$?
printf '%s\n' "$O1" | grep -q 'PARTIAL RUN (--rerun-failed): 2 of 3 journeys — J-MAKE, J-SHIP (added because a chosen journey requires what they leave: J-MAKE)' \
  && ok "--rerun-failed picks J-SHIP from the last findings and adds J-MAKE for its requires" || bad "rerun selection line" "$(printf '%s\n' "$O1" | head -5)"
[ -f "$WORK/tests/e2e/artifacts/journey-findings-rerun.json" ] && [ "$(cat "$WORK/tests/e2e/artifacts/journey-findings.json")" = "$FULL_BEFORE" ] \
  && ok "the partial run writes journey-findings-rerun.json; the full run's slot is untouched" || bad "partial run touched the full slot, or wrote no rerun slot" "exit $R1"
O2="$(run --only=J-LIST)"
printf '%s\n' "$O2" | grep -q 'PARTIAL RUN (--only): 1 of 3 journeys — J-LIST$' && ok "--only=J-LIST walks just that journey" || bad "--only selection" "$(printf '%s\n' "$O2" | head -5)"
O3="$(run --only=J-NOPE)"; R3=$?
[ "$R3" -eq 2 ] && printf '%s\n' "$O3" | grep -q 'no journey with id J-NOPE' && ok "--only with an unknown id exits 2 naming it" || bad "unknown --only id" "exit $R3: $(printf '%s\n' "$O3" | head -3)"
# A data-rung row with a one-word step name must not stop the rerun with "no journey with id".
cp "$WORK/tests/e2e/artifacts/journey-findings.json" "$WORK/full.keep"
node -e 'const fs=require("fs"),p=process.argv[1],f=JSON.parse(fs.readFileSync(p,"utf8"));f.results.push({rung:"data",name:"Submit: Order +1",verdict:"FAIL"});fs.writeFileSync(p,JSON.stringify(f))' "$WORK/tests/e2e/artifacts/journey-findings.json"
O6="$(run --rerun-failed)"; R6=$?
{ [ "$R6" -ne 2 ] || ! printf '%s\n' "$O6" | grep -q 'no journey with id'; } && printf '%s\n' "$O6" | grep -q 'PARTIAL RUN (--rerun-failed): 2 of 3 journeys' \
  && ok "--rerun-failed ignores a data row named 'Submit: …' and reruns the failed journey" || bad "data-rung row stopped the rerun" "exit $R6: $(printf '%s\n' "$O6" | head -3)"
cp "$WORK/full.keep" "$WORK/tests/e2e/artifacts/journey-findings.json"
rm -f "$WORK/tests/e2e/artifacts/journey-findings.json"
O4="$(run --rerun-failed)"; R4=$?
[ "$R4" -eq 2 ] && printf '%s\n' "$O4" | grep -q 'run the journeys in full first' && ok "--rerun-failed with no last findings exits 2 and says to run in full" || bad "missing findings" "exit $R4: $(printf '%s\n' "$O4" | head -3)"
O5="$(run)"
printf '%s\n' "$O5" | grep -q 'PARTIAL RUN' && bad "a plain run printed PARTIAL RUN" || ok "a run without the flags is a full run, as before"

echo
echo "SCORE: $PASS/$((PASS+FAIL))"
[ "$FAIL" -eq 0 ]
