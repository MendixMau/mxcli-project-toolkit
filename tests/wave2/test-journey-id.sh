#!/usr/bin/env bash
# Usage: bash test-journey-id.sh [path-to-journey-runner.js]
#
# Fixture for journey-runner.js's journeyIdProblems() (#383): a journey file without a string
# `id` used to run and write `undefined-stepN.png`, and a second journey overwrote the first's
# captures. A missing/blank/non-string id now warns and falls back to the file basename; a
# duplicate id (explicit, or a colliding fallback) is refused, naming both files.
set -uo pipefail
SUT="${1:-}"
[ -z "$SUT" ] && SUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/project-tests/e2e/journey-runner.js"
[ -f "$SUT" ] || { echo "SKIP: subject not found at $SUT"; echo "SCORE: 0/0 — nothing to test"; exit 0; }
command -v node >/dev/null 2>&1 || { echo "SKIP: node not installed"; exit 0; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
E2E="$(cd "$(dirname "$SUT")" && pwd)"
CFG="$E2E/project.config.template.js"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/journey-id.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/tests/e2e"; : > "$WORK/Fixture.mpr"
cp "$SUT" "$E2E/helpers.js" "$E2E/settle.js" "$E2E/otel.js" "$E2E/config.js" "$WORK/tests/e2e/"
cp "$CFG" "$WORK/tests/e2e/project.config.js"
IFS= read -r -d '' JS <<'JSEOF' || true
const R = require('./journey-runner.js');
if (typeof R.journeyIdProblems !== 'function') { console.log('NOFN'); process.exit(0); }
const run = (loaded, files) => { const r = R.journeyIdProblems(loaded, files);
  return JSON.stringify({ ids: loaded.map(j => j.id), warn: r.warnings, bad: r.problems }); };
const say = (k, loaded, files) => console.log(`${k} ${run(loaded, files)}`);
say('GOOD', [{ id: 'J1' }, { id: 'J2' }], ['a.journey.json', 'b.journey.json']);
say('NOID', [{ name: 'hub-nav', role: 'Administrator' }], ['journeys/hub.journey.json']);
say('BLANK', [{ id: '  ' }], ['blank.journey.json']);
say('NUM', [{ id: 7 }], ['num.journey.json']);
say('DUP', [{ id: 'J1' }, { id: 'J1' }], ['a.journey.json', 'b.journey.json']);
say('FALLCOL', [{ id: 'hub' }, { name: 'x' }], ['a.journey.json', 'hub.journey.json']);
say('TWONOID', [{}, {}], ['one.journey.json', 'two.journey.json']);
JSEOF
# Behavioural: run the runner itself. APP_PORT=1 stops it at preflight (no app, no browser).
CLI="$WORK/cli"; mkdir -p "$CLI/journeys" "$CLI/dup"
printf '%s' '{"name":"hub-nav","role":"Administrator","steps":[]}' > "$CLI/journeys/hub.journey.json"
printf '%s' '{"id":"hub","steps":[]}' > "$CLI/dup/a.journey.json"
printf '%s' '{"steps":[]}' > "$CLI/dup/hub.journey.json"
runcli() { (cd "$WORK/tests/e2e" && APP_PORT=1 node journey-runner.js "$@" 2>&1); }
W_OUT="$(runcli "$CLI/journeys/hub.journey.json")"
case "$W_OUT" in *"WARN"*"hub.journey.json"*'using "hub"'*) ok "CLI: id-less file prints a WARN naming the file basename" ;; *) bad "CLI: no WARN for id-less file" "$(printf '%s' "$W_OUT" | head -5)" ;; esac
case "$W_OUT" in *undefined*) bad "CLI: output contains undefined" "$(printf '%s' "$W_OUT" | grep undefined | head -3)" ;; *) ok "CLI: output never contains undefined" ;; esac
D_OUT="$(runcli "$CLI/dup/a.journey.json" "$CLI/dup/hub.journey.json")"; D_RC=$?
[ "$D_RC" -eq 2 ] && ok "CLI: duplicate id exits 2" || bad "CLI: duplicate id exit code $D_RC" "$(printf '%s' "$D_OUT" | head -5)"
case "$D_OUT" in *"already used by"*) ok "CLI: duplicate id prints the ERROR naming both files" ;; *) bad "CLI: no duplicate ERROR" "$(printf '%s' "$D_OUT" | head -5)" ;; esac
case "$D_OUT" in *"=== PREFLIGHT"*) bad "CLI: duplicate id reached preflight" ;; *) ok "CLI: duplicate id stops before preflight" ;; esac
OUT="$(cd "$WORK/tests/e2e" && printf '%s' "$JS" | APP_PORT=1 node - 2>&1)"
line() { printf '%s\n' "$OUT" | sed -n "s/^$1 //p"; }
if printf '%s\n' "$OUT" | grep -qx NOFN; then bad "journey-runner.js exports no journeyIdProblems"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; fi
[ -n "$(line GOOD)" ] || { echo "FAIL — harness could not require $SUT"; echo "$OUT" | tail -5; exit 1; }
has() { case "$(line "$1")" in *"$2"*) return 0 ;; *) return 1 ;; esac; }
has GOOD '"ids":["J1","J2"],"warn":[],"bad":[]' && ok "journeys with distinct ids pass quietly" || bad "good ids flagged" "$(line GOOD)"
has NOID '"ids":["hub"]' && has NOID 'journeys/hub.journey.json: journey has no \"id\"' && has NOID '"bad":[]' \
  && ok "missing id warns naming the file and falls back to the basename (no undefined)" || bad "missing id not defaulted" "$(line NOID)"
has BLANK '"ids":["blank"]' && ok "blank id falls back to the basename" || bad "blank id" "$(line BLANK)"
has NUM '"ids":["num"]' && ok "non-string id falls back to the basename" || bad "numeric id" "$(line NUM)"
has DUP '"bad":["b.journey.json: journey id \"J1\" is already used by a.journey.json' && ok "duplicate id refused, naming both files" || bad "duplicate id accepted" "$(line DUP)"
has FALLCOL 'hub.journey.json: journey id \"hub\" is already used by a.journey.json' && ok "basename fallback colliding with an explicit id is refused" || bad "fallback collision accepted" "$(line FALLCOL)"
has TWONOID '"ids":["one","two"],"warn":' && has TWONOID '"bad":[]' && ok "two id-less files get distinct basenames" || bad "id-less pair" "$(line TWONOID)"
echo ""; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
