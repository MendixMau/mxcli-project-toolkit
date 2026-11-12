// Control for E5 F9: the smokewalk wait predicates must return false (not throw) while the Mendix session is not
// available yet, and true once it is. Playwright's waitForFunction rejects on the first throw, which made every role
// INVALID one second after a login that worked. Runs in plain node with a fake window/mx; exit 0 = pass.
const { loggedIn, contentPath, homeReady, landedWhere, landedOk, pageSettled, apiOnlyHome } = require('../bin/smokewalk.js');
let fail = 0;
const check = (name, got, want) => {
  const ok = got === want;
  if (!ok) fail++;
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);
};
global.document = { querySelectorAll: () => [] };
// catch case: session not available, getUserName throws (the real 9.24 behaviour right after the login redirect)
global.window = global;
global.mx = { session: { getUserName() { throw new Error('Session is not available'); } }, ui: { getContentForm() { throw new Error('no form'); } } };
check('loggedIn while session throws', loggedIn(), false);
check('homeReady while form throws', homeReady(), false);
check('landedWhere while form throws', landedWhere({ want: 'P/Home.page.xml' }), false);
// catch case: mx not defined at all
delete global.mx;
check('loggedIn without mx', loggedIn(), false);
// pass case: logged in, home form loaded
global.mx = { session: { getUserName: () => 'smoke_user' }, ui: { getContentForm: () => ({ path: 'P/Home.page.xml' }) } };
check('loggedIn when ready', loggedIn(), true);
check('homeReady when ready', homeReady(), true);
check('landedWhere on the wanted page', landedWhere({ want: 'P/Home.page.xml' }), 'content');
// R1: React client (no getUserName / getContentForm). catch case: anonymous session on the login page
global.mx = { session: { sessionData: { user: null } }, ui: {} };
global.history = { state: null };
check('react loggedIn when anonymous', loggedIn(), false);
check('react contentPath without page', contentPath(), null);
// catch case: a page in a popup is not the content page
global.mx = { session: { sessionData: { user: { guid: '1' } } }, ui: {} };
global.history = { state: { pageName: 'P.Home', params: { location: 'popup' } } };
check('react landedWhere on a popup state', landedWhere({ want: 'P/Home.page.xml' }), false);
// pass case: signed in, home page in content (shape seen on a real 10.24 React-client app)
global.history = { state: { pageName: 'P.Home', params: { location: 'content', url: '/p/home' } } };
check('react loggedIn when ready', loggedIn(), true);
check('react homeReady when ready', homeReady(), true);
check('react contentPath maps to the page path', contentPath(), 'P/Home.page.xml');
check('react landedWhere on the wanted page', landedWhere({ want: 'P/Home.page.xml' }), 'content');
check('react landedWhere on another page', landedWhere({ want: 'P/Other.page.xml' }), false);
delete global.history;
// E6-17 settle predicate. catch case: the Mendix progress bar is shown (the old MonitoringDashboard smoke shot)
const el = (cls, shown) => ({ className: cls, getClientRects: () => (shown ? [1] : []), style: { display: 'block' } });
global.document = { body: { innerHTML: 'x'.repeat(100) },
  querySelectorAll: sel => [el('mx-progress', true), el('mx-dataview-loading', false)].filter(e => sel.includes('.' + e.className)) };
check('pageSettled while progress bar shown', pageSettled().busy.join(','), 'mx-progress');
// pass case: the loading elements exist but are hidden (Mendix keeps some in the DOM)
global.document = { body: { innerHTML: 'x'.repeat(100) },
  querySelectorAll: sel => [el('mx-progress', false), el('spinner', false)].filter(e => sel.includes('.' + e.className)) };
check('pageSettled when loaders hidden', pageSettled().busy.length, 0);
check('pageSettled reports DOM size', pageSettled().size, 100);

// T3-6 landedOk: the step is judged by what the browser SHOWS. Static HTML in a real Chromium (the same engine the walk uses);
// without Playwright the same predicate runs on a fake document so the control never goes silent.
const PAGES = {
  'login form page': ['<form><input id="usernameInput"><input type="password" id="passwordInput"><button id="loginButton">Sign in</button></form>', /login form/],
  'custom login page (mx-name-loginButton)': ['<div><button class="mx-name-loginButton btn">Login</button></div>', /login form/],
  'password field only': ['<div class="mx-name-container1"><input type="password"></div>', /login form/],
  'error dialog': ['<div class="modal-dialog"><div class="modal-content"><h4>An error occurred</h4><p>Retrieve failed</p></div></div>', /error dialog is showing: An error occurred/],
  'mx error dialog class': ['<div class="mx-dialog mx-dialog-error"><div>An error occurred while ...</div></div>', /error dialog is showing/],
  'clean page': ['<div class="mx-name-page1"><h1>Home</h1><div class="mx-dialog" style="display:none">An error occurred (hidden template)</div><button class="mx-name-loginButtonLookalike2">Not login</button></div>', null],
  'other dialog': ['<div class="modal-dialog"><div class="modal-content">Are you sure you want to delete?</div></div>', null],
  'hidden login form': ['<form style="display:none"><input type="password"><button id="loginButton"></button></form><h1>Home</h1>', null],
};
function pwLoad() {
  for (const d of [process.env.PLAYWRIGHT_DIR, '/opt/node-tools/node_modules/playwright', require('path').join(require('os').homedir(), 'mendix-playwright/node_modules/playwright'), 'playwright'].filter(Boolean)) {
    try { return require(d); } catch (e) { /* next */ }
  }
  return null;
}
(async () => {
  const pw = pwLoad(); let browser = null;
  try { if (pw) browser = await pw.chromium.launch(); } catch (e) { browser = null; }
  if (browser) {
    const page = await browser.newPage();
    for (const [name, [html, want]] of Object.entries(PAGES)) {
      await page.setContent('<!doctype html><body>' + html + '</body>');
      const got = await page.evaluate(landedOk);
      const ok = want === null ? got === null : typeof got === 'string' && want.test(got);
      if (!ok) fail++;
      console.log(`${ok ? 'ok  ' : 'FAIL'} landedOk ${name} (chromium): ${want === null ? 'PASS' : 'FAIL'} wanted, got ${JSON.stringify(got)}`);
    }
    await browser.close();
  } else console.log('note  landedOk: no Playwright/Chromium here, fake document only');
  // fake document, always: login form -> reason, error dialog -> reason, clean -> null, inspection throws -> reason (never null)
  const fake = (items) => ({ querySelectorAll: sel => items.filter(i => sel.split(',').some(s => i.sel === s.trim())) });
  const shown = (sel, text) => ({ sel, textContent: text || '', offsetParent: {}, getClientRects: () => [1] });
  const hidden = (sel, text) => ({ sel, textContent: text || '', offsetParent: null, getClientRects: () => [] });
  global.document = fake([shown('#loginButton')]);
  check('landedOk fake login form', /login form/.test(landedOk() || ''), true);
  global.document = fake([shown('.mx-dialog', 'An error occurred')]);
  check('landedOk fake error dialog', /error dialog/.test(landedOk() || ''), true);
  global.document = fake([hidden('#loginButton'), hidden('input[type=password]'), hidden('.mx-dialog', 'An error occurred'), shown('.mx-dialog', 'Saved')]);
  check('landedOk fake clean page', landedOk(), null);
  global.document = { querySelectorAll() { throw new Error('boom'); } };
  check('landedOk when inspection throws is not a pass', /could not be inspected/.test(landedOk() || ''), true);
  // T8R B2-3: a home step on the plan's login page is SKIPPED as an API-only role, other home pages are walked
  const lp = { login_page: 'General.Login_Web' };
  check('apiOnlyHome login page home', /API-only role/.test(apiOnlyHome(lp, { via: 'home', page: 'General.Login_Web' }) || ''), true);
  check('apiOnlyHome ordinary home', apiOnlyHome(lp, { via: 'home', page: 'General.Home' }), null);
  check('apiOnlyHome menu step to the login page', apiOnlyHome(lp, { via: 'menu', page: 'General.Login_Web' }), null);
  check('apiOnlyHome no model login page', apiOnlyHome({ login_page: '' }, { via: 'home', page: 'General.Login_Web' }), null);
  // T7R-12, T8R-8: --repeat never clears a FAIL by luck: FAIL then PASS is FLAKY, FAIL on every attempt stays FAIL
  process.exit(fail ? 1 : 0);
})();
