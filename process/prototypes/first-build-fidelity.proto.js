// First-build wireframe fidelity scorer — model-side, headless.
// Denominator = the wireframe's own <main> content. Chrome (header.top, nav.tabs,
// .wf-note, the binding-annotation table, .crosscheck) is excluded by construction,
// which is the thing design-audit.js declined to do at class level.
const fs = require('fs'), path = require('path');
const WF = process.argv[2], MDLDIR = process.argv[3];
const FIRST_BUILD = ['10-practice-stub-pages.mdl','12-practice-pages.mdl','13-practice-pages-batch2.mdl','45-reporting-pages.mdl'];

function mainOf(html) {
  let m = html.match(/<main[^>]*>([\s\S]*?)<\/main>/i);
  let s = m ? m[1] : html;
  s = s.replace(/<div class="wf-note"[\s\S]*?<\/div>/gi, '');   // annotation chrome
  return s;
}
const strip = s => s.replace(/<[^>]+>/g, ' ').replace(/&[a-z]+;/g,' ').replace(/\s+/g,' ').trim();
const norm  = s => s.toLowerCase().replace(/[^a-z0-9 ]+/g,' ').replace(/\s+/g,' ').trim();
const words = s => norm(s).split(' ').filter(w => w.length > 3);

function wfFacts(file) {
  const html = fs.readFileSync(file,'utf8'), main = mainOf(html);
  const grab = (re) => [...main.matchAll(re)].map(m => strip(m[1])).filter(Boolean);
  const headings = grab(/<h[1-4][^>]*>([\s\S]*?)<\/h[1-4]>/gi);
  const buttons  = grab(/<button[^>]*>([\s\S]*?)<\/button>/gi);
  // content blocks: paragraphs, muted divs, labels, list items, table cells
  const blocks   = [...grab(/<p[^>]*>([\s\S]*?)<\/p>/gi), ...grab(/<li[^>]*>([\s\S]*?)<\/li>/gi),
                    ...grab(/<label[^>]*>([\s\S]*?)<\/label>/gi), ...grab(/<td[^>]*>([\s\S]*?)<\/td>/gi),
                    ...grab(/<div class="muted"[^>]*>([\s\S]*?)<\/div>/gi)];
  // structural classes actually used inside main (content, not annotation)
  const classes = new Set();
  for (const m of main.matchAll(/class="([^"]+)"/g))
    m[1].split(/\s+/).forEach(c => { if (c && !/^(wf-|ann|crosscheck)/.test(c)) classes.add(c); });
  return { headings, buttons, blocks: blocks.filter(b => b.length > 12), classes: [...classes] };
}

function pageMdl(pageName, files) {
  let out = '';
  for (const f of files) {
    const p = path.join(MDLDIR, f);
    if (!fs.existsSync(p)) continue;
    const src = fs.readFileSync(p,'utf8');
    const re = new RegExp('(CREATE OR MODIFY PAGE|CREATE PAGE)[^\\n]*"' + pageName + '"[\\s\\S]*?\\n\\}', 'g');
    for (const m of src.matchAll(re)) out += m[0] + '\n';
  }
  return out;
}

function score(wf, mdl) {
  const corpus = norm(mdl);
  const cls = new Set();
  for (const m of mdl.matchAll(/Class:\s*'([^']+)'/g)) m[1].split(/\s+/).forEach(c=>cls.add(c));
  const hit = (txt) => { const w = words(txt); return w.length ? w.filter(x=>corpus.includes(x)).length / w.length >= 0.6 : true; };
  const dim = (arr) => ({ n: arr.length, ok: arr.filter(hit).length, miss: arr.filter(x=>!hit(x)) });
  const h = dim(wf.headings), b = dim(wf.buttons), k = dim(wf.blocks);
  const cMiss = wf.classes.filter(c => !cls.has(c));
  const c = { n: wf.classes.length, ok: wf.classes.length - cMiss.length, miss: cMiss };
  const parts = [[h,0.25],[b,0.30],[k,0.25],[c,0.20]];
  let num=0, den=0;
  for (const [d,w] of parts) if (d.n) { num += w * (d.ok/d.n); den += w; }
  return { pct: den ? Math.round(100*num/den) : null, h, b, k, c };
}

const pages = process.argv.slice(4);
console.log('page                       fidelity  headings  actions  content  classes');
console.log('-------------------------------------------------------------------------');
const rows = [];
for (const spec of pages) {
  const [pageName, wfFile] = spec.split('=');
  const wfPath = path.join(WF, wfFile + '.html');
  if (!fs.existsSync(wfPath)) { console.log(pageName.padEnd(26), 'NO WIREFRAME'); continue; }
  const wf = wfFacts(wfPath);
  const mdl = pageMdl(pageName, FIRST_BUILD);
  if (!mdl.trim()) { console.log(pageName.padEnd(26), 'NOT IN FIRST-BUILD SCRIPTS'); continue; }
  const s = score(wf, mdl);
  rows.push([pageName, s]);
  console.log(pageName.padEnd(26),
    String(s.pct + '%').padStart(6),
    ('   ' + s.h.ok + '/' + s.h.n).padStart(10),
    ('  ' + s.b.ok + '/' + s.b.n).padStart(8),
    ('  ' + s.k.ok + '/' + s.k.n).padStart(8),
    ('  ' + s.c.ok + '/' + s.c.n).padStart(8));
}
console.log('\n--- what first build missed, per page ---');
for (const [p,s] of rows) {
  const miss = [...s.h.miss.map(x=>'heading: '+x), ...s.b.miss.map(x=>'action: '+x),
                ...s.k.miss.map(x=>'content: '+x.slice(0,70)), ...(s.c.miss.length?['classes: '+s.c.miss.join(' ')]:[])];
  if (miss.length) console.log('\n' + p + ' (' + s.pct + '%)\n  ' + miss.join('\n  '));
}
