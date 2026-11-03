#!/usr/bin/env bash
# Usage: bash test-journey-pseudo-text.sh [path-to-journey-runner.js]
#
# Fixture for #276 (finding 1): text authored in CSS (`.empty::after { content: "No placements yet" }`)
# is on the screen and absent from innerText, so a `textPresent` check FAILs a correct page — the
# reporter's journey for empty-state sentences failed 3 of 17 steps on its first run with the feature
# fine. `ui.pseudoText` asserts against the rendered ::before / ::after content instead.
#
# Part A: pseudoVerdict on stand-in input. Part B: pseudoTexts in a real headless Chromium on a
# localhost page (SKIPs when Playwright or its browser is absent). Part C: the wiring, by inspection,
# and validate-journeys.js accepting the field.

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

WORK="$(mktemp -d "${TMPDIR:-/tmp}/journey-pseudo.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/tests/e2e"; : > "$WORK/Fixture.mpr"
cp "$SUT" "$E2E/helpers.js" "$E2E/settle.js" "$E2E/otel.js" "$E2E/config.js" "$WORK/tests/e2e/"
cp "$CFG" "$WORK/tests/e2e/project.config.js"

IFS= read -r -d '' JS <<'JSEOF' || true
const http = require('http');
const R = require('./journey-runner.js');
if (typeof R.pseudoVerdict !== 'function' || typeof R.pseudoTexts !== 'function') { console.log('NOFN'); process.exit(0); }
const out = (k, v) => console.log(`${k} ${JSON.stringify(v)}`);
out('V:hit', R.pseudoVerdict(['No placements yet'], 'placements').verdict);
out('V:miss', R.pseudoVerdict(['Other'], 'No placements yet').verdict);
out('V:gone', R.pseudoVerdict(null, 'x').verdict);
(async () => {
  let H; try { H = require('./helpers.js'); if (!H.deviceProfiles()) throw new Error('no playwright'); } catch (e) { out('SKIPB', e.message); return; }
  const html = '<style>.empty::after{content:"No placements yet"} .gone{display:none} .gone::before{content:"Hidden text"}' +
               ' .q::before{content:"Say \\"hi\\""}</style><div class=empty></div><div class=gone></div><span class=q></span><p>body</p>';
  const srv = http.createServer((q, s) => { s.setHeader('content-type', 'text/html'); s.end(html); });
  await new Promise(r => srv.listen(0, '127.0.0.1', r));
  let browser, page;
  try { ({ browser, page } = await H.launchBrowser()); } catch (e) { out('SKIPB', e.message.split('\n')[0]); srv.close(); return; }
  await page.goto(`http://localhost:${srv.address().port}/`);
  out('B:texts', await R.pseudoTexts(page));
  out('B:inner', (await page.locator('body').innerText()).includes('No placements yet'));
  await browser.close(); srv.close();
})();
JSEOF
OUT="$(cd "$WORK/tests/e2e" && printf '%s' "$JS" | APP_PORT=1 timeout 90 node - 2>&1)"
get() { printf '%s\n' "$OUT" | sed -n "s/^$1 //p"; }
if printf '%s\n' "$OUT" | grep -qx NOFN || [ -z "$(get V:hit)" ]; then
  bad "journey-runner.js exports no pseudoTexts / pseudoVerdict (#276)" "$(printf '%s\n' "$OUT" | tail -3)"
else
  [ "$(get V:hit)" = '"PASS"' ] && [ "$(get V:miss)" = '"FAIL"' ] && [ "$(get V:gone)" = '"INVALID"' ] \
    && ok "pseudoVerdict: contained → PASS, absent → FAIL, unreadable page → INVALID" || bad "pseudoVerdict" "$(get V:hit)/$(get V:miss)/$(get V:gone)"
  if [ -n "$(get SKIPB)" ]; then echo "  skip — no Playwright browser here ($(get SKIPB))"
  else
    [ "$(get B:inner)" = false ] && ok "the page's innerText does not contain the CSS sentence (why textPresent FAILs it)" || bad "innerText unexpectedly has the CSS text" "$(get B:inner)"
    [ "$(get B:texts)" = '["No placements yet","Say \"hi\""]' ] && ok "pseudoTexts reads ::after/::before of rendered elements, unescapes quotes, skips display:none hosts" || bad "pseudoTexts" "$(get B:texts)"
  fi
fi

awk '/step\.ui\.pseudoText/{p=1} p&&/pseudoTexts\(page\)/{t=1} t&&/CSS content says/{r=1} r&&/RUNG 2: ordered spans/{x=1} END{exit !x}' "$SUT" \
  && ok "runJourney records one 'CSS content says' row per pseudoText string, after the landing guard" || bad "pseudoText not wired into runJourney"

if [ -f "$VALIDATOR" ]; then
  printf '%s' '{"id":"J","steps":[{"name":"s","actions":[],"ui":{"ready":".mx-name-x","pseudoText":["No placements yet"]}}]}' > "$WORK/v.json"
  node "$VALIDATOR" "$WORK/v.json" >/dev/null 2>&1 && ok "validate-journeys accepts ui.pseudoText" || bad "validator rejects pseudoText" "$(node "$VALIDATOR" "$WORK/v.json" 2>&1 | head -3)"
fi

echo
echo "SCORE: $PASS/$((PASS+FAIL))"
[ "$FAIL" -eq 0 ]
