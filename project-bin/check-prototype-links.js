#!/usr/bin/env node
// check-prototype-links.js: the mechanical half of design-artifacts.md Step 3b, on the clickable
// prototype that assemble-prototype.js writes.
//
// WHY. Step 3b asks a person to walk every wireframe and make a call on every control that has
// nothing behind it. The judgement half (cut it, or spec it) stays with the person. The
// mechanical half does not need one, and it is the half that gets skipped: a link to a screen
// that was renamed, a screen nothing links to any more, a button with no binding row and no
// recorded cut. On twenty separate files none of that is visible; in one assembled page every
// route and every control is in one document, so it can be counted.
//
// Static parse, deliberately NO Playwright: the project may not have it installed, and nothing
// here needs a rendered page. Links and attributes are in the markup.
//
// Failures (exit 1):
//   dead-link  an href="#/x" whose route no screen has
//   orphan     a screen no OTHER screen links to (the default route is exempt: it is where the
//              prototype opens)
//   unbound    a <button>, <a> or <input type="submit"> with neither data-bind naming a row of
//              its screen's table.bind nor data-cut="<reason>". A link whose href is a live
//              #/route is bound by that href. data-bind naming a row that does not exist is also
//              unbound: a stale binding is how a renamed row turns into a control nobody built.
// Warnings (exit unaffected):
//   unbound-warning  the same, on a screen that has NO table.bind at all. Wireframes drawn before
//              the data-bind convention have no rows to name, and failing every one of them
//              would get this check switched off on exactly the projects that predate it.
//
// Output: one line per finding, `route<TAB>kind<TAB>detail`, then a summary line.
//
// Usage:
//   check-prototype-links.js [design/prototype.html]
// Exit 0 clean, 1 failures, 2 usage/input error (missing file, no screens: NOT a pass).
'use strict';
const fs = require('fs');
const path = require('path');
const proto = require(path.join(__dirname, 'prototype-route.js'));

const fail2 = msg => { console.error('check-prototype-links: ' + msg); process.exit(2); };

const args = process.argv.slice(2);
let file = 'design/prototype.html';
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === '-h' || a === '--help') { console.log('usage: check-prototype-links.js [prototype.html]'); process.exit(0); }
  else if (a.startsWith('-')) fail2('unknown option ' + a);
  else file = a;
}
if (!fs.existsSync(file)) fail2('no prototype at ' + file + ' (run assemble-prototype.js, design-artifacts.md Step 3)');
const html = fs.readFileSync(file, 'utf8');
const secs = proto.sections(html);
if (!secs.length) fail2(file + ' has no <section data-route> screens - inspected nothing, NOT a pass');

const routes = new Set(secs.map(s => s.route));
const def = proto.defaultRoute(html);
const text = s => s.replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/\s+/g, ' ').trim();
const key = s => text(s).toLowerCase();

// Binding tables are annotation, and a control drawn inside one is documentation of a control,
// not a control. Tables do not nest in this apparatus, so the first </table> closes it.
const BIND_TABLE = /<table\b[^>]*class\s*=\s*["'][^"']*\b(?:bind|bt)\b[^"']*["'][^>]*>[\s\S]*?<\/table\s*>/gi;

function bindRowKeys(inner) {
  const keys = new Set();
  let tables = 0;
  for (const t of inner.matchAll(BIND_TABLE)) {
    tables++;
    for (const tr of t[0].matchAll(/<tr\b([^>]*)>([\s\S]*?)<\/tr\s*>/gi)) {
      if (/<th\b/i.test(tr[2])) continue;
      const id = proto.attr('<tr' + tr[1] + '>', 'id');
      const dr = proto.attr('<tr' + tr[1] + '>', 'data-row');
      const first = tr[2].match(/<td\b[^>]*>([\s\S]*?)<\/td\s*>/i);
      [id, dr, first && first[1]].forEach(v => { if (v && key(v)) keys.add(key(v)); });
    }
  }
  return { tables, keys };
}

const findings = [];
const add = (route, kind, detail) => findings.push([route, kind, detail]);
const inbound = new Map([...routes].map(r => [r, 0]));
let links = 0, controls = 0;

for (const s of secs) {
  const inner = s.inner.replace(/<(style|script)\b[\s\S]*?<\/\1\s*>/gi, ' ');
  const { tables, keys } = bindRowKeys(inner);
  const body = inner.replace(BIND_TABLE, ' ');

  for (const m of body.matchAll(/\bhref\s*=\s*["']#\/([^"']*)["']/gi)) {
    const target = decodeURIComponent(m[1]);
    if (!target) continue;
    links++;
    if (!routes.has(target)) add(s.route, 'dead-link', '#/' + target);
    else if (target !== s.route) inbound.set(target, inbound.get(target) + 1);
  }

  const ctrlRe = /<(button|a)\b([^>]*)>([\s\S]*?)<\/\1\s*>|<input\b([^>]*\btype\s*=\s*["']submit["'][^>]*)>/gi;
  for (const m of body.matchAll(ctrlRe)) {
    controls++;
    const tag = m[1] ? '<' + m[1] + m[2] + '>' : '<input' + m[4] + '>';
    const label = (m[1] ? text(m[3]) : proto.attr(tag, 'value') || 'submit').slice(0, 50) || '<' + (m[1] || 'input') + '>';
    const cut = proto.attr(tag, 'data-cut');
    if (cut !== null && cut.trim()) continue;
    const href = m[1] && m[1].toLowerCase() === 'a' ? proto.attr(tag, 'href') : null;
    if (href && href.indexOf('#/') === 0) continue;            // live or dead, the link check owns it
    const bind = proto.attr(tag, 'data-bind');
    if (bind !== null && bind.trim()) {
      if (keys.has(key(bind))) continue;
      add(s.route, 'unbound', label + ': data-bind="' + bind + '" names no row of this screen\'s table.bind');
      continue;
    }
    if (tables) add(s.route, 'unbound', label + ': no data-bind and no data-cut');
    else add(s.route, 'unbound-warning', label + ': no data-bind and no data-cut (screen has no table.bind)');
  }
}

for (const [r, n] of inbound) if (n === 0 && r !== def) add(r, 'orphan', 'no other screen links to #/' + r);

for (const f of findings) console.log(f.join('\t'));
const failures = findings.filter(f => !/-warning$/.test(f[1])).length;
const warnings = findings.length - failures;
console.log('check-prototype-links: ' + secs.length + ' screen(s), ' + links + ' route link(s), ' + controls +
  ' control(s); ' + failures + ' failure(s), ' + warnings + ' warning(s).');
process.exit(failures ? 1 : 0);
