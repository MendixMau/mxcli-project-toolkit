// pgdata.js: the journey engine's data instrument on PostgreSQL (E2E-9, E5b-11). Copied into the engine copy by
// run_journeys.py, with pgmap.py beside it; helpers.js oql() and journey-runner.js call it through PATCHES.
// Why: the engine's seeds, data, association and outcome rungs ask OQL through `mxcli oql --direct`, which a
// runapp/m2ee runtime does not answer (E5b-11), so every data check was INVALID and create-save was judged by its
// screen alone (T2-1: a save that wrote nothing). Every run has the app's Postgres; UPG_PSQL is how to reach it, e.g.
//   UPG_PSQL="docker exec -i mig-pg psql -U mendix -d opc_after_<run>"
// oql(sql)  OQL -> SQL through pgmap.py (names from mendixsystem$*, never guessed) -> { rows } or null.
//           null (never zero, never []) when UPG_PSQL is unset, the database does not answer or the query is not
//           translated: the engine reports the rung INVALID, the reason goes to stderr and to UPG_PGDATA_LOG.
// snap()    { "<Entity or Association>": rows } of every mapped table, or null with the reason (lastError()).
// effect(a, b)  what one journey step did to the database: { changed: { key: +n / -n } } (only keys that moved), or
//           { invalid: reason } when either count is missing: an effect that was not measured is never "nothing".
// Env: UPG_PSQL, UPG_PGMAP (the checked map run_journeys.py wrote), UPG_PYTHON (python3), UPG_PGMAP_PY (pgmap.py here),
//      UPG_PGDATA_LOG (append reasons there), UPG_PGDATA_DOWN (a reason: the preflight found no database, ask nothing).
'use strict';
const { execFileSync } = require('child_process');
const fs = require('fs');

const PY = process.env.UPG_PYTHON || 'python3';
const PGMAP = process.env.UPG_PGMAP_PY || (__dirname + '/pgmap.py');
let last = '';

function why(msg) {
  last = String(msg).trim().split('\n').slice(-3).join(' ').slice(0, 400);
  console.error(`  pgdata: ${last}`);
  if (process.env.UPG_PGDATA_LOG) {
    try { fs.appendFileSync(process.env.UPG_PGDATA_LOG, last + '\n'); } catch (e) { /* the stderr line stays */ }
  }
}

function pgmap(args) {
  if (process.env.UPG_PGDATA_DOWN) {   // run_journeys.py's preflight already found the database silent: say why, once per ask
    why(process.env.UPG_PGDATA_DOWN);
    return null;
  }
  if (!process.env.UPG_PSQL) {
    why('UPG_PSQL is unset: no database to ask (E5b-11: mxcli oql --direct does not answer on a runapp runtime)');
    return null;
  }
  try {
    return execFileSync(PY, [PGMAP, ...args], { encoding: 'utf8', timeout: 120000, stdio: ['ignore', 'pipe', 'pipe'] });
  } catch (e) {
    why(`${args[0]}${args[1] ? ' ' + JSON.stringify(args[1]).slice(0, 160) : ''}: ` +
        `${(e.stderr || '').trim() || e.message}`);
    return null;
  }
}

function oql(sql) {
  const out = pgmap(['query', sql]);
  if (out === null) return null;
  // SQL NULL becomes undefined: oqlScalar() then answers null ("nothing"), never the text "null"
  const rows = out.split('\n').filter(Boolean).map(l => JSON.parse(l).map(v => (v === null ? undefined : v)));
  return { rows };
}

function snap() {
  const out = pgmap(['counts']);
  if (out === null) return null;
  try { return JSON.parse(out); } catch (e) { why(`counts: not JSON: ${out.slice(0, 120)}`); return null; }
}

function effect(a, b) {
  if (!a || !b) return { invalid: `row counts not read ${!a ? 'before' : 'after'} the step: ${last || 'no reason given'}` };
  const changed = {};
  for (const k of new Set([...Object.keys(a), ...Object.keys(b)])) {
    const d = (b[k] || 0) - (a[k] || 0);
    if (d) changed[k] = d;
  }
  return { changed };
}

module.exports = { oql, snap, effect, lastError: () => last };
