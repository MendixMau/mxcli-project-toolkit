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
function findRoot(startDir) {
  let dir = startDir;
  for (;;) {
    try {
      if (fs.readdirSync(dir).some((f) => f.endsWith('.mpr'))) {
        return { root: dir, source: 'walked up to the directory containing the .mpr' };
      }
    } catch { /* unreadable directory — keep walking */ }
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
// human-readable ("WMS-Demo" -> "WMS Demo").
//
// NAME_OVERRIDE exists because a checkout directory is not always the app's
// name. This one is `WMS-Demo-main` — the `-main` is a GitHub zip-download
// suffix, not part of the project. `id` also feeds the default OTel service
// name, which MUST match what the runtime emits, so deriving a wrong name here
// would make every trace assertion query a service that does not exist. Set
// NAME_OVERRIDE to null in a project whose directory name is correct.
const NAME_OVERRIDE = null;   // TEMPLATE: set only if your checkout dir != the app name
const ID = process.env.PROJECT_ID || NAME_OVERRIDE || path.basename(ROOT);
const DISPLAY_NAME = process.env.PROJECT_DISPLAY_NAME || ID.replace(/[-_]+/g, ' ');

// ============================================================================
// CONFIGURED — everything below this line is a statement about THIS model.
// A new project MUST edit every block below. None of it can be derived.
// ============================================================================

// ── CONFIGURED: credentials ──────────────────────────────────────────────────
// The demo accounts this app was seeded with. Prefer a non-admin identity so the
// harness exercises the role grants a real user has.
const DEFAULT_USER = 'plantops_test_user';
const DEFAULT_PASS = 'PlantOps2025!';
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
// Proof that the SPA finished routing into the app shell. The first two are
// generic to every Mendix app and are the engine's own default; the rest are
// THIS project's widget names, needed because the phone layout has no nav tree
// (it auto-routes straight to the FieldScan tiles).
//   Read the real names with: ./mxcli -p <mpr> -c "DESCRIBE PAGE <Module>.<Page>"
const READY_SELECTORS = [
  '.mx-navigationtree',
  '.mx-name-btnSendMessage',
  '.mx-name-tileMove',
  '.mx-name-bM',
  '.mx-page',
];

// ── CONFIGURED: design-system stylesheet ─────────────────────────────────────
// Read by helpers.parseTokens() to pull the :root custom properties.
// (`dsHtml`, the design-system showcase page, used to live beside this and had
// no reader anywhere in the repo — deleted 2026-08-18 rather than carried.)
const DS_CSS = path.join(ROOT, 'design', 'ds.css');

// ── CONFIGURED: navigation captions ──────────────────────────────────────────
// navClick() clicks the real <a title="..."> in the Mendix nav tree, so these
// must match the menu captions EXACTLY.
//   Produce the right answer with: ./mxcli -p <mpr> -c "DESCRIBE NAVIGATION"
const NAV = {
  dashboard:    ['Dashboard'],
  equipment:    ['Assets & Barcodes', 'Equipment'],
  locations:    ['Assets & Barcodes', 'Locations'],
  fieldScan:    ['Assets & Barcodes', 'Field Scan'],
  barcodeLabel: ['Assets & Barcodes', 'Barcode Labels'],
  aiAssistant:  ['AI', 'AI Assistant'],
  aiAdmin:      ['AI', 'AI Admin'],
  designSystem: ['Configuration', 'Design System'],
};

// ── CONFIGURED: full-app walkthrough steps ───────────────────────────────────
// One entry per stop on the golden path. Every `.mx-name-*` selector and every
// `checks` entry is a widget name; every `oql` statement names domain entities.
// None of it is guessable.
//   Widget names:  ./mxcli -p <mpr> -c "DESCRIBE PAGE <Module>.<Page>"
//   Entity names:  ./mxcli -p <mpr> -c "SHOW ENTITIES IN <Module>"
const TARGETS = {
  'full-app': {
    label: `${ID} — Full App Walkthrough`,
    ready: '.mx-page',
    pages: [
      {
        key: 'dashboard', label: 'Dashboard', nav: NAV.dashboard,
        ready: '.mx-name-dvKPI',
        checks: ['dvKPI', 'dtTotal', 'dtActive', 'dtMfr', 'dtUnclass', 'btnNewItem', 'btnItemMgmt',
                 'cChartEquip', 'cChartMfr', 'cChartTrend', 'lvActivityFeed'],
        oql: [
          { label: 'Total equipment',  sql: 'SELECT COUNT(*) AS n FROM Equipment.Item' },
          { label: 'Active equipment', sql: 'SELECT COUNT(*) AS n FROM Equipment.Item WHERE Active = true' },
          { label: 'Total locations',  sql: 'SELECT COUNT(*) AS n FROM Location.Location' },
          { label: 'Placements',       sql: 'SELECT COUNT(*) AS n FROM FieldScan.ItemPlacement' },
        ],
      },
      {
        key: 'equipment-list', label: 'Equipment — Overview', nav: NAV.equipment,
        ready: '.mx-name-dgItems',
        checks: ['dgItems', 'btnRegister', 'btnExportItems', 'btnResetItems', 'btnEditItem1'],
        oql: [{ label: 'Equipment rows', sql: 'SELECT COUNT(*) AS n FROM Equipment.Item' }],
      },
      {
        key: 'equipment-detail', label: 'Equipment — Detail (read + cancel)', nav: null,
        ready: '.mx-name-dvItem',
        checks: ['dvItem', 'dynItemCode', 'dynModelName', 'txtDesc1', 'btnCancel'],
        oql: [],
      },
      {
        key: 'equipment-create', label: 'Equipment — Create + Cancel (no DB write)', nav: NAV.equipment,
        ready: '.mx-name-dgItems',
        checks: [],
        oql: [],
      },
      {
        key: 'locations', label: 'Locations — Overview', nav: NAV.locations,
        ready: '.mx-name-dgLocations',
        checks: ['dgLocations', 'btnRegisterLoc', 'btnExportLoc', 'btnResetLoc', 'btnDetailLoc1'],
        oql: [{ label: 'Location rows', sql: 'SELECT COUNT(*) AS n FROM Location.Location' }],
      },
      {
        key: 'location-detail', label: 'Locations — Detail (edit remark + cancel)', nav: null,
        ready: '.mx-name-dvLocation',
        checks: ['dvLocation', 'dynLocId', 'dynLocName', 'txtRemark', 'btnBack'],
        oql: [],
      },
      {
        key: 'barcode-label', label: 'Barcode Labels', nav: NAV.barcodeLabel,
        ready: '.mx-name-lvItems',
        checks: ['lvItems', 'btnPrint', 'ctnLabelPreview', 'txtItemInfo'],
        oql: [{ label: 'Print-enabled equipment',
                sql: 'SELECT COUNT(*) AS n FROM Equipment.Item WHERE PrintEnabled = true' }],
      },
      {
        key: 'fieldscan-home', label: 'Field Scan — Home', nav: NAV.fieldScan,
        ready: '.mx-name-bR',
        checks: ['bR', 'bM', 'bC', 'tileReceive', 'tileMove', 'tileCount'],
        oql: [],
      },
      {
        key: 'fieldscan-receive', label: 'Field Scan — Receive (resolve a real barcode)', nav: null,
        ready: '.mx-name-dvScanCtx',
        checks: ['dvScanCtx', 'tbScannedCode', 'btnResolve', 'tbQuantity', 'btnReceive', 'lvHistory'],
        oql: [{ label: 'ItemPlacement rows', sql: 'SELECT COUNT(*) AS n FROM FieldScan.ItemPlacement' }],
      },
      {
        key: 'fieldscan-move', label: 'Field Scan — Move (resolve item + location)', nav: NAV.fieldScan,
        ready: '.mx-name-dvScanCtx',
        checks: ['dvScanCtx', 'tbScannedCode', 'btnResolve', 'btnMove'],
        oql: [{ label: 'MovementLog rows', sql: 'SELECT COUNT(*) AS n FROM FieldScan.MovementLog' }],
      },
      {
        key: 'fieldscan-count', label: 'Field Scan — Stock Count', nav: NAV.fieldScan,
        ready: '.mx-name-dvCtx',
        checks: ['dvCtx', 'tbLocCode', 'btnResolveLoc', 'btnStart', 'tbAssetCode', 'btnScanAsset'],
        oql: [{ label: 'CountSession rows', sql: 'SELECT COUNT(*) AS n FROM FieldScan.CountSession' }],
      },
      {
        key: 'ai-chat', label: 'AI Assistant — Chat', nav: NAV.aiAssistant,
        ready: '.mx-name-dvChat',
        checks: ['heading', 'cHead', 'dvChat', 'cCopilot'],
        oql: [],
      },
      {
        key: 'ai-admin', label: 'AI Assistant — Admin (buttons present, not clicked)', nav: NAV.aiAdmin,
        ready: '.mx-name-btnLoadItemKB',
        checks: ['btnLoadItemKB', 'btnLoadLocKB', 'cItemKB', 'cLocKB'],
        oql: [],
      },
      {
        key: 'design-system', label: 'Design System — Component Gallery', nav: NAV.designSystem,
        ready: '.mx-page',
        checks: [],
        oql: [],
      },
    ],
  },
};

// ── CONFIGURED: the page -> wireframe map ────────────────────────────────────
// THE SINGLE COPY. page-audit.js and design-audit.js both read it from here;
// each used to carry its own near-identical duplicate, which is two chances to
// drift and no way to notice.
//
// Explicit and hand-verified against each wireframe's own <title>, NOT
// fuzzy-matched. A token heuristic once paired AIAssistant.AIAdmin_Home with
// home.html at 0.67 ("home" is in both names) and then reported 31 findings from
// a wireframe that has nothing to do with that page. A wrong mapping does not
// produce a weak finding, it produces a confident wrong one — so an unmapped
// page is `skipped` in design-audit (covered by rung 7) and graded as a coverage
// gap in page-audit (requirement R4).
//   Produce the candidate list with: ls design/wireframes
//   Confirm each pairing by reading that wireframe's <title>.
const PAGE_WIREFRAME = {
  'Analytics.Dashboard_Home': 'home.html',                                 // "Home Dashboard"
  'Equipment.Item_Overview': 'item-management.html',                       // "Equipment"
  'Equipment.Item_Detail': 'item-edit.html',                               // "Item Edit modal"
  'Equipment.BarcodeLabel_Overview': 'barcode-labels.html',                // "Barcode Label Renderer"
  'Location.Location_Overview': 'location-management.html',
  'Location.Location_Detail': 'location-detail.html',
  'FieldScan.MobileScan_Count': 'mobile-scan.html',                        // "Mobile Field-Scan"
  'FieldScan.Receive_Scan': 'movement-scan.html',                          // "Movement Scan (Receive · Move)"
  'FieldScan.Move_Scan': 'movement-scan.html',
  'RoutingManagement.Route_List': 'usi-route-list.html',
  'RoutingManagement.Route_Detail': 'usi-route-detail.html',
  'OperationManagement.Operation_List': 'usi-operation-list.html',
  'ProcessVariant.ProcessVariant_List': 'usi-processvariant-list.html',
  'ReworkDeviationRouting.ReworkRoute_List': 'usi-reworkroute-list.html',
  // Deliberately unmapped — no wireframe was ever drawn for these five. Not a
  // mapping bug, a coverage gap, and reported as a finding on each page rather
  // than silently omitted:
  //   AIAssistant.Chat_Home, AIAssistant.AIAdmin_Home, StyleGallery.Gallery_Home,
  //   Equipment.Item_Overview_Lab, FieldScan.FieldScan_Home
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
const PROBE_PAGE = process.env.PROBE_PAGE || 'RoutingManagement.Route_List';

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
// right. Repoint these at the equivalent pages of a new project — an exemplar
// naming a page that does not exist is worse than no exemplar.
const EXEMPLARS = {
  listPage:     'RoutingManagement.Route_List',
  overviewPage: 'Equipment.Item_Overview',
  detailPage:   'Equipment.Item_Detail',
};

// ── CONFIGURED: the weak walkthrough instruments ─────────────────────────────
// report-normalize.js used to branch on these two instrument names as string
// literals in three places. They are the project's own walkthrough scripts, so
// a project with different ones (or none) had no way to say so.
//   `input` is the key in report-normalize's INPUTS table that holds the
//   instrument's findings file; `script` is what a reader is told to re-run.
const WALKTHROUGHS = [
  { instrument: 'full-app-walkthrough', input: 'findings',       script: 'full-app-walkthrough.js', tags: [] },
  { instrument: 'mobile-fieldscan',     input: 'findingsMobile', script: 'mobile-fieldscan.js',     tags: ['mobile'] },
];

module.exports = {
  // DERIVED
  root: ROOT,
  rootSource: ROOT_INFO.source,
  get mpr() { return mprPath(); },                       // absolute path
  get mprName() { return path.basename(mprPath()); },    // e.g. "WMS-Demo.mpr"
  findMpr,
  id: ID,
  displayName: DISPLAY_NAME,
  otelService: process.env.OTEL_SERVICE || ID,
  // CONFIGURED
  defaultPort: DEFAULT_PORT,
  mxcli: process.env.MXCLI || './mxcli',
  credentials,
  readySelectors: READY_SELECTORS,
  dsCss: DS_CSS,
  NAV,
  TARGETS,
  PAGE_WIREFRAME,
  probePage,
  exemplars: EXEMPLARS,
  walkthroughs: WALKTHROUGHS,
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
  console.log(`  NAV             ${n(e.NAV)}`);
  console.log(`  TARGETS         ${n(e.TARGETS)}`);
  console.log(`  PAGE_WIREFRAME  ${n(e.PAGE_WIREFRAME)}`);
  console.log(`  exemplars       ${n(e.exemplars)}`);
  console.log(`  walkthroughs    ${n(e.walkthroughs)}`);
}
