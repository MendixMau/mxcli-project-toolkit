// Control for E2E-9 / E5b-11: the PATCHED journey engine (run_journeys.py --patch-engine) judges its data rung and
// records each step's effect through UPG_PSQL, never through `mxcli oql --direct`, and an unmeasured database is
// INVALID, never PASS. No browser, no Postgres: a fake Playwright page and a psql stand-in on SQLite.
//   node pgdata_effect_control.js <patched engine dir> <sqlitepsql.py> <shop.sql> <tmp dir>
// Cases (each on a fresh copy of the database):
//   pass         the page's "save" writes the run's own Shop.Item row -> +1 PASS, own-row check PASS,
//                effect {Shop.Base: +1, Shop.Item: +1} (Item specialises Base: two tables, both counted)
//   catch        the save writes nothing (T2-1) -> +1 FAIL, own-row FAIL, effect {} (measured: nothing changed)
//   unreachable  UPG_PSQL answers "connection refused" -> both checks INVALID, effect invalid with that reason
//   unset        no UPG_PSQL at all -> data INVALID, effect invalid "UPG_PSQL is unset" (mxcli is never asked)
// Exit 0 = pass.
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const [eng0, fake, initSql, tmp] = process.argv.slice(2).map(a => path.resolve(a));
if (!tmp) { console.error('usage: node pgdata_effect_control.js <engine> <sqlitepsql.py> <shop.sql> <tmp>'); process.exit(2); }

// A copy of the engine whose runner also exports runJourney and its result arrays (a test-only change to the copy)
const eng = path.join(tmp, 'engine');
fs.mkdirSync(eng, { recursive: true });
for (const f of fs.readdirSync(eng0)) if (/\.(js|py)$/.test(f)) fs.copyFileSync(path.join(eng0, f), path.join(eng, f));
const jr = path.join(eng, 'journey-runner.js');
const src = fs.readFileSync(jr, 'utf8');
if (!src.includes('  runExitCode,\n};')) { console.log('FAIL engine: journey-runner.js exports not found'); process.exit(1); }
fs.writeFileSync(jr, src.replace('  runExitCode,\n};', '  runExitCode, runJourney, results, walks,\n};'));
fs.writeFileSync(path.join(eng, 'project.config.js'), `module.exports = {
  root: ${JSON.stringify(tmp)}, mpr: null, mxcli: 'false', dsCss: null, defaultPort: '1', otelService: 'x',
  readySelectors: ['.mx-page'], NAV: {}, TARGETS: { 'full-app': [] },
  credentials: () => ({ user: 'u', pass: 'p', fallbackUser: '', fallbackPass: '' }),
};\n`);
process.env.APP_PORT = '1';
process.env.SETTLE_MS = '1';
process.env.SETTLE_STUCK_MS = '1';
const R = require(jr);

const RUN = '0101';
const journey = {
  id: 'J-create', title: 'create and save', steps: [{
    name: 'save',
    actions: [{ do: 'wait', ms: 7, settleMs: 0 }],   // ms 7 = the fake page's "the user pressed Save"
    data: { creates: 'Shop.Item', delta: 1, scope: { newRowsBy: 'id' },
            oql: [{ label: "the run's own row", sql: `SELECT COUNT(*) AS n FROM Shop.Item WHERE Name = 'U-${RUN}'`, expect: 1 }] },
  }],
};

let db;
const sqlite = sql => execFileSync('python3', [fake, db], { input: sql, encoding: 'utf8' });
const page = writes => ({
  waitForTimeout: async ms => {
    if (ms === 7 && writes)
      sqlite(`INSERT INTO "shop$base" VALUES (3, 'C3', NULL); INSERT INTO "shop$item" VALUES (3, 'U-${RUN}', 1, NULL)`);
    await new Promise(r => setTimeout(r, 1));
  },
  waitForLoadState: async () => {}, evaluate: async () => ({ busy: [], size: 1 }),
  screenshot: async () => {}, title: async () => 't', url: () => 'http://fake/',
  locator: () => ({ first: () => ({ isVisible: async () => true, innerText: async () => '' }), innerText: async () => '' }),
});

let fail = 0;
const check = (name, ok, detail) => { if (!ok) fail++; console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}: ${detail}`); };

async function run(name, env, writes) {
  db = path.join(tmp, `${name}.db`);
  fs.rmSync(db, { force: true });
  execFileSync('python3', [fake, db, '--init', initSql]);
  for (const k of ['UPG_PSQL', 'UPG_PGMAP', 'UPG_PGDATA_DOWN']) delete process.env[k];
  Object.assign(process.env, env(db));
  const from = R.results.length;
  await R.runJourney(page(writes), journey);
  const rows = R.results.slice(from).filter(r => r.rung === 'data');
  const v = label => (rows.find(r => r.name.includes(label)) || { verdict: 'MISSING' }).verdict;
  const w = R.walks[R.walks.length - 1];
  return { delta: v('save: Shop.Item'), own: v("own row"), effect: w.steps[0].effect, rows };
}

(async () => {
  const psql = d => `python3 ${fake} ${d}`;
  const show = r => JSON.stringify({ delta: r.delta, own: r.own, effect: r.effect });
  let r = await run('pass', d => ({ UPG_PSQL: psql(d) }), true);
  check('save writes the own row -> data PASS, effect Base +1 Item +1',
        r.delta === 'PASS' && r.own === 'PASS' && r.effect && r.effect.changed
        && JSON.stringify(r.effect.changed) === JSON.stringify({ 'Shop.Base': 1, 'Shop.Item': 1 }), show(r));
  r = await run('catch', d => ({ UPG_PSQL: psql(d) }), false);
  check('save writes nothing (T2-1) -> data FAIL, effect {} measured',
        r.delta === 'FAIL' && r.own === 'FAIL' && r.effect && r.effect.changed
        && Object.keys(r.effect.changed).length === 0, show(r));
  r = await run('unreachable', () => ({ UPG_PSQL: "sh -c 'echo connection refused >&2; exit 2'" }), true);
  check('database unreachable -> data INVALID, effect invalid (never PASS, never {})',
        r.delta === 'INVALID' && r.effect && /connection refused/.test(r.effect.invalid || '')
        && !r.rows.some(x => x.verdict === 'PASS'), show(r));
  r = await run('unset', () => ({}), true);
  check('UPG_PSQL unset -> data INVALID, effect invalid with the reason',
        r.delta === 'INVALID' && r.effect && /UPG_PSQL is unset/.test(r.effect.invalid || '')
        && !r.rows.some(x => x.verdict === 'PASS'), show(r));
  process.exit(fail ? 1 : 0);
})();
