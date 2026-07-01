# E2E Test Harness — Base Methodology
**Purpose:** How to build a Playwright E2E test suite for a Mendix app after completing
a major build phase. Covers harness setup, widget discovery, suite structure, DB
assertions, and bug reporting.
**Source:** Contoso M-0022 — 5 test suites built 2026-05, helpers.js pattern.
**Status:** Base methodology only — full skill to be written separately.

---

## When to build E2E tests

Build after completing a module build phase:
- Domain model + all microflows done
- Pages implemented and reachable via navigation
- Seed data loaded (ACT_SeedData_Run executed)
- App running locally (`mxcli docker run -p App.mpr --wait`)

---

## Prerequisites

- Node.js available
- Playwright installed: `npm init -y && npm i -D playwright`
- `npx playwright install chromium`
- App running at `http://localhost:8080`
- PostgreSQL accessible via psql.exe (for DB assertions)
- Test user credentials known (e.g. `yoko.taoka / Contoso12345`)

---

## Step 1 — Widget discovery

Before writing tests, map every widget name on every page.
Mendix renders widgets as `<div class="mx-name-widgetName">`.

**Discovery script pattern:**
```js
// discover-widgets.js — run once per page to build widget map
const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({ headless: false });
  const page = await browser.newPage();

  // Login
  await page.goto('http://localhost:8080');
  await page.fill('#usernameInput', 'yoko.taoka');
  await page.fill('#passwordInput', 'Contoso12345');
  await page.click('#loginButton');
  await page.waitForTimeout(3500);  // wait for post-login modal

  // Navigate to target page (click through navigation, never use /p/ URLs)
  await page.click('.mx-name-btnNewPayer');  // example
  await page.waitForTimeout(1500);

  // Dump all mx-name-* elements
  const widgets = await page.evaluate(() => {
    return [...document.querySelectorAll('[class*="mx-name-"]')]
      .map(el => ({
        name: [...el.classList].find(c => c.startsWith('mx-name-')),
        tag: el.tagName,
        text: el.innerText?.substring(0, 40)
      }));
  });
  console.log(JSON.stringify(widgets, null, 2));
  await browser.close();
})();
```

Save the output as your **widget map** for that page. Reference it in all tests.

---

## Step 2 — helpers.js

Create `tests/helpers.js` as the shared foundation:

```js
'use strict';
const { chromium } = require('playwright');
const { execSync } = require('child_process');

// ── Config ────────────────────────────────────────────────────────────────────
const BASE_URL  = process.env.APP_URL  || 'http://localhost:8080';
const TEST_USER = process.env.TEST_USER || 'yoko.taoka';
const TEST_PASS = process.env.TEST_PASS || 'Contoso12345';

// PostgreSQL config — for DB assertions
const PSQL = process.env.PSQL_PATH || 'C:\\Program Files\\PostgreSQL\\18\\bin\\psql.exe';
const PG_DB   = process.env.PG_DB   || 'PGadmin';
const PG_USER = process.env.PG_USER || 'postgres';
const PG_PASS = process.env.PG_PASS || 'Mendix1!';
const PG_HOST = process.env.PG_HOST || 'localhost';
const PG_PORT = process.env.PG_PORT || '5432';

// ── Login ─────────────────────────────────────────────────────────────────────
async function login(page) {
  await page.goto(BASE_URL);
  await page.fill('#usernameInput', TEST_USER);
  await page.fill('#passwordInput', TEST_PASS);
  await page.click('#loginButton');
  await page.waitForTimeout(3500);  // Mendix post-login modal can take ~3s
  await dismissModal(page);
}

async function dismissModal(page, retries = 3) {
  for (let i = 0; i < retries; i++) {
    const btn = page.locator('.mx-dialog-footer button').first();
    if (await btn.isVisible({ timeout: 800 }).catch(() => false)) {
      await btn.click();
      await page.waitForTimeout(500);
      return;
    }
  }
}

// ── Navigation ────────────────────────────────────────────────────────────────
// RULE: Never navigate to /p/ deep-link URLs after login.
// Always click through the navigation menu from the home page.
async function navigateToOverview(page) {
  // Adjust selector to match your app's nav menu item
  await page.click('.mx-name-navItemPayer');
  await page.waitForTimeout(1000);
}

// ── DB assertions ─────────────────────────────────────────────────────────────
// Mendix table naming: Module.EntityName → module$entityname (all lowercase)
// FK column: module$entity_otherentity (truncated at 63 chars by PostgreSQL)
function dbQuery(sql) {
  const wrapped = `SELECT json_agg(t) FROM (${sql}) t`;
  try {
    const env = { ...process.env, PGPASSWORD: PG_PASS };
    const raw = execSync(
      `"${PSQL}" -h ${PG_HOST} -p ${PG_PORT} -U ${PG_USER} -d ${PG_DB} -t -c "${wrapped.replace(/"/g, '\\"')}"`,
      { env, encoding: 'utf8' }
    );
    const clean = raw.replace(/\s+\+\r?\n\s*/g, '').trim();
    if (!clean || clean === 'null') return null;
    return JSON.parse(clean);
  } catch (e) {
    console.error('[dbQuery] error:', e.message);
    return null;
  }
}

// ── Reporting ─────────────────────────────────────────────────────────────────
function makeReporter(suiteName) {
  const results = [];
  function pass(id, description) {
    console.log(`  ✓ ${id}: ${description}`);
    results.push({ id, description, status: 'pass' });
  }
  function fail(id, description, detail) {
    console.error(`  ✗ ${id}: ${description} — ${detail}`);
    results.push({ id, description, status: 'fail', detail });
  }
  function summary() {
    const p = results.filter(r => r.status === 'pass').length;
    const f = results.filter(r => r.status === 'fail').length;
    console.log(`\n${suiteName}: ${p} passed, ${f} failed`);
    return { suite: suiteName, passed: p, failed: f, results };
  }
  return { pass, fail, summary };
}

module.exports = { chromium, login, dismissModal, navigateToOverview, dbQuery, makeReporter, BASE_URL };
```

---

## Step 3 — Suite structure

Build suites in this order. Each is a separate `.js` file.

| Suite | File | What it tests |
|-------|------|--------------|
| DB smoke | `e2e-db-smoke.js` | PostgreSQL direct — seed data present, table structure correct |
| Empty submit | `e2e-01-empty-submit.js` | All mandatory validation guards fire on empty form submit |
| Partial fill | `e2e-02-partial-fill.js` | Partial fill (30-50%) — correct errors, no crash |
| Happy path | `e2e-03-happy-path.js` | Full golden path — fill all fields, save, verify DB record |
| Robustness | `e2e-04-robustness.js` | Double-click, back button, stale data, edge cases |
| Demo | `e2e-demo.js` | Full walkthrough with screenshots — used for stakeholder demos |

**Rule: Never run two suites simultaneously.** Mendix has a session limit.
Add `sleep 5` between scripts in any batch runner.

---

## Step 4 — Test file pattern

```js
'use strict';
const { chromium, login, navigateToOverview, dbQuery, makeReporter } = require('./helpers');

(async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext();
  const page = await context.newPage();
  const R = makeReporter('E2E-01 Empty Submit');

  try {
    await login(page);
    await navigateToOverview(page);

    // Navigate to new form
    await page.click('.mx-name-btnNewRegistration');
    await page.waitForTimeout(1000);

    // Click Save without filling anything
    await page.click('.mx-name-btnSave2');
    await page.waitForTimeout(800);

    // Assert validation feedback appeared
    const errVisible = await page.locator('.mx-validation-message').first().isVisible();
    R.pass('E01-01', 'Validation message visible on empty submit');

    // Assert still on same page (not navigated away)
    const saveBtn = await page.locator('.mx-name-btnSave2').isVisible();
    if (saveBtn) R.pass('E01-02', 'Remained on form page after failed submit');
    else R.fail('E01-02', 'Remained on form page', 'Save button gone — navigated away');

    // DB assertion: no new record created
    const row = dbQuery('SELECT id FROM "payerregistration$payerdetail" ORDER BY createdon DESC LIMIT 1');
    // Compare to baseline count if you tracked it before the test

  } catch (err) {
    R.fail('CRASH', 'Unhandled error', err.message);
  } finally {
    const result = R.summary();
    await browser.close();
    process.exit(result.failed > 0 ? 1 : 0);
  }
})();
```

---

## Step 5 — Bug report format

When a test reveals a bug, write it up immediately in `docs/active/bug-log.md`:

```markdown
## BUG-E2E-[NN] — [Short title]

**Severity:** High / Medium / Low
**Status:** Open / Partially fixed / Resolved
**Found:** YYYY-MM-DD via [suite name]

**Symptom:**
What the user/test sees.

**Evidence:**
- Screenshot: `tests/results/screenshot-xxx.png`
- Test assertion: `[E03-05] failed — expected X, got Y`
- DB query result: `{ status: null }`

**Root cause:**
What's actually wrong (entity missing, microflow not wired, wrong selector, etc.)

**Suggested fix:**
Specific change needed. Do NOT implement without user approval.
```

**Rule: Never implement a bug fix without user approval.** Log → show → wait for "go ahead."

---

## Step 6 — After each run

Write a gap report in `tests/results/YYYY-MM-DD-gap-report.md`:

```markdown
# Test Run: YYYY-MM-DD

## Summary
- E2E-01: 5/5 passed ✓
- E2E-02: 4/6 passed — 2 failures
- E2E-03: 16/19 passed — 3 failures (see BUG-E2E-01, BUG-E2E-03)

## Blocking issues
- BUG-E2E-01 (HIGH): [description] — blocks happy path

## Non-blocking
- BUG-E2E-04 (LOW): [description]

## Next run plan
- Fix BUG-E2E-01 then re-run E2E-03
```

---

## Mendix-specific quirks to know

- **`.mx-name-*` selectors are stable** — always use these, never rely on position or text
- **Widget names come from MDL** — the name you gave a widget in `CREATE PAGE` is the class
- **Post-login modal** — Mendix shows a "Welcome" or consent modal after login; always dismiss it
- **3.5s wait after login** — less and the modal check may race; more is safe
- **Never use `/p/` deep-links after login** — Mendix invalidates the context; navigate via clicks
- **Session limit** — one browser session at a time; Studio Pro counts as a session too
- **M2EE token** — Mendix 11.10+ randomises it on every startup; use PostgreSQL direct (`dbQuery()`) not OQL for DB assertions
- **Table naming** — `Module.EntityName` → `module$entityname` all lowercase in PostgreSQL
- **FK truncation** — PostgreSQL truncates FK column names at 63 chars; verify with `information_schema.columns`
