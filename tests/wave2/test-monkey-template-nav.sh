#!/usr/bin/env bash
# Usage: bash test-monkey-template-nav.sh [path-to-monkey.js]
#
# Fixture for project-tests/e2e/monkey.js's "not measured" exits and config.js's
# navIsTemplate() (#679).
#
# The defect (field run, toolkit c9dedb11): a new project's first monkey run used the NAV copied
# from project.config.template.js, which describes the toolkit's sample app. None of its 8 menu
# captions were in the app, every target was "not reached" (info), and the run printed
# "reached 0 of 8 target(s)" and exited 0, so verify-module showed the monkey rung without a
# fault. "0 of 8 reached" and "8 of 8 reached, no crash" were the same exit code.
#
# Golden input: the template NAV is project.config.template.js itself, copied in as the
# project's project.config.js exactly as bin/install-tests.sh seeds a new project.
#
# Follow-up (field run 2026-11-20, a real Mendix 11.8 app): the template now ships NAV EMPTY, and
# an empty NAV reached "0 of 0 target(s)" and exited 0 after a login. An empty NAV now exits 2
# before the browser, and exitCode() treats 0 targets as not measured. The old sample NAV is still
# recognised (config.js TEMPLATE_NAV) for project.config.js files installed before the change.

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

WORK="$(mktemp -d "${TMPDIR:-/tmp}/monkey-nav.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/tests/e2e"; : > "$WORK/Fixture.mpr"
cp "$SUT" "$E2E/helpers.js" "$E2E/otel.js" "$E2E/config.js" "$WORK/tests/e2e/"
cp "$CFG" "$WORK/tests/e2e/project.config.js"

echo "== config.js: navIsTemplate() against the old sample and the shipped (empty) template =="
IFS= read -r -d '' JS <<'EOF' || true
const C = require('./config.js');
if (typeof C.navIsTemplate !== 'function') { console.log('NOFN'); process.exit(0); }
const S = C.TEMPLATE_NAV;
console.log('TPL ' + C.navIsTemplate({ nav: S }));
console.log('EMPTY ' + Object.keys(require('./project.config.js').NAV || {}).length + ',' + C.navIsTemplate());
const edited = Object.assign({}, S, { dashboard: ['Home'] });
console.log('EDITED ' + C.navIsTemplate({ nav: edited }));
const reordered = {}; for (const k of Object.keys(S).reverse()) reordered[k] = S[k];
console.log('REORDER ' + C.navIsTemplate({ nav: reordered }));
console.log('ALLOW ' + C.navIsTemplate({ nav: S, env: { ALLOW_TEMPLATE_NAV: '1' } }));
EOF
OUT="$(cd "$WORK/tests/e2e" && printf '%s' "$JS" | APP_PORT=1 node - 2>&1)"
line() { printf '%s\n' "$OUT" | sed -n "s/^$1 //p"; }
if printf '%s\n' "$OUT" | grep -qx NOFN; then bad "#679 config.js exports no navIsTemplate()"; else
  [ "$(line TPL)" = true ]      && ok "#679 the old sample NAV, unedited, reads as the sample" || bad "#679 sample NAV not detected" "$OUT"
  [ "$(line EMPTY)" = "0,false" ] && ok "the shipped template's NAV is empty (and is not 'the sample')" || bad "template NAV not empty" "$(line EMPTY)"
  [ "$(line EDITED)" = false ]  && ok "one edited caption → not the sample" || bad "edited NAV flagged as template" "$(line EDITED)"
  [ "$(line REORDER)" = true ]  && ok "key order is ignored" || bad "reordered template NAV missed" "$(line REORDER)"
  [ "$(line ALLOW)" = false ]   && ok "ALLOW_TEMPLATE_NAV=1 overrides" || bad "ALLOW_TEMPLATE_NAV ignored" "$(line ALLOW)"
fi

echo "== monkey.js: exit codes =="
IFS= read -r -d '' JS2 <<'EOF' || true
const M = require('./monkey.js');
if (typeof M.exitCode !== 'function') { console.log('NOFN'); process.exit(0); }
const e = (c, t, u) => M.exitCode({ crashes: c, targets: t, unreached: u });
console.log('CODES ' + [e(0, 8, 8), e(0, 8, 0), e(1, 8, 8), e(0, 8, 7), e(1, 8, 0), e(0, 0, 0), e(1, 0, 0)].join(','));
EOF
OUT="$(cd "$WORK/tests/e2e" && printf '%s' "$JS2" | APP_PORT=1 timeout 60 node - 2>&1)"
if printf '%s\n' "$OUT" | grep -qx NOFN; then bad "#679 monkey.js exports no exitCode()"; else
  [ "$(line CODES)" = "2,0,1,0,1,2,1" ] \
    && ok "#679 0 of N reached → 2 (not measured); some reached → 0; a crash → 1; 0 of 0 → 2" \
    || bad "#679 exit codes" "$(line CODES)"
fi
grep -qF 'process.exit(code);' "$SUT" && grep -qF 'const code = exitCode({ crashes: crashes.length, targets: targets.length, unreached: unreached.length });' "$SUT" \
  && ok "#679 main exits with exitCode() (the tested function is the one that runs)" \
  || bad "#679 main does not use exitCode()"

echo "== monkey.js main: the shipped (empty) NAV exits 2 BEFORE the browser =="
RUNOUT="$(cd "$WORK/tests/e2e" && env -u ALLOW_TEMPLATE_NAV APP_PORT=1 timeout 120 node monkey.js --rounds 1 2>&1)"; RC=$?
[ "$RC" -eq 2 ] && ok "empty NAV → exit 2 (not measured)" || bad "empty NAV exit code" "rc=$RC $(printf '%s' "$RUNOUT" | tail -3)"
printf '%s\n' "$RUNOUT" | grep -q 'SETUP  NOT CONFIGURED: NAV' && printf '%s\n' "$RUNOUT" | grep -q -- '--skip-monkey' \
  && ok "a SETUP line says NAV is not configured, how to fill it, and names --skip-monkey" \
  || bad "no NOT CONFIGURED line for the empty NAV" "$(printf '%s' "$RUNOUT" | tail -3)"
printf '%s\n' "$RUNOUT" | grep -qE 'INSTRUMENT FAULT|\(login\)|MONKEY SUMMARY|page\.goto|loginOnce' \
  && bad "the empty-NAV run went past the check (browser/login reached)" "$(printf '%s' "$RUNOUT" | tail -3)" \
  || ok "nothing after the NAV check ran: no browser launch, no login attempt"

echo "== monkey.js main: the old sample NAV exits 2 BEFORE the browser =="
# A project.config.js installed before the template went empty: its NAV is the old sample.
( cd "$WORK/tests/e2e" && APP_PORT=1 node -e '
  const fs = require("fs"), f = "project.config.js";
  const nav = JSON.stringify(require("./config.js").TEMPLATE_NAV || {});
  fs.writeFileSync(f, fs.readFileSync(f, "utf8").replace(/const NAV = \{[\s\S]*?\n\};/, "const NAV = " + nav + ";"));
' ) >/dev/null 2>&1
# APP_PORT=1: nothing listens. Without the check the run launches a browser and fails at login
# (exit 1), or exits 2 on a missing playwright — neither names the NAV.
RUNOUT="$(cd "$WORK/tests/e2e" && env -u ALLOW_TEMPLATE_NAV APP_PORT=1 timeout 120 node monkey.js --rounds 1 2>&1)"; RC=$?
[ "$RC" -eq 2 ] && ok "#679 sample NAV → exit 2 (instrument fault, not measured)" || bad "#679 sample NAV exit code" "rc=$RC $(printf '%s' "$RUNOUT" | tail -3)"
printf '%s\n' "$RUNOUT" | grep -q 'SETUP  NAV is the unedited sample' && ok "#679 a SETUP line names the sample NAV" \
  || bad "#679 no SETUP line for the sample NAV" "$(printf '%s' "$RUNOUT" | tail -3)"
printf '%s\n' "$RUNOUT" | grep -qE 'INSTRUMENT FAULT|\(login\)|MONKEY SUMMARY|page\.goto|loginOnce' \
  && bad "#679 the run went past the NAV check (browser/login reached)" "$(printf '%s' "$RUNOUT" | tail -3)" \
  || ok "#679 nothing after the NAV check ran: no browser launch, no login attempt"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
