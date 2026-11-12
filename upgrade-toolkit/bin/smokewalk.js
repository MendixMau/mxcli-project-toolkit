#!/usr/bin/env node
// smokewalk.js: run a smokewalk_gen.py plan against a running Mendix app with Playwright.
// Per role: log in, then for each step go home, click the menu item (or home button), wait until the
// expected page is the content form (or a popup opened), and record client errors.
// PASS    = landed on the expected page, no page error, no console error, no Mendix error dialog, and the document does
//           not show the login form or an "An error occurred" dialog (landedOk, T3-6; also checked after the home step).
// FAIL    = an error, or it landed somewhere else / nothing opened.
// INVALID = could not judge (no credentials for the role, login failed, menu link not rendered).
//
// Usage:
//   node smokewalk.js --plan plan.json --url http://localhost:8380 --user Administrator=MxAdmin:pass \
//        [--user Role=name:pass ...] [--microflows] [--out results.json] [--compare old-results.json ...] [--shots DIR]
//        [--repeat N] [--login-path /login-without-sso.html]   (T5: where the walk signs in, default /login.html, as run_journeys.py)
//   node smokewalk.js --rejudge new.json [--rejudge new2.json ...] --compare old.json [--compare ...]   (no browser: judge
//        again; several --rejudge files are pooled as the walks of one new run)
// T6R-9: one walk is a coin flip for an intermittent client error (T6R DepartmentManager Settings, React #409 "attempt to
// uninitialize widget that is not loaded yet": 2 of 3 walks of one package, 0 of 2 of the next, the old app walked once).
// --repeat N walks every role N times (default 3 for a baseline walk, 1 with --compare or --rejudge; env UPG_SMOKE_REPEAT
// overrides the default); the results keep each step's runs ("runs": [{verdict, errors}], "flaky": "n of m"), a step is
// PASS only when every run PASSed. --compare is repeatable: the old runs of all files are pooled. Per step:
//   REGRESSION                      every old run PASSed, every new run not: as before
//   REGRESSION (intermittent: n of m) every old run PASSed, n of m new runs not: still a regression (exit 1), the error
//                                   was never seen on the old app
//   FLAKY on both                   the old app failed the step in some runs, and every new failure carries only errors
//                                   the old failures had (digits ignored): not a regression, not a pass (exit 2)
//   FLAKY-BASELINE                  the old app failed the step in some runs, every new run PASSed: listed
// A new error the old runs never showed is a REGRESSION whatever the old flake rate.
// --shots DIR saves one full-page screenshot per judged step as DIR/shots-<Role>/smoke-<caption>.png, so shotdiff.py
// can pair the old and new walk by name (run both walks with --shots, then shotdiff.py OLD-DIR NEW-DIR).
// Before each click the home page is settled too (T8R-8: the walk clicked 300 ms after the home page opened, and lazy
// Charts 6 widgets were torn down mid-load). A role whose home is the login page (API-only) is SKIPPED (T8R B2-3).
// Each shot waits until the page has settled (settle.js: no progress bar or loading state, network idle, DOM stable;
// SETTLE_MS, default 15000). A page still loading after that is saved as smoke-<caption>-LOADING.png (shotdiff: INVALID);
// one whose indicator stays on a DOM that stood still is saved as -STUCK.png (shotdiff: INVALID, closable by an accept).
// A thin bar at the top edge on a page with text is not loading (settle.js TOP BAR, B4N1-14): the step says "top bar ignored".
// Roles without --user are INVALID (never silently PASS). Microflow steps are SKIPPED unless --microflows,
// because a microflow can change data. Each role logs out at the end (trial runtimes allow 6 sessions).
// Exit: 0 all judged steps PASS, 1 any FAIL (with --compare: any PASS -> not PASS regression), 2 incomplete (login failed for a role with
// credentials, an INVALID step, PASS steps lost in --compare, nothing judged) or runner error.
// Each judged step stores t0/t1 (ISO): gate.sh's smoke rung, with EXCLUDE_SYSTEMS, asks apimock.py attribute-smoke
// whether every FAIL step only failed on a call into an excluded system (E2E-14).
// Playwright: PLAYWRIGHT_DIR or ~/mendix-playwright/node_modules/playwright.
const fs = require('fs');
// BEGIN clearStaleShots
// a shots folder kept from an earlier walk may hold this step under another suffix (reached, -NOT-REACHED, -STUCK,
// -LOADING): remove those so the rung compares this walk's shot only (run2: a stale reached shot made the pair INVALID)
function clearStaleShots(d, f) {
  try {
    const base = f.replace(/(-STUCK|-LOADING|-NOT-REACHED)?\.png$/, '');
    for (const suf of ['', '-STUCK', '-LOADING', '-NOT-REACHED']) {
      if (base + suf + '.png' !== f) for (const ext of ['.png', '.txt']) fs.rmSync(path.join(d, base + suf + ext), { force: true });
    }
  } catch (e) { /* a leftover only costs a stale pair */ }
}
// END clearStaleShots
const path = require('path');
const os = require('os');
const { settle, pageSettled } = require('./settle.js');
const { topmost } = require('./journey-verbs.js');

function args() {
  const a = process.argv.slice(2), o = { users: {}, microflows: false, timeout: 15000, loginPath: '/login.html' };
  for (let i = 0; i < a.length; i++) {
    const k = a[i];
    if (k === '--plan') o.plan = a[++i];
    else if (k === '--url') o.url = a[++i].replace(/\/$/, '');
    else if (k === '--user') { const [r, cred] = a[++i].split(/=(.*)/s); const j = cred.indexOf(':'); o.users[r] = [cred.slice(0, j), cred.slice(j + 1)]; }
    else if (k === '--microflows') o.microflows = true;
    else if (k === '--out') o.out = a[++i];
    else if (k === '--compare') (o.compare = o.compare || []).push(a[++i]);
    else if (k === '--repeat') o.repeat = +a[++i];
    else if (k === '--rejudge') (o.rejudge = o.rejudge || []).push(a[++i]);
    else if (k === '--role') (o.roles = o.roles || []).push(a[++i]);
    else if (k === '--timeout') o.timeout = +a[++i];
    else if (k === '--shots') o.shots = a[++i];
    else if (k === '--login-path') { o.loginPath = a[++i]; if (!o.loginPath || o.loginPath[0] !== '/') { console.error('--login-path needs a path starting with /'); process.exit(2); } }
    else { console.error('unknown arg ' + k); process.exit(2); }
  }
  if (o.rejudge && !o.compare) { console.error('--rejudge needs --compare'); process.exit(2); }
  if (!o.rejudge && (!o.plan || !o.url)) { console.error('need --plan and --url'); process.exit(2); }
  const env = +process.env.UPG_SMOKE_REPEAT;
  if (o.repeat === undefined) o.repeat = env > 0 ? env : (o.compare || o.rejudge ? 1 : 3);
  if (!(o.repeat >= 1)) { console.error('--repeat must be 1 or more'); process.exit(2); }
  return o;
}

function loadPlaywright() {
  const dirs = [process.env.PLAYWRIGHT_DIR, path.join(os.homedir(), 'mendix-playwright/node_modules/playwright'), 'playwright'].filter(Boolean);
  for (const d of dirs) { try { return require(d); } catch (e) { /* next */ } }
  console.error('smokewalk: playwright not found (set PLAYWRIGHT_DIR)'); process.exit(2);
}

const IGNORE_CONSOLE = [/favicon/i, /Failed to load resource.*404/i];

// Page predicates for waitForFunction. Each one catches its own exceptions: right after the login redirect
// mx.session.getUserName() throws "Session is not available", and waitForFunction rejects on the FIRST throw, which
// made every role INVALID "login failed" although the login worked (E5 F9). Exported for controls/smokewalk_predicates.js.
// R1 (Purchase Request 10.24, real run): the React client has neither mx.session.getUserName nor mx.ui.getContentForm,
// so every role of a React-client app was INVALID "login failed" while each had landed on its own home page. React
// client: the user is mx.session.sessionData.user (an anonymous session has none) and the content page is
// history.state.pageName ("Module.Page", location "content"), mapped to the Dojo path "Module/Page.page.xml".
// waitForFunction serializes each predicate on its own, so the both-clients lookup is repeated inline, not shared.
function loggedIn() {
  try {
    if (!window.mx || !mx.session) return false;
    if (mx.session.getUserName) return !!(mx.session.getUserName() && mx.ui.getContentForm && mx.ui.getContentForm());
    const u = mx.session.sessionData && mx.session.sessionData.user, h = history.state;
    return !!(u && u.guid && h && h.pageName && h.params && h.params.location === 'content');
  } catch (e) { return false; }
}
function contentPath() {
  try {
    if (window.mx && mx.ui && mx.ui.getContentForm) { const f = mx.ui.getContentForm(); return (f && f.path) || null; }
    const h = history.state;
    if (!h || !h.pageName || !h.params || h.params.location !== 'content') return null;
    const i = h.pageName.indexOf('.');
    return i > 0 ? h.pageName.slice(0, i) + '/' + h.pageName.slice(i + 1) + '.page.xml' : null;
  } catch (e) { return null; }
}
function homeReady() {
  try {
    if (window.mx && mx.ui && mx.ui.getContentForm) return !!(mx.ui.getContentForm() && mx.ui.getContentForm().path);
    const h = history.state;
    return !!(window.mx && h && h.pageName && h.params && h.params.location === 'content');
  } catch (e) { return false; }
}
function landedWhere({ want }) {
  try {
    let p = null;
    if (mx.ui && mx.ui.getContentForm) { const f = mx.ui.getContentForm(); p = f && f.path; }
    else { const h = history.state, i = h && h.pageName ? h.pageName.indexOf('.') : -1;
      if (i > 0 && h.params && h.params.location === 'content') p = h.pageName.slice(0, i) + '/' + h.pageName.slice(i + 1) + '.page.xml'; }
    if (p === want) return 'content';
    const win = [...document.querySelectorAll('.mx-window')].find(w => w.offsetParent !== null);
    if (win) return 'popup';
    return false;
  } catch (e) { return false; }
}

// T3-6: "landed" is judged by what the browser SHOWS, not by the Mendix client's idea of the content form. A user that is
// not the entity the home microflow retrieves lands on the login form or an "An error occurred" dialog while
// mx.ui.getContentForm() still answers, and the step used to PASS. Returns null when the document is clean, else the
// reason (a string) that makes the step FAIL. A page that throws while being inspected is a reason too: never a silent PASS.
// A page that legitimately shows a password field (change-password) FAILs here by design: judge that step by eye.
// Runs in the browser (page.evaluate), so it uses only `document`. Exported for controls/smokewalk_predicates.js.
function landedOk() {
  try {
    const shown = e => !!e && (e.offsetParent !== null || (e.getClientRects && e.getClientRects().length > 0));
    const all = sel => [...document.querySelectorAll(sel)];
    if (all('#loginButton, .mx-name-loginButton').some(shown) || all('input[type=password]').some(shown))
      return 'login form is showing (the user is not the entity the home microflow needs, or the session ended)';
    const dlg = all('.mx-dialog, .modal-dialog, .mx-dialog-error').filter(shown)
      .find(e => /An error occurred/i.test(e.textContent || ''));
    if (dlg) return 'error dialog is showing: ' + String(dlg.textContent).replace(/\s+/g, ' ').trim().slice(0, 160);
    return null;
  } catch (e) { return 'page could not be inspected: ' + String(e && e.message || e).slice(0, 100); }
}

function loginUrl(url, loginPath) { return url + (loginPath || '/login.html'); }

async function login(page, url, user, pass, timeout, loginPath) {
  let status = 0;
  page.on('response', r => { if (r.url().endsWith('/xas/') && r.request().postData() && r.request().postData().includes('"login"')) status = r.status(); });
  await page.goto(loginUrl(url, loginPath), { waitUntil: 'domcontentloaded' });
  await page.fill('#usernameInput', user);
  await page.fill('#passwordInput', pass);
  await page.click('#loginButton');
  try {
    await page.waitForFunction(loggedIn, null, { timeout });
    return null;
  } catch (e) {
    if (status === 402) return 'login refused: license session limit (a trial runtime allows 6 sessions; end other sessions or restart the app)';
    return 'login failed (HTTP ' + status + ', still on ' + page.url() + ')';
  }
}

async function logout(page) {
  // free the session: a trial runtime only allows a few, and a closed browser does not end it
  try { await page.evaluate(() => new Promise(res => { try { mx.logout(); } catch (e) {} setTimeout(res, 1500); })); } catch (e) { /* page gone */ }
}

async function hookErrors(page, sink) {
  // record Mendix error dialogs even when they look like a normal popup
  await page.evaluate(() => {
    if (window.__swHooked) return; window.__swHooked = true; window.__swErrors = [];
    for (const k of ['error', 'exception']) {
      const orig = mx.ui[k]; if (!orig) continue;
      mx.ui[k] = function (msg) { try { window.__swErrors.push(k + ': ' + String(msg && msg.message || msg).slice(0, 300)); } catch (e) {} return orig.apply(this, arguments); };
    }
  });
}

async function goHome(page, url, timeout) {
  await page.goto(url + '/index.html', { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(homeReady, null, { timeout });
  await page.waitForTimeout(300);
  await settle(page, { timeout: Math.min(timeout, Number(process.env.SETTLE_MS || 15000)) });  // T8R-8; never throws
}

async function clickStep(page, step) {
  if (step.via === 'menu') {
    const suffix = '-' + step.menu_path.join('-');
    return await page.evaluate((suffix) => {
      const re = new RegExp('(^|\\s)mx-name-[A-Za-z0-9_]+' + suffix.replace(/-/g, '\\-') + '(\\s|$)');
      const links = [...document.querySelectorAll('a[class*="mx-name-"], li[class*="mx-name-"] > a, [class*="mx-name-"]')].filter(e => re.test(e.className));
      const vis = links.find(e => e.offsetParent !== null) || links[0];
      if (!vis) return 'menu link ' + suffix + ' not rendered';
      vis.click(); return null;
    }, suffix);
  }
  if (step.via === 'button') {
    if (!(await page.locator('.mx-name-' + step.widget).count())) return 'button .mx-name-' + step.widget + ' not rendered';
    const loc = await topmost(page, step.widget); // the page's widget, not a layout widget of the same name (R38)
    await loc.click(); return null;
  }
  return null; // home: already there
}

async function landed(page, step, before, timeout) {
  if (step.kind !== 'page') { await page.waitForTimeout(2500); return { ok: true, where: 'microflow ran' }; }
  try {
    const where = await page.waitForFunction(landedWhere, { want: step.page_path, before, via: step.via }, { timeout });
    const w = await where.jsonValue();
    await page.waitForTimeout(1500); // let widgets fetch data; late errors still count
    return { ok: true, where: w };
  } catch (e) {
    const p = await page.evaluate(contentPath).catch(() => '?');
    return { ok: false, where: 'still on ' + p };
  }
}

// ---- T6R-9: repeated walks and the compare over pooled runs (pure: controls/smokewalk_judge.js) ----
const stepKey = (role, s) => role + ' | ' + s.via + ' | ' + s.caption + ' | ' + s.target;
const stepRuns = s => s.runs || [{ verdict: s.verdict, errors: s.errors, reason: s.reason, landed: s.landed, t0: s.t0, t1: s.t1 }];
const RANK = { FAIL: 3, INVALID: 2, SKIPPED: 1, PASS: 0 };

// one error signature per error line; digits do not count (React #409, timeouts, ids); a run without error lines is
// known by its verdict and reason
function errSig(run) {
  const es = run.errors && run.errors.length ? run.errors : [run.verdict + ': ' + (run.reason || run.landed || 'no detail')];
  return es.map(e => String(e).replace(/\d+/g, '#').replace(/\s+/g, ' ').trim().slice(0, 200));
}

function roleVerdict(rr) {
  if (!rr.steps.length) return rr.verdict;
  const v = rr.steps.map(x => x.verdict);
  return v.includes('FAIL') ? 'FAIL' : v.includes('PASS') ? (v.includes('INVALID') ? 'PASS*' : 'PASS')
    : rr.apiOnly && v.every(x => x === 'SKIPPED') ? 'SKIPPED' : 'INVALID';   // an API-only role is listed, not a login failure
}

// N walks (each a results.roles list) -> one roles list; every step keeps its runs, PASS only when all runs PASSed.
// A role a walk did not ask for (absent, or "no credentials") adds no run; one whose login failed adds an INVALID run.
function mergeWalks(walks) {
  if (walks.length === 1) return walks[0];
  const asked = (w, role) => { const wr = w.find(x => x.role === role); return wr && !(wr.steps.length === 0 && /^no credentials/.test(wr.reason || '')) ? wr : null; };
  const base = JSON.parse(JSON.stringify(walks[0]));
  for (const w of walks.slice(1)) for (const wr of w) {   // a role only a later walk asked for
    const b = base.find(x => x.role === wr.role);
    if (asked(w, wr.role) && (!b || !asked([b], wr.role))) { if (b) base.splice(base.indexOf(b), 1, JSON.parse(JSON.stringify(wr))); else base.push(JSON.parse(JSON.stringify(wr))); }
  }
  const out = base;
  for (const rr of out) {
    for (const s of rr.steps) {
      const k = stepKey(rr.role, s);
      s.runs = walks.flatMap(w => {
        const wr = asked(w, rr.role);
        if (!wr) return [];
        const ws = wr.steps.find(x => stepKey(rr.role, x) === k);
        return ws ? stepRuns(ws) : [{ verdict: 'INVALID', reason: 'not walked in this run' + (wr.reason ? ': ' + wr.reason : '') }];
      });
      const bad = s.runs.filter(r => r.verdict !== 'PASS');
      const worst = bad.slice().sort((a, b) => RANK[b.verdict] - RANK[a.verdict])[0];
      s.verdict = worst ? worst.verdict : 'PASS';
      if (worst) { s.errors = worst.errors; if (worst.reason) s.reason = worst.reason; }
      if (bad.length && bad.length < s.runs.length) s.flaky = bad.length + ' of ' + s.runs.length;
    }
    rr.verdict = roleVerdict(rr);
  }
  return out;
}

// compare the new results with the pooled runs of one or more old results files: { lines, tot }
function judge(olds, results) {
  const om = new Map();
  for (const old of olds) for (const r of old.roles || []) for (const s of r.steps || []) {
    const k = stepKey(r.role, s); om.set(k, (om.get(k) || []).concat(stepRuns(s)));
  }
  const lines = [], tot = { regressions: 0, intermittent: 0, flaky_both: 0, flaky_baseline: 0, coverage_lost: 0 };
  const rate = (rs, v) => rs.filter(x => x.verdict === v).length;
  for (const r of results.roles) for (const s of r.steps) {
    const k = stepKey(r.role, s), O = om.get(k), N = stepRuns(s);
    om.delete(k);
    if (O === undefined) { lines.push('  new step ' + k + ': ' + s.verdict); continue; }
    const oldPass = rate(O, 'PASS');
    if (!oldPass) continue;   // never PASSed on the old app: a baseline defect, not a regression
    const newBad = N.filter(x => x.verdict !== 'PASS');
    const oldBad = O.filter(x => x.verdict !== 'PASS');
    if (!newBad.length) {
      if (oldBad.length) { tot.flaky_baseline++; lines.push(`  FLAKY-BASELINE ${k}: old not PASS ${oldBad.length} of ${O.length}, new PASS ${N.length} of ${N.length}`); }
      continue;
    }
    const seen = new Set(oldBad.flatMap(errSig));
    const first = errSig(newBad[0])[0];
    if (oldBad.length && newBad.every(x => errSig(x).every(e => seen.has(e)))) {
      tot.flaky_both++;
      lines.push(`  FLAKY on both ${k}: old not PASS ${oldBad.length} of ${O.length}, new ${newBad.length} of ${N.length}, same error: ${first}`);
      continue;
    }
    tot.regressions++;
    if (O.length === 1 && N.length === 1) { lines.push('  REGRESSION ' + k + ': PASS -> ' + s.verdict); continue; }
    const inter = newBad.length < N.length;
    if (inter) tot.intermittent++;
    lines.push(`  REGRESSION${inter ? ` (intermittent: ${newBad.length} of ${N.length})` : ''} ${k}: old PASS ${oldPass} of ${O.length}, `
               + `new not PASS ${newBad.length} of ${N.length}; ` + (oldBad.length ? 'error not seen on the old app: ' : '') + first);
  }
  om.forEach((rs, k) => { const p = rate(rs, 'PASS'); if (p) tot.coverage_lost++; lines.push('  step gone ' + k + ' (was ' + (p === rs.length ? 'PASS' : rs.map(x => x.verdict).join('/')) + ')'); });
  lines.push(`  PASS steps no longer judged (coverage lost): ${tot.coverage_lost}`);
  if (tot.flaky_baseline || tot.flaky_both) lines.push(`  flaky: ${tot.flaky_baseline} only on the old app (listed), ${tot.flaky_both} on both (not a regression and not a pass: exit 2; walk again or pin it)`);
  lines.push(`  regressions: ${tot.regressions}` + (tot.intermittent ? ` (${tot.intermittent} intermittent: the error never showed on the old app)` : ''));
  return { lines, tot };
}

// T8R B2-3: a role whose home page is the plan's login page (an API-only role: FSM FSMAPIConsumer, home General.Login_Web)
// signs in and is shown the login page again; that step PASSed as "content". Returns the SKIPPED reason, else null.
function apiOnlyHome(plan, s) {
  return s.via === 'home' && s.page && plan.login_page && s.page === plan.login_page
    ? 'API-only role: its home page is the login page ' + s.page + ', no signed-in home to walk' : null;
}

module.exports = { loggedIn, contentPath, homeReady, landedWhere, landedOk, pageSettled, mergeWalks, judge, errSig, apiOnlyHome, args, loginUrl };
if (require.main === module) (async () => {
  const o = args();
  let results;
  if (o.rejudge) {
    const news = o.rejudge.map(f => JSON.parse(fs.readFileSync(f, 'utf8')));
    results = Object.assign(news[0], { roles: mergeWalks(news.map(n => n.roles)) });
  } else {
    const plan = JSON.parse(fs.readFileSync(o.plan, 'utf8'));
    const { chromium } = loadPlaywright();
    const browser = await chromium.launch({ args: process.env.UPG_BROWSER_SPKI ? ['--ignore-certificate-errors-spki-list=' + process.env.UPG_BROWSER_SPKI] : [] });   // UPG_BROWSER_SPKI: trust a test broker's key only (natsfixture.py spki)
    results = { url: o.url, plan: o.plan, at: new Date().toISOString(), repeat: o.repeat, roles: [] };
    const walks = [];
    for (let walk = 0; walk < o.repeat; walk++) {
      const roles = []; walks.push(roles);
      const shots = walk === 0 ? o.shots : null;   // the screens rung pairs the first walk's shots
      for (const r of plan.roles) {
        if (o.roles && !o.roles.includes(r.role)) continue;
        const rr = { role: r.role, steps: [] }; roles.push(rr);
        const cred = o.users[r.role];
        if (!cred) { rr.verdict = 'INVALID'; rr.reason = 'no credentials (--user ' + r.role + '=name:pass)'; continue; }
        const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, screen: { width: 1440, height: 900 } }); const page = await ctx.newPage();   // desktop size like run_journeys (config.js): a field app's snippet sends screen.width <= 1280 to the Tablet profile
        try { const st = process.env.UPG_BROWSER_STORAGE ? JSON.parse(process.env.UPG_BROWSER_STORAGE) : null;   // UPG_BROWSER_STORAGE: localStorage a person's browser keeps (same for old and new)
          if (st) await ctx.addInitScript(it => { try { for (const k of Object.keys(it)) if (window.localStorage.getItem(k) === null) window.localStorage.setItem(k, it[k]); } catch (e) {} }, st); } catch (e) { /* bad JSON: no seed */ }
        let errs = [];
        page.on('pageerror', e => errs.push('pageerror: ' + String(e.message).slice(0, 300)));
        page.on('console', m => { if (m.type() === 'error' && !IGNORE_CONSOLE.some(re => re.test(m.text()))) errs.push('console: ' + m.text().slice(0, 300)); });
        const le = await login(page, o.url, cred[0], cred[1], o.timeout, o.loginPath);
        if (le) { rr.verdict = 'INVALID'; rr.reason = le; await ctx.close(); continue; }
        for (const s of r.steps) {
          const res = { caption: s.caption, kind: s.kind, via: s.via, target: s.page || s.microflow };
          rr.steps.push(res);
          if (s.kind === 'microflow' && !o.microflows) { res.verdict = 'SKIPPED'; res.reason = 'microflow (use --microflows)'; continue; }
          const api = apiOnlyHome(plan, s);
          if (api) { res.verdict = 'SKIPPED'; res.reason = api; rr.apiOnly = true; continue; }
          try {
            await goHome(page, o.url, o.timeout);
            const homeBad = await page.evaluate(landedOk).catch(e => 'page could not be inspected: ' + String(e.message).split('\n')[0]);
            if (homeBad) { res.verdict = 'FAIL'; res.errors = ['home: ' + homeBad]; continue; }
            await hookErrors(page);
            errs = [];
            const before = await page.evaluate(contentPath);
            const t0 = Date.now();
            const ce = await clickStep(page, s);
            if (ce) { res.verdict = 'INVALID'; res.reason = ce; continue; }
            const l = await landed(page, s, before, o.timeout);
            const mxErr = await page.evaluate(() => window.__swErrors || []).catch(() => []);
            const dlg = await page.evaluate(() => [...document.querySelectorAll('.mx-dialog-error, .mx-window .alert-danger')].filter(e => e.offsetParent !== null).map(e => e.textContent.trim().slice(0, 200)));
            const bad = await page.evaluate(landedOk).catch(e => 'page could not be inspected: ' + String(e.message).split('\n')[0]);
            res.ms = Date.now() - t0; res.landed = l.where;
            // E2E-14: the step's time window, matched against the API stand-in's request log (apimock.py attribute-smoke)
            res.t0 = new Date(t0).toISOString(); res.t1 = new Date().toISOString();
            res.errors = [...errs, ...mxErr.map(e => 'mx.ui.' + e), ...dlg.map(d => 'dialog: ' + d), ...(bad ? ['landed: ' + bad] : [])];
            res.verdict = l.ok && !res.errors.length ? 'PASS' : 'FAIL';
            if (shots) {
              const d = path.join(shots, 'shots-' + r.role); fs.mkdirSync(d, { recursive: true });
              // E6-17: wait until the page has settled (no progress bar or loading state, DOM stable) before the shot;
              // a page still loading is saved as -LOADING.png, which shotdiff marks INVALID instead of comparing it
              // T7-22: an indicator that stays on a DOM that stands still (empty grid, error page) is -STUCK, not -LOADING
              const st = l.ok ? await settle(page) : { ok: true };
              if (!st.ok) res.screen = (st.stuck ? 'STUCK (' : 'LOADING (') + st.reason + ', ' + st.ms + 'ms)';
              else if (st.topbar) res.screen = 'settled, ' + st.reason;   // B4N1-14: said, so a reader can check the shot
              const f = 'smoke-' + (s.caption + '-' + (s.page || s.microflow || '')).replace(/[^A-Za-z0-9_.]+/g, '_').slice(0, 90) + (l.ok ? (st.ok ? '' : st.stuck ? '-STUCK' : '-LOADING') : '-NOT-REACHED') + '.png';
              clearStaleShots(d, f);
              await page.screenshot({ path: path.join(d, f), fullPage: true }).catch(() => {});
              // NR1-25: the visible text beside the shot, so shotdiff sees a lost caption the pixels hide
              try { fs.writeFileSync(path.join(d, f.replace(/\.png$/, '.txt')), await page.evaluate(() => document.body.innerText)); } catch (e) { /* no sidecar: pixels only */ }
            }
          } catch (e) { res.verdict = 'FAIL'; res.errors = [...errs, 'runner: ' + String(e.message).split('\n')[0]]; }
        }
        rr.verdict = roleVerdict(rr);
        await logout(page);
        await ctx.close();
      }
    }
    await browser.close();
    results.roles = mergeWalks(walks);
  }

  // report
  const count = v => results.roles.reduce((n, r) => n + r.steps.filter(s => s.verdict === v).length, 0);
  const lines = [];
  for (const r of results.roles) {
    lines.push(`== ${r.role}: ${r.verdict}${r.reason ? ' (' + r.reason + ')' : ''}`);
    for (const s of r.steps) lines.push(`  ${s.verdict.padEnd(7)} ${s.via.padEnd(6)} ${s.caption} -> ${s.target}${s.flaky ? ' [not PASS in ' + s.flaky + ' walks]' : ''}${s.landed ? ' [' + s.landed + ', ' + s.ms + 'ms]' : ''}${s.reason ? ' (' + s.reason + ')' : ''}${s.screen ? ' [screen ' + s.screen + ']' : ''}${(s.errors || []).map(e => '\n            ' + e).join('')}`);
  }
  const tot = { PASS: count('PASS'), FAIL: count('FAIL'), INVALID: count('INVALID'), SKIPPED: count('SKIPPED'),
                roles_invalid: results.roles.filter(r => r.verdict === 'INVALID').length };
  results.totals = tot;
  lines.push('', `steps: PASS ${tot.PASS}, FAIL ${tot.FAIL}, INVALID ${tot.INVALID}, SKIPPED ${tot.SKIPPED}; roles not run (INVALID): ${tot.roles_invalid}`);
  if (o.compare) {
    const olds = o.compare.map(f => JSON.parse(fs.readFileSync(f, 'utf8')));
    const j = judge(olds, results);
    lines.push('', 'compare with ' + o.compare.join(', ') + ':', ...j.lines);
    Object.assign(tot, j.tot);
  }
  console.log(lines.join('\n'));
  if (o.out && !o.rejudge) fs.writeFileSync(o.out, JSON.stringify(results, null, 1));
  // 1 = something broke; 2 = could not judge everything that was asked (login failed, step INVALID, coverage lost)
  const loginFailed = results.roles.some(r => r.verdict === 'INVALID' && o.users[r.role]);
  const broke = o.compare ? tot.regressions : tot.FAIL;  // with --compare a FAIL that was already FAIL before is not new
  process.exit(broke ? 1 : (!tot.PASS || tot.INVALID || loginFailed || tot.coverage_lost || tot.flaky_both ? 2 : 0));
})().catch(e => { console.error('smokewalk: ' + e.stack); process.exit(2); });
