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
// Scoring (unchanged from the prototype, so numbers stay comparable to the 32%-median
// ToeicBuddy baseline): headings 25%, action labels 30%, content blocks 25%,
// structural classes 20%. A dimension the wireframe doesn't use is dropped from the
// denominator. Prints per-dimension hits and every miss; exits 0 always — it is an
// instrument, not a gate. The gate is check-page-shell.sh.
'use strict';
const fs = require('fs');

const [WF, PAGE, ...MDLS] = process.argv.slice(2);
if (!WF || !PAGE || !MDLS.length) {
  console.error('usage: page-fidelity.js <wireframe.html> <page-name> <mdl-file...|->');
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

function contentOf(html) {
  // Boundary preference: <main> (ToeicBuddy shape) → whole body (VB-USI shape),
  // then strip annotation chrome either way.
  const m = html.match(/<main[^>]*>([\s\S]*?)<\/main>/i);
  let s = m ? m[1] : (html.match(/<body[^>]*>([\s\S]*)<\/body>/i) || [,html])[1];
  s = dropBalanced(s, /<(div)[^>]*class="[^"]*wf-(?:bar|note)[^"]*"/i);
  s = dropBalanced(s, /<(div)[^>]*class="[^"]*wf-section[^"]*"/i);
  s = dropBalanced(s, /<(table)[^>]*class="[^"]*\bbind\b[^"]*"/i);
  // A "this screen is descoped/annotation-only" banner is chrome, not page copy.
  s = dropBalanced(s, /<(div)[^>]*class="[^"]*alert[^"]*"(?=[\s\S]{0,400}?DESCOPED)/i);
  return s;
}

const strip = s => s.replace(/<[^>]+>/g, ' ').replace(/&[a-z]+;/g, ' ').replace(/\s+/g, ' ').trim();
const norm  = s => s.toLowerCase().replace(/[^a-z0-9 ]+/g, ' ').replace(/\s+/g, ' ').trim();
const words = s => norm(s).split(' ').filter(w => w.length > 3);

function wfFacts(file) {
  const html = fs.readFileSync(file, 'utf8'), main = contentOf(html);
  const grab = re => [...main.matchAll(re)].map(x => strip(x[1])).filter(Boolean);
  const headings = grab(/<h[1-4][^>]*>([\s\S]*?)<\/h[1-4]>/gi);
  const buttons  = grab(/<button[^>]*>([\s\S]*?)<\/button>/gi);
  const blocks   = [...grab(/<p[^>]*>([\s\S]*?)<\/p>/gi), ...grab(/<li[^>]*>([\s\S]*?)<\/li>/gi),
                    ...grab(/<label[^>]*>([\s\S]*?)<\/label>/gi), ...grab(/<td[^>]*>([\s\S]*?)<\/td>/gi),
                    ...grab(/<span[^>]*>([\s\S]*?)<\/span>/gi),
                    ...grab(/<div class="muted"[^>]*>([\s\S]*?)<\/div>/gi)];
  const classes = new Set();
  for (const x of main.matchAll(/class="([^"]+)"/g))
    x[1].split(/\s+/).forEach(c => { if (c && !/^(wf-|ann|crosscheck|alert-ic|x-btn|req)/.test(c)) classes.add(c); });
  return { headings, buttons, blocks: blocks.filter(b => b.length > 12), classes: [...classes] };
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
  const popup = /Layout:\s*[^,)\n]*Popup/i.test(mdl);
  const chromeSet = new Set(popup ? ['dialog', 'dialog-head', 'dialog-body', 'dialog-foot'] : []);
  const intrinsic = new Set(/\btextbox\b/i.test(mdl) ? ['label', 'input'] : []);
  const scoredCls = wf.classes.filter(x => !chromeSet.has(x));
  const cMiss = scoredCls.filter(x => !cls.has(x) && !intrinsic.has(x));
  const c = { n: scoredCls.length, ok: scoredCls.length - cMiss.length, miss: cMiss,
              chrome: wf.classes.filter(x => chromeSet.has(x)) };
  const parts = [[h, .25], [b, .30], [k, .25], [c, .20]];
  let num = 0, den = 0;
  for (const [d, w] of parts) if (d.n) { num += w * (d.ok / d.n); den += w; }
  return { pct: den ? Math.round(100 * num / den) : null, h, b, k, c };
}

const wf = wfFacts(WF);
const mdl = pageMdl();
if (!mdl.trim()) { console.error('page-fidelity: no declaration of page "' + PAGE + '" found in input'); process.exit(2); }
const s = score(wf, mdl);
console.log(PAGE + '  fidelity ' + s.pct + '%   headings ' + s.h.ok + '/' + s.h.n +
  '  actions ' + s.b.ok + '/' + s.b.n + '  content ' + s.k.ok + '/' + s.k.n + '  classes ' + s.c.ok + '/' + s.c.n);
const miss = [...s.h.miss.map(x => 'heading: ' + x), ...s.b.miss.map(x => 'action:  ' + x),
              ...s.k.miss.map(x => 'content: ' + x.slice(0, 78)),
              ...(s.c.miss.length ? ['classes: ' + s.c.miss.join(' ')] : [])];
if (miss.length) console.log('  missed:\n  ' + miss.join('\n  '));
if (s.c.chrome.length) console.log('  chrome (layout-supplied, not scored): ' + s.c.chrome.join(' '));
