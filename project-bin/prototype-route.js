#!/usr/bin/env node
// prototype-route.js: the ONE reader and writer of design/prototype.html's section format.
//
// WHY ONE FILE. The clickable prototype (assemble-prototype.js) is an ASSEMBLED OUTPUT: every
// design/wireframes/<Screen>.html becomes one <section data-route> in a single page. Three
// tools then need to read a screen back out of it: page-fidelity.js (node), check-page-shell.sh
// (bash, which calls this file) and check-prototype-links.js. Two parsers of one format drift the
// first time the format changes, and the failure is silent: a scorer that extracts one byte
// more or less than the assembler wrote scores a different page. So the writer's conventions
// (scoped screen CSS, the end marker) and the reader that undoes them live side by side here.
//
// THE CONTRACT the extractor keeps: `standalone(prototype, route)` returns a document that every
// wireframe check reads exactly as it reads the per-screen source file. The only transforms the
// assembler applies to a screen are (1) its CSS is scoped under the section so twenty screens'
// `main{...}` rules cannot fight, and (2) `href="Other.html"` becomes `href="#/other"`. (1) is
// undone here; (2) is invisible to every check (none of them reads an href). The wave2 fixture
// test-prototype-route.sh pins "same screen, same score, as a file and as a route".
//
// Usage (CLI, for shell callers):
//   prototype-route.js <prototype.html>#/<route>     print that screen as a standalone document
//   prototype-route.js --list <prototype.html>       print every route, one per line
// Exit 0 ok, 2 usage/input error (missing file, unknown route; the message names known routes).
'use strict';
const fs = require('fs');

const ROUTE_RE = /^[A-Za-z0-9][A-Za-z0-9._\/-]*$/;
const endMarker = route => '<!-- proto-end:' + route + ' -->';
const scopePrefix = route => 'section[data-route="' + route + '"]';

// `design/prototype.html#/order-list` -> { file, route }. Anything without `#/` is a plain path.
function parseRef(ref) {
  const i = String(ref).indexOf('#/');
  if (i < 0) return null;
  return { file: ref.slice(0, i), route: ref.slice(i + 2) };
}

// ---- CSS scoping (written by the assembler, undone by the extractor) --------------------

// Find the brace matching the `{` at `open`. Comments are already stripped by the caller.
function matchBrace(css, open) {
  let depth = 0;
  for (let i = open; i < css.length; i++) {
    if (css[i] === '{') depth++;
    else if (css[i] === '}') { depth--; if (depth === 0) return i; }
  }
  return css.length - 1;
}

function scopeSelector(sel, prefix) {
  const m = sel.match(/^(\s*)([\s\S]*?)(\s*)$/);
  let core = m[2];
  if (!core) return sel;
  core = core.replace(/^html\s+body\b/, 'body');
  // A screen's `body`/`html`/`:root` rule targets the screen itself, which is now the section.
  if (/^(html|body|:root)(?=$|[\s.#\[:>+~])/.test(core)) core = core.replace(/^(html|body|:root)/, prefix);
  else core = prefix + ' ' + core;
  return m[1] + core + m[3];
}

// Split a selector list on top-level commas (a comma inside :is(...) is not a separator).
function splitSelectors(s) {
  const out = []; let depth = 0, cur = '';
  for (const c of s) {
    if (c === '(') depth++;
    else if (c === ')') depth--;
    if (c === ',' && depth === 0) { out.push(cur); cur = ''; } else cur += c;
  }
  out.push(cur);
  return out;
}

// Prefix every style rule's selectors with the section selector. Conditional group rules
// (@media, @supports, @container, @layer) are recursed into; @keyframes, @font-face and @page
// are copied untouched because their "selectors" are not selectors.
function scopeCss(css, route) {
  const prefix = scopePrefix(route);
  css = css.replace(/\/\*[\s\S]*?\*\//g, '');
  let out = '', i = 0;
  while (i < css.length) {
    const open = css.indexOf('{', i);
    if (open < 0) { out += css.slice(i); break; }
    let head = css.slice(i, open);
    // Statement at-rules (`@import x;`) and stray `}` before the next block pass through.
    const cut = Math.max(head.lastIndexOf(';'), head.lastIndexOf('}'));
    if (cut >= 0) { out += head.slice(0, cut + 1); head = head.slice(cut + 1); }
    const close = matchBrace(css, open);
    const body = css.slice(open + 1, close);
    const at = head.trim();
    if (/^@(media|supports|container|layer)\b/i.test(at)) {
      out += head + '{' + scopeCss(body, route) + '}';
    } else if (at.startsWith('@')) {
      out += head + '{' + body + '}';
    } else {
      out += splitSelectors(head).map(s => scopeSelector(s, prefix)).join(',') + '{' + body + '}';
    }
    i = close + 1;
  }
  return out;
}

function unscopeCss(css, route) {
  const prefix = scopePrefix(route);
  return css.split(prefix + ' ').join('').split(prefix).join('body');
}

// ---- reading sections back ---------------------------------------------------------------

const attr = (tag, name) => {
  const m = tag.match(new RegExp('\\s' + name + '\\s*=\\s*("([^"]*)"|\'([^\']*)\')', 'i'));
  return m ? (m[2] !== undefined ? m[2] : m[3]) : null;
};

// Every screen section, in document order. The assembler's end marker bounds a section
// exactly; a hand-built prototype without markers falls back to balanced <section> counting,
// so a wireframe that uses <section> internally still bounds correctly there too.
function sections(html) {
  const out = [];
  const openRe = /<section\b[^>]*\bdata-route\s*=\s*["'][^"']*["'][^>]*>/gi;
  let m;
  while ((m = openRe.exec(html))) {
    const tag = m[0];
    const route = attr(tag, 'data-route');
    const start = m.index + tag.length;
    let end = html.indexOf(endMarker(route), start);
    let resume;
    if (end >= 0) {
      resume = end + endMarker(route).length;
    } else {
      const re = /<section\b|<\/section\s*>/gi;
      re.lastIndex = start;
      let depth = 1, t;
      end = html.length;
      while ((t = re.exec(html))) {
        depth += t[0][1] === '/' ? -1 : 1;
        if (depth === 0) { end = t.index; break; }
      }
      resume = end;
    }
    out.push({ route, tag, inner: html.slice(start, end),
               source: attr(tag, 'data-source'), title: attr(tag, 'data-title'),
               chrome: attr(tag, 'data-chrome') });
    openRe.lastIndex = resume;
  }
  return out;
}

function defaultRoute(html) {
  const m = html.match(/<body\b[^>]*>/i);
  const d = m && attr(m[0], 'data-default-route');
  if (d) return d;
  const s = sections(html);
  return s.length ? s[0].route : null;
}

// One screen as a standalone document: its scoped CSS unscoped into <head>, its content in
// <body>. Returns null for an unknown route.
function standalone(html, route) {
  const sec = sections(html).find(s => s.route === route);
  if (!sec) return null;
  const styles = [];
  const inner = sec.inner.replace(/<style\b[^>]*\bdata-proto-screen-css\b[^>]*>([\s\S]*?)<\/style>/gi,
    (all, css) => { styles.push(unscopeCss(css, route)); return ''; });
  return '<!doctype html>\n<html><head>\n' +
    styles.map(s => '<style>' + s + '</style>\n').join('') +
    '</head><body>' + inner + '</body></html>\n';
}

function unknownRouteMessage(file, route, html) {
  const known = sections(html).map(s => '#/' + s.route);
  return 'no route "#/' + route + '" in ' + file + '; known routes: ' +
    (known.length ? known.join(' ') : '(none: not an assembled prototype)');
}

module.exports = { ROUTE_RE, endMarker, scopePrefix, parseRef, scopeCss, unscopeCss, sections,
                   defaultRoute, standalone, unknownRouteMessage, attr };

if (require.main === module) {
  const args = process.argv.slice(2);
  const fail = msg => { console.error('prototype-route: ' + msg); process.exit(2); };
  if (args[0] === '--list' && args[1]) {
    if (!fs.existsSync(args[1])) fail('no such file: ' + args[1]);
    for (const s of sections(fs.readFileSync(args[1], 'utf8'))) console.log(s.route);
    process.exit(0);
  }
  const ref = args.length === 1 ? parseRef(args[0]) : null;
  if (!ref) fail('usage: prototype-route.js <prototype.html>#/<route> | --list <prototype.html>');
  if (!fs.existsSync(ref.file)) fail('no such file: ' + ref.file);
  const html = fs.readFileSync(ref.file, 'utf8');
  const doc = standalone(html, ref.route);
  if (doc === null) fail(unknownRouteMessage(ref.file, ref.route, html));
  process.stdout.write(doc);
}
