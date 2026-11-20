#!/usr/bin/env bash
# Usage: bash test-page-audit-datagrid-count.sh [path-to-page-audit.js]
#
# Fixture for page-audit's live/empty-list-message rule (P1) on DataGrid2. DOM_PROBE's list
# selector held `[class*="widget-datagrid"]`, a SUBSTRING match, so one DataGrid2 counted as nine
# lists: the root plus its -content, -grid, -grid-head, -grid-body, -footer, -paging-bottom,
# -pb-start and -pb-end parts. Four of those hold no row, and the rule reported "9 lists on
# screen; 4 empty", a P1 FAIL with four "(unnamed)" findings, on a grid showing 20 rows.
#
# Golden input is CAPTURED (fixtures/runtime-mx118/overview-SideBar-1280x900.mhtml.gz): a CDP
# MHTML snapshot of a live Mendix 11.8.0 overview page with one DataGrid2 (v3.5.0). DOM_PROBE is
# lifted from page-audit.js's text (requiring the file runs its CLI setup) and evaluated by
# Chromium over that page; the rule itself comes from page-audit-rules.js.

set -uo pipefail

SUT="${1:-}"
[ -z "$SUT" ] && SUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/project-tests/e2e/page-audit.js"
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
GZ="$HERE/fixtures/runtime-mx118/overview-SideBar-1280x900.mhtml.gz"
[ -f "$GZ" ] || { echo "FAIL — golden capture missing: $GZ"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/page-audit-grid.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/tests/e2e"; : > "$WORK/Fixture.mpr"
cp "$E2E/page-audit-rules.js" "$WORK/tests/e2e/"
cp "$CFG" "$WORK/tests/e2e/project.config.js"
gzip -dc "$GZ" > "$WORK/page.mhtml"

IFS= read -r -d '' JS <<'JSEOF' || true
const fs = require('fs'); const path = require('path');
(async () => {
  const js = fs.readFileSync(process.env.SUT, 'utf8');
  const i = js.indexOf('const DOM_PROBE = function');
  if (i < 0) { console.log('LIFT-FAIL'); return; }
  let d = 0, j = js.indexOf('{', i);
  for (; j < js.length; j++) { if (js[j] === '{') d++; else if (js[j] === '}' && --d === 0) break; }
  const probeSrc = js.slice(js.indexOf('function', i), j + 1);
  let chromium; try { ({ chromium } = require('playwright')); } catch (e) { console.log('SKIP ' + e.message.split('\n')[0]); return; }
  let b; try { b = await chromium.launch(); } catch (e) { console.log('SKIP ' + e.message.split('\n')[0]); return; }
  const p = await b.newPage({ viewport: { width: 1280, height: 900 }, deviceScaleFactor: 1 });
  await p.goto(require('url').pathToFileURL(path.join(process.env.WORK, 'page.mhtml')).href);
  const probe = await p.evaluate(`(${probeSrc})()`);
  const bodyRows = await p.evaluate(() => document.querySelectorAll('.widget-datagrid-grid-body [role="row"]').length);
  await b.close();
  const R = require('./page-audit-rules.js');
  const rule = R.LIVE_RULES.find(r => r.id === 'live/empty-list-message');
  const res = rule.evaluate({ probe, qn: 'Tasks.Task_Overview_SideBar' });
  console.log('LISTS ' + JSON.stringify(probe.lists));
  console.log('BODYROWS ' + bodyRows);
  console.log('RULE ' + JSON.stringify({ ok: res.ok, detail: res.detail, n: res.findings.length }));
})().catch(e => console.log('ERR ' + e.message));
JSEOF
OUT="$(cd "$WORK/tests/e2e" && printf '%s' "$JS" | SUT="$SUT" WORK="$WORK" timeout 90 node - 2>&1)"
get() { printf '%s\n' "$OUT" | sed -n "s/^$1 //p"; }
if [ -n "$(get SKIP)" ]; then
  echo "  skip — $(get SKIP)"
elif printf '%s\n' "$OUT" | grep -qx LIFT-FAIL; then
  bad "could not lift DOM_PROBE from $SUT"
else
  [ "$(get BODYROWS)" -ge 20 ] 2>/dev/null && ok "capture: one DataGrid2 rendering $(get BODYROWS) body rows" || bad "capture shape" "$(get BODYROWS)"
  LISTS="$(get LISTS)"
  N="$(printf '%s' "$LISTS" | grep -o '"selector"' | wc -l | tr -d ' ')"
  [ "$N" = 1 ] && printf '%s' "$LISTS" | grep -q '"selector":"mx-name-dgSideBar"' \
    && ok "DOM_PROBE counts the grid once, by its name (mx-name-dgSideBar)" || bad "DOM_PROBE list count is $N, want 1" "$LISTS"
  [ "$(get RULE)" = '{"ok":true,"detail":"1 lists on screen; 0 empty","n":0}' ] \
    && ok "live/empty-list-message: 1 list, 0 empty → no P1 finding on a full grid" || bad "empty-list rule on a 20-row grid" "$(get RULE)"
fi
[ -n "$(get ERR)" ] && bad "fixture threw" "$(get ERR)"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
