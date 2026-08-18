// journey-runner.selftest.js — proves the journey harness can FAIL.
//
//   node tests/e2e/journey-runner.selftest.js     # exit 0 = the checks are real
//
// Runs with no app, no Jaeger, no DB: it feeds synthetic spans and the real journey
// file through the same assertions the runner uses, and requires the bad inputs to
// come back red. An assertion never observed failing is not evidence, it is
// decoration — and the corpus this harness replaces is full of exactly that.
// Everything here runs with no app, no Jaeger, no DB.
const fs = require('fs');
const O = require(__dirname + '/otel.js');

let bad = 0;
const t = (name, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  if (!ok) bad++;
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}${ok ? '' : `  got=${JSON.stringify(got)} want=${JSON.stringify(want)}`}`);
};

// ---- 1. the journey file is valid, and every check declares a bar -----------
// Which journey file? Whichever this project has. This used to name one project's
// journey outright, which meant the selftest — the instrument whose entire job is to
// prove the assertions can fail — was itself unrunnable on any other project: ENOENT
// before the first check. Resolution order: JOURNEY_FILE, then the first *.journey.json
// in journeys/, then the example shipped beside the engine. The checks below are
// shape checks and hold for any valid journey.
const JOURNEY_FILE = (() => {
  if (process.env.JOURNEY_FILE) return process.env.JOURNEY_FILE;
  const dir = __dirname + '/../../journeys';
  try {
    const hit = fs.readdirSync(dir).filter(f => f.endsWith('.journey.json')).sort()[0];
    if (hit) return dir + '/' + hit;
  } catch (_) { /* no journeys/ dir — fall through to the example */ }
  return __dirname + '/example.journey.json';
})();
const j = JSON.parse(fs.readFileSync(JOURNEY_FILE, 'utf8'));
console.log(`     (journey under test: ${JOURNEY_FILE.replace(__dirname + '/', '')})`);
t('journey parses / has steps', j.steps.length > 0, true);

const bars = [];
for (const s of j.steps) for (const q of (s.data && s.data.oql) || [])
  bars.push(q.expect !== undefined || q.atLeast !== undefined);
if (j.outcome) bars.push(j.outcome.expect !== undefined || j.outcome.atLeast !== undefined);
t('every OQL check declares expect or atLeast', bars.every(Boolean) && bars.length > 0, true);
t('outcome uses .sql (the key the runner reads)', typeof j.outcome.sql === 'string', true);

// Every {{var}} used anywhere must be produced by a seed — a typo'd placeholder
// would otherwise reach the page verbatim as the literal string "{{itemCode}}".
const seedNames = new Set((j.seeds || []).map(s => s.name));
const used = new Set();
JSON.stringify(j).replace(/\{\{(\w+)\}\}/g, (m, k) => used.add(k));
t('no undefined {{placeholders}}', [...used].filter(k => !seedNames.has(k)), []);

// ---- 2. assertSequence detects reorder / skip / empty ----------------------
const mf = (name, start) => ({ start, tags: { 'mx.microflow.name': name }, logs: [] });
const seq = (spans, names) => { let r; O.assertSequence(spans, names, (_n, ok) => { r = ok; }); return r; };
const good = [mf('A', 1), mf('B', 2), mf('C', 3)];
t('correct order passes',      seq(good, ['A', 'B', 'C']), true);
t('reordered fails',           seq([mf('B', 1), mf('A', 2)], ['A', 'B']), false);
t('skipped step fails',        seq([mf('A', 1), mf('C', 2)], ['A', 'B', 'C']), false);
t('empty capture fails',       seq([], ['A']), false);
t('incidental flows tolerated', seq([mf('A', 1), mf('X', 2), mf('B', 3)], ['A', 'B']), true);

// ---- 3. assertNoErrors sees an ERROR ACTIVITY under an OK microflow --------
// The whole reason rung 2 walks activity spans: a caught error leaves the
// microflow green while the commit did nothing.
const swallowed = [
  { start: 1, op: 'mf', tags: { 'mx.microflow.name': 'FieldScan.ACT_Movement_Receive', 'otel.status_code': 'OK' }, logs: [] },
  { start: 2, op: 'act', tags: { 'mx.activity.name': 'CallRest', 'otel.status_code': 'ERROR',
                                 'otel.status_description': 'Error calling REST service\n  at FieldScan.ACT_Movement_Receive (CallRest)' }, logs: [] },
];
let errOk; O.assertNoErrors(swallowed, (_n, ok) => { errOk = ok; });
t('swallowed activity error is caught', errOk, false);

process.exit(bad ? 1 : 0);
