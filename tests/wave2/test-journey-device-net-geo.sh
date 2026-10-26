#!/usr/bin/env bash
# Usage: bash test-journey-device-net-geo.sh [path-to-journey-runner.js]
#
# Fixture for #521 / #522: journey-runner.js's phone device per run, `offline` / `online` steps and a
# GPS fix per step, and validate-journeys.js accepting them. The defect: every journey opened in one
# 1440x900 desktop window (Mendix served the Responsive profile, so a phone journey failed at step 1
# for a setup reason); an "offline" step was a labelled `wait` that never left the network; a
# nanoflow reading the position got "permission denied". The reporter's project ruled every result
# for its 20 phone journeys INVALID.
#
# Part A runs the pure functions against Playwright's real device table (or a stand-in when Playwright
# is absent). Part B drives a real headless Chromium against a throwaway http://localhost page: the
# phone context measures 390x844 with touch, the position reads "denied" → the fix → the next fix →
# "denied" after the clear, and an offline reload fails until the runner goes back online. Part B
# SKIPs (counted in neither column) when Playwright or its browser is not installed.

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

WORK="$(mktemp -d "${TMPDIR:-/tmp}/journey-dng.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/tests/e2e"; : > "$WORK/Fixture.mpr"
cp "$SUT" "$E2E/helpers.js" "$E2E/settle.js" "$E2E/otel.js" "$E2E/config.js" "$WORK/tests/e2e/"
cp "$CFG" "$WORK/tests/e2e/project.config.js"

echo "A. device, network and position, as functions"
IFS= read -r -d '' JS <<'JSEOF' || true
const R = require('./journey-runner.js');
if (typeof R.resolveDevice !== 'function' || typeof R.resolveGeolocation !== 'function') { console.log('NOFN'); process.exit(0); }
let P = null; try { P = require('./helpers.js').deviceProfiles(); } catch (_) {}
if (!P) P = { 'iPhone 13': { userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X)', screen: { width: 390, height: 844 },
                             viewport: { width: 390, height: 664 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true },
              'iPhone 12': { userAgent: 'x', screen: { width: 390, height: 844 }, viewport: { width: 390, height: 664 }, isMobile: true, hasTouch: true } };
const o = { env: {}, profiles: P };
const out = (k, v) => console.log(`${k} ${JSON.stringify(v)}`);
out('D:none', R.resolveDevice({ id: 'a' }, o));
const ph = R.resolveDevice({ id: 'b', device: 'iPhone 13' }, o);
out('D:phone', [ph.key, ph.options.isMobile, ph.options.hasTouch]);
out('D:sized', R.resolveDevice({ id: 'c', device: { name: 'iPhone 13', viewport: { width: 390, height: 700 } } }, o).key);
out('D:vpmobile', R.resolveDevice({ id: 'd', viewport: { width: 400, height: 800, isMobile: true } }, o).options.isMobile);
out('D:vpdesk', R.resolveDevice({ id: 'e', viewport: { width: 1280, height: 720 } }, o));
out('D:unknown', R.resolveDevice({ id: 'f', device: 'iPhone 99' }, o).error || '');
out('D:override', R.resolveDevice({ id: 'g', device: 'iPhone 13' }, { env: { JOURNEY_DEVICE: 'desktop' }, profiles: P }).key);
out('D:mixed', R.runDevice([{ id: 'a' }, { id: 'b', device: 'iPhone 13' }], o).problems);
out('D:same', R.runDevice([{ id: 'b', device: 'iPhone 13' }, { id: 'h', device: 'iPhone 13' }], o).problems);
out('J:desk', R.judgeDevice(ph, { width: 1440, height: 900, ua: 'Mozilla/5.0 (X11; Linux x86_64)', touch: 0 }).ok);
out('J:phone', R.judgeDevice(ph, { width: 390, height: 844, ua: ph.options.userAgent, touch: 1 }).ok);
out('J:default', R.judgeDevice(R.resolveDevice({ id: 'a' }, o), { width: 1, height: 1 }).ok);
out('N:verbs', [R.networkVerb({ do: 'offline' }), R.networkVerb({ do: 'online' }), R.networkVerb({ do: 'wait', ms: 5 }),
                R.networkVerb({ do: 'wait', label: 'SET THE BROWSER OFFLINE HERE (context.setOffline(true))' })]);
out('N:end', [R.networkEndRow('J', true, true) && R.networkEndRow('J', true, true).verdict, R.networkEndRow('J', true, false), R.networkEndRow('J', false, true)]);
out('G:seed', R.resolveGeolocation({ latitude: '{{lat}}', longitude: 4.9, accuracy: 10 }, { lat: '52.37' }));
out('G:range', R.resolveGeolocation({ latitude: 95, longitude: 4.9 }).ok);
out('G:empty', R.resolveGeolocation({ latitude: '', longitude: 4.9 }).ok);
out('G:unres', R.resolveGeolocation({ latitude: '{{x}}', longitude: 4.9 }, {}).ok);
out('G:pick', [R.stepGeolocation({ geolocation: 1 }, {}, 0), R.stepGeolocation({ geolocation: 1 }, {}, 1), R.stepGeolocation({}, { _geolocation: 2 }, 3)]);
// A network step never touches the page: act() on a page whose locator() throws.
(async () => {
  let off = null;
  const page = { locator() { throw new Error('page touched'); }, context: () => ({ setOffline: async v => { off = v; } }) };
  try { await R.act(page, { do: 'offline' }, {}, () => {}); out('A:offline', [off, R.isOffline()]);
        await R.act(page, { do: 'online' }, {}, () => {}); out('A:online', [off, R.isOffline()]); }
  catch (e) { out('A:offline', e.message); }
})();
JSEOF
OUT="$(cd "$WORK/tests/e2e" && printf '%s' "$JS" | APP_PORT=1 timeout 60 node - 2>&1)"
get() { printf '%s\n' "$OUT" | sed -n "s/^$1 //p"; }
if printf '%s\n' "$OUT" | grep -qx NOFN || [ -z "$(get D:none)" ]; then
  bad "journey-runner.js exports no resolveDevice / resolveGeolocation (#521)" "$(printf '%s\n' "$OUT" | tail -3)"
else
  [ "$(get D:none)" = '{"kind":"desktop","key":"desktop","options":null}' ] && ok "a journey with no device keeps the default desktop launch (no context options)" || bad "default launch changed" "$(get D:none)"
  [ "$(get D:phone)" = '["iPhone 13 390x844",true,true]' ] && ok "\"device\": \"iPhone 13\" → 390x844 (the profile's screen, not its 390x664 viewport), mobile, touch" || bad "named device" "$(get D:phone)"
  [ "$(get D:sized)" = '"iPhone 13 390x700"' ] && ok "a device object's viewport sets the size" || bad "device object" "$(get D:sized)"
  [ "$(get D:vpmobile)" = true ] && ok "viewport + isMobile → a phone context" || bad "viewport isMobile" "$(get D:vpmobile)"
  [ "$(get D:vpdesk)" = '{"kind":"desktop","key":"desktop 1280x720","options":{"viewport":{"width":1280,"height":720}}}' ] && ok "viewport without isMobile → a desktop window of that size" || bad "desktop viewport" "$(get D:vpdesk)"
  case "$(get D:unknown)" in *'unknown device \"iPhone 99\"'*'nearest known:'*'never swaps'*) ok "an unknown device name is refused with the nearest known ones" ;; *) bad "unknown device not refused" "$(get D:unknown)" ;; esac
  [ "$(get D:override)" = '"desktop"' ] && ok "JOURNEY_DEVICE=desktop overrides a journey's device" || bad "override" "$(get D:override)"
  case "$(get D:mixed)" in *'one run is one browser context'*'desktop: a'*'iPhone 13 390x844: b'*) ok "a run mixing devices is a SETUP problem naming which journey needs which" ;; *) bad "mixed run not refused" "$(get D:mixed)" ;; esac
  [ "$(get D:same)" = '[]' ] && ok "journeys sharing one device run together" || bad "same-device run refused" "$(get D:same)"
  [ "$(get J:desk)" = false ] && [ "$(get J:phone)" = true ] && [ "$(get J:default)" = true ] && ok "judgeDevice: a desktop measurement for a phone journey is a mismatch; the phone's own is not" || bad "judgeDevice" "$(get J:desk)/$(get J:phone)/$(get J:default)"
  [ "$(get N:verbs)" = '[true,false,null,true]' ] && ok "offline / online verbs, a plain wait is not one, the legacy labelled wait is honoured" || bad "networkVerb" "$(get N:verbs)"
  [ "$(get N:end)" = '["INVALID",null,null]' ] && ok "still offline after walking every step → setup INVALID; a bail-out or an online end adds no row" || bad "networkEndRow" "$(get N:end)"
  [ "$(get G:seed)" = '{"ok":true,"value":{"latitude":52.37,"longitude":4.9,"accuracy":10}}' ] && ok "a GPS fix resolves a {{seed}} to a number" || bad "seeded fix" "$(get G:seed)"
  [ "$(get G:range)" = false ] && [ "$(get G:empty)" = false ] && [ "$(get G:unres)" = false ] && ok "latitude 95, an empty latitude and an unresolved placeholder are refused (never sent as 0,0)" || bad "bad fixes accepted" "$(get G:range)/$(get G:empty)/$(get G:unres)"
  [ "$(get G:pick)" = '[{"spec":1,"legacy":false},null,{"spec":2,"legacy":true}]' ] && ok "the journey's fix applies from step 1; _geolocation is read as legacy" || bad "stepGeolocation" "$(get G:pick)"
  [ "$(get A:offline)" = '[true,true]' ] && [ "$(get A:online)" = '[false,false]' ] && ok "act() offline/online calls context.setOffline and never touches the page" || bad "network act" "$(get A:offline) $(get A:online)"
fi

# Wiring, by inspection of the shipped source.
grep -qF "await H.launchBrowser({ contextOptions: contextOptions(dev.device) })" "$SUT" \
  && awk '/const dev = runDevice\(journeys/{d=1} d&&/process\.exit\(2\)/{e=1} e&&/H\.launchBrowser\(/{l=1} END{exit !l}' "$SUT" \
  && ok "the device is decided (exit 2 on a problem) before the browser opens" || bad "device not wired before launch"
awk '/RELEASE = async/{r=1} r&&/ensureOnline\(page\)/{o=1} o&&/H\.logout\(page\)/{l=1} END{exit !l}' "$SUT" \
  && ok "the sign-out goes back online first (an offline logout leaks a session)" || bad "release does not go online before logout"
[ "$(grep -c 'await endJourneyEnv(page, ' "$SUT")" -ge 2 ] && ok "every walk and every mutant ends with endJourneyEnv (online, position cleared)" || bad "endJourneyEnv not called after walks and mutants"

echo "B. a real Chromium, a throwaway localhost page"
IFS= read -r -d '' BJS <<'JSEOF' || true
const http = require('http');
let R, H;
try { R = require('./journey-runner.js'); H = require('./helpers.js'); if (!H.deviceProfiles()) throw new Error('no playwright'); }
catch (e) { console.log('SKIPB ' + e.message); process.exit(0); }
(async () => {
  const srv = http.createServer((q, s) => { s.setHeader('content-type', 'text/html'); s.end('<meta name=viewport content="width=device-width"><p>hi</p>'); });
  await new Promise(r => srv.listen(0, '127.0.0.1', r));
  const url = `http://localhost:${srv.address().port}/`;
  const dev = R.runDevice([{ id: 'p', device: 'iPhone 13' }], { env: {}, profiles: H.deviceProfiles() }).device;
  let browser, page;
  try { ({ browser, page } = await H.launchBrowser({ contextOptions: R.contextOptions(dev) })); }
  catch (e) { console.log('SKIPB ' + e.message.split('\n')[0]); srv.close(); process.exit(0); }
  const vp = page.viewportSize();
  const e = await page.evaluate(() => ({ ua: navigator.userAgent, touch: navigator.maxTouchPoints }));
  console.log('B:dev ' + JSON.stringify([vp.width, vp.height, e.touch > 0, R.judgeDevice(dev, { width: vp.width, height: vp.height, ...e }).ok]));
  await page.goto(url);
  const pos = () => page.evaluate(() => new Promise(r => navigator.geolocation.getCurrentPosition(
    p => r(`${p.coords.latitude},${p.coords.longitude}`), () => r('denied'), { timeout: 3000 })));
  const seen = [await pos()];
  await R.applyGeolocation(page, { latitude: 52.37, longitude: 4.9 }); seen.push(await pos());
  await R.applyGeolocation(page, { latitude: 1.3, longitude: 103.8 }); seen.push(await pos());
  await R.clearGeolocation(page); seen.push(await pos());
  console.log('B:geo ' + JSON.stringify(seen));
  const reload = () => page.reload().then(() => 'ok', () => 'failed');
  await R.act(page, { do: 'offline' }, {}, () => {});
  const r1 = await reload();
  const was = await R.ensureOnline(page);
  console.log('B:net ' + JSON.stringify([r1, was, await reload()]));
  await browser.close(); srv.close();
})().catch(e => { console.log('BERR ' + e.message); process.exit(0); });
JSEOF
BOUT="$(cd "$WORK/tests/e2e" && printf '%s' "$BJS" | APP_PORT=1 timeout 90 node - 2>&1)"
bget() { printf '%s\n' "$BOUT" | sed -n "s/^$1 //p"; }
if printf '%s\n' "$BOUT" | grep -q '^SKIPB'; then
  echo "  skip — no Playwright browser here ($(bget SKIPB))"
else
  [ "$(bget B:dev)" = '[390,844,true,true]' ] && ok "a phone context measures 390x844 with touch, and judgeDevice agrees" || bad "phone context" "$(bget B:dev) $(bget BERR)"
  [ "$(bget B:geo)" = '["denied","52.37,4.9","1.3,103.8","denied"]' ] && ok "position: denied → the fix → the next fix → denied after the clear" || bad "geolocation" "$(bget B:geo) $(bget BERR)"
  [ "$(bget B:net)" = '["failed",true,"ok"]' ] && ok "offline: a reload fails; ensureOnline restores it and the reload works" || bad "offline/online" "$(bget B:net) $(bget BERR)"
fi

echo "C. validate-journeys.js (#522)"
if [ -f "$VALIDATOR" ]; then
  printf '%s' '{"id":"J","steps":[{"name":"s","actions":[{"do":"offline"},{"do":"online"}]}]}' > "$WORK/v1.json"
  printf '%s' '{"id":"J","device":"iPhone 13","seeds":[{"name":"lat","sql":"SELECT 1 AS n"}],"steps":[{"name":"s","geolocation":{"latitude":"{{lat}}","longitude":4.9},"actions":[]}]}' > "$WORK/v2.json"
  printf '%s' '{"id":"J","steps":[{"name":"s","geolocation":{"latitude":95,"longitude":4.9},"spams":{"ordered":["M.A"]},"actions":[]}]}' > "$WORK/v3.json"
  node "$VALIDATOR" "$WORK/v1.json" >/dev/null 2>&1 && ok "offline / online are accepted (the issue's repro 1)" || bad "validator rejects offline/online" "$(node "$VALIDATOR" "$WORK/v1.json" 2>&1 | head -3)"
  node "$VALIDATOR" "$WORK/v2.json" >/dev/null 2>&1 && ok "a device and a seeded GPS fix are accepted" || bad "validator rejects device/geolocation" "$(node "$VALIDATOR" "$WORK/v2.json" 2>&1 | head -3)"
  V3="$(node "$VALIDATOR" "$WORK/v3.json" 2>&1)"
  printf '%s' "$V3" | grep -q 'not a number in \[-90, 90\]' && printf '%s' "$V3" | grep -q 'likely a typo for `spans`' \
    && ok "an out-of-range latitude and a misspelt step key are reported" || bad "validator misses bad fix / typo" "$V3"
  node "$VALIDATOR" --selftest >/dev/null 2>&1 && ok "validator selftest: every rule, the new ones included, watched going red" || bad "validator selftest" "$(node "$VALIDATOR" --selftest 2>&1 | grep FAIL | head -3)"
else
  echo "  skip — validator not found beside the runner"
fi

echo
echo "SCORE: $PASS/$((PASS+FAIL))"
[ "$FAIL" -eq 0 ]
