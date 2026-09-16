#!/usr/bin/env node
// assemble-prototype.js: build ONE clickable prototype out of the per-screen wireframes.
//
// WHY. design-artifacts.md Step 3 produces one HTML file per screen, around twenty on a real
// project, each with its binding table. That is the right SOURCE: two agents can edit two
// screens without a merge conflict, and every check (check-page-shell.sh, page-fidelity.js)
// reads one screen at a time. It is the wrong thing to REVIEW. A stakeholder cannot click
// through a flow across twenty files, a button that goes nowhere is found only by the manual
// Step 3b walk, and a BRD reviewer reads a use case as prose instead of trying it. A recent
// project hand-built a single hash-routed prototype of all its screens and the review went
// visibly better, so this makes that page an assembled output instead of a second artifact
// somebody has to keep in step by hand.
//
// Size is not a concern and was checked: twenty screens of static HTML with the inactive ones
// hidden is well under 1 MB, and switching screens is a class toggle.
//
// Usage:
//   assemble-prototype.js [design-dir]                       default: design
//   assemble-prototype.js --wireframes <dir> --ds <css> --out <file>
//
// Input:  <design>/wireframes/*.html (+ <design>/ds.css). Output: <design>/prototype.html.
//   * each screen becomes <section data-route="<route>">; the route is the `data-route`
//     attribute on the screen's <body> (or <html>, or the first element inside <body>), else
//     the kebab-cased filename (OrderList.html -> order-list)
//   * the default route is `index`, else `home`, else the first screen by filename
//   * `href="#/route"` switches screens; `href="Other.html"` between wireframes is rewritten
//     to `href="#/<other's route>"`
//   * "Show bindings" toggles the annotation apparatus (wf-* blocks, table.bind/.bt, .anno),
//     hidden by default so the reviewer sees the screen and not the build checklist
//   * a screen index lists every route; ds.css is inlined once, not per screen
//   * a screen's id="X" is namespaced to id="<route>--X" (see namespaceIds below); a screen's
//     inline <script>'s top-level `function name(){}` is namespaced onto
//     `window.__proto['<route>'].name` and its `on*="name(...)"` handler attributes are rewritten
//     to call through that namespace (see scopeScripts below) - both because twenty screens
//     concatenated into one document is one shared global scope, ids and function names alike
//   * no libraries, no network, and DETERMINISTIC: the same input gives the same bytes (no
//     timestamps, files sorted by byte order not locale), so the output diffs cleanly in git
// Exit 0 written, 2 usage/input error (no wireframes, duplicate or malformed route).
'use strict';
const fs = require('fs');
const path = require('path');
const proto = require(path.join(__dirname, 'prototype-route.js'));

const fail = msg => { console.error('assemble-prototype: ' + msg); process.exit(2); };

const args = process.argv.slice(2);
let designDir = 'design', wfDir = null, dsFile = null, outFile = null;
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === '--wireframes') wfDir = args[++i];
  else if (a === '--ds') dsFile = args[++i];
  else if (a === '--out') outFile = args[++i];
  else if (a === '-h' || a === '--help') {
    console.log('usage: assemble-prototype.js [design-dir] [--wireframes <dir>] [--ds <css>] [--out <file>]');
    process.exit(0);
  } else if (a.startsWith('-')) fail('unknown option ' + a);
  else designDir = a;
}
wfDir = wfDir || path.join(designDir, 'wireframes');
dsFile = dsFile || path.join(designDir, 'ds.css');
outFile = outFile || path.join(designDir, 'prototype.html');

if (!fs.existsSync(wfDir)) fail('no wireframe directory at ' + wfDir + ' (design-artifacts.md Step 3)');
// Byte-order sort, not localeCompare: a locale-dependent order would make the output differ
// between two machines on identical input, which is the one thing a generated file must not do.
const files = fs.readdirSync(wfDir).filter(f => /\.html$/i.test(f)).sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
if (!files.length) fail('no *.html wireframes in ' + wfDir + ' - nothing to assemble');

const kebab = name => name.replace(/\.html$/i, '')
  .replace(/([a-z0-9])([A-Z])/g, '$1-$2')
  .replace(/([A-Z]+)([A-Z][a-z])/g, '$1-$2')
  .replace(/[_\s]+/g, '-').replace(/[^A-Za-z0-9.\/-]/g, '-')
  .replace(/-+/g, '-').replace(/^-|-$/g, '').toLowerCase();

const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const text = s => s.replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ').replace(/\s+/g, ' ').trim();

const screens = [];
for (const f of files) {
  const html = fs.readFileSync(path.join(wfDir, f), 'utf8');
  const bodyTag = (html.match(/<body\b[^>]*>/i) || [''])[0];
  const htmlTag = (html.match(/<html\b[^>]*>/i) || [''])[0];
  let body;
  if (bodyTag) {
    const start = html.indexOf(bodyTag) + bodyTag.length;
    const end = html.search(/<\/body\s*>/i);
    body = html.slice(start, end >= start ? end : html.length);
  } else {
    body = html.replace(/<!doctype[^>]*>/i, '').replace(/<head\b[\s\S]*?<\/head\s*>/i, '')
               .replace(/<\/?html\b[^>]*>/gi, '');
  }
  const firstEl = (body.match(/<[a-z][a-z0-9-]*\b[^>]*>/i) || [''])[0];
  const route = proto.attr(bodyTag, 'data-route') || proto.attr(htmlTag, 'data-route') ||
                proto.attr(firstEl, 'data-route') || kebab(f);
  if (!proto.ROUTE_RE.test(route)) fail(f + ': route "' + route + '" is not a usable route (letters, digits, . _ - /)');
  const chrome = proto.attr(bodyTag, 'data-chrome') || proto.attr(htmlTag, 'data-chrome');
  const head = (html.match(/<head\b[^>]*>([\s\S]*?)<\/head\s*>/i) || [, ''])[1];
  const headCss = [...head.matchAll(/<style\b[^>]*>([\s\S]*?)<\/style\s*>/gi)].map(x => x[1]);
  const titleTag = (head.match(/<title[^>]*>([\s\S]*?)<\/title>/i) || [, ''])[1];
  const h = body.match(/<h[12][^>]*>([\s\S]*?)<\/h[12]>/i);
  const title = text(titleTag) || (h ? text(h[1]) : '') || route;
  screens.push({ file: f, route, chrome, body, headCss, title });
}

const seen = {};
for (const s of screens) {
  if (seen[s.route]) fail('route "' + s.route + '" is claimed by both ' + seen[s.route] + ' and ' + s.file + ' - give one a distinct data-route');
  seen[s.route] = s.file;
}
const routeOfFile = {};
screens.forEach(s => { routeOfFile[s.file] = s.route; });
const def = (screens.find(s => s.route === 'index') || screens.find(s => s.route === 'home') || screens[0]).route;

// href="Other.html", "./Other.html" or "Other.html#part" between wireframes -> "#/other".
// Only names in THIS wireframe set are rewritten; any other .html link is left as drawn, and
// check-prototype-links.js has no opinion about it.
function rewriteLinks(body) {
  return body.replace(/\bhref\s*=\s*(["'])(?:\.\/)?([^"'#\/]+\.html)(?:#[^"']*)?\1/gi,
    (all, q, name) => (routeOfFile[name] ? 'href=' + q + '#/' + routeOfFile[name] + q : all));
}

// Namespace one screen's ids so twenty screens' ids cannot collide either. WHY: a 9-screen PoC,
// 2026-09-15: 6 of 9 screens shared id="copilot-modal" (a copy-pasted "global" widget); assembled
// together, ids are never scoped (only CSS is), so getElementById() always resolved to the FIRST
// screen's element in the document - the button opened screen 1's hidden modal on every other
// screen, with no console error. Ids are unique per HTML *file*, never per assembled *document*,
// so id="X" here becomes id="<route>--X", along with every same-screen reference: href="#X",
// for=, aria-controls/aria-labelledby/aria-describedby=, "#X" inside this screen's own <style>,
// and getElementById('X') / querySelector[All]('#X') string literals inside its <script>.
// href="#/route" navigation (a different namespace: routes, not element ids) is left alone.
const reEsc = v => v.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
function idsIn(body) {
  const markupOnly = body.replace(/<(style|script)\b[\s\S]*?<\/\1\s*>/gi, ' ');
  return new Set([...markupOnly.matchAll(/\bid\s*=\s*["']([^"']+)["']/gi)].map(m => m[1]));
}
function namespaceIds(body, ids, ns) {
  body = body.replace(/\bid\s*=\s*(["'])([^"']+)\1/gi, (all, q, v) => ids.has(v) ? 'id=' + q + ns(v) + q : all);
  body = body.replace(/\bhref\s*=\s*(["'])#([^\/"][^"']*)\1/gi, (all, q, v) => ids.has(v) ? 'href=' + q + '#' + ns(v) + q : all);
  body = body.replace(/\b(for|aria-controls|aria-labelledby|aria-describedby)\s*=\s*(["'])([^"']+)\2/gi,
    (all, attr, q, v) => attr + '=' + q + v.split(/\s+/).map(t => ids.has(t) ? ns(t) : t).join(' ') + q);
  return body.replace(/<script\b([^>]*)>([\s\S]*?)<\/script\s*>/gi, (all, attrs, code) => {
    code = code.replace(/\bgetElementById\s*\(\s*(["'])([^"']+)\1\s*\)/g,
      (m2, q, v) => ids.has(v) ? 'getElementById(' + q + ns(v) + q + ')' : m2);
    code = code.replace(/\b(querySelectorAll|querySelector)\s*\(\s*(["'])#([^"']+)\2\s*\)/g,
      (m2, fn, q, v) => ids.has(v) ? fn + '(' + q + '#' + ns(v) + q + ')' : m2);
    return '<script' + attrs + '>' + code + '</script>';
  });
}

// Namespace each screen's inline <script> so twenty screens' *function names* cannot collide
// either - the same disease as the id collision above but worse: two screens each declaring
// `function toggleCopilot(){...}` concatenate into one document and the SECOND declaration
// silently wins for every screen's onclick, because a plain top-level `function` is a property
// of the global object, not scoped to its <script> tag. Field-proven on the same 9-screen PoC as
// the id fix, 2026-09-16: 6 screens each declared their own `toggleCopilot`/`toggleKebab`, and
// clicking the button on any screen but the last-in-document one opened or closed nothing (no
// console error - it silently ran the LAST screen's version against ITS OWN, hidden, elements).
// Each inline script (no `src=`) is wrapped in an IIFE and every top-level `function name(...)`
// found in it is exported onto `window.__proto['<route>'].name` from inside that IIFE; every
// `on<event>="name(...)"` handler attribute anywhere on the screen that calls one of those names
// is rewritten to call through the namespace instead, so screen B's button reaches screen B's
// function even though screen A's declaration of the same name executed earlier in the document.
// LIMITS (regex-simple, same posture as the id rewrite above - documented, not silently wrong):
//  - only `function name(...) {...}` top-level declarations are recognised. A handler backed by
//    a top-level `var`/`let`/`const` function expression (`const toggleCopilot = () => {}`) is
//    NOT exported or rewritten - there is no cheap way to tell a handler-bound const from an
//    unrelated one without a real parser. Prefer `function` declarations for anything an inline
//    handler attribute calls.
//  - code that reaches its own elements via `addEventListener` (not an inline `on*=` attribute)
//    already scopes fine as-is: it runs inside that screen's own IIFE and closes over that
//    screen's own bindings, so there is nothing to rewrite there.
//  - a name is exported only from the script tag that declares it, so a bare call to another
//    <script> tag's function *from inside a script's own code* (as opposed to an `on*=`
//    attribute) is not rewritten - only known to matter if a screen splits helpers and callers
//    across two separate <script> tags, which none of this toolkit's own wireframes do.
//  - `<script src="...">` (external) is left alone.
const topLevelFunctionNames = code => {
  const names = new Set();
  const re = /^[ \t]*function\s+([A-Za-z_$][\w$]*)\s*\(/gm;
  let m;
  while ((m = re.exec(code))) names.add(m[1]);
  return names;
};
function scopeScripts(body, route) {
  const scriptRe = /<script\b([^>]*)>([\s\S]*?)<\/script\s*>/gi;
  const allNames = new Set();
  let hasInline = false;
  for (const m of body.matchAll(scriptRe)) {
    if (/\bsrc\s*=/i.test(m[1])) continue;
    hasInline = true;
    topLevelFunctionNames(m[2]).forEach(n => allNames.add(n));
  }
  if (!hasInline) return body;
  // A single-quoted literal, not JSON.stringify (double-quoted): this key lands inside HTML
  // `on*="..."` attributes that are themselves double-quoted, and a route is already validated
  // against ROUTE_RE (letters, digits, `. _ - /` only - no quote or backslash can occur in it).
  const nsKey = "'" + route + "'";
  body = body.replace(scriptRe, (all, attrs, code) => {
    if (/\bsrc\s*=/i.test(attrs)) return all;
    const names = topLevelFunctionNames(code);
    const exportsCode = [...names].map(n => 'window.__proto[' + nsKey + '].' + n + ' = ' + n + ';').join('\n');
    return '<script' + attrs + '>\n' +
      'window.__proto = window.__proto || {};\n' +
      'window.__proto[' + nsKey + '] = window.__proto[' + nsKey + '] || {};\n' +
      '(function () {\n' + code + '\n' + exportsCode + '\n})();\n' +
      '</script>';
  });
  if (allNames.size) {
    const callRe = new RegExp('\\b(' + [...allNames].map(reEsc).join('|') + ')\\s*\\(', 'g');
    body = body.replace(/(\bon[a-z]+\s*=\s*)(["'])([\s\S]*?)\2/gi, (all, prefix, q, val) => {
      const rewritten = val.replace(callRe, (mm, name) => 'window.__proto[' + nsKey + '].' + name + '(');
      return prefix + q + rewritten + q;
    });
  }
  return body;
}

function screenSection(s) {
  let body = rewriteLinks(s.body);
  const ids = idsIn(body);
  const ns = id => s.route + '--' + id;
  if (ids.size) body = namespaceIds(body, ids, ns);
  const idRef = ids.size ? new RegExp('#(' + [...ids].map(reEsc).join('|') + ')\\b', 'g') : null;
  const scopeCssIds = c => idRef ? c.replace(idRef, (all, v) => '#' + ns(v)) : c;
  const css = s.headCss.map(c => proto.scopeCss(scopeCssIds(c), s.route)).join('\n');
  // Styles drawn inside the body are scoped in place, for the same reason as head styles.
  body = body.replace(/<style\b([^>]*)>([\s\S]*?)<\/style\s*>/gi,
    (all, attrs, c) => '<style data-proto-screen-css' + attrs + '>' + proto.scopeCss(scopeCssIds(c), s.route) + '</style>');
  body = scopeScripts(body, s.route);
  return '<section data-route="' + esc(s.route) + '" data-source="' + esc(s.file) + '" data-title="' + esc(s.title) + '"' +
    (s.chrome ? ' data-chrome="' + esc(s.chrome) + '"' : '') + '>\n' +
    (css.trim() ? '<style data-proto-screen-css>' + css + '</style>\n' : '') +
    body + '\n' + proto.endMarker(s.route) + '\n</section>\n';
}

let ds = '';
if (fs.existsSync(dsFile)) ds = fs.readFileSync(dsFile, 'utf8');
else console.error('assemble-prototype: no design system at ' + dsFile + ' - assembling without it (design-artifacts.md Step 1)');

// The annotation vocabulary is the one page-fidelity.js already treats as not-page-content:
// any wf-* block, the binding tables, and the .anno family. wf-screen / wf-shell / wf-wrap are
// the exception, because in some projects' wireframes they ARE the screen (page-fidelity.js
// uses them as the content boundary), and hiding them would hide the page.
const CHROME_CSS = `
#proto-screens > section[data-route]:not(.proto-active){display:none}
body:not(.proto-show-bindings) #proto-screens :is([class^="wf-"],[class*=" wf-"]):not(.wf-screen):not(.wf-shell):not(.wf-wrap),
body:not(.proto-show-bindings) #proto-screens :is(table.bind,table.bt,.anno,.annot,.anno-wrap,.rail-note){display:none!important}
#proto-bar{position:fixed;top:8px;right:8px;z-index:2147483000;font:12px/1.4 system-ui,sans-serif;background:#fff;color:#222;border:1px solid #ccc;border-radius:6px;padding:4px 8px;box-shadow:0 2px 8px rgba(0,0,0,.15);max-width:320px}
#proto-bar summary{cursor:pointer}
#proto-bar ol{margin:6px 0 4px;padding-left:18px;max-height:60vh;overflow:auto}
#proto-bar a{color:#0645ad}
#proto-bar code{color:#666}
#proto-bar label{display:block;margin-top:4px}
#proto-missing{background:#fff3cd;color:#5c4400;padding:6px 10px;font:13px system-ui,sans-serif}
`;

const SCRIPT = `
(function () {
  var def = document.body.getAttribute('data-default-route');
  var secs = document.querySelectorAll('#proto-screens > section[data-route]');
  var missing = document.getElementById('proto-missing');
  function show() {
    var h = location.hash, want = h.indexOf('#/') === 0 ? decodeURIComponent(h.slice(2)) : '';
    var r = def, i;
    for (i = 0; i < secs.length; i++) if (secs[i].getAttribute('data-route') === want) r = want;
    missing.hidden = !want || r === want;
    missing.textContent = 'No screen at #/' + want + ' - showing #/' + def;
    for (i = 0; i < secs.length; i++) {
      var on = secs[i].getAttribute('data-route') === r;
      secs[i].classList.toggle('proto-active', on);
      if (on) document.title = secs[i].getAttribute('data-title') + ' - prototype';
    }
    window.scrollTo(0, 0);
  }
  window.addEventListener('hashchange', show);
  show();
  var cb = document.getElementById('proto-bindings');
  cb.addEventListener('change', function () { document.body.classList.toggle('proto-show-bindings', cb.checked); });
})();
`;

const index = screens.map(s => '<li><a href="#/' + esc(s.route) + '">' + esc(s.title) + '</a> <code>#/' + esc(s.route) + '</code></li>').join('\n');

const out = '<!doctype html>\n' +
  '<!-- prototype.html: GENERATED by assemble-prototype.js from ' + screens.length + ' wireframe(s). Do not edit;\n' +
  '     edit design/wireframes/<Screen>.html and re-run. Each <section data-route> is one screen. -->\n' +
  '<html lang="en"><head>\n<meta charset="utf-8">\n<meta name="viewport" content="width=device-width, initial-scale=1">\n' +
  '<title>Prototype</title>\n' +
  (ds ? '<style data-proto-ds>\n' + ds + '\n</style>\n' : '') +
  '<style data-proto-chrome>' + CHROME_CSS + '</style>\n' +
  '</head>\n<body data-default-route="' + esc(def) + '">\n' +
  '<nav id="proto-bar"><details><summary>Screens (' + screens.length + ')</summary><ol>\n' + index + '\n</ol></details>\n' +
  '<label><input type="checkbox" id="proto-bindings"> Show bindings</label></nav>\n' +
  '<div id="proto-missing" hidden></div>\n' +
  '<div id="proto-screens">\n' + screens.map(screenSection).join('') + '</div>\n' +
  '<script>' + SCRIPT + '</script>\n</body></html>\n';

fs.mkdirSync(path.dirname(path.resolve(outFile)), { recursive: true });
fs.writeFileSync(outFile, out);
console.log('assemble-prototype: ' + screens.length + ' screen(s) -> ' + outFile + ' (default route #/' + def + ', ' +
  Math.round(Buffer.byteLength(out) / 1024) + ' KB)');
