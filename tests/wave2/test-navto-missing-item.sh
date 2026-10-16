#!/usr/bin/env bash
# Fixture: helpers.navTo throws when the nav item is absent (TK-012, field report from a
# five-app lab project, Mendix 11.15, mxcli v0.26.0). Before: no item found -> nothing
# clicked -> no error -> a broken-control journey on a home page passed.
# Uses a stub page (evaluate = DOM lookup result), so no browser is needed.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
E2E="${1:-$HERE/../../project-tests/e2e}"
# config.js needs a project.config.js; the template is the shipped default.
R="$(mktemp -d)"; trap 'rm -rf "$R"' EXIT; T="$R/tests/e2e"; mkdir -p "$T"; : > "$R/App.mpr"
cp -R "$E2E/." "$T/"; [ -f "$T/project.config.js" ] || cp "$T/project.config.template.js" "$T/project.config.js"
ALLOW_UNVERIFIED_APP=1 node - "$T" "$E2E" <<'JS'
const path = require('path'); const fs = require('fs');
const H = require(path.resolve(process.argv[2], 'helpers.js'));
const mk = (found) => ({
  evaluate: async (fn, t) => (found.includes(t) ? { ok: true, visible: [] } : { ok: false, visible: found }),
  waitForTimeout: async () => {},
  locator: () => ({ first: () => ({ isVisible: async () => false }) }),
});
(async () => {
  let fail = 0;
  const ok = (c, m) => { console.log((c ? 'ok   ' : 'FAIL ') + m); if (!c) fail++; };
  try { await H.navTo(mk(['Orders']), null, 'Orders'); ok(true, 'present item resolves'); }
  catch (e) { ok(false, 'present item resolves: ' + e.message); }
  try { await H.navTo(mk(['Orders']), null, 'Gone'); ok(false, 'absent item throws'); }
  catch (e) { ok(/navigation item "Gone" not found/.test(e.message), 'absent item throws a named error'); }
  try { await H.navTo(mk(['Orders', 'Suppliers']), null, 'Gone'); ok(false, 'message check'); }
  catch (e) {
    ok(/for \S+; visible: Orders, Suppliers\./.test(e.message), 'message names the user and the visible items');
    ok(/fix the journey/.test(e.message) && /role grants/.test(e.message), 'message separates journey fix from role-grant fix');
  }
  try { await H.navTo(mk([]), null, 'Gone'); ok(false, 'empty menu'); }
  catch (e) { ok(/visible: \(none\)/.test(e.message), 'empty menu reads (none)'); }
  // full-app-walkthrough: a missing item on a non-fatal step is a recorded failed step, not a throw.
  {
    const src = fs.readFileSync(path.resolve(process.argv[3], 'full-app-walkthrough.js'), 'utf8');
    const m = src.match(/case 'nav': \{([\s\S]*?)\n    \}\n/);
    const body = m ? m[1] : '';
    const recorded = [];
    const fn = new (Object.getPrototypeOf(async function () {}).constructor)('H', 'page', 'meta', 's', 'label', 'subst', 'p', 'step', 'vis', body);
    let threw = null, rv;
    try {
      rv = await fn(H, mk(['Orders']), { steps: [] }, { do: 'nav', item: 'Gone' }, 'Open Gone', (x) => x, async () => {},
        (meta, okv, label, detail) => { recorded.push({ okv, label, detail }); return okv; }, async () => true);
    } catch (e) { threw = e; }
    ok(m && !threw && rv === false && recorded.length === 1 && recorded[0].okv === false && /not found/.test(recorded[0].detail),
       'walkthrough nav: missing item is a recorded failed step, no throw' + (threw ? ': ' + threw.message : ''));
  }
  try { await H.navTo(mk(['Orders']), 'Menu', 'Orders'); ok(true, 'absent parent, present item resolves'); }
  catch (e) { ok(false, 'absent parent is soft: ' + e.message); }
  process.exit(fail ? 1 : 0);
})();
JS
