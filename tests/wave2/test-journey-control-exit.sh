#!/usr/bin/env bash
# Usage: bash test-journey-control-exit.sh [path-to-journey-runner.js]
#
# Fixture for project-tests/e2e/journey-runner.js's exit code — runExitCode(), which decides
# what verify-module's two journey rungs report.
#
# The defect (card-disbursement requirements-driven build, 2026-09-26): the walk's rule —
# exit 1 on any FAIL or INVALID — was applied to the --positive-control run too. A control
# run's FAIL rows are its mutants being caught, so a control that proved 7 of 7 rungs exited 1,
# verify-module graded the rung FINDING, and the module read INCOMPLETE on every run: a rung
# that could not go green, and so said nothing when it went red.
#
# Golden input is CAPTURED: fixtures/journey-control/{control,walk}-run.json are that build's
# journey-findings-control.json (476 rows: PASS 468, FAIL 7, INVALID 1; 7 of 7 rungs proven) and
# journey-findings.json (79 rows, all PASS), trimmed to rung/name/verdict — `detail` (screenshot
# names, trace sequences) and `walks` are dropped because runExitCode never reads them. Cases 3-6
# derive a broken run from the captured one by editing single rows, which is the shape each
# failure takes in the field.

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
FIX="$HERE/fixtures/journey-control"
[ -f "$FIX/control-run.json" ] && [ -f "$FIX/walk-run.json" ] || { echo "FAIL — golden capture missing under $FIX"; exit 1; }
E2E="$(cd "$(dirname "$SUT")" && pwd)"
for f in helpers.js otel.js config.js; do
  [ -f "$E2E/$f" ] || { echo "FAIL — $f not beside $SUT"; exit 1; }
done
CFG="$E2E/project.config.template.js"
[ -f "$CFG" ] || CFG="$HERE/../../project-tests/e2e/project.config.template.js"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

# The runner resolves a project at require time: an .mpr two levels up and an asserted port.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/journey-exit.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/tests/e2e"; : > "$WORK/Fixture.mpr"
cp "$SUT" "$E2E/helpers.js" "$E2E/otel.js" "$E2E/config.js" "$WORK/tests/e2e/"
cp "$CFG" "$WORK/tests/e2e/project.config.js"

OUT="$(cd "$WORK/tests/e2e" && APP_PORT=1 node - "$FIX" <<'EOF' 2>&1
const fix = process.argv[2];
const R = require('./journey-runner.js');
if (typeof R.runExitCode !== 'function') { console.log('NOFN'); process.exit(0); }
const ctl = require(fix + '/control-run.json'), walk = require(fix + '/walk-run.json');
const clone = o => JSON.parse(JSON.stringify(o));
const say = (k, pc, run) => console.log(`${k} ${R.runExitCode(pc, run.results, run.mutants)}`);
say('CTL', true, ctl);
say('WALK', false, walk);
// 3. one mutant NOT caught: its [control] row goes FAIL and the ledger loses a proof.
let c = clone(ctl); c.results.find(r => r.rung === 'control').verdict = 'FAIL'; c.mutants.proven--;
say('MISS', true, c);
// 4. a rung the journey cannot express: unsupported, INVALID control row, proven < expected.
c = clone(ctl); c.results.find(r => r.rung === 'control').verdict = 'INVALID';
c.mutants.proven--; c.mutants.supported--; say('UNSUP', true, c);
// 5. login refused: no mutant ran at all — nothing proven is not "all proven".
say('NONE', true, { results: [{ rung: 'ui', name: 'login', verdict: 'INVALID' }],
                    mutants: { expected: 0, supported: 0, proven: 0, unsupported: [] } });
// 6. the walk keeps its rule: one FAIL, then one INVALID, each exits 1.
let w = clone(walk); w.results[0].verdict = 'FAIL'; say('WFAIL', false, w);
w = clone(walk); w.results[0].verdict = 'INVALID'; say('WINV', false, w);
EOF
)"
line() { printf '%s\n' "$OUT" | sed -n "s/^$1 //p"; }
if printf '%s\n' "$OUT" | grep -qx NOFN; then
  bad "journey-runner.js exports no runExitCode — the exit rule is the walk's, applied to both runs"
  echo ""; echo "PASS=$PASS FAIL=$FAIL"; exit 1
fi
[ -n "$(line CTL)" ] || { echo "FAIL — harness could not require $SUT"; echo "$OUT" | tail -5; exit 1; }

[ "$(line CTL)" = 0 ]  && ok "captured control run (7 of 7 proven, 7 mutant FAILs, 1 INVALID) exits 0" \
                       || bad "a control that proved every rung exits non-zero (the 2026-09-26 FINDING)" "$(line CTL)"
[ "$(line WALK)" = 0 ] && ok "captured walk (79 PASS) exits 0" || bad "clean walk exits non-zero" "$(line WALK)"
[ "$(line MISS)" = 1 ] && ok "a mutant that was not caught fails the control" || bad "uncaught mutant exits 0" "$(line MISS)"
[ "$(line UNSUP)" = 1 ] && ok "an unproven (unsupported) rung fails the control" || bad "unproven rung exits 0" "$(line UNSUP)"
[ "$(line NONE)" = 1 ] && ok "a control where no mutant ran (login refused) fails" || bad "zero-mutant control exits 0" "$(line NONE)"
[ "$(line WFAIL)" = 1 ] && [ "$(line WINV)" = 1 ] && ok "the walk still exits 1 on a FAIL and on an INVALID" \
                       || bad "the walk's rule changed" "FAIL→$(line WFAIL) INVALID→$(line WINV)"

if awk '/process\.exit\(/ && /runExitCode\(POSITIVE_CONTROL/ {f=1} END{exit !f}' "$SUT"; then
  ok "main exits through runExitCode(POSITIVE_CONTROL, …)"
else
  bad "main does not exit through runExitCode — the tested rule is not the one that runs"
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
