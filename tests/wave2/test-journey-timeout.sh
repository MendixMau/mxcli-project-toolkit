#!/usr/bin/env bash
# Usage: bash test-journey-timeout.sh [path-to-journey-runner.js]
#
# Fixture for the per-journey timeout in project-tests/e2e/journey-runner.js (speed-night, 2026-11-09:
# run 3 sat ~10 min on one hung journey, nothing said so). Pieces under test:
#   journeyTimeoutMs  default 120 s, JOURNEY_TIMEOUT_S / JOURNEY_TIMEOUT_MS override, 0 = off, junk = default + warning
#   raceTimeout       a promise that outlives the cap loses and its later rejection is swallowed
#   timeoutRows       the failure is NAMED "runtime not serving / journey TIMEOUT" and carries the journey id
#   failedJourneyIds  a findings file with a TIMEOUT row selects that journey for --rerun-failed
# Part B hangs a real Playwright wait (a selector that never appears) against a stand-in page, as the
# runtime-stopped-serving case does, and requires the race to lose within the cap, then closes the
# browser and requires NO unhandled rejection from the abandoned wait. Not fixtured: the main loop's
# wiring (needs a live Mendix app); the field run is cited in the commit.
set -uo pipefail
SUT="${1:-}"
[ -z "$SUT" ] && SUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/project-tests/e2e/journey-runner.js"
[ -f "$SUT" ] || { echo "SKIP: subject not found at $SUT"; echo "SCORE: 0/0 — nothing to test"; exit 0; }
command -v node >/dev/null 2>&1 || { echo "SKIP: node not installed"; exit 0; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
E2E="$(cd "$(dirname "$SUT")" && pwd)"
CFG="$E2E/project.config.template.js"; [ -f "$CFG" ] || CFG="$HERE/../../project-tests/e2e/project.config.template.js"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/journey-timeout.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/tests/e2e"; : > "$WORK/Fixture.mpr"
cp "$SUT" "$E2E/helpers.js" "$E2E/settle.js" "$E2E/otel.js" "$E2E/config.js" "$WORK/tests/e2e/"
cp "$CFG" "$WORK/tests/e2e/project.config.js"

IFS= read -r -d '' JS <<'JSEOF' || true
const http = require('http');
const R = require('./journey-runner.js');
const out = (k, v) => console.log(`${k} ${JSON.stringify(v)}`);
if (typeof R.raceTimeout !== 'function') { console.log('NOFN'); process.exit(0); }
const jt = R.journeyTimeoutMs;
out('A:default', jt({}));
out('A:s', jt({ JOURNEY_TIMEOUT_S: '30' }));
out('A:ms', jt({ JOURNEY_TIMEOUT_MS: '2500' }));
out('A:ms-wins', jt({ JOURNEY_TIMEOUT_MS: '2500', JOURNEY_TIMEOUT_S: '30' }));
out('A:off', jt({ JOURNEY_TIMEOUT_S: '0' }));
out('A:junk', jt({ JOURNEY_TIMEOUT_S: 'soon' }));
out('A:neg', jt({ JOURNEY_TIMEOUT_S: '-5' }));
const t = R.timeoutRows({ id: 'J-REQ-01' }, 120000);
out('A:row-name', t.name);
out('A:row-named', /runtime not serving \/ journey TIMEOUT/.test(t.detail) && /120s/.test(t.detail));
const f = R.failedJourneyIds({ walks: [], results: [{ name: 'J-REQ-01: TIMEOUT', verdict: 'FAIL' }, { name: 'J-APP-01: precondition', verdict: 'INVALID' }] }, new Set(['J-REQ-01', 'J-APP-01', 'J-X']));
out('A:rerun', [...f.ids].sort());
(async () => {
  const slow = new Promise((_, rej) => setTimeout(() => rej(new Error('late boom')), 300));
  let unhandled = 0; process.on('unhandledRejection', () => unhandled++);
  const t0 = Date.now();
  const r1 = await R.raceTimeout(slow, 100);
  out('B:lost', { timedOut: r1.timedOut, fast: Date.now() - t0 < 250 });
  const r2 = await R.raceTimeout(Promise.resolve(42), 100); out('B:won', r2);
  const r3 = await R.raceTimeout(new Promise(r => setTimeout(() => r('late'), 120)), 0); out('B:off', r3);
  await new Promise(r => setTimeout(r, 500));
  out('B:late-rejection-swallowed', unhandled === 0);
  let H; try { H = require('./helpers.js'); if (!H.deviceProfiles()) throw new Error('no playwright'); } catch (e) { out('SKIPB', e.message); return; }
  let browser, page;
  const srv = http.createServer((q, s) => { s.setHeader('content-type', 'text/html'); s.end('<div class="mx-name-page">stopped serving</div>'); });
  await new Promise(r => srv.listen(0, '127.0.0.1', r));
  try { ({ browser, page } = await H.launchBrowser()); } catch (e) { out('SKIPB', e.message.split('\n')[0]); srv.close(); return; }
  await page.goto(`http://localhost:${srv.address().port}/`);
  const t1 = Date.now();
  const hung = await R.raceTimeout(page.waitForSelector('.mx-name-never', { timeout: 30000 }), 700);
  out('C:hung', { timedOut: hung.timedOut, withinCap: Date.now() - t1 < 3000 });
  await browser.close(); srv.close();
  await new Promise(r => setTimeout(r, 600));
  out('C:no-unhandled', unhandled === 0);
})();
JSEOF
OUT="$(cd "$WORK/tests/e2e" && printf '%s' "$JS" | APP_PORT=1 timeout 90 node - 2>&1)"
get() { printf '%s\n' "$OUT" | sed -n "s/^$1 //p"; }
chk() { [ "$(get "$1")" = "$2" ] && ok "$3" || bad "$3" "$(get "$1")"; }
if printf '%s\n' "$OUT" | grep -qx NOFN; then bad "journey-runner.js exports no raceTimeout" "$(printf '%s\n' "$OUT" | tail -3)"
else
  chk A:default '{"ms":120000,"source":"default"}' "default is 120 s"
  chk A:s '{"ms":30000,"source":"env"}' "JOURNEY_TIMEOUT_S=30 -> 30 s"
  chk A:ms '{"ms":2500,"source":"env"}' "JOURNEY_TIMEOUT_MS=2500 -> 2.5 s"
  chk A:ms-wins '{"ms":2500,"source":"env"}' "MS wins when both are set (the experiment-A patch name stays valid)"
  chk A:off '{"ms":0,"source":"env"}' "0 turns the cap off (the run header says so)"
  [ "$(get A:junk | grep -c 'ignored JOURNEY_TIMEOUT value')" -eq 1 ] && ok "junk value -> default plus a warning" || bad "junk value" "$(get A:junk)"
  [ "$(get A:neg | grep -c '"ms":120000')" -eq 1 ] && ok "negative value -> default" || bad "negative" "$(get A:neg)"
  chk A:row-name '"J-REQ-01: TIMEOUT"' "the failure row is named with the journey id"
  chk A:row-named true "the detail says 'runtime not serving / journey TIMEOUT' and the cap"
  chk A:rerun '["J-APP-01","J-REQ-01"]' "--rerun-failed selects the timed-out journey and the not-run one"
  chk B:lost '{"timedOut":true,"fast":true}' "a promise slower than the cap loses, in about the cap"
  chk B:won '{"timedOut":false,"value":42}' "a fast promise wins with its value"
  chk B:off '{"timedOut":false,"value":"late"}' "cap 0 waits for the promise"
  chk B:late-rejection-swallowed true "an abandoned promise's later rejection is not unhandled"
  if [ -n "$(get SKIPB)" ]; then echo "  skip — no Playwright browser here ($(get SKIPB))"
  else
    chk C:hung '{"timedOut":true,"withinCap":true}' "a real Playwright wait that never resolves is cut at the cap"
    chk C:no-unhandled true "closing the browser under the abandoned wait raises no unhandled rejection"
  fi
fi
echo; echo "SCORE: $PASS/$((PASS+FAIL))"; [ "$FAIL" -eq 0 ]
