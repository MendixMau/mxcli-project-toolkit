'use strict';
// ============================================================================
// GenAI configuration driver — MxCloud keys, collections, knowledge base
// ----------------------------------------------------------------------------
// There is no MDL, mxcli or SQL path for this. MxGenAIConnector stores the key
// through ACT_ConfigurationStringImport_Save, which calls the Mendix GenAI
// backend to enumerate models before it writes MxCloudDeployedModel rows. Insert
// a configuration row by hand and you get a key with no models behind it, which
// the UI renders as configured and the agents then fail on at chat time. So the
// UI is the only honest path, and this script is how we drive it.
//
// Idempotent: a key whose keyName is already in the Models/Knowledge bases grid
// is skipped, so re-running never stacks duplicate configuration rows.
// FORCE_REIMPORT=1 bypasses that guard — needed after an egress fix, because the
// backend model fetch only happens during import.
//
// Copy to the project's tests/e2e/ (next to the harness helpers.js, which does the
// login) and run against the running app:
//
//   export GenAIText="$(grep '^GenAIText=' <your .env> | cut -d= -f2-)"   # never echo it
//   GENAI_CONFIG_URL=/p/genai-resources node tests/e2e/configure-genai.js [outDir]
//
// Keys are read from the environment ONLY — never pass one on the command line
// (argv is world-readable in /proc), never commit one, never screenshot the filled
// textarea. Set only the keys the app needs; unset ones are skipped with a warning.
//
// Reaching the page. MxGenAIConnector.Configuration_Overview ("GenAI Resources") has no
// URL out of the box, so tell the script how the app reaches it:
//   GENAI_CONFIG_URL      a page URL: either the overview itself (if you gave it a Url) or a
//                         page holding a button that opens it
//   GENAI_CONFIG_BUTTON   optional: the .mx-name-<button> on that page (e.g. .mx-name-btnGenAIKeys)
// The login user (TEST_USER, read by helpers.js) needs MxGenAIConnector.Administrator.
//
// Field run 2026-10-06 (a Mendix 11.15 app, GenAI Connector 7.2.1): one text key imported,
// 1 Configuration and 9 DeployedModel rows read back by OQL.
// ============================================================================
const path = require('path');
const fs = require('fs');
const { chromium } = require('playwright');

const BASE = process.env.APP_BASE || `http://localhost:${process.env.APP_PORT || 8080}`;
const H = require('./helpers.js');               // the toolkit e2e harness: login() reads TEST_USER/TEST_PASS
const CONFIG_URL = process.env.GENAI_CONFIG_URL || null;
const CONFIG_BUTTON = process.env.GENAI_CONFIG_BUTTON || null;
const OUT = process.argv[2] || path.join(__dirname, 'artifacts', 'screenshots', 'genai-config');
fs.mkdirSync(OUT, { recursive: true });

// The MxCloud resource keys, one env var each. Order matters: the knowledge base key
// carries an embeddings resource, so importing embeddings first keeps the Models grid
// readable. A single-call agent needs only GenAIText.
const KEYS = [
  { env: 'GenAIText',  label: 'text-generation', keyName: 'GenAIText'   },
  { env: 'GenAIEmbed', label: 'embeddings',      keyName: 'GenAIEmbed'  },
  { env: 'GenAIKB',    label: 'knowledge-base',  keyName: 'GenAIKB'     },
];

let shotN = 0;
async function shot(page, name) {
  shotN += 1;
  const f = path.join(OUT, `${String(shotN).padStart(2, '0')}-${name}.png`);
  await page.screenshot({ path: f });
  console.log('  shot:', path.basename(f));
  return f;
}

// ── Mendix click quirks ──────────────────────────────────────────────────────
// Two separate interception problems, both fatal to page.click():
//   1. the nav flyout is overlapped by the page grid
//   2. every Mendix modal lays a .mx-underlay over the whole document
// Both are solved the same way: fire the DOM click directly on the real element,
// so Mendix's own handler runs without a physical pointer ever being involved.
function jsClickByText(page, scopeSel, re) {
  return page.evaluate(({ scopeSel, reSrc }) => {
    const scope = scopeSel ? document.querySelector(scopeSel) : document;
    if (!scope) return 'no-scope';
    const rx = new RegExp(reSrc, 'i');
    const b = [...scope.querySelectorAll('button')].find((x) => rx.test(x.innerText || ''));
    if (!b) return 'no-button';
    b.click();
    return 'clicked';
  }, { scopeSel, reSrc: re.source });
}

function jsClickNav(page, title) {
  return page.evaluate((t) => {
    const a = [...document.querySelectorAll('.mx-navigationtree a')]
      .find((x) => x.getAttribute('title') === t);
    if (!a) return false;
    a.scrollIntoView({ block: 'nearest' });
    a.click();
    return true;
  }, title);
}

// A Mendix "show message" dialog stacks ON TOP of the popup that triggered it and
// blocks every later click until dismissed. The import flow always raises one
// (success or warning), so read it, then clear it — and return the text, because
// "imported successfully, but no models could be retrieved" is the single most
// important signal this whole script produces and must never be swallowed.
async function drainDialogs(page, { max = 4 } = {}) {
  const seen = [];
  for (let i = 0; i < max; i += 1) {
    const dlg = page.locator('.mx-dialog, .modal-dialog').filter({ has: page.locator('button:text-is("OK")') }).first();
    if (!(await dlg.isVisible({ timeout: 1200 }).catch(() => false))) break;
    seen.push((await dlg.innerText().catch(() => '')).replace(/\s+/g, ' ').trim());
    await jsClickByText(page, null, /^OK$/);
    await page.waitForTimeout(600);
  }
  return seen;
}

async function login(page) {
  await H.login(page);
  await page.waitForTimeout(1500);
}

// The trial runtime caps concurrent sessions; a run that never logs out burns a
// slot and the NEXT run's valid password reads as "Sign in failed" in the UI.
// Always log out, even on the failure path.
async function logout(page) {
  await page.evaluate(() => window.mx && mx.logout && mx.logout()).catch(() => {});
  await page.waitForTimeout(1200);
}

// GENAI_CONFIG_URL, then GENAI_CONFIG_BUTTON if set. Proven only when the page's own
// "Import key" button is there: a wrong URL otherwise reads as "nothing to import".
async function openConfigPage(page) {
  if (!CONFIG_URL) throw new Error('Set GENAI_CONFIG_URL (and GENAI_CONFIG_BUTTON if a button opens the page): Configuration_Overview has no URL by default');
  await page.goto(BASE + CONFIG_URL);
  if (CONFIG_BUTTON) {
    await page.waitForSelector(CONFIG_BUTTON, { timeout: 60000 });
    await page.evaluate((s) => document.querySelector(s).click(), CONFIG_BUTTON);
  }
  const ok = await page.waitForFunction(() => [...document.querySelectorAll('button')].some((b) => /import key/i.test(b.innerText || '')), null, { timeout: 30000 }).then(() => true).catch(() => false);
  if (!ok) throw new Error('GenAI Resources page not reached (no "Import key" button) — check GENAI_CONFIG_URL / GENAI_CONFIG_BUTTON and that TEST_USER has MxGenAIConnector.Administrator');
}

// Switch tabs on the GenAI Resources page. Returns true if a tab matching the
// pattern was found and clicked.
function clickTab(page, re) {
  return page.evaluate((reSrc) => {
    const rx = new RegExp(reSrc, 'i');
    const t = [...document.querySelectorAll('a, li, .mx-tabcontainer-tab')]
      .find((x) => rx.test(x.innerText || ''));
    if (!t) return false;
    t.click();
    return true;
  }, re.source);
}

// Which keyNames are already registered.
//
// Do NOT select on td / [role="gridcell"] — this page renders a DataGrid2 whose
// cells match neither (a run on 2026-08-28 re-imported all three keys while the
// grid visibly listed them). Scrape the rendered text of the content area
// instead and substring-match the keyName; the key names are distinctive enough
// that a false positive is not a realistic failure mode, and the cost of a false
// NEGATIVE — a duplicate configuration row that has to be deleted in SQL — is
// much higher than the cost of a false positive.
//
// Both tabs must be read: the knowledge-base key lands on Knowledge bases, which
// is not in the DOM until its tab has been clicked.
async function registeredKeyNames(page) {
  const readText = () => page.evaluate(() => {
    const el = document.querySelector('.mx-page, .mx-name-mainGrid') || document.body;
    return el.innerText || '';
  });

  let text = await readText();
  if (await clickTab(page, /knowledge bases/)) {
    await page.waitForTimeout(2000);
    text += '\n' + (await readText());
    // Leave the page on Models — importing a key starts from there.
    if (await clickTab(page, /^\s*models\s*$/)) await page.waitForTimeout(1500);
  }
  return KEYS.filter((k) => text.includes(k.keyName)).map((k) => k.keyName);
}

(async () => {
  const missing = KEYS.filter((k) => !process.env[k.env]).map((k) => k.env);
  if (missing.length === KEYS.length) {
    console.error('No GenAI key env vars set (' + KEYS.map(k => k.env).join(', ') + '). Nothing to do.');
    process.exit(2);
  }
  if (missing.length) console.warn('WARNING: not set, will be skipped:', missing.join(', '));

  const browser = await chromium.launch({
    executablePath: process.env.CHROMIUM_PATH || undefined,
    headless: process.env.HEADED ? false : true,
  });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  page.setDefaultTimeout(25000);
  const summary = { imported: [], skipped: [], warnings: [], collections: null, indexed: null };

  try {
    await login(page);
    await openConfigPage(page);
    await shot(page, 'genai-resources-before');

    // FORCE_REIMPORT re-imports keys that are already registered. The model
    // list is only fetched during import, so after an egress/allowlist fix a
    // plain re-run would skip every key and never retry the backend call that
    // was failing. It DOES add another Configuration row per key — the page has
    // no delete affordance, so only reach for this when the models are actually
    // missing, and clean up afterwards.
    const already = process.env.FORCE_REIMPORT ? [] : await registeredKeyNames(page);
    if (process.env.FORCE_REIMPORT) console.log('FORCE_REIMPORT: idempotency guard bypassed');

    for (const k of KEYS) {
      const val = process.env[k.env];
      if (!val) continue;
      if (already.includes(k.keyName)) {
        console.log(`${k.env}: already registered as "${k.keyName}" — skipping`);
        summary.skipped.push(k.env);
        continue;
      }
      console.log(`${k.env}: importing…`);
      if ((await jsClickByText(page, '.mx-page, .mx-name-mainGrid', /import key/)) !== 'clicked') {
        throw new Error('Import key button not found on GenAI Resources');
      }
      await page.waitForSelector('.modal-dialog textarea', { timeout: 20000 });
      if (!summary.imported.length) await shot(page, 'import-key-popup');

      // The key is a secret: fill it, never screenshot the filled textarea.
      await page.fill('.modal-dialog textarea', val);
      await jsClickByText(page, '.modal-dialog', /import key/);

      // The backend round-trip (enumerate models) is the slow part.
      await page.waitForTimeout(3000);
      const msgs = await drainDialogs(page);
      msgs.forEach((m) => { console.log('   dialog:', m); summary.warnings.push(`${k.env}: ${m}`); });

      // Close the import popup if it is still standing (it does not self-close
      // when the backend call failed).
      await jsClickByText(page, '.modal-dialog', /^cancel$/);
      await page.waitForSelector('.mx-underlay', { state: 'detached', timeout: 15000 }).catch(() => {});
      await page.waitForTimeout(1200);
      summary.imported.push(k.env);
      await shot(page, `after-import-${k.label}`);
    }

    // ── Knowledge bases tab → Update collections ──
    await page.evaluate(() => {
      const t = [...document.querySelectorAll('a, li, .mx-tabcontainer-tab')]
        .find((x) => /knowledge bases/i.test(x.innerText || ''));
      if (t) t.click();
    });
    await page.waitForTimeout(2000);
    await shot(page, 'knowledge-bases-tab');

    summary.collections = await jsClickByText(page, null, /update collections/);
    console.log('Update collections:', summary.collections);
    if (summary.collections === 'clicked') {
      await page.waitForSelector('.mx-underlay', { state: 'detached', timeout: 90000 }).catch(() => {});
      (await drainDialogs(page)).forEach((m) => { console.log('   dialog:', m); summary.warnings.push('collections: ' + m); });
      await shot(page, 'after-update-collections');
    }

    // ── Optional project glue: an "Index knowledge base" button, if your app put one on this
    // page to embed its KB after the keys land. A no-op when there is none.
    summary.indexed = await jsClickByText(page, null, /index knowledge base/);
    console.log('Index knowledge base:', summary.indexed);
    if (summary.indexed === 'clicked') {
      await page.waitForSelector('.mx-underlay', { state: 'detached', timeout: 180000 }).catch(() => {});
      (await drainDialogs(page)).forEach((m) => { console.log('   dialog:', m); summary.warnings.push('index-kb: ' + m); });
      await shot(page, 'after-index-knowledge-base');
    }

    await shot(page, 'genai-resources-after');
  } finally {
    await logout(page);
    await browser.close();
  }

  console.log('\n── summary ──');
  console.log(JSON.stringify(summary, null, 2));
  fs.writeFileSync(path.join(OUT, 'summary.json'), JSON.stringify(summary, null, 2));

  // A key that imported without models is NOT a configured app: the agents will
  // render a chat panel and answer nothing. Exit non-zero so a caller notices.
  if (summary.warnings.some((w) => /no models could be retrieved/i.test(w))) {
    console.error('\nFAIL: keys stored but no models retrieved — the runtime could not reach the');
    console.error('Mendix GenAI backend. Check runtime.log for "Host not in allowlist".');
    process.exit(1);
  }
})().catch((e) => { console.error('configure-genai FAILED:', e.message); process.exit(1); });
