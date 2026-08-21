'use strict';
// ============================================================================
// review-report.js — turns one bin/review-module.sh run into docs/report.json shape
// ----------------------------------------------------------------------------
// Runs standalone:
//   node tests/e2e/review-report.js --dir <run dir> --module <Module> --out <report.json>
//                                   [--root <repo>] [--stamp <iso>] [--finished <iso>]
//   node tests/e2e/review-report.js --help
//
// and is invoked by bin/review-module.sh through the equivalent environment variables,
// which remain supported as fallbacks (argv wins when both are present):
//   REVIEW_DIR  REVIEW_MODULE  REVIEW_OUT  REVIEW_ROOT  REVIEW_STAMP  REVIEW_FINISHED
//
// Exit: 0 report written · 2 could not run (missing/!bad input, unwritable --out).
// There is no exit 1: this file reports findings, it does not have findings of its own.
//
// It is the review sibling of report-normalize.js: same contract
// (docs/verification/report-schema.md), same verdict enum, much smaller input set —
// this run produced exactly three instruments' worth of artefacts and it must not
// pretend otherwise.
//
// THREE RULES IT ENFORCES, each paid for elsewhere in this repo:
//
//   1. EMIT ALWAYS. Every exit path of review-module.sh reaches this file, including
//      "the module does not exist" and "every instrument faulted". A run that wrote no
//      report is indistinguishable from a run that never happened.
//
//   2. ABSENT IS NOT GREEN. Every instrument the run declared gets an instruments[] row
//      whether or not it produced output, and an instrument that produced no rows also
//      gets a `fault` CHECK — an instruments[] row alone leaves checks[] looking clean.
//
//   3. THE JOURNEY IS A FAULT, NOT AN OMISSION. This report is model-side only. The app
//      was never contacted. That fact is carried as a `fault` check and a `fault`
//      instrument row, so no reader and no renderer can mistake it for coverage.
//
//   4. A FAULTED INSTRUMENT'S LEFTOVER OUTPUT IS NOT A MEASUREMENT. Three artefacts in
//      the run dir can outlive the instrument that was supposed to produce them — a
//      conformance.tsv sliced out of an EARLIER day's report, a graph.tsv holding an
//      error message instead of a TSV, a coverage.txt holding a stack trace. Each was
//      measured to produce a `pass` check with `provenance: measured` while the
//      instrument's own row said `fault`. Every reader of those three files below now
//      proves the file is the output of THIS run before it will emit a green row.
// ============================================================================

const fs = require('fs');
const path = require('path');
const cp = require('child_process');

// project.config.js is the only project-aware file in tests/e2e/, and it has no
// side effects at require time.
const PROJ = require('./project.config');

const SCHEMA_VERSION = '1.1';

const USAGE = [
  'review-report.js — one bin/review-module.sh run -> a schema ' + SCHEMA_VERSION + ' report.json',
  '',
  'Usage:',
  '  node tests/e2e/review-report.js --dir <run dir> --module <Module> --out <report.json>',
  '                                  [--root <repo>] [--stamp <iso>] [--finished <iso>]',
  '  node tests/e2e/review-report.js --help',
  '',
  'Options (each also accepts --flag=value):',
  '  --dir       <path>  the run directory review-module.sh wrote, holding instruments.tsv,',
  '                      conformance.tsv, graph.tsv and coverage.txt. Required.',
  '  --module    <Name>  the module this run reviewed. Required — it is the subject of every',
  '                      row, so there is no safe default.',
  '  --out       <path>  where to write report.json. Required. Parent dirs are created.',
  '  --root      <path>  repo root, for the .mpr / git / PROJECT.md provenance block.',
  '                      Default: the directory holding the .mpr (project.config).',
  '  --mpr       <name>  the .mpr filename, for the provenance block.',
  '                      Default: the single *.mpr in --root (project.config).',
  '  --display-name <s>  human-readable project name for the report header.',
  '                      Default: derived from the project directory name.',
  '  --stamp     <iso>   run start.    Default: now.',
  '  --finished  <iso>   run end.      Default: now.',
  '',
  'Environment fallbacks (argv wins): REVIEW_DIR REVIEW_MODULE REVIEW_OUT REVIEW_ROOT',
  '                                   REVIEW_STAMP REVIEW_FINISHED REVIEW_MPR',
  '                                   REVIEW_DISPLAY_NAME',
  '',
  'Exit: 0 report written · 2 could not run.',
  '',
  'A missing --dir, or a --dir with no instruments.tsv, is a FAULT and not an empty pass:',
  'this file cannot tell "the run measured nothing" from "the run never happened" without',
  'being told, so it refuses rather than emitting a report with no findings in it.',
].join('\n');

function die(msg) {
  console.error('review-report: ' + msg);
  console.error('');
  console.error(USAGE);
  process.exit(2);
}

const OPTS = { '--dir': 'dir', '--module': 'module', '--out': 'out',
               '--root': 'root', '--stamp': 'stamp', '--finished': 'finished',
               // Project identity — defaulted from project.config, never hardcoded here.
               '--mpr': 'mpr', '--display-name': 'displayName' };

function parseArgv(argv) {
  const o = {};
  for (let i = 0; i < argv.length; i++) {
    let a = argv[i], v = null;
    if (a === '-h' || a === '--help') { console.log(USAGE); process.exit(0); }
    const eq = a.indexOf('=');
    if (a.startsWith('--') && eq > 0) { v = a.slice(eq + 1); a = a.slice(0, eq); }
    if (!(a in OPTS)) die('unknown argument: ' + argv[i]);
    if (v === null) {
      v = argv[++i];
      if (v === undefined) die(a + ' needs a value');
    }
    // An empty value is a caller bug, not a request for the default. Silently defaulting
    // here is how `--module ""` becomes a report about a module named "".
    if (v === '') die(a + ' was given an empty value');
    o[OPTS[a]] = v;
  }
  return o;
}

const ARGV = parseArgv(process.argv.slice(2));

// argv, then env, then (only where a default is safe) a default.
const pick = (key, envKey) => ARGV[key] || process.env[envKey] || null;
const req = (key, envKey) => pick(key, envKey) ||
  die('--' + key + ' is not set (and ' + envKey + ' is empty)');

const DIR      = req('dir', 'REVIEW_DIR');
const MODULE   = req('module', 'REVIEW_MODULE');
const OUT      = req('out', 'REVIEW_OUT');
const ROOT     = pick('root', 'REVIEW_ROOT') || PROJ.root;
const MPR_NAME = pick('mpr', 'REVIEW_MPR') || PROJ.mprName;
const DISPLAY  = pick('displayName', 'REVIEW_DISPLAY_NAME') || PROJ.displayName;
const STARTED  = pick('stamp', 'REVIEW_STAMP') || new Date().toISOString();
const FINISHED = pick('finished', 'REVIEW_FINISHED') || new Date().toISOString();
const readIf = (p) => { try { return fs.readFileSync(p, 'utf8'); } catch (e) { return null; } };
const sh = (cmd) => { try { return cp.execSync(cmd, { cwd: ROOT, stdio: ['ignore', 'pipe', 'ignore'] })
  .toString().trim() || null; } catch (e) { return null; } };
const slug = (s) => String(s).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'x';
const num = (s) => (s == null || s === '' || isNaN(Number(s)) ? null : Number(s));

const checks = [];
const instruments = [];

/* ── instruments.tsv: name \t verdict \t rc \t elapsed \t log \t reason ───── */

// review-module.sh truncates instruments.tsv before it installs the EXIT trap, so by the
// time this file runs the file always exists — empty on the earliest fault, never absent.
// Its absence therefore means --dir does not name a review run. Refusing is the honest
// answer: every artefact below is optional, so a wrong --dir otherwise yields a
// well-formed report about a run that never happened.
const instrRaw = readIf(path.join(DIR, 'instruments.tsv'));
if (instrRaw === null) {
  die(path.join(DIR, 'instruments.tsv') + ' does not exist, so --dir does not name a ' +
      'review-module.sh run.\n  Refusing to emit a report for a run that left no trace ' +
      'of which instruments were even attempted.');
}

const instrRows = (instrRaw || '')
  .split('\n').filter(Boolean)
  .map((l) => { const f = l.split('\t'); return {
    name: f[0], verdict: f[1], rc: f[2], elapsed: f[3], log: f[4], reason: f[5] || '' }; });

const byName = new Map(instrRows.map((r) => [r.name, r]));
const ran = (n) => { const r = byName.get(n); return !!r && r.verdict !== 'fault'; };

// Fixed metadata per instrument. `canExpressFault` is the machine-readable form of
// schema rule 5: an instrument whose own dialect has no "did not run" state cannot be
// trusted to report one, and its greens are weaker evidence than another's.
const META = {
  conformance: {
    canExpressFault: true, evidenceStrength: 'strong',
    expressibleVerdicts: ['pass', 'fail', 'fault'],
    source: 'architecture/modules/' + MODULE + '/coverage-ledger.md vs ' + MPR_NAME,
  },
  'graph-sweep': {
    canExpressFault: true, evidenceStrength: 'medium',
    expressibleVerdicts: ['pass', 'fault', 'manual'],
    source: '.mxcli/catalog.db',
    note: 'wiring shape is measured; whether a given shape is a DEFECT is an intent ' +
          'question answered against the module brief, not here',
  },
  coverage: {
    canExpressFault: true, evidenceStrength: 'medium',
    expressibleVerdicts: ['pass', 'fail', 'fault'],
    source: 'BRD leaves vs coverage-ledger.md',
  },
  'journey-runner': {
    canExpressFault: true, evidenceStrength: 'strong',
    expressibleVerdicts: ['pass', 'fail', 'fault'],
    source: 'journeys/' + MODULE + '.journey.json',
  },
  // Stage 4 of module-review.md. Not an instrument this chain can ever run — a script
  // cannot look at a page — but it must appear, because an omitted dimension renders as
  // a covered one. `evidenceStrength: 'none'` is honest: there is no evidence here at all
  // until review-agent's job 2 has produced design/ui-reviews/ui-review-<date>.html.
  'ui-review': {
    canExpressFault: true, evidenceStrength: 'none',
    expressibleVerdicts: ['fault'],
    source: 'design/ui-reviews/ui-review-<date>.html (written by review-agent, not by this script)',
    note: 'the visual assessment of every page in the module against wireframe, design ' +
          'system, or module-review.md §4d\'s unaided rubric. Judgement, not measurement — ' +
          'it is performed by a reviewer looking at rendered screens, and this chain never ' +
          'performs it',
  },
};

for (const r of instrRows) {
  const e = Object.assign({ name: r.name, verdict: r.verdict }, META[r.name] || {});
  if (r.rc !== '' && r.rc != null) e.rc = num(r.rc);
  e.elapsedSec = num(r.elapsed);
  e.log = r.log || null;
  if (r.reason) e.reason = r.reason;
  instruments.push(e);
}

/* ── conformance checks ───────────────────────────────────────────────────── */

const CONF_VERDICT = {
  OK: 'pass',
  STALE: 'fail', UNDERSTATED: 'fail', 'UNKNOWN-STATUS': 'fail',
  UNRUNNABLE: 'fault', TIMEOUT: 'fault',
};
const CONF_DETAIL = {
  STALE: 'ledger claims built/partial; the model says the element is ABSENT',
  UNDERSTATED: 'ledger claims not-built; the model says the element is PRESENT',
  'UNKNOWN-STATUS': 'the stored status is not one the checker understands',
  UNRUNNABLE: 'the acceptance cell is backticked prose, not a runnable command — this row ' +
              'was NOT measured',
  TIMEOUT: 'the probe did not return; nothing was measured',
};

let conf = { checked: 0, ok: 0, stale: 0, understated: 0, unrunnable: 0, timeout: 0, unknown: 0 };
let confRows = 0;

// Rule 4. review-module.sh slices conformance.tsv out of the NEWEST docs/conformance/
// report-*.tsv, which on a timed-out or crashed conformance run is a report from an
// EARLIER day. Measured 2026-08-18 with RM_TMO_CONFORMANCE=1: conformance measured 1 of 22
// rows and reported "nothing was measured", and this file then emitted 13 `pass` checks
// with provenance `measured` and measuredAt set to today's run. The instrument's own row
// said `fault` the whole time — an instruments[] row alone does not stop checks[] reading
// green. So: if the instrument faulted, its leftover rows are not evidence.
const confFaulted = byName.has('conformance') && !ran('conformance');
const confTsv = confFaulted ? null : readIf(path.join(DIR, 'conformance.tsv'));
if (confTsv) {
  for (const line of confTsv.split('\n')) {
    const f = line.split('\t');
    if (f.length < 5 || f[0] === 'module' || !f[0]) continue;
    const [mod, ptrRaw, stored, observed, verdict] = f;
    const cmd = f[5] || null;
    confRows++;
    // Rule 4 of the schema: `requirement` is a real pointer or null, NEVER one cleaned
    // into existence. Ledger cells arrive decorated with backticks and counts.
    const ptr = String(ptrRaw || '').replace(/`/g, '').trim();
    const requirement = ptr.startsWith('/') ? ptr.split(/\s/)[0] : null;
    const v = CONF_VERDICT[verdict] || 'fault';
    conf.checked++;
    if (verdict === 'OK') conf.ok++;
    else if (verdict === 'STALE') conf.stale++;
    else if (verdict === 'UNDERSTATED') conf.understated++;
    else if (verdict === 'UNRUNNABLE') conf.unrunnable++;
    else if (verdict === 'TIMEOUT') conf.timeout++;
    else conf.unknown++;
    checks.push({
      id: 'review/conformance/' + slug(mod) + '/' + slug(ptr),
      instrument: 'conformance', kind: 'conformance', module: mod,
      journey: null, stepIndex: null, stepName: null,
      requirement,
      title: (ptr || '(no pointer)') + ' — ledger says "' + (stored || '?') + '"',
      verdict: v,
      provenance: v === 'fault' ? 'declared' : 'measured',
      notRun: v === 'fault' ? true : undefined,
      detail: 'stored=' + stored + ' observed=' + observed + ' (' + verdict + ')' +
              (CONF_DETAIL[verdict] ? ' — ' + CONF_DETAIL[verdict] : ''),
      measuredAt: STARTED,
      nonVacuity: { controlRan: false, note: 'conformance has no positive control' },
      evidence: cmd ? [{ type: 'command', command: cmd }] : [],
      blocks: [],
    });
  }
}
// Rule 2: an instrument that ran but emitted nothing must SAY so in checks[], or the
// findings table renders clean over zero measurements.
if (confRows === 0) {
  const why = byName.get('conformance') && byName.get('conformance').reason;
  checks.push(faultCheck('review/conformance/' + slug(MODULE) + '/none', 'conformance',
    'conformance', 'ledger conformance for ' + MODULE + ' was not measured',
    (why || 'the conformance instrument produced no rows for this module') +
    (confFaulted
      ? '. Any conformance.tsv in the run directory was DISCARDED: the instrument did ' +
        'not complete, so its rows are either partial or left over from an earlier run, ' +
        'and neither is a measurement of this one.'
      : '')));
}

/* ── graph sweep: wiring shape + orphans ──────────────────────────────────── */
// The SQL is measured; "is this shape a defect" is JUDGED and never blends into the
// same number (review-agent rule 4). Judged rows carry verdict `manual` — a human still
// owes the intent call — so they can never be read as either a clean pass or a finding.

const graphTsv = readIf(path.join(DIR, 'graph.tsv'));
// graph.tsv is graph-sweep's LOG file, so on any failure it holds the failure text rather
// than a TSV. Parsing it is therefore also the liveness test: no `kind` header means no
// sweep happened, whatever the instrument row says. `graphParsed` gates the ONLY green row
// this section can emit — "no orphaned microflows" — which otherwise fires on zero orphans
// found in zero lines read. Measured 2026-08-18 with a graph.tsv holding
// "No such file or directory": pass, provenance `measured`.
const graphParsed = !!graphTsv && /^kind\t/.test(graphTsv);
let wiringSeen = false, orphanCount = 0;
if (graphParsed) {
  for (const line of graphTsv.split('\n')) {
    const f = line.split('\t');
    if (f[0] === 'wiring') {
      wiringSeen = true;
      const [mod, elems] = [f[1], num(f[2])];
      const [inb, outb] = String(f[3] || '').split('|').map(num);
      const unwired = inb === 0;
      checks.push({
        id: 'review/wiring/' + slug(mod), instrument: 'graph-sweep', kind: 'conformance',
        module: mod, journey: null, stepIndex: null, stepName: null, requirement: null,
        title: mod + ' — module wiring shape',
        verdict: unwired ? 'manual' : 'pass',
        provenance: unwired ? 'judged' : 'measured',
        detail: elems + ' elements · ' + inb + ' inbound · ' + outb + ' outbound' +
          (unwired
            ? ' — NO inbound reference from any other module. This is the signature of ' +
              '"imported but never wired in". It is not automatically a defect (most ' +
              'marketplace modules are legitimately unused); resolving intent needs the ' +
              'module brief, which this instrument does not read.'
            : ''),
        measuredAt: STARTED,
        nonVacuity: { controlRan: false, note: 'graph sweep has no positive control' },
        evidence: [{ type: 'query',
          sql: "objects/refs in .mxcli/catalog.db, grouped by module",
          value: inb + ' inbound' }],
        blocks: [],
      });
    } else if (f[0] === 'orphan') {
      orphanCount++;
      checks.push({
        id: 'review/orphan/' + slug(f[1]), instrument: 'graph-sweep', kind: 'conformance',
        module: MODULE, journey: null, stepIndex: null, stepName: null, requirement: null,
        title: f[1] + ' — microflow with no inbound call',
        verdict: 'manual', provenance: 'judged',
        detail: (f[2] || '?') + ' activities, and no inbound call / action / menu_item / ' +
          'show_page / datasource edge. Entry-point prefixes are already excluded. ' +
          'SHOW REFERENCES TO misses layout snippetcalls, so this is strong evidence of ' +
          'deadness, not proof.',
        measuredAt: STARTED,
        nonVacuity: { controlRan: false, note: 'graph sweep has no positive control' },
        evidence: [{ type: 'query', sql: 'microflows_data LEFT JOIN refs (catalog.db)',
                     value: f[1] }],
        blocks: [],
      });
    }
  }
}

if (!ran('graph-sweep') || !graphParsed) {
  checks.push(faultCheck('review/wiring/' + slug(MODULE), 'graph-sweep', 'conformance',
    MODULE + ' — module wiring shape was not measured',
    (byName.get('graph-sweep') && byName.get('graph-sweep').reason) ||
    (graphParsed
      ? 'graph-sweep did not run; the catalog was stale, empty or missing'
      : 'graph-sweep produced no TSV — graph.tsv carries no `kind` header, so it holds ' +
        'the instrument\'s failure output, not a sweep. Nothing about the wiring of ' +
        MODULE + ' was read.')));
  checks.push(faultCheck('review/orphan/' + slug(MODULE) + '/none', 'graph-sweep',
    'conformance', MODULE + ' — orphaned microflows were not looked for',
    'no sweep output to read. Zero orphans found in zero lines is not zero orphans.'));
} else {
  if (!wiringSeen) {
    // A module below --min-elements produces no wiring row at all. Silence there reads
    // as "wired fine"; it means "not looked at".
    checks.push(faultCheck('review/wiring/' + slug(MODULE), 'graph-sweep', 'conformance',
      MODULE + ' — module wiring shape was not measured',
      'graph-sweep emitted no wiring row for this module: it sits below the ' +
      '--min-elements threshold, or carries no objects in the catalog.'));
  }
  if (orphanCount === 0) {
    checks.push({
      id: 'review/orphan/' + slug(MODULE) + '/none', instrument: 'graph-sweep',
      kind: 'conformance', module: MODULE, journey: null, stepIndex: null, stepName: null,
      requirement: null, title: MODULE + ' — no orphaned microflows',
      verdict: 'pass', provenance: 'measured',
      detail: 'every microflow in ' + MODULE + ' has at least one inbound call / action / ' +
              'menu_item / show_page / datasource edge (entry-point prefixes excluded).',
      measuredAt: STARTED,
      nonVacuity: { controlRan: false, note: 'graph sweep has no positive control' },
      evidence: [{ type: 'query', sql: 'microflows_data LEFT JOIN refs (catalog.db)',
                   value: '0 orphans' }],
      blocks: [],
    });
  }
}

/* ── coverage ─────────────────────────────────────────────────────────────── */

const covTxt = readIf(path.join(DIR, 'coverage.txt'));
let leaves = null;
// coverage.txt is coverage-check's LOG file: on a crash or a fault it exists and holds the
// error text. Every counter then parses to null, `null > 0` is false, `bad` is empty, and
// the row went out as pass/measured reading "leaves null · claimed null · unclaimed null".
// Measured 2026-08-18 with coverage.txt = "cannot read BRD: unexpected token at line 1".
// So: parse first, and only claim a verdict if all five counters are real numbers.
const COUNTERS = ['total', 'claimed', 'unclaimed', 'phantom', 'doubleClaimed'];
if (covTxt) {
  const g = (re) => { const m = re.exec(covTxt); return m ? Number(m[1]) : null; };
  leaves = {
    total:         g(/^\s*leaves:\s*(\d+)/m),
    claimed:       g(/^\s*CLAIMED:\s*(\d+)/m),
    unclaimed:     g(/^\s*UNCLAIMED:\s*(\d+)/m),
    phantom:       g(/^\s*PHANTOM:\s*(\d+)/m),
    doubleClaimed: g(/^\s*DOUBLE-CLAIMED:\s*(\d+)/m),
  };
}
const covMissing = leaves ? COUNTERS.filter((k) => leaves[k] == null) : COUNTERS;
if (covTxt && covMissing.length === 0) {
  const bad = ['unclaimed', 'phantom', 'doubleClaimed'].filter((k) => leaves[k] > 0);
  checks.push({
    id: 'review/coverage/' + slug(MODULE), instrument: 'coverage', kind: 'coverage',
    module: MODULE, journey: null, stepIndex: null, stepName: null, requirement: null,
    title: MODULE + ' — every BRD leaf claimed by exactly one ledger row',
    verdict: bad.length ? 'fail' : 'pass', provenance: 'measured',
    detail: 'leaves ' + leaves.total + ' · claimed ' + leaves.claimed + ' · unclaimed ' +
            leaves.unclaimed + ' · phantom ' + leaves.phantom + ' · double-claimed ' +
            leaves.doubleClaimed,
    measuredAt: STARTED,
    nonVacuity: { controlRan: false, note: 'coverage-check has no positive control' },
    evidence: [{ type: 'log', path: relOut(path.join(DIR, 'coverage.txt')) }],
    blocks: [],
  });
} else {
  checks.push(faultCheck('review/coverage/' + slug(MODULE), 'coverage', 'coverage',
    MODULE + ' — BRD leaf coverage was not measured',
    (byName.get('coverage') && byName.get('coverage').reason) ||
    (covTxt
      ? 'coverage-check wrote output but no ' + covMissing.join('/') + ' count could be ' +
        'read from it, so it did not finish a count. An unreadable counter is an ' +
        'unmeasured one, never a zero.'
      : 'coverage-check produced no output')));
  // The rollup must not inherit half-parsed counters either.
  if (covMissing.length) leaves = null;
}

/* ── the journey that did not run ─────────────────────────────────────────── */
// Rule 3. Present, `fault`, and worded so nobody has to infer it.

checks.push({
  id: 'review/journey/' + slug(MODULE), instrument: 'journey-runner', kind: 'outcome',
  module: MODULE, journey: null, stepIndex: null, stepName: null, requirement: null,
  title: MODULE + ' — the running app was never contacted',
  verdict: 'fault', provenance: 'declared', notRun: true,
  detail: 'no journey run in this invocation. bin/review-module.sh answers a MODEL ' +
          'question (does what was built match what was decided) and deliberately never ' +
          'starts the app. Nothing in this report is evidence about runtime behaviour. ' +
          'For that: bin/loop/verify-module.sh ' + MODULE + ', with the stack up.',
  measuredAt: STARTED,
  nonVacuity: { controlRan: false, note: 'no journey ran, so no control could run either' },
  evidence: [{ type: 'command', command: 'bin/loop/verify-module.sh ' + MODULE }],
  blocks: [],
});
if (!byName.has('journey-runner')) {
  instruments.push({
    name: 'journey-runner', verdict: 'fault',
    reason: 'no journey run in this invocation', canExpressFault: true,
  });
}

/* ── the LOOK that did not happen ─────────────────────────────────────────── */
// Same rule, same reason, one layer up: module-review.md stage 4 is the pass that finds
// the defects a journey walks straight past — a page that renders but is unusable, a
// placeholder heading, a primary action nobody can find. No script performs it. Omitting
// the row let an end-to-end run report journeys, DB assertions and a monkey pass, go
// green, and never look at a screen (measured 2026-08-20).

checks.push({
  id: 'review/look/' + slug(MODULE), instrument: 'ui-review', kind: 'outcome',
  module: MODULE, journey: null, stepIndex: null, stepName: null, requirement: null,
  title: MODULE + ' — no page in this module was looked at',
  verdict: 'fault', provenance: 'declared', notRun: true,
  detail: 'module-review.md stage 4 (the LOOK) was not performed in this invocation and ' +
          'cannot be: it is a judgement pass over rendered pages, assessed against the ' +
          'wireframe, the design system, or §4d\'s unaided rubric where neither exists. ' +
          'Nothing in this report is evidence about how ' + MODULE + ' looks or whether a ' +
          'user could complete anything on it. For that: review-agent job 2, which writes ' +
          'design/ui-reviews/ui-review-<date>.html and appends P1/P2 findings to ' +
          'docs/improvement-register.md.',
  measuredAt: STARTED,
  nonVacuity: { controlRan: false, note: 'nobody looked, so there is nothing to control for' },
  evidence: [{ type: 'command', command: 'review-agent — module-review.md §4 over ' + MODULE }],
  blocks: [],
});
if (!byName.has('ui-review')) {
  instruments.push({
    name: 'ui-review', verdict: 'fault',
    reason: 'no visual review in this invocation - module-review.md stage 4',
    canExpressFault: true,
  });
}

/* ── coverage[] rollup ────────────────────────────────────────────────────── */

const ledgerPath = path.join(ROOT, 'architecture/modules/' + MODULE + '/coverage-ledger.md');
const ledger = readIf(ledgerPath);
const coverage = [];
if (ledger) {
  const brdRel = (/[A-Za-z0-9_/.-]*\.brd\.json/.exec(ledger) || [null])[0];
  const brdId = brdRel ? (/(F\d+)/.exec(path.basename(brdRel)) || [null, null])[1] : null;
  const tot = /^\|\s*BUILDABLE\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|/m.exec(ledger);
  const st = (name) => {
    const m = new RegExp('^\\|\\s*' + name + '\\s*\\|\\s*(\\d+)\\s*\\|', 'm').exec(ledger);
    return m ? Number(m[1]) : null;
  };
  coverage.push({
    module: MODULE, brd: brdId,
    // null, never 0: "we never counted" and "we counted zero" are opposite facts, and
    // painting null green is the false green this whole contract exists to retire.
    leaves: leaves || { total: null, claimed: null, unclaimed: null, phantom: null,
                        doubleClaimed: null },
    rows: tot ? { buildable: Number(tot[1]),
                  byStatus: { built: st('built'), partial: st('partial'),
                              notBuilt: st('not-built') } }
              : null,
    conformance: conf.checked
      ? { checked: conf.checked, ok: conf.ok, stale: conf.stale,
          understated: conf.understated, unrunnable: conf.unrunnable + conf.timeout }
      : null,
    journeys: [],   // empty = nothing walks this module IN THIS REPORT, by construction
    source: 'architecture/modules/' + MODULE + '/coverage-ledger.md',
    generatedAt: (/Regenerated\s+(\d{4}-\d{2}-\d{2})/.exec(ledger) || [null, null])[1],
  });
}

/* ── assemble ─────────────────────────────────────────────────────────────── */

function faultCheck(id, instrument, kind, title, why) {
  return {
    id, instrument, kind, module: MODULE, journey: null, stepIndex: null, stepName: null,
    requirement: null, title, verdict: 'fault', provenance: 'declared', notRun: true,
    detail: why, measuredAt: STARTED,
    nonVacuity: { controlRan: false, note: 'the instrument did not produce this row' },
    evidence: [], blocks: [],
  };
}

/** evidence[].path is relative to report.json (schema rule 3). */
function relOut(abs) {
  let r = path.relative(path.dirname(path.resolve(OUT)), abs);
  return path.sep === '\\' ? r.split('\\').join('/') : r;
}

let mprMtime = null;
try { mprMtime = fs.statSync(path.join(ROOT, MPR_NAME)).mtime.toISOString(); } catch (e) {}
let mendix = null;
try { mendix = JSON.parse(readIf(path.join(ROOT, 'deployment/model/metadata.json')) || '{}')
  .RuntimeVersion || null; } catch (e) {}
const gitCommit = sh('git rev-parse --short HEAD');
const branch = sh('git rev-parse --abbrev-ref HEAD');
const toolkitCommit = (() => {
  const p = readIf(path.join(ROOT, 'PROJECT.md')) || '';
  const m = /Toolkit commit:\s*`?([0-9a-f]{7,40})`?/i.exec(p);
  return m ? m[1] : null;
})();

const report = {
  schemaVersion: SCHEMA_VERSION,
  project: {
    id: path.basename(ROOT), displayName: DISPLAY, mpr: MPR_NAME,
    mprModifiedAt: mprMtime, mendixVersion: mendix, toolkitCommit,
    gitCommit, branch,
  },
  run: {
    startedAt: STARTED, finishedAt: FINISHED,
    trigger: 'review-module', target: MODULE,
    env: {
      // The app was never contacted. Saying so beats leaving a baseUrl that implies it was.
      baseUrl: null, host: null, ownership: 'unknown',
      ownershipBasis: 'no app contacted — this is a model-side review, run with the app down',
      user: null, userFallbackUsed: false, database: null,
    },
    reproduce: {
      command: 'bin/review-module.sh ' + MODULE,
      seeds: null, monkeySeed: null,
    },
  },
  checks,
  instruments,
  coverage,
  deferrals: [],
  walks: [],   // never fabricated from a contract: no journey ran, so there is no walk
};

fs.mkdirSync(path.dirname(path.resolve(OUT)), { recursive: true });
fs.writeFileSync(OUT, JSON.stringify(report, null, 1) + '\n');

const roll = checks.reduce((a, c) => { a[c.verdict] = (a[c.verdict] || 0) + 1; return a; }, {});
console.error('review-report: ' + checks.length + ' checks (' +
  Object.keys(roll).sort().map((k) => roll[k] + ' ' + k).join(' · ') + ') -> ' + OUT);
