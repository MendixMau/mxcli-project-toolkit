#!/usr/bin/env bash
# Usage: bash test-e2e-visible-wait.sh [path-to-helpers.js]
#
# Fixture for #536's remaining sites: helpers.js visibleWithin() and its callers.
# Playwright's locator.isVisible() ignores its `timeout` option and answers at once, so
# `isVisible({ timeout: 6000 })` read an element that was attached but still fading in (or a page
# still rendering) as "not visible" in 0 ms. #547 fixed the journey landing guard; the click /
# fill / combobox actions and gotoTarget()'s ready wait still used it.
#
# Part 1 runs anywhere node does: a stand-in locator proves visibleWithin() waits through
# waitFor({ state: 'visible' }) and never through isVisible(). Part 2 is the issue's own
# reproduction in real Chromium (skipped, and said so, where Playwright has no browser).

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
RUNNER="$E2E/journey-runner.js"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

# helpers.js resolves a project at require time: an .mpr two levels up.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/visible-wait.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/tests/e2e"; : > "$WORK/Fixture.mpr"
cp "$SUT" "$E2E/config.js" "$WORK/tests/e2e/"
cp "$CFG" "$WORK/tests/e2e/project.config.js"

IFS= read -r -d '' JS <<'JSEOF' || true
const H = require('./helpers.js');
if (typeof H.visibleWithin !== 'function') { console.log('NOFN'); process.exit(0); }
(async () => {
  // A locator whose element turns visible after `after` ms; isVisible() is the instant answer.
  const fake = (after) => { const t0 = Date.now(); const calls = [];
    return { calls,
      isVisible: async () => { calls.push('isVisible'); return Date.now() - t0 >= after; },
      waitFor: ({ state, timeout }) => { calls.push(`waitFor:${state}:${timeout}`);
        return new Promise((res, rej) => after <= timeout ? setTimeout(res, after) : setTimeout(() => rej(new Error('Timeout')), timeout)); } }; };
  const late = fake(300); const r1 = await H.visibleWithin(late, 2000);
  const never = fake(1e9); const r2 = await H.visibleWithin(never, 200);
  console.log('FAKE ' + JSON.stringify({ late: r1, lateCalls: late.calls, never: r2 }));
  let pw = null; try { pw = require('playwright'); } catch (e) {}
  if (!pw) { console.log('REAL SKIP playwright not installed'); return; }
  let b; try { b = await pw.chromium.launch(); } catch (e) { console.log('REAL SKIP ' + String(e.message).split('\n')[0]); return; }
  const p = await b.newPage();
  // The issue's reproduction, verbatim shape: shown 2 s after load.
  await p.setContent('<div id="x" style="display:none">hi</div>' +
    '<script>setTimeout(() => document.getElementById("x").style.display = "block", 2000)</script>');
  const instant = await p.locator('#x').isVisible({ timeout: 5000 });
  const t = Date.now(); const waited = await H.visibleWithin(p.locator('#x'), 5000); const ms = Date.now() - t;
  const miss = await H.visibleWithin(p.locator('#nope'), 300);
  await b.close();
  console.log('REAL ' + JSON.stringify({ instant, waited, slow: ms >= 1000, miss }));
})().then(() => process.exit(0));
JSEOF
OUT="$(cd "$WORK/tests/e2e" && printf '%s' "$JS" | APP_PORT=1 timeout 60 node - 2>&1)"
get() { printf '%s\n' "$OUT" | sed -n "s/^$1 //p"; }
if printf '%s\n' "$OUT" | grep -qx NOFN || [ -z "$(get FAKE)" ]; then
  bad "#536 helpers.js exports no visibleWithin()" "$(printf '%s\n' "$OUT" | tail -3)"
else
  [ "$(get FAKE)" = '{"late":true,"lateCalls":["waitFor:visible:2000"],"never":false}' ] \
    && ok "#536 visibleWithin() waits through waitFor({state:'visible'}) with its budget: late element true, absent false" \
    || bad "#536 visibleWithin() does not wait as stated" "$(get FAKE)"
  case "$(get REAL)" in
    SKIP*) echo "  skip — real-browser reproduction: $(get REAL)" ;;
    '{"instant":false,"waited":true,"slow":true,"miss":false}') ok "#536 Chromium: isVisible({timeout}) answers false at once; visibleWithin() waits ~2 s and answers true" ;;
    *) bad "#536 real-browser reproduction" "$(get REAL)" ;;
  esac
fi
# The callers that mean "wait" use it; the misleading form is gone from them.
grep -qF "await visibleWithin(page.locator(target.ready).first(), 6000);" "$SUT" \
  && ok "#536 gotoTarget() waits for target.ready" || bad "#536 gotoTarget() still reads target.ready with isVisible({timeout})"
if [ -f "$RUNNER" ]; then
  n="$(grep -c 'H.visibleWithin(' "$RUNNER")"
  [ "$n" -ge 3 ] && ! grep -qE "(el|box)\.isVisible\(\{ timeout" "$RUNNER" \
    && ok "#536 journey-runner click / fill / combobox wait with visibleWithin() ($n sites, no isVisible({timeout}) left on them)" \
    || bad "#536 a journey-runner action still uses isVisible({timeout})" "$n sites; $(grep -nE '(el|box)\.isVisible\(\{ timeout' "$RUNNER" | head -3)"
fi
# The remaining sites that mean "wait" (#536, review follow-up): journey-runner's ui.checks loop
# (journey-examples.md says "4 s each"), monkey.js land() / the blank-page oracle / the re-land
# check, full-app-walkthrough.js vis() / expectAbsent / fill / widget checks, gotoTarget()'s nav.
# Instant probes (the spinner checks, the login helpers) stay instant on purpose.
if [ -f "$RUNNER" ]; then
  grep -qF 'const seen = await H.visibleWithin(page.locator(`.mx-name-${c}`).first(), 4000);' "$RUNNER"     && ok "#536 journey-runner ui.checks waits up to 4 s per widget" || bad "#536 ui.checks still answers at once"
fi
MONKEY="$E2E/monkey.js"; WALK="$E2E/full-app-walkthrough.js"
if [ -f "$MONKEY" ]; then
  n="$(grep -c "H.visibleWithin(page.locator('.mx-page" "$MONKEY")"
  [ "$n" -ge 2 ] && grep -qF "H.visibleWithin(page.locator('.mx-page, .mx-navigationtree').first(), 3000)" "$MONKEY"     && ok "#536 monkey.js land(), the re-land check and the blank-page oracle wait ($((n+1)) sites)"     || bad "#536 monkey.js still reads .mx-page with isVisible({timeout})" "$(grep -n "mx-page').first().isVisible" "$MONKEY" | head -3)"
fi
if [ -f "$WALK" ]; then
  ! grep -qE 'isVisible\(\{ timeout' "$WALK" && grep -qF 'const vis = (n, ms = 6000) => H.visibleWithin(w(n), ms);' "$WALK"     && ok "#536 full-app-walkthrough.js has no isVisible({timeout}) left; vis() waits"     || bad "#536 full-app-walkthrough.js still uses isVisible({timeout})" "$(grep -nE 'isVisible\(\{ timeout' "$WALK" | head -3)"
fi
grep -qF "if (await visibleWithin(nav, 3000)) {" "$SUT" && ok "#536 gotoTarget() waits for its nav anchor" || bad "#536 gotoTarget() nav still answers at once"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
