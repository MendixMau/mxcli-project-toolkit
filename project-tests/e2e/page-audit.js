'use strict';
// ============================================================================
// page-audit.js — the PER-PAGE design instrument
// ----------------------------------------------------------------------------
//   node tests/e2e/page-audit.js                    # full run (needs the app up)
//   node tests/e2e/page-audit.js --static-only      # model-side only, app may be down
//   node tests/e2e/page-audit.js --page Equipment.Item_Detail
//   node tests/e2e/page-audit.js --positive-control # prove every category can go red
//
// Output: tests/e2e/artifacts/page-audit.json          (one artifact, per-page sections)
//         tests/e2e/artifacts/page-audit-control.json  (--positive-control; own file —
//         a control run must never overwrite a real run)
//         tests/e2e/artifacts/page-audit-<Module.Page>.png  (one screenshot per page)
//
// WHAT THIS IS FOR, AND HOW IT DIFFERS FROM design-audit.js
// `design-audit.js` sweeps the corpus for class correctness, accessibility and
// overflow. It answers "are the classes right across all pages". This answers a
// different question, the one the user actually asked: **for THIS page, what should
// be improved, graded against this project's own page-development skills and its own
// exemplar MDL, and does it have a wireframe at all.** Overlap is deliberately
// avoided: no class-invention sweep here, no a11y here — those are design-audit's.
// The two are complementary and neither supersedes the other.
//
// THE FOUR REQUIREMENTS IT WAS BUILT AGAINST
//   R1 every in-scope page is screenshotted, not just the ones a journey walks.
//   R2 a report section PER PAGE.
//   R3 graded against rules extracted from .ai-context/skills/*, the toolkit's
//      ui-preflight-pages.md / ui-review-loop.md / learned-stylegallery.md, and the
//      project's own mdlsource/ exemplars. Every rule cites its source.
//   R4 a page with NO wireframe is still fully graded. The wireframe check is one
//      section of that page's report; its absence renders as an explicit
//      "no wireframe on file" finding — never a pass, never a reason to skip.
//
// VERDICTS: pass | fail | fault. `fault` = did not measure. Never amber, never
// silence. Page precedence: fault > fail > pass. Process rc: 2 fault, 1 finding, 0 clean.
//
// NON-VACUITY: `[].every()` is `true`, and that bug has shipped in this repo before.
// Every aggregate below guards non-emptiness first, a page with zero checks run is
// `fault` however good its screenshot, and every rule category carries a mutant
// (`--positive-control`). A category whose mutant did not fire is reported
// UNPROVEN → fault, never pass.
//
// mxcli #891 GUARD: an object-list item's content-slot children are never read, so a
// DataGrid2 inside an Accordion describes as an empty group and a sweep reports clean
// WITHOUT HAVING LOOKED. Any page whose ELK tree is shorter than its own mdlSource, or
// that contains an empty content slot, is stamped `partially-read` → the page verdict
// is `fault`. Structural rules therefore run over the mdlSource parse (complete), and
// classes are read from the UNION of tree and mdlSource.
// ============================================================================

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const R = require('./page-audit-rules.js');

// project.config.js is the only project-aware file in tests/e2e/. It is safe to
// require here where ./config is not: it has NO side effects at require time
// (see the comment near the login below, and the header of project.config.js).
const PROJ = require('./project.config');

const ROOT = PROJ.root;
const MPR = PROJ.mprName;
const MXCLI = path.join(ROOT, 'mxcli');
const ARTIFACTS = path.join(__dirname, 'artifacts');
const SCOPE_FILE = path.join(ROOT, '.claude', 'loop', 'page-scope.json');
const WIREFRAME_DIR = path.join(ROOT, 'design', 'wireframes');
const MDLSOURCE = path.join(ROOT, 'mdlsource');
const SCHEMA_VERSION = '1.0';
const INSTRUMENT = 'page-audit';

// ── args ─────────────────────────────────────────────────────────────────────
const argv = process.argv.slice(2);
const has = (f) => argv.includes(f);
const valOf = (f) => { const i = argv.indexOf(f); return i >= 0 ? argv[i + 1] : null; };
const OPT = {
  staticOnly: has('--static-only'),
  positiveControl: has('--positive-control'),
  page: valOf('--page'),
  out: valOf('--out'),
};
const nowIso = () => new Date().toISOString();
const moduleOf = (qn) => (qn && qn.includes('.') ? qn.split('.')[0] : null);

// ── the page→wireframe map ───────────────────────────────────────────────────
// Hand-verified, and formerly DUPLICATED here from design-audit.js because that
// file exports nothing. Both copies now read the single map in project.config.js:
// two near-identical literals are two chances to drift and no way to notice.
// The five omissions in that map are the point of requirement R4 — they are pages
// that were built with no wireframe, and they must still be graded.
const PAGE_WIREFRAME = PROJ.PAGE_WIREFRAME;

// ── mxcli reads (READ-ONLY: `describe` does not write the .mpr; `test` and
//    `docker check` do, and are never invoked here) ───────────────────────────
function describePage(qn) {
  try {
    const raw = execFileSync(MXCLI, ['-p', MPR, 'describe', '--format', 'elk', 'page', qn],
      { cwd: ROOT, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, timeout: 180000 });
    return { ok: true, doc: JSON.parse(raw) };
  } catch (e) {
    return { ok: false, error: (e.stderr || e.message || String(e)).toString().trim().slice(0, 400) };
  }
}
function describeNavigation() {
  try {
    return execFileSync(MXCLI, ['-p', MPR, 'describe', 'navigation', 'Responsive'],
      { cwd: ROOT, encoding: 'utf8', timeout: 60000 });
  } catch { return null; }
}

// ── ELK tree walk + the #891 completeness guard ──────────────────────────────
function walkElk(root, visit) {
  const seen = new Set();
  (function rec(node) {
    if (Array.isArray(node)) { for (const n of node) rec(n); return; }
    if (!node || typeof node !== 'object') return;
    if (node.widget && node.id) { if (seen.has(node.id)) return; seen.add(node.id); visit(node); }
    for (const v of Object.values(node)) if (v && typeof v === 'object') rec(v);
  })(root);
}

/**
 * Is the ELK tree a complete read of the page? Four independent symptoms, any one
 * of which means we did not see the whole page. Returns { partial, ... }.
 */
function readCompleteness(doc, mdlNodes) {
  const mdl = String(doc.mdlSource || '');
  const inTree = new Set();
  walkElk(doc.root, (n) => { if (n.name) inTree.add(n.name); });

  // Widgets the page's OWN MDL declares that never appear in the tree.
  const unread = mdlNodes.filter((n) => !inTree.has(n.name)).map((n) => `${n.type} ${n.name}`);

  // The two shapes #891 is known to swallow whole on this project.
  const customContentCols = mdlNodes.filter((n) => n.type === 'column'
    && /ShowContentAs:\s*customContent/i.test(n.props || '')).map((n) => n.name);
  const controlbars = mdlNodes.filter((n) => n.type === 'controlbar').map((n) => n.name);

  // A node the tree reports childless whose MDL twin has a body — the accordion /
  // object-list shape from #891 verbatim.
  const emptyGroups = [];
  const mdlByName = new Map(mdlNodes.map((n) => [n.name, n]));
  walkElk(doc.root, (n) => {
    const kids = ['children', 'rows', 'columns', 'items', 'tabs', 'groups']
      .reduce((a, k) => a + (Array.isArray(n[k]) ? n[k].length : 0), 0);
    const twin = n.name && mdlByName.get(n.name);
    if (kids === 0 && twin && twin.hasBody && /[^\s]/.test(String(twin.body))) {
      emptyGroups.push(`${n.widget} ${n.name}`);
    }
  });

  const partial = unread.length > 0 || customContentCols.length > 0
    || controlbars.length > 0 || emptyGroups.length > 0;
  return {
    partial, treeNodes: inTree.size, mdlDeclared: mdlNodes.length,
    unread, customContentCols, controlbars, emptyGroups,
  };
}

// ── class union (tree ∪ mdlSource) ───────────────────────────────────────────
function classUnion(doc, mdlNodes) {
  const out = new Set();
  walkElk(doc.root, (n) => { for (const c of String(n.class || '').split(/\s+/)) if (c) out.add(c); });
  for (const n of mdlNodes) for (const c of R.classesOf(n)) out.add(c);
  return [...out];
}

// ── page text corpus, for the wireframe region heuristic ─────────────────────
function pageTextCorpus(doc, mdlNodes) {
  const bits = [String(doc.title || '')];
  for (const n of mdlNodes) {
    for (const k of ['Content', 'Caption', 'Label', 'EmptyMessage']) {
      const v = R.unquote(R.prop(n, k));
      if (v) bits.push(v);
    }
    if (n.name) bits.push(n.name.replace(/([a-z])([A-Z])/g, '$1 $2'));
  }
  walkElk(doc.root, (n) => {
    if (n.content) bits.push(String(n.content));
    if (Array.isArray(n.columns)) for (const c of n.columns) if (c.caption) bits.push(String(c.caption));
  });
  return bits.join(' \n ');
}

// ── wireframes ───────────────────────────────────────────────────────────────
function wireframeHeadings(file) {
  try {
    const html = fs.readFileSync(file, 'utf8');
    return [...html.matchAll(/<h[1-3][^>]*>([\s\S]*?)<\/h[1-3]>/gi)]
      .map((m) => m[1].replace(/<[^>]*>/g, ' ').replace(/&[a-z]+;/gi, ' ').replace(/\s+/g, ' ').trim())
      .filter((t) => t && t.length < 90);
  } catch { return []; }
}

// The newest mdlsource script that names this page — the yardstick for wireframe
// staleness. Scanned once and cached, because it is a whole-tree grep.
let MDL_INDEX = null;
function mdlScriptsNaming(qn) {
  if (!MDL_INDEX) {
    MDL_INDEX = [];
    const walk = (d) => {
      let ents = [];
      try { ents = fs.readdirSync(d, { withFileTypes: true }); } catch { return; }
      for (const e of ents) {
        const p = path.join(d, e.name);
        if (e.isDirectory()) walk(p);
        else if (e.name.endsWith('.mdl')) {
          try { MDL_INDEX.push({ file: path.relative(ROOT, p), mtime: fs.statSync(p).mtimeMs, text: fs.readFileSync(p, 'utf8') }); } catch { /* unreadable */ }
        }
      }
    };
    walk(MDLSOURCE);
  }
  // Only scripts that BUILD the page count. Matching any file that merely mentions
  // the name swept in nav edits and grant-only scripts, and made 12 of 14 wireframes
  // look stale — noise that would have trained the reader to ignore the check.
  const builds = new RegExp(`(create\\s+(or\\s+(modify|replace)\\s+)?page|alter\\s+page)\\s+"?${qn.replace('.', '\\.')}"?`, 'i');
  return MDL_INDEX.filter((f) => builds.test(f.text)).sort((a, b) => b.mtime - a.mtime);
}

function wireframeFor(qn, wfFiles) {
  const file = PAGE_WIREFRAME[qn] || null;
  const scripts = mdlScriptsNaming(qn);
  const newestScript = scripts.length ? { file: scripts[0].file, mtime: scripts[0].mtime } : null;
  if (!file) {
    return { file: null, exists: false, mtime: null, headings: [], newestScript,
      why: 'no wireframe was ever drawn for this page (absent from the hand-verified map)' };
  }
  const full = path.join(WIREFRAME_DIR, file);
  if (!wfFiles.includes(file) || !fs.existsSync(full)) {
    return { file, exists: false, mtime: null, headings: [], newestScript,
      why: `mapped wireframe ${file} is missing from design/wireframes/` };
  }
  return { file, exists: true, path: path.relative(ROOT, full), mtime: fs.statSync(full).mtimeMs,
    headings: wireframeHeadings(full), newestScript, why: null };
}

// ── the row contract (docs/verification/report-schema.md) ────────────────────
function row(o) {
  return {
    id: o.id,
    instrument: INSTRUMENT,
    kind: o.kind || 'ui',
    module: o.module ?? null,
    page: o.page ?? null,
    requirement: null,
    title: o.title,
    verdict: o.verdict,
    severity: o.severity || null,
    category: o.category || null,
    provenance: o.provenance || 'measured',
    detail: o.detail,
    ...(o.remediation ? { remediation: o.remediation } : {}),
    ...(o.cite ? { cite: o.cite } : {}),
    ...(o.reason ? { reason: o.reason } : {}),
    ...(o.findings ? { findings: o.findings } : {}),
    measuredAt: nowIso(),
    evidence: o.evidence || [],
  };
}

// ── running one rule against one page context ────────────────────────────────
// The single evaluator, used by the real sweep AND by the positive controls, so a
// control can never prove a code path production does not run.
function runRule(rule, ctx) {
  if (typeof rule.remediate !== 'function') {
    return { verdict: 'fault', detail: `rule ${rule.id} ships no remediate() — a finding with no remediation is a complaint`, findings: [] };
  }
  let res;
  try {
    res = rule.evaluate(ctx);
  } catch (e) {
    return { verdict: 'fault', detail: `rule threw: ${String(e.message).slice(0, 240)}`, findings: [] };
  }
  if (!res || typeof res.ok !== 'boolean') {
    return { verdict: 'fault', detail: 'rule returned no verdict', findings: [] };
  }
  const findings = res.findings || [];
  // Non-vacuity at the rule level: "ok" with findings present is incoherent.
  if (res.ok && findings.length) {
    return { verdict: 'fault', detail: 'rule reported ok while emitting findings — incoherent', findings };
  }
  return {
    verdict: res.ok ? 'pass' : 'fail',
    detail: res.detail || '',
    notApplicable: !!res.notApplicable,
    findings,
    remediation: res.ok ? null : safeRemediate(rule, findings, ctx),
  };
}
function safeRemediate(rule, findings, ctx) {
  try { return rule.remediate(findings, ctx); }
  catch (e) { return `(remediation generator failed: ${String(e.message).slice(0, 120)})`; }
}

// ============================================================================
// STATIC SWEEP — one page at a time
// ============================================================================
function auditPageStatic(qn, wfFiles) {
  const mod = moduleOf(qn);
  const out = { page: qn, module: mod, checks: [], findings: [], verdict: 'pass',
    wireframe: null, completeness: null, screenshot: null, humanJudgement: R.HUMAN_JUDGEMENT };

  const d = describePage(qn);
  if (!d.ok) {
    out.checks.push(row({ id: `${INSTRUMENT}/read/${qn}`, module: mod, page: qn, category: 'completeness',
      title: 'page read from the model', verdict: 'fault', detail: `describe failed: ${d.error}`,
      remediation: `Run \`./mxcli -p ${MPR} describe --format elk page ${qn}\` by hand and fix what it reports. Until this page can be read, nothing about it has been measured.` }));
    out.verdict = 'fault';
    return out;
  }
  const doc = d.doc;
  const parsed = R.parseMdlTree(doc.mdlSource);
  const mdlNodes = parsed.all;

  // Parse failure is a fault for the whole page: every structural rule below reads
  // this tree, and an empty parse would make all of them pass vacuously.
  if (parsed.error || mdlNodes.length === 0) {
    out.checks.push(row({ id: `${INSTRUMENT}/read/${qn}`, module: mod, page: qn, category: 'completeness',
      title: 'page MDL parsed', verdict: 'fault',
      detail: parsed.error || 'MDL parsed to zero widgets — every structural rule would have passed vacuously',
      remediation: `Inspect the raw output of \`./mxcli -p ${MPR} describe --format elk page ${qn}\`. If mdlSource is present but the parser found nothing, that is a page-audit-rules.js parser defect, not a page defect — fix the parser before trusting any verdict for this page.` }));
    out.verdict = 'fault';
    return out;
  }

  const comp = readCompleteness(doc, mdlNodes);
  out.completeness = comp;
  out.checks.push(row({
    id: `${INSTRUMENT}/completeness/${qn}`, module: mod, page: qn, category: 'completeness',
    title: 'the model read is complete (mxcli #891 guard)',
    verdict: comp.partial ? 'fault' : 'pass',
    severity: comp.partial ? 'P2' : null,
    detail: comp.partial
      ? `partially-read: ELK tree has ${comp.treeNodes} of ${comp.mdlDeclared} declared widgets. `
        + `unread=[${comp.unread.slice(0, 8).join(', ')}${comp.unread.length > 8 ? ', …' : ''}] `
        + `customContent columns=[${comp.customContentCols.join(', ')}] controlbars=[${comp.controlbars.join(', ')}] `
        + `empty content slots=[${comp.emptyGroups.join(', ')}]`
      : `ELK tree covers all ${comp.mdlDeclared} declared widgets`,
    cite: 'mxcli issue #891 — object-list content-slot children are never read',
    remediation: comp.partial
      ? `Do not treat this page's mechanical result as a clean sweep — it is not. The structural rules below ran over the page's own mdlSource and are sound, but any tree-only reading (design-audit.js class sweep, a hand DESCRIBE) has not looked at ${comp.unread.length} widget(s). Review those subtrees by hand per ui-review-loop.md, and track mxcli #891.`
      : undefined,
  }));

  const ctx = {
    qn, module: mod, doc, mdl: String(doc.mdlSource || ''), mdlNodes, mdlRoot: parsed.root,
    classes: classUnion(doc, mdlNodes),
    pageText: pageTextCorpus(doc, mdlNodes),
    wireframe: wireframeFor(qn, wfFiles),
  };
  out.wireframe = {
    file: ctx.wireframe.file, exists: ctx.wireframe.exists,
    path: ctx.wireframe.path || null, why: ctx.wireframe.why,
    headings: ctx.wireframe.headings.length,
  };

  // R4: the wireframe rules run in the SAME loop as everything else, and their
  // outcome never gates the others. A missing wireframe is a finding on this page,
  // not a reason to stop grading it.
  for (const rule of [...R.RULES, ...R.WIREFRAME_RULES]) {
    const res = runRule(rule, ctx);
    const chk = row({
      id: `${INSTRUMENT}/${rule.id}/${qn}`, module: mod, page: qn,
      category: rule.category, severity: rule.severity, title: rule.title,
      verdict: res.verdict, provenance: rule.provenance || 'measured',
      detail: res.notApplicable ? `n/a — ${res.detail}` : res.detail,
      cite: rule.cite,
      findings: res.findings.length ? res.findings : undefined,
      remediation: res.remediation || undefined,
    });
    out.checks.push(chk);
    if (res.verdict === 'fail') {
      out.findings.push({
        ruleId: rule.id, category: rule.category, severity: rule.severity,
        title: rule.title, detail: res.detail, cite: rule.cite,
        where: res.findings, remediation: res.remediation,
      });
    }
  }

  // Live rules are declared for every page even when they cannot run, so a
  // --static-only report shows them as `fault` (did not measure) rather than
  // omitting them — an omitted row renders as green.
  return out;
}

// ============================================================================
// LIVE SWEEP — screenshot + the checks only the DOM can answer
// ============================================================================
// The in-browser probe. A pure function of the DOM, so the positive control can
// drive the identical function against a file:// fixture with the app down.
const DOM_PROBE = function () {
  const txt = (document.body && document.body.innerText) || '';
  const errEl = document.querySelector('.mx-dialog-error, .modal-dialog .alert-danger, .mx-name-alerts .alert-danger');
  const listSel = '.mx-datagrid, [class*="widget-datagrid"], .mx-listview, [class*="widget-gallery"]';
  const lists = Array.prototype.slice.call(document.querySelectorAll(listSel)).map(function (el) {
    const rows = el.querySelectorAll('tbody tr, [role="row"]:not([role="columnheader"]), .mx-listview-item, [class*="widget-gallery-item"]').length;
    const name = (String(el.className).match(/mx-name-[\w-]+/) || ['(unnamed)'])[0];
    return { selector: name, rows, hasEmptyText: /no (results|items|records|rows|routes|data)|nothing to show|empty/i.test(el.innerText || '') };
  });
  return {
    textLength: txt.trim().length,
    widgetCount: document.querySelectorAll('[class*="mx-name-"]').length,
    errorDialog: !!errEl, errorDialogText: errEl ? errEl.innerText : null,
    lists,
  };
};

function navMapFromModel() {
  const txt = describeNavigation();
  if (!txt) return { map: new Map(), source: 'unavailable' };
  const map = new Map(); let group = null;
  for (const line of txt.split('\n')) {
    let m = /^\s*menu\s+'([^']+)'\s*\(/.exec(line);
    if (m) { group = m[1]; continue; }
    if (/^\s*\);\s*$/.test(line)) { group = null; continue; }
    m = /^\s*menu item\s+'([^']+)'\s+page\s+([\w.]+);/.exec(line);
    if (m) { map.set(m[2], { group, item: m[1] }); }
  }
  return { map, source: 'describe navigation Responsive' };
}

// App reachability + ownership. We refuse an unverified port for the same reason
// config.js does: on 2026-08-18 :8080 was ANOTHER project's Mendix, and a harness
// pointed at it reports that project's software as ours.
function appStatus() {
  let port = process.env.APP_PORT || null;
  let ownership = port ? 'asserted' : 'unknown';
  let source = port ? 'APP_PORT env' : 'guess';
  if (!port) {
    try {
      const t = fs.readFileSync(path.join(ROOT, '.claude', 'loop', 'stack.env'), 'utf8');
      const p = t.match(/^APP_PORT=(\d+)/m); const o = t.match(/^APP_OWNERSHIP=(\w+)/m);
      if (p) { port = p[1]; source = 'stack.env'; }
      if (o) ownership = o[1];
    } catch { /* never run */ }
  }
  // DEFECT FIXED 2026-08-18: this was a literal 8084 while config.js fell back to
  // 8081. Two instruments in one harness disagreeing about which app they are
  // testing is exactly what test-stack-up.sh's ownership check exists to catch.
  // One fallback, one place: project.config.defaultPort.
  port = port || PROJ.defaultPort;
  return { port, ownership, source, baseUrl: `http://localhost:${port}` };
}

async function liveSweep(pages, perPage) {
  const app = appStatus();
  const rows = [];
  const faultAll = (reason) => {
    for (const qn of pages) {
      for (const rule of R.LIVE_RULES) {
        rows.push(row({
          id: `${INSTRUMENT}/${rule.id}/${qn}`, module: moduleOf(qn), page: qn,
          category: 'live', severity: rule.severity, title: rule.title,
          verdict: 'fault', detail: `not measured: ${reason}`, cite: rule.cite,
          remediation: `Bring the app up (\`./bin/test-stack-up.sh\`) and re-run \`node tests/e2e/page-audit.js\`. Until then this page's rendering, its empty-state behaviour and its screenshot are UNMEASURED — not clean.`,
        }));
      }
      rows.push(row({
        id: `${INSTRUMENT}/live/screenshot/${qn}`, module: moduleOf(qn), page: qn,
        category: 'live', severity: 'P2', title: 'page screenshot captured',
        verdict: 'fault', detail: `not captured: ${reason}`,
        remediation: 'Bring the app up and re-run. Requirement R1 (screenshot every in-scope page) is unmet while this is fault.',
      }));
    }
    return { rows, app, reason };
  };

  if (OPT.staticOnly) return faultAll('--static-only was requested; the app was not driven');
  if (app.ownership !== 'verified' && app.ownership !== 'asserted' && process.env.ALLOW_UNVERIFIED_APP !== '1') {
    return faultAll(`app ownership is "${app.ownership}" for :${app.port} (from ${app.source}) — refusing to measure a Mendix that may belong to another project`);
  }
  // Reachability, before we spend a browser on it.
  const reachable = await new Promise((resolve) => {
    const http = require('http');
    const req = http.get(`${app.baseUrl}/index.html`, (res) => { res.resume(); resolve(res.statusCode < 500); });
    req.on('error', () => resolve(false));
    req.setTimeout(8000, () => { req.destroy(); resolve(false); });
  });
  if (!reachable) return faultAll(`no HTTP answer from ${app.baseUrl}`);

  let chromium;
  try { ({ chromium } = require('playwright')); }
  catch (e) { return faultAll(`playwright is not installed: ${e.message}`); }

  const nav = navMapFromModel();
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  fs.mkdirSync(ARTIFACTS, { recursive: true });

  try {
    // Login. Deliberately NOT using tests/e2e/helpers.js: config.js calls
    // process.exit(2) at require time on an unverified port, which would kill this
    // process before it could write its artifact. Ownership is enforced above instead.
    //
    // DEFECT FIXED 2026-08-18: this used to read APP_USER/APP_PASS while config.js
    // read TEST_USER/TEST_PASS. Setting one pair and not the other ran the UI walk
    // and this audit as two different identities inside one report, silently.
    // PROJ.credentials() is the single resolver — and, unlike ./config, it is a
    // NON-EXITING accessor, so requiring it here does not break the rule above.
    const { user, pass } = PROJ.credentials();
    await page.goto(`${app.baseUrl}/login.html`, { waitUntil: 'domcontentloaded', timeout: 45000 });
    await page.fill('#usernameInput, input[name="username"], #username', user).catch(() => {});
    await page.fill('#passwordInput, input[name="password"], #password', pass).catch(() => {});
    await page.click('#loginButton, button[type="submit"], .login-button').catch(() => {});
    await page.waitForLoadState('networkidle', { timeout: 45000 }).catch(() => {});

    for (const qn of pages) {
      const mod = moduleOf(qn);
      const target = nav.map.get(qn);
      const shot = path.join(ARTIFACTS, `page-audit-${qn}.png`);
      const pp = perPage.find((p) => p.page === qn);
      let navigated = false; let why = null;

      if (!target) {
        why = `no navigation route to this page in ${nav.source} — it cannot be reached by clicking, so it was not measured`;
      } else {
        try {
          // Click, never page.goto: an overlay or off-canvas toggle that swallows
          // clicks is invisible to a direct URL, and that bug has shipped here.
          if (target.group) {
            const g = page.locator(`.mx-navigationtree >> text="${target.group}"`).first();
            if (await g.count()) { await g.click({ timeout: 5000 }).catch(() => {}); await page.waitForTimeout(400); }
          }
          const item = page.locator(`text="${target.item}"`).first();
          await item.click({ timeout: 10000 });
          await page.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {});
          await page.waitForTimeout(600);
          navigated = true;
        } catch (e) {
          why = `clicking nav item "${target.item}" failed: ${String(e.message).slice(0, 160)}`;
        }
      }

      if (!navigated) {
        rows.push(row({ id: `${INSTRUMENT}/live/screenshot/${qn}`, module: mod, page: qn,
          category: 'live', severity: 'P2', title: 'page screenshot captured',
          verdict: 'fault', detail: why,
          remediation: `Give ${qn} a navigation entry point, or record it as a runtime-only entry in .claude/loop/page-scope.json with the microflow that opens it. A page nobody can click to is unreviewable and probably unreachable for users too.` }));
        for (const rule of R.LIVE_RULES) {
          rows.push(row({ id: `${INSTRUMENT}/${rule.id}/${qn}`, module: mod, page: qn,
            category: 'live', severity: rule.severity, title: rule.title, verdict: 'fault',
            detail: `not measured: ${why}`, cite: rule.cite,
            remediation: 'Restore a clickable route to this page, then re-run.' }));
        }
        continue;
      }

      await page.screenshot({ path: shot, fullPage: true }).catch(() => {});
      const captured = fs.existsSync(shot);
      if (pp && captured) pp.screenshot = path.relative(ROOT, shot);
      rows.push(row({ id: `${INSTRUMENT}/live/screenshot/${qn}`, module: mod, page: qn,
        category: 'live', severity: 'P2', title: 'page screenshot captured',
        verdict: captured ? 'pass' : 'fault',
        detail: captured ? path.relative(ROOT, shot) : 'screenshot call produced no file',
        evidence: captured ? [{ type: 'screenshot', path: path.relative(ROOT, shot) }] : [],
        remediation: captured ? undefined : 'Re-run with the app up; a page with no screenshot has not satisfied R1.' }));

      let probe = null;
      try { probe = await page.evaluate(DOM_PROBE); }
      catch (e) { probe = null; why = `DOM probe threw: ${String(e.message).slice(0, 160)}`; }

      for (const rule of R.LIVE_RULES) {
        if (!probe) {
          rows.push(row({ id: `${INSTRUMENT}/${rule.id}/${qn}`, module: mod, page: qn,
            category: 'live', severity: rule.severity, title: rule.title, verdict: 'fault',
            detail: `not measured: ${why}`, cite: rule.cite,
            remediation: 'Re-run with the app up.' }));
          continue;
        }
        const res = runRule(rule, { qn, module: mod, probe });
        rows.push(row({ id: `${INSTRUMENT}/${rule.id}/${qn}`, module: mod, page: qn,
          category: 'live', severity: rule.severity, title: rule.title,
          verdict: res.verdict, detail: res.notApplicable ? `n/a — ${res.detail}` : res.detail,
          cite: rule.cite, findings: res.findings.length ? res.findings : undefined,
          remediation: res.remediation || undefined }));
        if (res.verdict === 'fail' && pp) {
          pp.findings.push({ ruleId: rule.id, category: 'live', severity: rule.severity,
            title: rule.title, detail: res.detail, cite: rule.cite,
            where: res.findings, remediation: res.remediation });
        }
      }
    }
  } finally {
    await browser.close().catch(() => {});
  }
  return { rows, app, reason: null };
}

// ============================================================================
// POSITIVE CONTROLS — one mutant per category, each proving ITS OWN check red
// ============================================================================
// A clean synthetic page that passes every static rule. If the baseline is not
// green, every mutant below is meaningless, so that is asserted first and loudly.
const BASELINE_MDL = `create or modify page Control.Baseline_List (
  Title: 'Baseline List',
  Layout: Atlas_Core.Atlas_TopBar_3,
  Params: { $Filter: Control.BaselineFilter }
) {
  layoutgrid mainGrid {
    row row1 {
      column col1 (DesktopWidth: AutoFill) {
        container crumbStrip (Class: 'crumbs') {
          dynamictext crumbTrail (Content: 'Home > Baseline')
        }
        dynamictext pageHeading (Content: 'Baseline List', RenderMode: H1, Class: 'page-head')
        dataview dataView1 (DataSource: $Filter, Class: 'card spacing-outer-bottom-medium') {
          textbox txtCode (Label: 'Code', Attribute: Code)
          datagrid dgRows (DataSource: microflow Control.DS_Rows, PageSize: 10) {
            column colCode (Attribute: Code, Caption: 'Code')
            column colState (Caption: 'Lifecycle State', ShowContentAs: plainText) {
              dynamictext txtStateBadge (Content: '{1}', ContentParams: [{1} = Lifecycle_state], Class: 'badge badge-info')
            }
          }
          container emptyState (Class: 'empty-state') {
            dynamictext emptyStateTitle (Content: 'No rows match these filters', RenderMode: H3, Class: 'empty-state__title')
          }
          container gridFooter (Class: 'grid-footer') {
            actionbutton btnSearch (Caption: 'Search', ButtonStyle: Primary, Class: 'btn btn-cta')
          }
        }
      }
    }
  }
}

grant view on page Control.Baseline_List to Control.User;
`;

function baselineCtx(mdl) {
  const doc = {
    format: 'wireframe', type: 'page', name: 'Control.Baseline_List', title: 'Baseline List',
    layout: 'Atlas_Core.Atlas_TopBar_3', parameters: [{ name: 'Filter', type: 'Control.BaselineFilter' }],
    root: [], mdlSource: mdl,
  };
  const parsed = R.parseMdlTree(mdl);
  return {
    qn: 'Control.Baseline_List', module: 'Control', doc, mdl, mdlNodes: parsed.all,
    mdlRoot: parsed.root, classes: classUnion(doc, parsed.all),
    pageText: pageTextCorpus(doc, parsed.all),
    wireframe: { file: 'control.html', exists: true, mtime: 2e12, headings: ['Baseline List', 'Rows', 'Search'], newestScript: { file: 'mdlsource/control.mdl', mtime: 1e12 }, why: null },
    parseError: parsed.error, parsedCount: parsed.all.length,
  };
}

function ctlRow(id, fired, detail, extra = {}) {
  return row({
    id: `${INSTRUMENT}/control/${id}`, kind: 'control', category: 'control',
    title: `positive control: ${id}`,
    verdict: fired ? 'pass' : 'fault',
    detail: (fired ? 'MUTANT FIRED: ' : 'MUTANT DID NOT FIRE — the rule is UNPROVEN, which is fault, not pass: ') + detail,
    remediation: fired ? undefined : `Fix the mutant or the rule in tests/e2e/page-audit-rules.js so that ${id} demonstrably goes red, or delete the rule. A rule nobody has watched go red is decoration.`,
    ...extra,
  });
}

async function runControls() {
  const rows = [];
  const staticRules = [...R.RULES, ...R.WIREFRAME_RULES];

  // 0. The baseline must be green, and must parse to a real widget count.
  const base = baselineCtx(BASELINE_MDL);
  const baseResults = new Map();
  for (const rule of staticRules) baseResults.set(rule.id, runRule(rule, base));
  const notGreen = [...baseResults.entries()].filter(([, r]) => r.verdict !== 'pass');
  const baselineOk = base.parsedCount > 10 && !base.parseError && notGreen.length === 0;
  rows.push(ctlRow('baseline-is-green', baselineOk,
    `synthetic clean page parsed to ${base.parsedCount} widgets (parseError=${base.parseError || 'none'}); `
    + (notGreen.length ? `NOT GREEN on: ${notGreen.map(([id, r]) => `${id}=${r.verdict}(${r.detail})`).join(' | ')}` : 'all static rules pass')
    + '. A mutant is only meaningful against a green baseline.'));

  // 1. One mutant per static rule.
  for (const rule of staticRules) {
    if (!rule.mutate && !rule.mutateCtx) {
      rows.push(ctlRow(rule.id, false, 'no mutant is defined for this rule'));
      continue;
    }
    let ctx;
    let applied = true;
    if (rule.mutate) {
      const mutated = rule.mutate(BASELINE_MDL);
      applied = mutated !== BASELINE_MDL;
      ctx = baselineCtx(mutated);
    } else {
      ctx = baselineCtx(BASELINE_MDL);
    }
    if (rule.mutateCtx) rule.mutateCtx(ctx);
    if (!applied) {
      rows.push(ctlRow(rule.id, false, 'the mutant did not change the baseline text at all — it targets a string the baseline does not contain'));
      continue;
    }
    const res = runRule(rule, ctx);
    const fired = res.verdict === 'fail';
    // Cross-fire: a mutant that reddens OTHER rules too is reported, because it
    // means the control does not isolate the rule it claims to prove.
    const cross = staticRules.filter((r2) => r2.id !== rule.id)
      .filter((r2) => runRule(r2, ctx).verdict === 'fail' && baseResults.get(r2.id).verdict === 'pass')
      .map((r2) => r2.id);
    rows.push(ctlRow(rule.id, fired,
      `mutant → ${res.verdict}${res.detail ? ` (${res.detail})` : ''}`
      + (cross.length ? `; CROSS-FIRED onto: ${cross.join(', ')} — the control does not isolate this rule` : '; isolated'),
      { category: rule.category }));
  }

  // 2. The #891 completeness guard, both directions. A guard that never says
  //    "clean" is as useless as one that never says "partial".
  const partialDoc = {
    title: 'X', parameters: [], mdlSource: BASELINE_MDL,
    root: [{ id: 'wf-0', widget: 'accordion', name: 'mainGrid', class: 'acc',
      children: [{ id: 'wf-1', widget: 'accordiongroup', name: 'dgRows' }] }],
  };
  const pNodes = R.parseMdlTree(BASELINE_MDL).all;
  const cPartial = readCompleteness(partialDoc, pNodes);
  rows.push(ctlRow('completeness/partial-detected', cPartial.partial === true,
    `an accordion whose group body is absent from the tree → partial=${cPartial.partial}, unread=${cPartial.unread.length}. `
    + 'This is mxcli #891 verbatim; if it reported clean, the false green is back.'));

  const fullRoot = [];
  (function build(nodes, into) {
    for (const n of nodes) {
      const el = { id: `x-${into.length}-${n.name}`, widget: n.type, name: n.name, children: [] };
      into.push(el);
      if (n.children && n.children.length) build(n.children, el.children);
    }
  })(R.parseMdlTree(BASELINE_MDL).root, fullRoot);
  const cClean = readCompleteness({ title: 'X', parameters: [], mdlSource: BASELINE_MDL, root: fullRoot }, pNodes);
  rows.push(ctlRow('completeness/clean-detected', cClean.partial === false,
    `a tree containing every declared widget → partial=${cClean.partial}. `
    + (cClean.partial ? `still called partial (unread=${cClean.unread.join(', ')}, slots=${cClean.emptyGroups.join(', ')}) — the guard is stuck on "fault" and tells you nothing` : 'the guard can also say clean')));

  // 3. Live rules — two arms. Arm A proves the EVALUATOR goes red on a bad probe.
  //    Arm B proves the DOM PROBE ITSELF works, by running the identical function
  //    Playwright runs against file:// fixtures. Arm A alone would only prove that
  //    fabricated input produces fabricated output.
  for (const rule of R.LIVE_RULES) {
    if (!rule.mutateProbe) { rows.push(ctlRow(rule.id, false, 'no probe mutant defined')); continue; }
    const good = { textLength: 900, widgetCount: 12, errorDialog: false, errorDialogText: null,
      lists: [{ selector: '.mx-name-dgRows', rows: 7, hasEmptyText: false }] };
    const baseRes = runRule(rule, { qn: 'Control.Baseline_List', probe: good });
    const mutRes = runRule(rule, { qn: 'Control.Baseline_List', probe: rule.mutateProbe() });
    rows.push(ctlRow(rule.id, baseRes.verdict === 'pass' && mutRes.verdict === 'fail',
      `evaluator arm: good probe → ${baseRes.verdict}, mutant probe → ${mutRes.verdict}`,
      { category: 'live' }));
  }
  rows.push(await probeFixtureControl());

  return rows;
}

// Arm B: run DOM_PROBE — the exact function used against the live app — over two
// file:// fixtures. Works with the app down, which is the point.
async function probeFixtureControl() {
  let chromium;
  try { ({ chromium } = require('playwright')); }
  catch (e) { return ctlRow('live/dom-probe', false, `playwright unavailable: ${e.message}`, { category: 'live' }); }
  const dir = fs.mkdtempSync(path.join(require('os').tmpdir(), 'page-audit-ctl-'));
  const healthy = path.join(dir, 'healthy.html');
  const sick = path.join(dir, 'sick.html');
  fs.writeFileSync(healthy, `<body><div class="mx-name-page1">${'Real page content. '.repeat(20)}`
    + `<div class="mx-datagrid mx-name-dgRows"><table><tbody><tr><td>a</td></tr><tr><td>b</td></tr></tbody></table></div></div></body>`);
  fs.writeFileSync(sick, '<body><div class="mx-dialog-error">An error occurred</div>'
    + '<div class="mx-datagrid mx-name-dgRows"><table><tbody></tbody></table></div></body>');
  let detail; let fired = false;
  const browser = await chromium.launch();
  try {
    const pg = await browser.newPage();
    await pg.goto('file://' + healthy, { waitUntil: 'load' });
    const g = await pg.evaluate(DOM_PROBE);
    await pg.goto('file://' + sick, { waitUntil: 'load' });
    const b = await pg.evaluate(DOM_PROBE);
    const gOk = g.textLength > 120 && !g.errorDialog && g.lists.length === 1 && g.lists[0].rows === 2;
    const bOk = b.errorDialog === true && b.lists.length === 1 && b.lists[0].rows === 0;
    fired = gOk && bOk;
    detail = `healthy fixture → ${JSON.stringify(g).slice(0, 200)}; sick fixture → ${JSON.stringify(b).slice(0, 200)}`;
  } catch (e) {
    detail = `fixture run threw: ${String(e.message).slice(0, 200)}`;
  } finally { await browser.close().catch(() => {}); }
  return ctlRow('live/dom-probe', fired,
    `the DOM probe function itself, run by Playwright over file:// fixtures — ${detail}`, { category: 'live' });
}

// ============================================================================
// AGGREGATION + OUTPUT
// ============================================================================
const PRECEDENCE = { fault: 3, fail: 2, pass: 1, skipped: 0 };
function worst(verdicts) {
  // Non-vacuity: an empty verdict list is NEVER a pass. A page with zero checks is
  // a page we did not measure.
  if (!verdicts.length) return 'fault';
  return verdicts.reduce((a, v) => (PRECEDENCE[v] > PRECEDENCE[a] ? v : a), 'pass');
}

function main() {
  const startedAt = nowIso();
  fs.mkdirSync(ARTIFACTS, { recursive: true });

  // ── scope ──────────────────────────────────────────────────────────────────
  let scope = null; let scopeErr = null;
  try { scope = JSON.parse(fs.readFileSync(SCOPE_FILE, 'utf8')); }
  catch (e) { scopeErr = `${path.relative(ROOT, SCOPE_FILE)} unreadable: ${e.message}`; }
  let pages = scope && Array.isArray(scope.inScope) ? scope.inScope.slice() : [];
  if (OPT.page) pages = pages.includes(OPT.page) ? [OPT.page] : [OPT.page];

  const checks = []; const instruments = [];

  if (!pages.length) {
    checks.push(row({ id: `${INSTRUMENT}/scope`, kind: 'conformance', category: 'completeness',
      title: 'in-scope page set resolved', verdict: 'fault',
      detail: scopeErr || 'no pages resolved from page-scope.json',
      remediation: 'Regenerate the scope with bin/loop/page-scope.sh. Zero pages is not a clean audit — it is an audit that did not happen.' }));
    return finish({ startedAt, checks, instruments: [{ name: INSTRUMENT, verdict: 'fault', reason: scopeErr || 'no pages in scope' }], perPage: [], controlRows: [] });
  }
  checks.push(row({ id: `${INSTRUMENT}/scope`, kind: 'conformance', category: 'completeness',
    title: 'in-scope page set resolved', verdict: 'pass',
    detail: `${pages.length} pages from ${path.relative(ROOT, SCOPE_FILE)} (of ${scope.counts ? scope.counts.pagesTotal : '?'} total)` }));

  const wfFiles = fs.existsSync(WIREFRAME_DIR) ? fs.readdirSync(WIREFRAME_DIR).filter((f) => f.endsWith('.html')) : [];

  // ── control run: separate artifact, never mixed with a real run ────────────
  if (OPT.positiveControl) {
    return runControls().then((controlRows) => {
      const out = path.join(ARTIFACTS, 'page-audit-control.json');
      const allFired = controlRows.length > 0 && controlRows.every((r) => r.verdict === 'pass');
      fs.writeFileSync(out, JSON.stringify({
        schemaVersion: SCHEMA_VERSION, instrument: `${INSTRUMENT}-positive-control`,
        startedAt, finishedAt: nowIso(), controls: controlRows,
        summary: { total: controlRows.length, fired: controlRows.filter((r) => r.verdict === 'pass').length },
      }, null, 2));
      for (const r of controlRows) {
        console.log(`  control ${r.verdict === 'pass' ? 'FIRED  ' : 'UNPROVEN'} ${r.id.replace(`${INSTRUMENT}/control/`, '')}`);
        if (r.verdict !== 'pass') console.log(`      ${r.detail}`);
      }
      console.log(`\n  ${controlRows.filter((r) => r.verdict === 'pass').length}/${controlRows.length} controls fired → ${out}`);
      process.exitCode = allFired ? 0 : 2;
    }).catch((e) => { console.error(`control run threw: ${e.stack}`); process.exitCode = 2; });
  }

  // ── static sweep ───────────────────────────────────────────────────────────
  const perPage = [];
  for (const qn of pages) {
    const p = auditPageStatic(qn, wfFiles);
    perPage.push(p);
    checks.push(...p.checks);
  }

  // ── live sweep ─────────────────────────────────────────────────────────────
  return liveSweep(pages, perPage).then((live) => {
    checks.push(...live.rows);
    for (const p of perPage) {
      const mine = checks.filter((c) => c.page === p.page);
      p.verdict = worst(mine.map((c) => c.verdict));
      p.checkCount = mine.length;
      p.counts = mine.reduce((a, c) => { a[c.verdict] = (a[c.verdict] || 0) + 1; return a; }, {});
    }

    // Wireframe coverage — a headline number in its own right.
    const withWf = perPage.filter((p) => p.wireframe && p.wireframe.exists);
    const coverage = {
      inScopePages: perPage.length,
      withWireframe: withWf.length,
      withoutWireframe: perPage.length - withWf.length,
      ratio: perPage.length ? +(withWf.length / perPage.length).toFixed(3) : null,
      pagesWithNoWireframe: perPage.filter((p) => !(p.wireframe && p.wireframe.exists)).map((p) => p.page),
      wireframesWithNoInScopePage: wfFiles.filter((f) => !Object.values(PAGE_WIREFRAME).includes(f)),
    };

    instruments.push({
      name: INSTRUMENT,
      verdict: checks.some((c) => c.verdict === 'fault') ? 'fault' : 'pass',
      canExpressFault: true,
      reason: OPT.staticOnly ? 'ran --static-only: every live check is fault, not pass' : null,
    });
    instruments.push(OPT.positiveControl
      ? { name: `${INSTRUMENT}-positive-control`, verdict: 'pass', reason: null }
      : { name: `${INSTRUMENT}-positive-control`, verdict: 'fault',
        reason: 'not requested in this run (--positive-control absent) — the rules are unproven for THIS invocation; see page-audit-control.json for the last proving run' });

    return finish({ startedAt, checks, instruments, perPage, coverage, app: live.app, controlRows: [] });
  });
}

function finish({ startedAt, checks, instruments, perPage, coverage, app, controlRows }) {
  const tally = checks.reduce((a, c) => { a[c.verdict] = (a[c.verdict] || 0) + 1; return a; }, {});
  const artifact = {
    schemaVersion: SCHEMA_VERSION,
    instrument: INSTRUMENT,
    // Deliberately NOT merged into docs/report.json by this file: report-normalize.js
    // is owned by another workstream. The shape below is designed to be consumed by
    // it — `checks[]` already conforms to docs/verification/report-schema.md §checks,
    // and `perPage[]` is the per-page section a renderer can group on directly.
    consumedBy: 'docs/verification/page-audit.md documents the contract; wire-up is a separate change',
    run: {
      startedAt, finishedAt: nowIso(),
      mode: OPT.staticOnly ? 'static-only' : 'static+live',
      app: app || null,
      argv,
    },
    coverage: coverage || null,
    summary: {
      pages: perPage.length,
      pageVerdicts: perPage.reduce((a, p) => { a[p.verdict] = (a[p.verdict] || 0) + 1; return a; }, {}),
      checks: checks.length,
      verdicts: tally,
      findings: perPage.reduce((a, p) => a + p.findings.length, 0),
      findingsBySeverity: perPage.flatMap((p) => p.findings).reduce((a, f) => { a[f.severity] = (a[f.severity] || 0) + 1; return a; }, {}),
    },
    humanJudgement: R.HUMAN_JUDGEMENT,
    instruments,
    perPage,
    checks,
    controls: controlRows,
  };
  // A single-page run must NOT overwrite the corpus artifact: it did once during
  // development, and the resulting file looked like a clean 2-finding audit of the
  // whole app. Partial runs get their own filename.
  const out = OPT.out
    || path.join(ARTIFACTS, OPT.page ? `page-audit-${OPT.page}.json` : 'page-audit.json');
  fs.writeFileSync(out, JSON.stringify(artifact, null, 2));

  // ── console summary ────────────────────────────────────────────────────────
  console.log(`\npage-audit — ${artifact.run.mode} — ${perPage.length} pages, ${checks.length} checks`);
  if (coverage) {
    console.log(`wireframe coverage: ${coverage.withWireframe}/${coverage.inScopePages} in-scope pages have one `
      + `(${coverage.withoutWireframe} do not: ${coverage.pagesWithNoWireframe.join(', ') || 'none'})`);
  }
  for (const p of perPage) {
    const f = p.findings.length;
    console.log(`  ${p.verdict.toUpperCase().padEnd(5)} ${p.page.padEnd(42)} ${p.checkCount || 0} checks, ${f} finding${f === 1 ? '' : 's'}`
      + (p.wireframe && !p.wireframe.exists ? '  [NO WIREFRAME]' : ''));
  }
  console.log(`\nverdicts: ${JSON.stringify(tally)}  →  ${out}`);

  const anyFault = checks.some((c) => c.verdict === 'fault');
  const anyFail = checks.some((c) => c.verdict === 'fail');
  process.exitCode = anyFault ? 2 : (anyFail ? 1 : 0);
  return artifact;
}

if (require.main === module) {
  try {
    const r = main();
    if (r && typeof r.then === 'function') r.catch((e) => { console.error(e.stack); process.exitCode = 2; });
  } catch (e) { console.error(e.stack); process.exitCode = 2; }
}

module.exports = { auditPageStatic, readCompleteness, worst, DOM_PROBE, PAGE_WIREFRAME };
