#!/usr/bin/env bash
# Usage: bash test-e2e-config-neutral.sh [path-to-project.config.template.js]
#
# Fixture: a fresh scaffold's tests/e2e/project.config.js carries no other app's values.
#
# The defect (field run 2026-11-20, a blank Mendix 11.8 app scaffolded with init-project.sh and
# run for real under `mxcli run --local`): the installed project.config.js is byte-identical to
# project.config.template.js, and the template carried one sample app's CONFIGURED values — a
# menu, a probe page, two users, a walkthrough, 14 wireframe rows. Out of the box monkey reached
# "0 of 8 target(s)" and full-app-walkthrough died at its first seed with an OQL error for an
# entity the app never had. The fix ships every CONFIGURED block empty, so each instrument stops
# with NOT CONFIGURED and `node project.config.js` lists what is still to fill.
#
# Golden input: the template itself, installed by the real bin/install-tests.sh into a temp
# project, exactly as init-project.sh does it.

set -uo pipefail

TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUT="${1:-$TOOLKIT/project-tests/e2e/project.config.template.js}"
case "$SUT" in /*) ;; *) SUT="$PWD/$SUT" ;; esac
[ -f "$SUT" ] || { echo "SKIP: subject not found at $SUT"; exit 0; }
command -v node >/dev/null 2>&1 || { echo "SKIP: node not installed"; exit 0; }
E2E="$(cd "$(dirname "$SUT")" && pwd)"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/cfgneutral.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/proj"; : > "$WORK/proj/Fresh.mpr"

# Install the way a scaffold does: the real install-tests.sh, pointed at the SUT's directory.
if [ -x "$TOOLKIT/bin/install-tests.sh" ] && [ "$E2E" = "$TOOLKIT/project-tests/e2e" ]; then
  "$TOOLKIT/bin/install-tests.sh" "$WORK/proj" >"$WORK/install.log" 2>&1 || true
fi
D="$WORK/proj/tests/e2e"
if [ ! -f "$D/project.config.js" ]; then   # a SUT outside the toolkit: copy beside its engine
  mkdir -p "$D"; cp "$E2E"/*.js "$D/" 2>/dev/null; cp "$SUT" "$D/project.config.js"
fi
cmp -s "$SUT" "$D/project.config.js" && ok "the installed project.config.js is the template" \
  || bad "installed project.config.js differs from the subject"

echo "== the CONFIGURED blocks ship empty =="
IFS= read -r -d '' JS <<'EOF' || true
const c = require(process.argv[1]);
const n = (v) => (Array.isArray(v) ? v.length : v && typeof v === 'object' ? Object.keys(v).length : -1);
console.log('NAV ' + n(c.NAV));
console.log('ROLES ' + n(c.roles));
console.log('WIRE ' + n(c.PAGE_WIREFRAME));
console.log('ACTS ' + n((c.walkthrough || {}).acts));
console.log('SEEDS ' + n((c.walkthrough || {}).seeds || []));
console.log('TPAGES ' + Object.values(c.TARGETS || {}).reduce((a, t) => a + ((t && t.pages) || []).length, 0));
console.log('EX ' + Object.values(c.exemplars || {}).filter(Boolean).length);
console.log('PROBE ' + c.probePage('/nonexistent/page-scope.json'));
console.log('READY ' + c.readySelectors.filter((s) => /mx-name-/.test(s)).length);
EOF
OUT="$(env -u PROBE_PAGE node -e "$JS" "$D/project.config.js" 2>&1)"
line() { printf '%s\n' "$OUT" | sed -n "s/^$1 //p"; }
[ "$(line NAV)" = 0 ]    && ok "NAV is empty"                  || bad "NAV ships entries" "$(line NAV)"
[ "$(line ROLES)" = 0 ]  && ok "ROLES is empty (no users)"     || bad "ROLES ships users" "$(line ROLES)"
[ "$(line WIRE)" = 0 ]   && ok "PAGE_WIREFRAME is empty"       || bad "PAGE_WIREFRAME ships rows" "$(line WIRE)"
[ "$(line ACTS)" = 0 ] && [ "$(line SEEDS)" = 0 ] && ok "WALKTHROUGH has no acts and no seeds" \
  || bad "WALKTHROUGH ships a process" "acts=$(line ACTS) seeds=$(line SEEDS)"
[ "$(line TPAGES)" = 0 ] && ok "TARGETS carry no page stops"   || bad "TARGETS ship page stops" "$(line TPAGES)"
[ "$(line EX)" = 0 ]     && ok "exemplars are unset"           || bad "exemplars name pages" "$(line EX)"
[ "$(line PROBE)" = null ] && ok "PROBE_PAGE defaults to none (page-scope fallback)" || bad "PROBE_PAGE ships a page" "$(line PROBE)"
[ "$(line READY)" = 0 ]  && ok "readySelectors name no project widget" || bad "readySelectors carry widget names" "$(line READY)"

# Generic, so it needs no list of the old values: outside comments, no quoted <Module>.<Name>.
QN="$(sed -e 's#^[[:space:]]*//.*##' -e 's#[[:space:]]//[[:space:]].*##' "$SUT" | grep -noE "'[A-Z][A-Za-z0-9_]*\.[A-Z][A-Za-z0-9_]*'" | head -3)"
[ -z "$QN" ] && ok "no quoted <Module>.<Name> literal outside comments" || bad "qualified names in code" "$QN"

echo "== a first run says what to fill =="
P="$(cd "$D" && node project.config.js 2>&1)"
for k in NAV roles walkthrough; do
  printf '%s\n' "$P" | grep -qE "^  $k .*FILL ME" && ok "node project.config.js marks $k FILL ME" \
    || bad "no FILL ME marker for $k" "$(printf '%s\n' "$P" | grep -E "^  $k " | head -1)"
done

if [ -f "$D/full-app-walkthrough.js" ] && [ -f "$D/helpers.js" ]; then
  W="$(cd "$D" && APP_PORT=1 timeout 60 node full-app-walkthrough.js 2>&1)"; RC=$?
  [ "$RC" -eq 2 ] && ok "full-app-walkthrough exits 2 on the fresh config" || bad "walkthrough exit code" "rc=$RC $(printf '%s' "$W" | tail -2)"
  printf '%s\n' "$W" | grep -q 'NOT CONFIGURED' && printf '%s\n' "$W" | grep -q 'WALKTHROUGH and ROLES' \
    && ok "it names the blocks to fill" || bad "no NOT CONFIGURED line naming WALKTHROUGH/ROLES" "$(printf '%s' "$W" | head -4)"
  [ ! -f "$D/artifacts/findings.json" ] && ok "and writes no findings.json" || bad "a findings.json was written"
else
  bad "full-app-walkthrough.js / helpers.js not installed beside the config"
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
