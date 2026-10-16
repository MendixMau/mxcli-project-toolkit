#!/usr/bin/env node
// process-map.js: draw the Stage-3 process map. One swimlane map per business process,
// each step showing the wireframe it happens on, what the system does between screens, and
// every open question and assumption pinned to the step or screen it is about.
//
// WHY. A reviewer at Stage 3 gets sixty consolidated questions, thirty ASSUMED decisions and
// forty wireframes as three separate lists. A business owner reading "Should a rejected order go
// back to draft?" cannot tell where in the work that happens, so the question is answered blind or
// not at all. The map puts the three side by side: the process across screens, and each
// question stuck to the moment it changes. Field origin: a requirements-driven rebuild POC,
// 2026-10-16, where the reviewer said exactly this about the question list.
//
// SINGLE SOURCE. The map is GENERATED, never hand-edited, like blueprint.html:
//   design/process-model.json   authored by the architect agent from the BRDs
//                               (skills/process-map.md Step 2)
//   <anchors file>              written by `anchor` (derived) plus the agent's judged pass
//                               (skills/process-map.md Step 3)
//   BRDs, wireframes, PROJECT.md, optional consolidated questions file: read-only inputs
// Producers of the inputs: BRDs = Stage 2 (mandatory); wireframes = design-artifacts.md Step 3
// (Stage 3, mandatory); PROJECT.md = bin/init-project.sh + every checkpoint.
//
// Usage (run from the project root, or pass --project):
//   process-map.js validate [--strict]   check the model (and anchors, when present)
//   process-map.js anchor                derive anchors mechanically, keep judged ones, write
//                                          the anchors file, list what is still unanchored
//   process-map.js build                 validate, then write design/process-map.html
//   options: --project <root>  --model <file>  --out <file>  --json (anchor: todo as JSON)
//
// Exit: 0 ok; 1 validation errors (or unanchored items left: always for anchor, with --strict for validate); 2 usage/input error.
// No libraries, no network, deterministic output (same input, same bytes).
'use strict';
const fs = require('fs');
const path = require('path');

const die = msg => { console.error('process-map: ' + msg); process.exit(2); };

// ---------- args ----------
const argv = process.argv.slice(2);
let cmd = null, root = '.', modelArg = null, outArg = null, strict = false, asJson = false;
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--project') root = argv[++i];
  else if (a === '--model') modelArg = argv[++i];
  else if (a === '--out') outArg = argv[++i];
  else if (a === '--strict') strict = true;
  else if (a === '--json') asJson = true;
  else if (a === '-h' || a === '--help') {
    console.log('usage: process-map.js validate|anchor|build [--project <root>] [--model <file>] [--out <file>] [--strict] [--json]');
    process.exit(0);
  } else if (a.startsWith('-')) die('unknown option ' + a);
  else if (!cmd) cmd = a;
  else die('unexpected argument ' + a);
}
if (!['validate', 'anchor', 'build'].includes(cmd || '')) die('give a command: validate, anchor or build');
root = path.resolve(root);
const rel = p => path.resolve(root, p);
const modelFile = modelArg ? path.resolve(modelArg) : rel('design/process-model.json');
if (!fs.existsSync(modelFile)) die('no process model at ' + modelFile + ' (skills/process-map.md Step 2 authors it)');

const readJson = (f, what) => {
  try { return JSON.parse(fs.readFileSync(f, 'utf8')); }
  catch (e) { die('cannot parse ' + (what || f) + ': ' + e.message); }
};
const byteSort = (a, b) => (a < b ? -1 : a > b ? 1 : 0);
const model = readJson(modelFile, 'process model');
const designDir = path.dirname(modelFile);

// ---------- inputs ----------
function globDir(dir, re) {
  try { return fs.readdirSync(dir).filter(f => re.test(f)).sort(byteSort).map(f => path.join(dir, f)); }
  catch (e) { return []; }
}
function brdFiles() {
  if (Array.isArray(model.brdDirs) && model.brdDirs.length) {
    return model.brdDirs.flatMap(d => globDir(rel(d), /\.brd\.json$/));
  }
  // Same three shapes as bin/lib/discover-brds.sh and the artifact manifest.
  let out = [];
  for (const a of globDir(rel('analysis'), /./)) {
    out = out.concat(globDir(path.join(a, 'knowledge-base', 'brd'), /\.brd\.json$/));
  }
  out = out.concat(globDir(rel('knowledge-base/brd'), /\.brd\.json$/));
  return [...new Set(out)];
}

const BRDS = {};        // brdId -> { file, base, doc }
const UC = {};          // "F001:UC001" -> { brd, id, title, actors, text }
const OQ = {};          // "F001:Q01" -> { brd, id, oq, text }
const BRD_PAGES = {};   // short page name -> [brdId]
for (const f of brdFiles()) {
  const doc = readJson(f);
  const base = path.basename(f);
  const id = String(doc.id || (base.match(/^[A-Za-z]+\d+/) || [base])[0]);
  BRDS[id] = { file: f, base, doc };
  for (const u of doc.useCases || []) {
    UC[id + ':' + u.id] = { brd: id, id: u.id, title: u.title || '', actors: u.actors || [], json: JSON.stringify(u), raw: u };
  }
  for (const q of doc.openQuestions || []) {
    if (!q || !q.id) continue;
    OQ[id + ':' + q.id] = { brd: id, base, id: q.id, raw: q };
  }
  for (const p of doc.pages || []) {
    if (!p || !p.name) continue;
    (BRD_PAGES[p.name] = BRD_PAGES[p.name] || []).push(id);
  }
}
const brdByFile = {};
for (const [id, b] of Object.entries(BRDS)) brdByFile[b.base] = id;

// Wireframes: page key is data-mx-page ("Module.Page") when present, else the filename stem.
const wfDir = model.wireframes ? rel(model.wireframes) : path.join(designDir, 'wireframes');
const WF = {};          // pageKey -> { key, short, file, route, html }
const WF_SHORT = {};    // short name -> key
const kebab = name => name.replace(/\.html$/i, '')
  .replace(/([a-z0-9])([A-Z])/g, '$1-$2').replace(/([A-Z]+)([A-Z][a-z])/g, '$1-$2')
  .replace(/[_\s]+/g, '-').replace(/[^A-Za-z0-9.\/-]/g, '-').replace(/-+/g, '-')
  .replace(/^-|-$/g, '').toLowerCase();
const attr = (tag, name) => { const m = (tag || '').match(new RegExp('\\b' + name + '\\s*=\\s*["\']([^"\']*)["\']', 'i')); return m ? m[1] : ''; };
for (const f of globDir(wfDir, /\.html$/i)) {
  const html = fs.readFileSync(f, 'utf8');
  const bodyTag = (html.match(/<body\b[^>]*>/i) || [''])[0];
  const htmlTag = (html.match(/<html\b[^>]*>/i) || [''])[0];
  const stem = path.basename(f).replace(/\.html$/i, '');
  const key = attr(bodyTag, 'data-mx-page') || attr(htmlTag, 'data-mx-page') || stem;
  const short = key.includes('.') ? key.split('.').pop() : key;
  const route = attr(bodyTag, 'data-route') || attr(htmlTag, 'data-route') || kebab(path.basename(f));
  WF[key] = { key, short, file: path.relative(designDir, f).split(path.sep).join('/'), route, html };
  WF_SHORT[short] = key;
  WF_SHORT[stem] = WF_SHORT[stem] || key;
}
const resolvePage = p => (!p ? null : WF[p] ? p : WF_SHORT[p] ? WF_SHORT[p] : WF_SHORT[String(p).split('.').pop()] || null);
const shortOf = p => String(p || '').split('.').pop();

// ---------- model checks ----------
const errors = [], warnings = [];
const err = m => errors.push(m), warn = m => warnings.push(m);
const LANE_KINDS = ['role', 'system', 'scheduled', 'external'];
const STEP_KINDS = ['task', 'system', 'decision', 'end'];
const lanes = Array.isArray(model.lanes) ? model.lanes : [];
// Pass 1 (Stage 2 close) has no wireframes at all: a step may name a screen that is not drawn yet,
// or no screen, and renders as a labelled card without a thumbnail. Pass 2 is strict again.
const PASS1 = Object.keys(WF).length === 0;
const processes = Array.isArray(model.processes) ? model.processes : [];
if (!lanes.length) err('model has no lanes');
if (!processes.length) err('model has no processes');
const laneIdx = {};
lanes.forEach((l, i) => {
  if (!l.id) return err('lane ' + i + ' has no id');
  if (laneIdx[l.id] !== undefined) err('lane id ' + l.id + ' is used twice');
  laneIdx[l.id] = i;
  if (l.kind && !LANE_KINDS.includes(l.kind)) err('lane ' + l.id + ': kind "' + l.kind + '" is not one of ' + LANE_KINDS.join(', '));
});
const normUc = r => String(r || '').trim().replace(/\s+/, ':');
const STEP = {};        // stepId -> { step, proc }
const ucToSteps = {};   // ucRef -> [stepId]
const pageToSteps = {}; // pageKey -> [stepId]
const actionToSteps = {};
const procSeen = {};
for (const p of processes) {
  if (!p.id) { err('a process has no id'); continue; }
  if (procSeen[p.id]) err('process id ' + p.id + ' is used twice');
  procSeen[p.id] = true;
  if (!Array.isArray(p.steps) || !p.steps.length) { err(p.id + ': no steps'); continue; }
  let col = -1;
  const cells = {};
  for (const s of p.steps) {
    if (!s.id) { err(p.id + ': a step has no id'); continue; }
    if (STEP[s.id]) err('step id ' + s.id + ' is used twice');
    STEP[s.id] = { step: s, proc: p };
    // A person step is a task even before it has a screen (pass 1 has no wireframes); only a step
    // in a system, scheduled or external lane, or with an explicit kind, is automatic.
    const laneKind = (lanes[laneIdx[s.lane]] || {}).kind || 'role';
    s.kind = s.kind || (s.page || laneKind === 'role' ? 'task' : 'system');
    if (!STEP_KINDS.includes(s.kind)) err(s.id + ': kind "' + s.kind + '" is not one of ' + STEP_KINDS.join(', '));
    if (laneIdx[s.lane] === undefined) err(s.id + ': lane "' + s.lane + '" is not declared in lanes');
    col = Number.isInteger(s.col) ? s.col : col + 1;
    s._col = col;
    const cell = s.lane + '@' + col;
    if (cells[cell]) err(s.id + ': shares lane ' + s.lane + ' column ' + col + ' with ' + cells[cell] + ' (give one a different col)');
    cells[cell] = s.id;
    if (s.page) {
      const k = resolvePage(s.page);
      if (k) { s._page = k; (pageToSteps[k] = pageToSteps[k] || []).push(s.id); }
      else if (PASS1) { s._pageMissing = true; }
      else if (s.wireframeMissing) { s._pageMissing = true; warn(s.id + ': page ' + s.page + ' has no wireframe (' + s.wireframeMissing + ')'); }
      else err(s.id + ': page "' + s.page + '" has no wireframe in ' + path.relative(root, wfDir) + ' (no data-mx-page or filename matches; set wireframeMissing with a reason if that is intended)');
    } else if (s.kind === 'task' && !PASS1) {
      err(s.id + ': a task step needs a page (the screen the person works on); use kind "system" for automated work');
    }
    for (const r of s.useCases || []) {
      const ref = normUc(r);
      if (!UC[ref]) err(s.id + ': use case ' + r + ' is not in any BRD (expected "<brd id>:<use case id>")');
      (ucToSteps[ref] = ucToSteps[ref] || []).push(s.id);
    }
    for (const a of s.actions || []) (actionToSteps[a] = actionToSteps[a] || []).push(s.id);
  }
}
// next-links checked after every step id is known (a link may continue in another process)
for (const { step: s } of Object.values(STEP)) {
  s._next = (s.next || []).map(n => (typeof n === 'string' ? { to: n } : n));
  for (const n of s._next) if (!STEP[n.to]) err(s.id + ': next "' + n.to + '" is not a step id');
  if (s.kind === 'decision' && s._next.length < 2) err(s.id + ': a decision needs at least two outcomes in next');
}
const standalone = Array.isArray(model.standalone) ? model.standalone : [];
const standaloneSet = {};
for (const st of standalone) {
  const ref = normUc(st.useCase);
  if (!UC[ref]) err('standalone use case ' + st.useCase + ' is not in any BRD');
  if (!st.reason) err('standalone use case ' + st.useCase + ' has no reason');
  standaloneSet[ref] = st.reason || '';
}
for (const ref of Object.keys(UC).sort(byteSort)) {
  const onMap = !!ucToSteps[ref], alone = ref in standaloneSet;
  if (!onMap && !alone) err('use case ' + ref + ' (' + UC[ref].title + ') is on no process and not listed as standalone');
  if (onMap && alone) warn('use case ' + ref + ' is on a process and also listed as standalone');
}
// ignorePages: wireframes that are layout sketches, not screens; they need no step.
const ignoreSet = new Set();
for (const ig of model.ignorePages || []) {
  const k = resolvePage(ig);
  if (k) ignoreSet.add(k); else warn('ignorePages: "' + ig + '" matches no wireframe');
}
const pagesOffMap = Object.keys(WF).filter(k => !pageToSteps[k] && !ignoreSet.has(k)).sort(byteSort);
if (pagesOffMap.length) warn(pagesOffMap.length + ' wireframe(s) on no process step: ' + pagesOffMap.join(', '));

// ---------- pinnable items: questions + ASSUMED decisions ----------
const questionsFile = model.questions ? rel(model.questions) : null;
const anchorsFile = model.anchors ? rel(model.anchors) : path.join(designDir, 'question-anchors.json');
const registerFile = rel(model.register || 'PROJECT.md');
const ITEMS = [];       // { id, kind: question|decision, title, text, blocking, assumption, risk, askWho, refs:[oqKey], fingerprint }
const itemById = {};
const oqToItem = {};
const clean = s => String(s == null ? '' : s).replace(/\s+/g, ' ').trim();
const fp = s => clean(s).slice(0, 80);
function addItem(it) { if (itemById[it.id]) return; ITEMS.push(it); itemById[it.id] = it; }
if (questionsFile) {
  if (!fs.existsSync(questionsFile)) die('questions file ' + model.questions + ' named in the model does not exist');
  const qj = readJson(questionsFile, 'questions file');
  const list = Array.isArray(qj) ? qj : (qj.questions || []);
  for (const q of list) {
    const id = q.cid || q.id;
    if (!id) continue;
    const refs = [];
    for (const s of q.sources || []) {
      const b = brdByFile[s.brd] || brdByFile[path.basename(String(s.brd || ''))] || (BRDS[s.brd] ? s.brd : null);
      if (b && OQ[b + ':' + s.id]) { refs.push(b + ':' + s.id); oqToItem[b + ':' + s.id] = id; }
    }
    addItem({ id, kind: 'question', title: clean(q.title) || clean(q.question).slice(0, 80), text: clean(q.question),
      blocking: q.blocking === true, assumption: clean(q.assumption), risk: clean(q.risk), askWho: clean(q.askWho),
      category: clean(q.category), refs, fingerprint: fp(q.question) });
  }
}
for (const key of Object.keys(OQ).sort(byteSort)) {
  if (oqToItem[key]) continue;
  const q = OQ[key].raw;
  if (q.consolidatedId && itemById[q.consolidatedId]) { oqToItem[key] = q.consolidatedId; itemById[q.consolidatedId].refs.push(key); continue; }
  addItem({ id: key, kind: 'question', title: clean(q.question).slice(0, 80), text: clean(q.question), blocking: q.blocking === true,
    assumption: clean(q.assumption), risk: clean(q.risk), askWho: clean(q.askWho), category: BRDS[OQ[key].brd].doc.title || '',
    refs: [key], fingerprint: fp(q.question) });
  oqToItem[key] = key;
}
// ASSUMED decisions: rows of any register table whose header has Decision and Status columns.
if (fs.existsSync(registerFile)) {
  const lines = fs.readFileSync(registerFile, 'utf8').split(/\r?\n/);
  let hdr = null; const ord = {};
  const cellsOf = l => l.trim().replace(/^\|/, '').replace(/\|$/, '').split('|').map(c => c.trim());
  for (const l of lines) {
    if (!/^\s*\|/.test(l)) { hdr = null; continue; }
    const c = cellsOf(l);
    if (!hdr) {
      const lc = c.map(x => x.toLowerCase());
      const di = lc.findIndex(x => /^decision/.test(x)), si = lc.findIndex(x => /^status/.test(x));
      hdr = (di >= 0 && si >= 0) ? { di, si, st: lc.findIndex(x => /^stage/.test(x)) } : { skip: true };
      continue;
    }
    if (hdr.skip || /^[-:\s|]+$/.test(l.replace(/\|/g, ''))) continue;
    const status = c[hdr.si] || '', text = clean(c[hdr.di] || '');
    if (!/ASSUMED/.test(status) || !text) continue;
    const stage = hdr.st >= 0 ? clean(c[hdr.st]) : '';
    const own = text.match(/^([A-Z][A-Z0-9]*-[A-Z]*\d+)\s*:/);
    ord[stage] = (ord[stage] || 0) + 1;
    const id = own ? own[1] : 'D' + (stage || 'x') + '-' + String(ord[stage]).padStart(2, '0');
    addItem({ id, kind: 'decision', title: text.replace(/^[A-Z][A-Z0-9]*-[A-Z]*\d+\s*:\s*/, '').slice(0, 90), text, blocking: false,
      assumption: text, risk: clean((c.slice(-1)[0] || '').match(/risk:(.*)$/i) ? c.slice(-1)[0].match(/risk:(.*)$/i)[1] : ''),
      status: clean(status), stage, refs: [], fingerprint: fp(text) });
  }
}

// ---------- derive anchors (mechanical) ----------
const tok = (s, t) => new RegExp('(^|[^A-Za-z0-9_-])' + t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '($|[^A-Za-z0-9_-])').test(s);
// "a/b.ts:10-20,31; c.sql:5" -> [{f:'b.ts' path, a:10, b:20}, ...]. Only cited line numbers count.
function ranges(s) {
  const out = [];
  for (const m of String(s).matchAll(/([A-Za-z0-9_.\/\[\]-]+\.[A-Za-z]{1,5}):([0-9][0-9,\s-]*)/g)) {
    const f = m[1].replace(/^.*?(?=[^\/]+\/[^\/]+$)/, '');
    for (const part of m[2].split(',')) {
      const n = part.trim().match(/^(\d+)(?:-(\d+))?$/);
      if (n) out.push({ f, a: +n[1], b: +(n[2] || n[1]) });
    }
  }
  return out;
}
const overlaps = (xs, ys) => xs.some(x => ys.some(y => x.f === y.f && x.a <= y.b && y.a <= x.b));
const stepOrder = {}; let so = 0;
for (const p of processes) for (const s of p.steps || []) stepOrder[s.id] = so++;
function derive(it) {
  const score = {}, basis = {}, pages = new Set();
  const hit = (sid, w, why) => { if (!STEP[sid]) return; if ((score[sid] || 0) < w) { score[sid] = w; basis[sid] = why; } };
  const texts = [it.text, it.assumption, it.title];
  for (const key of it.refs) {
    const o = OQ[key];
    const q = o.raw;
    texts.push(clean(q.question), clean(q.assumption), clean(q.source), clean(q.evidence));
    // a) use cases that list this open question; c) use cases whose text names it
    for (const [ref, u] of Object.entries(UC)) {
      if (u.brd !== o.brd) continue;
      const listed = (u.raw.openQuestions || []).includes(o.id);
      if (listed || tok(u.json, o.id)) for (const sid of ucToSteps[ref] || []) hit(sid, listed ? 2 : 1, key + ' -> ' + ref + ' -> ' + sid);
    }
    // b) business rules that land in a use case and name this question
    for (const br of BRDS[o.brd].doc.businessRules || []) {
      const t = JSON.stringify(br);
      if (!tok(t, o.id)) continue;
      for (const m of String(br.landsIn || '').match(/UC[-A-Za-z0-9]+/g) || []) {
        for (const sid of ucToSteps[o.brd + ':' + m] || []) hit(sid, 1, key + ' -> ' + (br.id || 'rule') + ' -> ' + o.brd + ':' + m + ' -> ' + sid);
      }
    }
    // d) BRD pages whose text names it
    for (const pg of BRDS[o.brd].doc.pages || []) {
      if (tok(JSON.stringify(pg), o.id)) { const k = resolvePage(pg.name); if (k) pages.add(k); }
    }
    // source citations: the question and a use case cite overlapping lines of the same file
    // (migration BRDs cite "path/file.ts:10-40"); the same file alone is too common to count
    const qr = ranges([q.source, q.evidence].map(clean).join(' '));
    if (qr.length) for (const [ref, u] of Object.entries(UC)) {
      if (u.brd !== o.brd) continue;
      if (overlaps(qr, ranges(String(u.raw.source || '')))) for (const sid of ucToSteps[ref] || []) hit(sid, 1, key + ' cites the lines of ' + ref + ' -> ' + sid);
    }
    // use case ids named inside the question itself
    const own = [q.question, q.assumption, q.source, q.evidence].map(clean).join(' ');
    for (const ref of Object.keys(UC)) {
      if (UC[ref].brd === o.brd && tok(own, UC[ref].id)) for (const sid of ucToSteps[ref] || []) hit(sid, 1, key + ' names ' + ref + ' -> ' + sid);
    }
  }
  const all = texts.filter(Boolean).join(' ');
  // e) microflow names and page names in the text (most specific)
  for (const a of Object.keys(actionToSteps)) if (tok(all, a)) for (const sid of actionToSteps[a]) hit(sid, 3, 'names ' + a + ' -> ' + sid);
  // A one-word page name (Home, Login, Dashboard) is also an ordinary word or a module name, so
  // it counts only in its full Module.Page form; Order_Overview-style names count bare.
  for (const k of Object.keys(WF)) {
    const sh = WF[k].short, distinctive = /_|[a-z][A-Z]/.test(sh);
    if ((distinctive && tok(all, sh)) || (k !== sh && tok(all, k))) pages.add(k);
  }
  // f) "F002 UC005" style references (decisions and consolidated questions use them)
  for (const m of all.matchAll(/\b([A-Z]+\d{3})[ :]+(UC[-A-Za-z0-9]+)/g)) {
    for (const sid of ucToSteps[m[1] + ':' + m[2]] || []) hit(sid, 2, 'names ' + m[1] + ':' + m[2] + ' -> ' + sid);
  }
  // g) a decision that names an open question or consolidated question inherits its steps
  if (it.kind === 'decision') {
    for (const k of Object.keys(OQ)) if (tok(all, OQ[k].id) && OQ[k].id.length > 3) { const ii = itemById[oqToItem[k]]; if (ii && ii._derived) for (const t of ii._derived) if (t.type === 'step') hit(t.step, 1, 'names ' + OQ[k].id + ' -> ' + t.step); }
    for (const q of ITEMS) if (q.kind === 'question' && q.id !== it.id && /^[A-Z]+-\d+$/.test(q.id) && tok(all, q.id) && q._derived) for (const t of q._derived) if (t.type === 'step') hit(t.step, 1, 'names ' + q.id + ' -> ' + t.step);
  }
  for (const k of pages) for (const sid of pageToSteps[k] || []) hit(sid, 2, 'names screen ' + WF[k].short + ' -> ' + sid);
  // Pass 1 has no wireframes to resolve a screen name against, so a step's own `page` name stands in.
  if (PASS1) for (const { step: st } of Object.values(STEP)) {
    if (!st.page) continue;
    const sh = shortOf(st.page);
    if (tok(all, st.page) || (/_|[a-z][A-Z]/.test(sh) && tok(all, sh))) hit(st.id, 2, 'names screen ' + sh + ' -> ' + st.id);
  }
  const top = Math.max(0, ...Object.values(score));
  if (top > 0) {
    const sids = Object.keys(score).filter(s => score[s] === top).sort((a, b) => stepOrder[a] - stepOrder[b]).slice(0, 3);
    return { targets: sids.map(s => ({ type: 'step', step: s })), basis: sids.map(s => basis[s]).join('; ') };
  }
  if (pages.size) {
    const ks = [...pages].sort(byteSort).slice(0, 3);
    return { targets: ks.map(k => ({ type: 'page', page: k })), basis: 'names screen(s) ' + ks.map(shortOf).join(', ') + ' (on no step)' };
  }
  return null;
}
for (const it of ITEMS.filter(i => i.kind === 'question')) { const d = derive(it); it._derived = d ? d.targets : null; it._basis = d ? d.basis : ''; }
for (const it of ITEMS.filter(i => i.kind === 'decision')) { const d = derive(it); it._derived = d ? d.targets : null; it._basis = d ? d.basis : ''; }

// ---------- existing anchors (judged entries survive; derived are recomputed) ----------
const prev = fs.existsSync(anchorsFile) ? readJson(anchorsFile, 'anchors file') : { anchors: [] };
const prevById = {};
for (const a of prev.anchors || []) prevById[a.id] = a;
function targetOk(t) {
  if (!t || !t.type) return 'no type';
  if (t.type === 'step') return STEP[t.step] ? '' : 'step ' + t.step + ' does not exist';
  if (t.type === 'page') return resolvePage(t.page) ? '' : 'page ' + t.page + ' has no wireframe';
  if (t.type === 'global') return t.bucket ? '' : 'global target needs a bucket';
  return 'unknown target type ' + t.type;
}
const ANCH = {};       // id -> { targets, anchoredBy, basis }
const staleJudged = [];
for (const it of ITEMS) {
  const p = prevById[it.id];
  if (p && p.anchoredBy === 'judged') {
    if (p.fingerprint && p.fingerprint !== it.fingerprint) { staleJudged.push(it.id); }
    else {
      const bad = (p.targets || []).map(targetOk).filter(Boolean);
      if (bad.length) err('anchor ' + it.id + ': ' + bad.join('; '));
      else { ANCH[it.id] = { targets: p.targets, anchoredBy: 'judged', basis: p.basis || p.why || '' }; continue; }
    }
  }
  if (it._derived) ANCH[it.id] = { targets: it._derived, anchoredBy: 'derived', basis: it._basis };
}
for (const id of Object.keys(prevById)) if (!itemById[id]) warn('anchors file names ' + id + ', which is no longer a question or ASSUMED decision');
for (const id of staleJudged) warn('judged anchor ' + id + ' dropped: the item text changed since it was judged; judge it again');

const unanchored = ITEMS.filter(it => !ANCH[it.id]);
const stats = { derived: 0, judged: 0, global: 0, unanchored: unanchored.length, total: ITEMS.length };
for (const a of Object.values(ANCH)) {
  stats[a.anchoredBy]++;
  if (a.targets.every(t => t.type === 'global')) stats.global++;
}
const statLine = () => 'anchors: ' + stats.total + ' item(s), ' + stats.derived + ' derived, ' + stats.judged + ' judged, ' +
  stats.global + ' global, ' + stats.unanchored + ' unanchored';

// With --json, stdout carries only the JSON; status lines go to stderr.
const say = (...a) => (asJson ? console.error(...a) : console.log(...a));
function report() {
  for (const w of warnings) say('WARN  ' + w);
  for (const e of errors) say('ERROR ' + e);
  const ucs = Object.keys(UC).length;
  say('model: ' + processes.length + ' process(es), ' + Object.keys(STEP).length + ' step(s), ' + ucs + ' use case(s) (' +
    Object.keys(standaloneSet).length + ' standalone), ' + Object.keys(WF).length + ' wireframe(s), ' + errors.length + ' error(s), ' + warnings.length + ' warning(s)');
  say(statLine());
}

// ---------- commands ----------
if (cmd === 'validate') {
  report();
  if (unanchored.length) console.log('unanchored: ' + unanchored.map(i => i.id).join(', '));
  process.exit(errors.length || (strict && unanchored.length) ? 1 : 0);
}

if (cmd === 'anchor') {
  const out = {
    schema: 'process-anchors/1',
    note: 'Generated by process-map.js anchor. Edit only judged entries (anchoredBy "judged"); derived entries are recomputed on every run.',
    anchors: ITEMS.filter(it => ANCH[it.id]).map(it => ({
      id: it.id, kind: it.kind, anchoredBy: ANCH[it.id].anchoredBy, targets: ANCH[it.id].targets,
      basis: ANCH[it.id].basis, fingerprint: it.fingerprint,
    })),
  };
  fs.mkdirSync(path.dirname(anchorsFile), { recursive: true });
  fs.writeFileSync(anchorsFile, JSON.stringify(out, null, 2) + '\n');
  report();
  say('wrote ' + path.relative(root, anchorsFile));
  if (unanchored.length) {
    if (asJson) {
      console.log(JSON.stringify(unanchored.map(it => ({ id: it.id, kind: it.kind, anchoredBy: 'judged', targets: [], basis: '', fingerprint: it.fingerprint, text: it.text })), null, 2));
    } else {
      console.log('to judge (' + unanchored.length + '): add an entry with anchoredBy "judged" for each');
      for (const it of unanchored) console.log(it.id + '\t' + it.kind + '\t' + it.text.slice(0, 160));
    }
  }
  // exit 1 while items remain (not an error: keep judging until 0 unanchored)
  process.exit(errors.length || unanchored.length ? 1 : 0);
}

// ---------- build ----------
report();
if (errors.length) { console.error('process-map: not building, fix the model first'); process.exit(1); }
const outFile = outArg ? path.resolve(outArg) : path.join(designDir, 'process-map.html');
const protoFile = model.prototype ? rel(model.prototype) : path.join(designDir, 'prototype.html');
const protoHref = fs.existsSync(protoFile) ? path.relative(path.dirname(outFile), protoFile).split(path.sep).join('/') : '';
const dsFile = model.ds ? rel(model.ds) : path.join(designDir, 'ds.css');
const dsCss = fs.existsSync(dsFile) ? fs.readFileSync(dsFile, 'utf8') : '';

// strip <script> from wireframes: thumbnails are pictures, and sandboxed frames could not run them anyway
const usedPages = new Set(Object.keys(pageToSteps));
for (const it of ITEMS) for (const t of (ANCH[it.id] || { targets: [] }).targets) if (t.type === 'page') usedPages.add(resolvePage(t.page));
const wfOut = {};
for (const k of [...usedPages].sort(byteSort)) {
  const w = WF[k];
  wfOut[k] = { short: w.short, route: w.route, file: w.file,
    html: w.html.replace(/<script\b[\s\S]*?<\/script\s*>/gi, '').replace(/<link\b[^>]*rel\s*=\s*["']stylesheet["'][^>]*>/gi, '<!--css-->') };
}
const data = {
  app: model.app || '', title: model.title || 'Process map', protoHref,
  lanes: lanes.map(l => ({ id: l.id, label: l.label || l.id, kind: l.kind || 'role' })),
  processes: processes.map(p => ({ id: p.id, title: p.title || p.id, summary: p.summary || '', journey: p.journey || '',
    steps: p.steps.map(s => ({ id: s.id, lane: s.lane, kind: s.kind, col: s._col, title: s.title || s.id, does: s.does || '',
      page: s._page || (s.page || ''), pageMissing: s._pageMissing ? (s.wireframeMissing || true) : '', status: s.status || '',
      actions: s.actions || [], events: s.events || [], useCases: (s.useCases || []).map(normUc),
      next: s._next.map(n => ({ to: n.to, label: n.label || '' })), note: s.note || '' })) })),
  useCases: Object.fromEntries(Object.keys(UC).sort(byteSort).map(k => [k, UC[k].title])),
  standalone: standalone.map(s => ({ useCase: normUc(s.useCase), reason: s.reason || '' })),
  items: ITEMS.map(it => ({ id: it.id, kind: it.kind, title: it.title, text: it.text, blocking: it.blocking,
    assumption: it.kind === 'question' ? it.assumption : '', risk: it.risk, askWho: it.askWho || '', status: it.status || '',
    anchoredBy: ANCH[it.id] ? ANCH[it.id].anchoredBy : '', basis: ANCH[it.id] ? ANCH[it.id].basis : '',
    targets: ANCH[it.id] ? ANCH[it.id].targets.map(t => (t.type === 'page' ? { type: 'page', page: resolvePage(t.page) } : t)) : [] })),
  stats, wireframes: wfOut, pagesOffMap, ds: dsCss,
};
const json = JSON.stringify(data).replace(/</g, '\\u003c');
const tpl = fs.readFileSync(path.join(__dirname, 'process-map.template.html'), 'utf8');
const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const html = tpl
  .replace('__TITLE__', () => esc((model.app ? model.app + ' ' : '') + (model.title || 'process map')))
  .replace('"__DATA__"', () => json);
fs.mkdirSync(path.dirname(outFile), { recursive: true });
fs.writeFileSync(outFile, html);
console.log('wrote ' + path.relative(root, outFile) + ' (' + Math.round(html.length / 1024) + ' KB)');
