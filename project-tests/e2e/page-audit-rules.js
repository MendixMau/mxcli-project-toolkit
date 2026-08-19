'use strict';
// ============================================================================
// page-audit-rules.js — the rule set for page-audit.js, as DATA not code
// ----------------------------------------------------------------------------
// Every rule below is derived from THIS project's own skills and its own exemplar
// MDL — not from general web-design knowledge. Each carries:
//
//   cite        where the rule comes from (skill file + section), so a disputed
//               finding is settled by reading a file, not by arguing with a model.
//   exemplar    a file in mdlsource/ that already does it right, where one exists.
//               This is what makes a rule "house style" rather than an opinion.
//   remediate() a concrete change: what to add/edit, in which kind of file.
//               A finding with no remediation is a complaint, so remediate() is
//               mandatory and page-audit.js refuses to load a rule without one.
//   mutate()    the positive control. It takes the CLEAN synthetic baseline page
//               and breaks exactly this rule. If the mutant does not turn this
//               rule red, the rule is reported `fault` (UNPROVEN), never `pass`.
//
// WHY THE MDL TREE AND NOT THE ELK WIDGET TREE
// mxcli issue #891: an object-list item's content-slot children are never read, so
// a DataGrid2 inside an Accordion — and every `controlbar` and `customContent`
// column body on this project's pages — is simply absent from the ELK `root` tree.
// MEASURED on one of this project's list pages: 13 tree nodes vs 27 widgets declared in
// the page's own `mdlSource` in the SAME response. So every structural rule here
// runs over a tree parsed from `mdlSource`, which is complete; the ELK tree is used
// only to DETECT the loss (readCompleteness) and to union class usage.
//
// SEVERITY uses the module-review.md scale: P1 broken/missing, P2 significant,
// P3 polish.
//
// PROJECT-SPECIFIC TEXT: the rule LOGIC below is generic, but `exemplar` and
// `remediate()` name real pages and the real .mpr so a reader can go look. Those
// names are NOT literals here — they come from project.config.js (`mprName`,
// `exemplars`). An exemplar naming a page that does not exist in the project
// being audited is worse than no exemplar at all.
// ============================================================================

const PROJ = require('./project.config');
const MPR = PROJ.mprName;
const EX = PROJ.exemplars;

// ── MDL parsing ──────────────────────────────────────────────────────────────
// A widget declaration is `<type> <name> ( props ) { body }`, where props may span
// many lines and body may nest. Regex alone cannot do this (nested parens in
// `ContentParams: [{1} = X]`, braces inside `Content: '{1}'`), so we scan with a
// small hand parser that tracks quotes and depth. The parser is the single source
// of structure for every rule AND for the positive controls — a control can never
// end up proving a parser that production does not run.

const WIDGET_HEAD = /(^|\n)([ \t]*)([a-zA-Z][a-zA-Z0-9_]*)[ \t]+("?)([A-Za-z_][A-Za-z0-9_]*)\4[ \t]*(?=[({\n])/g;

// Keywords that look like a widget head but are MDL structure, not a widget.
const NON_WIDGET = new Set([
  'create', 'grant', 'revoke', 'page', 'snippet', 'layout', 'menu', 'or', 'modify',
  'replace', 'insert', 'drop', 'set', 'alter', 'define', 'use', 'as', 'on', 'to',
]);

function skipString(src, i) {
  const q = src[i];
  i++;
  while (i < src.length) {
    if (src[i] === '\\') { i += 2; continue; }
    if (src[i] === q) return i + 1;
    i++;
  }
  return i;
}

// Read a balanced (...) or {...} starting at `i` (which must be the opener).
// Returns { inner, end } where end is the index just past the closer.
function readBalanced(src, i) {
  const open = src[i];
  const close = open === '(' ? ')' : '}';
  let depth = 0;
  const start = i;
  while (i < src.length) {
    const c = src[i];
    if (c === "'" || c === '"') { i = skipString(src, i); continue; }
    if (c === open) depth++;
    else if (c === close) { depth--; if (depth === 0) return { inner: src.slice(start + 1, i), end: i + 1 }; }
    i++;
  }
  return { inner: src.slice(start + 1), end: src.length, unterminated: true };
}

/**
 * Parse `mdlSource` into a widget tree.
 * Returns { root: [nodes], all: [nodes], error }. Each node:
 *   { type, name, props, body, children, parent, line, hasBody }
 */
function parseMdlTree(mdl) {
  const src = String(mdl || '');
  const all = [];
  const lineAt = (idx) => src.slice(0, idx).split('\n').length;

  function parseBlock(text, offset, parent) {
    const out = [];
    WIDGET_HEAD.lastIndex = 0;
    const re = new RegExp(WIDGET_HEAD.source, 'g');
    let m;
    let cursor = 0;
    while ((m = re.exec(text))) {
      if (m.index < cursor) continue;               // inside a body we already consumed
      const type = m[3].toLowerCase();
      if (NON_WIDGET.has(type)) continue;
      const name = m[5];
      let i = m.index + m[0].length;
      // skip whitespace
      while (i < text.length && /\s/.test(text[i])) i++;
      let props = '';
      if (text[i] === '(') { const r = readBalanced(text, i); props = r.inner; i = r.end; }
      // Peek — do NOT advance — past whitespace looking for a body opener. Advancing
      // here eats the newline that the NEXT widget's `(^|\n)` anchor needs, which
      // silently dropped every widget that followed a bodyless one (measured: the
      // `datagrid` after a `textbox` vanished, and its columns were reparented to the
      // dataview). The positive control caught this; a corpus run would not have.
      let j = i;
      while (j < text.length && /\s/.test(text[j])) j++;
      let body = null; let hasBody = false;
      if (text[j] === '{') { const r = readBalanced(text, j); body = r.inner; hasBody = true; i = r.end; }
      const node = {
        type, name, props, body, hasBody, children: [], parent,
        // m[1] is the leading '\n' the anchor consumed, so the widget itself is on
        // the NEXT line. Without the +1 every reported line number is one short —
        // verified against this project's equipment overview `column col3` (real line 64).
        line: lineAt(offset + m.index + (m[1] ? 1 : 0)),
      };
      all.push(node);
      out.push(node);
      if (hasBody) {
        node.children = parseBlock(body, offset + (i - body.length - 1), node);
      }
      cursor = i;
      re.lastIndex = i;
    }
    return out;
  }

  // Only parse inside the page body — the `create or modify page X (...) { ... }`
  // block. Outside it live the `grant` statements, which are not widgets.
  //
  // The body opener is NOT simply the first `{`: the page header carries
  // `Params: { $Filter: Module.Entity }` inside its parens, and taking the first
  // brace lands inside that instead, yielding a zero-widget parse that would have
  // rendered as a clean pass on every structural rule.
  let pageOpen = -1;
  {
    const head = /create\s+(?:or\s+(?:modify|replace)\s+)?page\s+[\w."]+/i.exec(src);
    let i = head ? head.index + head[0].length : 0;
    while (i < src.length && /\s/.test(src[i])) i++;
    if (src[i] === '(') i = readBalanced(src, i).end;
    while (i < src.length && src[i] !== '{') i++;
    pageOpen = i < src.length ? i : src.indexOf('{');
  }
  let root = [];
  let error = null;
  try {
    if (pageOpen >= 0) {
      const r = readBalanced(src, pageOpen);
      if (r.unterminated) error = 'page body braces are unbalanced';
      root = parseBlock(r.inner, pageOpen + 1, null);
    } else if (src.trim()) {
      error = 'no page body found in mdlSource';
    } else {
      error = 'mdlSource is empty';
    }
  } catch (e) {
    error = `MDL parse threw: ${String(e.message).slice(0, 200)}`;
  }
  return { root, all, error };
}

// The page body text, with the header (and its `Params: { ... }` brace) removed.
// Shared by the parser and by any rule that greps the body.
function pageBodyOf(mdl) {
  const src = String(mdl || '');
  const head = /create\s+(?:or\s+(?:modify|replace)\s+)?page\s+[\w."]+/i.exec(src);
  let i = head ? head.index + head[0].length : 0;
  while (i < src.length && /\s/.test(src[i])) i++;
  if (src[i] === '(') i = readBalanced(src, i).end;
  while (i < src.length && src[i] !== '{') i++;
  return i < src.length ? readBalanced(src, i).inner : src;
}

const ancestors = (n) => { const out = []; let p = n.parent; while (p) { out.push(p); p = p.parent; } return out; };
const hasAncestor = (n, types) => ancestors(n).some((a) => types.includes(a.type));
const prop = (node, key) => {
  const re = new RegExp(`(^|,|\\s)${key}\\s*:\\s*`, 'i');
  const m = re.exec(node.props || '');
  if (!m) return null;
  const rest = node.props.slice(m.index + m[0].length);
  // value ends at a comma that is not inside quotes/brackets
  let depth = 0, i = 0;
  for (; i < rest.length; i++) {
    const c = rest[i];
    if (c === "'" || c === '"') { i = skipString(rest, i) - 1; continue; }
    if (c === '[' || c === '(') depth++;
    else if (c === ']' || c === ')') depth--;
    else if (c === ',' && depth === 0) break;
  }
  return rest.slice(0, i).trim();
};
const unquote = (v) => (v == null ? null : String(v).replace(/^['"]|['"]$/g, ''));
const classesOf = (node) => String(unquote(prop(node, 'Class')) || '').split(/\s+/).filter(Boolean);

// ── widget vocabularies (lowercased MDL keywords, as used in mdlsource/) ─────
const INPUT_WIDGETS = ['textbox', 'textarea', 'checkbox', 'radiobuttons', 'datepicker',
  'combobox', 'referenceselector', 'inputreferencesetselector', 'dropdown'];
const LIST_WIDGETS = ['datagrid', 'listview', 'gallery', 'templategrid'];
const CONTEXT_WIDGETS = ['dataview', 'listview', 'gallery', 'templategrid', 'datagrid', 'snippet'];
const CONTAINER_WIDGETS = ['container', 'divcontainer', 'groupbox', 'scrollcontainer',
  'header', 'footer', 'layoutgrid', 'row', 'column', 'tabcontainer', 'tabpage'];
const LEGAL_BUTTON_STYLES = ['default', 'primary', 'success', 'info', 'warning', 'danger', 'inverse'];

// A finding: keep them uniform so the renderer never has to special-case one rule.
const finding = (o) => ({
  where: o.where || null,          // widget name / line, human-locatable
  line: o.line ?? null,
  what: o.what,
});

// ============================================================================
// THE RULES
// ============================================================================
// Each `evaluate(ctx)` returns { ok, findings[], detail } — never a verdict. The
// harness turns that into pass/fail and applies the #891 fault override, so no
// rule can accidentally mint a `pass` for a page that was only half read.

const RULES = [
  // ── structure ─────────────────────────────────────────────────────────────
  {
    id: 'structure/empty-container',
    category: 'structure',
    title: 'No container may be declared with an empty body',
    severity: 'P1',
    cite: '.ai-context/skills/create-page.md §Runtime Pitfalls (~line 1024); lint MPR006',
    exemplar: 'mdlsource/gallery/14-kpi-tiles.mdl — every container carries a dynamictext child',
    evaluate(ctx) {
      const bad = ctx.mdlNodes.filter((n) => CONTAINER_WIDGETS.includes(n.type) && n.hasBody
        && !/[^\s]/.test(String(n.body).replace(/--[^\n]*/g, '')));
      return {
        ok: bad.length === 0,
        findings: bad.map((n) => finding({ where: `${n.type} ${n.name}`, line: n.line, what: 'declared with an empty body' })),
        detail: `${ctx.mdlNodes.filter((n) => CONTAINER_WIDGETS.includes(n.type)).length} containers inspected`,
      };
    },
    remediate: (f) => `In the page's build script under mdlsource/, give ${f.map((x) => x.where).join(', ')} a child `
      + `(\`dynamictext <name> (Content: ' ')\` is the sanctioned spacer — see mdlsource/gallery/16-process-stepper.mdl) `
      + `or delete the container. An empty container throws "Did not expect an argument to be undefined" at page load.`,
    mutate: (mdl) => mdl.replace("dynamictext crumbTrail (Content: 'Home > Baseline')", ''),
  },
  {
    id: 'structure/style-on-dynamictext',
    category: 'structure',
    title: 'DYNAMICTEXT must not carry an inline Style',
    severity: 'P1',
    cite: '.ai-context/skills/create-page.md:98; alter-page.md:112-123',
    exemplar: "mdlsource/usi/done-usi-147-operation-detail-page.mdl:491 — Style sits on the container wrapper, never on the text",
    evaluate(ctx) {
      const bad = ctx.mdlNodes.filter((n) => n.type === 'dynamictext' && prop(n, 'Style'));
      return {
        ok: bad.length === 0,
        findings: bad.map((n) => finding({ where: `dynamictext ${n.name}`, line: n.line, what: `Style: ${prop(n, 'Style')}` })),
        detail: `${ctx.mdlNodes.filter((n) => n.type === 'dynamictext').length} dynamictext widgets inspected`,
      };
    },
    remediate: (f) => `In the page's mdlsource/ script, move the inline style off ${f.map((x) => x.where).join(', ')} `
      + `onto a wrapping \`container (Style: ...) { dynamictext ... }\`, or better, replace it with a design-system class from design/ds.css. `
      + `Style on a dynamictext is a MxBuild NullReferenceException.`,
    mutate: (mdl) => mdl.replace('dynamictext pageHeading (Content:', "dynamictext pageHeading (Style: 'color:red', Content:"),
  },
  {
    id: 'structure/input-needs-context',
    category: 'structure',
    title: 'Input widgets must sit inside a data context (dataview / list template)',
    severity: 'P1',
    cite: '.ai-context/skills/create-page.md:524 ("Input widgets must be inside a DATAVIEW context"); CE1571',
    exemplar: 'mdlsource/usi/done-usi-147-operation-detail-page.mdl — every textbox is nested under the $Operation dataview',
    evaluate(ctx) {
      const inputs = ctx.mdlNodes.filter((n) => INPUT_WIDGETS.includes(n.type));
      const bad = inputs.filter((n) => !hasAncestor(n, CONTEXT_WIDGETS));
      return {
        ok: bad.length === 0,
        findings: bad.map((n) => finding({ where: `${n.type} ${n.name}`, line: n.line, what: 'has no dataview/list ancestor — CE1571 scope error' })),
        detail: `${inputs.length} input widgets inspected`,
      };
    },
    remediate: (f) => `Move ${f.map((x) => x.where).join(', ')} INSIDE the dataview bound to the page parameter, in the page's mdlsource/ script. `
      + `A widget that needs a page parameter must be inside its dataview, not beside it — CE1571 is a scope error, not a missing argument.`,
    mutate: (mdl) => mdl.replace('layoutgrid mainGrid {', "layoutgrid mainGrid {\n    textbox txtStray (Label: 'Stray', Attribute: Code)"),
  },
  {
    id: 'structure/dataview-in-layoutgrid',
    category: 'structure',
    title: 'A dataview holding inputs must sit inside layoutgrid → row → column',
    severity: 'P2',
    cite: '.ai-context/skills/create-page.md:856-860 (Customer Edit example); lint MPR010',
    exemplar: 'mdlsource/usi/done-usi-147-operation-detail-page.mdl:385-392',
    evaluate(ctx) {
      const dvs = ctx.mdlNodes.filter((n) => n.type === 'dataview'
        && n.children && subtree(n).some((c) => INPUT_WIDGETS.includes(c.type)));
      // A `column` ancestor is required specifically, not merely a layoutgrid: a
      // dataview parked in a bare container inside the grid has the same broken
      // label/control widths, and requiring only `layoutgrid` would pass it.
      const bad = dvs.filter((n) => !hasAncestor(n, ['column']));
      return {
        ok: bad.length === 0,
        findings: bad.map((n) => finding({ where: `dataview ${n.name}`, line: n.line, what: 'input-bearing dataview is not inside a layoutgrid column' })),
        detail: `${dvs.length} input-bearing dataviews inspected`,
      };
    },
    remediate: (f) => `Wrap ${f.map((x) => x.where).join(', ')} in \`layoutgrid mainGrid { row row1 { column col1 (DesktopWidth: AutoFill) { ... } } }\` `
      + `in the page's mdlsource/ script — label and control widths only render correctly inside a grid.`,
    // Brace-count preserving: one opener swapped for another opener.
    mutate: (mdl) => mdl.replace('column col1 (DesktopWidth: AutoFill) {', 'container bareWrap {'),
  },

  // ── binding ───────────────────────────────────────────────────────────────
  {
    id: 'binding/empty-content',
    category: 'binding',
    title: "DYNAMICTEXT Content: '' is banned (use a single space)",
    severity: 'P1',
    cite: ".ai-context/skills/create-page.md:1035-1042 — MxBuild 'Place holder index 1 is greater than 0'",
    exemplar: "mdlsource/gallery/16-process-stepper.mdl — spacers use Content: ' '",
    evaluate(ctx) {
      const bad = ctx.mdlNodes.filter((n) => n.type === 'dynamictext' && /^''$/.test(String(prop(n, 'Content') || '').trim()));
      return {
        ok: bad.length === 0,
        findings: bad.map((n) => finding({ where: `dynamictext ${n.name}`, line: n.line, what: "Content: ''" })),
        detail: `${ctx.mdlNodes.filter((n) => n.type === 'dynamictext').length} dynamictext widgets inspected`,
      };
    },
    remediate: (f) => `In the page's mdlsource/ script change ${f.map((x) => x.where).join(', ')} to \`Content: ' '\` (one space) or remove the widget.`,
    mutate: (mdl) => mdl.replace("Content: 'Home > Baseline'", "Content: ''"),
  },
  {
    id: 'binding/unbound-placeholder',
    category: 'binding',
    title: 'Every {N} placeholder in Content must be bound by ContentParams',
    severity: 'P1',
    cite: '.ai-context/skills/create-page.md:240-244 (MDL-WIDGET04 / CE0720)',
    exemplar: 'mdlsource/usi/done-usi-147-operation-detail-page.mdl:425 — Content: \'{1}\', ContentParams: [{1} = OperationCode]',
    evaluate(ctx) {
      const bad = [];
      for (const n of ctx.mdlNodes) {
        const content = prop(n, 'Content');
        if (!content) continue;
        const holes = new Set([...String(content).matchAll(/\{(\d+)\}/g)].map((m) => m[1]));
        if (!holes.size) continue;
        const params = prop(n, 'ContentParams') || '';
        const bound = new Set([...params.matchAll(/\{(\d+)\}\s*=/g)].map((m) => m[1]));
        const missing = [...holes].filter((h) => !bound.has(h));
        if (missing.length) bad.push(finding({ where: `${n.type} ${n.name}`, line: n.line, what: `unbound placeholders {${missing.join('}, {')}}` }));
      }
      return { ok: bad.length === 0, findings: bad, detail: 'every Content string with a {N} checked against its ContentParams' };
    },
    remediate: (f) => `Add the missing \`ContentParams: [{N} = <Attribute>]\` entries to ${f.map((x) => x.where).join(', ')} in the page's mdlsource/ script, `
      + `or make the caption a static string. An unbound placeholder is a Studio Pro NullReferenceException, not a cosmetic bug.`,
    mutate: (mdl) => mdl.replace("Content: 'Baseline List', RenderMode: H1", "Content: 'Baseline List {1}', RenderMode: H1"),
  },
  {
    id: 'binding/contentparams-qualified',
    category: 'binding',
    title: 'ContentParams values must be bare attribute names, not $currentObject/Attr',
    severity: 'P2',
    cite: '.ai-context/skills/create-page.md:233-238; project STOP-12 note in mdlsource/usi/usi-89-route-list-banner-emptystate.mdl',
    exemplar: 'mdlsource/usi/done-usi-147-operation-detail-page.mdl:425',
    // KNOWN FALSE-POSITIVE SURFACE, stated rather than hidden: MCP-authored widgets
    // legitimately carry the qualified form (the MCP path has no such defect) and the
    // ELK output cannot tell us which channel wrote a widget. Severity is P2 for that reason.
    evaluate(ctx) {
      const bad = ctx.mdlNodes.filter((n) => /\$currentObject\//.test(prop(n, 'ContentParams') || ''));
      return {
        ok: bad.length === 0,
        findings: bad.map((n) => finding({ where: `${n.type} ${n.name}`, line: n.line, what: 'ContentParams uses $currentObject/Attr' })),
        detail: 'CLI-authored widgets must use the bare form; MCP-authored ones may not — verify the channel before fixing',
      };
    },
    remediate: (f) => `If ${f.map((x) => x.where).join(', ')} is maintained through the CLI, drop the \`$currentObject/\` prefix in the mdlsource/ script `
      + `(mxcli concatenates the qualified entity name → CE1613). If it was authored via Studio Pro MCP, leave it and record the waiver in the script header.`,
    mutate: (mdl) => mdl.replace('ContentParams: [{1} = Lifecycle_state]', 'ContentParams: [{1} = $currentObject/Lifecycle_state]'),
  },
  {
    id: 'binding/page-param-consumed',
    category: 'binding',
    title: 'Every declared page parameter must be consumed by a widget',
    severity: 'P2',
    cite: '.ai-context/skills/overview-pages.md:262-268; master-detail-pages.md:70-76',
    exemplar: 'mdlsource/usi/done-usi-03-page-routelist.mdl — $Filter is consumed by the dataview it was declared for',
    evaluate(ctx) {
      const params = (ctx.doc.parameters || []).map((p) => p.name).filter(Boolean);
      // The page BODY only. `ctx.mdl.indexOf('{')` lands inside the header's
      // `Params: { $Filter: ... }`, which made every parameter look consumed by
      // its own declaration — the rule could not fail. Caught by the control.
      const body = pageBodyOf(ctx.mdl);
      const bad = params.filter((p) => !new RegExp(`\\$${p}\\b`).test(body));
      return {
        ok: bad.length === 0,
        findings: bad.map((p) => finding({ where: `parameter $${p}`, what: 'declared but never referenced by any widget on the page' })),
        detail: params.length ? `${params.length} parameters declared` : 'page declares no parameters',
      };
    },
    remediate: (f) => `Either bind ${f.map((x) => x.where).join(', ')} with \`dataview dv (DataSource: ${f[0].where.replace('parameter ', '')}) { ... }\` `
      + `in the page's mdlsource/ script, or remove the parameter from the page header and from every caller that passes it.`,
    mutate: (mdl) => mdl.replace('DataSource: $Filter,', 'DataSource: $Unrelated,'),
  },
  {
    id: 'binding/selection-target-exists',
    category: 'binding',
    title: 'A `DataSource: selection <widget>` must name a widget that exists on the page',
    severity: 'P1',
    cite: '.ai-context/skills/master-detail-pages.md:132-146 (Selection Binding / Widget Names)',
    exemplar: 'mdlsource/usi/done-usi-147-operation-detail-page.mdl — detail pane binds the list widget by its exact name',
    evaluate(ctx) {
      const names = new Set(ctx.mdlNodes.map((n) => n.name));
      const refs = [...ctx.mdl.matchAll(/DataSource:\s*selection\s+([A-Za-z_][\w]*)/gi)].map((m) => m[1]);
      const bad = refs.filter((r) => !names.has(r));
      return {
        ok: bad.length === 0,
        findings: bad.map((r) => finding({ where: `selection ${r}`, what: 'names a widget that does not exist on this page — the detail pane will never populate' })),
        detail: refs.length ? `${refs.length} selection bindings resolved` : 'page has no selection bindings',
      };
    },
    remediate: (f) => `Correct the widget name in the \`DataSource: selection ...\` clause in the page's mdlsource/ script, and confirm the target list `
      + `carries \`Selection: Single\`. Read the live names with \`./mxcli -p ${MPR} describe page <Module>.<Page>\` — do not guess.`,
    mutate: (mdl) => mdl.replace('DataSource: microflow Control.DS_Rows', 'DataSource: selection dgDoesNotExist'),
  },

  // ── list behaviour ────────────────────────────────────────────────────────
  {
    id: 'list/empty-state',
    category: 'list',
    title: 'Every grid/list/gallery needs a zero-result empty state',
    severity: 'P2',
    cite: 'ui-preflight-pages.md Step 4 "Empty state"; module-review.md §4c; learned-stylegallery.md:199-205',
    exemplar: 'mdlsource/usi/usi-89-route-list-banner-emptystate.mdl:137-149 — container emptyState (Class: \'empty-state\')',
    evaluate(ctx) {
      const lists = ctx.mdlNodes.filter((n) => LIST_WIDGETS.includes(n.type));
      if (!lists.length) return { ok: true, findings: [], detail: 'page has no list widget', notApplicable: true };
      const hasEmptyClass = ctx.classes.some((c) => /empty/i.test(c));
      const bad = lists.filter((n) => !prop(n, 'EmptyMessage') && !hasEmptyClass);
      return {
        ok: bad.length === 0,
        findings: bad.map((n) => finding({ where: `${n.type} ${n.name}`, line: n.line, what: 'no EmptyMessage and no sibling with an empty-state class' })),
        detail: `${lists.length} list widgets inspected; page ${hasEmptyClass ? 'has' : 'has no'} empty-state class`,
      };
    },
    remediate: () => `Add the project's empty-state block next to the grid with an \`alter page\` script in mdlsource/: `
      + `\`container emptyState (Class: 'empty-state') { dynamictext t (Content: 'No results match these filters', RenderMode: H3, Class: 'empty-state__title') ... }\` `
      + `— copy the shape from mdlsource/usi/usi-89-route-list-banner-emptystate.mdl:137. A grid that renders nothing on zero rows is a P1 in module-review.md; `
      + `it is graded P2 here because the static view cannot prove the runtime is ever empty.`,
    mutate: (mdl) => mdl.split('empty-state').join('plainbox'),
  },

  // ── security ──────────────────────────────────────────────────────────────
  {
    id: 'security/grant-view',
    category: 'security',
    title: 'Every page must grant view to at least one module role',
    severity: 'P1',
    cite: 'lint MPR007 / CE0557; project convention — mdlsource/usi/done-usi-147-operation-detail-page.mdl:518',
    exemplar: 'mdlsource/usi/done-usi-147-operation-detail-page.mdl:518',
    evaluate(ctx) {
      const grants = [...ctx.mdl.matchAll(/grant view on page\s+([\w.]+)\s+to\s+([^;]+);/gi)];
      const roles = grants.flatMap((g) => g[2].split(',').map((s) => s.trim())).filter(Boolean);
      return {
        ok: roles.length > 0,
        findings: roles.length ? [] : [finding({ where: ctx.qn, what: 'no `grant view on page` — the page is unreachable for every role' })],
        detail: roles.length ? `granted to ${roles.length} role(s)` : 'no grants found in the describe output',
      };
    },
    remediate: (f, ctx) => `Append \`grant view on page ${ctx.qn} to <Module>.<Role>, ...;\` to the page's mdlsource/ script and re-exec it. `
      + `Name every module role that must reach the page — check .claude/loop/page-scope.json "roles" for the intended set.`,
    mutate: (mdl) => mdl.replace(/grant view on page[^;]*;/g, ''),
  },

  // ── style / design-system ─────────────────────────────────────────────────
  {
    id: 'style/buttonstyle-enum',
    category: 'style',
    title: 'ButtonStyle must be one of the seven legal Mendix values',
    severity: 'P2',
    cite: '.ai-context/skills/create-page.md:282-284 (MDL-WIDGET02)',
    exemplar: "mdlsource/usi/done-usi-147-operation-detail-page.mdl:400 — ButtonStyle: Info + Class: 'btn btn-secondary'",
    evaluate(ctx) {
      const btns = ctx.mdlNodes.filter((n) => /button/.test(n.type));
      const bad = [];
      for (const n of btns) {
        const v = unquote(prop(n, 'ButtonStyle'));
        if (v && !LEGAL_BUTTON_STYLES.includes(String(v).toLowerCase())) {
          bad.push(finding({ where: `${n.type} ${n.name}`, line: n.line, what: `ButtonStyle: ${v}` }));
        }
      }
      return { ok: bad.length === 0, findings: bad, detail: `${btns.length} buttons inspected` };
    },
    remediate: (f) => `In the page's mdlsource/ script set ${f.map((x) => x.where).join(', ')} to one of `
      + `${LEGAL_BUTTON_STYLES.join('/')} and express the visual variant through a design-system class from design/ds.css `
      + `(\`btn btn-secondary\`, \`btn btn-ghost\`, \`btn btn-cta\`) — that is the pattern used throughout mdlsource/usi/.`,
    mutate: (mdl) => mdl.replace('ButtonStyle: Primary', 'ButtonStyle: Secondary'),
  },
  {
    id: 'style/list-wrapper-layout-class',
    category: 'style',
    title: 'Never put a grid/flex layout class on a gallery or list wrapper',
    severity: 'P1',
    cite: 'learned-stylegallery.md §"Gallery Widget Layout — the wrapper-CSS trap" (lines 172-190) — "a real P1 from the WMS audit"',
    exemplar: 'set DesktopColumns/TabletColumns/PhoneColumns on the widget, or scope the CSS to .my-gallery .widget-gallery-content in themesource/<module>/web/main.scss',
    evaluate(ctx) {
      const lists = ctx.mdlNodes.filter((n) => LIST_WIDGETS.includes(n.type));
      const bad = [];
      for (const n of lists) {
        const offending = classesOf(n).filter((c) => /^(grid|flex|grid-[0-9]+|kpi-grid|flex-col)$/.test(c));
        if (offending.length) bad.push(finding({ where: `${n.type} ${n.name}`, line: n.line, what: `layout class on the widget wrapper: ${offending.join(' ')}` }));
        const style = String(unquote(prop(n, 'Style')) || '');
        if (/display\s*:\s*(grid|flex)/i.test(style)) bad.push(finding({ where: `${n.type} ${n.name}`, line: n.line, what: `inline display:${/grid/i.test(style) ? 'grid' : 'flex'} on the widget wrapper` }));
      }
      return { ok: bad.length === 0, findings: bad, detail: `${lists.length} list widgets inspected` };
    },
    remediate: (f) => `Mendix wraps list widgets in fixed structural children (.widget-gallery-top-bar / -content / -footer). A layout class on the outer element `
      + `strands the cards in the middle track. For ${f.map((x) => x.where).join(', ')}: either move the rule to `
      + `\`.<your-class> .widget-gallery-content\` in themesource/<module>/web/main.scss, or delete the class and set DesktopColumns/TabletColumns/PhoneColumns in the mdlsource/ script.`,
    mutate: (mdl) => mdl.replace('datagrid dgRows (', "datagrid dgRows (Class: 'grid-3', "),
  },
  {
    id: 'style/page-heading',
    category: 'style',
    title: 'Every page needs exactly one H1 heading widget',
    severity: 'P2',
    cite: 'module-review.md §4b (one h1 per page); .ai-context/skills/create-page.md RenderMode',
    exemplar: "mdlsource/usi/done-usi-03-page-routelist.mdl — dynamictext pageHeading (RenderMode: H1, Class: 'page-head')",
    evaluate(ctx) {
      const h1s = ctx.mdlNodes.filter((n) => /^H1$/i.test(String(unquote(prop(n, 'RenderMode')) || '')));
      return {
        ok: h1s.length === 1,
        findings: h1s.length === 1 ? [] : [finding({ where: ctx.qn, what: h1s.length === 0 ? 'no widget declares RenderMode: H1' : `${h1s.length} H1 widgets: ${h1s.map((n) => n.name).join(', ')}` })],
        detail: `${h1s.length} H1 heading widget(s)`,
      };
    },
    remediate: (f, ctx) => `In ${ctx.qn}'s mdlsource/ script give the page one and only one heading widget: `
      + `\`dynamictext pageHeading (Content: '<Page title>', RenderMode: H1, Class: 'page-head')\`, and demote the others to H2/H3. `
      + `Zero or multiple H1s is an axe "page-has-heading-one" / "heading-order" finding as well as a hierarchy bug.`,
    mutate: (mdl) => mdl.replace('RenderMode: H1, ', ''),
  },

  // ── component reuse (the StyleGallery exists to be reused) ────────────────
  {
    id: 'reuse/status-badge',
    category: 'reuse',
    title: 'A status/state/priority value must render through the badge component, not plain text',
    severity: 'P2',
    cite: 'ui-preflight-pages.md Step 3 "⛔ Reuse is mandatory" (lines 94-101); module-review.md §4e',
    exemplar: `mdlsource/gallery/13-badges-chips.mdl + ${EX.listPage}'s Lifecycle column: Class: 'badge badge-info'`,
    evaluate(ctx) {
      const bad = [];
      for (const n of ctx.mdlNodes) {
        if (n.type !== 'dynamictext') continue;
        const params = prop(n, 'ContentParams') || '';
        // `[{1} = Lifecycle_state]` — the value runs to the comma or the closing
        // bracket, and the last path segment is the attribute. An earlier `$`-anchored
        // regex never matched because of the trailing `]`, so this rule could not fail.
        const raw = /\{1\}\s*=\s*([^,\]]+)/.exec(params);
        const bound = raw ? String(raw[1]).trim().split('/').pop() : null;
        if (!bound || !/(state|status|priority|severity|phase|lifecycle)/i.test(bound)) continue;
        if (!classesOf(n).some((c) => /^(badge|chip|kt-badge)/.test(c))) {
          bad.push(finding({ where: `dynamictext ${n.name}`, line: n.line, what: `renders "${bound}" as plain text; the built badge component is not used` }));
        }
      }
      return { ok: bad.length === 0, findings: bad, detail: 'state-like bindings checked for badge reuse' };
    },
    remediate: (f) => `Add the gallery's badge classes to ${f.map((x) => x.where).join(', ')} in the page's mdlsource/ script — `
      + `\`Class: 'badge badge-info'\` (or -success/-warning/-danger/-neutral per design/ds.css), copying mdlsource/gallery/13-badges-chips.mdl. `
      + `A plain-text status column next to a built badge component is the exact defect module-review.md §4e exists to catch.`,
    mutate: (mdl) => mdl.replace("Class: 'badge badge-info'", "Class: 'plaintext'"),
  },
  {
    id: 'reuse/card-block-separation',
    category: 'reuse',
    title: 'Content blocks on a data page must be wrapped in the card component',
    severity: 'P2',
    cite: 'ui-preflight-pages.md Step 4 "Block separation"; oneshot-page-structure-patterns.md §6',
    exemplar: `${EX.listPage} — dataview dataView1 (Class: 'card spacing-outer-bottom-medium')`,
    evaluate(ctx) {
      const dataish = ctx.mdlNodes.some((n) => LIST_WIDGETS.includes(n.type) || n.type === 'dataview');
      if (!dataish) return { ok: true, findings: [], detail: 'page has no data block to separate', notApplicable: true };
      // Accept the design-system `card`, its parts (`card-body`), and Atlas's own
      // `mx-card` — this project's overview page wraps itself in `mx-card` and was a
      // false positive under a `^card` match. Also accept a Card design property.
      const hasCard = ctx.classes.some((c) => /(^|-)card(-|$)/.test(c))
        || /DesignProperties:[^\]]*['"]Card['"]/i.test(ctx.mdl);
      return {
        ok: hasCard,
        findings: hasCard ? [] : [finding({ where: ctx.qn, what: 'page has a data block but no `card` wrapper anywhere — it reads as one undifferentiated wall' })],
        detail: hasCard ? 'card wrapper present' : 'no card class in the union of tree and mdlSource',
      };
    },
    remediate: (f, ctx) => `Wrap each distinct content block of ${ctx.qn} in the design-system card — add \`Class: 'card spacing-outer-bottom-medium'\` `
      + `to the block's container/dataview in the page's mdlsource/ script (\`card\` is defined in design/ds.css). Copy the shape from ${EX.listPage}.`,
    mutate: (mdl) => mdl.split("card spacing-outer-bottom-medium").join('boxy'),
  },

  // ── conventions ───────────────────────────────────────────────────────────
  {
    id: 'convention/page-name-suffix',
    category: 'convention',
    title: 'Page names follow the Entity_Role convention',
    severity: 'P3',
    cite: '.ai-context/skills/overview-pages.md:440-450 (Naming Conventions); lint CONV003',
    exemplar: `${EX.overviewPage} / ${EX.detailPage} / ${EX.listPage}`,
    evaluate(ctx) {
      const short = ctx.qn.split('.')[1] || '';
      const ok = /_(Overview|NewEdit|Detail|List|Home|Scan|Count|Lab)$/.test(short);
      return {
        ok,
        findings: ok ? [] : [finding({ where: ctx.qn, what: `page name "${short}" does not end in a recognised role suffix` })],
        detail: `page short name: ${short}`,
      };
    },
    remediate: (f, ctx) => `Rename ${ctx.qn} to \`<Entity>_<Role>\` (Overview / NewEdit / Detail / List / Home) with a \`create or modify page\` script in mdlsource/, `
      + `then fix every caller found by \`./mxcli -p ${MPR} -c "SHOW REFERENCES TO ${ctx.qn}"\`. Cosmetic — schedule it, do not block a demo on it.`,
    mutateCtx: (ctx) => { ctx.qn = 'Control.Baseline'; },
  },
  {
    id: 'convention/page-title',
    category: 'convention',
    title: 'Page Title must be set and human-readable',
    severity: 'P3',
    cite: '.ai-context/skills/create-page.md (page header Title:); module-review.md §4c (browser-tab and breadcrumb text)',
    exemplar: "mdlsource/usi/done-usi-03-page-routelist.mdl — Title: 'Route List'",
    evaluate(ctx) {
      const t = String(ctx.doc.title || '').trim();
      const short = (ctx.qn.split('.')[1] || '');
      const bad = !t || t === short || /_/.test(t);
      return {
        ok: !bad,
        findings: bad ? [finding({ where: ctx.qn, what: t ? `Title "${t}" is the raw page name, not a human title` : 'Title is empty' })] : [],
        detail: `Title: ${t || '(empty)'}`,
      };
    },
    remediate: (f, ctx) => `Set a human title in ${ctx.qn}'s mdlsource/ script header — \`Title: 'Route List'\` — it is what the browser tab, `
      + `the breadcrumb and every screenshot caption show.`,
    mutateCtx: (ctx) => { ctx.doc = { ...ctx.doc, title: '' }; },
  },
];

// subtree helper used by a rule above (declared after RULES for readability is a
// hoisting hazard, so it lives here and is function-declared).
function subtree(node) {
  const out = [];
  (function rec(n) { for (const c of n.children || []) { out.push(c); rec(c); } })(node);
  return out;
}

// ── wireframe rules ──────────────────────────────────────────────────────────
// Separate array because they are graded per page as their OWN report section
// (requirement R4): a page with no wireframe is still fully graded by everything
// above, and the absence renders as an explicit state, never as a pass and never
// as a reason to skip the rest.
const WIREFRAME_RULES = [
  {
    id: 'wireframe/on-file',
    category: 'wireframe',
    title: 'The page has a wireframe on file',
    severity: 'P2',
    cite: 'ui-preflight-pages.md Step 1 — "If no wireframe exists: ⛔ STOP … the wireframe is not optional"',
    evaluate(ctx) {
      const w = ctx.wireframe;
      if (w.file && w.exists) return { ok: true, findings: [], detail: `design/wireframes/${w.file}` };
      return {
        ok: false,
        findings: [finding({ where: ctx.qn, what: w.file ? `mapped wireframe ${w.file} is missing from design/wireframes/` : 'NO WIREFRAME ON FILE' })],
        detail: w.why || 'no wireframe',
      };
    },
    remediate: (f, ctx) => `Draw \`design/wireframes/<${ctx.qn.split('.')[1].toLowerCase().replace(/_/g, '-')}>.html\` following design-artifacts.md `
      + `(annotated HTML: layout, binding table, .origin note), then add the mapping so the audit can compare against it. `
      + `Until it exists, every visual judgement about this page is unanchored — ui-preflight-pages.md Step 1 says STOP, and this page was built anyway.`,
    mutateCtx: (ctx) => { ctx.wireframe = { file: null, exists: false, why: 'control: wireframe removed' }; },
  },
  {
    id: 'wireframe/freshness',
    category: 'wireframe',
    title: 'The wireframe is not older than the page build scripts that name the page',
    severity: 'P3',
    cite: 'module-review.md Degrade-loudly table — "Wireframe older than the page\'s last build script (mtime)"',
    evaluate(ctx) {
      const w = ctx.wireframe;
      if (!w.exists) return { ok: true, findings: [], detail: 'no wireframe to date-check', notApplicable: true };
      if (!w.newestScript) return { ok: true, findings: [], detail: 'no mdlsource script names this page', notApplicable: true };
      const stale = w.mtime < w.newestScript.mtime;
      return {
        ok: !stale,
        findings: stale ? [finding({ where: w.file, what: `wireframe (${new Date(w.mtime).toISOString().slice(0, 10)}) predates ${w.newestScript.file} (${new Date(w.newestScript.mtime).toISOString().slice(0, 10)}) — divergence may be intentional and undocumented` })] : [],
        detail: `wireframe ${new Date(w.mtime).toISOString().slice(0, 10)} vs newest script ${new Date(w.newestScript.mtime).toISOString().slice(0, 10)}`,
      };
    },
    remediate: (f, ctx) => `Either refresh design/wireframes/${ctx.wireframe.file} to match what was built, or add a dated note in the wireframe's `
      + `annotation block recording that the build deliberately diverged and why. A silently stale wireframe makes the next visual review compare against fiction.`,
    mutateCtx: (ctx) => { ctx.wireframe = { ...ctx.wireframe, exists: true, mtime: 1, newestScript: { file: 'mdlsource/control.mdl', mtime: 2e12 } }; },
  },
  {
    id: 'wireframe/region-coverage',
    category: 'wireframe',
    title: 'The regions the wireframe names appear in the built page',
    severity: 'P3',
    // HEURISTIC AND LABELLED AS SUCH. Matching wireframe heading text against page
    // text can only ever be suggestive; it is graded so that it fires on gross
    // divergence (nothing matched) and stays quiet on wording differences.
    cite: 'module-review.md §4d — "is a region missing, is the information hierarchy inverted"',
    provenance: 'inferred',
    evaluate(ctx) {
      const w = ctx.wireframe;
      if (!w.exists) return { ok: true, findings: [], detail: 'no wireframe to compare against', notApplicable: true };
      const heads = w.headings || [];
      if (heads.length < 3) return { ok: true, findings: [], detail: `wireframe has only ${heads.length} headings — too few to judge`, notApplicable: true };
      const corpus = ctx.pageText.toLowerCase();
      const norm = (s) => s.toLowerCase().replace(/[^a-z0-9 ]+/g, ' ').replace(/\s+/g, ' ').trim();
      const matched = heads.filter((h) => {
        const words = norm(h).split(' ').filter((x) => x.length > 3);
        if (!words.length) return true;
        return words.some((x) => corpus.includes(x));
      });
      const ratio = matched.length / heads.length;
      return {
        ok: ratio > 0.34,
        findings: ratio > 0.34 ? [] : [finding({ where: w.file, what: `only ${matched.length}/${heads.length} wireframe regions have any textual counterpart on the page: missing ≈ ${heads.filter((h) => !matched.includes(h)).slice(0, 6).join(' | ')}` })],
        detail: `${matched.length}/${heads.length} wireframe headings matched page text (heuristic)`,
      };
    },
    remediate: (f, ctx) => `Open design/wireframes/${ctx.wireframe.file} beside a screenshot of the page and confirm each named region was built. `
      + `This check is a heuristic on heading text, so treat it as a prompt for the module-review.md §4d side-by-side, not as proof of a missing region.`,
    mutateCtx: (ctx) => { ctx.wireframe = { ...ctx.wireframe, exists: true, headings: ['Zygomorphic Manifold', 'Quixotic Ledger', 'Brumal Cadastre', 'Fylfot Reticule'] }; },
  },
];

// ── live (DOM) rules ─────────────────────────────────────────────────────────
// These are declared here so the category list is complete and a --static-only run
// reports them as `fault` (did not measure) rather than omitting them, which would
// render as green. Their evaluate() takes a DOM probe result, not a Playwright page,
// so the positive control can drive them from a file:// fixture with the app down.
const LIVE_RULES = [
  {
    id: 'live/renders-content',
    category: 'live',
    title: 'The page renders substantive content and no runtime error dialog',
    severity: 'P1',
    cite: 'module-review.md §4c — mxbuild-clean pages still ship blank',
    evaluate(ctx) {
      const p = ctx.probe;
      const bad = [];
      if (p.errorDialog) bad.push(finding({ where: ctx.qn, what: `runtime error dialog on screen: ${String(p.errorDialogText).slice(0, 160)}` }));
      if (p.textLength < 120) bad.push(finding({ where: ctx.qn, what: `only ${p.textLength} characters of text rendered — the page is effectively blank` }));
      return { ok: bad.length === 0, findings: bad, detail: `${p.textLength} chars of text, ${p.widgetCount} mx widgets` };
    },
    remediate: (f, ctx) => `Open ${ctx.qn} in the running app and read the browser console and the runtime log. A blank page with a clean mxbuild is almost always `
      + `a datasource microflow returning nothing or erroring — check the microflow behind the page's dataview with \`./mxcli -p ${MPR} describe microflow <MF>\`, `
      + `and confirm the import mapping was re-selected in Studio Pro if the source is REST.`,
    mutateProbe: () => ({ textLength: 8, widgetCount: 0, errorDialog: true, errorDialogText: 'An error occurred, please contact your system administrator', lists: [] }),
  },
  {
    id: 'live/empty-list-message',
    category: 'live',
    title: 'A list rendering zero rows shows an empty-state message',
    severity: 'P1',
    cite: 'module-review.md §4c — "a grid with no empty-state"; only the DOM can answer this',
    evaluate(ctx) {
      const p = ctx.probe;
      if (!p.lists || !p.lists.length) return { ok: true, findings: [], detail: 'no list widget rendered', notApplicable: true };
      const bad = p.lists.filter((l) => l.rows === 0 && !l.hasEmptyText);
      return {
        ok: bad.length === 0,
        findings: bad.map((l) => finding({ where: l.selector, what: 'rendered zero rows and showed no empty-state text' })),
        detail: `${p.lists.length} lists on screen; ${p.lists.filter((l) => l.rows === 0).length} empty`,
      };
    },
    remediate: () => `Add the empty-state block described by list/empty-state above, and verify it by filtering the grid to zero results in the running app. `
      + `Note the second possible cause: an empty list has five silent causes (no data, failed datasource, wrong scope, security, unselected import mapping) — `
      + `measure which one with an OQL count before "fixing" the UI.`,
    mutateProbe: () => ({ textLength: 900, widgetCount: 12, errorDialog: false, errorDialogText: null, lists: [{ selector: '.mx-name-dgRows', rows: 0, hasEmptyText: false }] }),
  },
];

const ALL_CATEGORIES = ['completeness', 'structure', 'binding', 'list', 'security', 'style',
  'reuse', 'convention', 'wireframe', 'live'];

// Advice from the same skills that CANNOT be mechanically evaluated. Emitted into
// the artifact verbatim so a per-page report says what it did not judge, rather
// than letting silence imply the page was judged on it.
const HUMAN_JUDGEMENT = [
  { topic: 'Is this the right page at all?', note: 'A page can pass every class and structure check and still be the wrong page — wrong information hierarchy, an affordance the wireframe implied that was never built.', cite: 'module-review.md §4d' },
  { topic: 'Which element is THE call to action', note: 'The --primary / --cta split is a design decision per screen; no rule can pick the one CTA.', cite: 'learned-stylegallery.md §Token Naming' },
  { topic: 'Static container vs real widget', note: 'Whether a gallery component should be a hardcoded container or a live widget depends on what it is demonstrating.', cite: 'learned-stylegallery.md §Static vs Real-Widget Components' },
  { topic: 'Is the caption the right business word', note: 'Column captions and labels being *correct domain language* is a BA judgement against the BRDs.', cite: 'module-review.md §4f' },
  { topic: 'Snippet vs inline', note: 'Only purely visual, data-agnostic components should become snippets; data-bound widgets must stay inline.', cite: '.ai-context/skills/fragments.md' },
  { topic: 'Silent save failure', note: 'Submitting a form with required fields empty and watching for a visible validation message needs interaction, not a screenshot.', cite: 'module-review.md §4c' },
  { topic: 'Root-causing a visual symptom', note: 'getComputedStyle + judgement to find which DOM level a wrong class landed on.', cite: 'module-review.md §4d' },
];

module.exports = {
  RULES, WIREFRAME_RULES, LIVE_RULES, ALL_CATEGORIES, HUMAN_JUDGEMENT,
  parseMdlTree, pageBodyOf, prop, unquote, classesOf, subtree, ancestors, hasAncestor,
  INPUT_WIDGETS, LIST_WIDGETS, CONTAINER_WIDGETS, CONTEXT_WIDGETS, LEGAL_BUTTON_STYLES,
};
