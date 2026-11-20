'use strict';
// ############################################################################
// ============================================================================
// project.config.js — THE ONLY FILE IN tests/e2e/ THAT KNOWS WHICH PROJECT
//                     THIS IS.
// ----------------------------------------------------------------------------
// Everything else under tests/e2e/ (config.js, helpers.js, otel.js,
// page-audit.js, page-audit-rules.js, design-audit.js, report-normalize.js,
// report-render.js, review-report.js, journey-runner.js, monkey.js) is engine:
// it must be copyable into another Mendix project unchanged. When you port the
// harness, this file is the one you edit.
//
// Two kinds of value live here, and they are kept apart on purpose:
//
//   DERIVED   — computed from the filesystem (the .mpr, the project root, the
//               project's name). Do NOT hardcode these; that is the whole point
//               of this file existing. They are correct in a fresh clone with
//               no edits at all.
//
//   CONFIGURED — cannot be derived from anything, because they are statements
//               about THIS application's model: navigation captions, widget
//               names, domain entities, the page->wireframe map. Every one of
//               them is marked with a loud comment saying which command
//               produces the right answer for a new project.
//
// NOTHING IN THIS FILE MAY HAVE SIDE EFFECTS AT REQUIRE TIME.
// page-audit.js deliberately does NOT `require('./config')`, because config.js
// calls process.exit(2) on an unverified port and would kill the audit before
// it could write its artifact (see the comment near page-audit.js's login).
// This file must stay safe for that caller: no exit, no console output, no
// throw on require. `mpr` therefore throws only when it is ACCESSED.
// ============================================================================

const fs = require('fs');
const path = require('path');

// ── DERIVED: the project root ────────────────────────────────────────────────
// Walk up from this file until we find a directory holding a *.mpr. Deliberately
// NOT `path.resolve(__dirname, '..', '..')`: that hardcodes "the harness lives
// exactly two levels below the root", which is a project layout assumption like
// any other. The two-levels-up answer is kept only as the last resort, so a
// project with no .mpr on disk yet still gets a usable root instead of a crash.
// F-042 (field run, 2026-08-28): a two-tree layout — tests/e2e at the repo root, the
// model under a sibling app/ — defeats a pure ancestor walk, because app/ is never an
// ancestor of tests/e2e. The walk therefore probes each ancestor's app/ child too, and
// two explicit overrides win over any walking: PROJECT_ROOT names the root outright,
// and an MPR_FILE that resolves as-given pins the root to the model's own directory.
function hasMpr(dir) {
  try { return fs.readdirSync(dir).some((f) => f.endsWith('.mpr')); } catch { return false; }
}
function findRoot(startDir) {
  if (process.env.PROJECT_ROOT) {
    return { root: path.resolve(process.env.PROJECT_ROOT), source: 'PROJECT_ROOT env' };
  }
  if (process.env.MPR_FILE && fs.existsSync(process.env.MPR_FILE)) {
    return { root: path.dirname(path.resolve(process.env.MPR_FILE)),
             source: 'directory of MPR_FILE env' };
  }
  let dir = startDir;
  for (;;) {
    if (hasMpr(dir)) {
      return { root: dir, source: 'walked up to the directory containing the .mpr' };
    }
    const sibling = path.join(dir, 'app');
    if (hasMpr(sibling)) {
      return { root: sibling, source: 'walked up to an app/ directory containing the .mpr' };
    }
    const up = path.dirname(dir);
    if (up === dir) break;
    dir = up;
  }
  return {
    root: path.resolve(startDir, '..', '..'),
    source: 'fallback: two levels above tests/e2e (no .mpr found by walking up)',
  };
}

const ROOT_INFO = findRoot(__dirname);
const ROOT = ROOT_INFO.root;

// ── DERIVED: the .mpr ────────────────────────────────────────────────────────
// Mirrors the semantics of the toolkit's project-bin/_common.sh find_mpr():
//   MPR_FILE env wins · exactly one *.mpr in the root is the answer · zero is an
//   error · more than one is an error, because picking the wrong one means
//   measuring (or writing to) the wrong model and no guess is safe.
function findMpr() {
  if (process.env.MPR_FILE) {
    const given = process.env.MPR_FILE;
    if (fs.existsSync(given)) return path.resolve(given);
    const inRoot = path.join(ROOT, given);
    if (fs.existsSync(inRoot)) return inRoot;
    throw new Error(`MPR_FILE='${given}' does not exist (looked at '${given}' and '${inRoot}')`);
  }
  let names = [];
  try { names = fs.readdirSync(ROOT).filter((f) => f.endsWith('.mpr')); } catch { /* handled below */ }
  if (names.length === 0) {
    throw new Error(`no .mpr found in ${ROOT} (project root ${ROOT_INFO.source}). ` +
                    'Set MPR_FILE=<name>.mpr if the model lives elsewhere.');
  }
  if (names.length > 1) {
    throw new Error(`${names.length} .mpr files in ${ROOT} — refusing to guess which model to measure:\n` +
                    names.map((n) => '  ' + n).join('\n') +
                    '\nSet MPR_FILE=<name>.mpr to choose.');
  }
  return path.join(ROOT, names[0]);
}

// Resolved once, on first access, and cached — including the failure, so a
// broken project reports the same clear message every time rather than
// re-scanning the directory on every call.
let _mpr;
function mprPath() {
  if (_mpr === undefined) {
    try { _mpr = { ok: findMpr() }; } catch (e) { _mpr = { err: e }; }
  }
  if (_mpr.err) throw _mpr.err;
  return _mpr.ok;
}

// ── DERIVED: identity ────────────────────────────────────────────────────────
// The project root's directory name is the one name that is always present, so
// it is the default: `id` is it verbatim, `displayName` is it made
// human-readable ("acme-wms" -> "acme wms").
//
// NAME_OVERRIDE exists because a checkout directory is not always the app's
// name. A common case is a directory ending in `-main`, which is a GitHub
// zip-download suffix, not part of the project. `id` also feeds the default OTel service
// name, which MUST match what the runtime emits, so deriving a wrong name here
// would make every trace assertion query a service that does not exist. Set
// NAME_OVERRIDE to null in a project whose directory name is correct.
//
// Two-tree layout: ROOT is app/, and "app" names nothing — `id` came out as `app`, so every
// trace assertion queried a service called `app` (a requirements-driven field build,
// 2026-09-25). There the model's own name is the identity, and it is also what
// `mxcli run --local --trace` defaults OTEL_SERVICE_NAME to. Read inside a try: this file
// must not throw on require, and a missing .mpr still throws where `mpr` is accessed.
const NAME_OVERRIDE = null;   // TEMPLATE: set only if your checkout dir != the app name
function derivedId() {
  const dirName = path.basename(ROOT);
  if (dirName !== 'app') return dirName;
  try { return path.basename(mprPath(), '.mpr'); } catch { return path.basename(path.dirname(ROOT)); }
}
const ID = process.env.PROJECT_ID || NAME_OVERRIDE || derivedId();
const DISPLAY_NAME = process.env.PROJECT_DISPLAY_NAME || ID.replace(/[-_]+/g, ' ');

// ============================================================================
// CONFIGURED — everything below this line is a statement about THIS model.
// A new project MUST fill every block below. None of it can be derived.
//
// THIS FILE SHIPS EMPTY ON PURPOSE. It used to ship one sample app's menu, pages,
// users and process, which a fresh scaffold then ran as if they were its own: monkey
// reached "0 of 8 targets" and the walkthrough died on an OQL error for an entity the
// app never had. An empty block makes each instrument stop with "NOT CONFIGURED: fill
// <block>" instead. `node tests/e2e/project.config.js` lists what is still empty.
// ============================================================================

// ── CONFIGURED: credentials ──────────────────────────────────────────────────
// The demo accounts this app was seeded with. Prefer a non-admin identity so the
// harness exercises the role grants a real user has.
const DEFAULT_USER = 'demo_test_user';
const DEFAULT_PASS = 'Demo2025!';
// Last-resort identity so a credential problem degrades to a reported finding
// instead of a zero-coverage run. Set FALLBACK_USER='' to disable.
const DEFAULT_FALLBACK_USER = 'MxAdmin';
const DEFAULT_FALLBACK_PASS = 'Mendix1!';

// DEFECT FIXED 2026-08-18: the same two credentials were read under two different
// env names — TEST_USER/TEST_PASS in config.js and APP_USER/APP_PASS in
// page-audit.js. Setting one pair and not the other gave two identities inside a
// single run, with the UI walk and the page audit measuring different access
// paths and nothing saying so. TEST_USER/TEST_PASS is now the only name; APP_USER
// and APP_PASS still work, but say so on stderr rather than diverging silently.
let _credWarned = false;
function credentials() {
  const aliased = [];
  if (!process.env.TEST_USER && process.env.APP_USER) aliased.push('APP_USER -> TEST_USER');
  if (!process.env.TEST_PASS && process.env.APP_PASS) aliased.push('APP_PASS -> TEST_PASS');
  if (aliased.length && !_credWarned) {
    _credWarned = true;
    console.error('  DEPRECATED env name(s) in use: ' + aliased.join(', ') +
                  '\n  APP_USER/APP_PASS are accepted as aliases and will be removed. ' +
                  'Set TEST_USER/TEST_PASS instead.');
  }
  return {
    user: process.env.TEST_USER || process.env.APP_USER || DEFAULT_USER,
    pass: process.env.TEST_PASS || process.env.APP_PASS || DEFAULT_PASS,
    fallbackUser: process.env.FALLBACK_USER ?? DEFAULT_FALLBACK_USER,
    fallbackPass: process.env.FALLBACK_PASS ?? DEFAULT_FALLBACK_PASS,
  };
}

// ── CONFIGURED: the one port fallback ────────────────────────────────────────
// DEFECT FIXED 2026-08-18: config.js fell back to 8081 and page-audit.js to 8084.
// Two instruments in one harness disagreeing about which app they are testing is
// exactly the failure test-stack-up.sh's ownership check exists to catch. One
// fallback, one place. It is still only a guess — stack.env is the measurement.
const DEFAULT_PORT = '8081';

// ── CONFIGURED: post-login readiness selectors ───────────────────────────────
// Proof that the SPA finished routing into the app shell. The two below are
// generic to every Mendix app. Add THIS project's widget names only when a
// layout has neither (a phone layout with no nav tree, say).
//   Read the real names with: ./mxcli -p <mpr> -c "DESCRIBE PAGE <Module>.<Page>"
const READY_SELECTORS = [
  '.mx-navigationtree',
  '.mx-page',
];

// ── CONFIGURED: design-system stylesheet ─────────────────────────────────────
// Read by helpers.parseTokens() to pull the :root custom properties.
// (`dsHtml`, the design-system showcase page, used to live beside this and had
// no reader anywhere in the repo — deleted 2026-08-18 rather than carried.)
// In a two-tree layout ROOT is app/ while design/ sits beside it at the repo
// root, so probe ROOT first and fall back to ROOT's parent (F-042).
function designPath(...parts) {
  const inRoot = path.join(ROOT, ...parts);
  if (fs.existsSync(inRoot)) return inRoot;
  const beside = path.join(path.dirname(ROOT), ...parts);
  return fs.existsSync(beside) ? beside : inRoot;
}
const DS_CSS = designPath('design', 'ds.css');

// ── CONFIGURED: navigation captions ──────────────────────────────────────────
// navClick() clicks the real <a title="..."> in the Mendix nav tree, so these
// must match the menu captions EXACTLY. One entry per menu item monkey.js fuzzes:
//   key: ['Item']  for a top-level item,  key: ['Group', 'Item']  for a nested one.
//   Produce the right answer with: ./mxcli -p <mpr> -c "DESCRIBE NAVIGATION"
// FILL ME — empty, monkey.js exits 2 "NOT CONFIGURED: NAV" without a browser.
const NAV = {
};

// ── CONFIGURED: page stops (legacy) ──────────────────────────────────────────
// A map of named page-stop lists, read only through config.js resolveTarget().
// No shipped instrument calls it; kept so a project's own script that does keeps
// working. Shape: { '<name>': { label, ready, pages: [{ key, label, nav, ready,
// checks: [widget names], oql: [{ label, sql }] }] } }.
const TARGETS = {
};

// ── CONFIGURED: the page -> wireframe map ────────────────────────────────────
// THE SINGLE COPY. page-audit.js and design-audit.js both read it from here;
// each used to carry its own near-identical duplicate, which is two chances to
// drift and no way to notice.
//
// Explicit and hand-verified against each wireframe's own <title>, NOT
// fuzzy-matched. A token heuristic once paired an admin page with home.html at
// 0.67 ("home" is in both names) and then reported 31 findings from a wireframe
// that has nothing to do with that page. A wrong mapping does not produce a weak
// finding, it produces a confident wrong one — so an unmapped page is `skipped`
// in design-audit (covered by rung 7) and graded as a coverage gap in page-audit
// (requirement R4).
//   Produce the candidate list with: ls design/wireframes
//   Confirm each pairing by reading that wireframe's <title>.
// FILL ME — shape: '<Module>.<Page>': '<file>.html',   // "<the wireframe's <title>>"
const PAGE_WIREFRAME = {
};

// ── CONFIGURED: the live positive-control probe page ─────────────────────────
// design-audit.js's `guard-891-live` control asserts that the mxcli #891
// content-slot guard fires against a REAL page of this project. That needs a
// page known to contain an unread content slot (a DataGrid2 with customContent
// columns or a control bar). PROBE_PAGE overrides; if neither is set, the first
// in-scope page from .claude/loop/page-scope.json is used, which is a weaker
// choice because it may happen to be fully readable.
//   Find a candidate with: ./mxcli -p <mpr> describe --format elk page <Module>.<Page>
//   and compare the tree node count against the page's own mdlSource.
const PROBE_PAGE = process.env.PROBE_PAGE || null;   // FILL ME, or leave null for the page-scope fallback

function probePage(scopeFile) {
  if (PROBE_PAGE) return PROBE_PAGE;
  try {
    const scope = JSON.parse(fs.readFileSync(scopeFile, 'utf8'));
    const pages = scope.inScope || scope.pages || [];
    const first = pages[0];
    return typeof first === 'string' ? first : (first && (first.page || first.qn)) || null;
  } catch { return null; }
}

// ── CONFIGURED: exemplar pages quoted in page-audit advice strings ───────────
// page-audit-rules.js's rule LOGIC is generic; its `exemplar` and `remediate`
// text points a reader at a page in THIS project that already does the thing
// right. Name the equivalent pages of this project — an exemplar naming a page
// that does not exist is worse than no exemplar, so null prints "no exemplar set".
// FILL ME — '<Module>.<Page>' each, or leave null.
const EXEMPLARS = {
  listPage:     null,
  overviewPage: null,
  detailPage:   null,
};

// ── CONFIGURED: the roles the business process passes through ────────────────
// full-app-walkthrough.js signs OUT and signs IN again at every role change, so
// each entry needs real credentials for a real account. Use accounts that hold
// exactly one business role: an account carrying two of them cannot fail a role
// boundary and every negative check below it is vacuous.
//   Find the roles:     ./mxcli -p <mpr> -c "SHOW SECURITY ROLES"
//   Find the accounts:  the app's own Administration → Accounts page, or the
//                       demo users (`create or modify demo user` sets a known password)
// Env overrides exist so CI can inject credentials without editing this file.
// FILL ME — shape:
//   requester: { label: '<role as the business says it>',
//                user: process.env.ROLE_REQUESTER_USER || '<user>',
//                pass: process.env.ROLE_REQUESTER_PASS || '<password>' },
const ROLES = {
};

// ── CONFIGURED: the one cross-module, cross-role business process ────────────
// THE GAP THIS CLOSES, in this project's own history: a full e2e pass over six
// modules produced six journey-findings files, each recording
// configuredUser == actualUser == one single persona, usedFallback:false, and not
// one role change anywhere. Six single-persona smoke tests do not add up to an
// end-to-end test of a business process, because the handoff between two roles
// falls in the gap BETWEEN two per-module journeys and belongs to neither.
//
// So this block describes ONE process, the way the business describes it — raised
// by somebody, approved by somebody else, consumed by a third — and
// full-app-walkthrough.js walks it. Per-module depth stays in journeys/*.journey.json
// and journey-runner.js; do not reproduce it here.
//
// A walk configured with one role, or one module, FAILS its own pre-flight checks:
// it would be a module journey wearing an end-to-end label.
//
// Widget names:  ./mxcli -p <mpr> -c "DESCRIBE PAGE <Module>.<Page>"
// Menu captions: ./mxcli -p <mpr> -c "DESCRIBE NAVIGATION"
// Entity names:  ./mxcli -p <mpr> -c "SHOW ENTITIES IN <Module>"
//
// Step verbs (the whole vocabulary — see full-app-walkthrough.js `runStep`):
//   nav {group,item,ready}        click {widget}            fill {widget,value,debounceMs}
//   expect {widget}               expectAbsent {widget}     expectText {widget,text}
//   expectRows {widget,min}       expectMatchesDb {widget,sql}
//   baseline {name,sql}           capture {name,sql}        oql {label,sql,expect|atLeast|deltaFrom,by}
//   wait {ms}                     shot {name}
// Any step may carry `label` (what the report calls it) and `fatal: true` (nothing
// after this is worth attempting — later steps are then reported NOT REACHED
// rather than left silently absent). `{{name}}` interpolates a seed or a capture.
// FILL ME — `acts` is empty, so full-app-walkthrough.js exits 2 "NOT CONFIGURED".
// The shape of one process (illustrative names; replace every one of them):
//
//   seeds: [{ name: 'orderNo', sql: "SELECT OrderNo AS o FROM Sales.Order WHERE Status = 'Open' LIMIT 1" }],
//   acts: [
//     { key: 'raise', role: 'requester', module: 'Sales', label: 'raise an order',
//       // `checks` are read on the act's landing page: after its handoffAssert, and
//       // after its LEADING `nav` steps — so a first act may simply start with a nav.
//       checks: ['dgOrders'],
//       steps: [
//         { do: 'nav', group: 'Sales', item: 'Orders', ready: 'dgOrders', fatal: true },
//         { do: 'baseline', name: 'orders', sql: 'SELECT COUNT(*) AS n FROM Sales.Order' },
//         { do: 'click', widget: 'btnNew', fatal: true },
//         { do: 'fill', widget: 'txtReference', value: 'E2E walkthrough' },
//         { do: 'click', widget: 'btnSave', settle: 3000 },
//         { do: 'oql', label: 'the order was written', deltaFrom: 'orders', by: 1,
//           sql: 'SELECT COUNT(*) AS n FROM Sales.Order', fatal: true },
//         { do: 'expectAbsent', widget: 'btnApprove', label: 'the requester cannot approve' },
//       ] },
//     { key: 'approve', role: 'approver', module: 'Approvals', label: 'approve it',
//       handoffAssert: [   // runs right after the sign-in: can role B SEE role A's work?
//         { do: 'nav', group: 'Approvals', item: 'My Queue', ready: 'dgQueue', fatal: true },
//         { do: 'expectText', widget: 'dgQueue', text: '{{orderNo}}' } ],
//       checks: ['dgQueue', 'btnApprove'],
//       steps: [ { do: 'click', widget: 'btnApprove', settle: 3000 } ] },
//   ],
//   cleanup: { role: 'approver', steps: [ /* oql checks that put the data back */ ] },
const WALKTHROUGH = {
  label: `${ID} — cross-role business process`,
  // One sentence, in the language the business uses. It is printed in the report.
  process: '',
  // Live values, never literals: a walk pinned to one record number reports "the
  // feature is broken" the first time somebody reseeds the database.
  seeds: [],
  acts: [],
  // Put the data back. A walk that writes and does not restore makes the second
  // run measure the first run's leftovers — and the cleanup itself is reported.
  cleanup: null,
};

// ── CONFIGURED: the weak walkthrough instruments ─────────────────────────────
// report-normalize.js used to branch on these instrument names as string literals
// in three places. They are the project's own walkthrough scripts, so a project
// with different ones (or none) had no way to say so.
//   `input` is the key in report-normalize's INPUTS table that holds the
//   instrument's findings file; `script` is what a reader is told to re-run.
//
// EVERY ENTRY HERE MUST HAVE A SCRIPT THAT EXISTS. A declared instrument with no
// file behind it does not report "missing script" — it reports the APPLICATION at
// verdict `fault`, reason "findings.json does not exist — the instrument did not
// run, or ran without writing", which reads as a broken app and sends the reader
// to debug configuration that was never wrong. That is not hypothetical: this
// template declared `full-app-walkthrough` for months while no such file had ever
// existed in the toolkit, and a 6-module field pass reported exactly that
// (2026-08-20, process/improvement-plan-e2e-reporting.md Finding 5).
const WALKTHROUGHS = [
  { instrument: 'full-app-walkthrough', input: 'findings', script: 'full-app-walkthrough.js', tags: [] },
  // A phone-viewport walkthrough is a real second instrument, but the toolkit
  // ships no `mobile-fieldscan.js` and most projects have no mobile surface at
  // all. UNCOMMENT THIS ONLY ONCE tests/e2e/mobile-fieldscan.js exists in your
  // project — otherwise you are re-creating the fault described above:
  // { instrument: 'mobile-fieldscan', input: 'findingsMobile', script: 'mobile-fieldscan.js', tags: ['mobile'] },
];

module.exports = {
  // DERIVED
  root: ROOT,
  rootSource: ROOT_INFO.source,
  get mpr() { return mprPath(); },                       // absolute path
  get mprName() { return path.basename(mprPath()); },    // e.g. "YourApp.mpr"
  findMpr,
  id: ID,
  displayName: DISPLAY_NAME,
  otelService: process.env.OTEL_SERVICE || ID,
  // CONFIGURED
  defaultPort: DEFAULT_PORT,
  mxcli: process.env.MXCLI || './mxcli',
  credentials,
  readySelectors: READY_SELECTORS,
  // Sign-out captions monkey.js must never click, ADDED to its built-in list (English, Dutch,
  // German, French, Spanish, Portuguese, Italian). Set it when the app's sign-out control
  // reads otherwise, e.g. /\bkirjaudu ulos\b/i — a monkey that signs itself out scores the
  // login page as a crash and fuzzes nothing more (#469).
  signOutPattern: null,
  dsCss: DS_CSS,
  NAV,
  TARGETS,
  PAGE_WIREFRAME,
  probePage,
  exemplars: EXEMPLARS,
  walkthroughs: WALKTHROUGHS,
  roles: ROLES,
  walkthrough: WALKTHROUGH,
};

// --- `node project.config.js` -------------------------------------------------------------
// Print what this file DERIVED, so porting the harness starts with evidence instead of a
// guess. Everything below is computed from the filesystem; if any line is wrong, nothing
// downstream can be right — a wrong otelService silently queries a service that does not
// exist and every trace assertion comes back empty, which grades as fault, not as failure.
if (require.main === module) {
  const rows = [
    ['root', module.exports.root],
    ['rootSource', module.exports.rootSource],
    ['id', module.exports.id],
    ['displayName', module.exports.displayName],
    ['otelService', module.exports.otelService],
    ['defaultPort', module.exports.defaultPort],
  ];
  let mpr;
  try { mpr = module.exports.mprName; } catch (e) { mpr = `UNRESOLVED — ${e.message}`; }
  rows.splice(2, 0, ['mpr', mpr]);
  const w = Math.max(...rows.map(r => r[0].length));
  console.log('derived from the filesystem:');
  for (const [k, v] of rows) console.log(`  ${k.padEnd(w)}  ${v}`);
  console.log('\ndeclared (edit these — they are this project\'s, not yours):');
  // Some of these are objects and some are arrays; count both rather than printing
  // "undefined", which reads as "not configured" when it only means "not an array".
  const n = (v) => (Array.isArray(v) ? v.length : v && typeof v === 'object' ? Object.keys(v).length : 0);
  const e = module.exports;
  // An empty block says which instrument it stops, so the first run is a to-do list, not a guess.
  const fill = (k, why) => (n(e[k]) ? '' : `   ← FILL ME: ${why}`);
  const setEx = Object.values(e.exemplars || {}).filter(Boolean).length;
  console.log(`  NAV             ${n(e.NAV)}${fill('NAV', 'monkey.js exits 2 NOT CONFIGURED')}`);
  console.log(`  TARGETS         ${n(e.TARGETS)}`);
  console.log(`  PAGE_WIREFRAME  ${n(e.PAGE_WIREFRAME)}${fill('PAGE_WIREFRAME', 'every page reads as unmapped')}`);
  console.log(`  exemplars       ${setEx} of ${n(e.exemplars)} set`);
  console.log(`  walkthroughs    ${n(e.walkthroughs)}`);
  console.log(`  roles           ${n(e.roles)}${fill('roles', 'full-app-walkthrough.js cannot sign in as anyone')}`);
  // Roles and modules, not act count: a walk with ten acts and one role is the
  // single-persona blind spot this instrument exists to close, and it should be
  // visible as such the moment somebody prints this file.
  const acts = (e.walkthrough && e.walkthrough.acts) || [];
  const uniq = (k) => [...new Set(acts.map((a) => a[k]).filter(Boolean))];
  console.log(`  walkthrough     ${acts.length} act(s), ${uniq('role').length} role(s), ${uniq('module').length} module(s)`
              + `${!acts.length ? '   ← FILL ME: full-app-walkthrough.js exits 2 NOT CONFIGURED'
                : uniq('role').length < 2 ? '   ← SINGLE PERSONA: this is a module journey, not a process' : ''}`);
}
