#!/usr/bin/env bash
# Usage: bash test-journey-row-click.sh [path-to-journey-runner.js]
#
# Fixture for #148 (one slice: the row-scoped click). A grid repeats one widget name per row, so a
# bare `.mx-name-<w>` click lands on whichever row rendered first. `row` picks the innermost row whose
# text contains it, `in` scopes to one container widget. Drives act() in a real headless Chromium on a
# localhost page (SKIPs without Playwright): the bare click hits row A, the scoped one row B, a
# Data Grid 2 style `role=row` with display:contents works, and a row nobody shows throws.
# #760: `fill` honours `row` / `in` the same way (a list view repeats one textbox name per item).

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
// #668: displayed names resolve seeds like execution does; an unresolvable one stays as written.
R.setDisplayVars({ order: 'SO-1001' });
out('E:shown', [R.shown('Open {{order}}'), R.shown('Open {{nope}}'), R.shown('plain')]);
out('E:label', R.describeAct({ do: 'click', widget: 'b', label: 'Ship {{order}}' }, { order: 'SO-1001' }).target);
out('E:label-missing', R.describeAct({ do: 'click', widget: 'b', label: 'Ship {{nope}}' }, {}).target);
out('D:row', R.describeAct({ do: 'click', widget: 'btnShip', label: 'Ship', row: '{{code}}' }, { code: 'B-200' }).target);
out('D:fillrow', R.describeAct({ do: 'fill', widget: 'txtValue', value: '42', row: '{{code}}' }, { code: 'R-2' }).target);
(async () => {
  let H; try { H = require('./helpers.js'); if (!H.deviceProfiles()) throw new Error('no playwright'); } catch (e) { out('SKIPB', e.message); return; }
  const html = '<script>window.hits=[]</script><div class="mx-name-grid1"><table>' +
    '<tr><td>Order A-100</td><td><button class="mx-name-btnShip" onclick="hits.push(\'A\')">Ship</button></td></tr>' +
    '<tr><td>Order B-200</td><td><button class="mx-name-btnShip" onclick="hits.push(\'B\')">Ship</button></td></tr></table></div>' +
    '<div class="mx-name-grid2" role="grid"><div role="row" style="display:contents"><span>Order B-200</span>' +
    '<button class="mx-name-btnShip" onclick="hits.push(\'B2\')">Ship</button></div></div>' +
    // cells rendered with no whitespace between them, as React renders a grid
    '<div class="mx-name-grid3"><table><tr><td>Order 1</td><td><button class="mx-name-btnShip" onclick="hits.push(\'O1\')">Ship</button></td></tr>' +
    '<tr><td>Order 10</td><td><button class="mx-name-btnShip" onclick="hits.push(\'O10\')">Ship</button></td></tr></table></div>' +
    // #665: the pluggable List view renders each item as <li class="mx-name-index-N"> with NO
    // .mx-listview-item (so ROW_SEL misses it). PROVENANCE: structure taken from the compiled list view
    // widget of a toolkit-built demo app's deployed client (`jsx("ul", ...items.map(... jsx("li",
    // { className: "mx-name-index-" + index ...`), 2026-11. It is NOT a saved DOM page: no saved page with
    // this class exists in the repo or the demo apps; the item content (a text widget, a button) is generic.
    '<div class="mx-listview mx-name-grid5"><ul><li class="mx-name-index-0"><span class="mx-name-txt1">Order P-1</span>' +
    '<button class="mx-name-btnShip" onclick="hits.push(\'P1\')">Ship</button></li>' +
    '<li class="mx-name-index-1"><span class="mx-name-txt1">Order P-2</span>' +
    '<button class="mx-name-btnShip" onclick="hits.push(\'P2\')">Ship</button></li></ul></div>' +
    // guard case (shape NOT verified against a real page): widgets inside the item carry the index class too
    '<div class="mx-name-grid6"><ul><li class="mx-name-index-0"><span class="mx-name-txt1 mx-name-index-0">Order Q-1</span>' +
    '<button class="mx-name-btnShip mx-name-index-0" onclick="hits.push(\'Q1\')">Ship</button></li></ul></div>' +
    // #760: a list view whose item template repeats one textbox name. PROVENANCE: built from the
    // reporter's DOM excerpt quoted in issue #759/#760 (div.mx-listview.mx-name-<lv> > ul >
    // li.mx-name-index-0 > div.mx-dataview > ...), NOT a captured page: no captured Mendix 11 list view
    // DOM exists in the repo. The textbox shape (div.mx-name-<w> > input) is the standard Mendix one.
    '<div class="mx-listview mx-name-lvRows"><ul>' +
    '<li class="mx-name-index-0"><div class="mx-dataview"><span class="mx-name-txtCode">Row R-1</span>' +
    '<div class="mx-name-txtValue form-group"><input type="text" value=""></div></div></li>' +
    '<li class="mx-name-index-1"><div class="mx-dataview"><span class="mx-name-txtCode">Row R-2</span>' +
    '<div class="mx-name-txtValue form-group"><input type="text" value=""></div></div></li></ul></div>' +
    '<div class="mx-name-grid4"><table><tr><td>Order 7</td><td><button class="mx-name-btnShip">Ship</button></td></tr>' +
    '<tr><td>Order 7</td><td><button class="mx-name-btnShip">Ship</button></td></tr></table></div>';
  const srv = http.createServer((q, s) => { s.setHeader('content-type', 'text/html'); s.end(html); });
  await new Promise(r => srv.listen(0, '127.0.0.1', r));
  let browser, page;
  try { ({ browser, page } = await H.launchBrowser()); } catch (e) { out('SKIPB', e.message.split('\n')[0]); srv.close(); return; }
  await page.goto(`http://localhost:${srv.address().port}/`);
  const note = () => {};
  await R.act(page, { do: 'click', widget: 'btnShip', settleMs: 0 }, {}, note);
  await R.act(page, { do: 'click', widget: 'btnShip', row: '{{code}}', in: 'grid1', settleMs: 0 }, { code: 'B-200' }, note);
  await R.act(page, { do: 'click', widget: 'btnShip', row: 'B-200', in: 'grid2', settleMs: 0 }, {}, note);
  await R.act(page, { do: 'click', widget: 'btnShip', row: 'Order 1', in: 'grid3', settleMs: 0 }, {}, note);
  await R.act(page, { do: 'click', widget: 'btnShip', row: 'P-2', in: 'grid5', settleMs: 0 }, {}, note);
  await R.act(page, { do: 'click', widget: 'btnShip', row: 'Q-1', in: 'grid6', settleMs: 0 }, {}, note);
  out('B:amb', await R.act(page, { do: 'click', widget: 'btnShip', row: 'Order 7', in: 'grid4', settleMs: 0 }, {}, note).then(() => 'no error', x => x.message));
  out('B:err', await R.act(page, { do: 'click', widget: 'btnShip', row: 'Z-999', in: 'grid1', settleMs: 0 }, {}, note).then(() => 'no error', x => x.message));
  out('B:hits', await page.evaluate(() => window.hits));
  await R.act(page, { do: 'fill', widget: 'txtValue', row: '{{code}}', in: 'lvRows', value: '42', settleMs: 0 }, { code: 'R-2' }, note);
  await R.act(page, { do: 'fill', widget: 'txtValue', row: 'R-1', value: '7', settleMs: 0 }, {}, note);
  out('B:fill', await page.$$eval('.mx-name-lvRows input', els => els.map(e => e.value)));
  out('B:fillbare', await R.act(page, { do: 'fill', widget: 'txtValue', value: 'x', settleMs: 0 }, {}, note)
    .then(() => page.$$eval('.mx-name-lvRows input', els => els.map(e => e.value)), x => x.message));
  out('B:fillerr', await R.act(page, { do: 'fill', widget: 'txtValue', row: 'R-9', in: 'lvRows', value: '1', settleMs: 0 }, {}, note).then(() => 'no error', x => x.message));
  await browser.close(); srv.close();
})();
JSEOF
OUT="$(cd "$WORK/tests/e2e" && printf '%s' "$JS" | APP_PORT=1 timeout 90 node - 2>&1)"
get() { printf '%s\n' "$OUT" | sed -n "s/^$1 //p"; }
if printf '%s\n' "$OUT" | grep -qx NOFN; then
  bad "journey-runner.js exports no scopedWidget (#148)" "$(printf '%s\n' "$OUT" | tail -3)"
else
  [ "$(get E:shown)" = '["Open SO-1001","Open {{nope}}","plain"]' ] && ok "displayed text resolves seeds; an unknown placeholder stays visible (#668)" || bad "shown" "$(get E:shown)"
  [ "$(get E:label)" = '"Ship SO-1001"' ] && [ "$(get E:label-missing)" = '"Ship {{nope}}"' ] && ok "action labels in the walk resolve seeds, unresolved stay as-is (#668)" || bad "label" "$(get E:label) / $(get E:label-missing)"
  [ "$(get D:row)" = '"Ship in the row \"B-200\""' ] && ok "the walk narrates which row was clicked" || bad "describeAct row" "$(get D:row)"
  [ "$(get D:fillrow)" = '"\"42\" into txtValue in the row \"R-2\""' ] && ok "the walk narrates which row was filled (#760)" || bad "describeAct fill row" "$(get D:fillrow)"
  if [ -n "$(get SKIPB)" ]; then echo "  skip — no Playwright browser here ($(get SKIPB))"
  else
    [ "$(get B:hits)" = '["A","B","B2","O1","P2","Q1"]' ] && ok "bare click hits the first row (the defect); row+in hits the named row, also in a display:contents role=row grid; row \"Order 1\" never hits \"Order 10\"; a plain-div row carrying mx-name-index-N is found by fallback (#665)" || bad "row-scoped click" "$(get B:hits)"
    [ "$(get B:amb)" = '"ambiguous: 2 rows in .mx-name-grid4 say \"Order 7\""' ] && ok "two rows that both say the text throw 'ambiguous' (step FAIL), never pick one" || bad "ambiguous row" "$(get B:amb)"
    [ "$(get B:err)" = '"no row in .mx-name-grid1 says \"Z-999\""' ] && ok "a row nobody shows throws (step FAIL), never falls back to the first row" || bad "missing row" "$(get B:err)"
    [ "$(get B:fill)" = '["7","42"]' ] && ok "fill with row+in types into the named list view item (li.mx-name-index-N), not row 1; row alone works too (#760)" || bad "row-scoped fill" "$(get B:fill)"
    [ "$(get B:fillbare)" = '["x","42"]' ] && ok "fill without row/in keeps the old first-match behaviour" || bad "bare fill" "$(get B:fillbare)"
    [ "$(get B:fillerr)" = '"no row in .mx-name-lvRows says \"R-9\""' ] && ok "a fill row nobody shows throws (step FAIL), never types into row 1" || bad "fill missing row" "$(get B:fillerr)"
  fi
fi

if [ -f "$VALIDATOR" ]; then
  node "$VALIDATOR" --selftest >/dev/null 2>&1 && ok "validator selftest (row / in rows included) watched going red" || bad "validator selftest" "$(node "$VALIDATOR" --selftest 2>&1 | grep FAIL | head -3)"
fi

echo
echo "SCORE: $PASS/$((PASS+FAIL))"
[ "$FAIL" -eq 0 ]
