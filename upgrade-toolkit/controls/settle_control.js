// Control for E6-17: settle() must not report a page as settled while a loading indicator is shown or the DOM still
// changes, and must report it settled once both stop. Fake Playwright page, plain node; exit 0 = pass.
const { settle } = require('../bin/settle.js');
const fake = states => {
  let i = 0;
  return { waitForLoadState: async () => {}, waitForTimeout: async () => {},
           evaluate: async () => states[Math.min(i++, states.length - 1)] };
};
let fail = 0;
const check = (name, ok, detail) => { if (!ok) fail++; console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}: ${detail}`); };
(async () => {
  // waitForTimeout is a no-op, so time only passes in real ms; use small windows
  let r = await settle(fake([{ busy: ['mx-progress'], size: 10 }]), { timeout: 300, stableMs: 0 });
  check('progress bar never goes away -> not settled', !r.ok && /still loading: mx-progress/.test(r.reason), JSON.stringify(r));
  let n = 0;
  const growing = { waitForLoadState: async () => {}, waitForTimeout: async () => {}, evaluate: async () => ({ busy: [], size: n++ }) };
  r = await settle(growing, { timeout: 300, stableMs: 0 });
  check('DOM keeps changing -> not settled', !r.ok && /DOM still changing/.test(r.reason), JSON.stringify(r));
  r = await settle(fake([{ busy: ['mx-progress'], size: 10 }, { busy: [], size: 50 }, { busy: [], size: 80 }, { busy: [], size: 80 }]), { timeout: 2000, stableMs: 0 });
  check('loads, then stable -> settled', r.ok, JSON.stringify(r));
  // T7-22: the indicator stays on a DOM that stands still (empty 10.6 Data grid 2, error page) -> STUCK, not LOADING
  r = await settle(fake([{ busy: ['mx-progress'], size: 10 }]), { timeout: 300, stableMs: 0, stuckMs: 100 });
  check('indicator stays, DOM still -> stuck', !r.ok && r.stuck === true && /stuck: mx-progress/.test(r.reason), JSON.stringify(r));
  let k = 0;
  const busyGrowing = { waitForLoadState: async () => {}, waitForTimeout: async () => {}, evaluate: async () => ({ busy: ['mx-progress'], size: k++ }) };
  r = await settle(busyGrowing, { timeout: 300, stableMs: 0, stuckMs: 100 });
  check('indicator stays, DOM changing -> loading, not stuck', !r.ok && !r.stuck && /still loading/.test(r.reason), JSON.stringify(r));
  // B4N1-14: a thin bar at the top edge (UMC session renew) on a page that rendered: settled, said so
  const T = { busy: [], topbar: ['mx-progress-line'], size: 10 };
  r = await settle(fake([Object.assign({}, T, { text: 22 })]), { timeout: 2000, stableMs: 0, stuckMs: 100, topbarMs: 100 });
  check('top bar only, page has text, DOM still -> settled (top bar ignored)', r.ok && r.topbar === true && /top bar ignored: mx-progress-line/.test(r.reason), JSON.stringify(r));
  r = await settle(fake([Object.assign({}, T, { text: 0 })]), { timeout: 300, stableMs: 0, stuckMs: 100, topbarMs: 100 });
  check('top bar only, blank page -> stuck, not settled', !r.ok && r.stuck === true && /stuck: mx-progress-line/.test(r.reason), JSON.stringify(r));
  r = await settle(fake([Object.assign({}, T, { text: 22, busy: ['widget-datagrid-loading'] })]), { timeout: 300, stableMs: 0, stuckMs: 100, topbarMs: 100 });
  check('top bar plus a grid loading state -> stuck, not settled', !r.ok && r.stuck === true && /widget-datagrid-loading/.test(r.reason), JSON.stringify(r));
  let g = 0;
  const topGrowing = { waitForLoadState: async () => {}, waitForTimeout: async () => {}, evaluate: async () => Object.assign({}, T, { text: 22, size: g++ }) };
  r = await settle(topGrowing, { timeout: 300, stableMs: 0, stuckMs: 100, topbarMs: 100 });
  check('top bar, DOM still changing -> loading, not settled', !r.ok && !r.stuck && /still loading: mx-progress-line/.test(r.reason), JSON.stringify(r));
  // the same in a real Chromium when there is one: the predicate measures the box, not a fake
  let pw = null;
  for (const d of [process.env.PLAYWRIGHT_DIR, '/opt/node-tools/node_modules/playwright', 'playwright'].filter(Boolean)) { try { pw = require(d); break; } catch (e) { /* next */ } }
  let browser = null;
  try { if (pw) browser = await pw.chromium.launch(); } catch (e) { browser = null; }
  if (browser) {
    const page = await browser.newPage();
    const BAR = '<div class="mx-progress-line" style="position:fixed;top:0;left:0;width:100%;height:4px;background:#ddd"><div style="margin-left:40%;width:10%;height:4px;background:#3a9"></div></div>';
    const CASES = [
      ['rendered page under a persistent top bar', '<div class="mx-placeholder"><h1>Contents</h1><div>Modules</div></div>' + BAR, x => x.ok && x.topbar],
      ['blank page under the same bar', '<div class="mx-placeholder"></div>' + BAR, x => !x.ok && x.stuck],
      ['centred progress box over a page with text', '<div class="mx-placeholder"><h1>Contents</h1></div><div class="mx-progress" style="position:fixed;top:200px;left:40%;width:250px;height:42px"></div>', x => !x.ok && x.stuck && !x.topbar],
      ['top bar 30px high is no thin bar', '<div class="mx-placeholder"><h1>Contents</h1></div><div class="mx-progress-line" style="position:fixed;top:0;width:100%;height:30px"></div>', x => !x.ok && !x.topbar],
    ];
    for (const [n, html, want] of CASES) {
      await page.setContent('<!doctype html><body>' + html + '</body>');
      const x = await settle(page, { timeout: 2500, stableMs: 0, stuckMs: 500, topbarMs: 500 });
      check(n + ' (chromium)', !!want(x), JSON.stringify(x));
    }
    await browser.close();
  } else console.log('note  settle top bar: no Playwright/Chromium here, fake page only');
  process.exit(fail ? 1 : 0);
})();
