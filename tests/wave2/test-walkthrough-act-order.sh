#!/usr/bin/env bash
# Usage: bash test-walkthrough-act-order.sh [path-to-full-app-walkthrough.js]
#
# Fixture: full-app-walkthrough.js reads an act's widget `checks` on the act's LANDING page.
#
# The defect (field run 2026-11-20, a real Mendix 11.8 app under `mxcli run --local`): the act
# loop evaluated `act.checks` before the act's own `steps`. The first act has no handoffAssert to
# navigate for it, so when its first step is the `nav` that opens its page — the shape the
# template's own example act had — every check was read on the home page and FAILed:
#     ✗ raise:widget:dgTasks … not visible
#     ✓ raise:Tasks opens                      (the nav, one line later)
# Now an act's LEADING nav steps run first, then its checks, then the rest of its steps.
#
# No browser and no app: helpers.js is replaced by a stub whose page knows which menu item it
# is on and which widgets each page shows; config.js and the walkthrough are the real files.

set -uo pipefail

SUT="${1:-}"
[ -z "$SUT" ] && SUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/project-tests/e2e/full-app-walkthrough.js"
[ -f "$SUT" ] || { echo "SKIP: subject not found at $SUT"; exit 0; }
command -v node >/dev/null 2>&1 || { echo "SKIP: node not installed"; exit 0; }
E2E="$(cd "$(dirname "$SUT")" && pwd)"
[ -f "$E2E/config.js" ] || { echo "FAIL — config.js not beside $SUT"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/walkorder.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
D="$WORK/tests/e2e"; mkdir -p "$D"; : > "$WORK/Fixture.mpr"
cp "$SUT" "$D/full-app-walkthrough.js"; cp "$E2E/config.js" "$D/config.js"

cat > "$D/helpers.js" <<'EOF'
'use strict';
const fs = require('fs'), path = require('path');
// Which widgets each "page" shows. The app starts on Home.
const PAGES = { Home: ['homeTile'], Orders: ['dgOrders', 'btnNew'], Queue: ['dgQueue', 'btnApprove'] };
const page = {
  cur: 'Home',
  on() {}, url() { return 'http://stub/' + this.cur; }, video() { return null; },
  locator(sel) { const pg = this; return { first: () => ({ sel, pg }) }; },
};
const results = [];
module.exports = {
  fs, path, process,
  ensureDirs: (...d) => d.forEach((x) => fs.mkdirSync(x, { recursive: true })),
  makeReporter: () => ({
    pass: (id, l) => { results.push({ id, ok: true }); console.log('  ✓ ' + id); },
    fail: (id, l, d) => { results.push({ id, ok: false }); console.log('  ✗ ' + id + ' — ' + d); },
    summary: () => ({ results, passed: results.filter((r) => r.ok).length, failed: results.filter((r) => !r.ok).length }),
  }),
  launchBrowser: async () => ({ browser: { close: async () => {} },
    context: { close: async () => {}, tracing: { stop: async () => {} } }, page }),
  login: async () => ({ ok: true, user: 'u1' }),
  logout: async () => true,
  navTo: async (pg, group, item) => { if (!PAGES[item]) throw new Error(`navigation item "${item}" not found`); pg.cur = item; },
  visibleWithin: async (loc) => {
    const m = /mx-name-([A-Za-z0-9_]+)/.exec(loc.sel);
    if (!m) return true;                       // the app-shell selector
    return (PAGES[loc.pg.cur] || []).includes(m[1]);
  },
  fullPageShot: async () => {}, oqlScalar: () => '1', dismissModal: async () => {},
  humanClick: async () => {}, humanType: async () => {}, humanTypeKeys: async () => {},
  injectCursor: async () => {}, injectOqlOverlay: async () => {},
};
EOF

cat > "$D/project.config.js" <<'EOF'
'use strict';
const path = require('path');
module.exports = {
  root: path.resolve(__dirname, '..', '..'), rootSource: 'fixture', mpr: path.resolve(__dirname, '..', '..', 'Fixture.mpr'),
  mprName: 'Fixture.mpr', id: 'fixture', displayName: 'fixture', otelService: 'fixture', defaultPort: '1',
  mxcli: './mxcli', credentials: () => ({ user: 'u1', pass: 'p', fallbackUser: '', fallbackPass: '' }),
  readySelectors: ['.mx-page'], signOutPattern: null, NAV: {}, TARGETS: {}, PAGE_WIREFRAME: {},
  probePage: () => null, exemplars: {}, walkthroughs: [],
  roles: { r1: { label: 'Requester', user: 'u1', pass: 'p' }, r2: { label: 'Approver', user: 'u2', pass: 'p' } },
  walkthrough: {
    label: 'fixture', process: 'raise then approve', seeds: [],
    acts: [
      // The first act: arrives by its own leading nav step (no handoffAssert).
      { key: 'raise', role: 'r1', module: 'M1', checks: ['dgOrders', 'btnNew'],
        steps: [{ do: 'nav', item: 'Orders', ready: 'dgOrders', label: 'Orders opens', fatal: true },
                { do: 'expect', widget: 'btnNew', label: 'New is offered' }] },
      // A handoff act: arrives by handoffAssert; its first step is NOT a nav, so it is unchanged.
      { key: 'approve', role: 'r2', module: 'M2', checks: ['dgQueue'],
        handoffAssert: [{ do: 'nav', item: 'Queue', ready: 'dgQueue', fatal: true }],
        steps: [{ do: 'expect', widget: 'btnApprove', label: 'Approve is offered' }] },
      // A fatal arrival that fails: checks must be NOT REACHED, not read on the wrong page.
      { key: 'gone', role: 'r2', module: 'M2', checks: ['dgGone'],
        steps: [{ do: 'nav', item: 'Gone', ready: 'dgGone', label: 'Gone opens', fatal: true }] },
    ],
    cleanup: null,
  },
};
EOF

OUT="$(cd "$D" && APP_PORT=1 SPEED=1000 DEMO_SPEED=1000 timeout 120 node full-app-walkthrough.js 2>&1)"; RC=$?
F="$D/artifacts/findings.json"
if [ ! -f "$F" ]; then bad "the walk wrote no findings.json" "rc=$RC $(printf '%s' "$OUT" | tail -5)"; else
  IFS= read -r -d '' JS <<'EOF' || true
const d = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
const pg = (k) => d.pages.find((p) => p.key === k) || { widgets: [], steps: [] };
const w = (k, n) => (pg(k).widgets.find((x) => x.name === n) || {});
console.log('RAISE ' + w('raise', 'dgOrders').status + ',' + w('raise', 'btnNew').status);
console.log('APPROVE ' + w('approve', 'dgQueue').status);
console.log('GONE ' + w('gone', 'dgGone').status + '|' + /NOT REACHED/.test(w('gone', 'dgGone').detail || ''));
console.log('STEPS ' + pg('raise').steps.map((s) => s.label + ':' + s.status).join(','));
EOF
  R="$(node -e "$JS" "$F" 2>&1)"
  line() { printf '%s\n' "$R" | sed -n "s/^$1 //p"; }
  [ "$(line RAISE)" = "ok,ok" ] && ok "first act: checks read AFTER its leading nav (dgOrders, btnNew present)" \
    || bad "first act's checks were read before it navigated" "$(line RAISE)"
  [ "$(line APPROVE)" = "ok" ] && ok "handoff act: checks read after handoffAssert (unchanged)" || bad "handoff act checks" "$(line APPROVE)"
  [ "$(line GONE)" = "missing|true" ] && ok "a fatal arrival leaves its checks NOT REACHED, not read on the previous page" \
    || bad "fatal-arrival checks" "$(line GONE)"
  printf '%s\n' "$(line STEPS)" | grep -q 'Orders opens:pass' && printf '%s\n' "$(line STEPS)" | grep -q 'New is offered:pass' \
    && ok "the first act's steps still all run, once each" || bad "first act steps" "$(line STEPS)"
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
