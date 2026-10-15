'use strict';
// named-controls.js — prove each journey's OWN claim can fail (#159)
//   node tests/e2e/named-controls.js journeys/*.control.json journeys/controls/*.control.json
//
// --positive-control proves the HARNESS can fail: it breaks generic rungs. It cannot prove the
// claim a journey exists for. A control file, named *.control.json (never *.journey.json, which
// real walks pick up), is a copy of its journey with ONE claim the app must not satisfy, plus
// "control": { "of": "J-01", "mustFail": "<check-name text>" }.
// PROVEN only when all three hold: (1) the runner exits 1; (2) every check whose name contains
// mustFail is FAIL, and there is at least one; (3) nothing else is FAIL or INVALID. Rule 3 is the
// point: a control that goes red somewhere else (a login fault, a moved landing) proves nothing
// about the named claim. The control's persona must equal the run's user (TEST_USER); a mismatch
// is a FAULT and the control does not run. Findings go to artifacts/control-<id>.json via the
// runner's --out=, never over the real walk's file. Exit 0 only when every control is PROVEN.
// Field case (card-disbursement build, 2026-09-26): a journey passed every rung and its positive
// control proved every rung, yet its claim was true by accident; this control read NOT PROVEN.
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

function judge(exitCode, results, mustFail) {
  if (exitCode !== 1) return { verdict: 'NOT PROVEN', why: `runner exited ${exitCode}, not 1` };
  const named = results.filter(r => String(r.name || '').includes(mustFail));
  if (!named.length) return { verdict: 'NOT PROVEN', why: `no check name contains "${mustFail}"` };
  const held = named.filter(r => r.verdict !== 'FAIL');
  if (held.length) return { verdict: 'NOT PROVEN', why: `named check not FAIL: ${held.map(r => `${r.name} = ${r.verdict}`).join('; ')}` };
  const other = results.filter(r => !named.includes(r) && (r.verdict === 'FAIL' || r.verdict === 'INVALID'));
  if (other.length) return { verdict: 'NOT PROVEN', why: `red elsewhere: ${other.map(r => `${r.name} = ${r.verdict}`).join('; ')}` };
  return { verdict: 'PROVEN', why: `${named.length} named check(s) FAIL, nothing else red` };
}

function runControl(file, { user, artifactsDir, runner = path.join(__dirname, 'journey-runner.js') }) {
  if (!file.endsWith('.control.json')) return { id: path.basename(file), verdict: 'FAULT', why: 'not named *.control.json; not run' };
  const j = JSON.parse(fs.readFileSync(file, 'utf8'));
  const c = j.control || {};
  if (!c.of || !c.mustFail) return { id: j.id, verdict: 'FAULT', why: 'no control.of / control.mustFail' };
  if (j.persona !== user) return { id: j.id, of: c.of, verdict: 'FAULT', why: `persona "${j.persona}" is not the run user "${user}"; not run` };
  const out = path.join(artifactsDir, `control-${j.id}.json`);
  fs.rmSync(out, { force: true });          // a stale file from an earlier run must not be read
  const r = spawnSync(process.execPath, [runner, file, `--out=${out}`], { stdio: 'inherit' });
  if (!fs.existsSync(out)) return { id: j.id, of: c.of, verdict: 'NOT PROVEN', why: `runner exited ${r.status}; wrote no findings` };
  return { id: j.id, of: c.of, ...judge(r.status, JSON.parse(fs.readFileSync(out, 'utf8')).results || [], c.mustFail) };
}

module.exports = { judge, runControl };

if (require.main === module) {
  const files = process.argv.slice(2).filter(a => !a.startsWith('--'));
  if (!files.length) { console.error('usage: node tests/e2e/named-controls.js <control.json...>'); process.exit(3); }
  const { cfg } = require(__dirname + '/config.js');
  fs.mkdirSync(cfg.artifactsDir, { recursive: true });
  const rows = files.map(f => runControl(f, { user: cfg.user, artifactsDir: cfg.artifactsDir }));
  console.log('\n=== NAMED CONTROLS ===');
  for (const r of rows) console.log(`  ${r.verdict.padEnd(10)} ${r.id}${r.of ? ` (of ${r.of})` : ''} — ${r.why}`);
  const n = rows.filter(r => r.verdict === 'PROVEN').length;
  console.log(`  ${n} of ${rows.length} named controls PROVEN`);
  process.exit(n === rows.length ? 0 : 1);
}
