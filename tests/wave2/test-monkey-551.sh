#!/usr/bin/env bash
# Usage: bash test-monkey-551.sh [path-to-monkey.js]
#
# Fixture for #803: monkey.js scored Mendix validation feedback as a crash. The runtime answers a
# refused save (a required field emptied: "Enter the customer name") with HTTP 551 and a
# {"datavalidation":[...]} body. The response watch pushed every status >= 500 into http5xx and
# the oracle turned that into a crash hit ("HTTP 5xx: 551"). Now such a 551 is filed as
# validation (info); every other 5xx, and a 551 with any other body, is still crash-class.
#
# Real Chromium against a stub server: the page's requests produce real responses, so the watch's
# body read runs as it does in a run. Skipped, and said so, where Playwright has no browser.
# The 551 body below is the documented shape, NOT a capture from a running app (none was attached
# to the issue); only the top-level `datavalidation` array is relied on.

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
CFG="$E2E/project.config.template.js"
[ -f "$CFG" ] || CFG="$HERE/../../project-tests/e2e/project.config.template.js"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

# monkey.js resolves a project at require time: an .mpr two levels up and an asserted port.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/monkey-551.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/tests/e2e"; : > "$WORK/Fixture.mpr"
cp "$SUT" "$E2E/helpers.js" "$E2E/otel.js" "$E2E/config.js" "$WORK/tests/e2e/"
cp "$CFG" "$WORK/tests/e2e/project.config.js"

IFS= read -r -d '' JS <<'JSEOF' || true
const fs = require('fs');
const http = require('http');
const M = require('./monkey.js');
require('./otel.js').capture = async () => [];   // no Jaeger: the OTel arm returns no spans
const out = (k, v) => console.log(`${k} ${JSON.stringify(v)}`);

// The watch under test. An older monkey.js does not export it: lift it from the source, so the
// fixture measures the old behaviour instead of failing on a missing export.
let watch = M.installClientWatch, via = 'export';
if (typeof watch !== 'function') {
  const m = fs.readFileSync('./monkey.js', 'utf8').match(/function installClientWatch\(page, bucket\) \{[\s\S]*?\n\}\n/);
  watch = m ? eval('(' + m[0] + ')') : null; via = 'source';
}
out('VIA', via);

const BODY = {
  '/xas/valid':   [551, '{"datavalidation":[{"guid":"1","errors":{"Name":"Enter the customer name"}}]}'],
  '/xas/other':   [551, '{"message":"not validation"}'],
  '/xas/garbled': [551, '<html>oops</html>'],
  '/xas/crash':   [500, '{"message":"An error has occurred while handling the request."}'],
  '/xas/560':     [560, '{"message":"Attempt to illegally add an object to the state"}'],
};
const srv = http.createServer((req, res) => {
  const hit = BODY[req.url];
  if (hit) { res.writeHead(hit[0], { 'Content-Type': 'application/json' }); res.end(hit[1]); return; }
  res.writeHead(200, { 'Content-Type': 'text/html' });
  res.end('<div class="mx-page"><input value="Acme"><button class="mx-button">Save</button></div>');
});

(async () => {
  if (typeof M.isValidationFeedback === 'function') {
    const F = M.isValidationFeedback;
    out('UNIT', { v: F(551, BODY['/xas/valid'][1]), o: F(551, BODY['/xas/other'][1]), g: F(551, 'x'),
                  nul: F(551, 'null'), s500: F(500, BODY['/xas/valid'][1]), arr: F(551, '{"datavalidation":{}}') });
  } else out('UNIT', 'NOFN');
  if (!watch) { out('REAL', 'NOWATCH'); return; }
  let pw = null; try { pw = require('playwright'); } catch (e) {}
  if (!pw) { out('REAL', 'SKIP playwright not installed'); return; }
  let b; try { b = await pw.chromium.launch(); } catch (e) { out('REAL', 'SKIP ' + String(e.message).split('\n')[0]); return; }
  await new Promise(r => srv.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${srv.address().port}`;
  const page = await b.newPage();
  await page.goto(base + '/');
  const bucket = { jsErrors: [], http5xx: [], validation: [], pending: [] };
  watch(page, bucket);
  const res = {};
  for (const route of Object.keys(BODY)) {
    // As round() does at its start: a fresh bucket per round.
    bucket.jsErrors = []; bucket.http5xx = []; bucket.validation = []; bucket.pending = [];
    await page.evaluate(u => fetch(u, { method: 'POST' }).then(r => r.text()), route);
    await page.waitForTimeout(200);
    const o = await M.oracle(page, 0, bucket);
    res[route] = { hits: o.hits, validation: (o.validation || []).length };
  }
  await b.close(); srv.close();
  out('REAL', res);
})().then(() => process.exit(0), e => { console.log('ERR ' + e.stack); process.exit(0); });
JSEOF
OUT="$(cd "$WORK/tests/e2e" && printf '%s' "$JS" | APP_PORT=1 timeout 90 node - 2>&1)"
get() { printf '%s\n' "$OUT" | sed -n "s/^$1 //p"; }
j() { printf '%s' "$(get "$1")" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const o=JSON.parse(s);console.log(String(eval("o"+process.argv[1])))}catch(e){console.log("ERR")}})' "$2"; }

echo "  (watch taken from: $(get VIA))"
if [ "$(get UNIT)" = '"NOFN"' ] || [ -z "$(get UNIT)" ]; then
  bad "#803 monkey.js exports no isValidationFeedback()" "$(printf '%s\n' "$OUT" | tail -3)"
else
  [ "$(get UNIT)" = '{"v":true,"o":false,"g":false,"nul":false,"s500":false,"arr":false}' ] \
    && ok "#803 isValidationFeedback(): only a 551 whose body has a datavalidation array; other bodies, unparsable text and other statuses are not" \
    || bad "#803 isValidationFeedback() answers wrong" "$(get UNIT)"
fi

REAL="$(get REAL)"
case "$REAL" in
  '"SKIP'*) echo "  skip — real-browser cases: $REAL" ;;
  ''|'"NOWATCH"') bad "#803 the response watch could not be run" "$(printf '%s\n' "$OUT" | tail -5)" ;;
  *)
    [ "$(j REAL "['/xas/valid'].hits.length")" = 0 ] && [ "$(j REAL "['/xas/valid'].validation")" = 1 ] \
      && ok "#803 Chromium: a 551 with a datavalidation body is validation feedback, not a crash hit" \
      || bad "#803 a 551 datavalidation response (a refused save) is scored crash-class" "$(j REAL "['/xas/valid'].hits")"
    case "$(j REAL "['/xas/crash'].hits.join()")" in
      "HTTP 5xx: 500 http://127.0.0.1:"*"/xas/crash") ok "#803 control: a 500 is still crash-class" ;;
      *) bad "#803 a 500 is no longer crash-class" "$(j REAL "['/xas/crash'].hits")" ;;
    esac
    case "$(j REAL "['/xas/560'].hits.join()")" in
      "HTTP 5xx: 560 "*) ok "#803 control: a 560 is still crash-class" ;;
      *) bad "#803 a 560 is no longer crash-class" "$(j REAL "['/xas/560'].hits")" ;;
    esac
    case "$(j REAL "['/xas/other'].hits.join()")|$(j REAL "['/xas/garbled'].hits.join()")" in
      "HTTP 5xx: 551 "*"|HTTP 5xx: 551 "*) ok "#803 control: a 551 whose body is not datavalidation (other JSON, or not JSON) is still crash-class" ;;
      *) bad "#803 a 551 without a datavalidation body was exempted" "$REAL" ;;
    esac
    ;;
esac

grep -qF "else if (validation.length) finding('info'," "$SUT" \
  && ok "#803 round() files validation feedback as info, after crash and slow" \
  || bad "#803 round() does not report validation feedback as info"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
