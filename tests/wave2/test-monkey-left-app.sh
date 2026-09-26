#!/usr/bin/env bash
# Usage: bash test-monkey-left-app.sh [path-to-monkey.js]
#
# Fixture for project-tests/e2e/monkey.js's leftApp() and SIGN_OUT — the two guards that keep
# the harness's own moves from being scored as app crashes.
#
# The defect (card-disbursement requirements-driven build, 2026-09-26, seed 410855898): a
# backAfterSubmit round clicked "Switch theme" (a control that pushes no history entry), so
# Back left the app for login.html, then about:blank. The oracle scored each non-app page
# "blank page", every later round on the target scored it again, and the second target was
# never reached: 13 observations, 10 crash-class, one target unfuzzed, no app defect. With the
# Back fix in place, a reloadMidFlow round clicked the shell's "Sign out" and lost the target
# the same way. After both fixes the same seed read 26 observations, 0 crash-class.
#
# Golden input is CAPTURED: the URLs below are the ones that run's probe log recorded
# (url=… on each CRASH row, and the app routes it navigated), and the labels are the two
# controls clicked in it. The origin is the run's own baseUrl.

set -uo pipefail

SUT="${1:-}"
[ -z "$SUT" ] && SUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/project-tests/e2e/monkey.js"
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

# monkey.js resolves a project at require time: an .mpr two levels up and an asserted port.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/monkey-left.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/tests/e2e"; : > "$WORK/Fixture.mpr"
cp "$SUT" "$E2E/helpers.js" "$E2E/otel.js" "$E2E/config.js" "$WORK/tests/e2e/"
cp "$CFG" "$WORK/tests/e2e/project.config.js"

# An old monkey runs main on require and would launch a browser: bound it.
OUT="$(cd "$WORK/tests/e2e" && APP_PORT=1 timeout 30 node - <<'EOF' 2>&1
const M = require('./monkey.js');
if (typeof M.leftApp !== 'function' || !(M.SIGN_OUT instanceof RegExp)) { console.log('NOFN'); process.exit(0); }
const base = 'http://localhost:8080';
const L = (k, url, b) => console.log(`${k} ${M.leftApp(url, b === undefined ? base : b)}`);
L('LOGIN', 'http://localhost:8080/login.html');
L('LOGINQ', 'http://localhost:8080/login.html?profile=Responsive');
L('BLANK', 'about:blank');
L('EMPTY', '');
L('ROOT', 'http://localhost:8080/');
L('BARE', 'http://localhost:8080');
L('INDEX', 'http://localhost:8080/index.html');
L('CASES', 'http://localhost:8080/p/cases');
L('MOCK', 'http://localhost:8080/p/mock-console');
L('OTHER', 'http://localhost:80801/p/cases');
L('SLASHBASE', 'http://localhost:8080/p/cases', base + '/');
const S = t => console.log(`S:${t} ${M.SIGN_OUT.test(t)}`);
['Sign out', 'Log off', 'Logout', 'Switch theme', 'Signature', 'Log in'].forEach(S);
process.exit(0);
EOF
)"
line() { printf '%s\n' "$OUT" | sed -n "s/^$1 //p"; }
if printf '%s\n' "$OUT" | grep -qx NOFN || [ -z "$(line LOGIN)" ]; then
  bad "monkey.js exports no leftApp/SIGN_OUT (or ran main on require) — a round that leaves the app is scored as an app crash"
  printf '%s\n' "$OUT" | tail -3 | sed 's/^/         /'
  echo ""; echo "PASS=$PASS FAIL=$FAIL"; exit 1
fi

[ "$(line LOGIN)" = true ] && [ "$(line LOGINQ)" = true ] && ok "login.html (captured, with and without a query) is outside the app" \
  || bad "login.html counted as in-app — the 2026-09-26 cascade" "$(line LOGIN)/$(line LOGINQ)"
[ "$(line BLANK)" = true ] && [ "$(line EMPTY)" = true ] && ok "about:blank (captured) and an empty url are outside the app" \
  || bad "about:blank counted as in-app" "$(line BLANK)/$(line EMPTY)"
[ "$(line ROOT)" = false ] && [ "$(line BARE)" = false ] && [ "$(line INDEX)" = false ] \
  && ok "the app root, bare origin and index.html are in the app" || bad "app root counted as outside" "$(line ROOT)/$(line BARE)/$(line INDEX)"
[ "$(line CASES)" = false ] && [ "$(line MOCK)" = false ] && ok "captured app routes (/p/cases, /p/mock-console) are in the app" \
  || bad "an app route counted as outside — every round would re-land" "$(line CASES)/$(line MOCK)"
[ "$(line OTHER)" = true ] && ok "a lookalike origin (port prefix match) is outside the app" || bad "prefix match leaks another origin in" "$(line OTHER)"
[ "$(line SLASHBASE)" = false ] && ok "a baseUrl with a trailing slash still matches its routes" || bad "trailing-slash baseUrl breaks the match" "$(line SLASHBASE)"

s() { printf '%s\n' "$OUT" | sed -n "s/^S:$1 //p"; }
[ "$(s 'Sign out')" = true ] && [ "$(s 'Log off')" = true ] && [ "$(s 'Logout')" = true ] \
  && ok "SIGN_OUT matches Sign out (captured), Log off, Logout" || bad "a sign-out label is not excluded" "$(s 'Sign out')/$(s 'Log off')/$(s 'Logout')"
[ "$(s 'Switch theme')" = false ] && [ "$(s 'Signature')" = false ] && [ "$(s 'Log in')" = false ] \
  && ok "SIGN_OUT leaves Switch theme (captured), Signature, Log in fuzzable" || bad "SIGN_OUT over-matches" "$(s 'Switch theme')/$(s 'Signature')/$(s 'Log in')"

# The tested functions must be the ones the rounds use.
awk '/hasNotText: *SIGN_OUT/ {f=1} END{exit !f}' "$SUT" && ok "round()'s button locator filters SIGN_OUT" \
  || bad "the button locator does not filter SIGN_OUT — the tested regex is not the one that runs"
awk '/goBack\(/ {b=1} b && /leftApp\(page\.url\(\)/ {l=1} l && /goForward\(/ {f=1} END{exit !f}' "$SUT" \
  && ok "backAfterSubmit returns with Forward when Back left the app" || bad "backAfterSubmit does not check leftApp after Back"
grep -q "'lost'" "$SUT" && ok "a target lost mid-run is reported with its unfuzzed round count, not silently re-scored" \
  || bad "no 'lost' finding — an abandoned target reads as fuzzed"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
