#!/usr/bin/env node
'use strict';
// ============================================================================
// validate-journeys.js — static checks on a journey contract, with no app,
// no browser, no Jaeger and no database.
// ----------------------------------------------------------------------------
//   node examples/validate-journeys.js journeys/*.journey.json
//   node examples/validate-journeys.js --brd analysis/**/brd journeys/*.json
//   node examples/validate-journeys.js --selftest      # prove these checks can fail
//
// WHAT IT IS FOR
// journey-runner.js only discovers a malformed contract by walking the app for
// several minutes and then reporting a plausible-looking product failure. Every
// rule below encodes a way a journey can be wrong that the runner cannot tell
// apart from a defect: a placeholder that reaches the page as the literal string
// "{{supplierCode}}", an OQL check with no bar that is recorded INVALID forever, a
// `mustNotFire` the runner never evaluates.
//
// WHAT IT IS NOT
// It cannot tell you whether a selector, entity, microflow or requirement pointer
// is correct — only whether the contract is internally consistent and shaped the
// way the runner reads it. Passing this is necessary, never sufficient.
//
// NON-VACUITY: --selftest feeds a deliberately broken journey per rule and requires
// that rule — not merely some rule — to be the one that fires. A checker that has
// never been watched going red is the thing this whole toolkit exists to retire.
// ============================================================================

const fs = require('fs');
const path = require('path');

const ACTIONS = new Set(['nav', 'click', 'fill', 'combobox', 'dismissModal', 'wait']);

// ── the rules ────────────────────────────────────────────────────────────────
// Each returns an array of problem strings. `brds` is a Map<id, object> or null.
function validate(j, brds) {
  const p = [];
  const add = (where, msg) => p.push(`${where}: ${msg}`);

  if (!j.id) add('journey', 'no `id` — findings and control mutants are named from it');
  if (!Array.isArray(j.steps) || !j.steps.length) {
    add('journey', 'no `steps[]` — nothing to walk');
    return p;
  }

  // Seeds: unique names, forward references impossible (resolved in array order).
  const seen = new Set();
  for (const [i, s] of (j.seeds || []).entries()) {
    const at = `seeds[${i}]`;
    if (!s.name) add(at, 'no `name`');
    if (!s.sql) add(at, 'no `sql`');
    if (s.name && seen.has(s.name)) add(at, `duplicate seed name "${s.name}"`);
    if (s.sql && !/\bAS\b/i.test(s.sql))
      add(at, 'SQL has no column alias — oqlScalar reads the first cell and mxcli rejects an unaliased SELECT');
    for (const k of [...String(s.sql || '').matchAll(/\{\{(\w+)\}\}/g)].map(m => m[1]))
      if (!seen.has(k)) add(at, `references {{${k}}}, which is not an EARLIER seed — seeds resolve in array order`);
    if (s.name) seen.add(s.name);
  }

  // Every {{...}} in a field the runner actually substitutes must be produced by a
  // seed. `_`-prefixed keys are stripped first: they are author comments, the runner
  // never reads them, and a note that quotes a placeholder is not a defect.
  const used = new Set();
  JSON.stringify(stripComments(j)).replace(/\{\{(\w+)\}\}/g, (_m, k) => used.add(k));
  for (const k of used)
    if (!seen.has(k)) add('journey', `{{${k}}} is used but no seed produces it — it reaches the app as a literal`);

  // Requirement pointers.
  const ptrs = [...(j.requirement || [])];
  for (const st of j.steps) ptrs.push(...(st.requirement || []));
  for (const r of ptrs) {
    if (!/^[A-Za-z]\w*#\//.test(r))
      add('requirement', `"${r}" is not <BRD id>#/<json pointer>`);
    else if (brds) {
      const [id, ptr] = r.split('#');
      if (!brds.has(id)) add('requirement', `"${r}" names BRD ${id}, which was not found in the BRD dir`);
      else if (!resolvePointer(brds.get(id), ptr)) add('requirement', `"${r}" is DANGLING — the pointer does not resolve`);
    }
  }

  const bars = [];
  for (const [i, st] of j.steps.entries()) {
    const at = `steps[${i}]${st.name ? ` "${st.name}"` : ''}`;
    if (!st.name) add(at, 'no `name` — every finding for this step is labelled "undefined:"');

    for (const [k, a] of (st.actions || []).entries()) {
      const aat = `${at}.actions[${k}]`;
      if (!ACTIONS.has(a.do)) add(aat, `unknown action "${a.do}" — the runner throws and the step is FAIL`);
      if (['click', 'fill', 'combobox'].includes(a.do) && !a.widget) add(aat, `${a.do} needs \`widget\``);
      if (a.do === 'fill' && a.value === undefined) add(aat, 'fill needs `value`');
      if (a.do === 'combobox' && a.match === undefined) add(aat, 'combobox needs `match`');
      if (a.do === 'nav' && !a.item) add(aat, 'nav needs `item` (the destination anchor title)');
      if (a.do === 'wait' && a.settleMs !== undefined && a.ms === undefined)
        add(aat, 'wait reads `ms`, not `settleMs`');
      if (a.widget && a.widget.startsWith('.'))
        add(aat, `\`widget\` takes a bare Mendix name; the runner prepends .mx-name- (got "${a.widget}")`);
    }

    const ui = st.ui || {};
    if (ui.ready !== undefined && !/^[.#[]/.test(String(ui.ready)))
      add(`${at}.ui.ready`, `"${ui.ready}" is not a CSS selector — \`ready\` is passed to page.locator() verbatim, unlike \`checks\``);
    for (const c of ui.checks || [])
      if (typeof c !== 'string' || /^[.#[]/.test(c))
        add(`${at}.ui.checks`, `"${c}" looks like a selector — \`checks\` takes bare widget names, the runner prepends .mx-name-`);
    for (const key of ['textPresent', 'textAbsent'])
      for (const t of ui[key] || [])
        if (typeof t !== 'string')
          add(`${at}.ui.${key}`, 'contains a non-string — comment objects inside these arrays become assertions');

    const sp = st.spans;
    if (sp) {
      const ordered = sp.ordered || [];
      if (!Array.isArray(ordered) || !ordered.length) {
        if ((sp.mustNotFire || []).length)
          add(`${at}.spans`, 'declares `mustNotFire` with no non-empty `ordered` — the runner evaluates the whole trace block only when `ordered` is non-empty, so this claim is NEVER checked');
        else add(`${at}.spans`, 'is present but declares nothing the runner reads');
      }
      for (const n of ordered)
        if (!String(n).includes('.'))
          add(`${at}.spans.ordered`, `"${n}" is unqualified — \`ordered\` is matched EXACTLY against mx.microflow.name, which is module-qualified (\`mustNotFire\` is a regex and may be unqualified)`);
    }

    const d = st.data;
    if (d) {
      if (d.delta !== undefined && typeof d.delta !== 'number') add(`${at}.data.delta`, 'must be a number');
      if (d.delta !== undefined && !d.creates) add(`${at}.data`, '`delta` without `creates` is never read');
      for (const [k, spec] of (d.assocMustBeSet || []).entries()) {
        const sat = `${at}.data.assocMustBeSet[${k}]`;
        if (!spec.assoc) add(sat, 'no `assoc`');
        if (!spec.target) add(sat, 'no `target` (the far-side entity, for the INNER JOIN)');
        if (!spec.entity && !d.creates) add(sat, 'no `entity` and no `data.creates` to fall back to — the query is built with "undefined" and returns INVALID');
        if (spec.mustPointAt && (!spec.mustPointAt.attr || spec.mustPointAt.value === undefined))
          add(sat, '`mustPointAt` needs both `attr` and `value`');
      }
      for (const [k, q] of (d.oql || []).entries()) {
        const qat = `${at}.data.oql[${k}]`;
        if (!q.label) add(qat, 'no `label` — the finding has no name');
        if (!q.sql) add(qat, 'no `sql`');
        bars.push([qat, q]);
      }
    }
  }

  if (j.outcome) {
    if (!j.outcome.sql) add('outcome', 'no `sql` — the runner reads `outcome.sql` and skips the rung without it');
    bars.push(['outcome', j.outcome]);
  }
  for (const [where, q] of bars)
    if (q.expect === undefined && q.atLeast === undefined)
      add(where, 'declares neither `expect` nor `atLeast` — recorded INVALID on every run, because a check that cannot go red is not a check');

  return p;
}

// Author comments live in `_`-prefixed keys, which journey-runner.js never reads.
function stripComments(v) {
  if (Array.isArray(v)) return v.map(stripComments);
  if (v && typeof v === 'object')
    return Object.fromEntries(Object.entries(v).filter(([k]) => !k.startsWith('_')).map(([k, x]) => [k, stripComments(x)]));
  return v;
}

function resolvePointer(doc, ptr) {
  let cur = doc;
  for (let tok of String(ptr).split('/').slice(1)) {
    tok = tok.replace(/~1/g, '/').replace(/~0/g, '~');
    if (Array.isArray(cur)) { const i = Number(tok); if (!Number.isInteger(i) || !(i in cur)) return false; cur = cur[i]; }
    else if (cur && typeof cur === 'object') { if (!(tok in cur)) return false; cur = cur[tok]; }
    else return false;
  }
  return true;
}

function loadBrds(dir) {
  const m = new Map();
  for (const f of fs.readdirSync(dir)) {
    if (!f.endsWith('.json')) continue;
    try {
      const d = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
      if (d && d.id) m.set(String(d.id), d);
    } catch { /* a BRD that does not parse is not this tool's finding */ }
  }
  return m;
}

// ── self-test: every rule watched going red ─────────────────────────────────
function selftest() {
  const base = () => ({
    id: 'J-T', requirement: ['F101#/useCases/0/mainFlow/0'],
    seeds: [{ name: 'a', sql: 'SELECT X AS x FROM M.E LIMIT 1' }],
    steps: [{ name: 's', actions: [{ do: 'click', widget: 'btnGo' }],
              ui: { ready: '.mx-name-dv', checks: ['btnGo'], textPresent: ['hi {{a}}'] },
              spans: { ordered: ['M.ACT_Go'], mustNotFire: ['ACT_Del'] },
              data: { creates: 'M.E', delta: 1,
                      assocMustBeSet: [{ assoc: 'M.E_F', target: 'M.F', mustPointAt: { attr: 'K', value: '{{a}}' } }],
                      oql: [{ label: 'l', sql: 'SELECT COUNT(*) AS n FROM M.E', atLeast: 1 }] } }],
    outcome: { sql: 'SELECT COUNT(*) AS n FROM M.E', atLeast: 1 },
  });
  const cases = [
    ['clean journey has no problems', j => j, null],
    ['undefined placeholder', j => { j.steps[0].ui.textPresent = ['{{nope}}']; return j; }, 'no seed produces it'],
    ['unaliased seed sql', j => { j.seeds[0].sql = 'SELECT X FROM M.E'; return j; }, 'no column alias'],
    ['forward seed reference', j => { j.seeds.unshift({ name: 'b', sql: 'SELECT Y AS y FROM M.E WHERE Z={{a}}' }); return j; }, 'not an EARLIER seed'],
    ['oql with no bar', j => { delete j.steps[0].data.oql[0].atLeast; return j; }, 'neither `expect` nor `atLeast`'],
    ['outcome with no bar', j => { delete j.outcome.atLeast; return j; }, 'neither `expect` nor `atLeast`'],
    ['outcome with no sql', j => { delete j.outcome.sql; return j; }, 'reads `outcome.sql`'],
    ['ready given a bare widget name', j => { j.steps[0].ui.ready = 'dvThing'; return j; }, 'is not a CSS selector'],
    ['checks given a selector', j => { j.steps[0].ui.checks = ['.mx-name-btnGo']; return j; }, 'looks like a selector'],
    ['mustNotFire with no ordered', j => { j.steps[0].spans = { mustNotFire: ['ACT_Del'] }; return j; }, 'NEVER checked'],
    ['unqualified ordered span', j => { j.steps[0].spans.ordered = ['ACT_Go']; return j; }, 'is unqualified'],
    ['unknown action', j => { j.steps[0].actions[0].do = 'swipe'; return j; }, 'unknown action'],
    ['wait using settleMs', j => { j.steps[0].actions = [{ do: 'wait', settleMs: 500 }]; return j; }, 'reads `ms`'],
    ['assoc with no target', j => { delete j.steps[0].data.assocMustBeSet[0].target; return j; }, 'no `target`'],
    ['step with no name', j => { delete j.steps[0].name; return j; }, 'no `name`'],
    ['comment object inside textPresent', j => { j.steps[0].ui.textPresent = [{ _note: 'x' }]; return j; }, 'non-string'],
    ['dangling requirement pointer', j => { j.requirement = ['F101#/nope/9']; return j; }, 'DANGLING'],
  ];
  const brds = new Map([['F101', { id: 'F101', useCases: [{ mainFlow: ['1. go'] }] }]]);
  let bad = 0;
  for (const [name, mutate, want] of cases) {
    const problems = validate(mutate(base()), brds);
    const ok = want === null ? problems.length === 0 : problems.some(x => x.includes(want));
    if (!ok) bad++;
    console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}${ok ? '' : `\n       got: ${problems.join('\n            ') || '(no problems reported)'}`}`);
  }
  console.log(bad ? `\n${bad} rule(s) could not be shown failing — do not trust a green from this tool.`
                  : `\n${cases.length - 1} rules each watched going red; the clean case stays green.`);
  return bad ? 1 : 0;
}

// ── main ─────────────────────────────────────────────────────────────────────
const argv = process.argv.slice(2);
if (argv.includes('--selftest')) process.exit(selftest());

let brdDir = null;
const files = [];
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === '--brd') brdDir = argv[++i];
  else if (!argv[i].startsWith('--')) files.push(argv[i]);
}
if (!files.length) {
  console.error('usage: validate-journeys.js [--brd <dir>] <journey.json...> | --selftest');
  process.exit(3);
}
const brds = brdDir ? loadBrds(brdDir) : null;
let total = 0;
for (const f of files) {
  let j;
  try { j = JSON.parse(fs.readFileSync(f, 'utf8')); }
  catch (e) { console.log(`FAIL ${f}\n  does not parse: ${e.message}`); total++; continue; }
  const problems = validate(j, brds);
  total += problems.length;
  console.log(`${problems.length ? 'FAIL' : 'ok  '} ${f}${problems.length ? '' : `  (${(j.steps || []).length} steps)`}`);
  for (const x of problems) console.log(`       ${x}`);
}
console.log(total ? `\n${total} problem(s).` : '\nAll journeys are internally consistent. This says nothing about whether their selectors, entities or microflows exist.');
process.exit(total ? 1 : 0);
