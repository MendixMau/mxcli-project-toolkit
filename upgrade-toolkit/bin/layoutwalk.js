// layoutwalk.js: open a fixed list of pages per role, save a screenshot and its layout (geometry.js) per page and width.
// Why: the screens rung reads only the smoke shots and the journey shots are too noisy to compare, so a page that shows
// the right data in a broken layout (LineApp 10.24.13 -> 11.12.6: the Task List gallery at half width) passed
// the gate. Run this on the old and the new app with the same plan, then layoutdiff.py OLD NEW (gate.sh: rung layout).
//
// Usage:
//   node layoutwalk.js --plan layout-plan.json --url http://localhost:8080 --user Role=name:pass [--user ...]
//        --out DIR [--login-path /login.html] [--widths 1024x744,1280x800]
// Plan: [{ "name": "...", "role": "...", "storage": {"key": "value"} | null, "wait": "css", "click": ["text", ...],
//          "keepDialog": true }]. storage is put in localStorage before the app loads (null: none). click texts are clicked
// in order (exact text, first visible). Error dialogs from the stand-ins (a "Close" button in a dialog that says Error)
// are closed before the shot unless keepDialog. A page that does not reach "wait" is saved as <name>-NOT-REACHED.
// Output: DIR/<w>x<h>/<name>.png and <name>.geo.json per page and width.
// Playwright: PLAYWRIGHT_DIR or ~/mendix-playwright/node_modules/playwright (the same lookup as smokewalk.js).
// Exit: 0 every page reached, 2 a page not reached, no playwright, or a usage error.
const fs = require('fs'), path = require('path'), os = require('os');
const { writeGeometry } = require('./geometry');
function loadPlaywright() {
  const dirs = [process.env.PLAYWRIGHT_DIR, path.join(os.homedir(), 'mendix-playwright/node_modules/playwright'), 'playwright'].filter(Boolean);
  for (const d of dirs) { try { return require(d); } catch (e) { /* next */ } }
  console.error('layoutwalk: playwright not found (set PLAYWRIGHT_DIR)'); process.exit(2);
}
const arg = (k, d) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : d; };
const users = {}; process.argv.forEach((a, i) => { if (a === '--user') { const [r, up] = process.argv[i + 1].split(/=(.*)/); const [u, p] = up.split(/:(.*)/); users[r] = { u, p }; } });
if (!arg('--plan') || !arg('--url') || !arg('--out')) { console.error('layoutwalk: need --plan, --url and --out'); process.exit(2); }
const pw = loadPlaywright();
const plan = JSON.parse(fs.readFileSync(arg('--plan'))), base = arg('--url'), login = arg('--login-path', '/login.html'), out = arg('--out');
const widths = arg('--widths', '1024x744,1280x800').split(',').map(s => s.split('x').map(Number));
const sleep = ms => new Promise(r => setTimeout(r, ms));
async function settle(p) {
  await p.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
  await p.waitForFunction(() => !document.querySelector('.mx-progress, .mx-progress-indicator'), null, { timeout: 15000 }).catch(() => {});
  await sleep(1500);
}
async function closeErrors(p) {
  for (let i = 0; i < 4; i++) {
    const c = p.locator('.modal-dialog:has-text("Error") button:has-text("Close"), .mx-dialog:has-text("Error") button:has-text("Close")').first();
    if (!(await c.isVisible().catch(() => false))) return;
    await c.click().catch(() => {}); await sleep(600);
  }
}
(async () => {
  const args = process.env.UPG_BROWSER_SPKI ? ['--ignore-certificate-errors-spki-list=' + process.env.UPG_BROWSER_SPKI] : [];
  const b = await pw.chromium.launch({ args }); let n = 0, reached = 0;
  for (const [w, h] of widths) for (const s of plan) {
    const dir = path.join(out, `${w}x${h}`); fs.mkdirSync(dir, { recursive: true });
    const cred = users[s.role]; if (!cred) { console.log(`SKIP ${s.name}: no --user for ${s.role}`); continue; }
    const ctx = await b.newContext({ viewport: { width: w, height: h } });
    if (s.storage) await ctx.addInitScript(st => { try { for (const k in st) localStorage.setItem(k, st[k]); } catch (e) {} }, s.storage);
    const p = await ctx.newPage(); let ok = true;
    try {
      await p.goto(base + login, { waitUntil: 'domcontentloaded' });
      await p.fill('#usernameInput', cred.u); await p.fill('#passwordInput', cred.p); await p.click('#loginButton');
      await p.waitForSelector('.mx-page', { timeout: 60000 }); await settle(p);
      if (!s.keepDialog) await closeErrors(p);
      for (const t of s.click || []) { await p.getByText(new RegExp('^\\s*' + t + '\\s*$', 'i')).first().click({ timeout: 20000 }); await settle(p); if (!s.keepDialog) await closeErrors(p); }
      await p.waitForSelector(s.wait, { timeout: 30000 }); await settle(p);
      if (!s.keepDialog) await closeErrors(p);
    } catch (e) { ok = false; console.log(`NOT-REACHED ${s.name} ${w}x${h}: ${e.message.split('\n')[0]}`); }
    const png = path.join(dir, s.name + (ok ? '' : '-NOT-REACHED') + '.png');
    await p.screenshot({ path: png }).catch(() => {}); await writeGeometry(p, png);
    n++; if (ok) reached++;
    await p.goto(base + '/logout').catch(() => {}); await ctx.close();
  }
  await b.close(); console.log(`layoutwalk: ${reached} of ${n} pages reached`); process.exit(reached === n ? 0 : 2);
})().catch(e => { console.error('layoutwalk failed:', e.message); process.exit(2); });
