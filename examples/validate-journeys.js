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
// `spans` block that declares nothing the runner reads.
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

const ACTIONS = new Set(['nav', 'click', 'fill', 'combobox', 'dismissModal', 'wait', 'back', 'offline', 'online']);
// Step keys journey-runner.js reads. An unknown key close to one of these is a likely typo: the
// runner ignores it silently and walks the step without the check the author meant (#522).
const STEP_KEYS = ['name', 'requirement', 'actions', 'ui', 'spans', 'data', 'geolocation'];
function editDistance(a, b) {
  const d = Array.from({ length: a.length + 1 }, (_, i) => [i]);
  for (let j = 1; j <= b.length; j++) d[0][j] = j;
  for (let i = 1; i <= a.length; i++) for (let j = 1; j <= b.length; j++)
    d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
  return d[a.length][b.length];
}
// A GPS fix as the runner reads it (#521): literal numbers are range-checked here; a {{seed}} is
// checked by the placeholder rule and resolved by the runner.
function checkGeolocation(g, where, add) {
  if (!g || typeof g !== 'object' || Array.isArray(g)) { add(where, 'must be { "latitude", "longitude", "accuracy"? }'); return; }
  for (const [k, lo, hi, req] of [['latitude', -90, 90, true], ['longitude', -180, 180, true], ['accuracy', 0, Infinity, false]]) {
    const v = g[k];
    if (v === undefined) { if (req) add(where, `no \`${k}\` — the runner stops the journey INVALID`); continue; }
    if (typeof v === 'string' && /^\s*\{\{\w+\}\}\s*$/.test(v)) continue;
    const n = typeof v === 'string' && v.trim() ? Number(v) : v;
    if (typeof n !== 'number' || !Number.isFinite(n) || n < lo || n > hi)
      add(where, `\`${k}\` ${JSON.stringify(v)} is not a number in [${lo}, ${hi}] — the runner stops the journey INVALID`);
  }
}
const validSize = v => v && Number.isInteger(v.width) && Number.isInteger(v.height) && v.width > 0 && v.height > 0;

// ── the rules ────────────────────────────────────────────────────────────────
// Each returns an array of problem strings. `brds` is a Map<id, object> or null.
function validate(j, brds) {
  const p = [];
  const add = (where, msg) => p.push(`${where}: ${msg}`);

  if (!j.id) add('journey', 'no `id` — findings and control mutants are named from it');
  // device / viewport (#521): the runner refuses a malformed one before the browser opens.
  if (j.device !== undefined && typeof j.device !== 'string' &&
      !(j.device && typeof j.device.name === 'string' && (j.device.viewport === undefined || validSize(j.device.viewport))))
    add('journey.device', 'must be a Playwright device name, or { "name", "viewport": { "width", "height" } } in whole pixels');
  if (j.viewport !== undefined && !validSize(j.viewport))
    add('journey.viewport', 'must be { "width", "height" } in whole pixels (plus "isMobile": true for a phone)');
  if (j.geolocation !== undefined) checkGeolocation(j.geolocation, 'journey.geolocation', add);
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
      add(at, 'SQL has no column alias — oqlScalar reads the first SELECT alias and mxcli rejects an unaliased SELECT');
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
    for (const k of Object.keys(st)) {
      if (k.startsWith('_') || STEP_KEYS.includes(k)) continue;
      const near = STEP_KEYS.find(x => editDistance(k.toLowerCase(), x.toLowerCase()) <= 2);
      if (near) add(at, `unknown key \`${k}\` — likely a typo for \`${near}\`; the runner ignores it and walks the step without it`);
    }
    if (st.geolocation !== undefined) checkGeolocation(st.geolocation, `${at}.geolocation`, add);

    for (const [k, a] of (st.actions || []).entries()) {
      const aat = `${at}.actions[${k}]`;
      if (!ACTIONS.has(a.do)) add(aat, `unknown action "${a.do}" — the runner throws and the step is FAIL`);
      if (['click', 'fill', 'combobox'].includes(a.do) && !a.widget) add(aat, `${a.do} needs \`widget\``);
      if (a.do === 'fill' && a.value === undefined) add(aat, 'fill needs `value`');
      if (a.do === 'combobox' && a.match === undefined) add(aat, 'combobox needs `match`');
      if (a.do === 'nav' && !a.item) add(aat, 'nav needs `item` (the destination anchor title)');
      if (a.do === 'back' && a.timeout !== undefined && !(typeof a.timeout === 'number' && a.timeout > 0))
        add(aat, `back \`timeout\` must be a positive number of ms (got ${JSON.stringify(a.timeout)})`);
      if (a.do === 'wait' && a.settleMs !== undefined && a.ms === undefined)
        add(aat, 'wait reads `ms`, not `settleMs`');
      if (a.widget && a.widget.startsWith('.'))
        add(aat, `\`widget\` takes a bare Mendix name; the runner prepends .mx-name- (got "${a.widget}")`);
    }

    const ui = st.ui || {};
    if (ui.no5xx !== undefined && typeof ui.no5xx !== 'boolean')
      add(`${at}.ui.no5xx`, `must be true or false — the runner watches for HTTP 5xx only when it is exactly true (got ${JSON.stringify(ui.no5xx)})`);
    if (ui.ready !== undefined && !/^[.#[]/.test(String(ui.ready)))
      add(`${at}.ui.ready`, `"${ui.ready}" is not a CSS selector — \`ready\` is passed to page.locator() verbatim, unlike \`checks\``);
    for (const c of ui.checks || [])
      if (typeof c !== 'string' || /^[.#[]/.test(c))
        add(`${at}.ui.checks`, `"${c}" looks like a selector — \`checks\` takes bare widget names, the runner prepends .mx-name-`);
    for (const key of ['textPresent', 'textAbsent'])
      for (const t of ui[key] || [])
        if (typeof t !== 'string')
          add(`${at}.ui.${key}`, 'contains a non-string — comment objects inside these arrays become assertions');

    // A negative-only claim (`mustNotFire` with no `ordered`) is evaluated since #150: the
    // runner judges it once tracing is shown live — the step's `liveness` span, or any span from
    // the service since the journey began. `liveness` is read only for such a claim.
    const sp = st.spans;
    if (Array.isArray(sp)) {
      add(`${at}.spans`, 'is an array — the old shape [{ mf, status }], which the runner never read (it records it INVALID); use { "ordered": [...], "mustNotFire": [...] }');
    } else if (sp) {
      const ordered = sp.ordered || [];
      const mustNot = sp.mustNotFire || [];
      if (!Array.isArray(ordered)) add(`${at}.spans.ordered`, 'must be an array');
      if (!Array.isArray(mustNot)) add(`${at}.spans.mustNotFire`, 'must be an array');
      const hasOrdered = Array.isArray(ordered) && ordered.length > 0;
      const hasMustNot = Array.isArray(mustNot) && mustNot.length > 0;
      if (!hasOrdered && !hasMustNot)
        add(`${at}.spans`, 'is present but declares nothing the runner reads (neither `ordered` nor `mustNotFire`) — the runner records it INVALID');
      for (const n of hasMustNot ? mustNot : []) {
        try { new RegExp(n); } catch (e) { add(`${at}.spans.mustNotFire`, `"${n}" is not a valid regex — the runner compiles it with new RegExp()`); }
      }
      if (sp.liveness !== undefined) {
        if (typeof sp.liveness !== 'string' || !sp.liveness.trim())
          add(`${at}.spans.liveness`, 'must be a non-empty string: a microflow name or span operation the step is known to produce');
        else if (hasOrdered)
          add(`${at}.spans.liveness`, 'is only read for a negative-only claim (`mustNotFire` with no `ordered`) — with `ordered`, the claimed microflows are the liveness evidence');
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

// A Stage-2 folder holds a derived <id>-<slug>.mx-brd.json beside each <id>-<slug>.brd.json, with
// the same id and another shape. Pointers are written against the BRD, so the BRD wins the id; a
// derived file is read only for an id no BRD in the folder has (#520: it listed second and
// replaced the BRD, and every pointer read DANGLING).
function loadBrds(dir) {
  const m = new Map();
  const derived = (f) => f.endsWith('.mx-brd.json');
  const names = fs.readdirSync(dir).filter((f) => f.endsWith('.json'));
  let ignored = 0;
  for (const f of [...names.filter((f) => !derived(f)), ...names.filter(derived)]) {
    try {
      const d = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
      if (!d || !d.id) continue;
      if (derived(f) && m.has(String(d.id))) { ignored++; continue; }
      m.set(String(d.id), d);
    } catch { /* a BRD that does not parse is not this tool's finding */ }
  }
  if (ignored) console.error(`note: ${ignored} .mx-brd.json file(s) not read: a .brd.json in ${dir} has the same id, and pointers resolve against the BRD`);
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
    ['negative-only spans claim is accepted', j => { j.steps[0].spans = { mustNotFire: ['ACT_Del'] }; return j; }, null],
    ['negative-only claim with liveness is accepted', j => { j.steps[0].spans = { ordered: [], mustNotFire: ['ACT_Del'], liveness: 'M.DS_Page' }; return j; }, null],
    ['spans block declaring nothing', j => { j.steps[0].spans = { ordered: [] }; return j; }, 'declares nothing the runner reads'],
    ['liveness not a string', j => { j.steps[0].spans = { mustNotFire: ['ACT_Del'], liveness: 5 }; return j; }, 'must be a non-empty string'],
    ['liveness beside ordered', j => { j.steps[0].spans.liveness = 'M.DS_Page'; return j; }, 'only read for a negative-only claim'],
    ['mustNotFire not a regex', j => { j.steps[0].spans.mustNotFire = ['ACT_(Del']; return j; }, 'not a valid regex'],
    ['unqualified ordered span', j => { j.steps[0].spans.ordered = ['ACT_Go']; return j; }, 'is unqualified'],
    ['unknown action', j => { j.steps[0].actions[0].do = 'swipe'; return j; }, 'unknown action'],
    ['browser back is a known action', j => { j.steps[0].actions.push({ do: 'back' }); return j; }, null],
    ['offline / online are known actions', j => { j.steps[0].actions.push({ do: 'offline' }, { do: 'online' }); return j; }, null],
    ['phone device, step GPS fix from a seed', j => { j.device = 'iPhone 13'; j.steps[0].geolocation = { latitude: '{{a}}', longitude: 4.9, accuracy: 10 }; return j; }, null],
    ['GPS latitude out of range', j => { j.steps[0].geolocation = { latitude: 95, longitude: 4.9 }; return j; }, 'not a number in [-90, 90]'],
    ['GPS fix with no longitude', j => { j.geolocation = { latitude: 1 }; return j; }, 'no `longitude`'],
    ['device object with a bad viewport', j => { j.device = { name: 'iPhone 13', viewport: { width: '390' } }; return j; }, 'Playwright device name'],
    ['viewport not whole pixels', j => { j.viewport = { width: 390.5, height: 844, isMobile: true }; return j; }, 'whole pixels'],
    ['misspelt step key', j => { j.steps[0].spams = j.steps[0].spans; delete j.steps[0].spans; return j; }, 'likely a typo for `spans`'],
    ['back timeout not a number', j => { j.steps[0].actions.push({ do: 'back', timeout: '15s' }); return j; }, 'must be a positive number'],
    ['ui.no5xx true is accepted', j => { j.steps[0].ui.no5xx = true; return j; }, null],
    ['ui.no5xx not a boolean', j => { j.steps[0].ui.no5xx = 'yes'; return j; }, 'must be true or false'],
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
                  : `\n${cases.filter(c => c[2] !== null).length} rules each watched going red; ${cases.filter(c => c[2] === null).length} clean case(s) stay green.`);
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
