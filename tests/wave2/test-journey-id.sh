#!/usr/bin/env bash
# Usage: bash test-journey-id.sh [path-to-journey-runner.js]
#
# Fixture for journey-runner.js's journeyIdProblems() (#383): a journey file without a string
# `id` used to run and write `undefined-stepN.png`, and a second journey overwrote the first's
# captures. The check refuses a missing/blank/non-string id and a duplicate id, naming the file.
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
const say = (k, loaded, files) => console.log(`${k} ${JSON.stringify(R.journeyIdProblems(loaded, files))}`);
say('GOOD', [{ id: 'J1' }, { id: 'J2' }], ['a.journey.json', 'b.journey.json']);
say('NOID', [{ name: 'hub-nav', role: 'Administrator' }], ['hub.journey.json']);
say('BLANK', [{ id: '  ' }], ['blank.journey.json']);
say('NUM', [{ id: 7 }], ['num.journey.json']);
say('DUP', [{ id: 'J1' }, { id: 'J1' }], ['a.journey.json', 'b.journey.json']);
JSEOF
OUT="$(cd "$WORK/tests/e2e" && printf '%s' "$JS" | APP_PORT=1 node - 2>&1)"
line() { printf '%s\n' "$OUT" | sed -n "s/^$1 //p"; }
if printf '%s\n' "$OUT" | grep -qx NOFN; then bad "journey-runner.js exports no journeyIdProblems"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; fi
[ -n "$(line GOOD)" ] || { echo "FAIL — harness could not require $SUT"; echo "$OUT" | tail -5; exit 1; }
[ "$(line GOOD)" = '[]' ] && ok "journeys with distinct ids pass" || bad "good ids refused" "$(line GOOD)"
case "$(line NOID)" in *'hub.journey.json: journey has no \"id\"'*) ok "missing id is refused, naming the file and key" ;; *) bad "missing id accepted" "$(line NOID)" ;; esac
case "$(line BLANK)" in *'no \"id\"'*) ok "blank id refused" ;; *) bad "blank id accepted" "$(line BLANK)" ;; esac
case "$(line NUM)" in *'no \"id\"'*) ok "non-string id refused" ;; *) bad "numeric id accepted" "$(line NUM)" ;; esac
case "$(line DUP)" in *'b.journey.json'*'already used by a.journey.json'*) ok "duplicate id refused, naming both files" ;; *) bad "duplicate id accepted" "$(line DUP)" ;; esac
if awk '/journeyIdProblems\(loaded, files\)/ {f=1} /process.exit\(2\)/ && f {g=1} END{exit !g}' "$SUT"; then ok "main calls it and exits 2"; else bad "main never enforces journeyIdProblems"; fi
echo ""; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
