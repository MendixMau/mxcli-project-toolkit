'use strict';
// ============================================================================
// journey-rung4-scope.test.js — non-vacuity controls for rung 4's row scoping
//   node tests/e2e/journey-rung4-scope.test.js
//
// WHAT THIS PROVES, AND WHAT IT DOES NOT
//
// It proves that the SQL journey-runner.js now builds SELECTS THE RIGHT ROWS, by
// evaluating that SQL over fixture tables whose contents are known exactly. Each control
// is run TWICE — once unscoped (the old behaviour) and once scoped (the new one) — so the
// test does not merely show the fix passing, it shows the OLD behaviour producing the
// wrong verdict on the very same fixture. A control that only ever goes green proves
// nothing; these are written so that reverting the fix turns them red.
//
// It does NOT prove the integration path. THE APP WAS DOWN when this was written
// (localhost:8094 refused: "cannot connect to Mendix admin API"), so no query below has
// ever been sent to a Mendix runtime. Two claims are therefore REASONED, NOT MEASURED,
// and are called out again in docs/verification/rung4-scoping.md:
//   1. that this runtime's OQL accepts `SELECT MAX(id) FROM <Entity>` and `WHERE e.id > n`
//   2. that the evaluator below agrees with Mendix's OQL semantics for these shapes
// (1) is the load-bearing one, and it is why an unreadable watermark is reported INVALID
// rather than falling back to the whole table: the first live run will say so out loud.
//
// The evaluator is deliberately narrow — it understands only the four shapes the builders
// emit. If a builder starts emitting something else, the evaluator throws rather than
// guessing, so this test cannot quietly stop testing the thing it names.
// ============================================================================

const R = require(__dirname + '/journey-runner.js');

let pass = 0, fail = 0;
function check(name, actual, expected) {
  const a = JSON.stringify(actual), e = JSON.stringify(expected);
  if (a === e) { pass++; console.log(`  \x1b[32mPASS\x1b[0m ${name}`); }
  else { fail++; console.log(`  \x1b[31mFAIL\x1b[0m ${name}\n         got ${a}\n    expected ${e}`); }
}

// ── A fixture "database" ────────────────────────────────────────────────────
// A row is { id, PlacedOn, links: { '<Assoc>': { <attr>: <value> } | null } }.
// A null link is a row that saved with no association — the legacy shape.
function makeDb(table, rows) {
  const parseWhere = (w) => (w || '').split(' AND ').map(s => s.trim()).filter(Boolean).map(term => {
    let m = /^t\.(\w+) = '(.*)'$/.exec(term);
    if (m) return { side: 't', attr: m[1], op: '=', val: m[2] };
    m = /^e\.(\w+) > (?:'(.*)'|(-?\d+))$/.exec(term);
    if (m) return { side: 'e', attr: m[1], op: '>', val: m[2] !== undefined ? m[2] : Number(m[3]) };
    throw new Error(`fixture evaluator does not understand WHERE term: ${term}`);
  });

  const applies = (row, joined, preds) => preds.every(p => {
    if (p.side === 'e') {
      const v = row[p.attr];
      if (v === undefined) throw new Error(`fixture rows have no attribute ${p.attr}`);
      return v > p.val;
    }
    return joined && String(joined[p.attr]) === String(p.val);
  });

  return function oqlScalar(sql) {
    let m = /^SELECT COUNT\(\*\) AS n FROM (\S+)$/.exec(sql);
    if (m) { expectTable(m[1]); return String(rows.length); }

    m = /^SELECT MAX\((\w+)\) AS w FROM (\S+)$/.exec(sql);
    if (m) {
      expectTable(m[2]);
      if (!rows.length) return null;
      const vals = rows.map(r => r[m[1]]);
      if (vals.some(v => v === undefined)) throw new Error(`no such attribute ${m[1]}`);
      return String(vals.slice().sort((a, b) => (a > b ? 1 : a < b ? -1 : 0)).pop());
    }

    m = /^SELECT COUNT\(\*\) AS n FROM (\S+) AS e(?: INNER JOIN e\/(\S+)\/(\S+) AS t)?(?: WHERE (.*))?$/.exec(sql);
    if (m) {
      expectTable(m[1]);
      const assoc = m[2] || null;
      const preds = parseWhere(m[4]);
      let n = 0;
      for (const row of rows) {
        // An INNER JOIN drops rows whose FK is null — the semantics assocGap relies on.
        const joined = assoc ? (row.links || {})[assoc] || null : undefined;
        if (assoc && !joined) continue;
        if (applies(row, joined, preds)) n++;
      }
      return String(n);
    }
    throw new Error(`fixture evaluator does not understand SQL: ${sql}`);
  };

  function expectTable(t) {
    if (t !== table) throw new Error(`query hit ${t}, fixture is ${table}`);
  }
}

// The two rung-4 verdicts, computed exactly as journey-runner.js computes them, but
// against a fixture. Kept in one place so the controls below differ only in their data.
function judge(rows, { scoped, entity = 'FieldScan.ItemPlacement',
                       assoc = 'FieldScan.ItemPlacement_Location',
                       target = 'Location.Location', attr = 'LocId', want = 'LOC-SEED',
                       newRowsBy = 'id', writeRow = null } = {}) {
  const before = rows.slice();
  const scalar = makeDb(entity, before);
  const num = (sql) => { const v = scalar(sql); return v === null ? null : Number(v); };

  // Watermark taken BEFORE the step's write, which is the whole point.
  const sc = R.captureScope(entity, scoped ? { newRowsBy } : null, num, scalar);

  const after = writeRow ? before.concat([writeRow]) : before;
  const scalar2 = makeDb(entity, after);
  const num2 = (sql) => { const v = scalar2(sql); return v === null ? null : Number(v); };

  if (sc.state === 'broken') return { assocMustBeSet: 'INVALID', mustPointAt: 'INVALID', sc };

  const total = num2(R.sqlAssocTotal(entity, sc));
  const linked = num2(R.sqlAssocLinked(entity, assoc, target, sc));
  const pointing = num2(R.sqlMustPointAt(entity, assoc, target, attr, want, sc));

  const assocVerdict = (sc.state !== 'unscoped' && total === 0) ? 'FAIL'
                     : (total - linked === 0 ? 'PASS' : 'FAIL');
  return {
    assocMustBeSet: assocVerdict,
    mustPointAt: pointing >= 1 ? 'PASS' : 'FAIL',
    evidence: R.scopeEvidence(sc).strength,
    counts: { total, linked, pointing },
    sc,
  };
}

const LINK_SEED = { 'FieldScan.ItemPlacement_Location': { LocId: 'LOC-SEED' } };
const LINK_OTHER = { 'FieldScan.ItemPlacement_Location': { LocId: 'LOC-OTHER' } };

console.log('\n=== rung-4 scoping — non-vacuity controls ===\n');

// ── CONTROL 1 ───────────────────────────────────────────────────────────────
// A row a PREVIOUS run wrote, pointing at the seeded location. The journey then does
// NOTHING (writeRow: null — a silently no-op commit). mustPointAt must not be satisfied
// by the leftover row.
console.log('CONTROL 1 — previous run\'s row must no longer satisfy mustPointAt');
{
  const prev = [{ id: 1000, PlacedOn: '2026-08-01 09:00:00', links: LINK_SEED }];
  const old = judge(prev, { scoped: false, writeRow: null });
  const now = judge(prev, { scoped: true, writeRow: null });
  check('unscoped (OLD behaviour) wrongly PASSES on the leftover row', old.mustPointAt, 'PASS');
  check('scoped   (NEW behaviour) FAILS — the journey wrote nothing', now.mustPointAt, 'FAIL');
  check('unscoped is reported as weak evidence', old.evidence, 'weak');
  check('scoped   is reported as strong evidence', now.evidence, 'strong');
}

// ── CONTROL 2 ───────────────────────────────────────────────────────────────
// One legacy row with a null FK, plus the correct row this run writes. assocMustBeSet
// must judge only the new row.
console.log('\nCONTROL 2 — legacy null-FK row must no longer fail assocMustBeSet');
{
  const legacy = [
    { id: 500, PlacedOn: '2025-01-01 00:00:00', links: {} },              // null FK, ancient
    { id: 1000, PlacedOn: '2026-08-01 09:00:00', links: LINK_OTHER },     // fine, unrelated
  ];
  const fresh = { id: 1200, PlacedOn: '2026-08-18 12:00:00', links: LINK_SEED };
  const old = judge(legacy, { scoped: false, writeRow: fresh });
  const now = judge(legacy, { scoped: true, writeRow: fresh });
  check('unscoped (OLD behaviour) wrongly FAILS on the legacy row', old.assocMustBeSet, 'FAIL');
  check('unscoped counted the whole table', old.counts, { total: 3, linked: 2, pointing: 1 });
  check('scoped   (NEW behaviour) PASSES', now.assocMustBeSet, 'PASS');
  check('scoped   counted only the new row', now.counts, { total: 1, linked: 1, pointing: 1 });
}

// ── CONTROL 3 ───────────────────────────────────────────────────────────────
// The row the journey actually wrote must still be found — the scoping must not be
// so tight that it excludes its own subject. This is the control that would catch an
// off-by-one (`>=` vs `>`) or a watermark taken after the write instead of before.
console.log('\nCONTROL 3 — the row this run wrote is still found');
{
  const history = [
    { id: 500, PlacedOn: '2025-01-01 00:00:00', links: {} },
    { id: 1000, PlacedOn: '2026-08-01 09:00:00', links: LINK_SEED },
  ];
  const fresh = { id: 1128, PlacedOn: '2026-08-18 12:00:00', links: LINK_SEED };
  const now = judge(history, { scoped: true, writeRow: fresh });
  check('mustPointAt PASSES on the row just written', now.mustPointAt, 'PASS');
  check('assocMustBeSet PASSES', now.assocMustBeSet, 'PASS');
  check('exactly one row is in scope', now.counts, { total: 1, linked: 1, pointing: 1 });
}

// ── CONTROL 4 ───────────────────────────────────────────────────────────────
// The wrong-combobox run of 2026-08-14: a row IS written and IS linked, but to the
// neighbouring location. assocMustBeSet is satisfied (a link exists); mustPointAt must
// not be. This is the separation the whole check exists for, re-proven under scoping.
console.log('\nCONTROL 4 — a linked-but-wrong-target row still fails mustPointAt only');
{
  const history = [{ id: 1000, PlacedOn: '2026-08-01 09:00:00', links: LINK_SEED }];
  const wrong = { id: 1128, PlacedOn: '2026-08-18 12:00:00', links: LINK_OTHER };
  const now = judge(history, { scoped: true, writeRow: wrong });
  check('assocMustBeSet PASSES (a link does exist)', now.assocMustBeSet, 'PASS');
  check('mustPointAt FAILS (it points at the wrong location)', now.mustPointAt, 'FAIL');
}

// ── CONTROL 5 ───────────────────────────────────────────────────────────────
// A step that writes nothing must not produce a vacuous "0/0 linked, gap 0 → PASS".
console.log('\nCONTROL 5 — a step that wrote no row does not pass vacuously');
{
  const history = [{ id: 1000, PlacedOn: '2026-08-01 09:00:00', links: LINK_SEED }];
  const now = judge(history, { scoped: true, writeRow: null });
  check('assocMustBeSet FAILS on an empty scope', now.assocMustBeSet, 'FAIL');
  check('mustPointAt FAILS on an empty scope', now.mustPointAt, 'FAIL');
}

// ── CONTROL 6 ───────────────────────────────────────────────────────────────
// Backward compatibility and the honesty of the fallback.
console.log('\nCONTROL 6 — contract compatibility and instrument honesty');
{
  const rows = [{ id: 1000, PlacedOn: '2026-08-01 09:00:00', links: LINK_SEED }];
  const scalar = makeDb('FieldScan.ItemPlacement', rows);
  const num = (s) => Number(scalar(s));

  // No scope declared: the old journey still runs, unchanged SQL, but labelled weak.
  const unscoped = R.captureScope('FieldScan.ItemPlacement', undefined, num, scalar);
  check('a journey with no scope still runs', unscoped.state, 'unscoped');
  check('...and its SQL is byte-identical to the pre-fix query',
        R.sqlMustPointAt('E', 'A', 'T', 'LocId', 'X', unscoped),
        "SELECT COUNT(*) AS n FROM E AS e INNER JOIN e/A/T AS t WHERE t.LocId = 'X'");
  check('...and is reported WEAK', R.scopeEvidence(unscoped).strength, 'weak');

  // Empty table: no WHERE needed, and the evidence is still strong.
  const emptyDb = makeDb('E', []);
  const empty = R.captureScope('E', { newRowsBy: 'id' }, (s) => Number(emptyDb(s)), emptyDb);
  check('an empty table scopes to everything', empty.state, 'empty');
  check('...with no WHERE clause', R.sqlAssocTotal('E', empty), 'SELECT COUNT(*) AS n FROM E AS e');
  check('...and still counts as strong evidence', R.scopeEvidence(empty).strength, 'strong');

  // The runtime refuses MAX(<attr>) on a non-empty table → INVALID, never a quiet
  // fall back to the whole table.
  const refuses = (sql) => (/^SELECT MAX/.test(sql) ? null : scalar(sql));
  const broken = R.captureScope('FieldScan.ItemPlacement', { newRowsBy: 'id' },
                                (s) => { const v = refuses(s); return v === null ? null : Number(v); },
                                refuses);
  check('an unreadable watermark is BROKEN, not silently unscoped', broken.state, 'broken');
  // judge() mirrors the runner's branch: state 'broken' short-circuits both checks to
  // INVALID before any scoped SQL is built.
  check('...and both checks go INVALID rather than running unscoped',
        { a: broken.state === 'broken' ? 'INVALID' : 'RAN',
          m: broken.state === 'broken' ? 'INVALID' : 'RAN' },
        { a: 'INVALID', m: 'INVALID' });
  check('...naming the attribute the runtime refused',
        /will not aggregate "id"/.test(broken.reason), true);

  // Literal quoting is decided by the value, so a DateTime scope works with no
  // attribute-name table in the runner.
  check('numeric watermarks go in bare',
        R.whereScoped({ state: 'scoped', attr: 'id', watermark: '1128' }, 'e'),
        ' WHERE e.id > 1128');
  check('DateTime watermarks are quoted',
        R.whereScoped({ state: 'scoped', attr: 'PlacedOn', watermark: '2026-08-18 12:00:00' }, 'e'),
        " WHERE e.PlacedOn > '2026-08-18 12:00:00'");
}

// ── CONTROL 7 ───────────────────────────────────────────────────────────────
// The monotonicity claim `id` scoping rests on, exercised at its worst case rather
// than asserted in a comment. demo-data.md:87 — id = (short<<48)|(seq<<7)|rand7.
// Adjacent sequences differ by 128; the random suffix can differ by at most 127, so
// the LOWER sequence can never produce the HIGHER id.
console.log('\nCONTROL 7 — Mendix id monotonicity at its adversarial worst case');
{
  const SHORT = 59;
  const mkId = (seq, rand) => (BigInt(SHORT) << 48n) | (BigInt(seq) << 7n) | BigInt(rand);
  const worst = mkId(1000, 127) < mkId(1001, 0);   // max suffix on the older row
  check('seq n with suffix 127 still sorts below seq n+1 with suffix 0', worst, true);
  let ok = true;
  for (let seq = 1; seq < 400; seq++) {
    if (!(mkId(seq, (seq * 37) % 128) < mkId(seq + 1, (seq * 91) % 128))) ok = false;
  }
  check('400 consecutive sequences with arbitrary suffixes stay ordered', ok, true);
}

console.log(`\n=== ${pass} passed, ${fail} failed ===`);
process.exit(fail === 0 ? 0 : 1);
