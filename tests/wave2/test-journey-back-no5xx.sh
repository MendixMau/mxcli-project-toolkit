#!/usr/bin/env bash
# Usage: bash test-journey-back-no5xx.sh [path-to-journey-runner.js]
#
# Fixture for #564: journey-runner.js's `{ "do": "back" }` action and the opt-in `ui.no5xx` row.
# The defect: a page whose data sources failed after browser Back (HTTP 560 on /xas/) still drew
# its frame, so the landing guard read PASS; and no journey could press Back at all. The issue's
# project ran the patch on its own app: the Back journey went 60 PASS / 2 FAIL on the defective
# build (both FAILs the no5xx rows, the landing guard PASS on the same steps), 62/62 after the fix.
#
# The functions run against stand-in input; the wiring (listener added before the actions,
# removed on every exit, row recorded before the not-reached bail-out) is checked in the source.

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
VALIDATOR="$(cd "$E2E/../.." 2>/dev/null && pwd)/examples/validate-journeys.js"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/journey-back.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/tests/e2e"; : > "$WORK/Fixture.mpr"
cp "$SUT" "$E2E/helpers.js" "$E2E/settle.js" "$E2E/otel.js" "$E2E/config.js" "$WORK/tests/e2e/"
cp "$CFG" "$WORK/tests/e2e/project.config.js"

IFS= read -r -d '' JS <<'JSEOF' || true
const R = require('./journey-runner.js');
if (typeof R.backLeftApp !== 'function' || typeof R.no5xxVerdict !== 'function') { console.log('NOFN'); process.exit(0); }
const base = 'http://localhost:8080';
for (const [k, u] of [['ROUTE', base + '/p/orders'], ['ROOT', base + '/'], ['LOGIN', base + '/login.html?profile=Responsive'],
                      ['BLANK', 'about:blank'], ['OTHER', 'http://localhost:80801/p/x']])
  console.log(`B:${k} ${R.backLeftApp(u, base)}`);
console.log('V:none ' + JSON.stringify(R.no5xxVerdict([])));
console.log('V:two ' + JSON.stringify(R.no5xxVerdict(['560 POST http://localhost:8080/xas/', '560 POST http://localhost:8080/xas/'])));
console.log('V:many ' + JSON.stringify(R.no5xxVerdict(Array.from({ length: 7 }, (_, i) => `500 GET /x${i}`)).detail));
JSEOF
OUT="$(cd "$WORK/tests/e2e" && printf '%s' "$JS" | APP_PORT=1 timeout 30 node - 2>&1)"
get() { printf '%s\n' "$OUT" | sed -n "s/^$1 //p"; }
if printf '%s\n' "$OUT" | grep -qx NOFN || [ -z "$(get B:ROUTE)" ]; then
  bad "journey-runner.js exports no backLeftApp / no5xxVerdict (#564)" "$(printf '%s\n' "$OUT" | tail -3)"
else
  [ "$(get B:ROUTE)" = false ] && [ "$(get B:ROOT)" = false ] && ok "Back to an app route or the root stays in the app" || bad "app route read as outside" "$(get B:ROUTE)/$(get B:ROOT)"
  [ "$(get B:LOGIN)" = true ] && [ "$(get B:BLANK)" = true ] && [ "$(get B:OTHER)" = true ] \
    && ok "Back to login.html, about:blank or a look-alike origin left the app" || bad "a page outside the app read as inside" "$(get B:LOGIN)/$(get B:BLANK)/$(get B:OTHER)"
  [ "$(get V:none)" = '{"verdict":"PASS","detail":"no answer >= 500"}' ] && ok "no 5xx → PASS" || bad "clean step" "$(get V:none)"
  [ "$(get V:two)" = '{"verdict":"FAIL","detail":"2 answer(s) >= 500: 560 POST http://localhost:8080/xas/; 560 POST http://localhost:8080/xas/"}' ] \
    && ok "two 560s on /xas/ (the issue's row) → FAIL naming them" || bad "5xx row" "$(get V:two)"
  case "$(get V:many)" in '"7 answer(s) >= 500: '*'; …"') ok "more than 5 → count kept, list cut" ;; *) bad "long list" "$(get V:many)" ;; esac
fi

# Wiring, by inspection of the shipped source.
grep -qF "case 'back': {" "$SUT" && grep -qF "if (backLeftApp(page.url(), cfg.baseUrl))" "$SUT" \
  && ok "act() has the back action and checks backLeftApp after it" || bad "act() has no back action, or does not check where Back landed"
awk '/const watch5xx = !!\(step\.ui && step\.ui\.no5xx === true\)/{w=1} w&&/if \(watch5xx\) page\.on\(.response., on5xx\)/{on=1}
     on&&/const seal = \(\) => \{/{s=1} s&&/if \(watch5xx\) page\.off\(.response., on5xx\)/{off=1}
     off&&/for \(const a of step\.actions/{a=1} END{exit !(w&&on&&off&&a)}' "$SUT" \
  && ok "no5xx is opt-in (exactly true), listens from before the first action, and seal() removes the listener" \
  || bad "no5xx listener wiring missing or out of order"
awk '/leg\.reached = onPage;/{r=1} r&&/^    record5xx\(\);/{x=1} x&&/if \(!onPage\) \{/{b=1} END{exit !b}' "$SUT" \
  && awk '/ACTION-FAILED/{f=1} f&&/record5xx\(\);/{g=1} g&&/seal\(\);/{h=1;exit} END{exit !h}' "$SUT" \
  && ok "the no5xx row is recorded before the not-reached bail-out and on the action-failed path" \
  || bad "the no5xx row can be skipped by a bail-out — the 5xx that caused it would not show"

if [ -f "$VALIDATOR" ]; then
  printf '%s' '{"id":"J","steps":[{"name":"s","actions":[{"do":"back"}],"ui":{"ready":".mx-name-x","no5xx":true}}]}' > "$WORK/ok.json"
  printf '%s' '{"id":"J","steps":[{"name":"s","actions":[{"do":"back"}],"ui":{"no5xx":"yes"}}]}' > "$WORK/bad.json"
  node "$VALIDATOR" "$WORK/ok.json" >/dev/null 2>&1 && ok "validate-journeys accepts back and ui.no5xx: true" || bad "validator rejects back / no5xx" "$(node "$VALIDATOR" "$WORK/ok.json" 2>&1 | head -3)"
  VB="$(node "$VALIDATOR" "$WORK/bad.json" 2>&1)"
  printf '%s\n' "$VB" | grep -q 'must be true or false' && ok "validate-journeys flags a non-boolean ui.no5xx" || bad "validator accepts no5xx: \"yes\""
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
