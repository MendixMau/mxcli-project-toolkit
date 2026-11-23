#!/usr/bin/env bash
# Usage: bash test-design-audit-stale-artifact.sh [path-to-design-audit.js]
#
# Fixture: design-audit.js never leaves the previous run's design-audit.json behind as if current.
#
# The defect (field run 2026-11-20, a real Mendix 11.8 app under `mxcli run --local`): following
# skills/e2e-harness-base.md literally (`npm i -D playwright`) shadowed the container's global
# Playwright with a newer one whose browser was not downloaded. design-audit then crashed at
# chromium.launch (main().catch, exit 1) and wrote nothing — so artifacts/design-audit.json from
# the run before stayed in place, unchanged, and read as this run's result.
# Now: a browser that does not launch is a FAULT row per rung-7 check (the artifact is
# rewritten, exit 2), and any other crash removes the stale artifact (report-normalize then reads
# design-audit as `fault`, "did not run").
#
# Golden input: the launch error is Playwright's own message, verbatim from the field log
# (runtime/designaudit2.log), thrown by a stub `playwright` module so no browser is needed.

set -uo pipefail

SUT="${1:-}"
[ -z "$SUT" ] && SUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/project-tests/e2e/design-audit.js"
[ -f "$SUT" ] || { echo "SKIP: subject not found at $SUT"; exit 0; }
command -v node >/dev/null 2>&1 || { echo "SKIP: node not installed"; exit 0; }
E2E="$(cd "$(dirname "$SUT")" && pwd)"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/dastale.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
D="$WORK/tests/e2e"; mkdir -p "$D/artifacts" "$WORK/node_modules/playwright" "$WORK/node_modules/axe-core"
: > "$WORK/Fixture.mpr"
for f in design-audit.js scope-ensure.js settle.js config.js helpers.js otel.js; do
  [ -f "$E2E/$f" ] && cp "$E2E/$f" "$D/"
done
cat > "$D/project.config.js" <<'EOF'
'use strict';
const path = require('path');
const root = path.resolve(__dirname, '..', '..');
module.exports = { root, rootSource: 'fixture', mpr: path.join(root, 'Fixture.mpr'), mprName: 'Fixture.mpr',
  id: 'fixture', displayName: 'fixture', otelService: 'fixture', defaultPort: '1', mxcli: './mxcli',
  credentials: () => ({ user: 'u', pass: 'p', fallbackUser: '', fallbackPass: '' }),
  readySelectors: ['.mx-page'], signOutPattern: null, dsCss: path.join(root, 'design', 'ds.css'),
  NAV: {}, TARGETS: {}, PAGE_WIREFRAME: {}, probePage: () => null, exemplars: {}, walkthroughs: [],
  roles: {}, walkthrough: null };
EOF
printf '#!/bin/sh\necho "stub mxcli: no model here" >&2\nexit 1\n' > "$WORK/mxcli"; chmod +x "$WORK/mxcli"
echo '/* axe stub */' > "$WORK/node_modules/axe-core/axe.min.js"
echo '{"name":"axe-core","version":"0.0.0","main":"axe.min.js"}' > "$WORK/node_modules/axe-core/package.json"
echo '{"name":"playwright","version":"0.0.0","main":"index.js"}' > "$WORK/node_modules/playwright/package.json"

STALE='{"instrument":"design-audit","STALE_MARKER":true,"checks":[]}'
run() {  # $1 = playwright stub mode
  cat > "$WORK/node_modules/playwright/index.js" <<EOF
const MSG = "browserType.launch: Executable doesn't exist at /opt/pw-browsers/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell\n"
  + "╔════════════════════════════════════════════════════════════╗\n"
  + "║ Looks like Playwright was just installed or updated.       ║";
module.exports = { chromium: { launch: async () => {
  if ('$1' === 'nolaunch') throw new Error(MSG);
  return { newContext: async () => { throw new Error('stub: context crashed'); }, close: async () => {} };
} } };
EOF
  printf '%s' "$STALE" > "$D/artifacts/design-audit.json"
  OUT="$(cd "$D" && MXCLI="$WORK/mxcli" APP_PORT=1 NODE_PATH="$WORK/node_modules" timeout 120 node design-audit.js --page M.Page 2>&1)"; RC=$?
}

echo "== the browser does not launch (Playwright's own message) =="
run nolaunch
F="$D/artifacts/design-audit.json"
if grep -q STALE_MARKER "$F" 2>/dev/null; then
  bad "the previous run's design-audit.json is still there, unchanged" "rc=$RC $(printf '%s' "$OUT" | grep -m1 crashed)"
else
  ok "design-audit.json was rewritten by this run"
  node -e '
    const d = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const r7 = d.checks.filter((c) => /^design-audit\/rung7\/(a11y|overflow|structure)\//.test(c.id));
    process.exit(r7.length === 3 && r7.every((c) => c.verdict === "fault" && /browser did not launch: .*Executable doesn.t exist/.test(c.detail)) ? 0 : 1);
  ' "$F" && ok "each browser rung-7 check (a11y, overflow, structure) is a FAULT naming the launch failure" || bad "rung-7 rows do not name the launch failure" "$(node -e 'require(process.argv[1]).checks.filter((c) => /rung7/.test(c.id)).forEach((c) => console.log(c.id, c.verdict, String(c.detail).slice(0, 140)))' "$F")"
fi
[ "$RC" -eq 2 ] && ok "exit 2 (instrument fault), not a crash" || bad "exit code on a browser that does not launch" "rc=$RC"

echo "== any other crash =="
run crash
if [ -f "$F" ] && grep -q STALE_MARKER "$F"; then
  bad "a crash left the previous run's design-audit.json in place" "rc=$RC"
else
  ok "a crash leaves no stale design-audit.json behind"
fi
printf '%s\n' "$OUT" | grep -q "removed the previous run's" && ok "and says it removed it" || bad "no line about the removed artifact" "$(printf '%s' "$OUT" | tail -3)"
[ "$RC" -eq 1 ] && ok "a crash still exits 1" || bad "crash exit code" "rc=$RC"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
