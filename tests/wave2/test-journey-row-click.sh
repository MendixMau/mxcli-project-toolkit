#!/usr/bin/env bash
# Usage: bash test-journey-row-click.sh [path-to-journey-runner.js]
#
# Fixture for #148 (one slice: the row-scoped click). A grid repeats one widget name per row, so a
# bare `.mx-name-<w>` click lands on whichever row rendered first. `row` picks the innermost row whose
# text contains it, `in` scopes to one container widget. Drives act() in a real headless Chromium on a
# localhost page (SKIPs without Playwright): the bare click hits row A, the scoped one row B, a
# Data Grid 2 style `role=row` with display:contents works, and a row nobody shows throws.

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

WORK="$(mktemp -d "${TMPDIR:-/tmp}/journey-rowclick.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/tests/e2e"; : > "$WORK/Fixture.mpr"
cp "$SUT" "$E2E/helpers.js" "$E2E/settle.js" "$E2E/otel.js" "$E2E/config.js" "$WORK/tests/e2e/"
cp "$CFG" "$WORK/tests/e2e/project.config.js"

IFS= read -r -d '' JS <<'JSEOF' || true
const http = require('http');
const R = require('./journey-runner.js');
const out = (k, v) => console.log(`${k} ${JSON.stringify(v)}`);
if (typeof R.scopedWidget !== 'function') { console.log('NOFN'); process.exit(0); }
out('D:row', R.describeAct({ do: 'click', widget: 'btnShip', label: 'Ship', row: '{{code}}' }, { code: 'B-200' }).target);
(async () => {
  let H; try { H = require('./helpers.js'); if (!H.deviceProfiles()) throw new Error('no playwright'); } catch (e) { out('SKIPB', e.message); return; }
  const html = '<script>window.hits=[]</script><div class="mx-name-grid1"><table>' +
    '<tr><td>Order A-100</td><td><button class="mx-name-btnShip" onclick="hits.push(\'A\')">Ship</button></td></tr>' +
    '<tr><td>Order B-200</td><td><button class="mx-name-btnShip" onclick="hits.push(\'B\')">Ship</button></td></tr></table></div>' +
    '<div class="mx-name-grid2" role="grid"><div role="row" style="display:contents"><span>Order B-200</span>' +
    '<button class="mx-name-btnShip" onclick="hits.push(\'B2\')">Ship</button></div></div>';
  const srv = http.createServer((q, s) => { s.setHeader('content-type', 'text/html'); s.end(html); });
  await new Promise(r => srv.listen(0, '127.0.0.1', r));
  let browser, page;
  try { ({ browser, page } = await H.launchBrowser()); } catch (e) { out('SKIPB', e.message.split('\n')[0]); srv.close(); return; }
  await page.goto(`http://localhost:${srv.address().port}/`);
  const note = () => {};
  await R.act(page, { do: 'click', widget: 'btnShip', settleMs: 0 }, {}, note);
  await R.act(page, { do: 'click', widget: 'btnShip', row: '{{code}}', in: 'grid1', settleMs: 0 }, { code: 'B-200' }, note);
  await R.act(page, { do: 'click', widget: 'btnShip', row: 'B-200', in: 'grid2', settleMs: 0 }, {}, note);
  out('B:err', await R.act(page, { do: 'click', widget: 'btnShip', row: 'Z-999', in: 'grid1', settleMs: 0 }, {}, note).then(() => 'no error', x => x.message));
  out('B:hits', await page.evaluate(() => window.hits));
  await browser.close(); srv.close();
})();
JSEOF
OUT="$(cd "$WORK/tests/e2e" && printf '%s' "$JS" | APP_PORT=1 timeout 90 node - 2>&1)"
get() { printf '%s\n' "$OUT" | sed -n "s/^$1 //p"; }
if printf '%s\n' "$OUT" | grep -qx NOFN; then
  bad "journey-runner.js exports no scopedWidget (#148)" "$(printf '%s\n' "$OUT" | tail -3)"
else
  [ "$(get D:row)" = '"Ship in the row \"B-200\""' ] && ok "the walk narrates which row was clicked" || bad "describeAct row" "$(get D:row)"
  if [ -n "$(get SKIPB)" ]; then echo "  skip — no Playwright browser here ($(get SKIPB))"
  else
    [ "$(get B:hits)" = '["A","B","B2"]' ] && ok "bare click hits the first row (the defect); row+in hits the named row, also in a display:contents role=row grid" || bad "row-scoped click" "$(get B:hits)"
    [ "$(get B:err)" = '"no row in .mx-name-grid1 says \"Z-999\""' ] && ok "a row nobody shows throws (step FAIL), never falls back to the first row" || bad "missing row" "$(get B:err)"
  fi
fi

if [ -f "$VALIDATOR" ]; then
  node "$VALIDATOR" --selftest >/dev/null 2>&1 && ok "validator selftest (row / in rows included) watched going red" || bad "validator selftest" "$(node "$VALIDATOR" --selftest 2>&1 | grep FAIL | head -3)"
fi

echo
echo "SCORE: $PASS/$((PASS+FAIL))"
[ "$FAIL" -eq 0 ]
