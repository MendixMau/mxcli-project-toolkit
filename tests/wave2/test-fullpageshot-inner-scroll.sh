#!/usr/bin/env bash
# Usage: bash test-fullpageshot-inner-scroll.sh [path-to-helpers.js]
#
# Fixture for #812: helpers.js fullPageShot used `page.screenshot({ fullPage: true })`, which
# measures the DOCUMENT. On Mendix 11.8 the Atlas_SideBar and Atlas_TopBar layouts keep the
# document viewport-tall and scroll `.mx-scrollcontainer-center` instead, so the "full page" shot
# stopped at the viewport (900 px) and the grid's lower rows and paging bar were never in it.
# Atlas_Default scrolls the document, and that shape must keep its full shot.
#
# Golden input is CAPTURED (fixtures/runtime-mx118/overview-*-1280x900.mhtml.gz): CDP MHTML
# snapshots (DOM plus CSS) of the same 29-row overview page under both layouts, from a live
# Mendix 11.8.0 runtime. Chromium loads them from file:// at 1280x900 — no app needed.

set -uo pipefail

SUT="${1:-}"
[ -z "$SUT" ] && SUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/project-tests/e2e/helpers.js"
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
FIX="$HERE/fixtures/runtime-mx118"
for l in SideBar Default; do
  [ -f "$FIX/overview-$l-1280x900.mhtml.gz" ] || { echo "FAIL — golden capture missing: $FIX/overview-$l-1280x900.mhtml.gz"; exit 1; }
done

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/fullpageshot.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/tests/e2e"; : > "$WORK/Fixture.mpr"
cp "$SUT" "$E2E/config.js" "$WORK/tests/e2e/"
cp "$CFG" "$WORK/tests/e2e/project.config.js"
for l in SideBar Default; do gzip -dc "$FIX/overview-$l-1280x900.mhtml.gz" > "$WORK/$l.mhtml"; done

IFS= read -r -d '' JS <<'JSEOF' || true
const fs = require('fs'); const path = require('path');
(async () => {
  let H, chromium;
  try { H = require('./helpers.js'); ({ chromium } = require('playwright')); } catch (e) { console.log('SKIP ' + e.message.split('\n')[0]); return; }
  let b; try { b = await chromium.launch(); } catch (e) { console.log('SKIP ' + e.message.split('\n')[0]); return; }
  for (const l of ['SideBar', 'Default']) {
    const p = await b.newPage({ viewport: { width: 1280, height: 900 }, deviceScaleFactor: 1 });
    await p.goto(require('url').pathToFileURL(path.join(process.env.WORK, l + '.mhtml')).href);
    const m = await p.evaluate(() => { const c = document.querySelector('.mx-scrollcontainer-center');
      return { doc: document.documentElement.scrollHeight, center: c.scrollHeight, client: c.clientHeight }; });
    const file = path.join(process.env.WORK, l + '.png');
    const rec = await H.fullPageShot(p, file);
    const png = fs.existsSync(file) ? fs.readFileSync(file) : null;
    console.log(`${l} ` + JSON.stringify({ ...m, shotH: png ? png.readUInt32BE(20) : 0, shotW: png ? png.readUInt32BE(16) : 0,
      vpAfter: p.viewportSize().height, complete: rec && rec.complete, root: rec && rec.scrollRoot, error: rec && rec.error }));
    await p.close();
  }
  await b.close();
})().catch(e => console.log('ERR ' + e.message));
JSEOF
OUT="$(cd "$WORK/tests/e2e" && printf '%s' "$JS" | WORK="$WORK" APP_PORT=1 timeout 120 node - 2>&1)"
get() { printf '%s\n' "$OUT" | sed -n "s/^$1 //p"; }
if [ -n "$(get SKIP)" ]; then
  echo "  skip — $(get SKIP)"
else
  SB="$(get SideBar)"; DF="$(get Default)"
  num() { printf '%s' "$1" | sed -n "s/.*\"$2\":\([0-9]*\).*/\1/p"; }
  # The capture must still show the shape: SideBar's document is viewport-tall, its centre scrolls.
  [ "$(num "$SB" doc)" = 900 ] && [ "$(num "$SB" center)" -gt 1000 ] \
    && ok "SideBar capture: document 900 px, .mx-scrollcontainer-center $(num "$SB" center) px (inner scroll)" || bad "SideBar capture shape" "$SB"
  [ "$(num "$DF" doc)" -gt 1000 ] && [ "$(num "$DF" center)" = "$(num "$DF" client)" ] \
    && ok "Default capture: the document scrolls ($(num "$DF" doc) px), the centre does not" || bad "Default capture shape" "$DF"
  H="$(num "$SB" shotH)"; C="$(num "$SB" center)"
  [ -n "$H" ] && [ "$H" -ge "$C" ] && [ "$H" -le $((C + 60)) ] \
    && ok "SideBar: shot is ${H} px for ${C} px of content (was cut at the 900 px viewport)" || bad "SideBar shot cropped" "$SB"
  printf '%s' "$SB" | grep -q '"complete":true' && printf '%s' "$SB" | grep -q '"root":"div.mx-scrollcontainer-center"' \
    && ok "SideBar: the shot's record names its scroll root and says complete" || bad "SideBar shot record" "$SB"
  [ "$(num "$SB" vpAfter)" = 900 ] && [ "$(num "$SB" shotW)" = 1280 ] && ok "SideBar: viewport restored to 900 px, width unchanged" || bad "viewport not restored" "$SB"
  [ "$(num "$DF" shotH)" = "$(num "$DF" doc)" ] \
    && ok "Default: shot is the full document ($(num "$DF" shotH) px), the plain fullPage path kept" || bad "Default shot" "$DF"
fi
[ -n "$(get ERR)" ] && bad "fixture threw" "$(get ERR)"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
