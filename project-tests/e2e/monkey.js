'use strict';
// ============================================================================
// monkey.js — the crash net. Deliberately weighted as a net, not a defect finder.
// ----------------------------------------------------------------------------
//   node tests/e2e/monkey.js                       # all targets, random seed
//   node tests/e2e/monkey.js --seed 12345          # reproduce a previous run
//   node tests/e2e/monkey.js --target fieldscan-receive --rounds 40
//
// HONEST WEIGHTING, UP FRONT
// TFC's monkey pass scored 0 fail / 27 pass / 5 info while its scripted journeys
// found all 9 real defects. Fuzzing is not where the yield is in this stack. It is
// here to catch the crash class that journeys cannot reach — an unhandled exception
// on input nobody thought to type — and the report says so, so nobody reads a clean
// monkey run as evidence the module works.
//
// DIAGNOSTIC ONLY. It never fixes anything and never files anything. Both
// e2e-harness-base.md and module-review.md forbid unapproved fixes from a test run.
//
// REPRODUCIBILITY
// Every run prints and records MONKEY_SEED. A finding that cannot be reproduced
// cannot be triaged, and an unreproducible fuzz finding is worse than none: it burns
// a debugging session on noise.
//
// WHY PAYLOADS GO IN BASE64
// The nastier strings are XSS- and SQL-shaped by design. Shell-interpolating them
// into a command line is the exact injection the test is probing — triggered in the
// harness instead of the app, where it proves nothing and can do real damage. They
// are carried as base64 and decoded with atob() inside the page. Never build a
// payload by string-concatenating it into a Bash command.
// ============================================================================

const fs = require('fs');
const path = require('path');
const H = require(__dirname + '/helpers.js');
const O = require(__dirname + '/otel.js');
const { cfg, NAV } = require(__dirname + '/config.js');

// ── args ────────────────────────────────────────────────────────────────────
const argv = process.argv.slice(2);
const arg = (k, d) => { const i = argv.indexOf(k); return i === -1 ? d : argv[i + 1]; };
const SEED = Number(arg('--seed', process.env.MONKEY_SEED || Date.now() % 1e9));
const ROUNDS = Number(arg('--rounds', 25));
const ONLY = arg('--target', null);

// ── seeded RNG (mulberry32) ─────────────────────────────────────────────────
// Math.random() would make every finding a one-off anecdote.
function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rnd = rng(SEED);
const pick = arr => arr[Math.floor(rnd() * arr.length)];

// ── payload generators ──────────────────────────────────────────────────────
// Each returns { label, text }. Text is never shell-touched; it goes into the page
// base64-encoded (see typeSafely).
const PAYLOADS = [
  () => ({ label: 'empty',            text: '' }),
  () => ({ label: 'single space',     text: ' ' }),
  () => ({ label: 'oversized 5000ch', text: 'A'.repeat(5000) }),
  () => ({ label: 'CJK',              text: '\u5009\u5eab\u7ba1\u7406\u30b7\u30b9\u30c6\u30e0\u8a66\u9a13\u7528\u6587\u5b57\u5217' }),
  () => ({ label: 'emoji + combining', text: '🧪́́́ test' }),
  () => ({ label: 'RTL override',     text: 'abc‮def' }),
  () => ({ label: 'null-ish',         text: 'null' }),
  () => ({ label: 'numeric overflow', text: '9'.repeat(40) }),
  () => ({ label: 'negative',         text: '-1' }),
  () => ({ label: 'XSS-shaped',       text: '<img src=x onerror=alert(1)>' }),
  () => ({ label: 'script tag',       text: '<script>window.__monkey=1</script>' }),
  () => ({ label: 'SQL-shaped',       text: "'; DROP TABLE x; --" }),
  () => ({ label: 'OQL-shaped',       text: "' OR 1=1 --" }),
  () => ({ label: 'path traversal',   text: '../../../../etc/passwd' }),
  () => ({ label: 'format string',    text: '%s%n%s%n' }),
  () => ({ label: 'newlines',         text: 'a\nb\r\nc' }),
  () => ({ label: 'leading zeros',    text: '000123' }),
  () => ({ label: 'whitespace-wrapped', text: '   padded   ' }),
];

// Interaction abuses that need no text at all — historically the higher-yield half.
const ABUSES = ['doubleClick', 'backAfterSubmit', 'rapidTab', 'reloadMidFlow'];

// ── findings ────────────────────────────────────────────────────────────────
const findings = [];
function finding(severity, target, what, detail) {
  findings.push({ severity, target, what, detail: String(detail).slice(0, 400), seed: SEED });
  const c = { crash: '\x1b[31mCRASH\x1b[0m', info: '\x1b[33minfo \x1b[0m', ok: '\x1b[32mok   \x1b[0m' }[severity];
  console.log(`  ${c} ${target} · ${what}${detail ? '  — ' + detail : ''}`);
}

// ── the crash oracle ────────────────────────────────────────────────────────
// Concretely defined, because "did it crash?" is otherwise a judgement call that
// drifts between runs. Five signals, and the fifth is the one only OTel can see.
function installClientWatch(page, bucket) {
  page.on('pageerror', e => bucket.jsErrors.push(String(e.message).slice(0, 200)));
  page.on('response', r => { if (r.status() >= 500) bucket.http5xx.push(`${r.status()} ${r.url().slice(0, 120)}`); });
}

async function oracle(page, t0, bucket) {
  const hits = [];
  if (bucket.jsErrors.length) hits.push(`unhandled JS: ${bucket.jsErrors[0]}`);
  if (bucket.http5xx.length) hits.push(`HTTP 5xx: ${bucket.http5xx[0]}`);

  // Blank page: the client rendered nothing at all.
  const alive = await page.locator('.mx-page, .mx-navigationtree').first()
                          .isVisible({ timeout: 3000 }).catch(() => false);
  if (!alive) hits.push('blank page — no .mx-page or nav tree');

  // Stuck spinner: Mendix never resolved the request.
  const spinning = await page.locator('.mx-progress, .mx-dialog-progress').first()
                             .isVisible({ timeout: 1000 }).catch(() => false);
  if (spinning) {
    await page.waitForTimeout(8000);
    const still = await page.locator('.mx-progress, .mx-dialog-progress').first()
                            .isVisible({ timeout: 1000 }).catch(() => false);
    if (still) hits.push('spinner still up after 8s');
  }

  // The signal no UI check can produce: an ERROR activity span whose microflow span
  // is OK. Verified 2026-08-03 — a microflow's error handler swallows the failure,
  // the microflow reports OK, and the page renders normally over a dead integration.
  // Absent Jaeger this check does not run, and that is reported, not assumed clean.
  const spans = await O.capture(t0, { min: 1, retries: 2, waitMs: 1200 });
  if (!spans.length) {
    hits.push(null); // sentinel: see below
  } else {
    const errs = O.errorSpans(spans);
    if (errs.length) hits.push(`ERROR span: ${O.describeError(errs[0])}`);
  }
  const traceRan = spans.length > 0;
  return { hits: hits.filter(Boolean), traceRan };
}

// ── typing without shelling ─────────────────────────────────────────────────
async function typeSafely(page, handle, text) {
  const b64 = Buffer.from(text, 'utf8').toString('base64');
  await handle.evaluate((el, encoded) => {
    // decodeURIComponent(escape(atob(...))) round-trips UTF-8 through atob's latin1.
    const v = decodeURIComponent(escape(atob(encoded)));
    const setter = Object.getOwnPropertyDescriptor(el.constructor.prototype, 'value').set;
    setter.call(el, v);
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  }, b64);
}

// ── one round ───────────────────────────────────────────────────────────────
async function round(page, target, bucket) {
  bucket.jsErrors = []; bucket.http5xx = [];
  const t0 = Date.now();

  const inputs = page.locator('.mx-page input:visible, .mx-page textarea:visible');
  const buttons = page.locator('.mx-page button:visible, .mx-page .mx-button:visible');
  const nIn = await inputs.count().catch(() => 0);
  const nBtn = await buttons.count().catch(() => 0);

  let what = '';
  if (nIn > 0 && rnd() < 0.75) {
    const p = pick(PAYLOADS)();
    const el = inputs.nth(Math.floor(rnd() * nIn));
    what = `field ← ${p.label}`;
    await typeSafely(page, el, p.text).catch(() => {});
    if (nBtn > 0) await buttons.nth(Math.floor(rnd() * nBtn)).click({ force: true, timeout: 4000 }).catch(() => {});
  } else {
    const abuse = pick(ABUSES);
    what = `abuse: ${abuse}`;
    const btn = nBtn > 0 ? buttons.nth(Math.floor(rnd() * nBtn)) : null;
    if (abuse === 'doubleClick' && btn) {
      // Double-submit is the classic duplicate-record bug and one real users hit.
      await btn.click({ force: true, timeout: 4000 }).catch(() => {});
      await btn.click({ force: true, timeout: 2000 }).catch(() => {});
    } else if (abuse === 'backAfterSubmit') {
      if (btn) await btn.click({ force: true, timeout: 4000 }).catch(() => {});
      await page.waitForTimeout(1500);
      await page.goBack({ timeout: 6000 }).catch(() => {});
    } else if (abuse === 'rapidTab') {
      for (let i = 0; i < 15; i++) await page.keyboard.press('Tab').catch(() => {});
      await page.keyboard.press('Enter').catch(() => {});
    } else if (abuse === 'reloadMidFlow') {
      if (btn) btn.click({ force: true, timeout: 4000 }).catch(() => {});
      await page.waitForTimeout(300);
      await page.reload({ timeout: 15000 }).catch(() => {});
    }
  }

  await page.waitForTimeout(1800);
  const { hits, traceRan } = await oracle(page, t0, bucket);
  if (hits.length) finding('crash', target, what, hits.join(' | '));
  else finding('ok', target, what, traceRan ? '' : 'no spans — OTel arm of the oracle did NOT run');
  return traceRan;
}

// ── main ────────────────────────────────────────────────────────────────────
(async () => {
  console.log(`MONKEY_SEED=${SEED}   rounds=${ROUNDS}   (re-run exactly: --seed ${SEED})`);

  const { browser, page } = await H.launchBrowser();
  const bucket = { jsErrors: [], http5xx: [] };
  installClientWatch(page, bucket);

  const li = await H.login(page);
  if (!li.ok) { finding('crash', '(login)', 'sign in', li.reason || 'failed'); await browser.close(); process.exit(1); }
  if (li.usedFallback) {
    // Not fatal for a crash net — admin can still crash the app — but it must be on
    // the record, because admin reaches pages a real user cannot and the coverage
    // therefore does not match the persona the journeys use.
    finding('info', '(login)', 'identity',
      `fell back to "${li.user}" instead of "${cfg.user}" — monkey coverage is admin's, not the persona's`);
  }

  const targets = Object.keys(NAV).filter(k => !ONLY || k === ONLY);
  if (ONLY && !targets.length) { console.error(`no NAV target "${ONLY}" — have: ${Object.keys(NAV).join(', ')}`); process.exit(3); }

  let anyTrace = false;
  for (const key of targets) {
    // NAV entries are ['Item'] for top-level or ['Group', 'Item'] for nested —
    // navTo takes (page, parentTitle|null, childTitle).
    const nav = NAV[key];
    const [group, item] = nav.length === 1 ? [null, nav[0]] : nav;
    console.log(`\n=== ${key}`);
    await H.navTo(page, group, item).catch(() => {});
    await page.waitForTimeout(2000);
    const landed = await page.locator('.mx-page').first().isVisible({ timeout: 8000 }).catch(() => false);
    if (!landed) { finding('info', key, 'not reached', 'nav did not land — target skipped, NOT fuzzed'); continue; }
    for (let i = 0; i < Math.ceil(ROUNDS / targets.length); i++) {
      anyTrace = (await round(page, key, bucket)) || anyTrace;
    }
  }

  await browser.close();

  const crashes = findings.filter(f => f.severity === 'crash');
  console.log('\n=== MONKEY SUMMARY ===');
  console.log(`  seed ${SEED} · ${findings.length} observations · ${crashes.length} crash-class`);
  if (!anyTrace) {
    console.log('  ⚠ No spans were captured in ANY round. The OTel arm of the crash oracle');
    console.log('    never ran, so swallowed-error crashes could not have been detected.');
    console.log('    This run is a partial net, not a clean bill of health.');
  }
  console.log('  Read a clean run as "no unhandled crash on these inputs" and nothing more:');
  console.log('  scripted journeys, not fuzzing, are what find defects in this stack.');

  fs.mkdirSync(cfg.artifactsDir, { recursive: true });
  const out = path.join(cfg.artifactsDir, 'monkey-findings.json');
  fs.writeFileSync(out, JSON.stringify({
    capturedAt: new Date().toISOString(), seed: SEED, rounds: ROUNDS,
    configuredUser: cfg.user, actualUser: li.user, usedFallback: !!li.usedFallback,
    otelOracleRan: anyTrace, findings,
  }, null, 2));
  console.log(`  findings → ${path.relative(cfg.root, out)}`);

  process.exit(crashes.length ? 1 : 0);
})().catch(e => { console.error('ERR', e.stack?.split('\n').slice(0, 8).join('\n')); process.exit(1); });
