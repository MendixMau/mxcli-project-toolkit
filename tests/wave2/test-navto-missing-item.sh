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
ALLOW_UNVERIFIED_APP=1 node - "$T" <<'JS'
const path = require('path');
const H = require(path.resolve(process.argv[2], 'helpers.js'));
const mk = (found) => ({
  evaluate: async (fn, t) => found.includes(t),
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
  try { await H.navTo(mk(['Orders']), 'Menu', 'Orders'); ok(true, 'absent parent, present item resolves'); }
  catch (e) { ok(false, 'absent parent is soft: ' + e.message); }
  process.exit(fail ? 1 : 0);
})();
JS
