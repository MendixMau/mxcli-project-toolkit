# E2E Test Harness — Base Methodology
**Applies to:** any mxcli project.
**Purpose:** How to build a Playwright E2E test suite for a Mendix app after completing
a major build phase. Covers harness setup, widget discovery, suite structure, DB
assertions, and bug reporting.
**Source:** reference sample — 5 test suites built 2026-05, helpers.js pattern.
**Status:** Base methodology only — full skill to be written separately.

---

## When to build E2E tests

Build after completing a module build phase:
- Domain model + all microflows done
- Pages implemented and reachable via navigation
- Seed data loaded — either via an `ACT_SeedData_Run` after-startup microflow, or (the more
  common shape once a project has several modules' worth of hand-written demo data) an ordered
  set of idempotent seed SQL scripts run directly against Postgres. See "Seed-data bootstrap"
  below — the DB smoke check is now expected to self-heal a missing/fresh case rather than just
  fault the harness on it.
- App running locally (`mxcli docker run -p App.mpr --wait`)

---

## Prerequisites

- Node.js available
- Playwright installed: `npm init -y && npm i -D playwright`
- `npx playwright install chromium`
- App running at `http://localhost:8080`
- A working data-assertion instrument. **Prefer the M2EE admin API** (`mxcli oql --direct`,
  `adminPort = runtime port + 10`, token from the project's own m2ee config) — see
  `learned-db-assertions.md`. The `psql.exe` config further down is the Windows-only
  **fallback**; there is no `psql.exe` on macOS, and a harness with neither instrument has no
  data rung at all while still reporting "e2e".
- Test user credentials known (e.g. `demo.user / Demo12345`)

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
  await page.fill('#usernameInput', 'demo.user');
  await page.fill('#passwordInput', 'Demo12345');
  await page.click('#loginButton');
  await page.waitForTimeout(3500);  // wait for post-login modal

  // Navigate to target page (click through navigation, never use /p/ URLs)
  await page.click('.mx-name-btnNewOrder');  // example
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
const TEST_USER = process.env.TEST_USER || 'demo.user';
const TEST_PASS = process.env.TEST_PASS || 'Demo12345';

// DB assertion config: see `learned-db-assertions.md` for the full instrument (M2EE admin API
// first, psql fallback, and why). Do not hand-roll dbQuery() from this file alone.

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
  await page.click('.mx-name-navItemOrder');
  await page.waitForTimeout(1000);
}

// ── DB assertions ─────────────────────────────────────────────────────────────
// dbQuery() is NOT defined here. Build it per `learned-db-assertions.md`: M2EE admin API
// first (mxcli oql --direct, adminPort = runtime port + 10, token from the project's own
// m2ee config), psql only as a fallback and only where PostgreSQL is actually reachable.
// A harness with neither instrument wired has no data rung at all — say so in the run report,
// don't silently ship UI-only and call it "e2e".

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

module.exports = { chromium, login, dismissModal, navigateToOverview, /* dbQuery, see learned-db-assertions.md */ makeReporter, BASE_URL };
```

---

## Step 3 — Suite structure

Build suites in this order. Each is a separate `.js` file.

| Suite | File | What it tests |
|-------|------|--------------|
| DB smoke | `e2e-db-smoke.js` | PostgreSQL direct — seed data present, table structure correct. Self-heals: on a missing/short table it now runs the project's seed bootstrap and re-checks once, rather than just failing (see "Seed-data bootstrap" below). |
| Empty submit | `e2e-01-empty-submit.js` | All mandatory validation guards fire on empty form submit |
| Partial fill | `e2e-02-partial-fill.js` | Partial fill (30-50%) — correct errors, no crash |
| Happy path | `e2e-03-happy-path.js` | Full golden path — fill all fields, save, verify DB record |
| Robustness | `e2e-04-robustness.js` | Double-click, back button, stale data, edge cases |
| Demo | `e2e-demo.js` | Full walkthrough with screenshots — used for stakeholder demos |

**Rule: Never run two suites simultaneously.** Mendix has a session limit.
Add `sleep 5` between scripts in any batch runner.

---

## Seed-data bootstrap (before the DB smoke check is a hard gate)

**Added 2026-08-21**, after a project with several modules' worth of hand-written demo data
(a QA-sampling approval project) found its DB smoke check only ever *detected* absent seed data and failed the
whole harness on it — there was no path from "fresh clone / fresh CI runner, empty DB" back to
a runnable suite short of a human re-seeding by hand.

The fix has two parts, and both are project-repo artifacts (this skill only documents the
pattern — implement it per-project, next to that project's own seed SQL):

1. **Every per-module seed script must be idempotent.** Guard each `INSERT` with
   `WHERE NOT EXISTS (...)`, keyed on the natural/business key the journey specs
   (`journeys/*.journey.json` `seeds` blocks, or equivalent) actually resolve by — not on the
   Mendix-generated `id`, which is random per environment. See
   `.ai-context/skills/demo-data.md` (or the project's own copy of that skill) for the
   underlying ID-generation/`object_sequence`-advancement technique; the idempotency guard is
   an addition on top of that, not a replacement for it. A script guarded this way is safe to
   run against an empty DB (normal insert) or an already-seeded one (no-op) without ever
   double-inserting or throwing a unique-constraint error.
2. **One canonical, ordered runner** (e.g. `mdlsource/seed/run-all-seeds.sh`) that calls every
   per-module seed script via `psql`, in dependency order (a seed that looks up another
   module's rows by natural key — e.g. a workflow run resolving a product number — must run
   after the script that seeds those rows). Standard libpq env vars
   (`PGHOST`/`PGPORT`/`PGDATABASE`/`PGUSER`/`PGPASSWORD`) resolve the connection, with a
   `docker exec`-based fallback for the (common) case where the host's own Postgres port is
   shadowed by an unrelated local instance — see individual seed scripts' headers for that
   caveat and `demo-data.md`'s "Step 2: Connect to the Database" for the general pattern. **Do
   not trust the `.mpr`'s configured `DatabaseName` blindly** — the live dev database's actual
   name can differ from what `describe settings` reports; confirm with `psql -l` first.

`e2e-db-smoke.js` then wraps that runner as its self-heal path: check every seed-bearing table
against its expected minimum row count (the count the seed script itself inserts on a clean
run, not the live count — that grows as journeys exercise the app); if any table is missing or
short, invoke the runner once and re-check; only fail the gate (exit 1, a genuine finding) if
seed data is still missing after the bootstrap ran without error. A `psql`/DB-connectivity
failure is an instrument fault (exit 2), never a finding — same convention as the rest of this
harness (`learned-db-assertions.md`).

This turns "empty DB" from a hard fault into a one-time, automatic, idempotent catch-up step —
the harness bootstraps itself on a fresh clone or CI runner instead of requiring a human to
seed by hand before the first run.

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
    const row = dbQuery('SELECT id FROM "orderregistration$orderdetail" ORDER BY createdon DESC LIMIT 1');
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
- **DB assertions** — instrument choice, token handling, table/FK naming: see `learned-db-assertions.md` (M2EE admin API first, psql fallback only where PostgreSQL is actually reachable — do not assume the M2EE token is always randomised, read the project's own config)
