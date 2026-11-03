#!/usr/bin/env node
// look-shots.js — which journey screenshots show which owed page (producer of shots.tsv).
//
//   node look-shots.js --root <project> --widgets widgets.tsv --pages pages.tsv --out shots.tsv <findings.json>...
//
// Called by `bin/look-ledger.sh shots` (which does the mxcli reads and writes the two TSV inputs;
// Node never spawns mxcli, so there is no .exe/.cmd probe to get wrong on Windows).
//   widgets.tsv   Module.Page <TAB> widgetName          one row per widget of each page (DESCRIBE PAGE)
//   pages.tsv     Module.Page <TAB> url                 SHOW PAGES' url column ("" when the page has none)
//   shots.tsv     epoch iso Module.Page image-path image-mtime journey step   (written, replaced whole)
//   --prev <shots.tsv>  rows of an earlier run are carried over while their image is still on disk
//                 with the same mtime: one findings slot is written per run, so a second persona's
//                 run would otherwise erase the first persona's pages.
//
// THE RULE. A journey step is evidence for page P only if all of: the step REACHED (its ui.ready
// selector appeared, journey-runner's own PASS), its screenshot is on disk and >= 10 KB (the
// PROOF-OF-LOOK size floor), and P is the ONE page whose widget set holds every `.mx-name-X` the
// step landed on. Several pages sharing the widget -> the shot's URL path must pick one of them
// (a page's Url pattern, `{Param}` = one segment); still not exactly one -> the shot is not
// claimed for any page. When unsure, do not claim: an unclaimed page is listed as UNREACHED and
// gets a gap-fill journey or a page-audit pass, which is a visible cost; a wrong claim is a LOOK
// that never happened.
// Seeing the shot is still the reviewer's job: look_status counts a page SEEN only after the
// Read hook recorded that image being opened (look-ledger.sh).
'use strict';
const fs = require('fs'), path = require('path');
const argv = process.argv.slice(2);
const opt = {}; const files = [];
for (let i = 0; i < argv.length; i++) {
  if (/^--(root|widgets|pages|out|prev)$/.test(argv[i])) opt[argv[i].slice(2)] = argv[++i]; else files.push(argv[i]);
}
const tsv = f => { try { return fs.readFileSync(f, 'utf8').split(/\r?\n/).filter(Boolean).map(l => l.split('\t')); } catch (e) { return []; } };
const widgets = {};   // page -> Set
for (const [p, w] of tsv(opt.widgets)) (widgets[p] ||= new Set()).add(w);
const urls = {};
for (const [p, u] of tsv(opt.pages)) if (u) urls[p] = u.trim();
const urlMatches = (page, shotUrl) => {
  const pat = urls[page]; if (!pat) return false;
  let pathname; try { pathname = new URL(shotUrl).pathname; } catch (e) { return false; }
  const re = new RegExp('(^|/)' + pat.replace(/^\/+/, '').split('/').map(s =>
    /^\{.*\}$/.test(s) ? '[^/]+' : s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('/') + '/?$');
  return re.test(pathname);
};
const rows = new Map();
for (const fp of files) {
  let j; try { j = JSON.parse(fs.readFileSync(fp, 'utf8')); } catch (e) { continue; }
  for (const w of j.walks || []) for (const st of w.steps || []) {
    if (!st.reached || !st.shot || !st.shot.file) continue;
    const toks = [...String((st.expects || {}).landsOn || '').matchAll(/\.mx-name-([A-Za-z0-9_]+)/g)].map(m => m[1]);
    if (!toks.length) continue;
    let img = path.isAbsolute(st.shot.file) ? st.shot.file : path.resolve(opt.root || '.', st.shot.file);
    if (!fs.existsSync(img)) img = path.join(path.dirname(path.resolve(fp)), path.basename(st.shot.file));
    let sz = 0; try { sz = fs.statSync(img).size; } catch (e) { continue; }
    if (sz < 10240) continue;
    let cand = Object.keys(widgets).filter(p => toks.every(t => widgets[p].has(t)));
    if (cand.length > 1) cand = cand.filter(p => urlMatches(p, st.shot.url || ''));
    if (cand.length !== 1) continue;
    const mt = Math.floor(fs.statSync(img).mtimeMs / 1000);
    rows.set(cand[0] + '\t' + img, [cand[0], img.replace(/\\/g, '/'), mt, w.journey || '', st.n || ''].join('\t'));
  }
}
// carry-over: an earlier run's attribution survives while its image is still the same file
const prevRows = [];
for (const r of tsv(opt.prev)) {
  if (r.length < 7) continue;
  let mt = -1; try { mt = Math.floor(fs.statSync(r[3]).mtimeMs / 1000); } catch (e) { /* image gone: dropped */ }
  if (mt === Number(r[4]) && !rows.has(r[2] + '\t' + r[3])) prevRows.push(r);
}
const now = new Date();
const out = [...rows.values()].sort().map(r => { const [p, img, mt, jn, n] = r.split('\t');
  return [Math.floor(now / 1000), now.toISOString().replace(/\.\d+Z$/, 'Z'), p, img, mt, jn, n].join('\t'); })
  .concat(prevRows.map(r => r.join('\t')));
fs.writeFileSync(opt.out, out.length ? out.join('\n') + '\n' : '');
console.log(out.length + ' journey screenshot(s) attributed to ' + new Set(out.map(r => r.split('\t')[2])).size + ' page(s)');
