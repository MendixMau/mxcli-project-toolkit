'use strict';
// ============================================================================
// design-audit.js — the UI-quality instrument (rungs 6 and 7)
// ----------------------------------------------------------------------------
//   node tests/e2e/design-audit.js                      # full run (needs the app up)
//   node tests/e2e/design-audit.js --static-only        # model+CSS only, app may be down
//   node tests/e2e/design-audit.js --page Equipment.Item_Detail
//   node tests/e2e/design-audit.js --positive-control   # prove each rung can go red
//
// Output: tests/e2e/artifacts/design-audit.json  (checks[] merge into docs/report.json)
//         tests/e2e/artifacts/design-audit-control.json  (--positive-control; own file,
//         because a control run must never overwrite a real run — journey-proof §control)
//
// WHY THIS FILE EXISTS, AND THE THREE THINGS IT REFUSES TO DO
//
// 1. It refuses to omit a page. An omitted row renders as green. Every in-scope page
//    gets a row for every check, and a page that could not be read gets `fault` rows
//    with a reason, never silence.
//
// 2. It refuses to sweep a tree it knows is incomplete and call the result clean.
//    MEASURED on this project (RoutingManagement.Route_List, 2026-08-18): the ELK
//    describe tree contains 13 widget nodes; the page's own `mdlSource` in the SAME
//    response declares 27. The entire `controlbar` subtree and both `customContent`
//    column bodies are absent from the tree — with them, the classes `filter-stack`,
//    `page-actions`, `filter-stack__actions`, `btn-cta`, `badge-info` and 8 widgets.
//    That is mxcli issue #891 (content-slot children are never read). A class sweep
//    over the tree alone reports Route_List clean WITHOUT HAVING LOOKED at half of it.
//    So: classes are extracted from the UNION of tree and mdlSource, and any page whose
//    tree is provably shorter than its own MDL is stamped `partially-read`, which
//    renders as `fault`. Never `pass`.
//
// 3. It refuses to call an app-dependent check `pass` when the app was not there.
//    `--static-only` marks them `skipped` with a reason. A page with no navigation
//    route is `fault`, not skipped — we could not measure it and we know it.
//
// NON-VACUITY. Every rung carries its own mutant (`--positive-control`), each of which
// must turn its OWN check red and leave the others alone. A rung whose mutant did not
// fire is reported `fault`. `[].every()` is `true`, so every assertion below guards
// non-emptiness before it concludes anything.
// ============================================================================

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const os = require('os');

// project.config.js is the only project-aware file in tests/e2e/, and it has no
// side effects at require time (unlike ./config, which can process.exit(2)).
const PROJ = require('./project.config');

const ROOT = PROJ.root;
const MPR = PROJ.mprName;
const MXCLI = path.join(ROOT, 'mxcli');
const ARTIFACTS = path.join(__dirname, 'artifacts');
const SCOPE_FILE = path.join(ROOT, '.claude', 'loop', 'page-scope.json');
const DS_CSS = path.join(ROOT, 'design', 'ds.css');
const WIREFRAME_DIR = path.join(ROOT, 'design', 'wireframes');
const THEME_CSS = [
  path.join(ROOT, 'deployment', 'web', 'theme.compiled.css'),
  path.join(ROOT, 'deployment', 'web', 'dist', 'widgets.css'),
];
const SCHEMA_VERSION = '1.1';

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

// ============================================================================
// 1. CSS — which classes are actually DEFINED, and where
// ============================================================================
// Selector-position only: we walk the file tracking brace depth and harvest class
// tokens from the text that PRECEDES an opening brace. Harvesting the whole file
// would pick up `content: ".foo"` and url fragments and quietly define classes that
// no rule ever declares — which turns the invented-class check into decoration.
function classesInCss(text) {
  const out = new Set();
  const src = text.replace(/\/\*[\s\S]*?\*\//g, '');
  let depth = 0, buf = '';
  for (let i = 0; i < src.length; i++) {
    const c = src[i];
    if (c === '{') {
      if (depth === 0) harvest(buf, out);
      buf = ''; depth++;
    } else if (c === '}') {
      depth = Math.max(0, depth - 1); buf = '';
    } else if (depth === 0) {
      buf += c;
      if (buf.length > 8000) buf = buf.slice(-4000);
    }
  }
  return out;
}
function harvest(selectorText, out) {
  // `-?[_a-zA-Z]` first char keeps `.5em` and `.75rem` out of the class set.
  const re = /\.(-?[_a-zA-Z][A-Za-z0-9_-]*)/g;
  let m;
  while ((m = re.exec(selectorText))) out.add(m[1]);
}

function readCssSet(files) {
  const set = new Set(); const read = []; const missing = [];
  for (const f of files) {
    if (!fs.existsSync(f)) { missing.push(f); continue; }
    for (const c of classesInCss(fs.readFileSync(f, 'utf8'))) set.add(c);
    read.push(f);
  }
  return { set, read, missing };
}

// Wireframe-only chrome: classes DEFINED in a wireframe's own inline <style> and
// nowhere in the shipped stylesheets. Derived, not hardcoded — a hardcoded
// ["annotation"] list would miss `ann-block`, which is what this project actually uses.
function wireframeInlineClasses() {
  const perFile = new Map(); const all = new Set();
  if (!fs.existsSync(WIREFRAME_DIR)) return { perFile, all, files: [] };
  const files = fs.readdirSync(WIREFRAME_DIR).filter((f) => f.endsWith('.html'));
  for (const f of files) {
    const html = fs.readFileSync(path.join(WIREFRAME_DIR, f), 'utf8');
    const set = new Set();
    for (const m of html.matchAll(/<style[^>]*>([\s\S]*?)<\/style>/gi)) {
      for (const c of classesInCss(m[1])) { set.add(c); all.add(c); }
    }
    perFile.set(f, set);
  }
  return { perFile, all, files };
}

function wireframeRefClasses(file) {
  const html = fs.readFileSync(path.join(WIREFRAME_DIR, file), 'utf8');
  const out = new Set();
  for (const m of html.matchAll(/class\s*=\s*"([^"]*)"/g)) {
    for (const t of m[1].split(/\s+/)) if (t) out.add(t);
  }
  return out;
}

// ============================================================================
// 2. The model — read-only. `describe --format elk` never writes to the .mpr.
// ============================================================================
function describePage(qn) {
  try {
    const raw = execFileSync(MXCLI, ['-p', MPR, 'describe', '--format', 'elk', 'page', qn],
      { cwd: ROOT, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, timeout: 120000 });
    return { ok: true, doc: JSON.parse(raw), bytes: raw.length };
  } catch (e) {
    return { ok: false, error: (e.stderr || e.message || String(e)).toString().trim().slice(0, 500) };
  }
}

function describeNavigation() {
  try {
    return execFileSync(MXCLI, ['-p', MPR, 'describe', 'navigation', 'Responsive'],
      { cwd: ROOT, encoding: 'utf8', timeout: 60000 });
  } catch (e) { return null; }
}

// ── ELK tree walk. Children hide in `children`, in `rows[].columns[].children`,
// and in whatever nesting a future widget invents — so recurse every array.
function walkElk(root, visit) {
  const seen = new Set();
  (function rec(node, parent) {
    if (Array.isArray(node)) { for (const n of node) rec(n, parent); return; }
    if (!node || typeof node !== 'object') return;
    let self = parent;
    if (node.widget && node.id) {
      if (seen.has(node.id)) return;
      seen.add(node.id);
      visit(node, parent);
      self = node;
    }
    for (const v of Object.values(node)) if (v && typeof v === 'object') rec(v, self);
  })(root, null);
}

function elkNodes(doc) {
  const nodes = [];
  walkElk(doc.root, (n, p) => nodes.push({ node: n, parent: p }));
  return nodes;
}

function splitClasses(s) {
  return String(s || '').split(/\s+/).map((x) => x.trim()).filter(Boolean);
}

// ── mdlSource parsing. The MDL is the fuller of the two views (see header note 2),
// so it is the primary source for classes and the yardstick for completeness.
// Structural MDL keywords that are not widget instances and never appear as ELK nodes.
// `placeholder` belongs here: it is a layout slot, its children DO come through, and
// counting it as unread reported two phantom findings on FieldScan.Move_Scan.
const MDL_NON_WIDGET_TYPES = new Set([
  'row', 'column', 'controlbar', 'create', 'grant', 'menu', 'page', 'snippet', 'layout',
  'placeholder',
]);
// NOT excluded, deliberately: `group` (accordion groups). This project has no accordion
// to verify against, and a phantom "unread" errs toward fault, which is recoverable —
// excluding it would risk the false green this guard exists to prevent.
function mdlClasses(src) {
  const out = new Set();
  for (const m of String(src || '').matchAll(/\bClass:\s*(['"])([^'"]*)\1/g)) {
    for (const c of splitClasses(m[2])) out.add(c);
  }
  return out;
}
function mdlWidgetInstances(src) {
  const out = [];
  for (const line of String(src || '').split('\n')) {
    const m = /^\s*([a-z][a-z0-9]*)\s+("?)([A-Za-z_][A-Za-z0-9_]*)\2\s*[({]/.exec(line);
    if (!m) continue;
    if (MDL_NON_WIDGET_TYPES.has(m[1])) continue;
    out.push({ type: m[1], name: m[3] });
  }
  return out;
}
function mdlDesignPropKeys(src) {
  const out = new Set();
  for (const m of String(src || '').matchAll(/DesignProperties:\s*\[([^\]]*)\]/g)) {
    for (const k of m[1].matchAll(/'([^']+)'\s*:/g)) out.add(k[1]);
  }
  return out;
}

// ============================================================================
// 3. mxcli #891 — the false-green guard
// ============================================================================
// Structural, not name-based: we never look for the word "accordion". We compare the
// widget instances the page's own MDL declares against the nodes the ELK tree carries.
// Anything declared and not carried is a slot describe did not read. Also flagged
// independently: `ShowContentAs: customContent` columns and `controlbar` blocks, whose
// bodies the tree has no representation for at all.
function readCompleteness(doc) {
  const mdl = String(doc.mdlSource || '');
  const declared = mdlWidgetInstances(mdl);
  const inTree = new Set();
  walkElk(doc.root, (n) => { if (n.name) inTree.add(n.name); });

  const unread = declared.filter((w) => !inTree.has(w.name));
  // `ShowContentAs: customContent` is frequently on a continuation line, so the probe
  // must span the whole `column X ( … )` head, not one line of it.
  const customContentCols = [...mdl.matchAll(/^\s*column\s+("?)([A-Za-z_][\w]*)\1\s*\(([^)]*)\)/gm)]
    .filter((m) => /ShowContentAs:\s*customContent/.test(m[3])).map((m) => m[2]);
  const controlbars = [...mdl.matchAll(/^\s*controlbar\s+([A-Za-z_][\w]*)/gm)].map((m) => m[1]);

  // An empty group in the tree where the MDL has a body is the accordion/object-list
  // shape from #891 verbatim.
  const emptyGroups = [];
  walkElk(doc.root, (n) => {
    const kids = Array.isArray(n.children) ? n.children.length : 0;
    const arrays = ['rows', 'columns', 'items', 'tabs', 'groups'];
    const otherKids = arrays.reduce((a, k) => a + (Array.isArray(n[k]) ? n[k].length : 0), 0);
    // Only simple identifiers, so the probe regex needs no escaping and cannot
    // accidentally match on a metacharacter in a widget name.
    if (kids === 0 && otherKids === 0 && n.name && /^[A-Za-z_][A-Za-z0-9_]*$/.test(n.name)) {
      // The `{` must END the line — a body opener. Matching any `{` on the line made
      // `dynamictext dtMvItem (Content: '{1}', ContentParams: [{1} = ItemCode])` look
      // like a container with an unread body.
      const re = new RegExp(`\\b${n.name}\\b[^\\n]*\\{\\s*$`, 'm');
      if (re.test(mdl)) emptyGroups.push({ name: n.name, widget: n.widget });
    }
  });

  const partial = unread.length > 0 || customContentCols.length > 0
    || controlbars.length > 0 || emptyGroups.length > 0;
  return {
    partial,
    treeNodes: inTree.size,
    mdlDeclared: declared.length,
    unread: unread.map((w) => `${w.type} ${w.name}`),
    customContentCols,
    controlbars,
    emptyGroups,
  };
}

// ============================================================================
// 4. Class extraction for one page (union of both views)
// ============================================================================
function pageClassUsage(doc) {
  const fromTree = new Map();   // class -> [widget names]
  const nodes = elkNodes(doc);
  for (const { node } of nodes) {
    for (const c of splitClasses(node.class)) {
      if (!fromTree.has(c)) fromTree.set(c, []);
      fromTree.get(c).push(node.name || node.id);
    }
  }
  const fromMdl = mdlClasses(doc.mdlSource);
  const all = new Set([...fromTree.keys(), ...fromMdl]);
  return { all, fromTree, fromMdl, nodes };
}

// ── The Mendix-specific rule: a raw class where a sanctioned design property exists.
// Only classes that map onto a real Atlas design property are flagged; a design-system
// class like `kt-badge` is not a spacing hack and must not be reported as one.
const DESIGN_PROP_EQUIVALENTS = [
  { re: /^spacing-(inner|outer)-(top|bottom|left|right)?-?(none|smallest|small|medium|large|largest)$/, prop: 'Spacing' },
  { re: /^flex-(row|column)$/, prop: 'Flex container' },
  { re: /^align-items-/, prop: 'Align items X / Y' },
  { re: /^justify-content-/, prop: 'Align items X' },
  { re: /^background-color-/, prop: 'Background color' },
  { re: /^text-align-/, prop: 'Text align' },
];
function rawClassOverDesignProperty(doc, usage) {
  const hits = [];
  for (const { node } of usage.nodes) {
    const cls = splitClasses(node.class);
    if (!cls.length) continue;
    const props = new Set((node.designProperties || []).map((p) => p.key));
    for (const c of cls) {
      const rule = DESIGN_PROP_EQUIVALENTS.find((r) => r.re.test(c));
      if (rule) hits.push({ widget: node.name || node.id, class: c, property: rule.prop, alsoHasProperty: props.has(rule.prop) });
    }
  }
  // mdlSource carries the nodes the tree drops (#891), so sweep it too.
  const mdlProps = mdlDesignPropKeys(doc.mdlSource);
  for (const c of mdlClasses(doc.mdlSource)) {
    const rule = DESIGN_PROP_EQUIVALENTS.find((r) => r.re.test(c));
    if (rule && !hits.some((h) => h.class === c)) {
      hits.push({ widget: '(from mdlSource — node absent from ELK tree)', class: c, property: rule.prop, alsoHasProperty: mdlProps.has(rule.prop) });
    }
  }
  return hits;
}

// ============================================================================
// 5. page -> wireframe mapping
// ============================================================================
// The map itself lives in project.config.js — it is a statement about THIS model.
// It used to be duplicated here and in page-audit.js as two near-identical literals,
// which is two chances to drift and no way to notice. Read the reasoning (why it is
// hand-verified and never fuzzy-matched) at the map's definition; the consequence
// here is that an unmapped page is `skipped` and covered by rung 7, which is the
// entire reason rung 7 exists.
const PAGE_WIREFRAME = PROJ.PAGE_WIREFRAME;

function mapPageToWireframe(qn, wfFiles) {
  const f = PAGE_WIREFRAME[qn];
  if (!f) return { file: null, why: 'no wireframe was drawn for this page (not in the hand-verified map)' };
  if (!wfFiles.includes(f)) return { file: null, why: `mapped wireframe ${f} is missing from design/wireframes` };
  return { file: f, why: null };
}

// Annotation chrome: wireframe-only styling that must never reach a real page. Two
// arms, because neither alone is complete — `ann`/`ann-block` are defined only in the
// wireframes' inline <style> (arm 1), while `wf-note` was promoted into ds.css and
// would slip past arm 1 entirely (arm 2).
const CHROME_NAME = /^(ann|ann-.*|annotation.*|wf-note.*|wireframe-.*)$/;

// THE differ. One function, used by the real sweep AND by the positive control, so a
// control can never end up proving a differ that production does not run.
function classifyClasses(referenced, css, wfAll) {
  const chrome = referenced.filter((c) => CHROME_NAME.test(c) || (wfAll.has(c) && !css.ds.has(c) && !css.theme.has(c)));
  const invented = referenced.filter((c) => !css.ds.has(c) && !css.theme.has(c) && !chrome.includes(c));
  const neverPromoted = referenced.filter((c) => css.ds.has(c) && !css.theme.has(c));
  return { chrome, invented, neverPromoted };
}

// ============================================================================
// 6. App-dependent checks (rung 7 #2, #3, #4). Pure functions over a Playwright page,
//    so the positive controls can drive them against /tmp fixtures with the app down.
// ============================================================================
async function checkA11y(page, axeSource) {
  await page.evaluate(axeSource);
  const res = await page.evaluate(async () => {
    /* global axe */
    return await axe.run(document, { runOnly: { type: 'tag', values: ['wcag2a', 'wcag2aa', 'wcag21aa'] } });
  });
  const bad = (res.violations || []).filter((v) => v.impact === 'serious' || v.impact === 'critical');
  return {
    ran: true,
    totalViolations: (res.violations || []).length,
    seriousOrCritical: bad.length,
    testedRules: (res.passes || []).length + (res.violations || []).length + (res.incomplete || []).length,
    items: bad.map((v) => ({ id: v.id, impact: v.impact, nodes: v.nodes.length, help: v.help })),
  };
}

async function checkOverflow(page, widths = [360, 768, 1440]) {
  const out = [];
  for (const w of widths) {
    await page.setViewportSize({ width: w, height: 900 });
    await page.waitForTimeout(250);
    const m = await page.evaluate(() => ({
      scrollWidth: document.body.scrollWidth,
      clientWidth: document.body.clientWidth,
      docScroll: document.documentElement.scrollWidth,
      docClient: document.documentElement.clientWidth,
    }));
    out.push({ width: w, ...m, overflows: m.scrollWidth > m.clientWidth });
  }
  return out;
}

async function checkStructure(page) {
  const snapshot = await page.locator('body').ariaSnapshot().catch(() => null);
  const dom = await page.evaluate(() => ({
    h1: [...document.querySelectorAll('h1')].map((e) => (e.textContent || '').trim().slice(0, 60)),
    landmarks: [...document.querySelectorAll('main,nav,header,footer,aside,[role=main],[role=navigation],[role=banner],[role=contentinfo]')]
      .map((e) => e.tagName.toLowerCase() + (e.getAttribute('role') ? `[role=${e.getAttribute('role')}]` : '')),
  }));
  return { snapshot, h1Count: dom.h1.length, h1Text: dom.h1, landmarks: [...new Set(dom.landmarks)] };
}

// ── navigation map, derived from the live navigation document
function buildNavMap() {
  const txt = describeNavigation();
  if (!txt) return { map: new Map(), source: 'unavailable' };
  const map = new Map();
  let group = null;
  for (const line of txt.split('\n')) {
    let m = /^\s*menu\s+'([^']+)'\s*\(/.exec(line);
    if (m) { group = m[1]; continue; }
    if (/^\s*\);\s*$/.test(line)) { group = null; continue; }
    m = /^\s*menu item\s+'([^']+)'\s+page\s+([\w.]+);/.exec(line);
    if (m) { map.set(m[2], { group, item: m[1], via: 'page' }); continue; }
    m = /^\s*menu item\s+'([^']+)'\s+microflow\s+([\w.]+);/.exec(line);
    if (m) map.set(`microflow:${m[2]}`, { group, item: m[1], via: 'microflow' });
  }
  // Resolve microflow-opened items onto pages by module + name tokens. Inference is
  // labelled as such in the row detail; it is never presented as measured routing.
  for (const [k, v] of [...map]) {
    if (!k.startsWith('microflow:')) continue;
    const mf = k.slice('microflow:'.length);
    const mod = mf.split('.')[0];
    const guess = `${mod}.${v.item.replace(/\s+/g, '_')}`;
    if (!map.has(guess)) map.set(guess, { ...v, inferredFrom: mf });
  }
  return { map, source: 'describe navigation Responsive' };
}

// ============================================================================
// 7. Row helpers — the schema contract
// ============================================================================
function row(o) {
  return {
    id: o.id,
    instrument: 'design-audit',
    kind: o.kind || 'ui',
    module: o.module ?? null,
    page: o.page ?? null,
    requirement: null,
    title: o.title,
    verdict: o.verdict,
    provenance: o.provenance || 'measured',
    detail: o.detail,
    measuredAt: nowIso(),
    ...(o.nonVacuity ? { nonVacuity: o.nonVacuity } : {}),
    ...(o.blockedBy ? { blockedBy: o.blockedBy } : {}),
    ...(o.reason ? { reason: o.reason } : {}),
    ...(o.tags ? { tags: o.tags } : {}),
    evidence: o.evidence || [],
  };
}
const moduleOf = (qn) => (qn && qn.includes('.') ? qn.split('.')[0] : null);

// ============================================================================
// 8. The static sweep (rung 6 + rung 7 check 1 + #891 guard)
// ============================================================================
function staticSweep(pages, css, wf, controlNotes) {
  const checks = [];
  const stats = {
    pagesRead: 0, pagesFault: 0, partiallyRead: 0,
    inventedClassPages: 0, inventedClasses: new Set(),
    neverPromotedPages: 0, neverPromotedClasses: new Set(),
    chromePages: 0, chromeClasses: new Set(),
    rawClassPages: 0, rawClassHits: 0,
    wireframeMatched: 0, wireframeMissing: 0,
  };
  const perPage = [];

  for (const qn of pages) {
    const mod = moduleOf(qn);
    const res = describePage(qn);
    if (!res.ok) {
      stats.pagesFault++;
      const rid = `design-audit/read/${qn}`;
      checks.push(row({
        id: rid, module: mod, page: qn, title: 'page readable by describe --format elk',
        verdict: 'fault', detail: `describe failed: ${res.error}`,
        evidence: [{ type: 'command', command: `./mxcli -p ${MPR} describe --format elk page ${qn}` }],
      }));
      for (const [suffix, title] of [
        ['rung6/wireframe-conformance', 'wireframe conformance (class-promotion diff)'],
        ['rung6/invented-class', 'no invented classes'],
        ['rung6/never-promoted', 'ds.css classes promoted to the deployed theme'],
        ['rung6/wireframe-chrome', 'no wireframe-only chrome in a real page'],
        ['rung7/unmatched-class', 'every referenced class is defined somewhere'],
        ['rung7/raw-class-vs-designproperty', 'no raw class where a design property exists'],
      ]) {
        checks.push(row({
          id: `design-audit/${suffix}/${qn}`,
          module: mod, page: qn, title, verdict: 'fault', provenance: 'declared',
          detail: 'page could not be read; this check never ran',
          blockedBy: rid,
        }));
      }
      perPage.push({ page: qn, read: false });
      continue;
    }
    stats.pagesRead++;
    const doc = res.doc;
    const comp = readCompleteness(doc);
    const usage = pageClassUsage(doc);

    // ── #891 guard ─────────────────────────────────────────────────────────
    const readId = `design-audit/read/${qn}/complete`;
    checks.push(row({
      id: readId, module: mod, page: qn,
      title: 'ELK tree carries the whole page (mxcli #891 content-slot guard)',
      verdict: comp.partial ? 'fault' : 'pass',
      detail: comp.partial
        ? `partially-read: describe returned ${comp.treeNodes} tree nodes for ${comp.mdlDeclared} widgets declared in the page's own mdlSource. `
          + `Unread widgets: ${comp.unread.length ? comp.unread.join(', ') : 'none by name'}. `
          + `customContent columns: ${comp.customContentCols.join(', ') || 'none'}. `
          + `controlbars: ${comp.controlbars.join(', ') || 'none'}. `
          + `empty groups: ${comp.emptyGroups.map((g) => `${g.widget} ${g.name}`).join(', ') || 'none'}. `
          + 'Every class finding below is therefore a LOWER BOUND, not a clean bill of health.'
        : `describe returned ${comp.treeNodes} tree nodes for ${comp.mdlDeclared} declared widgets; no unread slot detected`,
      nonVacuity: controlNotes.guard891,
      tags: comp.partial ? ['partially-read'] : undefined,
      evidence: [{ type: 'command', command: `./mxcli -p ${MPR} describe --format elk page ${qn}` }],
    }));

    // ── class differ ───────────────────────────────────────────────────────
    const referenced = [...usage.all].sort();
    const { chrome, invented, neverPromoted } = classifyClasses(referenced, css, wf.all);

    const emptyRefs = referenced.length === 0;
    const lowerBound = comp.partial;
    const boundNote = lowerBound ? ' [LOWER BOUND — page is partially-read, see the #891 guard row]' : '';

    const mkClassRow = (idSuffix, title, list, flavour) => {
      let verdict, detail;
      if (emptyRefs) {
        verdict = 'fault';
        detail = 'no class references found on this page at all — an empty result set is not a pass; '
          + 'either the page genuinely styles nothing or the extraction did not see it';
      } else if (list.length) {
        verdict = 'fail';
        detail = `${list.length} ${flavour}: ${list.join(', ')} (of ${referenced.length} classes referenced)${boundNote}`;
      } else {
        verdict = lowerBound ? 'fault' : 'pass';
        detail = lowerBound
          ? `no ${flavour} among the ${referenced.length} classes we could see, but the page is partially-read — this is not a pass`
          : `no ${flavour} among ${referenced.length} referenced classes`;
      }
      return row({
        id: `design-audit/${idSuffix}/${qn}`, module: mod, page: qn, title, verdict, detail,
        nonVacuity: controlNotes.rung6,
        ...(lowerBound ? { blockedBy: readId } : {}),
        evidence: [{ type: 'contract', note: `defined-class corpus: ds.css ${css.ds.size}, deployed theme ${css.theme.size}, wireframe-inline ${wf.all.size}` }],
      });
    };

    checks.push(mkClassRow('rung6/invented-class', 'no invented classes (referenced, defined nowhere)', invented, 'invented-class'));
    checks.push(mkClassRow('rung6/never-promoted', 'ds.css classes promoted to the deployed theme', neverPromoted, 'never-promoted'));
    checks.push(mkClassRow('rung6/wireframe-chrome', 'no wireframe-only annotation chrome in a real page', chrome, 'wireframe-chrome'));
    checks.push(mkClassRow('rung7/unmatched-class', 'rung 7 — unmatched class sweep (runs without a wireframe)',
      invented, 'unmatched-class'));

    if (invented.length) { stats.inventedClassPages++; invented.forEach((c) => stats.inventedClasses.add(c)); }
    if (neverPromoted.length) { stats.neverPromotedPages++; neverPromoted.forEach((c) => stats.neverPromotedClasses.add(c)); }
    if (chrome.length) { stats.chromePages++; chrome.forEach((c) => stats.chromeClasses.add(c)); }
    if (comp.partial) stats.partiallyRead++;

    // ── wireframe conformance ───────────────────────────────────────────────
    // Rung 6 proper: the class-promotion diff, scored on the three defined flavours.
    // The wireframe-vs-page class delta is reported but does NOT set the verdict — a
    // page legitimately drops app-shell chrome (app-rail, brand, avatar) that the
    // wireframe drew, and scoring on that turns every page red for no defect.
    const m = mapPageToWireframe(qn, wf.files);
    if (!m.file) {
      stats.wireframeMissing++;
      checks.push(row({
        id: `design-audit/rung6/wireframe-conformance/${qn}`, module: mod, page: qn,
        title: 'wireframe conformance (class-promotion diff)',
        verdict: 'skipped', reason: m.why,
        detail: 'rung 6 does not apply to this page; rung 7 measures it anyway — that is the point of rung 7',
      }));
    } else {
      stats.wireframeMatched++;
      const wfRefs = wireframeRefClasses(m.file);
      const wfOnly = [...wfRefs].filter((c) => !usage.all.has(c) && (css.ds.has(c) || css.theme.has(c))).sort();
      const pageOnly = referenced.filter((c) => !wfRefs.has(c)).sort();
      const bad = [...invented, ...neverPromoted, ...chrome];
      checks.push(row({
        id: `design-audit/rung6/wireframe-conformance/${qn}`, module: mod, page: qn,
        title: 'wireframe conformance (class-promotion diff)',
        verdict: bad.length ? 'fail' : (lowerBound ? 'fault' : 'pass'),
        detail: `wireframe ${m.file}: `
          + (bad.length
            ? `${invented.length} invented, ${neverPromoted.length} never-promoted, ${chrome.length} wireframe-chrome`
            : 'every class this page references resolves to the deployed theme or ds.css')
          + `; informational: ${wfOnly.length} styled classes in the wireframe the page never uses`
          + (wfOnly.length ? ` (${wfOnly.slice(0, 25).join(', ')}${wfOnly.length > 25 ? ', …' : ''})` : '')
          + `, ${pageOnly.length} classes the page adds beyond the wireframe${boundNote}`,
        nonVacuity: controlNotes.rung6,
        ...(lowerBound ? { blockedBy: readId } : {}),
        evidence: [{ type: 'log', path: `../design/wireframes/${m.file}` }],
      }));
    }

    // ── raw class where a design property exists ────────────────────────────
    const raw = rawClassOverDesignProperty(doc, usage);
    if (raw.length) { stats.rawClassPages++; stats.rawClassHits += raw.length; }
    checks.push(row({
      id: `design-audit/rung7/raw-class-vs-designproperty/${qn}`, module: mod, page: qn,
      title: 'no raw class where a sanctioned design property exists',
      verdict: raw.length ? 'fail' : (lowerBound ? 'fault' : 'pass'),
      detail: raw.length
        ? `${raw.length} hand-written class(es) duplicating a design property: `
          + raw.map((h) => `${h.widget}.${h.class} → "${h.property}"${h.alsoHasProperty ? ' (widget ALSO sets the property — conflict)' : ''}`).join('; ')
        : (lowerBound ? 'none seen, but the page is partially-read — not a pass' : 'none'),
      nonVacuity: controlNotes.rung6,
      ...(lowerBound ? { blockedBy: readId } : {}),
    }));

    perPage.push({ page: qn, read: true, partiallyRead: comp.partial, classes: referenced.length, invented, neverPromoted, chrome, wireframe: m.file, rawClassHits: raw.length });
  }

  return { checks, stats, perPage };
}

// ============================================================================
// 9. App-dependent sweep (rung 7 checks 2-4)
// ============================================================================
async function appSweep(pages, navMap, controlNotes) {
  const checks = [];
  const titles = {
    a11y: 'accessibility — zero serious/critical (wcag2a, wcag2aa, wcag21aa)',
    overflow: 'no horizontal overflow at 360 / 768 / 1440',
    structure: 'structure inventory — exactly one h1, landmarks present',
  };

  if (OPT.staticOnly) {
    for (const qn of pages) {
      for (const [k, title] of Object.entries(titles)) {
        checks.push(row({
          id: `design-audit/rung7/${k}/${qn}`, module: moduleOf(qn), page: qn, title,
          verdict: 'skipped', provenance: 'declared',
          reason: '--static-only: the running app was not contacted',
          detail: 'NOT a pass. This check needs a rendered page and was deliberately not run.',
        }));
      }
    }
    return { checks, ran: false, reason: '--static-only' };
  }

  let helpers, cfg, chromium, axeSource;
  try {
    helpers = require('./helpers');
    cfg = require('./config').cfg || require('./config');
    ({ chromium } = require('playwright'));
    axeSource = fs.readFileSync(require.resolve('axe-core/axe.min.js'), 'utf8');
  } catch (e) {
    for (const qn of pages) for (const [k, title] of Object.entries(titles)) {
      checks.push(row({
        id: `design-audit/rung7/${k}/${qn}`, module: moduleOf(qn), page: qn, title,
        verdict: 'fault', detail: `harness dependency missing: ${e.message}`,
      }));
    }
    return { checks, ran: false, reason: e.message };
  }

  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  let loggedIn = false;
  try { loggedIn = !!(await helpers.login(page)); } catch (e) { loggedIn = false; }

  for (const qn of pages) {
    const mod = moduleOf(qn);
    const nav = navMap.get(qn);
    if (!loggedIn || !nav) {
      const why = !loggedIn ? 'could not sign in to the running app' : 'no navigation route to this page in the Responsive profile — it is opened from another page';
      for (const [k, title] of Object.entries(titles)) {
        checks.push(row({
          id: `design-audit/rung7/${k}/${qn}`, module: mod, page: qn, title,
          verdict: 'fault', detail: `${why}; this check never ran`,
        }));
      }
      continue;
    }
    try {
      await page.setViewportSize({ width: 1440, height: 900 });
      await helpers.navTo(page, nav.group, nav.item);
      await page.waitForTimeout(1200);

      const st = await checkStructure(page);
      const shot = path.join(ARTIFACTS, `design-audit-${qn}.png`);
      await page.screenshot({ path: shot, fullPage: false }).catch(() => {});
      checks.push(row({
        id: `design-audit/rung7/structure/${qn}`, module: mod, page: qn, title: titles.structure,
        verdict: (st.h1Count === 1 && st.landmarks.length > 0) ? 'pass' : 'fail',
        detail: `h1 count ${st.h1Count} (${st.h1Text.join(' | ') || 'none'}); landmarks: ${st.landmarks.join(', ') || 'NONE'}`,
        nonVacuity: controlNotes.structure,
        evidence: [{ type: 'screenshot', path: `../tests/e2e/artifacts/${path.basename(shot)}` }],
      }));

      const a = await checkA11y(page, axeSource);
      checks.push(row({
        id: `design-audit/rung7/a11y/${qn}`, module: mod, page: qn, title: titles.a11y,
        verdict: a.testedRules === 0 ? 'fault' : (a.seriousOrCritical === 0 ? 'pass' : 'fail'),
        detail: a.testedRules === 0
          ? 'axe reported zero rules evaluated — an empty result set is not a pass'
          : `${a.seriousOrCritical} serious/critical of ${a.totalViolations} violations over ${a.testedRules} rules`
            + (a.items.length ? `: ${a.items.map((i) => `${i.id}(${i.impact},x${i.nodes})`).join(', ')}` : ''),
        nonVacuity: controlNotes.a11y,
      }));

      const ov = await checkOverflow(page);
      const bad = ov.filter((o) => o.overflows);
      checks.push(row({
        id: `design-audit/rung7/overflow/${qn}`, module: mod, page: qn, title: titles.overflow,
        verdict: ov.length === 0 ? 'fault' : (bad.length === 0 ? 'pass' : 'fail'),
        detail: ov.map((o) => `${o.width}: ${o.scrollWidth}/${o.clientWidth}${o.overflows ? ' OVERFLOW' : ''}`).join('; '),
        nonVacuity: controlNotes.overflow,
      }));
    } catch (e) {
      for (const [k, title] of Object.entries(titles)) {
        checks.push(row({
          id: `design-audit/rung7/${k}/${qn}`, module: mod, page: qn, title,
          verdict: 'fault', detail: `error while measuring: ${String(e.message).slice(0, 300)}`,
        }));
      }
    }
  }
  await browser.close().catch(() => {});
  return { checks, ran: true };
}

// ============================================================================
// 10. POSITIVE CONTROLS — one mutant per rung, each proving ITS OWN check red
// ============================================================================
// Everything happens under /tmp. The real ds.css, the real theme and the real .mpr are
// opened read-only and never written.
const CONTROL_DIR = path.join(os.tmpdir(), `design-audit-control-${process.pid}`);

function ctlRow(id, name, fired, detail, extra = {}) {
  return row({
    id: `design-audit/control/${id}`, kind: 'control', module: null, page: null,
    title: `positive control — ${name}`,
    verdict: fired ? 'pass' : 'fault',
    detail: (fired ? 'MUTANT FIRED: ' : 'MUTANT DID NOT FIRE (the rung is UNPROVEN, which is fault, not pass): ') + detail,
    ...extra,
  });
}

async function runControls(pages, css, wf) {
  fs.mkdirSync(CONTROL_DIR, { recursive: true });
  const out = [];

  // ── control 1: rung 6 differ ────────────────────────────────────────────
  // Rename one class that the real pages reference and that IS defined today. The
  // differ must then report exactly that class as invented — no more, no less.
  {
    // Scan the scope for a page that actually references a DEFINED class. Taking
    // pages[0] blindly picked AIAssistant.AIAdmin_Home, whose one class is itself a
    // finding — there was nothing to rename and the rung reported UNPROVEN for a
    // reason that had nothing to do with the differ. Prefer a class that is in BOTH
    // ds.css and the theme, so the same victim can drive both mutants.
    let probePage = null, referenced = [], victim = null, firstErr = null;
    for (const qn of pages) {
      const p = describePage(qn);
      if (!p.ok) { firstErr = firstErr || `${qn}: ${p.error}`; continue; }
      const refs = [...pageClassUsage(p.doc).all].sort();
      const best = refs.find((c) => css.ds.has(c) && css.theme.has(c)) || refs.find((c) => css.ds.has(c) || css.theme.has(c));
      if (best) { probePage = qn; referenced = refs; victim = best; break; }
    }
    if (!victim) {
      out.push(ctlRow('rung6-invented-class', 'rung 6 class differ', false,
        `no in-scope page references a class defined in ds.css or the deployed theme — nothing to rename. ${firstErr || ''}`));
      out.push(ctlRow('rung6-never-promoted', 'rung 6 never-promoted differ', false,
        'no victim class available; this rung is UNPROVEN'));
    } else {
      {
        const pages0 = probePage;
        const mDs = path.join(CONTROL_DIR, 'ds.css');
        fs.writeFileSync(mDs, fs.readFileSync(DS_CSS, 'utf8').split(`.${victim}`).join(`.MUTANT-${victim}`));
        const mTheme = [];
        for (const t of THEME_CSS) {
          if (!fs.existsSync(t)) continue;
          const p = path.join(CONTROL_DIR, path.basename(t));
          fs.writeFileSync(p, fs.readFileSync(t, 'utf8').split(`.${victim}`).join(`.MUTANT-${victim}`));
          mTheme.push(p);
        }
        const mutCss = { ds: readCssSet([mDs]).set, theme: readCssSet(mTheme).set };
        const baseInv = classifyClasses(referenced, css, wf.all).invented;
        const mutInv = classifyClasses(referenced, mutCss, wf.all).invented;
        const delta = mutInv.filter((c) => !baseInv.includes(c));
        const fired = delta.length === 1 && delta[0] === victim;
        out.push(ctlRow('rung6-invented-class', 'rung 6 class differ', fired,
          `renamed .${victim} → .MUTANT-${victim} in copies of ds.css and the deployed theme under ${CONTROL_DIR}; `
          + `the SAME classifyClasses() production uses, run over ${pages0}, newly reports `
          + `[${delta.join(', ') || 'nothing'}] (expected exactly [${victim}]); baseline invented = ${baseInv.length}`,
          { evidence: [{ type: 'log', path: mDs }] }));

        // never-promoted has its own mutant: remove the class from the THEME only.
        const mTheme2 = [];
        for (const t of THEME_CSS) {
          if (!fs.existsSync(t)) continue;
          const p = path.join(CONTROL_DIR, 'np-' + path.basename(t));
          fs.writeFileSync(p, fs.readFileSync(t, 'utf8').split(`.${victim}`).join(`.MUTANT-${victim}`));
          mTheme2.push(p);
        }
        const npTheme = readCssSet(mTheme2).set;
        const baseNp = classifyClasses(referenced, css, wf.all).neverPromoted;
        const mutNp = classifyClasses(referenced, { ds: css.ds, theme: npTheme }, wf.all).neverPromoted;
        const npDelta = mutNp.filter((c) => !baseNp.includes(c));
        const npFired = css.ds.has(victim) ? (npDelta.length === 1 && npDelta[0] === victim) : npDelta.length === 0;
        out.push(ctlRow('rung6-never-promoted', 'rung 6 never-promoted differ', css.ds.has(victim) ? npFired : false,
          css.ds.has(victim)
            ? `de-promoted .${victim} from theme copies only; differ newly reports [${npDelta.join(', ') || 'nothing'}] (expected exactly [${victim}])`
            : `.${victim} is not defined in design/ds.css, so it cannot be a never-promoted mutant — this rung is UNPROVEN`));
      }
    }
  }

  // ── control 2: the #891 guard ───────────────────────────────────────────
  // (a) synthetic: a DataGrid2 inside an Accordion, described the way #891 describes it —
  //     the accordion group present, its content slot empty, the grid only in the MDL.
  {
    const fixture = {
      format: 'elk', type: 'page', name: 'Control.Accordion_Grid',
      root: [{
        id: 'wf-0', widget: 'accordion', name: 'accGroups', class: 'acc',
        children: [{ id: 'wf-1', widget: 'accordiongroup', name: 'grpRoutes', class: 'acc-group' }],
      }],
      mdlSource: [
        "create or modify page Control.Accordion_Grid (Title: 'x') {",
        "  accordion accGroups (Class: 'acc') {",
        "    group grpRoutes (Header: 'Routes', Class: 'acc-group') {",
        "      datagrid dgInner (DataSource: microflow X.Y, PageSize: 10) {",
        "        column c1 (Attribute: A, Caption: 'A')",
        '      }',
        '    }',
        '  }',
        '}',
      ].join('\n'),
    };
    fs.writeFileSync(path.join(CONTROL_DIR, 'accordion-fixture.json'), JSON.stringify(fixture, null, 1));
    const comp = readCompleteness(fixture);
    const fired = comp.partial && comp.unread.some((u) => u.includes('dgInner'));
    out.push(ctlRow('guard-891-synthetic', 'mxcli #891 content-slot guard (synthetic accordion + DataGrid2)', fired,
      `fixture describes an accordion group as an EMPTY GROUP while its mdlSource declares datagrid dgInner. `
      + `Guard verdict: ${comp.partial ? 'partially-read → fault' : 'CLEAN PASS — the false green is back'}; unread = [${comp.unread.join(', ')}]`,
      { evidence: [{ type: 'log', path: path.join(CONTROL_DIR, 'accordion-fixture.json') }] }));

    // A guard that fires on everything proves nothing. Negative side of the control:
    const clean = {
      root: [{ id: 'wf-0', widget: 'divcontainer', name: 'c1', class: 'a', children: [{ id: 'wf-1', widget: 'dynamictext', name: 't1' }] }],
      mdlSource: "create or modify page X.Y (Title: 'x') {\n  container c1 (Class: 'a') {\n    dynamictext t1 (Content: 'hi')\n  }\n}",
    };
    const cleanComp = readCompleteness(clean);
    out.push(ctlRow('guard-891-negative', 'mxcli #891 guard does not fire on a fully-read page', !cleanComp.partial,
      `a fully-read fixture must NOT be marked partially-read; guard said partial=${cleanComp.partial}`));
  }

  // (b) live: the same guard against the real project. The page name is
  // project.config's `probePage` (a page known to carry an unread content slot),
  // falling back to the first in-scope page from page-scope.json — it used to be
  // a literal page name of this project baked into the engine.
  {
    const probe = PROJ.probePage(SCOPE_FILE);
    if (!probe) {
      out.push(ctlRow('guard-891-live', 'mxcli #891 guard against a real project page', false,
        'no probe page: set PROBE_PAGE, or probePage in tests/e2e/project.config.js'));
    } else {
      const live = describePage(probe);
      if (!live.ok) {
        out.push(ctlRow('guard-891-live', 'mxcli #891 guard against a real project page', false, `describe failed: ${live.error}`));
      } else {
        const comp = readCompleteness(live.doc);
        out.push(ctlRow('guard-891-live', 'mxcli #891 guard against a real project page', comp.partial,
          `${probe}: ${comp.treeNodes} tree nodes vs ${comp.mdlDeclared} declared widgets; `
          + `customContent columns [${comp.customContentCols.join(', ')}]; unread [${comp.unread.join(', ')}]`));
      }
    }
  }

  // ── control 3-5: rung 7 browser checks, against /tmp fixtures ────────────
  // Fixtures, not the live app: the checks must be provable with the app down, and a
  // fixture isolates ONE defect so we can assert that only its own check went red.
  let chromium, axeSource;
  try {
    ({ chromium } = require('playwright'));
    axeSource = fs.readFileSync(require.resolve('axe-core/axe.min.js'), 'utf8');
  } catch (e) {
    for (const n of ['rung7-a11y', 'rung7-overflow', 'rung7-structure']) {
      out.push(ctlRow(n, `rung 7 ${n}`, false, `playwright/axe-core unavailable: ${e.message}`));
    }
    return out;
  }

  const FIX = {
    clean: `<title>c</title><header><nav><a href="#a">n</a></nav></header><main><h1>Only heading</h1>
      <p style="color:#111;background:#fff">body text</p><img src="data:image/gif;base64,R0lGODlhAQABAAAAACw=" alt="dot"></main>`,
    dupH1: `<title>c</title><header><nav><a href="#a">n</a></nav></header><main><h1>One</h1><h1>Two</h1>
      <p style="color:#111;background:#fff">body text</p><img src="data:image/gif;base64,R0lGODlhAQABAAAAACw=" alt="dot"></main>`,
    overflow: `<title>c</title><header><nav><a href="#a">n</a></nav></header><main><h1>Only heading</h1>
      <div style="width:2200px;height:20px;background:#111"></div>
      <p style="color:#111;background:#fff">body text</p><img src="data:image/gif;base64,R0lGODlhAQABAAAAACw=" alt="dot"></main>`,
    a11y: `<title>c</title><header><nav><a href="#a">n</a></nav></header><main><h1>Only heading</h1>
      <p style="color:#111;background:#fff">body text</p><img src="data:image/gif;base64,R0lGODlhAQABAAAAACw="></main>`,
  };
  const wrap = (b) => `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>*{margin:0;padding:0;box-sizing:border-box}body{font:16px system-ui;color:#111;background:#fff}</style></head><body>${b}</body></html>`;
  const files = {};
  for (const [k, v] of Object.entries(FIX)) {
    const p = path.join(CONTROL_DIR, `fixture-${k}.html`);
    fs.writeFileSync(p, wrap(v)); files[k] = p;
  }

  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const pg = await ctx.newPage();
  const measure = async (file) => {
    await pg.setViewportSize({ width: 1440, height: 900 });
    await pg.goto('file://' + file, { waitUntil: 'load' });
    const structure = await checkStructure(pg);
    const a11y = await checkA11y(pg, axeSource);
    const overflow = await checkOverflow(pg);
    return {
      structureRed: !(structure.h1Count === 1 && structure.landmarks.length > 0),
      a11yRed: a11y.testedRules > 0 && a11y.seriousOrCritical > 0,
      overflowRed: overflow.some((o) => o.overflows),
      structure, a11y, overflow,
    };
  };

  const base = await measure(files.clean);
  const baselineGreen = !base.structureRed && !base.a11yRed && !base.overflowRed;
  out.push(ctlRow('rung7-baseline', 'rung 7 baseline fixture is green on all three checks', baselineGreen,
    `structure red=${base.structureRed} (h1=${base.structure.h1Count}, landmarks=${base.structure.landmarks.join('/')}), `
    + `a11y red=${base.a11yRed} (${base.a11y.seriousOrCritical} serious/critical over ${base.a11y.testedRules} rules), `
    + `overflow red=${base.overflowRed}. A mutant is only meaningful against a green baseline.`));

  const m1 = await measure(files.dupH1);
  out.push(ctlRow('rung7-structure', 'rung 7 structure — duplicate h1 injected', m1.structureRed && !m1.a11yRed && !m1.overflowRed,
    `structure red=${m1.structureRed} (h1 count ${m1.structure.h1Count}), a11y red=${m1.a11yRed}, overflow red=${m1.overflowRed}. `
    + 'Required: structure red, the other two unchanged.',
    { evidence: [{ type: 'log', path: files.dupH1 }] }));

  const m2 = await measure(files.overflow);
  out.push(ctlRow('rung7-overflow', 'rung 7 overflow — 2200px fixed-width element injected', m2.overflowRed && !m2.structureRed && !m2.a11yRed,
    `overflow red=${m2.overflowRed} (${m2.overflow.map((o) => `${o.width}:${o.scrollWidth}/${o.clientWidth}`).join(' ')}), `
    + `structure red=${m2.structureRed}, a11y red=${m2.a11yRed}. Required: overflow red, the other two unchanged.`,
    { evidence: [{ type: 'log', path: files.overflow }] }));

  const m3 = await measure(files.a11y);
  out.push(ctlRow('rung7-a11y', 'rung 7 accessibility — image alt removed', m3.a11yRed && !m3.structureRed && !m3.overflowRed,
    `a11y red=${m3.a11yRed} (${m3.a11y.seriousOrCritical} serious/critical: ${m3.a11y.items.map((i) => i.id).join(',') || 'none'} over ${m3.a11y.testedRules} rules), `
    + `structure red=${m3.structureRed}, overflow red=${m3.overflowRed}. Required: a11y red, the other two unchanged.`,
    { evidence: [{ type: 'log', path: files.a11y }] }));

  await browser.close().catch(() => {});
  return out;
}

// ============================================================================
// 11. main
// ============================================================================
async function main() {
  fs.mkdirSync(ARTIFACTS, { recursive: true });
  const startedAt = nowIso();

  // scope
  let pages = [], scopeErr = null;
  if (OPT.page) {
    pages = [OPT.page];
  } else {
    try {
      const s = JSON.parse(fs.readFileSync(SCOPE_FILE, 'utf8'));
      pages = Array.isArray(s.inScope) ? s.inScope : [];
      if (!pages.length) scopeErr = 'page-scope.json carries an empty inScope array';
    } catch (e) { scopeErr = `cannot read ${SCOPE_FILE}: ${e.message}`; }
  }

  // css corpora
  const dsRead = readCssSet([DS_CSS]);
  const themeRead = readCssSet(THEME_CSS);
  const css = { ds: dsRead.set, theme: themeRead.set };
  const wf = wireframeInlineClasses();

  const corpusFault = [];
  if (!dsRead.read.length) corpusFault.push('design/ds.css is missing or empty');
  if (!themeRead.read.length) corpusFault.push('no deployed theme CSS found under deployment/web');
  if (!wf.files.length) corpusFault.push('no wireframes found under design/wireframes');

  const checks = [];
  const instruments = [];

  // corpus row — a differ run against an empty corpus would call every class invented,
  // so the corpus itself gets a check rather than an assumption.
  checks.push(row({
    id: 'design-audit/corpus/defined-classes', kind: 'conformance', module: null, page: null,
    title: 'the defined-class corpus was actually loaded',
    verdict: corpusFault.length ? 'fault' : (css.ds.size && css.theme.size ? 'pass' : 'fault'),
    detail: corpusFault.length ? corpusFault.join('; ')
      : `ds.css ${css.ds.size} classes; deployed theme ${css.theme.size} classes from ${themeRead.read.map((f) => path.relative(ROOT, f)).join(', ')}; `
        + `wireframe-inline ${wf.all.size} classes across ${wf.files.length} files. `
        + `${[...css.ds].filter((c) => !css.theme.has(c)).length} ds.css classes are absent from the deployed theme overall — `
        + 'the never-promoted check is therefore capable of firing; whether it does depends on which of them a page references.',
    evidence: [{ type: 'log', path: '../design/ds.css' }],
  }));

  if (scopeErr || !pages.length) {
    checks.push(row({
      id: 'design-audit/scope', kind: 'conformance', title: 'in-scope page set resolved',
      verdict: 'fault', detail: scopeErr || 'no pages resolved',
    }));
    instruments.push({ name: 'design-audit', verdict: 'fault', reason: scopeErr || 'no pages in scope' });
    write({ startedAt, checks, instruments, pages: [], perPage: [], stats: null });
    return;
  }
  checks.push(row({
    id: 'design-audit/scope', kind: 'conformance', title: 'in-scope page set resolved',
    verdict: 'pass', detail: `${pages.length} pages from ${path.relative(ROOT, SCOPE_FILE)}`,
  }));

  // ── controls first, so every check row can carry an honest nonVacuity note ──
  let controlRows = [];
  if (OPT.positiveControl) {
    controlRows = await runControls(pages, css, wf);
  }
  const fired = (id) => controlRows.some((r) => r.id === `design-audit/control/${id}` && r.verdict === 'pass');
  const note = (ids, label) => OPT.positiveControl
    ? { controlRan: true, note: `${label}: ${ids.map((i) => `${i}=${fired(i) ? 'fired' : 'DID NOT FIRE'}`).join(', ')}` }
    : { controlRan: false, note: 'positive control not run for this build (--positive-control absent)' };
  const controlNotes = {
    rung6: note(['rung6-invented-class', 'rung6-never-promoted'], 'rung 6 differ'),
    guard891: note(['guard-891-synthetic', 'guard-891-live', 'guard-891-negative'], '#891 guard'),
    a11y: note(['rung7-a11y'], 'rung 7 a11y'),
    overflow: note(['rung7-overflow'], 'rung 7 overflow'),
    structure: note(['rung7-structure'], 'rung 7 structure'),
  };

  const st = staticSweep(pages, css, wf, controlNotes);
  checks.push(...st.checks);

  const navInfo = OPT.staticOnly ? { map: new Map(), source: 'not consulted (--static-only)' } : buildNavMap();
  const app = await appSweep(pages, navInfo.map, controlNotes);
  checks.push(...app.checks);

  checks.push(...controlRows);

  instruments.push({
    name: 'design-audit', verdict: 'pass', canExpressFault: true,
    expressibleVerdicts: ['pass', 'fail', 'fault', 'skipped'],
    evidenceStrength: OPT.staticOnly ? 'static-model+css' : 'static-model+css+rendered',
    reason: null,
  });
  instruments.push(OPT.positiveControl
    ? {
      name: 'design-audit-positive-control',
      verdict: controlRows.length && controlRows.every((r) => r.verdict === 'pass') ? 'pass' : 'fail',
      reason: controlRows.length ? null : 'controls produced no rows',
    }
    : { name: 'design-audit-positive-control', verdict: 'fault', reason: 'not requested (--positive-control absent)' });
  instruments.push(app.ran
    ? { name: 'design-audit-rendered', verdict: 'pass', reason: null }
    : { name: 'design-audit-rendered', verdict: OPT.staticOnly ? 'skipped' : 'fault', reason: app.reason });

  write({ startedAt, checks, instruments, pages, perPage: st.perPage, stats: st.stats, controlRows });
}

function write({ startedAt, checks, instruments, pages, perPage, stats, controlRows = [] }) {
  const tally = {};
  for (const c of checks) tally[c.verdict] = (tally[c.verdict] || 0) + 1;
  const doc = {
    schemaVersion: SCHEMA_VERSION,
    instrument: 'design-audit',
    positiveControl: OPT.positiveControl,
    run: {
      startedAt, finishedAt: nowIso(),
      mode: OPT.staticOnly ? 'static-only' : 'full',
      pages: pages.length,
      reproduce: { command: `node tests/e2e/design-audit.js ${argv.join(' ')}`.trim() },
    },
    tally,
    summary: stats ? {
      pagesRead: stats.pagesRead, pagesFault: stats.pagesFault,
      partiallyRead: stats.partiallyRead,
      inventedClassPages: stats.inventedClassPages, inventedClasses: [...stats.inventedClasses].sort(),
      neverPromotedPages: stats.neverPromotedPages, neverPromotedClasses: [...stats.neverPromotedClasses].sort(),
      wireframeChromePages: stats.chromePages, wireframeChromeClasses: [...stats.chromeClasses].sort(),
      rawClassPages: stats.rawClassPages, rawClassHits: stats.rawClassHits,
      wireframeMatched: stats.wireframeMatched, wireframeUnmatched: stats.wireframeMissing,
    } : null,
    perPage,
    instruments,
    checks,
  };
  const out = OPT.out
    ? path.resolve(ROOT, OPT.out)
    : path.join(ARTIFACTS, OPT.positiveControl ? 'design-audit-control.json' : 'design-audit.json');
  fs.writeFileSync(out, JSON.stringify(doc, null, 2));

  // console: short, honest, no green where there is none
  const order = ['fail', 'fault', 'skipped', 'pass'];
  console.log(`\ndesign-audit → ${path.relative(ROOT, out)}`);
  console.log(`mode=${doc.run.mode} pages=${pages.length} checks=${checks.length}`);
  console.log(order.filter((v) => tally[v]).map((v) => `${v}=${tally[v]}`).join('  '));
  if (doc.summary) {
    console.log(`partially-read pages: ${doc.summary.partiallyRead}/${doc.summary.pagesRead}`);
    console.log(`invented classes (${doc.summary.inventedClasses.length}): ${doc.summary.inventedClasses.join(', ') || '—'}`);
    console.log(`never-promoted (${doc.summary.neverPromotedClasses.length}): ${doc.summary.neverPromotedClasses.join(', ') || '—'}`);
    console.log(`wireframe chrome (${doc.summary.wireframeChromeClasses.length}): ${doc.summary.wireframeChromeClasses.join(', ') || '—'}`);
    console.log(`raw-class-over-designProperty hits: ${doc.summary.rawClassHits} on ${doc.summary.rawClassPages} pages`);
    console.log(`wireframe matched ${doc.summary.wireframeMatched}, unmatched ${doc.summary.wireframeUnmatched}`);
  }
  for (const r of controlRows) console.log(`  control ${r.verdict === 'pass' ? 'FIRED ' : 'UNPROVEN'} ${r.id.split('/').pop()}`);
  const failing = checks.filter((c) => c.verdict === 'fail');
  if (failing.length) {
    console.log('\nfindings:');
    for (const f of failing.slice(0, 60)) console.log(`  [fail] ${f.id}\n         ${f.detail}`);
    if (failing.length > 60) console.log(`  … ${failing.length - 60} more`);
  }
}

main().catch((e) => { console.error('design-audit crashed:', e); process.exit(1); });
