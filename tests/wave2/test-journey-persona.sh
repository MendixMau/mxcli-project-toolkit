#!/usr/bin/env bash
# Usage: bash test-journey-persona.sh [path-to-journey-runner.js]
#
# Fixture for project-tests/e2e/journey-runner.js's persona check — personaMismatch(), which
# decides whether a journey may run under the user this run signed in as.
#
# The defect (#149, 2026-09-25): a journey's `persona` was printed and nothing else, so a
# journey declaring a non-admin persona walked green under TEST_USER=admin — a pass for the
# wrong reason, since admin bypasses the grants the journey claims to prove. Inputs are the
# two fields the check reads (`persona`, the signed-in user name); nothing else is consulted.

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
for f in helpers.js otel.js config.js; do
  [ -f "$E2E/$f" ] || { echo "FAIL — $f not beside $SUT"; exit 1; }
done
CFG="$E2E/project.config.template.js"
[ -f "$CFG" ] || CFG="$HERE/../../project-tests/e2e/project.config.template.js"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

# The runner resolves a project at require time: an .mpr two levels up and an asserted port.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/journey-persona.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/tests/e2e"; : > "$WORK/Fixture.mpr"
cp "$SUT" "$E2E/helpers.js" "$E2E/otel.js" "$E2E/config.js" "$WORK/tests/e2e/"
cp "$CFG" "$WORK/tests/e2e/project.config.js"

IFS= read -r -d '' JS <<'JSEOF' || true
const R = require('./journey-runner.js');
if (typeof R.personaMismatch !== 'function') { console.log('NOFN'); process.exit(0); }
const say = (k, j, u) => { const d = R.personaMismatch(j, u); console.log(`${k} ${d === null ? 'RUN' : 'SKIP ' + d}`); };
say('SAME',  { id: 'J1', persona: 'Reviewer' }, 'Reviewer');
say('ADMIN', { id: 'J1', persona: 'Reviewer' }, 'MxAdmin');
say('NONE',  { id: 'J1' }, 'MxAdmin');
JSEOF
OUT="$(cd "$WORK/tests/e2e" && printf '%s' "$JS" | APP_PORT=1 node - 2>&1)"
line() { printf '%s\n' "$OUT" | sed -n "s/^$1 //p"; }
if printf '%s\n' "$OUT" | grep -qx NOFN; then
  bad "journey-runner.js exports no personaMismatch — persona is still decoration"
  echo ""; echo "PASS=$PASS FAIL=$FAIL"; exit 1
fi
[ -n "$(line SAME)" ] || { echo "FAIL — harness could not require $SUT"; echo "$OUT" | tail -5; exit 1; }

[ "$(line SAME)" = RUN ] && ok "persona equal to the signed-in user runs" || bad "matching persona refused" "$(line SAME)"
case "$(line ADMIN)" in
  SKIP*Reviewer*MxAdmin*TEST_USER=Reviewer*) ok "persona Reviewer under MxAdmin is refused, naming both users and the remedy" ;;
  *) bad "a journey for Reviewer runs under MxAdmin (the #149 false pass)" "$(line ADMIN)" ;;
esac
[ "$(line NONE)" = RUN ] && ok "a journey with no persona runs as whoever signed in" || bad "persona-less journey refused" "$(line NONE)"

if awk '/personaMismatch\(j, li\.user\)/ {f=1} END{exit !f}' "$SUT"; then
  ok "main checks every journey against the signed-in user"
else
  bad "main never calls personaMismatch(j, li.user) — the tested rule is not the one that runs"
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
