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
- App running locally (`mxcli docker run -p App.mpr --wait`, or `mxcli run --local` for a
  Docker-free warm loop — see § Bringing the stack up for the flag table)

---

## Prerequisites

- Node.js available
- Playwright installed: `npm init -y && npm i -D playwright`
- `npx playwright install chromium`
- App running at `http://localhost:8080` — or, when this session cannot reach that host (a
  cloud container, a devcontainer, a phone), at the public URL from `mxcli run --local --hub`.
  Point the harness `BASE_URL` at whichever one actually answers; never assume `localhost:8080`.
- A working data-assertion instrument. **Prefer the M2EE admin API** (`mxcli oql --direct`,
  `adminPort = runtime port + 10`, token from the project's own m2ee config) — see
  `learned-db-assertions.md`. The `psql.exe` config further down is the Windows-only
  **fallback**; there is no `psql.exe` on macOS, and a harness with neither instrument has no
  data rung at all while still reporting "e2e".
- Test user credentials known (e.g. `demo.user / Demo12345`)

---

## Bringing the stack up

Moved from `testing-shape.md` §5, which keeps the rule (you bring the stack up; the crash-net
scripts cannot) and a one-line list of the rules below. This is the mechanics and the field cases.

| Command | Use |
|---|---|
| `mxcli docker run` | setup, build and start in one |
| `mxcli docker status` | verify it is actually up — **do not infer "up" from the absence of an error** |
| `mxcli docker reload` | rebuild + hot reload after an exec |
| `mxcli docker down` | tear down |

**Docker-free alternative — `mxcli run --local`.** Keeps an `mxbuild --serve` process and a
standalone Mendix runtime hot: cold first build ~10-15s, then an incremental rebuild ~1s that is
hot-applied without a restart for page/microflow/text changes (entity, view and association changes
still restart the runtime — the metamodel is reconciled only at startup). Needs Mendix 11.x, JDK 21,
and a reachable PostgreSQL whose database **already exists**; no Docker daemon. Runtime stack traces
and microflow `LOG` output land in `<projectDir>/.mxcli/runtime.log` — the browser only shows a
generic dialog, so that file is where a server-side error is actually readable.

| Flag | Use |
|---|---|
| `--watch` | rebuild and hot-apply on every model change |
| `--hub` | expose the running app at a public URL through `mxcli tunnel-hub` — a chisel client reverse-tunnels out over 443 and the runtime boots with `ApplicationRootUrl` set to the hub URL, so the app works under that origin. Implies `--local`. |
| `--test-endpoint` | host mxcli's token-guarded test endpoint, so `mxcli test <files> -p <app.mpr> --attach` runs against this already-warm app — a couple of seconds instead of ~30 |

**`mxcli test … --attach` is a model write even when nothing changes.** It adds and then removes
its `MxTest` microflows, so the `.mpr` mtime moves while every unit comes back byte-identical —
and the catalog then reads stale, so `verify-module.sh`'s graph sweep FAULTs with "catalog is
stale" on a module you did not touch. Order a test-then-verify loop as: `mxcli test … --attach`
→ `./mxcli -p <app.mpr> -c 'REFRESH CATALOG FULL'` (~6 s) → `verify-module.sh`. (Field case: the
card-disbursement requirements-driven build, 2026-09, mxcli v0.24.0 — a seeding test run before
the module verify made the graph sweep FAULT until the catalog was rebuilt.)

**`--test-endpoint` writes into the working model for as long as the app runs.** It injects an
`MxTest` module, `javasource/mxtest/`, `themesource/mxtest/` and a Settings-unit change that
chains its registration after startup; a clean stop prints "test endpoint removed; project
restored". In that window `git status` shows extra model paths and the lint ratchet rises
(CUSTOM002, CONV013). So: run the build-time app **without** the flag and switch it on only for a
test window; no exec, no commit and no model restore until the clean stop. Restoring the model
under a running endpoint deletes `MxTest`, and the next `--attach` refuses with "needs a runtime
restart". After the stop, `git status` on the model must be empty. (Field case: the same build,
v0.24.0, 2026-09-26: 11 model paths with the endpoint up, back to 2 after the stop.)

**`run --local` starts with scheduled events off.** The runtime log reads "Synchronizing scheduled
events: None", so job-driven behaviour is never exercised and a journey over it can only pass
vacuously or fail for the wrong reason. Prove scheduled work in a **separate** start with
`--runtime-setting ScheduledEventExecution=ALL`: count rows over at least 2 ticks and grep the log
for the "Scheduling …" line. Keep journeys that count rows exactly on the default start, where no
timer moves the data. (Field case: the same build, Mendix 11.13.0, 2026-09-26.)

**A gate build while `run --local` serves breaks the running client.** `bin/verify-model.sh` and
exec.sh's gate run `mxbuild --target=deploy`, which rewrites `deployment/web/` and drops the
`dist/` bundle `run --local` built. The runtime keeps answering 200, but every page load 404s on
`dist/index.js`, so a journey's login hangs waiting for `.mx-page` — it reads as a login or
licence failure. The tell is `404 - file not found for file: dist%2Findex.js` in
`.mxcli/runtime.log`. Restart `run --local` after every gate build; never probe across one.
(Field case: the card-disbursement requirements-driven build, Mendix 11.13.0, 2026-09-25.)

**`--hub` is what makes a container-hosted run reachable.** A cloud/devcontainer session has no
shared filesystem with a laptop and cannot serve `localhost` to one. Before `--hub` the only answer
was a hand-rolled ngrok/cloudflared tunnel; it is now a flag.

**`mxcli test --local` does NOT leave a warm `run --local` app alone.** It uses its own ports
(8081/8091) and its own `<project>_test` database, but not its own deployment directory: mxbuild
always writes `<app dir>/deployment`, so a building test run rewrites `deployment/run/bin` under the
live app. mxcli warns ("This test run recompiles the project") but does not stop it, and the live
app then answers 200 with empty bodies or `NoClassDefFoundError` — journeys that follow fail for
reasons unrelated to the feature. **Restart `run --local` after any `test --local` run; never run a
journey across one.** `--attach` avoids the second build but hot-applies into the live app and runs
against its database, so restart before any journey that counts rows.
(Field case: existing app, mxcli v0.25, Mendix 11.15, 2026-10-07.)

**The remedy: `./bin/test-scratch.sh -- <test files> --local`.** It takes this project's exec lock
while it copies (so it never copies a half-written model), copies the model tree to a scratch dir
without `.git`, `deployment/` or `.mxcli/` (the live app's run --local record), takes a machine-wide
lock on the test ports 8081/8091 (a live holder refuses, a dead one is taken over), runs `mxcli test`
there with `-p` on the copy. The copy is a warm one that keeps its own `.mxcli` and `deployment/`
between runs (`--cold` for the gate, `--no-cache` for a throwaway), and several test files run in one
boot (`@cleanup none` files get their own); `unit-test.md` § 4a has the numbers and the limits. The live model, its `deployment/` and the running
app are never touched, so no restart is owed afterwards. It refuses `--attach`, which by design runs
against the live app. (Field case: 2026-10-12, one unlocked `mxcli test` in the live repo broke the
running app with `NoClassDefFoundError`, .mpr unchanged; #278.)

> ### 🔴 Docker is NOT a safe default if the app calls host services by `localhost`
>
> **Confirmed the hard way, 2026-08-06, on the first real run of this skill.** Inside a container,
> `localhost` is **the container**, not your machine. Measured from `docker-mendix-1`:
>
> | From inside the container | Result |
> |---|---|
> | `http://localhost:3001/...` (the mock API) | **000 — unreachable** |
> | `http://host.docker.internal:3001/...` | **200** |
>
> The microflow hardcodes `'http://localhost:3001/api/mes/core/v1/routes'`, so under Docker the REST
> call never happens. The same applies to the OTel endpoint (`localhost:4318`).
>
> **How it presents — and why it is dangerous:** an empty grid *and* an empty span set. Every trace
> assertion would pass **vacuously** on zero spans, leaving only a row-count failure, which sends
> you debugging the page. The correct verdict is ***the run is invalid***, not *the feature failed*.
>
> **Before choosing Docker, check whether the app calls anything on the host** — a mock, a collector,
> a database, any integration. If it does and the URLs are hardcoded to `localhost`, either run
> against Studio Pro's local run instead, or parameterise those URLs to `host.docker.internal`
> (**a model write** — ask first). Do not "fix" the resulting emptiness in the test.

**Three more gotchas that will otherwise be diagnosed as feature bugs:**

- **Docker has its own database.** Data assertions and demo data must target the *Docker* DB, not the
  SP-local one. Assert against the wrong database and the result is meaningless in whichever
  direction it lands.
- **Do not trust a remembered port.** Measured 2026-08-06: Docker binds **8080** — the *same* port as
  SP's Run Locally, not 8081. (8081 appears in an old log line as `ApplicationRootUrl`; it is not a
  bound port.) A suite that hardcodes `APP_PORT ||= '8081'` then hits a dead port and it looks exactly
  like "the app is broken". **Do not hardcode and do not remember: measure.** `bin/test-stack-up.sh`
  resolves the port, proves the thing answering is *this project's* Mendix, and publishes the answer
  to `.claude/loop/stack.env` for every consumer to read.
- **The admin/OQL route works — no `psql` needed for the Data rung.** Measured 2026-08-06 on Mendix
  11.13 **under Docker**: `mxcli oql --direct` on admin port `runtime+10` (8090) with the project's
  own token returned a correct row count. `learned-db-assertions.md` now leads with this; if you meet
  an older copy claiming the token route "always returns 401" on 11.10+ and mandating `psql.exe`,
  that copy is stale — the randomisation is a property of one deployment's config, not of Mendix.

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

### Scenario skeletons come from the BRD route paths

When the BRD's use cases name their prototype routes (`brd-generation.md`, `useCases[].routes`),
do not invent the happy-path and demo scenarios. Write one scenario per use case, and let its
route path be the skeleton: one step per route, one click per arrow.

WHY. The route path is the flow a stakeholder clicked through on `design/prototype.html` and
signed off. A scenario written from memory of the BRD prose tests the flow the test author
imagined, and the two drift in exactly the places that matter (the extra confirm screen, the
edit that opens from the list and not from the detail). Replaying the approved clicks makes a
failing scenario mean "the app does not do what was approved", which is a finding, instead of
"the test and the review disagree", which is an argument.

For a use case with `"routes": ["#/order-list", "#/order-detail", "#/order-edit"]`:

1. **Each route is a checkpoint.** Map it to the Mendix page it was built as through
   `design/wireframes/PAGE-MAP.tsv` (`brd-to-build-plan.md` Step 7, Navigation Wiring), and
   assert that page is showing: a widget name or the page title, never a sleep.
2. **Each arrow is a click.** The control that moves the prototype from one route to the next is
   the link in the first screen whose `href` is the second route. Read its label from the
   prototype rather than guessing it:

   ```
   node project-bin/prototype-route.js 'design/prototype.html#/order-list' | grep -o '<a[^>]*href="#/order-detail"[^>]*>[^<]*'
   ```

   Click the control with that label (or the widget its `data-bind` row names) in the live app.
3. **Everything between the clicks is the test author's.** Field fills, DB assertions and error
   cases are not in the route path and are written as in the pattern above. The path fixes the
   order of screens, not what happens on them.

```js
// UC001 Open an order: #/order-list -> #/order-detail -> #/order-edit   (F001.brd.json)
// One checkpoint per route. The selector is the page's own widget, from PAGE-MAP.tsv's page.
async function onPage(id, route, selector) {
  const ok = await page.locator(selector).first().isVisible({ timeout: 5000 }).catch(() => false);
  if (ok) R.pass(id, route); else R.fail(id, route, selector + ' not visible');
  return ok;
}
await navigateToOverview(page);
if (await onPage('UC001-1', '#/order-list', '.mx-name-gridOrders')) {          // Order_Overview
  await page.click('text=Open');                                                // the #/order-detail link
  if (await onPage('UC001-2', '#/order-detail', '.mx-name-panelOrder')) {       // Order_View
    await page.click('text=Edit');                                              // the #/order-edit link
    await onPage('UC001-3', '#/order-edit', '.mx-name-btnSave');                // Order_NewEdit
  }
}
```

Name the step ids after the use case (`UC001-2` is the second route of UC001), so a failure in
the run report points at the arrow of the approved flow that broke. A use case with no `routes`
gets a scenario written the old way and an `openQuestions` note on the BRD; a route path the
prototype can no longer walk is `brd-validation.md` check 8's finding, and is fixed there before
the scenario is written.

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
- **Stable is not unique in the DOM** — a tabbed page renders hidden panes at zero height, so `.mx-name-x` can match two nodes with the hidden one first. Use `:visible`, plain click before `force`, and poll text — `e2e-locators-that-lie.md` has the four measured defects
- **Widget names come from MDL** — the name you gave a widget in `CREATE PAGE` is the class
- **Post-login modal** — Mendix shows a "Welcome" or consent modal after login; always dismiss it
- **3.5s wait after login** — less and the modal check may race; more is safe
- **Never use `/p/` deep-links after login** — Mendix invalidates the context; navigate via clicks
- **Session limit** — one browser session at a time; Studio Pro counts as a session too
- **DB assertions** — instrument choice, token handling, table/FK naming: see `learned-db-assertions.md` (M2EE admin API first, psql fallback only where PostgreSQL is actually reachable — do not assume the M2EE token is always randomised, read the project's own config)

## Unhappy-path parts: link proxy and exactly-once check

`tests/e2e/link-proxy.js` (installed from the toolkit's `project-tests/e2e/`) is a dependency-free fault proxy to put between two apps (or a client and an app): latency, bandwidth, random loss, `down`, `request-lost`, `reply-lost` (the target processed it, the sender cannot know) and `refuse` with a status (a mode without a count applies to every request until set back to `normal`). Start it with `node tests/e2e/link-proxy.js --link hub:4042:4041 --control 4900`, drive it from a test with `client(4900, 'hub')`. `exactly-once.js` takes the ids the receiver recorded and the ids the sender submitted and reports missing, duplicated and unexpected ones. `node tests/e2e/link-proxy.selftest.js` proves both without any app. Point the app under test at the proxy port through a constant or env var, and restore it afterwards.
