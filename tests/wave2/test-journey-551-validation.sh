#!/usr/bin/env bash
# Usage: bash test-journey-551-validation.sh [path-to-journey-runner.js]
#
# Fixture for #818: journey-runner.js's opt-in `ui.no5xx` row FAILed a negative-path step whose
# save Mendix refused with validation feedback. Mendix answers a refused save with HTTP 551 and a
# `{"datavalidation":[…]}` body; that is the app working, not a server error.
#
# Golden input is CAPTURED (fixtures/runtime-mx118/xas-551-empty-required.json): the real /xas/
# answer of a Mendix 11.8.0 runtime to Save on a popup whose required Title was empty — status,
# headers and body verbatim. A headless Chromium walks a stand-in /xas/ that replays it, beside
# two controls that must still FAIL: a 500, and a 551 whose body is not datavalidation (an
# unknown 551 is not proven to be feedback, so it stays a 5xx).
#
# On master the captured-551 step reads FAIL "1 answer(s) >= 500: 551 POST …" (field run
# 2026-11-20, TasksNeg journey); fixed, it reads PASS with the 551 named in a note.

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
GOLDEN="$HERE/fixtures/runtime-mx118/xas-551-empty-required.json"
[ -f "$GOLDEN" ] || { echo "FAIL — golden capture missing: $GOLDEN"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/journey-551.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/tests/e2e"; : > "$WORK/Fixture.mpr"
cp "$SUT" "$E2E/helpers.js" "$E2E/settle.js" "$E2E/otel.js" "$E2E/config.js" "$WORK/tests/e2e/"
cp "$CFG" "$WORK/tests/e2e/project.config.js"

# The capture must be what it says: a 551 POST on /xas/ whose body is datavalidation.
node -e '
const c = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
const b = JSON.parse(c.body);
process.exit(c.status === 551 && c.method === "POST" && /\/xas\/$/.test(c.url) && Array.isArray(b.datavalidation) ? 0 : 1);
' "$GOLDEN" && ok "golden capture is a 551 POST /xas/ with a datavalidation body" || bad "golden capture is not the 551 shape" "$(head -c 300 "$GOLDEN")"

# Unit: the classifier and the verdict.
IFS= read -r -d '' JS <<'JSEOF' || true
const fs = require('fs');
const cap = JSON.parse(fs.readFileSync(process.env.GOLDEN, 'utf8'));
const H = require('./helpers.js'); const R = require('./journey-runner.js');
if (typeof H.isValidationFeedback !== 'function') { console.log('NOFN'); process.exit(0); }
const F = H.isValidationFeedback;
console.log('U ' + JSON.stringify([F(551, cap.body), F(551, '{}'), F(551, 'not json'), F(551, 'null'), F(500, cap.body), F(551, '{"datavalidation":{}}')]));
console.log('V:fb ' + JSON.stringify(R.no5xxVerdict([], ['551 POST http://localhost:8080/xas/'])));
console.log('V:none ' + JSON.stringify(R.no5xxVerdict([])));
JSEOF
OUT="$(cd "$WORK/tests/e2e" && printf '%s' "$JS" | GOLDEN="$GOLDEN" APP_PORT=1 timeout 30 node - 2>&1)"
get() { printf '%s\n' "$OUT" | sed -n "s/^$1 //p"; }
if printf '%s\n' "$OUT" | grep -qx NOFN; then
  bad "helpers.js exports no isValidationFeedback (#818)"
else
  [ "$(get U)" = '[true,false,false,false,false,false]' ] \
    && ok "isValidationFeedback: only a 551 whose body has a datavalidation ARRAY (captured body yes; {}, non-JSON, null, a 500, an object no)" \
    || bad "isValidationFeedback classification" "$(get U) $(printf '%s\n' "$OUT" | tail -2)"
  [ "$(get V:fb)" = '{"verdict":"PASS","detail":"no answer >= 500 (1 validation answer(s), HTTP 551 datavalidation, not counted: 551 POST http://localhost:8080/xas/)"}' ] \
    && ok "no5xxVerdict: feedback only → PASS with the 551 named in a note" || bad "verdict with feedback" "$(get V:fb)"
  [ "$(get V:none)" = '{"verdict":"PASS","detail":"no answer >= 500"}' ] && ok "no5xxVerdict: clean step unchanged" || bad "clean verdict changed" "$(get V:none)"
fi

# Real browser: three no5xx steps against a stand-in /xas/. Step 1 replays the CAPTURED 551,
# step 2 a 500, step 3 a 551 with a non-datavalidation body.
IFS= read -r -d '' BJS <<'JSEOF' || true
const http = require('http'); const fs = require('fs');
const cap = JSON.parse(fs.readFileSync(process.env.GOLDEN, 'utf8'));
(async () => {
  const btn = (n, q) => `<button class="mx-name-${n}" onclick="fetch('/xas/?${q}',{method:'POST',body:'{}'})">${n}</button>`;
  const page = '<div class="mx-name-dvTask">form</div>' + btn('btnValid', 'v') + btn('btn500', 'e') + btn('btnOther', 'o');
  const srv = http.createServer((q, s) => {
    if (q.url === '/xas/?v') { s.writeHead(cap.status, { 'content-type': cap.headers['content-type'] || 'application/json' }); return s.end(cap.body); }
    if (q.url === '/xas/?e') { s.statusCode = 500; return s.end('{}'); }
    if (q.url === '/xas/?o') { s.statusCode = 551; s.setHeader('content-type', 'application/json'); return s.end('{"something":"else"}'); }
    s.setHeader('content-type', 'text/html'); s.end(page);
  });
  await new Promise(r => srv.listen(0, '127.0.0.1', r));
  process.env.APP_URL = `http://localhost:${srv.address().port}`;
  let R, H, browser, pg;
  try { R = require('./journey-runner.js'); H = require('./helpers.js'); if (!H.deviceProfiles || !H.deviceProfiles()) throw new Error('no playwright');
        ({ browser, page: pg } = await H.launchBrowser()); }
  catch (e) { console.log('SKIPB ' + e.message.split('\n')[0]); srv.close(); return; }
  await pg.goto(process.env.APP_URL + '/');
  const step = (name, w) => ({ name, actions: [{ do: 'click', widget: w, settleMs: 600 }], ui: { ready: '.mx-name-dvTask', no5xx: true } });
  const j = { id: 'J-551', steps: [step('valid', 'btnValid'), step('e500', 'btn500'), step('other551', 'btnOther')] };
  await R.runJourney(pg, j);
  console.log('ROWS ' + JSON.stringify(R.results.filter(r => /no HTTP 5xx/.test(r.name)).map(r => [r.name.split(':')[0], r.verdict, r.detail.replace(/localhost:\d+/g, 'H')])));
  await browser.close(); srv.close();
})().catch(e => console.log('BERR ' + e.message));
JSEOF
BOUT="$(cd "$WORK/tests/e2e" && printf '%s' "$BJS" | GOLDEN="$GOLDEN" ALLOW_UNVERIFIED_APP=1 timeout 90 node - 2>&1)"
bget() { printf '%s\n' "$BOUT" | sed -n "s/^$1 //p"; }
if [ -n "$(bget SKIPB)" ]; then echo "  skip — real-browser walk: $(bget SKIPB)"
else
  ROWS="$(bget ROWS)"
  printf '%s' "$ROWS" | grep -qF '["valid","PASS","no answer >= 500 (1 validation answer(s), HTTP 551 datavalidation, not counted: 551 POST http://H/xas/?v)"]' \
    && ok "Chromium: the captured 551 datavalidation answer → no5xx PASS, the 551 kept as a note" || bad "captured 551 step" "$ROWS $(bget BERR)"
  printf '%s' "$ROWS" | grep -qF '["e500","FAIL","1 answer(s) >= 500: 500 POST http://H/xas/?e"]' \
    && ok "Chromium: control — a 500 still FAILs" || bad "500 control" "$ROWS $(bget BERR)"
  printf '%s' "$ROWS" | grep -qF '["other551","FAIL","1 answer(s) >= 500: 551 POST http://H/xas/?o"]' \
    && ok "Chromium: control — a 551 without datavalidation still FAILs" || bad "other-551 control" "$ROWS $(bget BERR)"
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
