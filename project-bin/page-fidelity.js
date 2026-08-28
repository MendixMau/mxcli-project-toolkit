#!/usr/bin/env node
// page-fidelity.js — score one drafted/built page's MDL against its wireframe, model-side.
//
// Promoted from process/prototypes/first-build-fidelity.proto.js after the VB-USI-main
// field run (2026-08-27). The prototype assumed ToeicBuddy's wireframe shape on two axes
// that do not travel:
//
//   * content boundary — ToeicBuddy wireframes wrap page content in <main>; VB-USI's
//     wrap popup content in .dialog and full-page content in bare divs, with annotation
//     chrome (wf-bar, wf-note, wf-section, the .bind table, DESCOPED banners) as
//     siblings. Scoring the whole body counts the annotation against the page.
//   * MDL case — the prototype matched CREATE...PAGE uppercase only; VB-USI's scripts
//     write it lowercase (same bug fixed in check-page-shell.sh, commit e0588e3).
//
// Usage:
//   page-fidelity.js <wireframe.html> <page-name> <mdl-file> [mdl-file...]
//   page-fidelity.js <wireframe.html> <page-name> -        (MDL on stdin, e.g. DESCRIBE output)
//
// Scoring: headings 25%, action labels 30%, content blocks 25%, structural classes 20%,
// bindings 25% (normalized over the dimensions the wireframe actually uses — one it
// doesn't use is dropped from the denominator). Prints per-dimension hits and every miss;
// exits 0 always — it is an instrument, not a gate. The gate is check-page-shell.sh.
//
// Third field run (ToeicBuddy Reading_Part, 2026-08-27) added bind-table awareness:
// on a data-heavy page nearly all visible copy is BOUND (passages, stems, options),
// and scoring it as literal text put a screenshot-verified faithful page at 43%.
// Now: wireframe-local mock classes (defined in the wireframe's own <style>) mark
// bound-data regions whose sample text leaves the text dimensions, and the binding-
// annotation table's Datasource identifiers are scored as their own dimension.
//
// STATED LIMITATION: identifier presence cannot see NESTING. The pre-fix Reading_Part
// (passage re-rendered per question instead of once per group — the script 64 defect)
// scores identically to the fixed page: same identifiers, same classes, wrong tree.
// List-nesting faithfulness stays with the LOOK pass (ui-review-loop.md) — this
// instrument will not catch it, by construction. Verified, not assumed: scored the
// pre-64 script set and the post-64 set; both 100%.
//
// EVERY RUN IS RECORDED. A score printed to a terminal evaporates — the MarkUseCase field
// run (2026-08-27) built its first pages with no fidelity trace at all, and "what went
// wrong" had to be reconstructed from a session status line. So the scorer appends each
// run to <project>/docs/PAGE-FIDELITY.tsv (project root = nearest .mpr above the
// wireframe). The FIRST NON-STUB row for a page is its first-build score of record — the
// number the 80% target judges; later rows show the rework curve. A forward-reference
// stub page (iterative-build-loop.md § Forward references — created only so a later
// script's references resolve) is scored with --stub: its row lands marked `stub` and
// is exempt from the target, because the stub is deliberately not the build. The
// exemption is the flag, never inferred — a bare page that someone forgot to finish
// scores as what it is. --no-log suppresses logging entirely (for scoring fixtures or
// another project's files); an unloggable run says so on stderr rather than logging
// silently nowhere.
'use strict';
const fs = require('fs');
const path = require('path');

const argv = process.argv.slice(2);
const NOLOG = argv.includes('--no-log');
const STUB = argv.includes('--stub');
const [WF, PAGE, ...MDLS] = argv.filter(a => a !== '--no-log' && a !== '--stub');
if (!WF || !PAGE || !MDLS.length) {
  console.error('usage: page-fidelity.js [--no-log] [--stub] <wireframe.html> <page-name> <mdl-file...|->');
  process.exit(2);
}

// ---- wireframe side -------------------------------------------------------------------

// Remove an element and its balanced subtree wherever the opening tag matches `openRe`.
// The prototype's non-greedy `[\s\S]*?<\/div>` stopped at the first close tag and left
// the tail of every nested annotation block in the denominator.
function dropBalanced(html, openRe) {
  let out = html, m;
  while ((m = out.match(openRe))) {
    const start = m.index;
    const tag = m[1].toLowerCase();
    const re = new RegExp('<' + tag + '\\b|</' + tag + '>', 'gi');
    re.lastIndex = start + 1;
    let depth = 1, end = out.length, t;
    while (depth > 0 && (t = re.exec(out))) {
      depth += t[0][1] === '/' ? -1 : 1;
      end = re.lastIndex;
    }
    out = out.slice(0, start) + ' ' + out.slice(end);
  }
  return out;
}

// Inner HTML of the first element whose opening tag matches `openRe` (balanced).
function innerBalanced(html, openRe) {
  const m = html.match(openRe);
  if (!m) return null;
  const tag = m[1].toLowerCase();
  const open = html.indexOf('>', m.index) + 1;
  const re = new RegExp('<' + tag + '\\b|</' + tag + '>', 'gi');
  re.lastIndex = open;
  let depth = 1, end = html.length, t;
  while (depth > 0 && (t = re.exec(html))) {
    depth += t[0][1] === '/' ? -1 : 1;
    if (depth === 0) end = t.index;
  }
  return html.slice(open, end);
}

function contentOf(html) {
  // Boundary preference, most-specific first:
  //   <main>            ToeicBuddy shape — content-only wireframes
  //   div.main          VB-USI full-page shape — the wireframe mocks the WHOLE app
  //                     shell; the sidebar is layout chrome, but div.main holds the
  //                     page title (VB-USI titles pages from the top bar), so it is
  //                     the boundary and the user chip is stripped below
  //   div.wf-screen     DealIQ shape — the wireframe is an annotated DOCUMENT, and the
  //   div.wf-shell      screen is one labelled block inside it, with the annotation
  //   div.mockup-frame  apparatus (meta header, binding tables, scope crosschecks) as
  //                     siblings. A wireframe that names its own screen has told us
  //                     where the boundary is; falling through to <body> scores the
  //                     annotation against the page. See the null-score note below.
  //                     Three names because one project's own wireframes were not
  //                     internally consistent: 02/03 .wf-screen, 04 .wf-shell,
  //                     06/07 .mockup-frame. Measured, not assumed — every one of them
  //                     fell through to <body> before this list existed.
  //   div.content       same shape when the wireframe has no .main wrapper
  //   <body>            popup/dialog wireframes with annotation siblings
  // then strip annotation chrome either way.
  const m = html.match(/<main[^>]*>([\s\S]*?)<\/main>/i);
  let s = m ? m[1]
    : innerBalanced(html, /<(div)[^>]*class="[^"]*\bwf-screen\b[^"]*"/i)
    || innerBalanced(html, /<(div)[^>]*class="[^"]*\bwf-shell\b[^"]*"/i)
    || innerBalanced(html, /<(div)[^>]*class="[^"]*\bmockup-frame\b[^"]*"/i)
    || innerBalanced(html, /<(div)[^>]*class="[^"]*\bmain\b[^"]*"/i)
    || innerBalanced(html, /<(div)[^>]*class="[^"]*\bcontent\b[^"]*"/i)
    || (html.match(/<body[^>]*>([\s\S]*)<\/body>/i) || [, html])[1];
  s = dropBalanced(s, /<(div)[^>]*class="[^"]*\buserchip\b[^"]*"/i);
  // wf-note is a <p> at least as often as a <div> ("Header binding note: ...", "Six rows,
  // MEDPIC SortOrder 1-6"). Prose ABOUT the page is not page copy whichever tag carries it;
  // scoring it as page copy is why an annotation-heavy wireframe reads as a content miss.
  s = dropBalanced(s, /<(div|p)[^>]*class="[^"]*wf-(?:bar|note|annot|meta|head)[^"]*"/i);
  s = dropBalanced(s, /<(div)[^>]*class="[^"]*wf-section[^"]*"/i);
  // Annotation apparatus that does not carry the wf- prefix: section captions, the
  // binding/scope-crosscheck table wrappers, and "out of scope for this wireframe"
  // callouts. Vocabulary, like .userchip and table.bind above — extend as shapes arrive.
  s = dropBalanced(s, /<(div)[^>]*class="[^"]*\bsection-h\b[^"]*"/i);
  s = dropBalanced(s, /<(div)[^>]*class="[^"]*\banno-wrap\b[^"]*"/i);
  s = dropBalanced(s, /<(div)[^>]*class="[^"]*\brail-note\b[^"]*"/i);
  s = dropBalanced(s, /<(div)[^>]*class="[^"]*\bannot\b[^"]*"/i);
  s = dropBalanced(s, /<(table)[^>]*class="[^"]*\bbind\b[^"]*"/i);
  // A "this screen is descoped/annotation-only" banner is chrome, not page copy.
  s = dropBalanced(s, /<(div)[^>]*class="[^"]*alert[^"]*"(?=[\s\S]{0,400}?DESCOPED)/i);
  return s;
}

const strip = s => s.replace(/<[^>]+>/g, ' ').replace(/&[a-z]+;/g, ' ').replace(/\s+/g, ' ').trim();
const norm  = s => s.toLowerCase().replace(/[^a-z0-9 ]+/g, ' ').replace(/\s+/g, ' ').trim();
const words = s => norm(s).split(' ').filter(w => w.length > 3);

// Classes defined in the wireframe's OWN <style> block are wireframe-local mock
// scaffolding, not design-system classes (those live in ds.css, which wireframes
// link). Measured (ToeicBuddy Reading_Part, 2026-08-27): .passage/.qcard exist
// only to mock the bound-data list items — passage bodies, question stems,
// option buttons — whose literal text a correctly-BINDING page contains none of
// (same reasoning as the <td> exclusion). Their subtrees leave the text
// dimensions and the classes leave the class denominator; both are REPORTED.
// ...but a wireframe's own <style> also defines its STRUCTURE and its ANNOTATION
// apparatus, and those are not mocks of bound data. Treating them as mocks does not
// merely mis-score — dropBalanced removes the matched subtree, so classing the
// wireframe's outer wrapper as a mock DELETES THE ENTIRE PAGE, and every dimension
// then reports 0-of-0, which normalizes to a null score rather than to a low one.
//
// Measured (DealIQ, 2026-08-28): wireframes shaped .wf-wrap > .wf-screen scored `null%`
// on all seven pages. Nothing failed and nothing said "unmeasured" — the run printed a
// clean report over an empty corpus. That is the failure mode worth fixing: the
// instrument is the score of record, and it was silently scoring nothing.
//
// The wf- prefix is already the annotation vocabulary elsewhere in this file (see the
// class-denominator filter in wfFacts), so the rule is the prefix, not a name list.
// The unprefixed entries are vocabulary, same as .userchip and table.bind in contentOf.
const SCAFFOLD_CLASSES = ['bind', 'bt', 'section-h', 'anno-wrap', 'rail-note', 'anno'];
const isScaffoldClass = c => /^wf-/.test(c) || SCAFFOLD_CLASSES.includes(c);

function localMockClasses(html) {
  const out = new Set();
  for (const st of html.matchAll(/<style[^>]*>([\s\S]*?)<\/style>/gi)) {
    // Comments first. A wireframe's <style> is commented prose as much as it is CSS, and
    // that prose NAMES CLASSES: "same bug class as .card/.right/.chat earlier this
    // session" harvested .card — a design-system class the wireframe only mentions —
    // whose subtree is every card on the page. Scoring then ran over what was left of a
    // gutted page. Cause and cure are both one line; the symptom was a 0% on a page that
    // screenshots as faithful.
    const css = st[1].replace(/\/\*[\s\S]*?\*\//g, ' ');
    for (const sel of css.matchAll(/\.([a-z][a-z0-9-]*)/gi)) out.add(sel[1]);
  }
  return out;
}

// The binding-annotation table (table.bind / table.bt) is dropped from the text
// corpus — but its Datasource column names real model identifiers, and whether
// the page actually references them is the fidelity backbone of a data-heavy
// page. One row per binding; a row scores when every identifier-looking token
// in its datasource cell (CamelCase words, Entity.Attr paths) appears in the
// page MDL. Rows whose cell names no identifier are annotation prose and skip.
function bindRows(html) {
  const t = innerBalanced(html, /<(table)[^>]*class="[^"]*\b(?:bind|bt)\b[^"]*"/i);
  if (!t) return [];
  const rows = [];
  for (const tr of t.matchAll(/<tr[^>]*>([\s\S]*?)<\/tr>/gi)) {
    const cells = [...tr[1].matchAll(/<t[dh][^>]*>([\s\S]*?)<\/t[dh]>/gi)].map(c => strip(c[1]));
    if (!cells.length || /<th/i.test(tr[1])) continue;
    const src = cells[2] || '';
    const ids = new Set();
    for (const m of src.matchAll(/\b([A-Z][A-Za-z0-9]*\.[A-Z][A-Za-z0-9_]*)\b/g))
      m[1].split('.').forEach(x => ids.add(x));
    for (const m of src.matchAll(/\b([A-Z][a-z0-9]+(?:[A-Z][A-Za-z0-9]*)+)\b/g)) ids.add(m[1]);
    if (ids.size) rows.push({ label: (cells[0] || '?').slice(0, 40), ids: [...ids] });
  }
  return rows;
}

function wfFacts(file) {
  const html = fs.readFileSync(file, 'utf8');
  const mock = localMockClasses(html);
  let main = contentOf(html);
  const mockUsed = [];
  const structural = [];
  for (const c of mock) {
    if (isScaffoldClass(c)) continue;
    const re = new RegExp('<(div|button|span|p)[^>]*class="[^"]*\\b' + c + '\\b[^"]*"', 'i');
    if (!re.test(main)) continue;
    const after = dropBalanced(main, re);
    // STRUCTURE IS NOT A MOCK. A bound-data mock is a repeated REGION of the page —
    // .passage/.qcard occur once per list item, which is what makes their sample text
    // bound data. A class that occurs ONCE and whose subtree is most of the page is the
    // wireframe's own wrapper (.wf-wrap, .mockup-frame), and dropping it deletes the page.
    // Both tests must hold, so a genuinely dominant repeated mock still scores as a mock.
    const uses = (main.match(new RegExp(re.source, 'gi')) || []).length;
    const kept = strip(after).length / Math.max(1, strip(main).length);
    if (uses === 1 && kept < 0.4) { structural.push(c); continue; }
    mockUsed.push(c); main = after;
  }
  const grab = re => [...main.matchAll(re)].map(x => strip(x[1])).filter(Boolean);
  const headings = grab(/<h[1-4][^>]*>([\s\S]*?)<\/h[1-4]>/gi);
  const buttons  = grab(/<button[^>]*>([\s\S]*?)<\/button>/gi);
  // <th> (column captions) is page-owned copy; <td> deliberately is NOT — a
  // wireframe's table cells are sample rows of BOUND data, and a page that
  // correctly binds them contains none of the literal text (same reasoning as
  // check-page-shell.sh's "bound content" non-check).
  const blocks   = [...grab(/<p[^>]*>([\s\S]*?)<\/p>/gi), ...grab(/<li[^>]*>([\s\S]*?)<\/li>/gi),
                    ...grab(/<label[^>]*>([\s\S]*?)<\/label>/gi), ...grab(/<th[^>]*>([\s\S]*?)<\/th>/gi),
                    ...grab(/<span[^>]*>([\s\S]*?)<\/span>/gi),
                    ...grab(/<div class="muted"[^>]*>([\s\S]*?)<\/div>/gi)];
  const classes = new Set();
  for (const x of main.matchAll(/class="([^"]+)"/g))
    x[1].split(/\s+/).forEach(c => { if (c && !/^(wf-|ann|crosscheck|alert-ic|x-btn|req)/.test(c)) classes.add(c); });
  // Classes confined to the wireframe's table.grid mock describe markup the
  // DATAGRID widget renders itself (wrapper, filter row, cell emphasis) — a page
  // cannot declare them. Curated: pill/status classes stay scored, because a page
  // CAN declare those (Class/DynamicClasses on in-column widgets).
  const GRID_OWN = ['grid', 'table-wrap', 'filter-row', 'actions', 'key', 'mono', 'input', 'row-blocked'];
  const outside = new Set();
  const noGrids = dropBalanced(main, /<(table)[^>]*class="[^"]*\bgrid\b[^"]*"/i);
  for (const x of noGrids.matchAll(/class="([^"]+)"/g)) x[1].split(/\s+/).forEach(c => outside.add(c));
  const gridOnly = GRID_OWN.filter(c => classes.has(c) && !outside.has(c));
  const mockCls = [...classes].filter(c => mockUsed.includes(c) || mock.has(c));
  mockCls.forEach(c => classes.delete(c));
  return { headings, buttons, blocks: blocks.filter(b => b.length > 12), classes: [...classes],
           gridOnly, mockUsed, structural, mockCls, binds: bindRows(html) };
}

// ---- MDL side -------------------------------------------------------------------------

function pageMdl() {
  let out = '';
  for (const f of MDLS) {
    const src = f === '-' ? fs.readFileSync(0, 'utf8') : fs.readFileSync(f, 'utf8');
    // Case-insensitive; page name quoted or bare; body up to a closing brace at col 0.
    const re = new RegExp(
      'CREATE(\\s+OR\\s+(MODIFY|REPLACE))?\\s+PAGE\\s+"?[A-Za-z0-9_]+"?\\."?' + PAGE + '"?\\b[\\s\\S]*?\\n\\}', 'gi');
    for (const m of src.matchAll(re)) out += m[0] + '\n';
  }
  return out;
}

function score(wf, mdl) {
  const corpus = norm(mdl);
  const cls = new Set();
  for (const m of mdl.matchAll(/Class:\s*['"]([^'"]+)['"]/gi)) m[1].split(/\s+/).forEach(c => cls.add(c));
  // DynamicClasses expressions emit class names conditionally — every quoted
  // token that looks like a class name lands in the DOM on some branch.
  for (const m of mdl.matchAll(/DynamicClasses:\s*'((?:[^']|'')*)'/gi))
    for (const t of m[1].matchAll(/''([a-z][a-z0-9-]*)''|'([a-z][a-z0-9-]*)'/gi))
      cls.add(t[1] || t[2]);
  const hit = txt => { const w = words(txt); return w.length ? w.filter(x => corpus.includes(x)).length / w.length >= 0.6 : true; };
  const dim = arr => ({ n: arr.length, ok: arr.filter(hit).length, miss: arr.filter(x => !hit(x)) });
  const h = dim(wf.headings), b = dim(wf.buttons), k = dim(wf.blocks);
  // Platform-supplied classes are not the page's to declare, so they leave the
  // denominator — REPORTED, never silently dropped (see the printout below):
  //   * on a popup layout, the dialog frame (dialog/dialog-head/-body/-foot) is
  //     rendered by the layout; a page that restated it would be duplicating
  //     chrome (learned-page-patterns.md, "Never Duplicate the Chrome Title").
  //   * a wireframe's <label>/<input> pair IS the MDL textbox widget — the widget
  //     emits both elements itself, so a textbox on the page satisfies them.
  //   * on a full-page layout, the top bar itself (its page title is still scored
  //     — the heading and crumb live in the page's own header block).
  const popup = /Layout:\s*[^,)\n]*Popup/i.test(mdl);
  const chromeSet = new Set(popup ? ['dialog', 'dialog-head', 'dialog-body', 'dialog-foot']
                                  : ['topbar', 'userchip', 'avatar', 'content']);
  const intrinsic = new Set(/\btextbox\b|\btextfilter\b/i.test(mdl) ? ['label', 'input'] : []);
  if (/\bdatagrid\b/i.test(mdl)) wf.gridOnly.forEach(x => intrinsic.add(x));
  const scoredCls = wf.classes.filter(x => !chromeSet.has(x));
  const cMiss = scoredCls.filter(x => !cls.has(x) && !intrinsic.has(x));
  const c = { n: scoredCls.length, ok: scoredCls.length - cMiss.length, miss: cMiss,
              chrome: wf.classes.filter(x => chromeSet.has(x)) };
  // Bindings: every identifier the annotation row names must appear in the MDL.
  const bindMiss = wf.binds.filter(r => !r.ids.every(id => corpus.includes(norm(id))));
  const bd = { n: wf.binds.length, ok: wf.binds.length - bindMiss.length, miss: bindMiss };
  const parts = [[h, .25], [b, .30], [k, .25], [c, .20], [bd, .25]];
  let num = 0, den = 0;
  for (const [d, w] of parts) if (d.n) { num += w * (d.ok / d.n); den += w; }
  return { pct: den ? Math.round(100 * num / den) : null, h, b, k, c, bd };
}

const wf = wfFacts(WF);
const mdl = pageMdl();
if (!mdl.trim()) { console.error('page-fidelity: no declaration of page "' + PAGE + '" found in input'); process.exit(2); }
const s = score(wf, mdl);
console.log(PAGE + '  fidelity ' + s.pct + '%   headings ' + s.h.ok + '/' + s.h.n +
  '  actions ' + s.b.ok + '/' + s.b.n + '  content ' + s.k.ok + '/' + s.k.n + '  classes ' + s.c.ok + '/' + s.c.n +
  (s.bd.n ? '  bindings ' + s.bd.ok + '/' + s.bd.n : ''));
const miss = [...s.h.miss.map(x => 'heading: ' + x), ...s.b.miss.map(x => 'action:  ' + x),
              ...s.k.miss.map(x => 'content: ' + x.slice(0, 78)),
              ...(s.c.miss.length ? ['classes: ' + s.c.miss.join(' ')] : []),
              ...s.bd.miss.map(r => 'binding: ' + r.label + ' (' + r.ids.join(' ') + ')')];
if (miss.length) console.log('  missed:\n  ' + miss.join('\n  '));
if (s.c.chrome.length) console.log('  chrome (layout-supplied, not scored): ' + s.c.chrome.join(' '));
if (wf.mockUsed.length) console.log('  bound-data mocks (wireframe-local, text not scored): ' + wf.mockUsed.join(' '));
if (wf.structural.length) console.log('  wireframe structure (kept as page content, not a mock): ' + wf.structural.join(' '));
if (wf.mockCls.length) console.log('  wireframe-local classes (not scored): ' + wf.mockCls.join(' '));
if (STUB) console.log('  stub — forward-reference target, exempt from the 80% target; the first non-stub row is the score of record');

// ---- record the run (see header: EVERY RUN IS RECORDED) -------------------------------
if (!NOLOG) {
  try {
    // Project root = nearest directory containing a .mpr, walking up from the wireframe.
    let root = null, d = path.resolve(path.dirname(WF));
    for (let i = 0; i < 12; i++) {
      let entries = [];
      try { entries = fs.readdirSync(d); } catch (e) { break; }
      if (entries.some(f => f.endsWith('.mpr'))) { root = d; break; }
      const up = path.dirname(d);
      if (up === d) break;
      d = up;
    }
    if (!root) {
      console.error('page-fidelity: score NOT logged — no .mpr found above ' + WF +
        ' (pass --no-log to silence this when scoring fixtures)');
    } else {
      const tsv = path.join(root, 'docs', 'PAGE-FIDELITY.tsv');
      fs.mkdirSync(path.join(root, 'docs'), { recursive: true });
      if (!fs.existsSync(tsv)) {
        fs.writeFileSync(tsv,
          '# PAGE-FIDELITY.tsv — appended by project-bin/page-fidelity.js on every run.\n' +
          '# The first NON-STUB row for a page is its first-build score of record (target:\n' +
          '# >=80%); later rows for the same page show the rework curve. Rows with source\n' +
          '# `stub` are forward-reference targets (scored with --stub) and are exempt from\n' +
          '# the target. Do not edit rows by hand.\n' +
          'date\tpage\tscore\theadings\tactions\tcontent\tclasses\tbindings\tsource\twireframe\n');
      }
      const frac = x => x.n ? x.ok + '/' + x.n : '-';
      const row = [
        new Date().toISOString().slice(0, 16).replace('T', ' '),
        PAGE, s.pct === null ? '-' : s.pct + '%',
        frac(s.h), frac(s.b), frac(s.k), frac(s.c), frac(s.bd),
        STUB ? 'stub' : MDLS[0] === '-' ? 'describe' : 'draft',
        path.relative(root, path.resolve(WF)),
      ].join('\t');
      fs.appendFileSync(tsv, row + '\n');
      console.log('  logged: ' + path.relative(process.cwd(), tsv));
    }
  } catch (e) {
    console.error('page-fidelity: score NOT logged (' + e.message + ')');
  }
}
