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

# A real headless Chromium walks a stand-in app on localhost (review follow-up): a step whose
# button POSTs to /xas/ and gets 560 still lands (ready PASS) and its no5xx row FAILs naming the
# 560 — the issue's shape; Back returns to the home page with no 5xx; Back on a first page leaves
# the app and throws. SKIPs (counted in neither column) without Playwright or its browser.
IFS= read -r -d '' BJS <<'JSEOF' || true
const http = require('http');
(async () => {
  const pages = {
    '/': '<a class="mx-name-lnk" href="/p2">to p2</a><div class="mx-name-home">home</div>',
    '/p2': '<div class="mx-name-ready2">p2</div><button class="mx-name-btnLoad" onclick="fetch(\'/xas/\',{method:\'POST\'})">load</button>',
  };
  const srv = http.createServer((q, s) => {
    if (q.url.startsWith('/xas/')) { s.statusCode = 560; return s.end('{}'); }
    s.setHeader('content-type', 'text/html'); s.end(pages[q.url] || 'nope');
  });
  await new Promise(r => srv.listen(0, '127.0.0.1', r));
  process.env.APP_URL = `http://localhost:${srv.address().port}`;
  let R, H, browser, page;
  try { R = require('./journey-runner.js'); H = require('./helpers.js'); if (!H.deviceProfiles || !H.deviceProfiles()) throw new Error('no playwright');
        if (typeof R.runJourney !== 'function') throw new Error('runJourney not exported');
        ({ browser, page } = await H.launchBrowser()); }
  catch (e) { console.log('SKIPB ' + e.message.split('\n')[0]); srv.close(); return; }
  await page.goto(process.env.APP_URL + '/');
  const j = { id: 'J-BACK', steps: [
    { name: 'open p2', actions: [{ do: 'click', widget: 'lnk' }], ui: { ready: '.mx-name-ready2' } },
    { name: 'load', actions: [{ do: 'click', widget: 'btnLoad', settleMs: 500 }], ui: { ready: '.mx-name-ready2', no5xx: true } },
    { name: 'back home', actions: [{ do: 'back', timeout: 3000 }], ui: { ready: '.mx-name-home', no5xx: true } } ] };
  const done = await R.runJourney(page, j);
  console.log('ROWS ' + JSON.stringify(R.results.map(r => [r.name, r.verdict, /560 POST/.test(r.detail)])) + ' ' + done);
  const p2 = await browser.newPage(); await p2.goto(process.env.APP_URL + '/');
  console.log('LEFT ' + await R.act(p2, { do: 'back', timeout: 3000 }, {}, () => {}).then(() => 'no error', e => e.message.split('(')[0].trim()));
  await browser.close(); srv.close();
})().catch(e => console.log('BERR ' + e.message));
JSEOF
BOUT="$(cd "$WORK/tests/e2e" && printf '%s' "$BJS" | ALLOW_UNVERIFIED_APP=1 timeout 90 node - 2>&1)"
bget() { printf '%s\n' "$BOUT" | sed -n "s/^$1 //p"; }
if [ -n "$(bget SKIPB)" ]; then echo "  skip — real-browser walk: $(bget SKIPB)"
else
  [ "$(bget ROWS)" = '[["open p2: reached","PASS",false],["load: reached","PASS",false],["load: no HTTP 5xx during the step","FAIL",true],["back home: reached","PASS",false],["back home: no HTTP 5xx during the step","PASS",false]] true' ] \
    && ok "Chromium: a 560 on /xas/ behind a page that still lands → ready PASS, no5xx FAIL naming the 560; Back lands home with no 5xx" \
    || bad "real-browser back/no5xx walk" "$(bget ROWS) $(bget BERR)"
  [ "$(bget LEFT)" = 'Back left the app' ] && ok "Chromium: Back on the first page leaves the app and throws (step FAIL)" || bad "Back out of the app not caught" "$(bget LEFT) $(bget BERR)"
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
