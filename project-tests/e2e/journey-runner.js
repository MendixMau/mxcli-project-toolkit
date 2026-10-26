'use strict';
// ============================================================================
// journey-runner.js — walk a persona down a golden path and check all four rungs
// ----------------------------------------------------------------------------
//   node tests/e2e/journey-runner.js journeys/FieldScan.journey.json
//   node tests/e2e/journey-runner.js journeys/*.journey.json --positive-control
//
// A suite PREFLIGHT runs before the browser opens (see "Suite preflight" below): admin
// credential + reachability, required env vars, live sessions. Exit 2 = aborted there.
// Env: TEST_USER / TEST_PASS (required; ALLOW_CONFIG_CREDENTIALS=1 to use the config
// default), M2EE_ADMIN_PASS / M2EE_ADMIN_PORT, ALLOW_NO_DATA_RUNG=1, JOURNEY_SESSION_CAP=<n>,
// ALLOW_SESSION_CAP=1, APP_PROBE=0 (no app probe between journeys). Journeys may declare
// requiresEnv / requires / leaves / consumes,
// resetsData (refused under --protect-state) and assertLanding (or --assert-landing).
//
// WHY THIS EXISTS
// The suite's 14 `TARGETS['full-app']` entries are independent PAGE STOPS: navigate,
// assert widgets present, count rows. Nothing in the corpus performs
// create → link → transition → verify-downstream with state carried between steps,
// which is the only shape that can answer the question the requirements actually ask:
// "does the user's journey, end to end, do what was specified?"
//
// FOUR RUNGS PER STEP, in this order, and the order matters:
//   1. LANDING GUARD  — did we actually arrive? A nav click that silently didn't
//      navigate leaves every later assertion measuring the PREVIOUS page and
//      screenshotting it under the new page's title. Assertions live only inside
//      the else branch. (testing-shape.md §4a)
//   2. ORDERED SPANS  — otel.assertSequence, not assertFired. Existence checks
//      cannot tell a skipped step from a reordered one.
//   3. DATA EFFECTS   — the row exists AND every association that must be set IS set.
//      An order created with no link to the unit it is for is a broken golden path
//      even though it saved, and every other rung goes green over it.
//   4. REQUIREMENT    — each finding carries its BRD pointer, so the report answers
//      "did we build what was decided", not just "did it work".
//
// A missing instrument is an INVALID RUN, never a PASS and never a FAIL. Jaeger down
// means the trace rung did not run; saying "passed" there is the exact false-green
// this harness was built to retire.
// ============================================================================

const fs = require('fs');
const path = require('path');
const H = require(__dirname + '/helpers.js');
const { settle } = require(__dirname + '/settle.js');
const O = require(__dirname + '/otel.js');
const { cfg } = require(__dirname + '/config.js');

const POSITIVE_CONTROL = process.argv.includes('--positive-control');
// --protect-state: refuse every journey tagged "resetsData": true (see preflight step 0b).
const PROTECT_STATE = process.argv.includes('--protect-state');
// --assert-landing (or any journey with "assertLanding": true): the landing check after login.
const ASSERT_LANDING = process.argv.includes('--assert-landing');
const files = process.argv.slice(2).filter(a => !a.startsWith('--'));
// --out=<file.json>: write findings there instead of the default slot. named-controls.js uses it
// so a named control never overwrites the real walk's (or the positive control's) findings (#159).
const OUT_ARG = (process.argv.find(a => a.startsWith('--out=')) || '').slice(6);
// Fix-loop reruns (#492): --only=<id,...> walks just those journeys; --rerun-failed[=<findings.json>]
// walks the journeys with any non-PASS row in the last run's findings (default: this mode's slot).
// Either way the journeys that `leave` what a chosen one `requires` are walked too, so declared
// state is rebuilt, and the findings go to a separate *-rerun.json slot: a partial run never
// replaces the full run's findings, and the full run is still owed where the test strategy names it.
const ONLY_ARG = (process.argv.find(a => a.startsWith('--only=')) || '').slice(7);
const RERUN_ARG = process.argv.find(a => a === '--rerun-failed' || a.startsWith('--rerun-failed='));
const PARTIAL = !!(ONLY_ARG || RERUN_ARG);
// `require.main === module` guard: tests/e2e/journey-rung4-scope.test.js requires this
// file to exercise the rung-4 SQL builders directly. Without the guard, requiring it
// would parse the TEST runner's argv, find no journey files and exit(3).
if (require.main === module && !files.length) {
  console.error('usage: node tests/e2e/journey-runner.js <journey.json...> [--positive-control] [--out=<file.json>]');
  process.exit(3);
}

// ── Verdicts ────────────────────────────────────────────────────────────────
// PASS / FAIL / INVALID are never collapsed. "The test could not run" and "the
// feature is broken" send you to different places, and blending them is how a
// week gets spent debugging a page that was never reached.
const results = [];
// The run's device (#521), written to the findings and to every walk.
let DEVICE = 'desktop (default 1440x900 window)';

// ── The walk ────────────────────────────────────────────────────────────────
// The assertions above answer "did it work". The walk answers "what did it DO" —
// which page, which button, what was typed, what the screen looked like at the
// moment each assertion was taken. It exists so a reviewer can follow the persona
// through the app and see the requirement being exercised, rather than reading a
// list of selectors and trusting it.
//
// A SCREENSHOT IS NOT AN ASSERTION, and this structure is built so it can never be
// mistaken for one. Every shot is attached to the checks that ran against that exact
// page state; the verdict always comes from the checks. The combobox off-by-one of
// 2026-08-14 is why: it committed "Seoul Gangnam Center" for "Seoul Gwanghwamun
// Center" — a real, valid, neighbouring row. The screenshot of that step looked
// perfect. Only the committed-value assertion caught it. Screenshots are for
// locating and understanding a failure, never for establishing one.
const walks = [];
// `evidenceStrength` is carried on the row AND folded into `detail`, deliberately.
// report-normalize.js reconciles emitted rows against declaredChecks() BY NAME, so the
// check names below must not change; and it copies `detail` verbatim into the rendered
// report while dropping fields it does not know. A strength that lives only in a new
// field would therefore be invisible in the artefact a human actually reads — which is
// the same "green cell that means less than it looks like" this rung exists to retire.
function record(rung, name, verdict, detail, req, evidenceStrength) {
  let text = String(detail ?? '');
  if (evidenceStrength === 'weak') text = text ? `${text}  [WEAK EVIDENCE]` : '[WEAK EVIDENCE]';
  const row = { rung, name, verdict, detail: text, requirement: req || '' };
  if (evidenceStrength) row.evidenceStrength = evidenceStrength;
  results.push(row);
  const mark = { PASS: '\x1b[32mPASS\x1b[0m', FAIL: '\x1b[31mFAIL\x1b[0m', INVALID: '\x1b[33mINVL\x1b[0m' }[verdict];
  console.log(`  ${mark} [${rung}] ${name}${text ? '  — ' + text : ''}`);
}
// Adapter so otel.js's reporter signature (name, ok, detail) can write into `record`.
const otelReporter = (req) => (name, ok, detail) =>
  record('trace', name, ok ? 'PASS' : 'FAIL', detail, req);

// ── Seeds: journey inputs come from the live DB, never hardcoded ────────────
// Test data drifts on every reseed. A journey pinned to 'SAM-NB-001' fails as
// "Receive is broken" the first time someone reseeds, which is a false FINDING —
// the mirror image of a false green and just as expensive.
//
// A seed that cannot be resolved is fatal to the journey: continuing with
// `undefined` in a scan field measures nothing and reports it as a feature bug.
function resolveSeeds(j) {
  const vars = {};
  for (const s of j.seeds || []) {
    // Seeds may reference earlier seeds ({{locId}}), so that a name and an id come
    // from the SAME row. Two independent `LIMIT 1` queries are not guaranteed to.
    const v = H.oqlScalar(subst(s.sql, vars));
    if (v === null || v === '') return { ok: false, missing: s.name, vars };
    vars[s.name] = String(v);
  }
  return { ok: true, vars };
}
const subst = (v, vars) =>
  typeof v === 'string' ? v.replace(/\{\{(\w+)\}\}/g, (m, k) => (k in vars ? vars[k] : m)) : v;

// ── Step actions ────────────────────────────────────────────────────────────
// A small, closed vocabulary addressed by Mendix widget name, not raw CSS — the
// convention the whole suite already uses, and the one that survives a re-render.
// Anything a journey cannot express with these belongs in a spec: the schema is
// meant to stay declarative enough to generate from a module brief's golden-path
// table.
const PAUSE = ms => new Promise(r => setTimeout(r, ms));
// Clock-skew margin for the liveness window (see runJourney's jt0).
const LIVENESS_SKEW_MS = 2000;
// The combobox waits below used to be fixed sleeps (400/1200/120/500 ms per field). Each now
// waits for the thing it was sleeping for; SETTLE_MODE=fixed keeps the old sleeps for an A/B run.
const FIXED = process.env.SETTLE_MODE === 'fixed';
const frames = page => page.evaluate(() => new Promise(r =>
  requestAnimationFrame(() => requestAnimationFrame(r)))).catch(() => {});

// A human-readable account of what the action WILL do, in the vocabulary a reviewer
// uses ("click Receive"), not the harness's (".mx-name-bReceive"). Both are kept: the
// sentence is for the person reading the walk, the selector for the person fixing it.
// One screenshot, recorded with the page's own title and URL so a reviewer can tell
// WHICH page they are looking at without decoding the selector. Returns null rather
// than throwing: a walk that loses its pictures is degraded, not invalid, and must
// never turn a real verdict into a harness failure.
async function shoot(page, name) {
  try {
    fs.mkdirSync(cfg.artifactsDir, { recursive: true });
    const file = path.join(cfg.artifactsDir, `${name}.png`);
    await page.screenshot({ path: file });
    return {
      file: path.relative(cfg.root, file),
      title: await page.title().catch(() => null),
      url: page.url(),
      at: new Date().toISOString(),
    };
  } catch { return null; }
}

function describeAct(a, vars) {
  const v = x => String(subst(x, vars));
  switch (a.do) {
    case 'nav':      return { verb: 'Navigate', target: [a.group, a.item].filter(Boolean).join(' › '), selector: null };
    case 'click':    return { verb: 'Click', target: (a.label || a.widget) + (a.row !== undefined ? ` in the row "${v(a.row)}"` : ''), selector: `.mx-name-${a.widget}` };
    case 'fill':     return { verb: 'Type', target: `"${v(a.value)}" into ${a.label || a.widget}`, selector: `.mx-name-${a.widget}` };
    case 'combobox': return { verb: 'Select', target: `"${v(a.match)}" in ${a.label || a.widget}`, selector: `.mx-name-${a.widget}` };
    case 'wait':     return { verb: 'Wait', target: `${a.ms || 0}ms`, selector: null };
    case 'back':     return { verb: 'Browser Back', target: '', selector: null };
    case 'offline':  return { verb: 'Go offline', target: 'browser network', selector: null };
    case 'online':   return { verb: 'Go online', target: 'browser network', selector: null };
    default:         return { verb: a.do, target: a.widget || '', selector: a.widget ? `.mx-name-${a.widget}` : null };
  }
}

async function act(page, a, vars, note) {
  const w = n => page.locator(`.mx-name-${n}`).first();
  // offline / online (#521) touch the browser context, never the page, and do not settle: a
  // settle waits on the network the step just cut.
  const net = networkVerb(a);
  if (net !== null) {
    if (a.do === 'wait')
      console.log(`    WARN legacy offline placeholder ("${a.label}") honoured — rewrite it as { "do": "${net ? 'offline' : 'online'}" }`);
    await setNetwork(page, net);
    return;
  }
  switch (a.do) {
    case 'nav':
      await H.navTo(page, a.group || null, a.item);
      break;
    case 'click': {
      const el = await scopedWidget(page, a, vars);
      await el.waitFor({ state: 'attached', timeout: 8000 }).catch(() => {});
      await el.scrollIntoViewIfNeeded({ timeout: 2000 }).catch(() => {});
      if (!(await H.visibleWithin(el, 6000)))
        throw new Error(`.mx-name-${a.widget} not visible`);
      // Hit-test before the forced click. `force` skips Playwright's actionability check, so a
      // click lands on whatever sits on top: a toast over the page's header actions swallowed
      // a click and the step read as "the action did nothing" two steps later (card-disbursement
      // build, row 5.6). A user's click lands there too, so a cover that outlasts an animation
      // (5 × 250 ms) is the finding, named by its class.
      let cover = null;
      for (let t = 0; t < 5; t++) {
        cover = await el.evaluate(n => {
          const r = n.getBoundingClientRect();
          const e = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2);
          if (!e || n.contains(e) || e.contains(n)) return null;
          const c = e.closest('[class]') || e;
          return String(c.className || c.tagName).trim().split(/\s+/).slice(0, 3).join('.');
        }).catch(() => null);
        if (!cover) break;
        await PAUSE(250);
      }
      if (cover)
        throw new Error(`.mx-name-${a.widget} is covered by .${cover} — a click lands on that, not on the widget`);
      await el.click({ force: true }).catch(() => el.click());
      break;
    }
    case 'fill': {
      const el = page.locator(`.mx-name-${a.widget} input, .mx-name-${a.widget} textarea`).first();
      if (!(await H.visibleWithin(el, 6000)))
        throw new Error(`.mx-name-${a.widget} input not visible`);
      await el.fill(String(subst(a.value, vars)));
      break;
    }
    case 'combobox': {
      // Atlas pluggable comboboxes are Downshift-backed: options render
      // position:fixed OUTSIDE the widget container, so a locator scoped to
      // .mx-name-<widget> finds nothing and a plain fill() does not commit a
      // selection. Toggle, then keyboard-select — the technique proven in
      // spec-fieldscan-otel.js.
      const box = w(a.widget);
      if (!(await H.visibleWithin(box, 6000)))
        throw new Error(`.mx-name-${a.widget} not visible`);
      await box.scrollIntoViewIfNeeded().catch(() => {});
      if (FIXED) await PAUSE(400); else await frames(page);
      // The toggle is INSIDE the widget (only the menu renders outside it). It used to be
      // looked up page-wide with .first(), which opened the page's FIRST combobox whatever
      // `widget` said: on a form with three comboboxes every step read the first one's menu
      // and failed "no option matches" (field run 2026-10-07, existing app).
      await box.locator('[id^="downshift-"][id$="-toggle-button"]').first()
                .click({ force: true }).catch(() => {});
      if (FIXED) await PAUSE(1200);
      const opts = page.locator('[role="option"]');
      await opts.first().waitFor({ state: 'visible', timeout: 5000 }).catch(() => {});
      // options can arrive in batches (async datasource): wait until the list stops growing
      if (!FIXED) await settle(page, { timeout: 3000, stableMs: 200, minMs: 0, networkIdleMs: 0 });
      const texts = await opts.evaluateAll(e => e.map(x => x.textContent.trim())).catch(() => []);
      const want = String(subst(a.match, vars));
      const idx = texts.findIndex(t => t.includes(want));

      // CONFIRMED FALSE GREEN, 2026-08-14 — this line used to read `if (idx === -1)
      // idx = 0;`. The seed asked for "Seoul Gwanghwamun Center", the option was not
      // in the list, and the journey silently selected whatever sat at position 0
      // ("Seoul Gangnam Center") and reported PASS. Every downstream rung then agreed
      // with it: the placement saved, both associations were non-null, assocGap was 0.
      // `assocMustBeSet` verifies that a link EXISTS — never that it points where the
      // journey intended — so the wrong-location run is indistinguishable from a
      // correct one on every instrument the harness had.
      //
      // A fallback that quietly substitutes a different input is not resilience. It
      // makes the journey measure something nobody asked for and call it the thing
      // they did ask for. If the seeded option is absent, that is the finding.
      if (idx === -1) {
        throw new Error(
          `${a.widget}: no option matches "${want}" — the seeded value is not selectable. ` +
          `Options were: ${texts.slice(0, 8).map(t => `"${t}"`).join(', ')}` +
          (texts.length > 8 ? ` (+${texts.length - 8} more)` : ''));
      }
      // MEASURED 2026-08-14, two failed approaches before this one. Both computed
      // where to land instead of checking where they had landed:
      //
      //   1. `idx + 1` ArrowDown presses, then Enter. Landed one option SHORT —
      //      asked for "Seoul Gwanghwamun Center", committed "Seoul Gangnam Center".
      //      Downshift's highlight index is not the same coordinate system as the
      //      DOM array index, so the press count and `idx` never had to agree.
      //   2. `opts.nth(idx).click({force:true})`. Closed the menu and committed
      //      NOTHING — Downshift does not treat a synthetic forced click as a select.
      //
      // Approach 1's failure is the dangerous one: an off-by-one lands on a REAL,
      // VALID neighbouring row, so nothing downstream looks wrong. Approach 2 at
      // least failed loudly.
      //
      // So: step the highlight and READ IT each time, committing only once the
      // highlighted option is the one asked for. Self-correcting whatever index
      // Downshift starts from, and it cannot commit a neighbour by construction.
      const activeText = async () => {
        const id = await box.locator('input[role="combobox"]')
                            .getAttribute('aria-activedescendant').catch(() => null);
        if (!id) return null;
        // Attribute selector, not `#id` — Downshift ids contain hyphens and digits
        // that a bare CSS id selector mis-parses, and `CSS.escape` is a BROWSER API
        // that is undefined here in Node (it threw "CSS is not defined" on the first
        // attempt, and the runner correctly reported that as a FAIL of the step
        // rather than skipping the assertion).
        return page.locator(`[id="${id}"]`).textContent().catch(() => null);
      };
      let landed = false;
      for (let k = 0; k < texts.length + 2; k++) {
        const cur = (await activeText() || '').trim();
        if (cur && cur.includes(want)) { landed = true; break; }
        await page.keyboard.press('ArrowDown');
        if (FIXED) await PAUSE(120); else await frames(page);
      }
      if (!landed) {
        throw new Error(
          `${a.widget}: stepped the whole menu without the highlight ever reaching ` +
          `"${want}". The option is listed but not reachable by keyboard.`);
      }
      await page.keyboard.press('Enter');
      if (FIXED) await PAUSE(500);
      else await settle(page, { timeout: 3000, stableMs: 150, minMs: 0, networkIdleMs: 0 });

      // Selecting is not committing. Downshift can close the menu without writing the
      // value back, so the committed input is read and compared to the seed — not
      // merely checked for non-emptiness, which the previous version did and which
      // any wrong value passes.
      const val = await box.locator('input[role="combobox"]').inputValue().catch(() => '');
      if (!val) throw new Error(`${a.widget} still empty after selecting "${want}"`);
      if (!val.includes(want)) {
        throw new Error(
          `${a.widget} committed "${val}" but the journey asked for "${want}" — ` +
          'the selection did not take. Every later assertion would be about the wrong row.');
      }
      note('ui', `combobox ${a.widget} committed the seeded value`, 'PASS', val);
      break;
    }
    case 'dismissModal': await H.dismissModal(page); break;
    case 'wait':         await page.waitForTimeout(a.ms || 1000); break;
    case 'back': {
      // Browser Back (#564): the Mendix client rebuilds the previous page from its own history and
      // re-sends the client state it kept — a path no in-app click takes. A networkidle timeout is
      // not a failure (a polling page never goes idle; the history move happened). Leaving the app
      // is: every later check would measure the login page or another site.
      const ms = a.timeout || 15000;
      await page.goBack({ waitUntil: 'networkidle', timeout: ms }).catch(e => {
        if (!/timeout/i.test(e.message)) throw e;
        console.log(`    WARN back: networkidle not reached in ${ms} ms; settling as usual`);
      });
      if (backLeftApp(page.url(), cfg.baseUrl))
        throw new Error(`Back left the app (now at ${page.url()}): the previous action pushed no history entry`);
      break;
    }
    default: throw new Error(`unknown action "${a.do}"`);
  }
  // An explicit settleMs is a fixed wait, as before. Otherwise wait for the page to
  // finish (settle.js) rather than 1200 ms after every action; SETTLE_MODE=fixed
  // restores the old 1200 ms for an A/B run.
  if (a.settleMs != null) await page.waitForTimeout(a.settleMs);
  else await settle(page, { timeout: 10000, stableMs: 300, networkIdleMs: 0, fallbackMs: 1200 });
}

// A grid repeats one widget name per row, so `.mx-name-<w>` first-match clicks whichever row
// rendered first (#148). `in` scopes to one container widget; `row` (substituted) picks the one
// innermost row that shows the text as a whole word run: "Order 1" never matches "Order 10". The
// row's own text and each element in it are tested, so cells rendered with no whitespace between
// them (React grids) still match. No row → throw; two or more → throw "ambiguous", never a pick.
// Neither field → the old first-match locator, unchanged.
const ROW_SEL = ':is(tr, [role="row"], .mx-listview-item, .mx-templategrid-item)';
async function scopedWidget(page, a, vars = {}) {
  let base = page;
  if (a.in) base = page.locator(`.mx-name-${a.in}`).first();
  if (a.row !== undefined) {
    const text = String(subst(a.row, vars));
    const rows = base.locator(ROW_SEL);
    const hits = await rows.evaluateAll((els, t) => {
      const esc = t.replace(/\s+/g, ' ').trim().replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      const re = new RegExp(`(?:^|[^\\p{L}\\p{N}])${esc}(?:[^\\p{L}\\p{N}]|$)`, 'u');
      const says = e => [e, ...e.querySelectorAll('*')]
        .some(n => re.test(String(n.innerText != null && n.innerText !== '' ? n.innerText : n.textContent || '').replace(/\s+/g, ' ').trim()));
      const m = els.filter(says);
      return els.map((e, i) => (m.includes(e) && !m.some(o => o !== e && e.contains(o))) ? i : -1).filter(i => i >= 0);
    }, text).catch(() => []);
    const where = a.in ? ` in .mx-name-${a.in}` : '';
    if (!hits.length) throw new Error(`no row${where} says "${text}"`);
    if (hits.length > 1) throw new Error(`ambiguous: ${hits.length} rows${where} say "${text}"`);
    base = rows.nth(hits[0]);
  }
  return base === page ? page.locator(`.mx-name-${a.widget}`).first() : base.locator(`.mx-name-${a.widget}`).first();
}

// Outside the app after a Back: another origin, about:blank, or the login page (monkey.js leftApp).
function backLeftApp(url, baseUrl) {
  const base = String(baseUrl).replace(/\/+$/, '');
  if (!url || (url !== base && !url.startsWith(base + '/'))) return true;
  return /\/login\.html(?:[?#]|$)/.test(url);
}

// The opt-in `ui.no5xx` row (#564): every answer >= 500 between the step's first action and its
// landing guard. Mendix can render a page's frame while every data source on it failed (HTTP 560
// on /xas/), and the landing guard alone then reads PASS.
function no5xxVerdict(hits) {
  return hits.length
    ? { verdict: 'FAIL', detail: `${hits.length} answer(s) >= 500: ${hits.slice(0, 5).join('; ')}${hits.length > 5 ? '; …' : ''}` }
    : { verdict: 'PASS', detail: 'no answer >= 500' };
}

// ── Device, network and position (#521) ─────────────────────────────────────
// Every journey used to open in one 1440x900 desktop window, so Mendix served the Responsive
// profile and a phone journey failed at step 1 for a setup reason; an "offline" step was a
// labelled `wait` that never left the network; a nanoflow reading the device position got
// "permission denied". All three are opt-in journey fields; a journey with none of them goes
// through H.launchBrowser() exactly as before.
//
// One run is one browser context and one sign-in, so one run is one device: a run whose
// journeys need different devices exits 2 before the browser opens (one SETUP line per
// device). JOURNEY_DEVICE=<Playwright name>|desktop applies one device to every journey.
const DEFAULT_PHONE = 'iPhone 13';
const validSize = v => v && Number.isInteger(v.width) && Number.isInteger(v.height) && v.width > 0 && v.height > 0;
function editDistance(a, b) {
  a = a.toLowerCase(); b = b.toLowerCase();
  const d = Array.from({ length: a.length + 1 }, (_, i) => [i]);
  for (let j = 1; j <= b.length; j++) d[0][j] = j;
  for (let i = 1; i <= a.length; i++) for (let j = 1; j <= b.length; j++)
    d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
  return d[a.length][b.length];
}
// `profiles` is Playwright's `devices` map (H.deviceProfiles()); injected so the selftest needs
// no browser. Returns { kind, key, options } or { error }. `options` null = the desktop default.
function resolveDevice(j, { env = process.env, profiles = null } = {}) {
  const id = j.id || '(journey)';
  const named = (name, size, src) => {
    if (!profiles) return { error: `${id}: ${src} "${name}" needs Playwright's device profiles, and Playwright did not load` };
    const p = profiles[name];
    if (!p) {
      const near = Object.keys(profiles).sort((x, y) => editDistance(name, x) - editDistance(name, y)).slice(0, 3);
      return { error: `${id}: unknown device "${name}" (${src}) — nearest known: ${near.join(', ')}. ` +
        'The runner never swaps in a neighbouring profile.' };
    }
    if (size != null && !validSize(size)) return { error: `${id}: ${src} viewport must be { "width", "height" } in whole pixels` };
    // The size: an explicit viewport, else the profile's screen (390x844 for iPhone 13) — its
    // `viewport` is the browser chrome-reduced 390x664, not the size the app is laid out for.
    const vp = size ? { width: size.width, height: size.height } : (p.screen || p.viewport);
    return { kind: p.isMobile ? 'phone' : 'desktop', key: `${name} ${vp.width}x${vp.height}`, name,
      options: { userAgent: p.userAgent, isMobile: !!p.isMobile, hasTouch: !!p.hasTouch,
                 deviceScaleFactor: p.deviceScaleFactor || 1, viewport: vp } };
  };
  const over = env.JOURNEY_DEVICE;
  if (over) return /^desktop$/i.test(over) ? { kind: 'desktop', key: 'desktop', options: null } : named(over, null, 'JOURNEY_DEVICE');
  const d = j.device;
  if (d !== undefined) {
    if (typeof d === 'string') return named(d, null, 'device');
    if (d && typeof d === 'object' && typeof d.name === 'string') return named(d.name, d.viewport, 'device');
    return { error: `${id}: "device" must be a Playwright device name or { "name", "viewport": { "width", "height" } }` };
  }
  const v = j.viewport;
  if (v !== undefined) {
    if (!validSize(v)) return { error: `${id}: "viewport" must be { "width", "height" } in whole pixels` };
    if (v.isMobile === true) {
      const base = named(DEFAULT_PHONE, v, 'viewport (isMobile)');
      return base.error ? base : { ...base, key: `phone ${v.width}x${v.height}` };
    }
    return { kind: 'desktop', key: `desktop ${v.width}x${v.height}`, options: { viewport: { width: v.width, height: v.height } } };
  }
  return { kind: 'desktop', key: 'desktop', options: null };
}
// One device for the whole run, or the SETUP problems that stop it before the browser opens.
function runDevice(journeys, opts = {}) {
  const problems = [], byKey = new Map();
  let device = null;
  for (const j of journeys) {
    const r = resolveDevice(j, opts);
    if (r.error) { problems.push(r.error); continue; }
    if (!byKey.has(r.key)) byKey.set(r.key, []);
    byKey.get(r.key).push(j.id);
    device = device || r;
  }
  if (byKey.size > 1)
    problems.push('one run is one browser context, so one device — these journeys need different ones: ' +
      [...byKey].map(([k, ids]) => `${k}: ${ids.join(', ')}`).join('; ') + '. Run each group separately.');
  return { device: device || { kind: 'desktop', key: 'desktop', options: null }, problems };
}
const contextOptions = dev => (dev && dev.options) || null;
const deviceLabel = dev => (dev && dev.options ? dev.key : 'desktop (default 1440x900 window)');
// The device as the page measures it on about:blank, judged against what was asked for. A
// phone journey run in a desktop context measures the wrong app (Mendix picks its profile from
// the user agent and size), so a mismatch stops the run before any sign-in.
function judgeDevice(dev, m) {
  const o = contextOptions(dev);
  if (!o) return { ok: true, detail: '' };
  const bad = [];
  if (o.viewport && (m.width !== o.viewport.width || m.height !== o.viewport.height))
    bad.push(`viewport ${m.width}x${m.height}, asked ${o.viewport.width}x${o.viewport.height}`);
  if (o.userAgent && m.ua !== o.userAgent) bad.push(`user agent "${String(m.ua).slice(0, 60)}…" is not the profile's`);
  if (o.hasTouch && !(m.touch > 0)) bad.push('no touch points on a touch device');
  return bad.length ? { ok: false, detail: bad.join('; ') } : { ok: true, detail: '' };
}
async function measureDevice(page) {
  const vp = page.viewportSize() || {};
  const e = await page.evaluate(() => ({ ua: navigator.userAgent, touch: navigator.maxTouchPoints })).catch(() => ({}));
  return { width: vp.width, height: vp.height, ua: e.ua, touch: e.touch };
}

// The ::before / ::after text of every rendered element (#276). `content` comes back as a CSS
// string ('"No placements yet"'); quotes and escapes are undone. Hidden elements are skipped: a
// pseudo-element on a display:none host is not on the screen.
async function pseudoTexts(page) {
  return page.evaluate(() => {
    const out = [];
    for (const el of document.querySelectorAll('body *')) {
      if (!el.getClientRects().length) continue;
      for (const pe of ['::before', '::after']) {
        const c = getComputedStyle(el, pe).content;
        if (!c || c === 'none' || c === 'normal') continue;
        const m = /^"((?:[^"\\]|\\.)*)"$/.exec(c);
        if (m) out.push(m[1].replace(/\\(.)/g, '$1'));
      }
    }
    return out;
  }).catch(() => null);
}
function pseudoVerdict(texts, want) {
  if (texts === null) return { verdict: 'INVALID', detail: 'could not read pseudo-element content (page gone?)' };
  return texts.some(t => t.includes(want))
    ? { verdict: 'PASS', detail: '' }
    : { verdict: 'FAIL', detail: `no rendered ::before/::after says it (${texts.length} with text${texts.length ? `: ${texts.slice(0, 3).map(t => JSON.stringify(t)).join(', ')}` : ''})` };
}

// offline / online. A `wait` whose label names context.setOffline(true|false) is the
// placeholder projects wrote before the verbs existed; it is honoured, with a WARN.
const NET = { offline: false };
function networkVerb(a) {
  if (!a) return null;
  if (a.do === 'offline') return true;
  if (a.do === 'online') return false;
  if (a.do === 'wait' && typeof a.label === 'string') {
    const m = /context\.setOffline\((true|false)\)/.exec(a.label);
    if (m) return m[1] === 'true';
  }
  return null;
}
async function setNetwork(page, offline) { await page.context().setOffline(offline); NET.offline = offline; }
const isOffline = () => NET.offline;
// Back online, always: after every journey and before the sign-out (an offline logout never
// reaches /xas/ and leaks a licence session). Returns whether it was offline.
async function ensureOnline(page) {
  if (!NET.offline) return false;
  await setNetwork(page, false);
  return true;
}
// A journey that walked every step and was still offline never declared its way back: the
// runner restored it, and the contract is wrong. Not walked to the end → the bail-out is the finding.
function networkEndRow(id, wasOffline, completed) {
  if (!wasOffline || !completed) return null;
  return { name: `${id}: back online at the end`, verdict: 'INVALID',
    detail: 'walked every step still offline — no { "do": "online" } step; the runner put it back online. Add the step.' };
}

// A GPS fix: `geolocation` { latitude, longitude, accuracy? } on a step or on the journey (from
// its first step on); {{seed}} placeholders allowed. `_geolocation` (files written before the
// runner read the field) is used when `geolocation` is absent, with a WARN: the validator treats
// `_` keys as comments and never checks their placeholders. A value that is not a number, out of
// range, or still a {{placeholder}} is INVALID and stops the journey; it is never sent as 0,0.
function resolveGeolocation(spec, vars = {}) {
  if (!spec || typeof spec !== 'object') return { ok: false, why: 'must be { "latitude", "longitude", "accuracy"? }' };
  const out = {};
  for (const [k, lo, hi, req] of [['latitude', -90, 90, true], ['longitude', -180, 180, true], ['accuracy', 0, Infinity, false]]) {
    let v = spec[k];
    if (v === undefined) { if (req) return { ok: false, why: `no ${k}` }; continue; }
    v = subst(v, vars);
    if (typeof v === 'string' && /\{\{\w+\}\}/.test(v)) return { ok: false, why: `${k} "${v}" is an unresolved placeholder` };
    if (typeof v === 'string' && !v.trim()) return { ok: false, why: `${k} is empty` };
    const n = Number(v);
    if (!Number.isFinite(n) || n < lo || n > hi) return { ok: false, why: `${k} ${JSON.stringify(v)} is not a number in [${lo}, ${hi}]` };
    out[k] = n;
  }
  return { ok: true, value: out };
}
const GEO = { granted: false };
async function applyGeolocation(page, value) {
  if (!GEO.granted) { await page.context().grantPermissions(['geolocation']); GEO.granted = true; }
  await page.context().setGeolocation(value);
}
// Between journeys: permission and position are cleared, so a fix never leaks into the next one.
async function clearGeolocation(page) {
  if (!GEO.granted) return;
  await page.context().clearPermissions();
  await page.context().setGeolocation(null).catch(() => {});
  GEO.granted = false;
}
// The step's fix: its own, else (first step only) the journey's. Returns { spec, legacy } or null.
function stepGeolocation(j, step, i) {
  if (step.geolocation !== undefined) return { spec: step.geolocation, legacy: false };
  if (step._geolocation !== undefined) return { spec: step._geolocation, legacy: true };
  if (i === 0 && j.geolocation !== undefined) return { spec: j.geolocation, legacy: false };
  if (i === 0 && j._geolocation !== undefined) return { spec: j._geolocation, legacy: true };
  return null;
}

// ── RUNG 2: ordered spans, as a function (called from runJourney) ───────────
// Runs for a positive claim (ordered) OR a negative-only claim (mustNotFire with ordered
// empty/absent) — a step whose whole proof is "this did NOT run" (#150). `capture` and
// `live` are injected so tests/wave2/test-journey-liveness.sh drives it with a
// captured Jaeger trace and no browser. `rec(name, verdict, detail)` records one row.
//
// NEGATIVE-ONLY NEEDS A LIVENESS REFERENCE. Zero spans in the step window is what a correct
// Cancel looks like AND what Jaeger down / OTel off looks like. Before 2026-10-13 that was
// INVALID "Jaeger down or OTel off" for both, so the claim could never pass; the opposite
// fix (zero spans → PASS) would pass with tracing dead. So: wait the full capture window
// (there is nothing to `until` on), then require evidence the pipeline was delivering —
// the step's declared `spans.liveness` span, or any span from the service since the
// journey began (otel.js liveness). No evidence → INVALID, naming which.
async function traceRung(step, { t0, since, rec, capture = null, live = O.liveness }) {
  if (!step.spans) return;
  // A spans block that declares nothing this rung reads reads as a trace claim in the journey
  // file and proves nothing — said out loud, never skipped (#150 item 3). The array shape
  // [{ mf, status }] is the old example.journey.json shape, named as such.
  const shape = Array.isArray(step.spans) ? 'array'
    : typeof step.spans !== 'object' ? typeof step.spans : 'object';
  const claimed = (shape === 'object' && Array.isArray(step.spans.ordered)) ? step.spans.ordered : [];
  const mustNot = (shape === 'object' && Array.isArray(step.spans.mustNotFire)) ? step.spans.mustNotFire : [];
  if (!claimed.length && !mustNot.length) {
    const why = shape === 'array'
      ? 'spans is an array — the old shape [{ mf, status }], which the runner never read; use { "ordered": [...], "mustNotFire": [...] }'
      : shape !== 'object'
        ? `spans is a ${shape} — use { "ordered": [...], "mustNotFire": [...] }`
        : !Object.keys(step.spans).length
          ? 'spans is {} — declares neither `ordered` nor `mustNotFire`'
          : 'spans block declares neither `ordered` nor `mustNotFire`';
    rec(`${step.name}: spans`, 'INVALID',
        `${why} — nothing to evaluate; trace rung did NOT run. Declare the claim or remove the block.`);
    return;
  }
  const negOnly = !claimed.length;
  const probe = (step.spans && step.spans.liveness) || null;
  const has = (sp, n) => O.microflowNames(sp).includes(n) || sp.some(x => x.op === n);
  // Wait for the claimed microflows, not just any span — see otel.js capture() `until`.
  const until = !negOnly ? sp => claimed.every(n => O.microflowNames(sp).includes(n))
    : probe ? sp => has(sp, probe) : () => false;
  let spans = capture ? await capture(t0, { min: 1, until })
                      : await O.capture(t0, { min: 1, until: until });
  const real = spans.length;
  if (negOnly && (!real || probe)) {
    // A project whose otel.js was hand-edited keeps it across a sync (it is not in the hold
    // set with this file), so a new runner can meet an otel.js older than liveness(). Say so,
    // never TypeError.
    if (typeof live !== 'function') {
      rec(`${step.name}: spans`, 'INVALID',
          'negative-only claim needs otel.js liveness(), which this project\'s tests/e2e/otel.js does not export — ' +
          'it is older than journey-runner.js (a locally edited copy kept by sync). Merge the toolkit\'s otel.js. ' +
          'Trace rung did NOT run.');
      return;
    }
    const lv = await live(since, { name: probe, spans });
    if (!lv.ok) {
      rec(`${step.name}: spans`, 'INVALID',
          `negative-only claim (${mustNot.join(', ')} must not run) with no liveness evidence: ${lv.detail}. ` +
          '"Nothing ran" and "tracing is off" look the same here — trace rung did NOT run.');
      return;
    }
    rec(`${step.name}: tracing live`, 'PASS', lv.detail);
  } else if (!real) {
    rec(`${step.name}: spans`, 'INVALID',
        'zero spans captured — Jaeger down or OTel off. Trace rung did NOT run.');
    return;
  }
  // Positive control only (controlMutants' trace-negative branch for a negative-only claim):
  // the forbidden microflow is injected into the capture AFTER the liveness verdict, so the
  // mutant proves assertNotFired can go red without being able to vouch for a dead pipeline.
  const inject = (step.spans && step.spans._controlInjectFired) || [];
  if (inject.length) spans = spans.concat(inject.map(n => ({ op: n, start: Date.now() * 1000, dur: 0,
    traceID: 'positive-control', tags: { 'mx.microflow.name': n }, logs: [] })));
  const rep = (name, ok, detail) => rec(name, ok ? 'PASS' : 'FAIL', detail);
  if (real) {
    O.guard(spans, rep, `${step.name}: capture non-empty`);
    if (claimed.length) O.assertSequence(spans, claimed, rep, `${step.name}: ordered`);
    O.assertNoErrors(spans, rep, `${step.name}: no ERROR at any level`);
  }
  for (const n of mustNot) O.assertNotFired(spans, new RegExp(n), rep, `${step.name}: ${n} did not run`);
}

// ── Rung 3 helpers ──────────────────────────────────────────────────────────
// oql() swallows every error and returns null, so null must mean "no measurement",
// never "zero". A count assertion that treats null as 0 passes when the instrument
// is dead — the same failure mode as an empty span capture.
function count(sql) {
  const v = H.oqlScalar(sql);
  return v === null ? null : Number(v);
}

// A declared OQL expectation. `expect` is exact, `atLeast` is a floor — the floor
// exists because seeded data carries history, so "this item now has a placement" is
// the honest claim while "exactly one" would be a lie about the fixture.
//
// A query with NEITHER is a check that cannot fail, so it is reported as INVALID
// rather than PASS. A green cell that could never have been red is decoration, and
// this whole harness exists because the corpus is full of them.
function checkOql(q, vars) {
  const v = H.oqlScalar(subst(q.sql, vars));
  if (v === null) return { verdict: 'INVALID', detail: 'OQL returned nothing — admin API unreachable or query rejected' };
  if (q.expect !== undefined)
    return { verdict: String(q.expect) === v ? 'PASS' : 'FAIL', detail: `got ${v}, expected ${q.expect}` };
  if (q.atLeast !== undefined)
    return { verdict: Number(v) >= Number(q.atLeast) ? 'PASS' : 'FAIL', detail: `got ${v}, need >= ${q.atLeast}` };
  return { verdict: 'INVALID', detail: `got ${v}, but no expect/atLeast declared — this check cannot fail` };
}

// ── Rung 4 row scoping: which rows is this step allowed to be judged on? ────
//
// THE DEFECT THIS REPLACES (both directions, on the same two checks):
//
//   assocMustBeSet ran `SELECT COUNT(*) FROM Entity` against `... INNER JOIN` over the
//   WHOLE TABLE. One legacy row with a null FK — seeded years of runs ago, nothing to do
//   with this journey — makes the gap non-zero forever. The step is reported as "saved
//   without its association" on every future run, for a row it never touched. A standing
//   red that no fix can clear teaches the reader to ignore the cell.
//
//   mustPointAt ran `... WHERE t.<attr> = '<seed>'` over the WHOLE TABLE and passed on
//   `n >= 1`. A row a PREVIOUS run wrote already satisfies it. So the check goes green
//   whether or not this journey did anything at all — including when the commit silently
//   no-ops. It is the check added to catch the 2026-08-14 wrong-combobox run, and as
//   written it could be satisfied by that very run's leftover row.
//
// Opposite verdicts, one cause: neither query could distinguish the rows THIS STEP wrote
// from everything else in the table.
//
// THE FIX — a DB-sourced high-water mark taken immediately before the step's actions.
// The step declares `data.scope.newRowsBy: "<attr>"`; the runner reads
// `SELECT MAX(<attr>) FROM <entity>` first, then scopes both checks to `e.<attr> > <mark>`.
//
// Why MAX() from the database and not the runner's clock: it removes clock skew from the
// question entirely. A `createdDate > <runner's Date.now()>` scope compares a timestamp
// written by the runtime (in its container, on its clock) against one read in Node on the
// host, and a container running even 2s behind silently scopes out the row the journey
// just wrote — a false FAIL that looks exactly like a broken commit. A watermark read out
// of the same database that will answer the assertion has no second clock in it.
//
// Why `id` is the recommended attribute — verified, not assumed, against
// .ai-context/skills/demo-data.md:87, which gives the Mendix object-ID layout as
//   id = (short_id << 48) | (sequence_number << 7) | random_7bits
// short_id is constant per entity, so within one entity ordering by id is ordering by
// sequence_number, and sequence_number is allocated strictly increasing (demo-data.md:122,
// "object_sequence is the next available sequence number for that entity"). The 7-bit
// random suffix sits BELOW the sequence field, so it cannot reorder two rows: consecutive
// sequences differ by 128 while the suffix can only vary by at most 127. Monotonic by
// construction, and immune to an UPDATE — unlike a stamped DateTime.
//
// `newRowsBy: "PlacedOn"` (or any stamped DateTime) also works and is the fallback if the
// runtime's OQL will not aggregate `id`, with one documented weakness: FieldScan's Move
// RE-STAMPS PlacedOn (mdlsource/fieldscan/04-microflows.mdl:165), so a pre-existing row
// that some other actor moves during the step re-enters scope. `id` cannot do that.
//
// A declared scope that cannot be measured is INVALID, never a quiet fall back to the
// whole table. Falling back would restore precisely the two false verdicts above while
// the report still showed the scoped wording.
function sqlRowCount(entity) { return `SELECT COUNT(*) AS n FROM ${entity}`; }
function sqlWatermark(entity, attr) { return `SELECT MAX(${attr}) AS w FROM ${entity}`; }

// Numeric marks (ids) go in bare; anything else (a DateTime) is quoted. Decided from the
// value the database returned, not from a hardcoded attribute-name list, so a journey can
// scope on any monotonic column without the runner knowing its type.
const scopeLiteral = (w) => (/^-?\d+$/.test(String(w)) ? String(w) : `'${w}'`);

// The WHERE tail shared by both scoped checks. `extra` (e.g. `t.LocId = 'L1'`) comes
// first so the generated SQL reads in the order a human would write it.
function whereScoped(sc, alias, extra) {
  const terms = [];
  if (extra) terms.push(extra);
  if (sc && sc.state === 'scoped') terms.push(`${alias}.${sc.attr} > ${scopeLiteral(sc.watermark)}`);
  return terms.length ? ` WHERE ${terms.join(' AND ')}` : '';
}

function sqlAssocTotal(entity, sc) {
  return `SELECT COUNT(*) AS n FROM ${entity} AS e${whereScoped(sc, 'e')}`;
}
function sqlAssocLinked(entity, assoc, target, sc) {
  return `SELECT COUNT(*) AS n FROM ${entity} AS e ` +
         `INNER JOIN e/${assoc}/${target} AS t${whereScoped(sc, 'e')}`;
}
function sqlMustPointAt(entity, assoc, target, attr, want, sc) {
  return `SELECT COUNT(*) AS n FROM ${entity} AS e ` +
         `INNER JOIN e/${assoc}/${target} AS t${whereScoped(sc, 'e', `t.${attr} = '${want}'`)}`;
}

// Read the high-water mark. Four outcomes, kept distinct because they mean different
// things to the reader:
//   unscoped — the journey declared no scope. Legacy contract; still runs, reported WEAK.
//   empty    — the table held no rows, so "rows this step wrote" is "all rows". No WHERE
//              needed and the evidence is STRONG: nothing older exists to be confused with.
//   scoped   — a mark was read; both checks are restricted to rows above it.
//   broken   — the table is non-empty but MAX() came back with nothing. The instrument
//              did not run; the checks that depend on it are INVALID.
function captureScope(entity, decl, countFn, scalarFn) {
  const c = countFn || count;
  const s = scalarFn || H.oqlScalar;
  if (!decl || !decl.newRowsBy) return { state: 'unscoped', entity };
  const attr = decl.newRowsBy;
  const n = c(sqlRowCount(entity));
  if (n === null)
    return { state: 'broken', entity, attr,
             reason: `row count for ${entity} returned nothing — admin API unreachable` };
  if (n === 0) return { state: 'empty', entity, attr };
  const w = s(sqlWatermark(entity, attr));
  if (w === null || w === '')
    return { state: 'broken', entity, attr,
             reason: `SELECT MAX(${attr}) FROM ${entity} returned nothing although the table ` +
                     `holds ${n} row(s) — this runtime's OQL will not aggregate "${attr}". ` +
                     `Declare a different data.scope.newRowsBy (e.g. a stamped DateTime).` };
  return { state: 'scoped', entity, attr, watermark: String(w), rowsBefore: n };
}

// How much a green cell from this scope is worth, in the report's own vocabulary.
function scopeEvidence(sc) {
  if (!sc || sc.state === 'unscoped')
    return { strength: 'weak',
             tag: 'unscoped: judged over the WHOLE table, so a row from an earlier run can ' +
                  'satisfy it and a legacy row can break it — declare data.scope.newRowsBy' };
  if (sc.state === 'empty')
    return { strength: 'strong', tag: `${sc.entity} was empty before this step, so every row is this step's` };
  return { strength: 'strong', tag: `scoped to rows with ${sc.attr} > ${sc.watermark}` };
}

// "Association set" is measured as: rows reachable through the association vs rows
// total. An INNER JOIN drops rows whose foreign key is null, so the difference is
// exactly the number of records that saved without their link — now counted only over
// the rows this step is answerable for.
function assocGap(entity, assoc, target, sc) {
  const total = count(sqlAssocTotal(entity, sc));
  const linked = count(sqlAssocLinked(entity, assoc, target, sc));
  if (total === null || linked === null) return null;
  return { total, linked, gap: total - linked };
}

// ── One journey ─────────────────────────────────────────────────────────────
// ── Positive controls: one deliberately broken precondition per rung ────────
// Each mutant returns the journey to run, which rung it challenges, and a predicate
// naming the check that MUST catch it. A mutant is only useful if the journey
// actually declares the thing being broken — `mustPointAt` cannot be proven on a
// journey that has none.
//
// UNSUPPORTED IS NOT ABSENT. Until 2026-08-21 `add` returned early and pushed no
// record at all when a journey could not express a mutant, and nothing anywhere
// carried a denominator: a run that proved 4 of the 7 rungs printed identically to
// one that proved all 7. journey-proof.md:128 has always said the opposite —
// "a rung with no mutant is UNPROVEN, which is fault, never pass" — so the skipped
// rungs were being silently counted as though the control run had vouched for them.
// An unsupported mutant now emits a record with supported:false, and the run loop
// turns that into INVALID (the instrument did not run), never PASS.
const CONTROL_RUNGS = [
  'ui-landing', 'ui-text', 'trace-order', 'trace-negative',
  'data-delta', 'data-target', 'outcome',
];

// A microflow name the mustNotFire pattern matches: the pattern itself when it matches its
// own text (the usual bare name, `Mod.ACT_X`), else the pattern with anchors and escapes
// stripped; null when neither matches (the mutant is then reported unsupported, not faked).
function forbiddenSample(pattern) {
  let re;
  try { re = new RegExp(pattern); } catch (_) { return null; }
  if (re.test(pattern)) return pattern;
  const plain = String(pattern).replace(/^\^|\$$/g, '').replace(/\\(.)/g, '$1');
  return re.test(plain) ? plain : null;
}

function controlMutants(j) {
  const clone = () => JSON.parse(JSON.stringify(j));
  const out = [];
  const add = (rung, what, mutate, expectFail) => {
    const c = clone();
    if (mutate(c) === false) {
      // The journey declares nothing this rung could break. Record it as unproven.
      out.push({ rung, what, supported: false,
                 why: 'this journey declares nothing this mutant can break' });
      return;
    }
    c.id = `${j.id}-CTL-${rung}`;
    c.title = `(positive control · ${rung} — ${what}; MUST fail)`;
    out.push({ rung, what, supported: true, journey: c, expectFail });
  };
  const named = (s) => (r) => r.name.includes(s);

  // Rung 1 — the landing guard that stops the walk.
  add('ui-landing', 'first step lands on a widget that does not exist', (c) => {
    if (!c.steps[0] || !c.steps[0].ui) return false;
    c.steps[0].ui.ready = '.mx-name-__this_widget_does_not_exist__';
  }, named('reached'));

  // Rung 2 — what the screen SAYS. The rung that caught P-1; if it cannot fail,
  // the one genuine product defect this harness has found was luck.
  add('ui-text', 'expect text the page never renders', (c) => {
    const s = c.steps.find(x => x.ui && x.ui.textPresent);
    if (!s) return false;
    s.ui.textPresent = ['__text_this_page_will_never_render__'];
    delete s.ui.textAbsent;                   // isolate: only the textPresent claim
  }, named('page says'));

  // Rung 3a — span ORDER. assertFired is existence-only; ordering is the claim.
  add('trace-order', 'expect a microflow that never fires', (c) => {
    const s = c.steps.find(x => x.spans && x.spans.ordered);
    if (!s) return false;
    s.spans.ordered = ['FieldScan.__ACT_This_Microflow_Does_Not_Exist__'];
    delete s.spans.mustNotFire;
  }, named('ordered'));

  // Rung 3b — the NEGATIVE trace claim. A mustNotFire that cannot fail would let
  // any out-of-sequence microflow through unnoticed.
  add('trace-negative', 'assert a microflow that DID run must not have run', (c) => {
    const s = c.steps.find(x => x.spans && x.spans.ordered && x.spans.ordered.length);
    if (s) { s.spans.mustNotFire = [s.spans.ordered[0].split('.').pop()]; return; }
    // A negative-only claim has no microflow that is known to run, so the mutant makes one:
    // the forbidden name is injected into the step's capture (after its liveness check) and
    // assertNotFired must go red on it (#150).
    const neg = c.steps.find(x => x.spans && (x.spans.mustNotFire || []).length);
    if (!neg) return false;
    const name = forbiddenSample(neg.spans.mustNotFire[0]);
    if (name === null) return false;
    neg.spans.mustNotFire = [neg.spans.mustNotFire[0]];
    neg.spans._controlInjectFired = [name];
  }, named('did not run'));

  // Rung 4a — the row-count delta.
  add('data-delta', 'expect +2 rows from a +1 action', (c) => {
    const s = c.steps.find(x => x.data && typeof x.data.delta === 'number');
    if (!s) return false;
    s.data.delta = s.data.delta + 1;
  }, named('+'));

  // Rung 4b — mustPointAt. Added 2026-08-14 and never yet observed failing; it is
  // the check that would have caught the wrong-location run, so leaving it unproven
  // would be exactly the decoration this whole exercise exists to retire.
  add('data-target', 'association must point at a value the journey never picked', (c) => {
    for (const s of c.steps) {
      for (const spec of (s.data && s.data.assocMustBeSet) || []) {
        if (spec.mustPointAt) {
          // A numeric key (Long/Integer) needs a numeric never-picked value: the text
          // sentinel is an OQL error there, the targeted check reads INVALID instead of
          // FAIL, and the rung is reported unproven over a working assertion
          // (card-disbursement build, row 3.8: a Long package key).
          spec.mustPointAt.value = /^-?\d+$/.test(String(spec.mustPointAt.value))
            ? '-424242' : '__LOC_THAT_WAS_NEVER_SELECTED__';
          return;
        }
      }
    }
    return false;
  }, named('points at the seeded'));

  // Rung 5 — the end-to-end outcome claim.
  // An exact `expect` is the stronger claim; the mutant once knew floors alone, so a
  // journey declaring `expect` had this rung reported unproven (card-disbursement build,
  // row 4.8).
  add('outcome', 'outcome query with an unreachable floor or exact value', (c) => {
    if (!c.outcome) return false;
    if (c.outcome.atLeast !== undefined) c.outcome.atLeast = 999999;
    else if (c.outcome.expect !== undefined) c.outcome.expect = 999999;
    else return false;
  }, named('end state'));

  // The denominator is declared, not counted from whatever happened to be added.
  // A rung that loses its `add` call in a future edit shows up here as unproven
  // rather than shrinking the denominator to match and going green.
  for (const rung of CONTROL_RUNGS) {
    if (!out.some(m => m.rung === rung)) {
      out.push({ rung, what: '(no mutant defined)', supported: false,
                 why: 'no mutant is defined for this rung — the control suite itself has a hole' });
    }
  }
  return out;
}

// Return to a known start state BETWEEN journeys.
//
// MEASURED 2026-08-14: without this, the 7 positive-control mutants ran back-to-back
// on one page and 5 of them died at step 1 on `.mx-name-bR never appeared` — the REAL
// selector, not the mutated one. Mutant 2 finished standing on the Receive page, so
// mutant 3 began its walk from there: the home button is absent on that screen and the
// nav group was already expanded, where a click COLLAPSES it. Five rungs reported
// "unproven" for a reason that had nothing to do with the rung.
//
// This is a RESET between independent journeys, which is legitimate. It is NOT the
// mid-journey `page.goto` recovery that e2e-harness notes forbid — that one hides state
// carry-over inside a walk. Here, carry-over between walks is precisely the bug.
async function resetToStart(page) {
  await page.goto(cfg.baseUrl, { waitUntil: 'domcontentloaded' });
  await settle(page, { fallbackMs: 2500 });
}

async function runJourney(page, j) {
  // Journey start: the window a negative-only span claim's liveness check reads. Only this
  // journey's own spans count — never the previous journey's, nor other users' from before
  // it began. LIVENESS_SKEW_MS (2 s) absorbs clock skew between this host and the runtime's
  // span timestamps (Jaeger stamps with the runtime's clock); it is far shorter than any
  // journey, so a span from the previous one cannot fall inside it in practice.
  const jt0 = Date.now() - LIVENESS_SKEW_MS;
  console.log(`\n=== JOURNEY ${j.id} — ${j.title || ''}`);
  console.log(`    persona: ${j.persona || cfg.user}   requirements: ${(j.requirement || []).join(', ') || '(none declared)'}`);

  const seeded = resolveSeeds(j);
  if (!seeded.ok) {
    record('data', `${j.id}: seeds resolved`, 'INVALID',
      `"${seeded.missing}" returned nothing — the DB has no row to drive this journey, ` +
      'or the admin API is unreachable. Journey NOT run; this is not a feature failure.',
      (j.requirement || []).join(', '));
    return;
  }
  const vars = seeded.vars;
  if (Object.keys(vars).length) console.log(`    seeds: ${JSON.stringify(vars)}`);

  // Baselines for every declared data effect, captured BEFORE the journey runs.
  // A delta needs a before. Taking it per-step instead of up front would let an
  // earlier step's write be counted as a later step's.
  const baseline = {};
  for (const s of j.steps) {
    const d = s.data;
    if (d && d.creates && !(d.creates in baseline)) {
      baseline[d.creates] = count(`SELECT COUNT(*) AS n FROM ${d.creates}`);
    }
  }

  const walk = { journey: j.id, title: j.title || '', persona: j.persona || cfg.user, device: DEVICE,
                 requirement: j.requirement || [], seeds: vars, steps: [] };
  walks.push(walk);

  for (const [i, step] of j.steps.entries()) {
    console.log(`\n  --- step ${i + 1}/${j.steps.length}: ${step.name}`);
    const req = (step.requirement || j.requirement || []).join(', ');
    const t0 = Date.now();
    const from = results.length;   // every check recorded from here belongs to this step
    const leg = { n: i + 1, name: step.name, requirement: req ? req.split(', ') : [],
                  actions: (step.actions || []).map(a => describeAct(a, vars)),
                  expects: {
                    landsOn: (step.ui && step.ui.ready) || null,
                    pageSays: (step.ui && step.ui.textPresent) || [],
                    pageDoesNotSay: (step.ui && step.ui.textAbsent) || [],
                    microflows: (step.spans && step.spans.ordered) || [],
                    writes: step.data && step.data.creates
                      ? { entity: step.data.creates, delta: step.data.delta ?? null,
                          associations: (step.data.assocMustBeSet || []).map(s => s.assoc || s) }
                      : null,
                  },
                  shot: null, reached: null, checks: [], ms: null };
    walk.steps.push(leg);
    // Attach this step's checks and timing however the step ends — including the
    // early `return`s below, which is why it is a finaliser called at each exit and
    // not a line at the bottom of the loop. A step that bailed still has to show
    // what it managed, or the walk goes quiet exactly where it matters most.
    // ui.no5xx (opt-in, #564): watch every response from the first action to the landing guard.
    const watch5xx = !!(step.ui && step.ui.no5xx === true);
    const hits5xx = [];
    const on5xx = (r) => { if (r.status() >= 500) hits5xx.push(`${r.status()} ${r.request().method()} ${r.url().slice(0, 120)}`); };
    let no5xxDone = !watch5xx;
    // Recorded before any bail-out, so a 5xx that is WHY the page never landed shows beside it.
    const record5xx = () => {
      if (no5xxDone) return;
      no5xxDone = true;
      page.off('response', on5xx);
      const v = no5xxVerdict(hits5xx);
      record('ui', `${step.name}: no HTTP 5xx during the step`, v.verdict, v.detail, req);
    };
    if (watch5xx) page.on('response', on5xx);
    const seal = () => {
      if (watch5xx) page.off('response', on5xx);
      leg.checks = results.slice(from).map(r =>
        ({ rung: r.rung, name: r.name, verdict: r.verdict, detail: r.detail }));
      leg.ms = Date.now() - t0;
    };

    // Actions may assert as they go — a combobox that commits the seeded value is a
    // real measurement and belongs in the findings, not buried in a side effect.
    const note = (rung, name, verdict, detail) =>
      record(rung, `${step.name}: ${name}`, verdict, detail, req);

    const geo = stepGeolocation(j, step, i);
    if (geo) {
      if (geo.legacy) console.log('    WARN _geolocation read as geolocation — rename the key; the validator does not check `_` keys');
      const g = resolveGeolocation(geo.spec, vars);
      if (!g.ok) {
        record('setup', `${step.name}: geolocation`, 'INVALID', `${g.why} — journey stopped; a position is never sent as 0,0`, req);
        seal();
        return;
      }
      await applyGeolocation(page, g.value);
      console.log(`    position: ${g.value.latitude}, ${g.value.longitude}${g.value.accuracy != null ? ` ±${g.value.accuracy} m` : ''}`);
    }

    // ── Rung 4 watermarks, taken BEFORE the actions ──────────────────────────
    // This is the only moment they can be taken. A mark read after the click already
    // includes the row the click wrote, and the scoped checks would then look for it
    // strictly above itself and find nothing — a false FAIL on a correct commit.
    // One mark per distinct entity the step will assert on.
    const scopes = new Map();
    if (step.data) {
      const decl = step.data.scope;
      const ents = new Set();
      if (step.data.creates) ents.add(step.data.creates);
      for (const spec of step.data.assocMustBeSet || [])
        ents.add(spec.entity || step.data.creates);
      for (const e of ents) if (e) scopes.set(e, captureScope(e, decl));
    }

    try {
      for (const a of step.actions || []) await act(page, a, vars, note);
    } catch (e) {
      record('ui', `${step.name}: actions completed`, 'FAIL', e.message.split('\n')[0], req);
      leg.shot = await shoot(page, `${j.id}-step${i + 1}-ACTION-FAILED`);
      record5xx();
      seal();
      return; // the journey's state is now unknown; later steps would measure noise
    }

    // ── RUNG 1: landing guard ────────────────────────────────────────────────
    let onPage = true;
    if (step.ui && step.ui.ready) {
      // waitFor, not isVisible: isVisible ignores its timeout and answers at once (#536), so a
      // page that rendered after the settle read NOT-REACHED. The NOT-REACHED shot below is
      // now taken after the full 12 s, so it shows what the page became.
      onPage = await page.locator(step.ui.ready).first()
                         .waitFor({ state: 'visible', timeout: 12000 }).then(() => true, () => false);
      if (!onPage) {
        leg.shot = await shoot(page, `${j.id}-step${i + 1}-NOT-REACHED`);
        record('ui', `${step.name}: reached`, 'FAIL',
               `"${step.ui.ready}" never appeared — screenshot ${path.basename(leg.shot.file)}`, req);
      } else {
        record('ui', `${step.name}: reached`, 'PASS', step.ui.ready, req);
      }
      leg.reached = onPage;
    }
    record5xx();

    // The success shot, taken HERE: after the actions and the landing guard, before
    // the text/trace/data rungs. That ordering is the whole point — this image is the
    // page state those rungs measured, not a later one. A shot taken at the bottom of
    // the loop would show the app after any navigation the rungs provoked, and would
    // quietly stop being evidence for the checks printed beside it.
    if (onPage && !leg.shot) leg.shot = await shoot(page, `${j.id}-step${i + 1}`);

    // Everything below asserts about THIS page. If we never landed, it would be
    // asserting about the previous one — so it does not run at all.
    if (!onPage) {
      record('ui', `${step.name}: downstream rungs`, 'INVALID', 'not reached; nothing measured', req);
      seal();
      return;
    }

    for (const c of (step.ui && step.ui.checks) || []) {
      const seen = await H.visibleWithin(page.locator(`.mx-name-${c}`).first(), 4000);   // waits up to 4 s (#536)
      record('ui', `${step.name}: widget ${c}`, seen ? 'PASS' : 'FAIL', '', req);
    }

    // What the page SAYS, not just which widgets exist. Every other rung answers
    // "did the machine do the work"; only this one answers "does the screen tell the
    // user the truth about it". FieldScan's Receive commits the row correctly and
    // then renders "No placements yet" on the panel listing that very row — a defect
    // that mxbuild, the microflow span, the activity spans and the OQL delta all
    // agree is fine, because by their own lights it is.
    const body = ((step.ui && (step.ui.textPresent || step.ui.textAbsent))
      ? await page.locator('body').innerText().catch(() => '') : '');
    for (const t of (step.ui && step.ui.textPresent) || []) {
      const want = String(subst(t, vars));
      record('ui', `${step.name}: page says "${want}"`,
             body.includes(want) ? 'PASS' : 'FAIL',
             body.includes(want) ? '' : 'not found in rendered text', req);
    }
    for (const t of (step.ui && step.ui.textAbsent) || []) {
      const bad = String(subst(t, vars));
      record('ui', `${step.name}: page does NOT say "${bad}"`,
             body.includes(bad) ? 'FAIL' : 'PASS',
             body.includes(bad) ? 'rendered — the screen contradicts the data' : '', req);
    }

    // CSS-authored text (#276): an empty-state sentence written as ::before / ::after content is
    // on the screen and absent from innerText, so textPresent FAILs a correct page. `pseudoText`
    // asserts it against the rendered pseudo-elements of visible elements instead.
    if (step.ui && (step.ui.pseudoText || []).length) {
      const texts = await pseudoTexts(page);
      for (const t of step.ui.pseudoText) {
        const want = String(subst(t, vars));
        const v = pseudoVerdict(texts, want);
        record('ui', `${step.name}: CSS content says "${want}"`, v.verdict, v.detail, req);
      }
    }

    // ── RUNG 2: ordered spans ────────────────────────────────────────────────
    await traceRung(step, { t0, since: jt0,
      rec: (name, verdict, detail) => record('trace', name, verdict, detail, req) });

    // ── RUNG 3: data effects ─────────────────────────────────────────────────
    const d = step.data;
    if (d) {
      if (d.creates) {
        const before = baseline[d.creates];
        const after = count(`SELECT COUNT(*) AS n FROM ${d.creates}`);
        if (before === null || after === null) {
          record('data', `${step.name}: ${d.creates} created`, 'INVALID',
                 'OQL returned nothing — admin API unreachable. Data rung did NOT run.', req);
        } else {
          const want = d.delta ?? 1;
          record('data', `${step.name}: ${d.creates} +${want}`,
                 after - before === want ? 'PASS' : 'FAIL',
                 `before=${before} after=${after} delta=${after - before}`, req);
          baseline[d.creates] = after;
        }
      }
      for (const spec of d.assocMustBeSet || []) {
        const entity = spec.entity || d.creates;
        const sc = scopes.get(entity) || { state: 'unscoped', entity };
        const ev = scopeEvidence(sc);

        // A declared-but-unreadable watermark stops both checks here. Running them
        // unscoped instead would print the scoped claim over whole-table numbers.
        if (sc.state === 'broken') {
          record('data', `${step.name}: ${spec.assoc} set on every row`, 'INVALID', sc.reason, req);
          if (spec.mustPointAt)
            record('data', `${step.name}: ${spec.assoc} points at the seeded ${spec.mustPointAt.attr}`,
                   'INVALID', sc.reason, req);
          continue;
        }

        const g = assocGap(entity, spec.assoc, spec.target, sc);
        if (g === null) {
          record('data', `${step.name}: ${spec.assoc} set`, 'INVALID', 'OQL returned nothing', req);
        } else if (sc.state !== 'unscoped' && g.total === 0) {
          // Scoped to nothing: the step wrote no row at all, so there is no association
          // to judge. Reporting "0/0 linked, gap 0" as PASS is the vacuous green the
          // scoping was added to remove — the delta check above owns this failure.
          record('data', `${step.name}: ${spec.assoc} set on every row`, 'FAIL',
                 `no ${entity} row was written by this step (${ev.tag}), so the association ` +
                 'could not be verified — nothing to link', req, 'strong');
        } else {
          record('data', `${step.name}: ${spec.assoc} set on every row`,
                 g.gap === 0 ? 'PASS' : 'FAIL',
                 `${g.linked}/${g.total} linked, ${g.gap} row(s) saved with no association ` +
                 `(${ev.tag})`, req, ev.strength);
        }

        // "Set" and "set to the right thing" are different claims, and the gap between
        // them is where a wrong-input run hides: a placement linked to SOME location
        // satisfies the check above no matter which location the user actually picked.
        // `mustPointAt` closes it by naming the seed the target has to match.
        if (spec.mustPointAt) {
          const { attr, value } = spec.mustPointAt;
          const want = subst(value, vars);
          const n = count(sqlMustPointAt(entity, spec.assoc, spec.target, attr, want, sc));
          if (n === null) {
            record('data', `${step.name}: ${spec.assoc} points at the seeded ${attr}`,
                   'INVALID', 'OQL returned nothing', req);
          } else {
            record('data', `${step.name}: ${spec.assoc} points at the seeded ${attr}`,
                   n >= 1 ? 'PASS' : 'FAIL',
                   `${n} row(s) link to ${spec.target} where ${attr} = '${want}' (${ev.tag})`,
                   req, ev.strength);
          }
        }
      }
      for (const q of d.oql || []) {
        const c = checkOql(q, vars);
        record('data', `${step.name}: ${q.label}`, c.verdict, c.detail, req);
      }
    }
    seal();
  }

  // ── RUNG 4: outcome ────────────────────────────────────────────────────────
  if (j.outcome && j.outcome.sql) {
    const c = checkOql(j.outcome, vars);
    record('outcome', outcomeCheckName(j), c.verdict, c.detail, (j.requirement || []).join(', '));
  }
  return true;   // walked every step (each early return above is a bail-out)
}

// After every journey (walk or mutant): back online, position cleared (#521).
async function endJourneyEnv(page, j, completed) {
  const wasOffline = await ensureOnline(page).catch(() => false);
  await clearGeolocation(page).catch(() => {});
  const row = networkEndRow(j.id, wasOffline, completed);
  if (row) record('setup', row.name, row.verdict, row.detail, (j.requirement || []).join(', '));
}

// The outcome check's name carries `outcome.label` when one is set, as a `data.oql[]` check's
// name carries its label (#538): a named control tagged in outcome.label otherwise matched no
// check name and always read NOT PROVEN. `<id> end state` stays the prefix, so an existing
// `mustFail: "end state"` still matches. report-normalize.js builds the same name.
function outcomeCheckName(j) {
  const label = j.outcome && typeof j.outcome.label === 'string' ? j.outcome.label.trim() : '';
  return label ? `${j.id} end state: ${label}` : `${j.id} end state`;
}

// ── Exit code ───────────────────────────────────────────────────────────────
// A walk passes when nothing FAILed and nothing was INVALID. A CONTROL run asks the other
// question — can the harness tell when the app is broken — so its FAIL rows are the mutants
// doing their job, and it passes only when every rung's mutant was caught (each `control`
// row PASS, proven == expected, and at least one rung tried).
//
// MEASURED 2026-09-26 (card-disbursement requirements-driven build): the walk's rule was
// applied to both runs. A control that proved 7 of 7 rungs exited 1 on its own 7 mutant
// FAILs plus the INVALID a broken landing leaves downstream, so verify-module graded the
// rung FINDING and the module INCOMPLETE on every run — a control rung that could not go
// green, and so told the reader nothing when it went red.
// One mutant's control row, from the rows its walk produced (#560). Caught on the targeted check
// → PASS. Failed elsewhere → FAIL, still unproven. Nothing failed but something was INVALID (a
// seed the previous mutant consumed, a guard that stopped the walk) → the mutant never reached
// its check: INVALID "mutant not run". Reading that as "BROKEN PRECONDITION WENT GREEN" sent the
// reader looking for a vacuous assertion in a journey that was fine. Only an all-green walk is
// "went green". The exit code is unchanged: a control passes only when every row is PASS.
function judgeMutant(produced, expectFail) {
  const hit = produced.find(r => r.verdict === 'FAIL' && expectFail(r));
  if (hit) return { verdict: 'PASS', proven: true, detail: `caught by "${hit.name}"` };
  if (produced.some(r => r.verdict === 'FAIL'))
    return { verdict: 'FAIL', proven: false, detail: 'the run failed, but NOT on the targeted check — this rung is still unproven' };
  const stop = produced.find(r => r.verdict === 'INVALID');
  if (stop)
    return { verdict: 'INVALID', proven: false,
             detail: `mutant not run: "${stop.name}" = INVALID before the targeted check — this rung is NOT tried, ` +
                     'not proven and not green (a consuming journey needs fresh data per mutant)' };
  return { verdict: 'FAIL', proven: false, detail: 'BROKEN PRECONDITION WENT GREEN — this rung proves nothing' };
}

function runExitCode(positiveControl, results, mutants) {
  if (!positiveControl) return results.some(r => r.verdict === 'FAIL' || r.verdict === 'INVALID') ? 1 : 0;
  const ctl = results.filter(r => r.rung === 'control');
  return mutants.expected > 0 && mutants.proven === mutants.expected
    && ctl.length === mutants.expected && ctl.every(r => r.verdict === 'PASS') ? 0 : 1;
}

// ── Persona = the signed-in user ────────────────────────────────────────────
// A journey's `persona` names the role whose access path it proves. It used to be
// printed and nothing else, so a journey declaring persona "Reviewer" walked green
// under TEST_USER=Admin — a pass for the wrong reason, because admin bypasses the
// very grants the journey claims to exercise (#149, 2026-09-25). One run signs in
// once, so a journey whose persona differs from that user is not run: INVALID, and
// the remedy is to run it with TEST_USER set to the persona. A journey with no
// persona runs as whoever signed in, as before.
// Returns null when the journey may run, or the INVALID detail when it may not.
function personaMismatch(j, signedInAs) {
  if (!j.persona || j.persona === signedInAs) return null;
  return `journey declares persona "${j.persona}", run signed in as "${signedInAs}" — ` +
         'the run measures the wrong access path. Journey NOT run; run it with ' +
         `TEST_USER=${j.persona} (one file, one run per role).`;
}

// ── Suite preflight: refuse a run that can only produce INVALIDs ────────────
// Field run 2026-10-12, 14 journeys (#286): the admin credential the runner defaulted to
// was not the app's, every data rung got HTTP 403 and read INVALID, and the suite walked
// all 14 journeys anyway — first pass 305/339 PASS, 2 of 14 green, discarded whole. Two
// unset mock env vars made 3 more journeys INVALID one at a time, and an undeclared order
// dependency (one journey's last step moved the record on; the next one's seed refused)
// made 6 of 14 INVALID. Every one of those is a SETUP fault, knowable before the first
// click, and each was reported as a pile of per-journey INVALIDs that look like test faults.
//
// So, before the browser opens:
//   0. login    — TEST_PASS unset aborts before any login attempt (#278): a run started
//                 without the project's env step submitted the config default, then the
//                 admin fallback, and locked two demo accounts for ~5 min each.
//                 ALLOW_CONFIG_CREDENTIALS=1 when the config default is the real password.
//   1. env      — every journey's `requiresEnv` names are checked; the missing ones are ONE
//                 setup line, and the journeys that need them are not walked.
//   2. admin    — if any journey has a data rung, seed or outcome, one OQL probe through
//                 the same `mxcli oql --direct` the rungs use. 401/403 or unreachable
//                 ABORTS THE SUITE (exit 2) with where the credential came from and how to
//                 set it — never the credential. ALLOW_NO_DATA_RUNG=1 proceeds anyway, with
//                 every data rung INVALID as before.
//   3. sessions — the same probe counts System.Session. Leaked sessions (journeys that
//                 never logged out, a hung runner, an agent retry loop) filled a trial
//                 licence's cap in the field (#287) and every later login read as a wrong
//                 password. JOURNEY_SESSION_CAP=<n> refuses the run when the live count is
//                 already at the cap; ALLOW_SESSION_CAP=1 overrides.
//
// The probe's text is mxcli v0.26.0's own messages (format strings read out of the binary,
// see tests/wave2/fixtures/journey-preflight/): "authentication failed (HTTP %d) -- check
// the admin password (--token or M2EE_ADMIN_PASS)" and "cannot connect to Mendix admin API
// at %s:%d -- is the app running?". The class is decided from those, not from the exit code.
const ADMIN_PROBE_SQL = 'SELECT COUNT(*) AS n FROM System.Session';

function classifyAdminProbe(text, status) {
  const t = String(text || '');
  const auth = t.match(/authentication failed \(HTTP (\d{3})\)/i)
            || t.match(/\bHTTP (401|403)\b/)
            || t.match(/\b(401) Unauthorized\b|\b(403) Forbidden\b/i);
  if (auth) return { state: 'auth', http: Number(auth[1] || auth[2]) };
  if (/cannot connect to Mendix admin API|ECONNREFUSED|connection refused/i.test(t))
    return { state: 'unreachable' };
  const parsed = H.parseOqlOutput(t, ADMIN_PROBE_SQL);
  if (status === 0 && parsed && parsed.rows && parsed.rows[0] !== undefined) {
    const v = H.scalarOf(parsed), n = v === null ? NaN : Number(v);
    return { state: 'ok', sessions: Number.isFinite(n) ? n : null };
  }
  return { state: 'unknown', detail: t.trim().split('\n').filter(Boolean).slice(-1)[0] || `exit ${status}` };
}

function runAdminProbe() {
  const { spawnSync } = require('child_process');
  const r = spawnSync(H.mxcliBin(), [
    'oql', '--direct', '--host', cfg.adminHost, '--port', String(cfg.adminPort),
    '--token', cfg.adminToken, '--json', ADMIN_PROBE_SQL,
  ], { cwd: cfg.root, encoding: 'utf8', timeout: 20000 });
  if (r.error) return { state: 'tool', detail: `${H.mxcliBin()}: ${r.error.code || r.error.message}` };
  return classifyAdminProbe(`${r.stdout || ''}\n${r.stderr || ''}`, r.status);
}

// Does this journey need the admin API at all? A UI-only journey must not be refused
// over a data instrument it never uses.
function journeyNeedsAdmin(j) {
  return (j.seeds || []).some(s => s && s.sql)
      || !!(j.outcome && j.outcome.sql)
      || (j.steps || []).some(s => s && s.data);
}

// var -> [journey ids] for every `requiresEnv` name that is unset or empty.
function missingEnv(journeys, env) {
  const miss = new Map();
  for (const j of journeys) {
    for (const v of j.requiresEnv || []) {
      if (env[v]) continue;
      if (!miss.has(v)) miss.set(v, []);
      miss.get(v).push(j.id);
    }
  }
  return miss;
}

// The whole preflight as one decision, with the probe injected so the fixture can feed it
// captured mxcli output. Returns:
//   lines  — SETUP lines to print, in order
//   rows   — result rows to record (rung 'setup')
//   skip   — journey id -> reason, journeys not to walk
//   abort  — null, or the exit code (2: instrument fault) that ends the suite here
// `redact` is applied to anything quoted back from the probe, so a token can never be echoed.
function preflight(journeys, { env = process.env, probe = runAdminProbe, admin = cfg,
                               protectState = PROTECT_STATE } = {}) {
  const lines = [], rows = [], skip = new Map();
  const redact = s => (admin.adminToken && admin.adminToken.length > 2
    ? String(s).split(admin.adminToken).join('<redacted>') : String(s));
  const setup = (name, detail) => {
    lines.push(`SETUP  ${name}: ${detail}`);
    rows.push({ rung: 'setup', name: `preflight: ${name}`, verdict: 'INVALID', detail, requirement: '' });
  };

  // 0. login credential (#278). A run that would submit the TEMPLATE PLACEHOLDER password
  // (nobody set TEST_PASS, nobody edited project.config.js's DEFAULT_PASS) then tries the admin
  // fallback; each rejected submit counts toward Mendix's 3-attempt lockout, and in the field
  // two demo accounts were locked for ~5 min each. So no login is attempted at all.
  // A password the PROJECT set in project.config.js is accepted: the template tells every
  // project to put its real demo password there, and nothing in the toolkit loads an env file
  // before verify-module runs the journeys — refusing it (#302 as first shipped) faulted every
  // journeys rung after the next sync. ALLOW_CONFIG_CREDENTIALS=1 overrides when the
  // placeholder really is the demo password. An admin object without passSource (older
  // config.js) keeps the #302 rule: refuse unless the password came from the env.
  const placeholder = admin.passSource !== undefined
    ? admin.passSource === 'template placeholder'
    : !admin.passFromEnv;
  if (placeholder && env.ALLOW_CONFIG_CREDENTIALS !== '1') {
    setup('credentials', `TEST_PASS is unset — the run would log in as "${admin.user}" with ` +
      "project.config.template.js's placeholder password and then try the fallback account, and each " +
      'rejected attempt counts toward the account lockout. Put the real demo password in ' +
      "project.config.js's DEFAULT_PASS, or load the project env first (export TEST_USER / " +
      'TEST_PASS, e.g. `set -a; . ./.env; set +a`), or set ALLOW_CONFIG_CREDENTIALS=1 if the ' +
      'placeholder is the real demo password. Suite ABORTED before any login');
    return { lines, rows, skip, abort: 2 };
  }

  // 0b. journeys that reset or reload demo data (#279). Field run 2026-10-12: one suite run
  // between a rehearsal and a recording wiped one app's seeded state, and that app never
  // appeared in the film. The tag is always printed; --protect-state refuses tagged journeys.
  const resetting = journeys.filter(j => j.resetsData === true).map(j => j.id);
  if (resetting.length && !protectState) {
    lines.push(`SETUP  resetsData: ${resetting.join(', ')} reset or reload demo data — anything seeded or rehearsed by hand is gone after this run (--protect-state refuses them)`);
  } else if (resetting.length) {
    for (const id of resetting) skip.set(id, 'tagged resetsData; --protect-state is on');
    setup('protect-state', `refused ${resetting.join(', ')} — tagged "resetsData": true and --protect-state is on. Record or snapshot the demo state first, then run them without the flag`);
  }

  // 1. env — one line for the suite, however many journeys share the gap.
  const miss = missingEnv(journeys, env);
  if (miss.size) {
    const ids = new Set([].concat(...miss.values()));
    for (const id of ids) skip.set(id, 'required env var(s) unset — see the SETUP line');
    setup('env', `missing ${[...miss].map(([v, js]) => `${v} (needed by ${js.join(', ')})`).join('; ')}` +
      ` — export ${miss.size === 1 ? 'it' : 'them'} and re-run; ${ids.size} journey(s) not walked`);
  }
  const runnable = journeys.filter(j => !skip.has(j.id));
  if (!runnable.length) return { lines, rows, skip, abort: 2 };

  // 2 + 3. one probe: credential, reachability and the live session count.
  if (!runnable.some(journeyNeedsAdmin)) return { lines, rows, skip, abort: null };
  const p = probe();
  const where = `${admin.adminHost}:${admin.adminPort}`;
  const how = 'set M2EE_ADMIN_PASS (and M2EE_ADMIN_PORT if the port differs), or start the app ' +
              'with `mxcli run --local` / `mxcli docker up` so the toolkit can read it from ' +
              '.mxcli/run-local.json / .docker/.env';
  const allowNoData = env.ALLOW_NO_DATA_RUNG === '1';
  if (p.state === 'auth' || p.state === 'unreachable' || p.state === 'tool') {
    const what = p.state === 'auth'
      ? `admin API at ${where} refused the credential (HTTP ${p.http}); credential from ${admin.adminSource}. ${how}`
      : p.state === 'unreachable'
        ? `admin API unreachable at ${where} — is the app running? Credential from ${admin.adminSource}; ` +
          'set M2EE_ADMIN_PORT if the admin API listens on another port'
        : `could not run the OQL instrument: ${redact(p.detail)}`;
    setup('admin', `${what}. Every seed, data rung and outcome would read INVALID — ` +
      (allowNoData ? 'proceeding because ALLOW_NO_DATA_RUNG=1.'
                   : 'suite ABORTED before the first journey (ALLOW_NO_DATA_RUNG=1 runs it anyway).'));
    return { lines, rows, skip, abort: allowNoData ? null : 2 };
  }
  if (p.state === 'unknown') {
    lines.push(`SETUP  admin: probe inconclusive (${redact(p.detail)}) — proceeding; data rungs may read INVALID`);
    return { lines, rows, skip, abort: null };
  }
  lines.push(`SETUP  admin: OK at ${where} (credential from ${admin.adminSource})`);
  if (p.sessions != null) {
    const cap = Number(env.JOURNEY_SESSION_CAP || 0);
    if (cap > 0 && p.sessions >= cap && env.ALLOW_SESSION_CAP !== '1') {
      setup('sessions', `${p.sessions} live session(s), cap ${cap} (JOURNEY_SESSION_CAP) — this run's ` +
        'login would be refused and read as a wrong password. Find the leak (a runner that never ' +
        'logged out, a hung run) or restart the runtime; ALLOW_SESSION_CAP=1 overrides');
      return { lines, rows, skip, abort: 2 };
    }
    lines.push(`SETUP  sessions: ${p.sessions} live${cap > 0 ? ` of cap ${cap}` : ''}` +
      (p.sessions > 0 && !cap ? ' — on a trial licence leaked sessions fill the cap; set JOURNEY_SESSION_CAP to refuse at it' : ''));
  }
  return { lines, rows, skip, abort: null };
}

// ── Landing state: no focus ring before any pointer action (#281) ───────────
// Mendix focuses the first nav item from script on page load, and Chrome treats that as
// :focus-visible. So a focus ring added for accessibility paints on every landing. A step
// that clicks first clears it, and a check that counts only inset box-shadows misses an
// outline. Field run 2026-10-12: the ring showed on landing for 3 of 3 roles on one app
// while its 3 UX asserts stayed green.
//
// collectLanding() runs in the page right after login, before any click. It returns the
// elements that draw a ring: any element with a visible outline, plus any FOCUSED element
// (activeElement, :focus, :focus-visible) with a box-shadow. A card's resting shadow is
// not a focus ring, so unfocused box-shadows are not collected. judgeLanding() is the pure
// verdict, exported for the fixture.
async function collectLanding(page) {
  return page.evaluate(() => {
    const out = [];
    const name = el => {
      const cls = (typeof el.className === 'string' ? el.className : '').trim().split(/\s+/)
        .filter(c => /^mx-name-|^mx-navigation|^nav|^btn/.test(c)).slice(0, 2).join('.');
      return el.tagName.toLowerCase() + (el.id ? '#' + el.id : '') + (cls ? '.' + cls : '');
    };
    for (const el of document.querySelectorAll('*')) {
      const cs = getComputedStyle(el);
      let focused = el === document.activeElement;
      try { focused = focused || el.matches(':focus') || el.matches(':focus-visible'); } catch {}
      const outlined = cs.outlineStyle !== 'none' && cs.outlineWidth !== '0px';
      const shadowed = focused && cs.boxShadow && cs.boxShadow !== 'none';
      if (outlined || shadowed)
        out.push({ el: name(el), outlineStyle: cs.outlineStyle, outlineWidth: cs.outlineWidth,
                   boxShadow: cs.boxShadow, focused });
      if (out.length >= 20) break;
    }
    return out;
  }).catch(e => ({ error: String(e && e.message || e) }));
}

function judgeLanding(snapshot) {
  if (!Array.isArray(snapshot))
    return { verdict: 'INVALID', detail: `landing state not read: ${(snapshot && snapshot.error) || 'no snapshot'}` };
  const rings = snapshot.filter(r =>
    (r.outlineStyle && r.outlineStyle !== 'none' && r.outlineWidth !== '0px')
    || (r.focused && r.boxShadow && r.boxShadow !== 'none'));
  if (!rings.length) return { verdict: 'PASS', detail: 'no outline and no focus box-shadow on any element' };
  return { verdict: 'FAIL', detail: `${rings.length} element(s) draw a ring before any click: ` +
    rings.slice(0, 5).map(r => r.outlineStyle && r.outlineStyle !== 'none' && r.outlineWidth !== '0px'
      ? `${r.el} outline ${r.outlineWidth} ${r.outlineStyle}` : `${r.el} focus box-shadow`).join('; ') +
    ' — style the ring for keyboard focus only (e.g. under a class set on the first Tab key)' };
}

// ── Declared state: requires / leaves / consumes ────────────────────────────
// Optional journey-level arrays of state tokens (free strings, e.g. "change-at-review"):
//   requires  — this journey's seeds only resolve when that state holds
//   leaves    — a clean walk of this journey leaves that state behind
//   consumes  — a walk of this journey destroys that state (moves the record on)
// orderJourneys() puts every journey that leaves X before every journey requiring X, and
// every journey requiring X before every journey consuming X; ties keep file order, so a
// suite with no headers runs exactly as listed (back-compat). A cycle keeps file order
// for the journeys in it and is reported.
function orderJourneys(journeys) {
  const n = journeys.length;
  const arr = (j, k) => Array.isArray(j[k]) ? j[k] : [];
  const edges = Array.from({ length: n }, () => new Set());
  const indeg = new Array(n).fill(0);
  const add = (a, b) => { if (a !== b && !edges[a].has(b)) { edges[a].add(b); indeg[b]++; } };
  for (let a = 0; a < n; a++) for (let b = 0; b < n; b++) {
    for (const x of arr(journeys[a], 'leaves'))
      if (arr(journeys[b], 'requires').includes(x)) add(a, b);
    for (const x of arr(journeys[a], 'requires'))
      if (arr(journeys[b], 'consumes').includes(x)) add(a, b);
  }
  const done = new Array(n).fill(false), order = [];
  for (;;) {
    let next = -1;
    for (let i = 0; i < n; i++) if (!done[i] && indeg[i] === 0) { next = i; break; }
    if (next === -1) break;
    done[next] = true; order.push(next);
    for (const b of edges[next]) indeg[b]--;
  }
  const cycle = [];
  for (let i = 0; i < n; i++) if (!done[i]) { cycle.push(journeys[i].id); order.push(i); }
  return { order: order.map(i => journeys[i]), cycle: cycle.length ? cycle : null };
}

// Tracks which declared states hold as the suite walks. `assumed` are tokens no journey in
// this run leaves: the runner cannot know them, so it trusts the fixture (and says so once).
function stateTracker(journeys) {
  const leftBy = new Map();
  for (const j of journeys) for (const x of j.leaves || []) {
    if (!leftBy.has(x)) leftBy.set(x, []);
    leftBy.get(x).push(j.id);
  }
  const held = new Set();
  const lost = new Map();      // token -> why it does not hold
  const ran = new Map();       // journey id -> 'clean' | '<n FAIL / m INVALID>' | 'not walked'
  return {
    // null when the journey may run, else the INVALID detail.
    gate(j) {
      const unmet = [];
      for (const x of j.requires || []) {
        if (held.has(x)) continue;
        if (lost.has(x)) { unmet.push(`${x} (${lost.get(x)})`); continue; }
        const by = leftBy.get(x);
        if (!by) continue;                       // no journey here leaves it: fixture's job
        const why = by.map(id => ran.has(id) ? `${id}, which ${ran.get(id) === 'not walked'
          ? 'was not walked' : `did not complete: ${ran.get(id)}`}` : `${id}, not yet run`);
        unmet.push(`${x} (left by journey ${why.join(' / ')})`);
      }
      return unmet.length ? `precondition not met: ${unmet.join('; ')} — journey NOT walked; ` +
        'this is an ordering/fixture fault, not a feature failure' : null;
    },
    // Called after each journey with the rows it produced (none when it was not walked).
    settle(j, rows, walked) {
      const f = rows.filter(r => r.verdict === 'FAIL').length;
      const v = rows.filter(r => r.verdict === 'INVALID').length;
      const clean = walked && !f && !v;
      ran.set(j.id, !walked ? 'not walked' : clean ? 'clean' : `${f} FAIL / ${v} INVALID`);
      if (!walked) return;
      for (const x of j.consumes || []) { held.delete(x); lost.set(x, `consumed by journey ${j.id}`); }
      if (clean) for (const x of j.leaves || []) { held.add(x); lost.delete(x); }
    },
    assumed() {
      const all = new Set([].concat(...journeys.map(j => j.requires || [])));
      return [...all].filter(x => !leftBy.has(x));
    },
  };
}

// ── App liveness between journeys (#285) ────────────────────────────────────
// The preflight probes the app once, before the first journey. Field run 2026-10-12: a watch
// rebuild failed mid-suite (IO_PathNotFound on deployment/web/pages), the runtime went down,
// and every remaining journey failed as if the features were broken — the suite owner had to
// be told to rerun only the infrastructure failures. So the runner asks before each journey
// whether the app still answers, and after each one whether it outlived it:
//   down before a journey → that journey is APP-DOWN (INVALID, `appDown: true`), not walked;
//   down after a journey  → its FAIL rows are flagged `appDown: true` and named in the summary
//                            as "rerun before reading as findings" — the verdict stays FAIL,
//                            because the app may have died of what the journey found.
// "Up" is any HTTP answer below 500; a refused connection, a timeout or a 5xx is down. A few
// short retries absorb a restart already in progress. APP_PROBE=0 turns it off.
async function probeApp(url, { timeoutMs = 5000, fetchFn = globalThis.fetch } = {}) {
  try {
    const r = await fetchFn(url, { redirect: 'manual', signal: AbortSignal.timeout(timeoutMs) });
    return r.status >= 500 ? { up: false, detail: `HTTP ${r.status}` } : { up: true, detail: `HTTP ${r.status}` };
  } catch (e) {
    return { up: false, detail: (e && e.cause && e.cause.code) || (e && e.name) || String(e) };
  }
}

async function appGate(url, { probe = probeApp, tries = 3, waitMs = 5000, sleep = PAUSE } = {}) {
  let last = null;
  for (let i = 0; i < tries; i++) {
    last = await probe(url);
    if (last.up) return { up: true, detail: last.detail, tries: i + 1 };
    if (i + 1 < tries) await sleep(waitMs);
  }
  return { up: false, detail: last.detail, tries };
}

// The rows a journey just produced, after the app was found down: flag every FAIL. Returns
// how many were flagged.
function flagAppDown(rows, detail) {
  let n = 0;
  for (const r of rows) {
    if (r.verdict !== 'FAIL') continue;
    r.appDown = true;
    r.detail = `${r.detail ? r.detail + '  ' : ''}[APP-DOWN after this journey: ${detail} — rerun before reading as a finding]`;
    n++;
  }
  return n;
}

// ── Exports for the rung-4 scope unit test ──────────────────────────────────
// The SQL builders are pure and exported so their behaviour can be proven against
// fixture rows without a running app. See tests/e2e/journey-rung4-scope.test.js.
// runExitCode/judgeMutant are exported for tests/wave2/test-journey-control-exit.sh, personaMismatch
// for tests/wave2/test-journey-persona.sh, the preflight/ordering set for
// tests/wave2/test-journey-preflight.sh, namedControlGaps/findControls/outcomeCheckName for
// tests/wave2/test-named-controls.sh.
module.exports = {
  sqlRowCount, sqlWatermark, whereScoped, scopeLiteral,
  sqlAssocTotal, sqlAssocLinked, sqlMustPointAt, captureScope, scopeEvidence,
  runExitCode, judgeMutant, backLeftApp, no5xxVerdict, personaMismatch, namedControlGaps, findControls, outcomeCheckName,
  classifyAdminProbe, journeyNeedsAdmin, missingEnv, preflight, orderJourneys, stateTracker,
  judgeLanding, journeyIdProblems,
  traceRung, controlMutants, forbiddenSample, probeApp, appGate, flagAppDown, LIVENESS_SKEW_MS,
  resolveDevice, runDevice, contextOptions, deviceLabel, judgeDevice, networkVerb, setNetwork, isOffline,
  ensureOnline, networkEndRow, resolveGeolocation, applyGeolocation, clearGeolocation, stepGeolocation,
  act, describeAct, pseudoTexts, pseudoVerdict, scopedWidget,
  // For fixtures that walk a journey in a real browser against a stand-in page (#564).
  runJourney, results,
};

// ── Fix-loop reruns (#492) ───────────────────────────────────────────────────
// The journeys a findings file shows as not clean: a step check, or a journey-level row
// (`<id>: …` / `<id> end state…`, setup and outcome rows), that is not PASS. An aborted run
// measured nothing usable and is refused. A journey that was never walked is recognised only by
// the row shapes the runner writes for one (app up, precondition, persona, seeds resolved, a
// control row, an end state), so a data or setup step named "Submit: …" is never read as an id.
// With `loadedIds`, ids the journeys given do not have are dropped (a renamed or removed journey).
const NEVER_WALKED = /^(\S+?)(?:: (?:app up|precondition|persona|seeds resolved|back online at the end)$| · | end state)/;
function failedJourneyIds(findings, loadedIds) {
  if (!findings || findings.aborted) return { error: `the findings file is an aborted run (${findings && findings.aborted}) — nothing to rerun from; run the journeys in full` };
  const ids = new Set();
  const walked = (findings.walks || []).map(w => w.journey);
  for (const w of findings.walks || [])
    if ((w.steps || []).some(st => (st.checks || []).some(c => c.verdict !== 'PASS'))) ids.add(w.journey);
  const known = new Set(walked);
  for (const r of findings.results || []) {
    if (r.verdict === 'PASS') continue;
    for (const id of known) if (r.name === id || r.name.startsWith(id + ':') || r.name.startsWith(id + ' ')) ids.add(id);
    const m = NEVER_WALKED.exec(r.name);   // journeys never walked (preflight, APP-DOWN, persona)
    if (m && !known.has(m[1])) ids.add(m[1]);
  }
  if (loadedIds) for (const id of [...ids]) if (!loadedIds.has(id)) ids.delete(id);
  return { ids };
}
// The chosen journeys plus every journey that leaves a token one of them requires (transitively),
// in the run's order. Unknown ids are named, never silently dropped.
function selectJourneys(journeys, wanted) {
  const byId = new Map(journeys.map(j => [j.id, j]));
  const unknown = [...wanted].filter(id => !byId.has(id));
  const pick = new Set([...wanted].filter(id => byId.has(id)));
  const added = [];
  for (let grew = true; grew;) {
    grew = false;
    for (const id of [...pick]) for (const x of byId.get(id).requires || [])
      for (const p of journeys) if ((p.leaves || []).includes(x) && !pick.has(p.id)) { pick.add(p.id); added.push(p.id); grew = true; }
  }
  return { selected: journeys.filter(j => pick.has(j.id)), added, unknown };
}
module.exports.failedJourneyIds = failedJourneyIds;
module.exports.selectJourneys = selectJourneys;

// ── Main ────────────────────────────────────────────────────────────────────
if (require.main !== module) return;
// Ends the server-side session exactly once, on every exit path: normal end, a thrown error
// (the .catch below), SIGINT/SIGTERM. The logout used to be one line after the journey loop,
// so a crash or an interrupted run skipped it and leaked a session — on a trial licence those
// accumulate until the cap refuses every login (#287: journeys that never logged out, a hung
// runner, a retry loop). Bounded, so a dead page cannot hang the exit.
let RELEASE = async () => {};
function armRelease(page, li) {
  let done = false;
  RELEASE = async () => {
    if (done || !li.ok) return;
    done = true;
    await ensureOnline(page).catch(() => {});   // an offline logout never reaches /xas/ (#521)
    const ok = await Promise.race([H.logout(page), PAUSE(5000).then(() => false)]);
    if (!ok) console.log('  ⚠ logout NOT confirmed — this run\'s session may still be open on the runtime ' +
                         '(trial licences cap live sessions; a restart clears them)');
  };
}

// An interrupted run (SIGINT/SIGTERM) writes its findings slot as aborted, with whatever it
// measured so far. Exiting without writing left the PREVIOUS run's file in the slot, reading
// as this run — the same stale-slot defect the preflight abort already guards against.
function writeAbortedFindings(reason, extra = {}) {
  try {
    fs.mkdirSync(path.dirname(findingsFile()), { recursive: true });   // --out= may name a new dir
    fs.writeFileSync(findingsFile(), JSON.stringify({
      capturedAt: new Date().toISOString(), aborted: reason,
      configuredUser: cfg.user, actualUser: extra.actualUser ?? null, usedFallback: !!extra.usedFallback,
      baseUrl: cfg.baseUrl, device: DEVICE, positiveControl: POSITIVE_CONTROL, results, walks,
    }, null, 2));
  } catch (e) { console.error(`  ⚠ could not write the aborted findings file: ${e.message}`); }
}
let SIGNAL_CTX = {};
function armSignals() {
  for (const sig of ['SIGINT', 'SIGTERM']) {
    process.once(sig, () => {
      console.log(`\n  ABORTED by ${sig} — findings written as aborted; this run is not a result.`);
      writeAbortedFindings(`signal ${sig}`, SIGNAL_CTX);
      RELEASE().finally(() => process.exit(2));
    });
  }
}

const fullSlot = () => path.join(cfg.artifactsDir,
  POSITIVE_CONTROL ? 'journey-findings-control.json' : 'journey-findings.json');
const findingsFile = () => OUT_ARG ? path.resolve(OUT_ARG)
  : PARTIAL ? fullSlot().replace(/\.json$/, '-rerun.json') : fullSlot();

// ── Named controls: every journey names its claim and ships a control (#159) ─
// The positive control proves the harness can fail; it cannot prove the claim a journey exists
// for. Field case (card-disbursement build, 2026-09-26): a journey passed every rung, its positive
// control proved every rung, and its claim ("a case waits while an upstream system is offline")
// was true only by accident; its named control read NOT PROVEN. So each journey declares
// `"claim"` and has a control file named `*.control.json` (`"control": {"of": <id>, "mustFail": ...}`)
// beside it or in controls/ beside it, run by named-controls.js. The suffix is required: every real
// walk discovers journeys as `*.journey.json` (verify-module, report-normalize, fixture-manifest),
// so a control saved under that suffix would be walked, normalized and seeded as a real journey. WARN-ONLY until a field run: printed and written
// to the findings as `namedControlGaps`, never a row, never the exit code. A control file is not
// itself checked.
function namedControlGaps(journeys, controlOf) {
  const gaps = [];
  for (const j of journeys) {
    if (j.control) continue;
    if (!j.claim) gaps.push(`${j.id}: no "claim" — name the business claim this journey exists to prove`);
    if (!controlOf.has(j.id)) gaps.push(`${j.id}: no named control — no *.control.json beside it (or in controls/) ` +
      `with control.of = "${j.id}"; write one and run named-controls.js`);
  }
  return gaps;
}

// The journey ids that have a `*.control.json` file in the given journey files' directories (and
// their controls/ subdirectories). Other names are never read as controls; unreadable JSON is
// skipped: this is a warning scan.
function findControls(journeyFiles) {
  const of = new Set();
  const dirs = new Set();
  for (const f of journeyFiles) { const d = path.dirname(path.resolve(f)); dirs.add(d); dirs.add(path.join(d, 'controls')); }
  for (const d of dirs) {
    let names = [];
    try { names = fs.readdirSync(d).filter(n => n.endsWith('.control.json')); } catch (_) { continue; }
    for (const n of names) {
      try { const c = JSON.parse(fs.readFileSync(path.join(d, n), 'utf8')).control; if (c && c.of) of.add(c.of); } catch (_) { /* not a journey */ }
    }
  }
  return of;
}
let CONTROL_GAPS = [];

// A journey with no string `id` used to run and name every capture `undefined-stepN.png`, so a
// second journey overwrote the first one's evidence (#383). A missing id now warns and falls back
// to the file basename; two journeys ending up with one id (explicit, or a colliding fallback)
// collide the same way and are refused. Sets `id` on id-less journeys. Returns { warnings,
// problems }; the caller exits 2 on any problem, before the browser opens.
function journeyIdProblems(loaded, files) {
  const warnings = [], problems = [], seen = new Map();
  const name = i => files[i] || `journey #${i + 1}`;
  const has = j => j && typeof j.id === 'string' && j.id.trim();
  const claim = (i, id) => {
    if (seen.has(id)) problems.push(`${name(i)}: journey id "${id}" is already used by ${seen.get(id)}; ids must be unique`);
    else seen.set(id, name(i));
  };
  loaded.forEach((j, i) => { if (has(j)) claim(i, j.id); });
  loaded.forEach((j, i) => {
    if (!j || has(j)) return;
    const id = path.basename(name(i)).replace(/(\.journey)?\.json$/, '') || `journey-${i + 1}`;
    warnings.push(`${name(i)}: journey has no "id"; using "${id}" (captures are named from it)`);
    j.id = id; claim(i, id);
  });
  return { warnings, problems };
}

(async () => {
  const loaded = files.map(f => JSON.parse(fs.readFileSync(f, 'utf8')));
  const { warnings: idWarnings, problems: idProblems } = journeyIdProblems(loaded, files);
  for (const l of idWarnings) console.error(`WARN ${l}`);
  if (idProblems.length) { for (const l of idProblems) console.error(`ERROR ${l}`); process.exit(2); }
  // Declared order first (requires/leaves/consumes); without headers this is file order.
  const { order: allJourneys, cycle } = orderJourneys(loaded);
  let journeys = allJourneys, partial = null;
  if (PARTIAL) {
    let wanted;
    if (ONLY_ARG) wanted = new Set(ONLY_ARG.split(',').map(x => x.trim()).filter(Boolean));
    else {
      const src = RERUN_ARG.includes('=') ? path.resolve(RERUN_ARG.slice(RERUN_ARG.indexOf('=') + 1)) : fullSlot();
      let f = null;
      try { f = JSON.parse(fs.readFileSync(src, 'utf8')); }
      catch (e) { console.error(`ERROR --rerun-failed: cannot read ${src} (${e.code || e.message}) — run the journeys in full first`); process.exit(2); }
      const r = failedJourneyIds(f, new Set(allJourneys.map(j => j.id)));
      if (r.error) { console.error(`ERROR --rerun-failed: ${r.error}`); process.exit(2); }
      wanted = r.ids;
      if (!wanted.size) { console.log(`  --rerun-failed: nothing failed in ${path.relative(cfg.root, src)} — nothing to rerun`); process.exit(0); }
    }
    const sel = selectJourneys(allJourneys, wanted);
    if (sel.unknown.length) { console.error(`ERROR no journey with id ${sel.unknown.join(', ')} among the files given`); process.exit(2); }
    journeys = sel.selected;
    partial = { of: allJourneys.length, ran: journeys.map(j => j.id), chosen: [...wanted], addedForRequires: sel.added,
                reason: ONLY_ARG ? '--only' : '--rerun-failed' };
    console.log(`  PARTIAL RUN (${partial.reason}): ${journeys.length} of ${allJourneys.length} journeys — ${partial.ran.join(', ')}` +
      (sel.added.length ? ` (added because a chosen journey requires what they leave: ${sel.added.join(', ')})` : ''));
  }
  if (allJourneys.some((j, i) => j !== loaded[i]))
    console.log(`  order from requires/leaves/consumes: ${allJourneys.map(j => j.id).join(' → ')}`);
  if (cycle)
    console.log(`  ⚠ requires/leaves/consumes form a cycle among ${cycle.join(', ')} — those keep file order`);

  // Preflight BEFORE the browser: a run that can only produce INVALIDs ends here, in one
  // line, instead of after N journeys of them.
  console.log('\n=== PREFLIGHT ===');
  const pf = preflight(journeys);
  for (const l of pf.lines) console.log(`  ${l}`);
  CONTROL_GAPS = namedControlGaps(journeys, findControls(files));
  for (const g of CONTROL_GAPS) console.log(`  WARN   named control: ${g}`);
  results.push(...pf.rows);
  if (pf.abort !== null) {
    console.log('\n=== SUMMARY ===');
    console.log(`  ABORTED at preflight — 0 of ${journeys.length} journeys walked. Fix the SETUP line(s) above.`);
    // Written, not skipped: an aborted run must not leave the previous run's file in the slot
    // reading as this one.
    writeAbortedFindings('preflight');
    console.log(`  findings → ${path.relative(cfg.root, findingsFile())}`);
    process.exit(pf.abort);
  }

  // One device per run (#521): decided before the browser opens, measured right after it does.
  const dev = runDevice(journeys, { profiles: H.deviceProfiles() });
  if (dev.problems.length) {
    for (const l of dev.problems) console.log(`  SETUP  device: ${l}`);
    console.log('\n=== SUMMARY ===\n  ABORTED at preflight — device. Fix the SETUP line(s) above.');
    writeAbortedFindings('device');
    process.exit(2);
  }
  DEVICE = deviceLabel(dev.device);

  armSignals();
  const { browser, page } = await H.launchBrowser({ contextOptions: contextOptions(dev.device) });
  if (contextOptions(dev.device)) {
    const m = await measureDevice(page);
    const jd = judgeDevice(dev.device, m);
    console.log(`  device: ${DEVICE} — measured ${m.width}x${m.height}, touch points ${m.touch}`);
    if (!jd.ok) {
      console.log(`  SETUP  device mismatch: ${jd.detail} — not signing in; every result would measure the wrong profile`);
      writeAbortedFindings('device mismatch');
      await browser.close();
      process.exit(2);
    }
  }

  const li = await H.login(page);
  armRelease(page, li);
  SIGNAL_CTX = { actualUser: li.user, usedFallback: li.usedFallback };

  // Landing check: once per run, right after login, before any click. One run signs in as
  // one role, so "N of N roles" is the count over the per-role runs.
  if (li.ok && (ASSERT_LANDING || journeys.some(j => j.assertLanding === true))) {
    const lj = judgeLanding(await collectLanding(page));
    record('ui', `landing as ${li.user}: no focus ring before any click`, lj.verdict, lj.detail);
  }
  // Identity, not presence. A silent degrade to admin bypasses the role grants the
  // journey exists to exercise, and every assertion below would be measuring an
  // access path no real user takes.
  if (!li.ok && li.fault) {
    // The runtime refused the login for a reason that is not the credential.
    // INVALID, not FAIL: nothing was measured, so there is no finding to report.
    record('ui', 'login', 'INVALID',
      `login faulted: "${li.reason}" — not a credential failure. The runtime refused ` +
      'the session (measured cause on 2026-08-18: trial-licence concurrent-session cap). ' +
      'Check the runtime log; no rung below this ran.');
  } else if (!li.ok) {
    record('ui', 'login', 'FAIL', li.reason || 'login failed');
  } else if (li.usedFallback) {
    record('ui', 'login', 'INVALID',
      `fell back to "${li.user}" instead of "${cfg.user}" — admin bypasses the role grants ` +
      'these journeys test; the whole run measures the wrong access path');
  } else {
    record('ui', 'login', 'PASS', li.user);
  }

  // Every mutant this run considered, supported or not. This is the denominator:
  // "N of M rungs proven", never a bare list of the ones that happened to work.
  const mutantLedger = [];

  const state = stateTracker(journeys);
  const assumed = state.assumed();
  if (assumed.length)
    console.log(`  requires that no journey in this run leaves (trusted to the fixture): ${assumed.join(', ')}`);

  const appDown = [], appDiedIn = [];
  const APP_PROBE = process.env.APP_PROBE !== '0';
  if (li.ok && !li.usedFallback) {
    for (const j of journeys) {
      // Already named once on the preflight SETUP line; no per-journey INVALID on top.
      if (pf.skip.has(j.id)) { state.settle(j, [], false); continue; }
      if (APP_PROBE) {
        const app = await appGate(cfg.baseUrl);
        if (!app.up) {
          console.log(`  APP-DOWN  ${j.id} — ${cfg.baseUrl} not answering (${app.detail}, ${app.tries} tries)`);
          record('setup', `${j.id}: app up`, 'INVALID',
            `APP-DOWN — ${cfg.baseUrl} did not answer before this journey (${app.detail}). Not walked; ` +
            'not a feature failure. Restart the app and rerun the APP-DOWN journeys.', (j.requirement || []).join(', '));
          results[results.length - 1].appDown = true;
          appDown.push(j.id);
          state.settle(j, [], false);
          continue;
        }
      }
      const wrongPersona = personaMismatch(j, li.user);
      if (wrongPersona) {
        record('ui', `${j.id}: persona`, 'INVALID', wrongPersona, (j.requirement || []).join(', '));
        state.settle(j, [], false);
        continue;
      }
      // A declared precondition left unmet by an earlier journey is named as such, with the
      // journey that should have left it — not a seed INVALID that reads like a data fault.
      // Walk runs only: a control run's mutants fail on purpose, so "did it complete" is moot.
      const unmet = POSITIVE_CONTROL ? null : state.gate(j);
      if (unmet) {
        record('setup', `${j.id}: precondition`, 'INVALID', unmet, (j.requirement || []).join(', '));
        state.settle(j, [], false);
        continue;
      }
      if (POSITIVE_CONTROL) {
        // Non-vacuity, per RUNG. testing-shape.md §6 asks for this and only one spec
        // in the whole corpus had ever been shown to fail when it should.
        //
        // MEASURED 2026-08-14: the previous version of this block broke exactly one
        // thing — step 1's `ready` selector — and then reported "assertions can fail"
        // for the whole journey. That green was far broader than what it tested:
        // breaking step 1 stops the walk before the trace, data and outcome rungs run,
        // so those were never challenged at all. On the live run they were 20 of the
        // 24 results. A control that only exercises the guard which stops the walk
        // proves the least interesting assertion in the harness and licenses a claim
        // about all the others.
        //
        // So: one mutant per rung, each requiring that THE TARGETED CHECK failed —
        // not merely that something did. Accepting any FAIL would let a mutant that
        // breaks by accident vouch for a rung it never reached, which is the same
        // vacuity bug one level up.
        // Mutants share one data set: nothing resets the data between them (#560).
        if ((j.consumes || []).length) {
          console.log(`  WARN   ${j.id} consumes ${j.consumes.join(', ')}: a mutant that walks past the action ` +
                      'uses that state up, so later mutants can stop INVALID ("mutant not run") — reset the data and re-run them');
        }
        for (const m of controlMutants(j)) {
          if (!m.supported) {
            // Unproven, and it must say so. INVALID is the verdict for "the
            // instrument did not run" — the summary already refuses to read
            // INVALID as green, which is exactly the treatment this deserves.
            mutantLedger.push({ journey: j.id, rung: m.rung, supported: false, why: m.why });
            record('control', `${j.id} · ${m.rung}: ${m.what}`, 'INVALID',
                   `${m.why} — this rung is UNPROVEN for ${j.id}, not passed ` +
                   '(journey-proof.md: a rung with no mutant is fault, never pass)');
            continue;
          }
          const before = results.length;
          await resetToStart(page);
          await endJourneyEnv(page, m.journey, await runJourney(page, m.journey));
          const v = judgeMutant(results.slice(before), m.expectFail);
          mutantLedger.push({ journey: j.id, rung: m.rung, supported: true, proven: v.proven });
          record('control', `${j.id} · ${m.rung}: ${m.what}`, v.verdict, v.detail);
        }
      } else {
        const before = results.length;
        await resetToStart(page);
        await endJourneyEnv(page, j, await runJourney(page, j));
        if (APP_PROBE) {
          const after = await probeApp(cfg.baseUrl);
          if (!after.up && flagAppDown(results.slice(before), after.detail)) appDiedIn.push(j.id);
        }
        state.settle(j, results.slice(before), true);
      }
    }
  }

  // Release the server-side session BEFORE closing the browser. Closing the
  // browser does not end a Mendix session; on an unlicensed runtime the leaked
  // sessions accumulate across runs until every later login is refused, and the
  // UI reports that as a wrong password. Measured 2026-08-18.
  await RELEASE();
  await browser.close();

  const n = v => results.filter(r => r.verdict === v).length;
  console.log('\n=== SUMMARY ===');
  console.log(`  PASS ${n('PASS')}   FAIL ${n('FAIL')}   INVALID ${n('INVALID')}`);
  if (n('INVALID')) {
    console.log('  ⚠ INVALID means an instrument did not run. Those checks are NOT green —');
    console.log('    they are absent. Fix the instrument before reading this report as coverage.');
  }
  if (appDown.length)
    console.log(`  APP-DOWN ${appDown.length} journey(s) not walked — the app stopped answering: ${appDown.join(', ')}. ` +
                'Restart it and rerun only these.');
  if (appDiedIn.length)
    console.log(`  ⚠ the app was down when ${appDiedIn.join(', ')} ended — their FAIL rows are flagged APP-DOWN; rerun before reading them as findings.`);

  // The control run's own denominator. Without it, 4 of 7 rungs proven and 7 of 7
  // print the same, and the second claim is the one everyone reads.
  const mutants = {
    expectedPerJourney: CONTROL_RUNGS.length,
    expected: mutantLedger.length,
    supported: mutantLedger.filter(m => m.supported).length,
    proven: mutantLedger.filter(m => m.proven).length,
    unsupported: mutantLedger.filter(m => !m.supported)
      .map(m => ({ journey: m.journey, rung: m.rung, why: m.why })),
  };
  if (POSITIVE_CONTROL) {
    console.log(`  control rungs: ${mutants.proven} of ${mutants.expected} proven ` +
                `(${CONTROL_RUNGS.length} rungs × ${journeys.length} journeys)`);
    if (mutants.unsupported.length) {
      console.log(`  ⚠ ${mutants.unsupported.length} rung(s) UNPROVEN — no mutant the journey could express:`);
      for (const u of mutants.unsupported) console.log(`      ${u.journey} · ${u.rung} — ${u.why}`);
      console.log('    Unproven is fault, not pass. Declare the missing claim on the journey,');
      console.log('    or accept that this rung has never been shown able to go red.');
    }
    console.log(runExitCode(true, results, mutants) === 0
      ? '  control verdict: PASS — every rung\'s mutant was caught; the FAIL/INVALID rows above are the mutants\''
      : '  control verdict: FAIL — at least one rung is unproven; read the [control] rows above');
  }

  fs.mkdirSync(cfg.artifactsDir, { recursive: true });
  // A control run NEVER writes to the real walk's slot.
  //
  // MEASURED 2026-08-14: it used to, and the control run silently replaced 24 real
  // results with 146 mutant ones. Nothing errored; the file was simply the wrong run
  // afterwards, and the next report would have described seven deliberately-broken
  // journeys as if they were the product. The raw evidence for that day's real walk
  // is gone — only its normalized copy in docs/report.json survived.
  //
  // These two files answer different questions ("does the app work" / "can this
  // harness tell when it doesn't") and must never share storage.
  const out = findingsFile();
  fs.mkdirSync(path.dirname(out), { recursive: true });   // --out= may name a new directory
  fs.writeFileSync(out, JSON.stringify({
    capturedAt: new Date().toISOString(),
    configuredUser: cfg.user, actualUser: li.user, usedFallback: !!li.usedFallback,
    baseUrl: cfg.baseUrl, device: DEVICE, positiveControl: POSITIVE_CONTROL, mutants, results, walks,
    appDown, appDiedIn, namedControlGaps: CONTROL_GAPS, partial,
  }, null, 2));
  console.log(`  findings → ${path.relative(cfg.root, out)}`);
  if (partial)
    console.log(`  PARTIAL RUN — ${partial.ran.length} of ${partial.of} journeys; the full findings slot is untouched. ` +
                'A fix-loop result only: the full journey run is still owed at module done, build complete and before deploy.');

  // A control run's exit ignores non-control rows, so a journey the preflight held back
  // (its mutants never ran) must still keep the control verdict from reading clean.
  process.exit(POSITIVE_CONTROL && pf.rows.length ? 1 : runExitCode(POSITIVE_CONTROL, results, mutants));
})().catch(async e => {
  console.error('ERR', e.stack?.split('\n').slice(0, 8).join('\n'));
  await RELEASE().catch(() => {});   // a crash must not leak the session either
  process.exit(1);
});
