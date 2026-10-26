#!/usr/bin/env bash
# Usage: bash test-harness-scan.sh [path-to-harness-scan.sh]
#
# Fixture for project-bin/harness-scan.sh (#567): hand-written browser test scripts that sign in
# without the toolkit's harness.
#   H1  signs in, never signs out            -> no-sign-out, exit 1
#   H2  signs in, only GETs /logout          -> get-logout-only, exit 1
#   H3  signs in, xas logout / mx.logout     -> own-sign-out, exit 0 (noted, not judged)
#   H4  requires helpers.js / journey-runner -> not listed
#   H5  the toolkit's engine files in tests/e2e/ and anything under node_modules/ -> not scanned
#   H6  the engine list in the scan names every .js install-manifest.sh installs into tests/e2e/
#   H7  no test folders at all               -> exit 0, "0 script(s) scanned"
set -uo pipefail
TK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUT="${1:-$TK/project-bin/harness-scan.sh}"
[ -f "$SUT" ] || { echo "usage: $0 /path/to/harness-scan.sh" >&2; exit 2; }
SD="$(cd "$(dirname "$SUT")" && pwd)"

PASS=0; FAIL=0
ok()  { echo "  ok   — $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL — $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/         /'; FAIL=$((FAIL + 1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/hscan.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
P="$WORK/proj"; mkdir -p "$P/bin" "$P/tests/e2e" "$P/tests/acceptance" "$P/e2e/node_modules/x"
cp "$SD/_common.sh" "$SUT" "$P/bin/"
scan() { out="$(cd "$P" && PROJECT_ROOT="$P" bash "$P/bin/harness-scan.sh" 2>&1)"; rc=$?; }

# H7 first, on an empty project.
scan
{ [ "$rc" = 0 ] && printf '%s' "$out" | grep -q '0 script(s) scanned'; } \
  && ok "H7: no test scripts: exit 0, 0 scanned" || bad "H7: empty project rc=$rc" "$out"

printf "const { chromium } = require('playwright');\nawait p.goto(base + '/login.html');\nawait b.close();\n" > "$P/tests/acceptance/a-nosignout.js"
printf "await page.fill('#usernameInput', u);\nawait page.goto(base + '/logout');\n" > "$P/tests/acceptance/b-getlogout.ts"
printf "await page.goto(url + '/login.html');\nawait page.evaluate(() => mx.logout());\n" > "$P/e2e/c-own.mjs"
printf "const { login, logout } = require('../e2e/helpers.js');\nawait page.goto(base + '/login.html');\n" > "$P/tests/acceptance/d-harness.js"
printf "import { run } from './journey-runner';\n// opens /login.html through the runner\n" > "$P/tests/acceptance/e-runner.mjs"
cp "$TK/project-tests/e2e/helpers.js" "$TK/project-tests/e2e/monkey.js" "$P/tests/e2e/"
printf "page.goto('/login.html')\n" > "$P/e2e/node_modules/x/index.js"
scan
{ [ "$rc" = 1 ] && printf '%s' "$out" | grep -q '^no-sign-out	tests/acceptance/a-nosignout.js'; } \
  && ok "H1: signs in, never signs out -> no-sign-out, exit 1" || bad "H1 rc=$rc" "$out"
printf '%s' "$out" | grep -q '^get-logout-only	tests/acceptance/b-getlogout.ts' \
  && ok "H2: GET /logout only -> get-logout-only" || bad "H2" "$out"
printf '%s' "$out" | grep -q '^own-sign-out	e2e/c-own.mjs' \
  && ok "H3: mx.logout -> own-sign-out (noted)" || bad "H3" "$out"
{ ! printf '%s' "$out" | grep -q 'd-harness\|e-runner'; } \
  && ok "H4: scripts through helpers.js / journey-runner are not listed" || bad "H4" "$out"
{ ! printf '%s\n' "$out" | cut -f2 | grep -q '^tests/e2e/\|node_modules'; } \
  && printf '%s' "$out" | grep -q '5 script(s) scanned, 5 sign in, 2 through the harness, 1 own sign-out, 2 at risk' \
  && ok "H5: engine files and node_modules not scanned (5 scanned, 2 at risk)" || bad "H5" "$out"

rm -f "$P/tests/acceptance/a-nosignout.js" "$P/tests/acceptance/b-getlogout.ts"
scan
[ "$rc" = 0 ] && ok "H3: own sign-out alone does not set exit 1" || bad "H3 exit rc=$rc" "$out"

# H6: the scan's engine list against the install manifest it mirrors.
eval "$(grep -E '^MXTK_PROJECT_TESTS(_TEMPLATE)?=' "$TK/bin/lib/install-manifest.sh")"
missing=""
for f in $MXTK_PROJECT_TESTS ${MXTK_PROJECT_TESTS_TEMPLATE:-}; do
  case "$f" in *.js) grep -q " $f " "$SUT" || missing="$missing $f" ;; esac
done
[ -z "$missing" ] && ok "H6: every engine .js install-manifest.sh installs is excluded by name" \
  || bad "H6: engine files the scan would flag as hand-written:$missing"

echo ""
echo "SCORE: $PASS/$((PASS + FAIL))"
[ "$FAIL" -eq 0 ]
