'use strict';
// ============================================================================
// report-normalize.js — every instrument's output, in one honest shape
// ----------------------------------------------------------------------------
//   node tests/e2e/report-normalize.js [--out docs/report.json]
//   node tests/e2e/report-normalize.js --selftest
//
// WHY THIS EXISTS
// Five instruments emit four incompatible verdict enums in three formats
// (docs/verification/report-schema.md, opening paragraph). The renderer must not
// know that. This file is the only place in the project that knows how a
// journey-runner "INVALID" relates to a summary.tsv "FAULT" relates to a
// findings.json `"status": "fail"`, and it collapses them onto the one enum:
//
//     pass | fail | fault | skipped | manual
//
// THE THREE RULES THAT COST US THE MOST TO LEARN, and how they are enforced here:
//
//   1. ABSENT IS NOT GREEN. Every input this file knows about is DECLARED up front
//      (see INPUTS). If it is missing, unreadable, or malformed, it becomes an
//      instruments[] entry with verdict "fault" and a reason. There is no code path
//      in which an input silently contributes nothing. This is the single false
//      positive the whole verification effort exists to retire: a harness that never
//      started renders as a clean run.
//
//   2. "DID NOT RUN" IS NOT "PASSED" AND NOT "FAILED". journey-runner's INVALID maps
//      to `fault`, never to fail. They send you to different places: `fail` sends you
//      to the app, `fault` sends you to the instrument. Blending them is how a week
//      gets spent debugging a page that was never reached.
//
//   3. A FAILED LANDING GUARD LEAVES A HOLE, AND THE HOLE MUST BE DRAWN. When step 5's
//      guard fails, the runner returns — so steps 5..N's span checks, data deltas and
//      OQL expectations produce NO records at all. Rendering only what was recorded
//      shows a run with one red cell and no gap. `expandBlocked()` reads the journey
//      CONTRACT (journeys/*.journey.json) — the only artefact that knows what WOULD
//      have been measured — and emits every declared-but-unrun expectation as a real
//      `fault` check, wired to the guard through `blocks[]`. On the live data this is
//      the difference between 13 checks and 26.
//
// DESIGN: normalize() is PURE. All file IO happens in loadInputs(); normalize() takes
// the loaded bundle and returns the report object. That is what makes --selftest able
// to assert the mapping rules against inline fixtures with no app, no DB, no artifacts.
// ============================================================================

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

// project.config.js is the only project-aware file in tests/e2e/, and it has no
// side effects at require time.
const PROJ = require('./project.config');

const ROOT = PROJ.root;
// The project's own walkthrough instruments. report-normalize used to branch on
// these two names as string literals in three separate places, so a project with
// different walkthrough scripts (or none) had no way to say so.
const WALKTHROUGHS = PROJ.walkthroughs;
const WALKTHROUGH_BY_NAME = new Map(WALKTHROUGHS.map((w) => [w.instrument, w]));
// 1.1 is additive throughout — a 1.0 renderer warns and renders every field it knows,
// which is the correct degradation. It adds:
//   walks[]                  the narrated walk (2026-08-17)
//   walks[].steps[].page     {qualifiedName, inScope, role[], wireframe, rung6, rung7[]}
//   roleSets[]               distinct in-scope page sets, one per SET and not per role
//   pageCoverage             the in-scope denominator and the pages nothing walked
//   run.env.ownership        carried since 1.0, first written by config.js (cfg.ownership)
// and one behavioural change that is NOT additive in spirit but is in shape: the
// journey rows of checks[] are now DERIVED from walks[] instead of being read
// independently out of results[]. Same ids, same verdicts, one source. See
// deriveWalkChecks().
// 1.2 is additive. It adds, on top of 1.1:
//   checks[].remediation     {class, measures, why, blastRadius, action, actionKind,
//                             needsApproval, where} on every non-pass check
//   nextSteps[]              the same remediations GROUPED and RANKED, so 135 identical
//                            faults become one actionable row with a count, not 135 shrugs
// Written 2026-08-18 for one measured reason: the rendered report contained the strings
// "did not run" 135 times and the strings "next step", "remediation", "how to fix" ZERO
// times. A hole that does not say what would close it is a shrug, not a finding.
const SCHEMA_VERSION = '1.2';

// ── The declared input set ───────────────────────────────────────────────────
// Rule 1 lives here. Anything this tool reads is named in this table, and every
// entry produces an instruments[] row whether or not the file exists.
const INPUTS = {
  journeyFindings: 'tests/e2e/artifacts/journey-findings.json',
  // A SEPARATE slot, because journey-findings.json is a single slot and a
  // --positive-control run overwrites the real walk in it (observed 2026-08-14:
  // the control run replaced 24 real results with 146 control ones, and a
  // normalizer reading only that file would have reported the mutants' findings
  // as the product's). The two runs answer different questions and must not
  // share storage: "the app works" and "the harness can tell when it doesn't".
  journeyFindingsControl: 'tests/e2e/artifacts/journey-findings-control.json',
  findings:        'tests/e2e/artifacts/findings.json',
  findingsMobile:  'tests/e2e/artifacts/findings-mobile.json',
  verifyDir:       '.claude/loop/verify',
  conformanceDir:  'docs/conformance',
  modulesDir:      'architecture/modules',
  journeysDir:     'journeys',
  runLedger:       '.claude/loop/run-ledger.jsonl',
  deferrals:       '.claude/loop/deferrals.jsonl',
  mpr:             PROJ.mprName,
  metadata:        'deployment/model/metadata.json',
  appConfig:       'deployment/model/config.json',
  projectMd:       'PROJECT.md',
  // ── 1.1 inputs ────────────────────────────────────────────────────────────
  // The two design rungs (6 = does the page match its wireframe, 7 = does it match
  // general design practice). Keyed by `page`, which is why the walk needs a page
  // block to join on at all.
  designAudit:     'tests/e2e/artifacts/design-audit.json',
  // The 19 in-scope pages, the 10 classified orphans, and the role→page sets. This is
  // the denominator: without it a report can only say "everything we walked was fine",
  // which is true of a run that walked one page.
  pageScope:       '.claude/loop/page-scope.json',
  // Widget → page index. A walk step says `.mx-name-dvScanCtx`; only the model knows
  // which page owns that widget. Read-only; a missing catalog degrades to unresolved
  // pages, never to a guessed one.
  catalog:         '.mxcli/catalog.db',
  wireframeDir:    'design/wireframes',
};

const KINDS = new Set(['ui', 'trace', 'data', 'outcome', 'control',
                       'build', 'lint', 'coverage', 'conformance', 'stack']);

// ── Verdict maps — one table per source dialect, nothing inline ──────────────
// Kept as data, not as `if` chains, so the mapping is auditable at a glance and
// the selftest can assert it directly.

// journey-runner. INVALID means "the instrument did not run" — the runner is
// explicit about this in its own header — so it is `fault`. Mapping it to `fail`
// would file an instrument outage as a product defect; mapping it to `pass` is the
// original sin this schema was written to prevent.
const V_JOURNEY = { PASS: 'pass', FAIL: 'fail', INVALID: 'fault' };

// .claude/loop/verify/<Module>/summary.tsv. FINDING is a real disagreement.
// INFO carries no verdict at all; `manual` is the schema's slot for "a human still
// has to look at this", which is exactly what an INFO row is.
const V_LOOP = { PASS: 'pass', FINDING: 'fail', FAULT: 'fault', INFO: 'manual', SKIPPED: 'skipped' };

// findings.json / findings-mobile.json. NOTE THE MISSING COLUMN: this dialect has
// no way to say "did not run". `ok`/`pass` and `fail`/`missing` are all it has, so a
// harness that died mid-page leaves greens behind for the pages it never reached.
// That weakness is recorded machine-readably on the instruments[] entry
// (canExpressFault:false, evidenceStrength:"weak") — see walkthroughInstrument().
const V_WALK = { ok: 'pass', pass: 'pass', fail: 'fail', missing: 'fail', error: 'fail' };

// docs/conformance/report-<date>.tsv. STALE and UNDERSTATED are both "the ledger and
// the model disagree" — findings. UNRUNNABLE is the instrument admitting it could not
// look, which is a fault by definition.
const V_CONF = { OK: 'pass', STALE: 'fail', UNDERSTATED: 'fail', OVERSTATED: 'fail',
                 UNRUNNABLE: 'fault', SKIPPED: 'skipped' };

// ── Small utilities ──────────────────────────────────────────────────────────

const abs = p => (path.isAbsolute(p) ? p : path.join(ROOT, p));

// Requirement pointers: rule 4 of the schema. A blank cell in a source is the
// ABSENCE of a pointer, and "" renders as an empty table cell that reads like an
// oversight. null reads as the measured fact it is. Never synthesise one.
function normReq(v) {
  if (v === null || v === undefined) return null;
  const s = String(v).trim();
  if (!s) return null;
  return s;
}

// Ids must be stable across runs (rule 6: two runs over the same inputs diff
// cleanly), so they are derived from content, never from array position or time.
function slug(s) {
  return String(s ?? '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80) || 'unnamed';
}
const pad2 = n => String(n).padStart(2, '0');

// Deterministic key order. JSON.stringify walks insertion order, so two runs that
// build objects by different code paths would diff even with identical data.
function sortKeysDeep(v) {
  if (Array.isArray(v)) return v.map(sortKeysDeep);
  if (v && typeof v === 'object') {
    const out = {};
    for (const k of Object.keys(v).sort()) out[k] = sortKeysDeep(v[k]);
    return out;
  }
  return v;
}

// Evidence paths are relative to report.json and never base64 (schema rule 3).
function relTo(outFile, target) {
  return path.relative(path.dirname(abs(outFile)), abs(target)).split(path.sep).join('/');
}

// Every read goes through here so that "missing" and "unreadable" and "not JSON"
// arrive at the caller as data rather than as a thrown exception that would abort
// the whole report — a reporting tool that crashes on a bad input is a reporting
// tool that renders nothing, which is worse than rendering a fault.
function readFileInput(rel) {
  const p = abs(rel);
  try {
    return { status: 'ok', path: rel, text: fs.readFileSync(p, 'utf8') };
  } catch (e) {
    return { status: e.code === 'ENOENT' ? 'missing' : 'unreadable', path: rel, error: e.message };
  }
}
function readJsonInput(rel) {
  const f = readFileInput(rel);
  if (f.status !== 'ok') return f;
  try {
    return { status: 'ok', path: rel, data: JSON.parse(f.text) };
  } catch (e) {
    return { status: 'malformed', path: rel, error: e.message };
  }
}
// ── What would produce this input? ───────────────────────────────────────────
// House style for an absent artifact is bin/gate-check.sh:577's: name WHERE it looked
// AND what writes it. Measured 2026-08-20 (VB-USI-main): the report carried the reason
// "tests/e2e/artifacts/findings.json does not exist — the instrument did not run, or ran
// without writing" for a whole instrument that was dark, and a reader could do nothing
// with it. Four instruments were in that state at once.
//
// VERIFIED producers only. An input with no entry says it has no entry — an invented
// command is worse than an admitted gap, exactly as `class: "unclassified"` with
// `action: null` is the only honest fallthrough for a remediation (report-schema.md §1.2).
const PRODUCERS = {
  [INPUTS.journeyFindings]:
    'node tests/e2e/journey-runner.js journeys/<Journey>.journey.json',
  [INPUTS.journeyFindingsControl]:
    'node tests/e2e/journey-runner.js --positive-control journeys/<Journey>.journey.json',
  [INPUTS.designAudit]: 'node tests/e2e/design-audit.js',
};
// The walkthrough scripts are per-project (project.config.js `walkthroughs`), so they are
// read from there rather than hard-coded — the same table the remediation classifier
// already uses to tell a reader what to re-run.
for (const w of WALKTHROUGHS) {
  if (w && w.input && INPUTS[w.input] && w.script) {
    PRODUCERS[INPUTS[w.input]] = `node tests/e2e/${w.script}`;
  }
}
const producerOf = p => PRODUCERS[p] || null;

const REASON = {
  missing: (f) => {
    const prod = producerOf(f.path);
    return `${f.path} does not exist — the instrument did not run, or ran without writing. ` +
      (prod
        ? `\`${prod}\` writes it; until it does, nothing in this report is evidence about ` +
          `what it would have measured.`
        : `No producer for this path is recorded in report-normalize.js PRODUCERS, so this ` +
          `report cannot say what writes it — closing that gap is the first step.`);
  },
  unreadable: f => `${f.path} could not be read: ${f.error}`,
  malformed:  f => `${f.path} is not valid JSON: ${f.error}`,
};
const faultReason = f => (REASON[f.status] || (x => `${x.path}: ${x.status}`))(f);

function safeExec(cmd, args, opts) {
  try {
    return execFileSync(cmd, args, { cwd: ROOT, encoding: 'utf8', timeout: 5000,
                                     stdio: ['ignore', 'pipe', 'ignore'], ...opts }).trim();
  } catch { return null; }
}

// ============================================================================
// SOURCE 1 — journey-findings.json + the journey contracts
// ============================================================================

// The runner records every check as `${step.name}: ${what}`, and records the
// journey id NOWHERE in the results rows (an instrument gap — see the report).
// So the journey and step ordinal are recovered by matching the step-name prefix
// against the contracts. Names are unique per contract in practice; where two
// contracts share a step name the first match wins and the ambiguity is noted.
function indexContracts(contracts) {
  const byStep = new Map();
  for (const c of contracts) {
    const j = c.data;
    if (!j || !Array.isArray(j.steps)) continue;
    j.steps.forEach((s, i) => {
      if (!byStep.has(s.name)) byStep.set(s.name, { journey: j, stepIndex: i + 1, step: s, file: c.path });
    });
  }
  return byStep;
}

// The runner's own naming conventions, reproduced EXACTLY. This is load-bearing:
// expandBlocked() generates the name the runner WOULD have recorded, so a generated
// entry and a real one collapse onto the same id and dedupe cleanly. If the runner's
// wording changes, blocked entries start duplicating real ones — the selftest's
// dedupe assertion is what catches that.
function declaredChecks(step, journey) {
  const out = [];
  const n = step.name;
  const ui = step.ui || {};
  if (ui.ready) out.push({ kind: 'ui', name: `${n}: reached`, title: 'reached', expectation: ui.ready });
  for (const c of ui.checks || [])
    out.push({ kind: 'ui', name: `${n}: widget ${c}`, title: `widget ${c} visible`, expectation: `.mx-name-${c}` });
  for (const t of ui.textPresent || [])
    out.push({ kind: 'ui', name: `${n}: page says "${t}"`, title: `page says "${t}"`, expectation: t });
  for (const t of ui.textAbsent || [])
    out.push({ kind: 'ui', name: `${n}: page does NOT say "${t}"`, title: `page does NOT say "${t}"`, expectation: t });
  const sp = step.spans || {};
  if ((sp.ordered || []).length) {
    out.push({ kind: 'trace', name: `[GUARD] ${n}: capture non-empty`, title: 'span capture non-empty', expectation: '>= 1 span' });
    out.push({ kind: 'trace', name: `[MF] ${n}: ordered`, title: `spans in order: ${sp.ordered.join(' → ')}`, expectation: sp.ordered.join(' → ') });
    out.push({ kind: 'trace', name: `[MF] ${n}: no ERROR at any level`, title: 'no ERROR span at microflow or activity level', expectation: 'all spans OK' });
  }
  for (const m of sp.mustNotFire || [])
    out.push({ kind: 'trace', name: `[MF] NEGATIVE: ${n}: ${m} did not run`, title: `${m} did not run`, expectation: `no span matching ${m}` });
  const d = step.data || {};
  if (d.creates)
    out.push({ kind: 'data', name: `${n}: ${d.creates} +${d.delta ?? 1}`, title: `${d.creates} row count +${d.delta ?? 1}`, expectation: `delta ${d.delta ?? 1}` });
  for (const a of d.assocMustBeSet || []) {
    const e = a.entity || d.creates;
    out.push({ kind: 'data', name: `${n}: ${a.assoc} set on every row`, title: `${a.assoc} set on every ${e} row`, expectation: 'gap 0' });
    if (a.mustPointAt)
      out.push({ kind: 'data', name: `${n}: ${a.assoc} points at the seeded ${a.mustPointAt.attr}`,
                 title: `${a.assoc} points at the seeded ${a.mustPointAt.attr}`, expectation: String(a.mustPointAt.value) });
  }
  for (const q of d.oql || [])
    out.push({ kind: 'data', name: `${n}: ${q.label}`, title: q.label,
               expectation: q.expect !== undefined ? `= ${q.expect}` : q.atLeast !== undefined ? `>= ${q.atLeast}` : 'no bar declared' });
  // Journey-level requirement is the fallback when a step declares none — same
  // precedence the runner uses.
  const req = normReq((step.requirement || journey.requirement || []).join(', '));
  return out.map(o => ({ ...o, requirement: req }));
}

function journeyCheckId(jid, stepIndex, name) {
  const base = stepIndex ? `journey/${jid}/step${stepIndex}/` : `journey/${jid}/`;
  return base + slug(name);
}

function collectJourney(input, contracts, ctx) {
  const checks = [];
  const instruments = [];
  if (input.status !== 'ok') {
    instruments.push({ name: 'journey-runner', verdict: 'fault', reason: faultReason(input),
                       source: input.path, sourceVerdicts: Object.keys(V_JOURNEY) });
    // The positive control is a SEPARATE instrument, emitted by collectControl from
    // its own file. Folding it in here would let "no journeys ran at all" and
    // "journeys ran, but nothing was ever proven able to fail" render identically.
    return { checks, instruments };
  }
  const d = input.data || {};

  // A control run in the real walk's slot is a FAULT, never product evidence.
  //
  // Every row in a control run comes from a deliberately-broken journey. Normalizing
  // them as product results would report mutants' failures as the app's defects and,
  // worse, their incidental passes as the app working. The runner no longer writes
  // here on a control run, but files outlive the code that wrote them: this guard is
  // what makes the pipeline safe to point at an artifacts directory of unknown age.
  if (d.positiveControl) {
    instruments.push({ name: 'journey-runner', verdict: 'fault',
      source: input.path, sourceVerdicts: Object.keys(V_JOURNEY),
      reason: `${input.path} holds a POSITIVE CONTROL run (positiveControl: true), not a real walk — ` +
              'every journey in it was deliberately broken. The real walk\'s evidence has been ' +
              'overwritten; re-run the runner without --positive-control to restore it.' });
    return { checks, instruments };
  }

  const results = Array.isArray(d.results) ? d.results : [];
  const byStep = indexContracts(contracts);
  const at = d.capturedAt || null;

  // Which journey does an unattributed row (e.g. "login") belong to? None — it is a
  // run-level check. `_` keeps the id sortable and marks the absence honestly.
  const seen = new Map();      // id -> check, for dedupe against blocked expansion
  const failedGuards = [];

  // ── checks[] is DERIVED from walks[] ───────────────────────────────────────
  // Until 1.1 the journey rows of checks[] and the rows inside walks[] were read out
  // of the same file by two independent code paths. Two structures that can disagree
  // will: the runner writes both, and nothing compared them. On the live artifact they
  // happened to agree (22 walk checks, 24 results rows, zero verdict disagreements) —
  // which is exactly the state in which a divergence would first ship unnoticed.
  //
  // So: where a walk exists, the walk IS the checks. results[] is then used for two
  // things only — the rows no walk step owns (`login`, the end-state query), and as a
  // reconciliation input that FAILS loudly if the two ever stop agreeing.
  const walkRaw = Array.isArray(d.walks) ? d.walks : [];
  const derived = deriveWalkChecks(walkRaw, ctx, at, d, contracts);
  for (const c of derived.checks) {
    seen.set(c.id, c);
    checks.push(c);
    if (c.verdict === 'fail' && /:\s*reached$/.test(c.sourceName || '')) {
      const hit = byStep.get(c.stepName);
      if (hit) failedGuards.push({ check: c, hit });
    }
  }
  checks.push(...reconcileWalkAgainstResults(walkRaw, results, byStep, ctx, at));

  for (const r of results) {
    // A row the walk already owns is not read twice. Matching is by the id the two
    // paths would produce, so a rename on either side surfaces as a duplicate rather
    // than a silent overwrite.
    if (derived.ownedNames.has(String(r.name || ''))) continue;
    const raw = String(r.name || '');
    const idx = raw.indexOf(': ');
    // Strip the otel reporter's own prefixes before matching the step name, or
    // "[MF] resolve the scanned item: ordered" never finds its step.
    const unprefixed = raw.replace(/^\[(GUARD|MF)\]\s*/, '').replace(/^NEGATIVE:\s*/, '');
    const pIdx = unprefixed.indexOf(': ');
    const stepName = pIdx > 0 ? unprefixed.slice(0, pIdx) : null;
    const hit = stepName ? byStep.get(stepName) : null;
    const jid = hit ? hit.journey.id : '_';
    const stepIndex = hit ? hit.stepIndex : null;
    const title = idx > 0 ? raw.slice(idx + 2) : raw;

    const verdict = V_JOURNEY[String(r.verdict).toUpperCase()] || 'fault';
    let id = journeyCheckId(jid, stepIndex, raw);
    let bump = 1;
    while (seen.has(id)) id = journeyCheckId(jid, stepIndex, raw) + `~${++bump}`;

    const check = {
      id,
      instrument: 'journey-runner',
      kind: KINDS.has(r.rung) ? r.rung : 'ui',
      module: hit ? ctx.journeyModule.get(hit.file) || null : null,
      journey: hit ? jid : null,
      stepIndex,
      stepName: stepName || null,
      requirement: normReq(r.requirement),
      title,
      verdict,
      provenance: 'measured',
      detail: String(r.detail ?? ''),
      measuredAt: at,
      nonVacuity: {
        controlRan: !!d.positiveControl,
        note: d.positiveControl ? 'run included --positive-control'
                                : 'positive control not run for this build',
      },
      evidence: [],
      blocks: [],
    };

    // The runner names the screenshot in prose; lift it into evidence[] so the
    // renderer never has to parse a detail string.
    const shot = /screenshot ([\w.\-]+\.png)/.exec(check.detail);
    if (shot) check.evidence.push({ type: 'screenshot', path: relTo(ctx.outFile, `tests/e2e/artifacts/${shot[1]}`) });

    seen.set(id, check);
    checks.push(check);
    if (verdict === 'fail' && /:\s*reached$/.test(raw) && hit) failedGuards.push({ check, hit });
  }

  // ── blocks[]: the severed spine ────────────────────────────────────────────
  for (const g of failedGuards) {
    const j = g.hit.journey;
    const from = g.hit.stepIndex;              // the guard's own step is also blocked
    const generated = [];
    for (let i = from; i <= j.steps.length; i++) {
      const step = j.steps[i - 1];
      for (const dc of declaredChecks(step, j)) {
        const id = journeyCheckId(j.id, i, dc.name);
        if (seen.has(id)) continue;            // it actually ran; not blocked
        const blocked = {
          id,
          instrument: 'journey-runner',
          kind: dc.kind,
          module: ctx.journeyModule.get(g.hit.file) || null,
          journey: j.id,
          stepIndex: i,
          stepName: step.name,
          requirement: dc.requirement,
          title: dc.title,
          verdict: 'fault',
          // NOT "measured": nothing was measured. The expectation is read out of the
          // contract, which is the only artefact that knows it. See the report note on
          // this being a schema extension.
          provenance: 'declared',
          notRun: true,
          detail: `declared in ${path.basename(g.hit.file)} but never measured — ` +
                  `step ${from} ("${j.steps[from - 1].name}") failed its landing guard and the journey stopped. ` +
                  `Expectation: ${dc.expectation}`,
          measuredAt: at,
          nonVacuity: { controlRan: !!d.positiveControl, note: 'check did not run' },
          evidence: [{ type: 'contract', path: relTo(ctx.outFile, g.hit.file) }],
          blocks: [],
          blockedBy: g.check.id,
        };
        seen.set(id, blocked);
        checks.push(blocked);
        generated.push(id);
      }
    }
    if (j.outcome && j.outcome.sql) {
      const id = journeyCheckId(j.id, null, `${j.id} end state`);
      if (!seen.has(id)) {
        const c = {
          id, instrument: 'journey-runner', kind: 'outcome',
          module: ctx.journeyModule.get(g.hit.file) || null, journey: j.id,
          stepIndex: null, stepName: null,
          requirement: normReq((j.requirement || []).join(', ')),
          title: `${j.id} end state`,
          verdict: 'fault', provenance: 'declared', notRun: true,
          detail: `the journey's end-state query never ran — stopped at step ${from}. ` +
                  `Expectation: ${j.outcome.expect !== undefined ? '= ' + j.outcome.expect : '>= ' + j.outcome.atLeast}`,
          measuredAt: at,
          nonVacuity: { controlRan: !!d.positiveControl, note: 'check did not run' },
          evidence: [{ type: 'contract', path: relTo(ctx.outFile, g.hit.file) }],
          blocks: [], blockedBy: g.check.id,
        };
        seen.set(id, c); checks.push(c); generated.push(id);
      }
    }
    g.check.blocks = generated.sort();
  }

  instruments.push({
    name: 'journey-runner',
    verdict: 'pass',                            // the INSTRUMENT ran; its checks carry the findings
    rc: null, elapsedSec: null, log: input.path,
    source: input.path,
    canExpressFault: true,
    evidenceStrength: 'strong',
    note: 'PASS/FAIL/INVALID are distinct at the source; INVALID → fault',
    checksEmitted: checks.length,
  });
  return { checks, instruments, walks: collectWalks(d, checks) };
}

// ── walks[] → checks[] ──────────────────────────────────────────────────────
// The walk knows its journey id and its step ordinal directly, so the derived rows
// are attributed better than the old path could manage: results[] records neither,
// and the journey had to be recovered by matching a step-name prefix against the
// contracts (first match wins, ambiguity noted). Derivation removes that guess.
function contractsByJourneyId(contracts, ctx) {
  const m = new Map();
  for (const c of contracts) {
    const id = c.data && c.data.id;
    if (id && !m.has(id)) m.set(id, { file: c.path, module: ctx.journeyModule.get(c.path) || null });
  }
  return m;
}

function deriveWalkChecks(walks, ctx, at, d, contracts) {
  const checks = [];
  const ownedNames = new Set();
  const byId = contractsByJourneyId(contracts, ctx);
  for (const w of walks) {
    const jid = w.journey || '_';
    const meta = byId.get(jid) || { file: null, module: null };
    for (const s of Array.isArray(w.steps) ? w.steps : []) {
      const stepIndex = typeof s.n === 'number' ? s.n : null;
      for (const c of Array.isArray(s.checks) ? s.checks : []) {
        const raw = String(c.name || '');
        ownedNames.add(raw);
        const idx = raw.indexOf(': ');
        let id = journeyCheckId(jid, stepIndex, raw);
        let bump = 1;
        while (checks.some(x => x.id === id)) id = journeyCheckId(jid, stepIndex, raw) + `~${++bump}`;
        const detail = String(c.detail ?? '');
        // 1.2: the narrative check and the verdict check are the same measurement seen
        // twice. Stamping the id here lets the walk renderer follow a fault row to its
        // remediation instead of re-deriving the id from the display name.
        c.checkId = id;
        const check = {
          id,
          instrument: 'journey-runner',
          kind: KINDS.has(c.rung) ? c.rung : 'ui',
          module: meta.module,
          journey: jid,
          stepIndex,
          stepName: s.name || null,
          // Step pointer wins over journey pointer — the same precedence the runner uses.
          requirement: normReq(((Array.isArray(s.requirement) && s.requirement.length
                                 ? s.requirement : w.requirement) || []).join(', ')),
          title: idx > 0 ? raw.slice(idx + 2) : raw,
          verdict: V_JOURNEY[String(c.verdict).toUpperCase()] || 'fault',
          provenance: 'measured',
          detail,
          measuredAt: at,
          nonVacuity: {
            controlRan: !!d.positiveControl,
            note: d.positiveControl ? 'run included --positive-control'
                                    : 'positive control not run for this build',
          },
          evidence: [],
          blocks: [],
          // Kept so the guard test below matches the runner's own wording rather than
          // a reconstruction of it.
          sourceName: raw,
          derivedFrom: 'walks[]',
        };
        const shot = /screenshot ([\w.\-]+\.png)/.exec(detail);
        if (shot) check.evidence.push({ type: 'screenshot', path: relTo(ctx.outFile, `tests/e2e/artifacts/${shot[1]}`) });
        // The step's own screenshot is evidence of the page state these checks measured.
        // It is NEVER the verdict — see the walks[] constraint table in the schema.
        else if (s.shot && s.shot.file) check.evidence.push({ type: 'screenshot', path: relTo(ctx.outFile, s.shot.file) });
        checks.push(check);
      }
    }
  }
  return { checks, ownedNames };
}

// Derivation is only safe if it is checked. This emits one row per journey stating
// whether walks[] and results[] still tell the same story, and a run-level row when
// there is no walk to derive from at all.
function reconcileWalkAgainstResults(walks, results, byStep, ctx, at) {
  const mk = (id, verdict, title, detail) => ({
    id, instrument: 'journey-runner', kind: 'conformance', module: null,
    journey: null, stepIndex: null, stepName: null, requirement: null,
    title, verdict, provenance: 'measured', detail, measuredAt: at,
    nonVacuity: { controlRan: false, note: 'structural reconciliation; no product control applies' },
    evidence: [], blocks: [],
  });
  if (!walks.length) {
    if (!results.length) return [];
    return [mk('derivation/no-walk', 'fault',
      'checks[] could not be derived from walks[]',
      `${results.length} result row(s) were read, but the runner recorded no walks[] block, so ` +
      'checks[] was read straight out of results[] as it was before schema 1.1. The two ' +
      'structures are then unreconciled and can disagree without anything noticing.')];
  }
  const out = [];
  const byName = new Map();
  for (const r of results) byName.set(String(r.name || ''), r);
  for (const w of walks) {
    const jid = w.journey || '_';
    const walkChecks = (Array.isArray(w.steps) ? w.steps : [])
      .flatMap(s => (Array.isArray(s.checks) ? s.checks : []));
    const problems = [];
    for (const c of walkChecks) {
      const r = byName.get(String(c.name || ''));
      if (!r) { problems.push(`"${c.name}" is in the walk but absent from results[]`); continue; }
      const a = V_JOURNEY[String(c.verdict).toUpperCase()] || 'fault';
      const b = V_JOURNEY[String(r.verdict).toUpperCase()] || 'fault';
      if (a !== b) problems.push(`"${c.name}" is ${a} in the walk and ${b} in results[]`);
    }
    // The other direction: a results row whose step belongs to THIS journey but which
    // no walk step claims. That means the walk is not the whole truth for this journey.
    const stepNames = new Set((Array.isArray(w.steps) ? w.steps : []).map(s => s.name));
    for (const r of results) {
      const raw = String(r.name || '');
      if (walkChecks.some(c => String(c.name || '') === raw)) continue;
      const unprefixed = raw.replace(/^\[(GUARD|MF)\]\s*/, '').replace(/^NEGATIVE:\s*/, '');
      const p = unprefixed.indexOf(': ');
      const sn = p > 0 ? unprefixed.slice(0, p) : null;
      if (sn && stepNames.has(sn)) problems.push(`results[] row "${raw}" belongs to step "${sn}" but no walk step recorded it`);
    }
    out.push(mk(`derivation/${slug(jid)}/walk-is-the-source`,
      problems.length ? 'fail' : 'pass',
      'walks[] and results[] agree, so checks[] can be derived from one of them',
      problems.length
        ? `${problems.length} disagreement(s): ${problems.slice(0, 8).join('; ')}` +
          (problems.length > 8 ? ` … and ${problems.length - 8} more` : '')
        : `${walkChecks.length} walk check(s) each have a same-verdict twin in results[]; ` +
          'checks[] was derived from the walk.'));
  }
  return out;
}

// The walk is narrative, not verdict. Each step carries a rolled-up status ONLY so
// the render can colour it; the status is derived from the step's own checks and
// never from the screenshot, which is why `shot` and `status` are computed in
// separate places and a step with no shot still gets a status.
//
// Precedence is fault > fail > pass. A step whose data rung did not run is not a
// green step with a footnote — "we could not measure this" outranks "everything we
// did measure was fine", or the walk would read as a clean run through a page whose
// most important claim was never tested.
function collectWalks(d, checks) {
  const walks = Array.isArray(d.walks) ? d.walks : [];
  return walks.map(w => ({
    journey: w.journey || null,
    title: w.title || '',
    persona: w.persona || null,
    requirement: Array.isArray(w.requirement) ? w.requirement.slice().sort() : [],
    seeds: w.seeds && Object.keys(w.seeds).length ? w.seeds : null,
    steps: (Array.isArray(w.steps) ? w.steps : []).slice()
      .sort((a, b) => (a.n || 0) - (b.n || 0))
      .map(s => {
        const cs = Array.isArray(s.checks) ? s.checks : [];
        const has = v => cs.some(c => c.verdict === v);
        return {
          n: s.n ?? null,
          name: s.name || '',
          requirement: Array.isArray(s.requirement) ? s.requirement.slice().sort() : [],
          actions: Array.isArray(s.actions) ? s.actions : [],
          expects: s.expects || null,
          reached: s.reached === undefined ? null : s.reached,
          // A step that recorded no checks at all is `fault`, not `pass`. An empty
          // list passing would be the `[].every()` bug wearing a different hat.
          status: cs.length === 0 ? 'fault'
                : has('INVALID') ? 'fault'
                : has('FAIL') ? 'fail' : 'pass',
          // checkId is stamped on the RAW check by deriveWalkChecks (which runs first,
          // on the same objects). Carrying it here is what lets the walk renderer follow
          // a fault row to its remediation instead of re-deriving the id from the name.
          checks: cs.map(c => ({ rung: c.rung, name: c.name,
                                 verdict: V_JOURNEY[c.verdict] || 'fault', detail: c.detail || '',
                                 checkId: c.checkId || null })),
          shot: s.shot || null,
          ms: s.ms ?? null,
        };
      }),
  })).sort((a, b) => String(a.journey).localeCompare(String(b.journey)));
}

// ============================================================================
// SOURCE 1c — the two DESIGN rungs, and the page block that joins them to the walk
// ============================================================================
// "UI test" in this project means "does the screen look the way we said it would",
// not "did a unit test pass". Two rungs answer that, and they are different questions:
//
//   rung 6 — does this page match ITS OWN wireframe?      (skipped when none was drawn)
//   rung 7 — does it match general design practice?       (always runs; needs no wireframe)
//
// design-audit.js measures both, keyed by `page`. The walk knows steps, not pages, so
// nothing joined them until 1.1. resolvePage() below is that join.

// design-audit files rung 6 under its own id namespace and puts three class-corpus
// checks there too. In THIS contract rung 6 is the wireframe question alone; the class
// checks are general practice and belong to rung 7. Encoded here rather than in prose
// so the selftest can assert it.
const RUNG6_ID = page => `design-audit/rung6/wireframe-conformance/${page}`;
const READ_ID  = page => `design-audit/read/${page}/complete`;

function collectDesignAudit(input, ctx) {
  const checks = [];
  const byPage = new Map();          // page -> { rung6, rung7: [...], partiallyRead, wireframe }
  if (!input || input.status !== 'ok') {
    return { checks, byPage, instrument: {
      name: 'design-audit', verdict: 'fault', reason: faultReason(input || { status: 'missing', path: INPUTS.designAudit }),
      source: INPUTS.designAudit, canExpressFault: true, evidenceStrength: 'strong',
      note: 'rungs 6 and 7 are the only instruments that look at whether a page LOOKS right; ' +
            'without them the report says nothing about design in either direction' } };
  }
  const d = input.data || {};
  const wireframeOf = new Map();
  for (const p of Array.isArray(d.perPage) ? d.perPage : []) {
    wireframeOf.set(p.page, p.wireframe ? `${INPUTS.wireframeDir}/${p.wireframe}` : null);
  }
  for (const c of Array.isArray(d.checks) ? d.checks : []) {
    const check = {
      id: c.id, instrument: 'design-audit',
      kind: KINDS.has(c.kind) ? c.kind : 'ui',
      module: c.module || null, journey: null, stepIndex: null, stepName: null,
      page: c.page || null,
      requirement: normReq(c.requirement),
      title: c.title || c.id,
      // A partially-read page (mxcli #891 — the ELK tree drops content slots) is a
      // FAULT and stays one. Every class finding under it is a lower bound, so a green
      // there would be a green computed from a page we only half saw.
      verdict: ['pass', 'fail', 'fault', 'skipped', 'manual'].includes(c.verdict) ? c.verdict : 'fault',
      provenance: c.provenance === 'judged' ? 'judged' : 'measured',
      detail: String(c.detail ?? c.reason ?? ''),
      measuredAt: c.measuredAt || (d.run && d.run.finishedAt) || null,
      nonVacuity: c.nonVacuity || { controlRan: !!d.positiveControl, note: 'see design-audit --positive-control' },
      evidence: Array.isArray(c.evidence) ? c.evidence : [],
      blocks: [],
      tags: Array.isArray(c.tags) ? c.tags : [],
    };
    if (c.reason) check.reason = c.reason;
    checks.push(check);
    if (!check.page) continue;
    if (!byPage.has(check.page)) {
      byPage.set(check.page, { rung6: null, rung7: [], partiallyRead: false,
                               wireframe: wireframeOf.has(check.page) ? wireframeOf.get(check.page) : null });
    }
    const e = byPage.get(check.page);
    if (check.id === RUNG6_ID(check.page)) e.rung6 = check.verdict;
    else e.rung7.push({ id: check.id, title: check.title, verdict: check.verdict, detail: check.detail });
    if (check.id === READ_ID(check.page) && check.verdict === 'fault') e.partiallyRead = true;
  }
  // #891 degrade, applied after the fact so it cannot be missed by check ordering.
  for (const [, e] of byPage) {
    if (e.partiallyRead && e.rung6 === 'pass') e.rung6 = 'fault';
    if (e.rung6 === null) e.rung6 = 'fault';   // the page was audited but never asked the question
    e.rung7.sort((a, b) => a.id.localeCompare(b.id));
  }
  const tally = v => checks.filter(c => c.verdict === v).length;
  return { checks, byPage, instrument: {
    name: 'design-audit', verdict: 'pass', source: input.path, log: input.path,
    canExpressFault: true, evidenceStrength: d.run && d.run.mode === 'static-only' ? 'weak' : 'strong',
    checksEmitted: checks.length,
    mode: (d.run && d.run.mode) || null,
    note: (d.run && d.run.mode === 'static-only'
      ? 'ran STATIC-ONLY: it read the model, not a rendered page. Every check that needs a ' +
        'browser (a11y, overflow, structure) is `skipped`, which is not a pass. '
      : '') +
      `rung 6 = wireframe conformance, rung 7 = general design practice; ` +
      `${tally('pass')} pass / ${tally('fail')} fail / ${tally('fault')} fault / ${tally('skipped')} skipped`,
  } };
}

// ── page scope: the denominator ─────────────────────────────────────────────
function collectPageScope(input) {
  if (!input || input.status !== 'ok') {
    return { ok: false, inScope: [], orphans: [], roles: [], roleSets: [],
             instrument: { name: 'page-scope', verdict: 'fault',
               reason: faultReason(input || { status: 'missing', path: INPUTS.pageScope }),
               source: INPUTS.pageScope, canExpressFault: true, evidenceStrength: 'strong',
               note: 'without the in-scope page list there is no denominator, and a report can ' +
                     'only say "everything we walked was fine" — which is also true of a run ' +
                     'that walked one page' } };
  }
  const d = input.data || {};
  const inScope = Array.isArray(d.inScope) ? d.inScope.slice().sort() : [];
  const roles = Array.isArray(d.roles) ? d.roles : [];

  // ── one report per distinct SET, never one per role ───────────────────────
  // MEASURED on this project: 9 roles resolve to 4 distinct sets, and 6 MxRole_*
  // personas see byte-identical pages. Emitting six identical persona reports would
  // present as thoroughness the very fact that security does not differentiate them.
  const byKey = new Map();
  for (const r of roles) {
    const pages = (Array.isArray(r.pages) ? r.pages : []).slice().sort();
    const key = pages.join('|') || '(empty)';
    if (!byKey.has(key)) byKey.set(key, { key, roles: [], pages, empty: pages.length === 0 });
    byKey.get(key).roles.push(r.role);
  }
  const roleSets = Array.from(byKey.values())
    .map(s => ({ ...s, roles: s.roles.slice().sort(), pageCount: s.pages.length }))
    .sort((a, b) => b.pageCount - a.pageCount || a.roles[0].localeCompare(b.roles[0]));
  roleSets.forEach((s, i) => { s.id = `set-${i + 1}`; });

  const shared = roleSets.filter(s => s.roles.length > 1 && !s.empty);
  const checks = [{
    id: 'scope/security-does-not-differentiate-personas',
    instrument: 'page-scope', kind: 'conformance', module: null, page: null,
    journey: null, stepIndex: null, stepName: null, requirement: null,
    title: 'each persona sees a page set of its own',
    verdict: shared.length ? 'fail' : 'pass',
    provenance: 'measured',
    detail: shared.length
      ? `${roles.length} role(s) resolve to ${roleSets.length} distinct in-scope page set(s). ` +
        shared.map(s => `${s.roles.length} roles (${s.roles.join(', ')}) see the identical ` +
                        `${s.pageCount} page(s)`).join('; ') +
        '. This is a finding about the model, not about the report: security is not ' +
        'differentiating these personas, so a per-persona walk cannot demonstrate that it does. ' +
        'One report is emitted per SET — the identical ones are one report, named for all the ' +
        'roles that share it.'
      : `${roles.length} role(s), ${roleSets.length} distinct set(s), none shared.`,
    measuredAt: d.generatedAt || null,
    nonVacuity: { controlRan: false, note: 'derived from the model catalog, not from a running app' },
    evidence: [{ type: 'contract', path: INPUTS.pageScope }],
    blocks: [],
  }];
  // page-scope.json reports its own count. Where its arithmetic and ours differ, both
  // numbers go on the page — silently preferring one is how a wrong denominator survives.
  if (typeof d.distinctRolePageSets === 'number' && d.distinctRolePageSets !== roleSets.length) {
    checks.push({
      id: 'scope/distinct-role-set-count-agrees',
      instrument: 'page-scope', kind: 'conformance', module: null, page: null,
      journey: null, stepIndex: null, stepName: null, requirement: null,
      title: 'page-scope.json\'s own set count matches the sets in its data',
      verdict: 'fail', provenance: 'measured',
      detail: `${INPUTS.pageScope} declares distinctRolePageSets: ${d.distinctRolePageSets}, but its ` +
              `roles[] array contains ${roleSets.length} distinct page set(s) ` +
              `(${roleSets.map(s => `${s.roles.join('+')}=${s.pageCount}`).join(', ')}). ` +
              'The difference is the empty set: a role that can reach nothing in scope is still a ' +
              'distinct set, and dropping it from the count hides a role with no reachable surface.',
      measuredAt: d.generatedAt || null,
      nonVacuity: { controlRan: false, note: 'arithmetic on the input file' },
      evidence: [{ type: 'contract', path: INPUTS.pageScope }], blocks: [],
    });
  }

  return {
    ok: true, inScope, roles, roleSets,
    orphans: Array.isArray(d.orphans) ? d.orphans : [],
    counts: d.counts || null,
    generatedAt: d.generatedAt || null,
    checks,
    instrument: {
      name: 'page-scope', verdict: 'pass', source: input.path,
      canExpressFault: true, evidenceStrength: 'strong',
      note: `${inScope.length} in-scope page(s), ${(d.orphans || []).length} classified orphan(s), ` +
            `${roles.length} role(s) → ${roleSets.length} distinct set(s)`,
      pagesInScope: inScope.length,
    },
  };
}

// ── the widget → page join ──────────────────────────────────────────────────
// A walk step says `.mx-name-dvScanCtx`; only the model knows that three pages declare
// a widget with that name. Resolution is an INTERSECTION and never a pick: where it
// stays ambiguous the page is null and the design rungs for that step are `fault`, on
// the same principle as everywhere else here — a joined-to-the-wrong-page design finding
// is worse than an admitted hole.
function mxNames(sel) {
  const out = [];
  const re = /\.mx-name-([A-Za-z0-9_]+)/g;
  let m;
  while ((m = re.exec(String(sel || '')))) out.push(m[1]);
  return out;
}

function resolvePage(step, runActions, widgetIndex, inScopeSet) {
  const pagesFor = n => {
    const v = widgetIndex && widgetIndex[n];
    return Array.isArray(v) && v.length ? v : null;
  };
  // Signals about the page you are ON: the landing guard and the widgets asserted visible.
  const own = [];
  own.push(...mxNames(step.expects && step.expects.landsOn));
  for (const c of Array.isArray(step.checks) ? step.checks : []) {
    const m = /:\s*widget ([A-Za-z0-9_]+)$/.exec(String(c.name || ''));
    if (m) own.push(m[1]);
  }
  const used = [];
  let cand = null;
  for (const n of Array.from(new Set(own)).sort()) {
    const p = pagesFor(n);
    if (!p) continue;
    used.push(n);
    cand = cand === null ? p.slice() : cand.filter(x => p.includes(x));
    if (!cand.length) break;
  }
  if (cand === null || !cand.length) {
    return { qualifiedName: null, candidates: [], resolvedBy: null, usedSelectors: used,
             why: cand === null
               ? 'no widget name on this step resolves to a page in the model catalog'
               : `the widgets asserted on this step (${used.join(', ')}) share no page — the step ` +
                 'either spans two pages or the catalog is stale' };
  }
  if (cand.length === 1) {
    return { qualifiedName: cand[0], candidates: cand, resolvedBy: 'widget-intersection', usedSelectors: used };
  }
  // Tie-break 1: an out-of-scope orphan is not where a walked persona is standing.
  const scoped = cand.filter(p => inScopeSet.has(p));
  if (scoped.length === 1) {
    return { qualifiedName: scoped[0], candidates: cand, resolvedBy: 'widget-intersection + in-scope',
             usedSelectors: used };
  }
  const narrowed = scoped.length ? scoped : cand;
  // Tie-break 2 (WEAK, and labelled weak): the actions performed anywhere in this
  // contiguous run of steps that share a landing selector act on the page you are on.
  // Applied greedily and skipping any that would empty the set, because a navigation
  // click is issued from the PREVIOUS page.
  let acc = narrowed.slice();
  const actUsed = [];
  for (const n of runActions) {
    const p = pagesFor(n);
    if (!p) continue;
    const next = acc.filter(x => p.includes(x));
    if (!next.length) continue;
    if (next.length < acc.length) { acc = next; actUsed.push(n); }
  }
  if (acc.length === 1) {
    return { qualifiedName: acc[0], candidates: cand,
             resolvedBy: 'widget-intersection + in-scope + same-page actions (WEAK)',
             usedSelectors: used.concat(actUsed) };
  }
  return { qualifiedName: null, candidates: narrowed, resolvedBy: null, usedSelectors: used,
           why: `${narrowed.length} pages declare every widget this step asserts ` +
                `(${narrowed.join(', ')}) and nothing in the walk distinguishes them` };
}

// Attach the page block to every walk step, and emit one auditable check per step
// saying whether the join succeeded. Returns the checks; mutates walks in place.
function attachPages(walks, designByPage, scope, widgetIndex, at) {
  const inScopeSet = new Set(scope.inScope || []);
  const rolesFor = new Map();
  for (const r of scope.roles || []) {
    for (const p of r.pages || []) {
      if (!rolesFor.has(p)) rolesFor.set(p, []);
      rolesFor.get(p).push(r.role);
    }
  }
  const orphanOf = new Map((scope.orphans || []).map(o => [o.page, o]));
  const checks = [];
  const walked = new Set();

  for (const w of walks) {
    const steps = Array.isArray(w.steps) ? w.steps : [];
    // A contiguous run of steps sharing a landing selector is one page visit.
    const runOf = steps.map(s => (s.expects && s.expects.landsOn) || null);
    for (let i = 0; i < steps.length; i++) {
      const s = steps[i];
      const runActions = [];
      for (let k = 0; k < steps.length; k++) {
        if (runOf[k] !== runOf[i] || runOf[i] === null) continue;
        for (const a of Array.isArray(steps[k].actions) ? steps[k].actions : []) {
          runActions.push(...mxNames(a.selector));
        }
      }
      const r = resolvePage(s, Array.from(new Set(runActions)).sort(), widgetIndex, inScopeSet);
      const qn = r.qualifiedName;
      const da = qn ? designByPage.get(qn) : null;
      if (qn) walked.add(qn);
      const orphan = qn ? orphanOf.get(qn) : null;

      s.page = {
        qualifiedName: qn,
        // `role` is an ARRAY and the schema says so: a page is visible to N module
        // roles, and a scalar would force this file to pick one of them arbitrarily.
        role: qn ? (rolesFor.get(qn) || []).slice().sort() : [],
        inScope: qn ? inScopeSet.has(qn) : null,
        orphan: orphan ? { classification: orphan.classification, note: orphan.note } : null,
        wireframe: da ? da.wireframe : null,
        // Unresolved page ⇒ the design rungs are not "fine", they are unjoinable.
        rung6: da ? da.rung6 : 'fault',
        rung7: da ? da.rung7 : [],
        resolvedBy: r.resolvedBy,
        candidates: r.candidates,
        usedSelectors: r.usedSelectors,
        why: qn ? null : (r.why || 'unresolved'),
      };

      checks.push({
        id: `page-join/${slug(w.journey || '_')}/step${s.n == null ? '?' : s.n}`,
        instrument: 'page-join', kind: 'conformance', module: null,
        page: qn, journey: w.journey || null, stepIndex: s.n == null ? null : s.n,
        stepName: s.name || null, requirement: null,
        title: 'this walk step is attributable to a page in the model',
        verdict: qn ? (r.resolvedBy && /WEAK/.test(r.resolvedBy) ? 'manual' : 'pass') : 'fault',
        provenance: 'measured',
        detail: qn
          ? `resolved to ${qn} by ${r.resolvedBy} from ${r.usedSelectors.join(', ') || 'no selector'}` +
            (/WEAK/.test(r.resolvedBy || '')
              ? '. This tie-break is a heuristic, not a measurement: it assumes an action ' +
                'issued during a page visit targets that page. A human should confirm it before ' +
                'the design findings below are attributed to this page.'
              : '')
          : `NOT resolved: ${r.why}. The design rungs for this step are therefore \`fault\` — ` +
            'not skipped and not clean. Attaching a wireframe verdict to a page we could not ' +
            'identify would be worse than admitting the hole.',
        measuredAt: at,
        nonVacuity: { controlRan: false, note: 'a model-catalog join, not a runtime measurement' },
        evidence: [{ type: 'contract', path: INPUTS.catalog }], blocks: [],
      });
    }
  }
  return { checks, walked };
}

// ── the uncovered remainder — the honest headline ───────────────────────────
// 19 pages in scope, 5 journeys. Whatever the journeys did not walk is not "untested",
// it is unknown, and it is listed under the journey that should have covered it.
function collectPageCoverage(scope, walked, journeysByModule, designByPage, at) {
  if (!scope.ok) return { checks: [], pageCoverage: null };
  const checks = [];
  const uncovered = [];
  const journeyOwning = mod => (journeysByModule.get(mod) || []);

  for (const page of scope.inScope) {
    const mod = String(page).split('.')[0];
    const owners = journeyOwning(mod);
    if (walked.has(page)) continue;
    uncovered.push({ page, module: mod, journeys: owners });
    const da = designByPage.get(page) || null;
    checks.push({
      id: `scope/uncovered/${page}`,
      instrument: 'page-scope', kind: 'ui', module: mod, page,
      journey: owners.length ? owners[0] : null, stepIndex: null, stepName: null,
      requirement: null,
      title: `${page} was walked by a journey`,
      verdict: 'fault',
      provenance: 'declared', notRun: true,
      detail: owners.length
        ? `in scope, and ${owners.join(', ')} is the journey that should have covered it — no ` +
          'walk step in this run resolved to this page. Nothing is known about its behaviour ' +
          'in either direction.'
        : `in scope, and NO journey exists for module ${mod} at all. This page has never been ` +
          'walked by anything; its behaviour is unknown, not untested.' +
          (da ? ` The design rungs did look at it (rung 6 ${da.rung6}), which says how it is ` +
                'built, never whether it works.' : ''),
      measuredAt: at,
      nonVacuity: { controlRan: false, note: 'check did not run' },
      evidence: [{ type: 'contract', path: INPUTS.pageScope }], blocks: [],
    });
  }
  const byJourney = new Map();
  for (const u of uncovered) {
    const key = u.journeys.length ? u.journeys.join(', ') : `(no journey for ${u.module})`;
    if (!byJourney.has(key)) byJourney.set(key, []);
    byJourney.get(key).push(u.page);
  }
  return {
    checks,
    pageCoverage: {
      inScope: scope.inScope.length,
      walked: scope.inScope.filter(p => walked.has(p)).length,
      uncovered: uncovered.length,
      // A page a walk resolved to that is NOT in scope is its own oddity, kept visible.
      walkedOutOfScope: Array.from(walked).filter(p => !scope.inScope.includes(p)).sort(),
      byJourney: Array.from(byJourney.entries())
        .map(([journey, pages]) => ({ journey, pages: pages.sort() }))
        .sort((a, b) => a.journey.localeCompare(b.journey)),
      orphans: scope.orphans,
      generatedAt: scope.generatedAt,
    },
  };
}

// ============================================================================
// SOURCE 1b — journey-findings-control.json (non-vacuity, per rung)
// ============================================================================
// The claim this instrument makes is NOT "the app works". It is "when the app
// stops working, this harness says so" — and it is a claim about each RUNG
// separately, because the rungs fail independently.
//
// MEASURED 2026-08-14, and the reason this is per-rung rather than a boolean:
// the first control implementation broke one thing (step 1's landing selector)
// and reported "assertions can fail" for the whole journey. Breaking step 1
// stops the walk, so the trace, data and outcome rungs were never challenged —
// 20 of the 24 results in the real run. A single boolean licensed a claim about
// all of them from evidence about one.
//
// So `positiveControl: true` in the file is NOT the proof. It only says the flag
// was passed. The proof is one row per rung, each requiring that THE TARGETED
// check failed. A rung with no row is UNPROVEN, which is a fault (absent), never
// a pass — the same discipline INVALID gets everywhere else in this pipeline.
const CONTROL_RUNGS = [
  ['ui-landing',     'the landing guard that stops the walk'],
  ['ui-text',        'what the screen says'],
  ['trace-order',    'microflow span ORDER, not mere existence'],
  ['trace-negative', 'the negative trace claim (mustNotFire)'],
  ['data-delta',     'the row-count delta'],
  ['data-target',    'mustPointAt — the association target, not its set-ness'],
  ['outcome',        'the end-to-end outcome query'],
];

function collectControl(input, ctx) {
  const checks = [];
  const mk = (verdict, reason, extra = {}) => ({
    name: 'positive-control', verdict, reason,
    source: input && input.path || INPUTS.journeyFindingsControl,
    canExpressFault: true, evidenceStrength: 'strong',
    note: 'proves the harness, not the product; one row per rung, unproven → fault',
    ...extra,
  });

  if (!input || input.status !== 'ok') {
    return { checks, instrument: mk('fault',
      'no control run on record — no assertion in this harness has been observed to fail on purpose, ' +
      'so every green it reports is unproven') };
  }
  const d = input.data || {};
  if (!d.positiveControl) {
    return { checks, instrument: mk('fault',
      `${input.path} exists but is not a control run (positiveControl is not true) — ` +
      'it is most likely a copy of a real walk, which proves nothing about non-vacuity') };
  }

  const rows = (Array.isArray(d.results) ? d.results : []).filter(r => r.rung === 'control');
  let proven = 0;
  for (const [rung, what] of CONTROL_RUNGS) {
    // The runner names control rows "<journey> · <rung>: <description>".
    const row = rows.find(r => typeof r.name === 'string' && r.name.includes(`· ${rung}:`));
    const id = `control/${slug(rung)}`;
    if (!row) {
      checks.push({ id, instrument: 'positive-control', kind: 'control', rung: 'control', verdict: 'fault',
        name: `${rung} — ${what}`, provenance: 'notRun',
        detail: 'no control mutant exists for this rung; it has never been observed failing',
        requirement: null, evidence: [{ type: 'contract', ref: 'controlMutants() in journey-runner.js' }] });
      continue;
    }
    const ok = row.verdict === 'PASS';
    if (ok) proven++;
    checks.push({ id, instrument: 'positive-control', kind: 'control', rung: 'control',
      verdict: ok ? 'pass' : 'fail',
      name: `${rung} — ${what}`, provenance: 'measured',
      detail: row.detail || (ok ? 'the broken precondition was caught by the targeted check'
                                : 'the mutant did not fail on the targeted check'),
      requirement: null,
      evidence: [{ type: 'log', ref: input.path }] });
  }

  const all = proven === CONTROL_RUNGS.length;
  return { checks, instrument: mk(all ? 'pass' : 'fail',
    all ? `all ${proven} rungs proven non-vacuous — each broken precondition was caught by its own targeted check`
        : `${proven}/${CONTROL_RUNGS.length} rungs proven; the rest are UNPROVEN — greens on those rungs are not evidence`,
    { rungsProven: proven, rungsTotal: CONTROL_RUNGS.length, capturedAt: d.capturedAt || null }) };
}

// ============================================================================
// SOURCE 2 — findings.json / findings-mobile.json (the walkthrough dialect)
// ============================================================================

function walkthroughInstrument(name, input, extra) {
  if (input.status !== 'ok')
    return { name, verdict: 'fault', reason: faultReason(input), source: input.path,
             canExpressFault: false, evidenceStrength: 'weak' };
  return {
    name,
    verdict: 'pass',
    rc: null, elapsedSec: null, log: input.path, source: input.path,
    // ── Machine-readable weakness (requirement 4) ────────────────────────────
    // This dialect has two states, not five. It CANNOT say "did not run", so a page
    // the harness never reached leaves no trace and its absent checks are simply not
    // in the file. A `pass` from here is therefore weaker evidence than a `pass` from
    // journey-runner, and the renderer must be able to see that without reading a
    // comment.
    canExpressFault: false,
    evidenceStrength: 'weak',
    expressibleVerdicts: ['pass', 'fail'],
    note: 'source enum is pass/fail only — it cannot express "did not run", so a page ' +
          'the harness never reached is silently absent rather than reported as fault. ' +
          'Greens from this instrument are weaker evidence than journey-runner greens.',
    ...extra,
  };
}

function collectWalkthrough(input, instName, tags, ctx) {
  const checks = [];
  if (input.status !== 'ok') return { checks, instrument: walkthroughInstrument(instName, input) };
  const d = input.data || {};
  const target = d.target || instName;
  const at = d.capturedAt || null;
  const mk = (idTail, kind, title, verdict, detail, evidence, pageKey) => ({
    id: `walkthrough/${slug(target)}/${idTail}`,
    instrument: instName,
    kind, module: null, journey: null,
    stepIndex: null, stepName: pageKey || null,
    requirement: null,                       // this dialect carries no BRD pointers at all
    title, verdict, provenance: 'measured',
    detail: String(detail ?? ''), measuredAt: at,
    nonVacuity: { controlRan: false, note: 'this instrument has no positive control' },
    evidence: evidence || [], blocks: [],
    tags,
  });

  for (const p of d.pages || []) {
    const pk = slug(p.key || p.label);
    const shot = p.screenshot
      ? [{ type: 'screenshot', path: relTo(ctx.outFile, `tests/e2e/artifacts/${p.screenshot}`) }]
      : [];
    for (const w of p.widgets || [])
      checks.push(mk(`${pk}/widget/${slug(w.name)}`, 'ui', `${p.label || p.key}: widget ${w.name}`,
                     V_WALK[w.status] || 'fault', w.detail || w.status, shot, p.key));
    for (const q of p.oqlRows || [])
      checks.push(mk(`${pk}/oql/${slug(q.label)}`, 'data', `${p.label || p.key}: ${q.label}`,
                     q.pass === true ? 'pass' : q.pass === false ? 'fail' : 'fault',
                     q.detail || `value ${q.value}`,
                     [...shot, { type: 'query', sql: q.sql, value: String(q.value ?? '') }], p.key));
    (p.steps || []).forEach((s, i) =>
      checks.push(mk(`${pk}/step/${pad2(i + 1)}-${slug(s.label)}`, 'ui', `${p.label || p.key}: ${s.label}`,
                     V_WALK[s.status] || 'fault', s.detail, shot, p.key)));
  }

  const inst = walkthroughInstrument(instName, input, {
    checksEmitted: checks.length,
    user: d.user || null,
    userFallbackUsed: !!(d.configuredUser && d.user && d.configuredUser !== d.user),
  });
  return { checks, instrument: inst };
}

// ============================================================================
// SOURCE 3 — .claude/loop/verify/<Module>/summary.tsv
// ============================================================================
// Columns per the contract: instrument / verdict / rc / elapsed / log. MEASURED
// REALITY: the live file has FOUR columns (no elapsed). Parsed positionally with the
// tail treated as optional rather than assumed present — a normalizer that indexes
// [4] blindly emits `log: undefined` and the renderer shows no log link at all.
function collectLoop(summaries) {
  const instruments = [];
  const checks = [];
  for (const s of summaries) {
    if (s.file.status !== 'ok') {
      instruments.push({ name: `verify-loop/${s.module}`, verdict: 'fault',
                         reason: faultReason(s.file), source: s.file.path });
      continue;
    }
    const lines = s.file.text.split('\n').map(l => l.trim()).filter(Boolean)
      .filter(l => !/^instrument\t/i.test(l));
    if (!lines.length) {
      instruments.push({ name: `verify-loop/${s.module}`, verdict: 'fault',
                         reason: `${s.file.path} is empty — the verify loop wrote a summary with no rows`,
                         source: s.file.path });
      continue;
    }
    for (const line of lines) {
      const f = line.split('\t');
      const rawVerdict = (f[1] || '').trim().toUpperCase();
      const verdict = V_LOOP[rawVerdict] || 'fault';
      const rcRaw = (f[2] || '').trim();
      // A 5th column may be elapsed or may be the log; distinguish by shape rather
      // than by position, because the two live files disagree about the count.
      const rest = f.slice(3).map(x => x.trim()).filter(Boolean);
      const elapsed = rest.find(x => /^\d+(\.\d+)?$/.test(x));
      const log = rest.find(x => !/^\d+(\.\d+)?$/.test(x)) || null;
      const name = `verify-loop/${s.module}/${(f[0] || 'unnamed').trim()}`;
      instruments.push({
        name, verdict,
        rc: rcRaw === '' ? null : Number(rcRaw),
        elapsedSec: elapsed === undefined ? null : Number(elapsed),
        log, source: s.file.path,
        sourceVerdict: rawVerdict || null,
        canExpressFault: true, evidenceStrength: 'strong',
      });
      // A FINDING/FAULT row is also a check: it is a verdict about the system, not
      // only about the instrument, and the renderer's check list would otherwise be
      // silent about a red stack gate.
      if (verdict === 'fail' || verdict === 'fault') {
        checks.push({
          id: `loop/${slug(s.module)}/${slug((f[0] || 'unnamed').trim())}`,
          instrument: 'verify-loop', kind: /stack/i.test(f[0] || '') ? 'stack' : 'build',
          module: s.module, journey: null, stepIndex: null, stepName: null,
          requirement: null, title: (f[0] || 'unnamed').trim(), verdict,
          provenance: 'measured',
          detail: `verify loop reported ${rawVerdict} (rc ${rcRaw || 'n/a'})`,
          measuredAt: s.mtime,
          nonVacuity: { controlRan: false, note: 'no positive control for the verify loop' },
          evidence: log ? [{ type: 'log', path: relTo(process.env.__OUT || 'docs/report.json', log) }] : [],
          blocks: [],
        });
      }
    }
  }
  return { instruments, checks };
}

// ============================================================================
// SOURCE 4 — docs/conformance/report-<date>.tsv (newest by filename)
// ============================================================================
function collectConformance(input, ctx) {
  const checks = [];
  const rollup = new Map();
  if (input.status !== 'ok')
    return { checks, rollup, instrument: { name: 'conformance', verdict: 'fault',
             reason: faultReason(input), source: input.path } };

  const lines = input.text.split('\n').map(l => l.replace(/\s+$/, '')).filter(Boolean);
  const seen = new Set();
  let rows = 0;
  for (const line of lines) {
    const f = line.split('\t');
    if (/^module$/i.test((f[0] || '').trim())) continue;          // header
    const [mod, pointerRaw, stored, observed, verdictRaw, command] = f.map(x => (x || '').trim());
    if (!mod) continue;
    rows++;
    const rawVerdict = (verdictRaw || '').toUpperCase();
    const verdict = V_CONF[rawVerdict] || 'fault';

    // The pointer column IS a BRD pointer, decorated: "`/actors/*` (6)". Stripping
    // the decoration is reading it, not inventing it (rule 4). Anything that does not
    // start with "/" after stripping is NOT treated as a pointer — better null than a
    // synthesised one.
    const cleaned = pointerRaw.replace(/`/g, '').replace(/\s*\(\d+\)\s*$/, '').trim();
    const requirement = cleaned.startsWith('/') ? cleaned : null;

    let id = `conformance/${slug(mod)}/${slug(cleaned || pointerRaw)}`;
    let bump = 1;
    while (seen.has(id)) id = `conformance/${slug(mod)}/${slug(cleaned || pointerRaw)}~${++bump}`;
    seen.add(id);

    checks.push({
      id, instrument: 'conformance', kind: 'conformance',
      module: mod, journey: null, stepIndex: null, stepName: null,
      requirement,
      title: `${pointerRaw} — ledger says "${stored}"`,
      verdict, provenance: 'measured',
      detail: `stored=${stored} observed=${observed} (${rawVerdict})`,
      measuredAt: ctx.conformanceDate || null,
      nonVacuity: { controlRan: false, note: 'no positive control for conformance' },
      evidence: command ? [{ type: 'command', command }] : [],
      blocks: [],
    });

    if (!rollup.has(mod)) rollup.set(mod, { checked: 0, ok: 0, stale: 0, understated: 0, unrunnable: 0, other: 0 });
    const r = rollup.get(mod);
    r.checked++;
    if (rawVerdict === 'OK') r.ok++;
    else if (rawVerdict === 'STALE') r.stale++;
    else if (rawVerdict === 'UNDERSTATED') r.understated++;
    else if (rawVerdict === 'UNRUNNABLE') r.unrunnable++;
    else r.other++;
  }
  return {
    checks, rollup,
    instrument: { name: 'conformance', verdict: rows ? 'pass' : 'fault',
                  reason: rows ? undefined : `${input.path} contained no data rows`,
                  log: input.path, source: input.path, rowsRead: rows,
                  canExpressFault: true, evidenceStrength: 'strong' },
  };
}

// ============================================================================
// SOURCE 5 — architecture/modules/*/coverage-ledger.md
// ============================================================================
// Two independent numbers live in these files and they are allowed to disagree:
// the DECLARED status counts in the "BUILDABLE status counts" table, and the ACTUAL
// per-row status column of the BUILDABLE table. Parsing only the declared table would
// let a hand-edited row drift invisibly, so both are read and a mismatch is emitted as
// a real `coverage` check.
function parseLedger(file, module) {
  if (file.status !== 'ok') return { error: faultReason(file) };
  const t = file.text;
  const num = s => Number(String(s).replace(/[,_]/g, ''));

  const leafM = /→\s*\*\*([\d,]+)\s+leaves\*\*/.exec(t);
  const totalsM = /\|\s*BUILDABLE\s*\|\s*([\d,]+)\s*\|\s*([\d,]+)\s*\|/.exec(t);
  const checkM = /claimed\s+([\d,]+)\s*\/\s*([\d,]+)[\s\S]{0,20}?UNCLAIMED\s+([\d,]+)[\s\S]{0,20}?PHANTOM\s+([\d,]+)[\s\S]{0,30}?DOUBLE-CLAIMED\s+([\d,]+)/.exec(t);
  const genM = /(?:Regenerated|Generated)\s+(\d{4}-\d{2}-\d{2})/.exec(t);
  const brdM = /brd\/(F\d+)[-\w]*\.brd\.json/.exec(t) || /^#\s*(F\d+)/m.exec(t);

  // Declared counts table. Sliced heading-to-next-heading, NOT to the next blank
  // line: the blank line immediately after a markdown heading would end the slice
  // before the table starts, and the whole declared/actual reconciliation would
  // silently report "no declared counts" on every real ledger.
  const declared = {};
  const dSect = /\n##\s*BUILDABLE status counts[^\n]*\n([\s\S]*?)(?=\n##\s|$)/.exec(t);
  if (dSect) for (const m of dSect[1].matchAll(/^\|\s*([\w-]+)\s*\|\s*(\d+)\s*\|/gm))
    if (!/^status$/i.test(m[1])) declared[m[1]] = Number(m[2]);

  // Actual per-row statuses in the BUILDABLE table
  const actual = {};
  let rows = 0;
  const bSect = /\n##\s*BUILDABLE\s*\n([\s\S]*?)(?=\n##\s|\n$)/.exec(t);
  if (bSect) {
    for (const line of bSect[1].split('\n')) {
      if (!line.trim().startsWith('|')) continue;
      if (/^\|\s*-+/.test(line.trim())) continue;
      const cells = line.split('|').slice(1, -1).map(c => c.trim());
      if (cells.length < 2) continue;
      const st = cells[cells.length - 1].replace(/\*/g, '').trim();
      if (/^status$/i.test(st) || !st) continue;
      actual[st] = (actual[st] || 0) + 1;
      rows++;
    }
  }

  return {
    module,
    brd: brdM ? brdM[1] : null,
    leaves: {
      // Absent numbers stay null. A missing coverage-check line means the check was
      // never run for this module — 0 unclaimed would be a claim nobody made.
      total: leafM ? num(leafM[1]) : null,
      claimed: checkM ? num(checkM[1]) : null,
      unclaimed: checkM ? num(checkM[3]) : null,
      phantom: checkM ? num(checkM[4]) : null,
      doubleClaimed: checkM ? num(checkM[5]) : null,
    },
    rows: {
      buildable: totalsM ? num(totalsM[1]) : (rows || null),
      byStatus: {
        built: actual.built ?? 0,
        partial: actual.partial ?? 0,
        notBuilt: actual['not-built'] ?? 0,
      },
      byStatusDeclared: Object.keys(declared).length
        ? { built: declared.built ?? null, partial: declared.partial ?? null, notBuilt: declared['not-built'] ?? null }
        : null,
      parsed: rows,
    },
    generatedAt: genM ? genM[1] : null,
  };
}

function collectCoverage(ledgers, conformanceRollup, journeysByModule, ctx) {
  const coverage = [];
  const checks = [];
  const instruments = [];
  let bad = 0;
  for (const l of ledgers) {
    const p = parseLedger(l.file, l.module);
    if (p.error) {
      bad++;
      instruments.push({ name: `coverage-ledger/${l.module}`, verdict: 'fault',
                         reason: p.error, source: l.file.path });
      continue;
    }
    coverage.push({
      module: p.module, brd: p.brd,
      leaves: p.leaves, rows: p.rows,
      conformance: conformanceRollup.get(p.module) || null,
      journeys: (journeysByModule.get(p.module) || []).slice().sort(),
      source: l.file.path,
      generatedAt: p.generatedAt,
    });
    // Declared vs actual, as a check with a verdict rather than a silent preference.
    const dec = p.rows.byStatusDeclared;
    if (dec) {
      const same = ['built', 'partial', 'notBuilt'].every(k => dec[k] === null || dec[k] === p.rows.byStatus[k]);
      checks.push({
        id: `coverage/${slug(p.module)}/status-counts-reconcile`,
        instrument: 'coverage-ledger', kind: 'coverage',
        module: p.module, journey: null, stepIndex: null, stepName: null,
        requirement: null,
        title: 'ledger status-count table matches its own BUILDABLE rows',
        verdict: same ? 'pass' : 'fail', provenance: 'measured',
        detail: `declared built/partial/not-built = ${dec.built}/${dec.partial}/${dec.notBuilt}; ` +
                `counted from rows = ${p.rows.byStatus.built}/${p.rows.byStatus.partial}/${p.rows.byStatus.notBuilt}`,
        measuredAt: p.generatedAt,
        nonVacuity: { controlRan: false, note: 'arithmetic check over the ledger text' },
        evidence: [{ type: 'log', path: relTo(ctx.outFile, l.file.path) }],
        blocks: [],
      });
    }
    // "Nothing walks this module" is a measurement, and it is the one the renderer
    // most needs: a module with 86 buildable rows and zero journeys has no golden path.
    checks.push({
      id: `coverage/${slug(p.module)}/has-a-journey`,
      instrument: 'coverage-ledger', kind: 'coverage',
      module: p.module, journey: null, stepIndex: null, stepName: null,
      requirement: null,
      title: 'at least one journey walks this module',
      verdict: (journeysByModule.get(p.module) || []).length ? 'pass' : 'fault',
      provenance: 'measured',
      detail: (journeysByModule.get(p.module) || []).length
        ? `journeys: ${(journeysByModule.get(p.module) || []).join(', ')}`
        : 'no journey contract targets this module — its rows are unwalked, not passing',
      measuredAt: null,
      nonVacuity: { controlRan: false, note: 'presence check over journeys/' },
      evidence: [], blocks: [],
    });
  }
  instruments.push({
    name: 'coverage-ledger',
    verdict: ledgers.length === 0 ? 'fault' : bad ? 'fail' : 'pass',
    reason: ledgers.length === 0 ? `no coverage-ledger.md under ${INPUTS.modulesDir}/*/` : undefined,
    source: `${INPUTS.modulesDir}/*/coverage-ledger.md`,
    modulesRead: coverage.length,
    canExpressFault: false, evidenceStrength: 'weak',
    note: 'a ledger is a written claim, not a measurement; only the conformance run tests it',
  });
  return { coverage, checks, instruments };
}

// ============================================================================
// SOURCE 6 — deferrals.jsonl / run-ledger.jsonl
// ============================================================================
function parseJsonl(file) {
  const rows = [];
  const errors = [];
  (file.text || '').split('\n').forEach((l, i) => {
    if (!l.trim()) return;
    try { rows.push(JSON.parse(l)); } catch (e) { errors.push(`line ${i + 1}: ${e.message}`); }
  });
  return { rows, errors };
}

function collectDeferrals(file) {
  if (file.status !== 'ok')
    return { deferrals: [], instrument: { name: 'deferrals', verdict: 'fault',
             reason: faultReason(file), source: file.path } };
  const { rows, errors } = parseJsonl(file);
  const deferrals = rows.map((r, i) => ({
    id: r.id || `D-${pad2(i + 1)}`,
    question: r.question || null,
    position: r.position || null,
    requirement: normReq(r.requirement),
    reversalCost: r.reversalCost || null,
    // null on BOTH is UNRAISED. An agent recording its own assumption is not consent.
    consentBy: r.consentBy || null,
    consentAt: r.consentAt || null,
  })).sort((a, b) => String(a.id).localeCompare(String(b.id)));
  return {
    deferrals,
    instrument: {
      name: 'deferrals',
      verdict: errors.length ? 'fail' : rows.length ? 'pass' : 'fault',
      reason: errors.length ? `unparseable lines: ${errors.join('; ')}`
            : rows.length ? undefined
            : `${file.path} is empty — no banked questions were recorded, which is not the same as none existing`,
      source: file.path, rowsRead: rows.length,
    },
  };
}

function collectRunLedger(file) {
  if (file.status !== 'ok')
    return { instrument: { name: 'run-ledger', verdict: 'fault', reason: faultReason(file), source: file.path }, rows: [] };
  const { rows, errors } = parseJsonl(file);
  return {
    rows,
    instrument: {
      name: 'run-ledger',
      verdict: errors.length ? 'fail' : rows.length ? 'pass' : 'fault',
      reason: errors.length ? `unparseable lines: ${errors.join('; ')}`
            : rows.length ? undefined
            : `${file.path} is empty — no run was journalled, so the report cannot state when this run began`,
      source: file.path, rowsRead: rows.length,
    },
  };
}

// ============================================================================
// THE PURE CORE
// ============================================================================
// ============================================================================
// REMEDIATION — what would have been measured, why it wasn't, what it costs,
// and what to do about it. One classifier, pure, table-driven, selftested.
// ----------------------------------------------------------------------------
// MEASURED PROBLEM this closes (2026-08-18): report.html rendered 135 `fault`
// rows. Every one of them said, in effect, "did not run". None of them said what
// the instrument would have measured, what is therefore unproven, or what action
// makes it run next time. A third of the report was an unexplained shrug.
//
// Discipline kept: a remediation is DERIVED from the check, never invented. When
// no rule matches, the remediation says so in those words (`class: 'unclassified'`)
// rather than emitting plausible-sounding advice. An unclassified row is a gap in
// THIS table and must read as one.
// ============================================================================

/** Priority tier per remediation class. Lower runs first in nextSteps[].
 *  Tiers are about BLAST RADIUS, not about count: one severed landing guard that
 *  costs 31 unproven claims outranks 13 accessibility findings. */
const REMEDIATION_TIER = {
  // The guard is tier 1 and the checks it severed are tier 2, in that order on purpose:
  // the severed rows' own action is "fix the blocking check first", so listing them
  // above it told the reader to do nothing before telling them what to do.
  'journey-landing-guard-failed': 1,
  'journey-severed': 2,
  'ui-text-contradiction': 3,
  'trace-zero-spans': 4,
  'page-never-walked-no-journey': 5,
  'page-never-walked-journey-exists': 5,
  'design-partial-read': 6,
  'design-no-wireframe': 6,
  'page-join-weak': 6,
  'design-lower-bound': 7,
  'design-no-nav-route': 7,
  'design-invented-class': 8,
  'design-unmatched-class': 8,
  'design-never-promoted': 8,
  'design-wireframe-chrome': 8,
  'design-wireframe-conformance': 8,
  'design-a11y': 8,
  'design-structure': 8,
  'design-overflow': 8,
  'design-raw-class': 8,
  'walkthrough-fail': 9,
  'conformance-unrunnable': 10,
  'conformance-drift': 10,
  'scope-selfcheck': 10,
  'loop-stack': 10,
  unclassified: 99,
};

const rTier = (cls) => (REMEDIATION_TIER[cls] == null ? 99 : REMEDIATION_TIER[cls]);

/** The page or module this remediation acts on — used as the nextSteps[] group key
 *  for the classes that are per-target rather than project-wide. */
function remTarget(c) {
  return c.page || c.module || c.journey || null;
}

/**
 * @param {object} c        the check
 * @param {Map}    byId     every check by id, for following `blockedBy`
 * @returns {object|null}   remediation, or null for a pass
 */
function classifyRemediation(c, byId) {
  if (!c || c.verdict === 'pass') return null;
  const det = String(c.detail || '');
  const id = String(c.id || '');
  const title = String(c.title || '');
  const page = c.page || null;
  // A page's qualified name IS Module.Page, so a check with a page but no module still
  // knows its module. Without this the page-join rows said "the journey contract"
  // instead of naming the file the reader has to open.
  const mod = c.module || (page && page.indexOf('.') > 0 ? page.split('.')[0] : null);
  const R = (o) => Object.assign({
    class: 'unclassified', measures: null, why: null, blastRadius: null,
    action: null, actionKind: 'unknown', needsApproval: false, where: null,
  }, o);

  // ── 1. a landing guard that failed, and everything it severed ─────────────
  if (c.instrument === 'journey-runner' && c.verdict === 'fail' && /reached$/.test(title)) {
    const sel = (det.match(/^"([^"]+)"/) || [])[1] || null;
    const shot = (det.match(/screenshot (\S+\.png)/) || [])[1] || null;
    return R({
      class: 'journey-landing-guard-failed',
      measures: 'that the persona actually arrived on the page this step names, before ' +
                'any later rung was allowed to measure anything on it',
      why: 'the ready selector ' + (sel ? sel + ' ' : '') + 'never appeared within the ' +
           'step timeout' + (shot ? ' (see ' + shot + ')' : ''),
      blastRadius: 'the walk stopped here, so every later step and every rung below the ' +
                   'guard in ' + (c.journey || 'this journey') + ' is `fault`, not `pass`',
      action: 'Open ' + (mod ? 'journeys/' + mod + '.journey.json' : 'the journey contract') +
              ' and check step ' + (c.stepIndex == null ? '1' : c.stepIndex) + ' against the ' +
              'live app: either the navigation path does not reach ' +
              (page || 'the page') + ' for this persona (a security/nav finding), or ' +
              (sel ? 'the ready selector ' + sel + ' is wrong' : 'the ready selector is wrong') +
              ' (a contract finding). The screenshot distinguishes them: a rendered page with a ' +
              'different widget means the selector; a login or an empty shell means the route.',
      actionKind: 'journey',
      where: mod ? 'journeys/' + mod + '.journey.json' : null,
    });
  }
  // The runner's own roll-up row for a step it never reached. It carries no
  // `blockedBy` because it IS the step, so it must be matched before the generic
  // severed rule or it falls through to `unclassified`.
  if (c.instrument === 'journey-runner' && c.verdict === 'fault' &&
      /^not reached; nothing measured$/.test(det)) {
    return R({
      class: 'journey-severed',
      measures: 'every rung below the landing guard on this step — what the screen says, ' +
                'which microflows fired, what was written, and the journey outcome',
      why: 'the step\'s landing guard failed, so the walk stopped before any of them ran',
      blastRadius: 'the whole of ' + (c.journey || 'this journey') + ' below step ' +
                   (c.stepIndex == null ? '1' : c.stepIndex) + ' is unmeasured',
      action: 'Fix the landing guard for step ' + (c.stepIndex == null ? '1' : c.stepIndex) +
              ' of ' + (mod ? 'journeys/' + mod + '.journey.json' : 'this journey') +
              ' (see the journey-landing-guard-failed row for the same journey); every rung ' +
              'below it is measured automatically on the next run.',
      actionKind: 'journey',
      where: mod ? 'journeys/' + mod + '.journey.json' : null,
    });
  }
  if (c.verdict === 'fault' && c.blockedBy) {
    const g = byId.get(c.blockedBy);
    const expect = (det.match(/Expectation: (.+)$/) || [])[1] || null;
    return R({
      class: 'journey-severed',
      measures: expect ? title + ' — expectation: ' + expect : title,
      why: 'the walk never reached this check: ' +
           (g ? 'step ' + (g.stepIndex == null ? '?' : g.stepIndex) + ' ("' +
                (g.stepName || g.title) + '") failed first and the journey stopped'
              : 'an earlier check in this journey failed and the journey stopped'),
      blastRadius: 'this expectation is untested in both directions — it is not known to ' +
                   'hold and not known to be broken',
      action: 'Fix the blocking check first (' + c.blockedBy + '); this row needs no separate ' +
              'work and will be measured on the next run once the walk gets past it.',
      actionKind: 'journey',
      where: mod ? 'journeys/' + mod + '.journey.json' : null,
    });
  }

  // ── 2. the screen contradicting the data ──────────────────────────────────
  if (c.instrument === 'journey-runner' && c.verdict === 'fail' && /does NOT say/.test(title)) {
    const phrase = (title.match(/"([^"]+)"/) || [])[1] || null;
    return R({
      class: 'ui-text-contradiction',
      measures: 'that the page does not render ' + (phrase ? '"' + phrase + '"' : 'the forbidden text') +
                ' after the action — the rung that catches a correct machine with a lying screen',
      why: 'the phrase was rendered anyway. The data rungs on this same step passed, so this ' +
           'is a display defect, not a persistence defect',
      blastRadius: 'a user completing this step is told the opposite of what the database ' +
                   'contains. Nothing downstream is wrong; the screen is',
      action: 'On ' + (page || 'the page for this step') + ', find the widget that renders ' +
              (phrase ? '"' + phrase + '"' : 'this text') + ' — in Mendix this is normally a ' +
              'list-view / data-grid empty message whose datasource is not refreshed after the ' +
              'commit. Either refresh the object in the committing microflow or bind the empty ' +
              'message to the same datasource the commit writes. This is a MODEL change and ' +
              'needs approval before any mxcli exec.',
      actionKind: 'model',
      needsApproval: true,
      where: page,
    });
  }

  // ── 3. the trace rung ─────────────────────────────────────────────────────
  if (c.kind === 'trace' && /zero spans captured/.test(det)) {
    return R({
      class: 'trace-zero-spans',
      measures: 'which microflows fired for this step, in what ORDER, that the ones declared ' +
                '`mustNotFire` did not, and that no span — microflow OR activity — reported ERROR',
      why: 'the span capture returned an empty set for this step\'s time window. Empty is a ' +
           'fault and never a pass: `[].every()` is `true`, which is the exact vacuous green ' +
           'this rung exists to refuse. The detail string guesses "Jaeger down or OTel off"; ' +
           'that guess is not itself measured and should not be read as a diagnosis',
      blastRadius: 'NO microflow-ordering claim anywhere in this report is proven. In ' +
                   'particular a microflow whose activity spans are ERROR but whose own span ' +
                   'is OK — a caught error over a dead integration — is indistinguishable from ' +
                   'success on the UI and data rungs alone. Measured on this project 2026-08-03',
      action: 'Before re-running, verify the collector end to end, in this order: ' +
              '(1) `curl -s http://localhost:16686/api/services` must list the service name ' +
              '`tests/e2e/otel.js` queries (env OTEL_SERVICE, else project.config.js `otelService`); ' +
              '(2) `curl -s http://localhost:16686/api/services/<service>/operations` must ' +
              'contain "Microflow " / "Call microflow " entries — if it lists only ' +
              '"Call queued task" rows, microflow tracing is off in App Settings, which is a ' +
              'MODEL write and needs approval; ' +
              '(3) if both hold, the zero is a timing fault — the runtime was still warming or ' +
              'the batch exporter had not flushed inside capture()\'s retry window ' +
              '(tests/e2e/otel.js: retries=8, waitMs=1500). Re-run the journey against an ' +
              'already-warm app and do not raise DEMO_SPEED.',
      actionKind: 'harness',
      where: 'tests/e2e/otel.js',
    });
  }

  // ── 4. pages nothing ever walked ──────────────────────────────────────────
  if (id.startsWith('scope/uncovered/')) {
    const covered = /is the journey that should have covered it/.test(det);
    return R({
      class: covered ? 'page-never-walked-journey-exists' : 'page-never-walked-no-journey',
      measures: 'nothing. No behavioural rung ran against this page at all — not what it ' +
                'says, not which microflows it fires, not what it writes',
      why: covered
        ? 'a journey exists for ' + (mod || 'this module') + ' but no step in this run ' +
          'resolved to this page'
        : 'no journey file exists for module ' + (mod || '?') + ', so nothing could walk it',
      blastRadius: 'this page is UNKNOWN, not untested. It could be perfect or it could be ' +
                   'unreachable; this report distinguishes neither. The design rungs below ' +
                   'say how it is BUILT, never whether it WORKS',
      action: covered
        ? 'Add a step to journeys/' + (mod || '<Module>') + '.journey.json that navigates to ' +
          (page || 'this page') + ', with a `ready` selector and at least one data effect. ' +
          'A page in scope with no walk step is a hole in the golden path, not a formatting gap.'
        : 'Author journeys/' + (mod || '<Module>') + '.journey.json for the golden path through ' +
          (page || 'this page') + ' (persona, steps, `ready` selectors, declared microflows, ' +
          'declared writes, BRD pointers), then run ' +
          '`node tests/e2e/journey-runner.js journeys/' + (mod || '<Module>') + '.journey.json`. ' +
          'Per journey-proof: a module with a ledger and no journey is a fault, not a silent pass.',
      actionKind: 'journey',
      where: mod ? 'journeys/' + mod + '.journey.json' : null,
    });
  }

  // ── 5. the design rungs ───────────────────────────────────────────────────
  if (/no navigation route to this page in the Responsive profile/.test(det)) {
    return R({
      class: 'design-no-nav-route',
      measures: title,
      why: 'design-audit renders a page by following the Responsive navigation profile. ' +
           (page || 'This page') + ' has no entry there — it is opened from another page — so ' +
           'the auditor never had a rendered DOM to measure',
      blastRadius: 'the live-DOM rungs (accessibility, horizontal overflow, heading/landmark ' +
                   'structure) are absent for this page. The static rungs below it did run; ' +
                   'they read the model, not the browser',
      action: 'Teach tests/e2e/design-audit.js to reach ' + (page || 'this page') + ' the way a ' +
              'user does — navigate to its parent page and click through — rather than by ' +
              'direct route. Adding a navigation entry purely to satisfy the auditor would ' +
              'change the product to suit the instrument and is the wrong fix.',
      actionKind: 'harness',
      where: 'tests/e2e/design-audit.js',
    });
  }
  if (/^partially-read:/.test(det)) {
    const unread = (det.match(/Unread widgets: ([^.]+)\./) || [])[1] || null;
    const nums = det.match(/returned (\d+) tree nodes for (\d+) widgets/);
    return R({
      class: 'design-partial-read',
      measures: 'that the auditor saw the WHOLE page — every widget the page\'s own mdlSource ' +
                'declares — before pronouncing on its classes',
      why: 'DESCRIBE returned ' + (nums ? nums[1] + ' tree nodes for ' + nums[2] + ' declared widgets'
                                        : 'fewer nodes than the page declares') +
           '. This is mxcli #891: widgets inside data-grid customContent columns, control bars ' +
           'and some containers are not walked by the describe tree',
      blastRadius: 'EVERY class-based rung on ' + (page || 'this page') + ' is a LOWER BOUND. ' +
                   '"no invented classes" here means "none among the ones we could see" — a ' +
                   'green that cannot be trusted as a clean bill of health' +
                   (unread ? '. Unread: ' + unread : ''),
      action: 'Until mxcli #891 lands, audit the unread widgets from the page\'s mdlSource ' +
              'directly' + (unread ? ' (' + unread + ')' : '') + ' rather than from DESCRIBE, or ' +
              'extend tests/e2e/design-audit.js to parse mdlSource as a second source and ' +
              'reconcile the two. Do not silence the row — a lower bound reported as a pass is ' +
              'the failure mode this guard exists for.',
      actionKind: 'harness',
      where: page,
    });
  }
  if (/but the page is partially-read/.test(det)) {
    return R({
      class: 'design-lower-bound',
      measures: title,
      why: 'the sweep found nothing wrong, but it could not see the whole page (mxcli #891 — ' +
           'see the "ELK tree carries the whole page" row for ' + (page || 'this page') + ')',
      blastRadius: 'this rung is neither pass nor fail for ' + (page || 'this page') + '; the ' +
                   'unseen widgets could carry exactly the violation being swept for',
      action: 'Close the partial read for ' + (page || 'this page') + ' first (see the ' +
              'design-partial-read action for the same page); this row resolves itself once ' +
              'the auditor can see every widget.',
      actionKind: 'harness',
      where: page,
    });
  }
  // Rung 6 SKIPPED is "nobody ever drew this page". Explicitly NOT a pass — and the
  // action is a design deliverable, not a harness fix.
  if (c.instrument === 'design-audit' && c.verdict === 'skipped' &&
      /rung 6 does not apply to this page/.test(det)) {
    return R({
      class: 'design-no-wireframe',
      measures: 'whether ' + (page || 'this page') + ' looks the way it was designed to — the ' +
                'class-promotion diff against its wireframe',
      why: 'no wireframe was ever drawn for this page, so there is no drawing to diff against',
      blastRadius: 'rung 6 is absent for this page, permanently, until a wireframe exists. ' +
                   'Rung 7 still ran and still applies — general design practice does not ' +
                   'need a drawing',
      action: 'Draw design/wireframes/<page>.html for ' + (page || 'this page') +
              ' per the toolkit\'s design-artifacts.md (one annotated wireframe per screen), ' +
              'or record a deliberate decision that this page is exempt. Silence is the one ' +
              'option that is not honest.',
      actionKind: 'design',
      where: page,
    });
  }
  if (c.instrument === 'design-audit') {
    const rung = id.startsWith('design-audit/rung6') ? 6 : 7;
    // NOTE: digits are KEPT. Stripping them turned the axe rung's key "a11y" into "ay",
    // which matched nothing and filed 13 real accessibility failures as `unclassified`.
    const kindKey = (id.split('/')[2] || '').replace(/[^a-z0-9-]/g, '');
    const CLASSES = {
      'invented-class': ['design-invented-class',
        'Every class the page references is defined somewhere the browser can load it.',
        'Define the listed classes in design/ds.css and promote them to the deployed theme, or ' +
        'remove them from the page. A class that exists nowhere renders as nothing — the page ' +
        'looks unstyled and no build step complains.'],
      'unmatched-class': ['design-unmatched-class',
        'Every class the page references matches something in the deployed theme or ds.css.',
        'Reconcile the listed classes: either promote them from design/ds.css into the ' +
        'deployed theme, or change the page to use the sanctioned class.'],
      'never-promoted': ['design-never-promoted',
        'Classes authored in design/ds.css actually reached the deployed theme.',
        'Run the ds.css promotion step so the listed classes exist in the deployed theme; ' +
        'until then the page references styling that is not shipped.'],
      'wireframe-chrome': ['design-wireframe-chrome',
        'No wireframe-only annotation chrome (callout numbers, spec labels) survived into the ' +
        'real page.',
        'Remove the listed annotation-only classes from the page — they are drawing furniture, ' +
        'not product UI.'],
      'wireframe-conformance': ['design-wireframe-conformance',
        'The page\'s class set matches the wireframe it was built against (class-promotion diff, ' +
        'not a picture comparison).',
        'Diff the page against its wireframe in design/wireframes/ and decide, per class, ' +
        'whether the page or the wireframe is now correct — then change the one that is stale. ' +
        'Neither artifact wins automatically.'],
      a11y: ['design-a11y',
        'Zero serious or critical axe violations under wcag2a / wcag2aa / wcag21aa.',
        'Fix the named rule on this page. `color-contrast` is almost always a design-token ' +
        'choice, fixable in design/ds.css without touching the model; anything naming a widget ' +
        'role or label is a MODEL change and needs approval.'],
      structure: ['design-structure',
        'Exactly one h1 and at least one landmark region per page.',
        'Give the page one h1 and wrap its regions in landmarks. Two h1s normally means the ' +
        'layout supplies one and the page adds another — fix it in the layout, once, rather ' +
        'than on every page.'],
      overflow: ['design-overflow',
        'No horizontal overflow at 360 / 768 / 1440 CSS pixels.',
        'Find the element wider than its viewport at the failing width and constrain it. On a ' +
        'Mendix page this is usually a data grid with fixed column widths inside a responsive ' +
        'container.'],
      'raw-class-vs-designproperty': ['design-raw-class',
        'No raw CSS class is used where the widget already exposes a sanctioned design property.',
        'Replace the listed raw classes with the widget\'s design property. Raw classes bypass ' +
        'the design system and survive theme changes silently.'],
    };
    const m = CLASSES[kindKey];
    if (m) {
      return R({
        class: m[0],
        measures: m[1],
        why: det || 'the rung reported a violation',
        blastRadius: 'rung ' + rung + ' on ' + (page || 'this page') +
          (rung === 6 ? ' — the page does not demonstrably match the drawing it was built against'
                      : ' — a design-practice defect a user meets on every visit'),
        action: m[2] + (page ? ' Page: ' + page + '.' : ''),
        actionKind: 'design',
        where: page,
      });
    }
  }

  // ── 6. conformance and the ledger ─────────────────────────────────────────
  if (c.instrument === 'conformance' && /UNRUNNABLE/.test(det)) {
    return R({
      class: 'conformance-unrunnable',
      measures: 'whether the model actually contains what the coverage ledger claims for ' +
                (c.requirement || 'this ledger row'),
      why: 'the ledger row names no query the conformance runner can execute, so the claim ' +
           'was never tested in either direction',
      blastRadius: 'this ledger row is an unverified written claim. The ledger is already the ' +
                   'weakest instrument in the report (it cannot express "did not run"); an ' +
                   'unrunnable row is weaker still',
      action: 'In architecture/modules/' + (mod || '<Module>') + '/coverage-ledger.md, give the ' +
              'row ' + (c.requirement || '') + ' a verifying mxcli command (DESCRIBE / SHOW), or ' +
              'mark it explicitly unverifiable with the reason. Both are honest; leaving it ' +
              'UNRUNNABLE is not.',
      actionKind: 'ledger',
      where: mod ? 'architecture/modules/' + mod + '/coverage-ledger.md' : null,
    });
  }
  if (c.instrument === 'conformance') {
    const state = (det.match(/\((STALE|UNDERSTATED|OVERSTATED)\)/) || [])[1] || 'DRIFT';
    return R({
      class: 'conformance-drift',
      measures: 'that the coverage ledger\'s written status for ' + (c.requirement || 'this row') +
                ' matches what the model actually contains',
      why: det + ' — ' + (state === 'UNDERSTATED'
        ? 'the model has MORE than the ledger admits'
        : state === 'OVERSTATED' ? 'the ledger claims MORE than the model has'
        : 'the ledger and the model disagree'),
      blastRadius: 'governance, not runtime: the app may work fine, but the document the ' +
                   'project signs off against is wrong about it',
      action: 'Update architecture/modules/' + (mod || '<Module>') + '/coverage-ledger.md for ' +
              (c.requirement || 'this row') + ' to the observed state, or explain the ' +
              'divergence in the row. Evidence command is in this check\'s evidence[].',
      actionKind: 'ledger',
      where: mod ? 'architecture/modules/' + mod + '/coverage-ledger.md' : null,
    });
  }

  // ── 7. the weak walkthrough instruments ───────────────────────────────────
  // Which instruments these are is project.config's `walkthroughs` list, not two
  // literals: they are the project's own walkthrough scripts.
  if (WALKTHROUGH_BY_NAME.has(c.instrument)) {
    const wt = WALKTHROUGH_BY_NAME.get(c.instrument);
    return R({
      class: 'walkthrough-fail',
      measures: title,
      why: det || 'the walkthrough step reported a failure',
      blastRadius: 'this instrument\'s enum is pass/fail only — it cannot say "did not run" — ' +
                   'so a fail here is real but its greens are weak evidence. It also runs as ' +
                   'MxAdmin, which bypasses the role grants a journey would test',
      action: 'Reproduce with `node tests/e2e/' + wt.script +
              '` and read the step named above. If the behaviour is real, promote it to a journey ' +
              'step so the stronger rungs (data delta, association target, trace order) can ' +
              'measure it — a walkthrough fail is a lead, not a diagnosis.',
      actionKind: 'harness',
      where: 'tests/e2e/' + wt.script,
    });
  }

  // ── 8. scope self-checks and the loop stack ───────────────────────────────
  if (c.instrument === 'page-join') {
    return R({
      class: 'page-join-weak',
      measures: 'which page in the model a walk step actually stood on, by intersecting the ' +
                'widgets the step touched against the catalog',
      why: det || 'the intersection did not uniquely identify a page and the join fell back to ' +
                  'a weaker signal',
      blastRadius: 'the two design rungs shown beside this step are attributed to a page the ' +
                   'join only INFERRED. If the inference is wrong they describe a different ' +
                   'page than the screenshot does',
      action: 'Give the step a distinguishing widget in ' +
              (mod ? 'journeys/' + mod + '.journey.json' : 'the journey contract') +
              ' — one `ready` selector that exists on this page and no other — so the join is ' +
              'exact rather than inferred. A step that stays ambiguous is left null by design; ' +
              'it is never a guess.',
      actionKind: 'journey',
      where: mod ? 'journeys/' + mod + '.journey.json' : null,
    });
  }
  if (c.instrument === 'page-scope') {
    return R({
      class: 'scope-selfcheck',
      measures: title,
      why: det || 'the page-scope self-check disagreed with its own data',
      blastRadius: 'the denominator this whole report divides by. If the in-scope page set or ' +
                   'the role→page sets are wrong, every "N of M pages walked" statement above ' +
                   'is wrong by the same amount',
      action: 'Regenerate .claude/loop/page-scope.json and re-normalize. If the disagreement ' +
              'survives, it is a security-model finding, not a tooling one: personas that ' +
              'resolve to identical page sets mean the model draws no distinction between them.',
      actionKind: 'harness',
      where: '.claude/loop/page-scope.json',
    });
  }
  if (c.instrument === 'verify-loop') {
    return R({
      class: 'loop-stack',
      measures: title,
      why: det || 'the verify-loop stage reported a non-zero exit',
      blastRadius: 'the module\'s own verify stage is red; anything downstream of it in the ' +
                   'loop ran against an unverified build',
      action: 'Re-run the named stage and read its log (this check\'s evidence[] carries the ' +
              'path). Fix the stage before trusting any later gate for ' + (mod || 'this module') + '.',
      actionKind: 'harness',
      where: mod ? '.claude/loop/verify/' + mod : '.claude/loop/verify',
    });
  }

  // ── fallthrough: SAY SO. Never invent advice. ─────────────────────────────
  return R({
    class: 'unclassified',
    measures: title || null,
    why: det || null,
    blastRadius: null,
    action: null,
    actionKind: 'unknown',
    where: page || mod || null,
  });
}

/** Group key: classes whose fix is per-page/per-module group by target; the rest
 *  are one project-wide row. Keeping this explicit (rather than "always group by
 *  target") is what stops 44 design rows collapsing into an unactionable blob. */
const REMEDIATION_PER_TARGET = new Set([
  'journey-landing-guard-failed', 'journey-severed', 'ui-text-contradiction',
  'page-never-walked-no-journey', 'page-never-walked-journey-exists',
  'design-partial-read', 'design-lower-bound', 'design-no-wireframe', 'page-join-weak',
]);

/**
 * Collapse remediations into ranked, actionable next steps.
 * One row per (class[, target]), carrying the count it stands for and the things
 * it affects — so "135 not run" reads as a handful of decisions, not 135 shrugs.
 */
function buildNextSteps(checks) {
  const groups = new Map();
  for (const c of checks) {
    const r = c.remediation;
    if (!r) continue;
    const target = REMEDIATION_PER_TARGET.has(r.class) ? remTarget(c) : null;
    const key = r.class + (target ? '::' + target : '');
    if (!groups.has(key)) {
      groups.set(key, {
        id: 'next/' + slug(key), class: r.class, target: target || null,
        scope: target ? (c.page ? 'page' : c.journey && !c.module ? 'process' : 'module') : 'project',
        measures: r.measures, why: r.why, blastRadius: r.blastRadius,
        action: r.action, actionKind: r.actionKind, needsApproval: !!r.needsApproval,
        where: r.where, count: 0, verdicts: {}, affects: new Set(), checkIds: [],
        measureSet: new Set(), kinds: new Set(), steps: new Set(),
      });
    }
    const g = groups.get(key);
    g.count++;
    if (r.measures) g.measureSet.add(r.measures);
    if (c.kind) g.kinds.add(c.kind);
    if (c.stepIndex != null) g.steps.add(c.stepIndex);
    g.verdicts[c.verdict] = (g.verdicts[c.verdict] || 0) + 1;
    if (c.page) g.affects.add(c.page);
    else if (c.journey) g.affects.add(c.journey);
    else if (c.module) g.affects.add(c.module);
    g.checkIds.push(c.id);
    // The group's blast radius should describe the group, not whichever member
    // happened to be first — so keep the longest, which is the most specific.
    if (r.blastRadius && (!g.blastRadius || r.blastRadius.length > g.blastRadius.length)) {
      g.blastRadius = r.blastRadius;
    }
    if (!g.action && r.action) g.action = r.action;
  }

  // A group's "would have measured" must describe the GROUP. Taking the first member's
  // sentence made a 32-check row read as though the only thing lost were one span count.
  for (const g of groups.values()) {
    const ms = [...g.measureSet];
    if (ms.length <= 1) { g.measures = ms[0] || g.measures; continue; }
    g.measures = ms.length + ' distinct expectations' +
      (g.steps.size ? ' across ' + g.steps.size + ' step(s)' : '') +
      (g.kinds.size ? ', on the ' + [...g.kinds].sort().join(' / ') + ' rung(s)' : '') +
      '. Examples: ' + ms.slice().sort().slice(0, 3).join(' · ') +
      (ms.length > 3 ? ' (+' + (ms.length - 3) + ' more — the full list is the check ids below)' : '');
  }

  const out = [...groups.values()].map((g) => ({
    id: g.id, class: g.class, tier: rTier(g.class), scope: g.scope, target: g.target,
    measures: g.measures, why: g.why, blastRadius: g.blastRadius, action: g.action,
    actionKind: g.actionKind, needsApproval: g.needsApproval, where: g.where,
    count: g.count, verdicts: g.verdicts,
    affects: [...g.affects].sort(),
    checkIds: g.checkIds.slice().sort(),
  }));
  out.sort((a, b) => (a.tier - b.tier) || (b.count - a.count) || a.id.localeCompare(b.id));
  out.forEach((s, i) => { s.rank = i + 1; });
  return out;
}

function normalize(inputs) {
  const ctx = {
    outFile: inputs.outFile || 'docs/report.json',
    journeyModule: inputs.journeyModule || new Map(),
    conformanceDate: inputs.conformanceDate || null,
  };
  const checks = [];
  const instruments = [];

  const j = collectJourney(inputs.journeyFindings, inputs.contracts || [], ctx);
  checks.push(...j.checks); instruments.push(...j.instruments);

  const ctl = collectControl(inputs.journeyFindingsControl, ctx);
  checks.push(...ctl.checks); instruments.push(ctl.instrument);

  // One pass per declared walkthrough (project.config `walkthroughs`), in order.
  for (const wt of WALKTHROUGHS) {
    const w = collectWalkthrough(inputs[wt.input], wt.instrument, wt.tags, ctx);
    checks.push(...w.checks); instruments.push(w.instrument);
  }

  const loop = collectLoop(inputs.summaries || []);
  checks.push(...loop.checks); instruments.push(...loop.instruments);

  const conf = collectConformance(inputs.conformance, ctx);
  checks.push(...conf.checks); instruments.push(conf.instrument);

  const cov = collectCoverage(inputs.ledgers || [], conf.rollup, inputs.journeysByModule || new Map(), ctx);
  checks.push(...cov.checks); instruments.push(...cov.instruments);

  const def = collectDeferrals(inputs.deferrals);
  instruments.push(def.instrument);
  const rl = collectRunLedger(inputs.runLedger);
  instruments.push(rl.instrument);

  // ── 1.1: the design rungs, the page join, and the in-scope denominator ─────
  const da = collectDesignAudit(inputs.designAudit, ctx);
  checks.push(...da.checks); instruments.push(da.instrument);

  const scope = collectPageScope(inputs.pageScope);
  checks.push(...(scope.checks || [])); instruments.push(scope.instrument);

  const walks = j.walks || [];
  const at = (inputs.journeyFindings.status === 'ok' && inputs.journeyFindings.data.capturedAt) || null;
  const join = attachPages(walks, da.byPage, scope, inputs.widgetIndex || {}, at);
  checks.push(...join.checks);
  if (!inputs.widgetIndex) {
    instruments.push({ name: 'page-join', verdict: 'fault',
      source: INPUTS.catalog, canExpressFault: true, evidenceStrength: 'strong',
      reason: `${INPUTS.catalog} could not be read, so no walk step could be attributed to a ` +
              'page. Every design rung on the walk is `fault` for that reason alone — none of ' +
              'them is a statement about the pages.' });
  } else {
    const ok = join.checks.filter(c => c.verdict === 'pass').length;
    instruments.push({ name: 'page-join', verdict: 'pass', source: INPUTS.catalog,
      canExpressFault: true, evidenceStrength: 'strong', checksEmitted: join.checks.length,
      note: `${ok}/${join.checks.length} walk step(s) resolved to a page by widget intersection; ` +
            'a step that stays ambiguous is null, never a pick' });
  }

  const cover = collectPageCoverage(scope, join.walked, inputs.journeysByModule || new Map(),
                                    da.byPage, at);
  checks.push(...cover.checks);

  // Determinism (rule 6): sort every array whose order carries no meaning.
  checks.sort((a, b) => a.id.localeCompare(b.id));

  // ── 1.2: attach a remediation to every non-pass, then group them ──────────
  // Runs AFTER the sort so `byId` sees the final set, and after every collector so
  // a severed check can follow `blockedBy` to the guard that severed it.
  const byId = new Map(checks.map(c => [c.id, c]));
  for (const c of checks) {
    const r = classifyRemediation(c, byId);
    if (r) c.remediation = r;
  }
  const nextSteps = buildNextSteps(checks);
  instruments.sort((a, b) => a.name.localeCompare(b.name));
  cov.coverage.sort((a, b) => a.module.localeCompare(b.module));

  const m = inputs.meta || {};
  const jf = inputs.journeyFindings.status === 'ok' ? inputs.journeyFindings.data : null;
  const ff = inputs.findings.status === 'ok' ? inputs.findings.data : null;
  const stamps = [jf && jf.capturedAt, ff && ff.capturedAt,
                  inputs.findingsMobile.status === 'ok' ? inputs.findingsMobile.data.capturedAt : null]
                 .filter(Boolean).sort();

  return {
    schemaVersion: SCHEMA_VERSION,
    project: {
      id: m.projectId || null,
      displayName: m.displayName || null,
      mpr: m.mpr || null,
      mprModifiedAt: m.mprModifiedAt || null,
      mendixVersion: m.mendixVersion || null,
      toolkitCommit: m.toolkitCommit || null,
      gitCommit: m.gitCommit || null,
      branch: m.branch || null,
    },
    run: {
      startedAt: stamps[0] || null,
      finishedAt: stamps[stamps.length - 1] || null,
      // MEASURED PROBLEM WITH THE SCHEMA, made visible instead of smoothed over:
      // `run` is singular, but the inputs are written by instruments that ran at
      // different times (live data: the walkthrough is from 08-12, the journey from
      // 08-14). startedAt..finishedAt then spans two days and reads as one long run.
      // The flag lets the renderer say "these are not one run" rather than implying it.
      evidenceSpansMultipleRuns: stamps.length > 1 &&
        (Date.parse(stamps[stamps.length - 1]) - Date.parse(stamps[0])) > 3600e3,
      evidenceTimestamps: stamps,
      trigger: jf ? 'journey' : (inputs.summaries || []).length ? 'verify-module' : ff ? 'e2e' : 'manual',
      target: m.target || null,
      env: {
        baseUrl: (jf && jf.baseUrl) || (ff && ff.baseUrl) || m.baseUrl || null,
        host: m.host || null,
        ownership: m.ownership || 'unknown',
        ownershipBasis: m.ownershipBasis || null,
        user: (jf && jf.actualUser) || (ff && ff.user) || null,
        userFallbackUsed: jf ? !!jf.usedFallback
                             : ff ? !!(ff.configuredUser && ff.user && ff.configuredUser !== ff.user)
                             : null,
        database: m.database || null,
      },
      reproduce: {
        command: m.command || null,
        // The runner does NOT persist the seeds it resolved (instrument gap, see the
        // handover note). null says so; {} would imply "there were none".
        seeds: null,
        monkeySeed: null,
      },
    },
    checks,
    // 1.2. Every non-pass check's remediation, grouped by (class[, page/module]) and
    // ranked by blast radius. This is the answer to "there's a lot of things which say
    // 'did not run' — what do you mean, and how do we fix that?". A group is never a
    // summary that loses its members: `checkIds` names every row it stands for.
    nextSteps,
    instruments,
    coverage: cov.coverage,
    deferrals: def.deferrals,
    // The narrated walk: what the persona did, page by page, with the checks that ran
    // against each page state. Empty when no journey ran — never fabricated from the
    // contract, because a contract says what SHOULD happen and this section's whole
    // value is that it says what DID.
    walks,
    // One entry per DISTINCT in-scope page set, not per role. Six personas that see the
    // same five pages are one report named for all six, and the fact that they are the
    // same is raised as a finding rather than rendered six times as thoroughness.
    roleSets: scope.roleSets || [],
    // The denominator. `uncovered` is the headline number, not a footnote.
    pageCoverage: cover.pageCoverage,
  };
}

// ============================================================================
// IO — everything that touches the disk
// ============================================================================
function listDirs(rel) {
  try { return fs.readdirSync(abs(rel), { withFileTypes: true }).filter(d => d.isDirectory()).map(d => d.name).sort(); }
  catch { return []; }
}

function detectOwnership(baseUrl) {
  // "verified" is a high bar on purpose: it means a container PROVED it serves this
  // project. Anything softer is "asserted" — the config file says so and nothing
  // checked. Everything else is "unknown", never a guess dressed as a fact.
  const out = safeExec('docker', ['ps', '--format', '{{.Names}}\t{{.Labels}}']);
  if (out) {
    for (const line of out.split('\n')) {
      const [name, labels = ''] = line.split('\t');
      if (labels.includes(ROOT) || labels.includes(`com.docker.compose.project=${path.basename(ROOT).toLowerCase()}`))
        return { ownership: 'verified', ownershipBasis: `docker container "${name}" labelled for ${ROOT}`, host: 'docker' };
    }
  }
  const cfg = readJsonInput(INPUTS.appConfig);
  if (cfg.status === 'ok') {
    const c = cfg.data.Configuration || {};
    const root = c.ApplicationRootUrl || '';
    const match = baseUrl && root && root.replace(/\/+$/, '') === String(baseUrl).replace(/\/+$/, '');
    return {
      ownership: 'asserted',
      ownershipBasis: `${INPUTS.appConfig} (ApplicationRootUrl=${root || 'unset'}${match ? ', matches baseUrl' : ', does NOT match baseUrl'})`,
      host: /localhost|127\.0\.0\.1/.test(String(baseUrl || root)) ? 'studio-pro' : 'remote',
      database: c.DatabaseType ? `${c.DatabaseType} ${c.DatabaseName || ''}`.trim() : null,
    };
  }
  return { ownership: 'unknown', ownershipBasis: null, host: null };
}

// Widget name → the pages that declare it, straight out of the mxcli catalog. READ
// ONLY: a `SELECT` against a sqlite file, no mxcli invocation, nothing that touches the
// .mpr. Returns null (not {}) when the catalog or the sqlite3 binary is absent, so the
// caller can tell "no widget resolved" apart from "we never looked".
function loadWidgetIndex() {
  if (!fs.existsSync(abs(INPUTS.catalog))) return null;
  const out = safeExec('sqlite3', ['-readonly', '-separator', '\t', abs(INPUTS.catalog),
    "SELECT Name, ContainerQualifiedName FROM widgets " +
    "WHERE ContainerType = 'PAGE' AND Name IS NOT NULL AND Name <> '';"], { timeout: 20000 });
  if (out === null) return null;
  const idx = {};
  for (const line of out.split('\n')) {
    const [name, page] = line.split('\t');
    if (!name || !page) continue;
    if (!idx[name]) idx[name] = [];
    if (!idx[name].includes(page)) idx[name].push(page);
  }
  for (const k of Object.keys(idx)) idx[k].sort();
  return Object.keys(idx).length ? idx : null;
}

function loadInputs(outFile) {
  const journeyFindings = readJsonInput(INPUTS.journeyFindings);
  const journeyFindingsControl = readJsonInput(INPUTS.journeyFindingsControl);
  const findings = readJsonInput(INPUTS.findings);
  const findingsMobile = readJsonInput(INPUTS.findingsMobile);

  // Journey contracts. The module a journey walks is taken from its FILE NAME
  // (FieldScan.journey.json → FieldScan) because the contract schema has no module
  // field — noted as an instrument gap rather than inferred from SQL text.
  const contracts = [];
  const journeyModule = new Map();
  const journeysByModule = new Map();
  let journeyFiles = [];
  try {
    journeyFiles = fs.readdirSync(abs(INPUTS.journeysDir)).filter(f => f.endsWith('.journey.json')).sort();
  } catch { /* no journeys/ — surfaces as zero contracts and unwalked modules */ }
  for (const f of journeyFiles) {
    const rel = `${INPUTS.journeysDir}/${f}`;
    const r = readJsonInput(rel);
    if (r.status !== 'ok') continue;
    contracts.push({ path: rel, data: r.data });
    const mod = f.replace(/\.journey\.json$/, '');
    journeyModule.set(rel, mod);
    if (!journeysByModule.has(mod)) journeysByModule.set(mod, []);
    journeysByModule.get(mod).push(r.data.id || f);
  }

  const summaries = listDirs(INPUTS.verifyDir).map(mod => {
    const rel = `${INPUTS.verifyDir}/${mod}/summary.tsv`;
    let mtime = null;
    try { mtime = fs.statSync(abs(rel)).mtime.toISOString(); } catch { /* reported by readFileInput */ }
    return { module: mod, file: readFileInput(rel), mtime };
  });

  // Newest conformance report BY FILENAME — the names are ISO dates, so lexical sort
  // is chronological, and mtime would reorder on a git checkout.
  let confRel = null, confDate = null;
  try {
    const files = fs.readdirSync(abs(INPUTS.conformanceDir))
      .filter(f => /^report-\d{4}-\d{2}-\d{2}\.tsv$/.test(f)).sort();
    if (files.length) {
      confRel = `${INPUTS.conformanceDir}/${files[files.length - 1]}`;
      confDate = files[files.length - 1].slice(7, 17);
    }
  } catch { /* handled below */ }
  const conformance = confRel
    ? readFileInput(confRel)
    : { status: 'missing', path: `${INPUTS.conformanceDir}/report-<date>.tsv`,
        error: 'no report-<date>.tsv found' };

  const ledgers = listDirs(INPUTS.modulesDir)
    .map(mod => ({ module: mod, file: readFileInput(`${INPUTS.modulesDir}/${mod}/coverage-ledger.md`) }))
    .filter(l => !(l.file.status === 'missing'));   // a module dir with no ledger is not an input

  // ── Project / run metadata ────────────────────────────────────────────────
  const meta = { projectId: path.basename(ROOT), mpr: INPUTS.mpr };
  try { meta.mprModifiedAt = fs.statSync(abs(INPUTS.mpr)).mtime.toISOString(); } catch { meta.mprModifiedAt = null; }
  const md = readJsonInput(INPUTS.metadata);
  if (md.status === 'ok') {
    meta.displayName = md.data.ProjectName || null;
    meta.mendixVersion = md.data.RuntimeVersion || null;
  }
  const pm = readFileInput(INPUTS.projectMd);
  if (pm.status === 'ok') {
    const m = /^Toolkit commit:\s*(\S+)/m.exec(pm.text);
    meta.toolkitCommit = m ? m[1] : null;
  }
  meta.gitCommit = safeExec('git', ['rev-parse', '--short', 'HEAD']);
  meta.branch = safeExec('git', ['rev-parse', '--abbrev-ref', 'HEAD']);

  const baseUrl = (journeyFindings.status === 'ok' && journeyFindings.data.baseUrl)
               || (findings.status === 'ok' && findings.data.baseUrl) || null;
  Object.assign(meta, detectOwnership(baseUrl), { baseUrl });
  // run.env.ownership has been in the schema since 1.0 and nothing wrote it until
  // config.js started resolving it (cfg.ownership / cfg.ownershipBasis, from
  // .claude/loop/stack.env's APP_OWNERSHIP or an explicit APP_PORT assertion). An
  // instrument that recorded it OUTRANKS detectOwnership(): the instrument knows which
  // app it actually talked to, this file can only inspect the environment afterwards.
  for (const src of [journeyFindings, findings, findingsMobile]) {
    if (src.status !== 'ok' || !src.data || !src.data.ownership) continue;
    meta.ownership = src.data.ownership;
    meta.ownershipBasis = `${src.path}: ${src.data.ownershipBasis || 'basis not recorded'}`;
    break;
  }

  meta.target = contracts.length && journeyFindings.status === 'ok'
    ? (journeyModule.get(contracts[0].path) || null)
    : summaries.length === 1 ? summaries[0].module
    : findings.status === 'ok' ? (findings.data.target || 'full-app') : null;
  meta.command = journeyFindings.status === 'ok' && journeyFiles.length
    ? `node tests/e2e/journey-runner.js ${INPUTS.journeysDir}/${journeyFiles[0]}`
    : null;

  return {
    outFile, journeyFindings, journeyFindingsControl, findings, findingsMobile,
    contracts, journeyModule, journeysByModule,
    summaries, conformance, conformanceDate: confDate, ledgers,
    deferrals: readFileInput(INPUTS.deferrals),
    runLedger: readFileInput(INPUTS.runLedger),
    designAudit: readJsonInput(INPUTS.designAudit),
    pageScope: readJsonInput(INPUTS.pageScope),
    widgetIndex: loadWidgetIndex(),
    meta,
  };
}

// ============================================================================
// SELFTEST — proves the mapping rules, with no app, no DB, no artifacts
// ============================================================================
function selftest() {
  let bad = 0;
  const t = (name, got, want) => {
    const ok = JSON.stringify(got) === JSON.stringify(want);
    if (!ok) bad++;
    console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}${ok ? '' : `  got=${JSON.stringify(got)} want=${JSON.stringify(want)}`}`);
  };
  const missing = p => ({ status: 'missing', path: p, error: 'ENOENT' });
  const base = {
    outFile: 'docs/report.json',
    journeyFindings: missing(INPUTS.journeyFindings),
    journeyFindingsControl: missing(INPUTS.journeyFindingsControl),
    findings: missing(INPUTS.findings),
    findingsMobile: missing(INPUTS.findingsMobile),
    contracts: [], journeyModule: new Map(), journeysByModule: new Map(),
    summaries: [], conformance: missing('docs/conformance/report-x.tsv'), ledgers: [],
    deferrals: missing(INPUTS.deferrals), runLedger: missing(INPUTS.runLedger), meta: {},
  };
  const inst = (rep, n) => rep.instruments.find(i => i.name === n);

  // ---- 1. mapping tables are the rules the prose promises --------------------
  t('INVALID → fault', V_JOURNEY.INVALID, 'fault');
  t('FAIL → fail',     V_JOURNEY.FAIL, 'fail');
  t('PASS → pass',     V_JOURNEY.PASS, 'pass');
  t('loop FINDING → fail', V_LOOP.FINDING, 'fail');
  t('loop FAULT → fault',  V_LOOP.FAULT, 'fault');
  t('conformance UNRUNNABLE → fault', V_CONF.UNRUNNABLE, 'fault');
  t('walkthrough missing → fail (not fault: the source cannot mean "did not run")',
    V_WALK.missing, 'fail');

  // ---- 2. requirement: "" is null, never "" ----------------------------------
  t('normReq("") → null', normReq(''), null);
  t('normReq("   ") → null', normReq('   '), null);
  t('normReq(undefined) → null', normReq(undefined), null);
  t('normReq keeps a real pointer', normReq('/pages/0/name'), '/pages/0/name');

  // ---- 3. every missing input becomes a fault instrument, never silence ------
  const empty = normalize({ ...base });
  t('no inputs → zero checks', empty.checks.length, 0);
  for (const n of ['journey-runner', 'full-app-walkthrough', 'mobile-fieldscan',
                   'conformance', 'coverage-ledger', 'deferrals', 'run-ledger']) {
    const i = inst(empty, n);
    t(`missing ${n} → fault instrument`, i && i.verdict, 'fault');
    t(`missing ${n} → carries a reason`, !!(i && i.reason), true);
  }
  t('positive-control absence is its own fault, not folded into journey-runner',
    inst(empty, 'positive-control').verdict, 'fault');

  // ---- 3a. the walk is narrative; its status comes from checks, never the picture ----
  const walkFile = steps => ({ status: 'ok', path: 'jf.json', data: {
    capturedAt: '2026-01-01T00:00:00Z', positiveControl: false, results: [],
    walks: [{ journey: 'J-W-01', title: 't', persona: 'p', requirement: ['F001#/a'],
              seeds: { itemCode: 'X' }, steps }] } });
  const st = (n, checks, shot) => ({ n, name: `step ${n}`, requirement: [], actions: [], checks, shot });

  const wOk = normalize({ ...base, journeyFindings: walkFile([
    st(2, [{ rung: 'ui', name: 'b', verdict: 'PASS', detail: '' }], { file: 'b.png' }),
    st(1, [{ rung: 'ui', name: 'a', verdict: 'PASS', detail: '' }], null)]) });
  t('walk steps are ordered by n, not by arrival', wOk.walks[0].steps.map(s => s.n), [1, 2]);
  t('a step with no screenshot still gets a status', wOk.walks[0].steps[0].status, 'pass');
  t('walk verdicts are normalized to the report dialect',
    wOk.walks[0].steps[0].checks[0].verdict, 'pass');

  // The precedence that keeps a walk honest: "could not measure" outranks "measured fine".
  const wMix = normalize({ ...base, journeyFindings: walkFile([
    st(1, [{ rung: 'ui', name: 'a', verdict: 'PASS', detail: '' },
           { rung: 'data', name: 'b', verdict: 'INVALID', detail: '' }], null)]) });
  t('an unmeasured rung makes the step fault, not pass', wMix.walks[0].steps[0].status, 'fault');
  const wFail = normalize({ ...base, journeyFindings: walkFile([
    st(1, [{ rung: 'ui', name: 'a', verdict: 'PASS', detail: '' },
           { rung: 'data', name: 'b', verdict: 'FAIL', detail: '' }], null)]) });
  t('a failing rung makes the step fail', wFail.walks[0].steps[0].status, 'fail');

  // An empty check list passing would be `[].every()` in another costume.
  const wEmpty = normalize({ ...base, journeyFindings: walkFile([st(1, [], { file: 'a.png' })]) });
  t('a step that asserted NOTHING is fault, however good the screenshot looks',
    wEmpty.walks[0].steps[0].status, 'fault');

  t('no journey → no walk, never a walk invented from the contract',
    normalize({ ...base }).walks, []);

  // A control run parked in the real slot must not be read as product evidence.
  const jCtl = normalize({ ...base, journeyFindings: { status: 'ok', path: 'journey-findings.json',
    data: { capturedAt: '2026-01-01T00:00:00Z', positiveControl: true,
            results: [{ rung: 'ui', name: 'x', verdict: 'PASS', detail: '', requirement: '' }] } } });
  t('a control run in the real slot faults journey-runner', inst(jCtl, 'journey-runner').verdict, 'fault');
  t('and emits no product checks from it',
    jCtl.checks.filter(c => c.instrument === 'journey-runner').length, 0);

  // ---- 3b. the control instrument is per-rung, and a copied real run is not one ----
  const ctlRow = (rung, verdict) => ({
    rung: 'control', verdict, detail: `d-${rung}`,
    name: `J-X-01 · ${rung}: whatever the mutant broke`,
  });
  const ctlFile = (results, positiveControl = true) =>
    ({ status: 'ok', path: 'ctl.json', data: { capturedAt: '2026-01-01T00:00:00Z', positiveControl, results } });

  const ctlAll = normalize({ ...base,
    journeyFindingsControl: ctlFile(CONTROL_RUNGS.map(([r]) => ctlRow(r, 'PASS'))) });
  t('all rungs proven → positive-control passes', inst(ctlAll, 'positive-control').verdict, 'pass');
  t('and it says how many', inst(ctlAll, 'positive-control').rungsProven, CONTROL_RUNGS.length);
  t('one check per rung', ctlAll.checks.filter(c => c.instrument === 'positive-control').length,
    CONTROL_RUNGS.length);

  // The bug this guards: a boolean flag standing in for per-rung evidence. One proven
  // rung must NOT license a green for the six that were never challenged.
  const ctlOne = normalize({ ...base, journeyFindingsControl: ctlFile([ctlRow('ui-landing', 'PASS')]) });
  t('one rung proven does NOT pass the instrument', inst(ctlOne, 'positive-control').verdict, 'fail');
  t('unproven rungs are fault, not pass',
    ctlOne.checks.filter(c => c.instrument === 'positive-control' && c.verdict === 'fault').length,
    CONTROL_RUNGS.length - 1);
  t('an unproven rung says it did not run',
    ctlOne.checks.find(c => c.id === 'control/ui-text').provenance, 'notRun');

  // A mutant that went green means the harness CANNOT see that class of defect.
  const ctlFailed = normalize({ ...base,
    journeyFindingsControl: ctlFile(CONTROL_RUNGS.map(([r]) => ctlRow(r, r === 'data-target' ? 'FAIL' : 'PASS'))) });
  t('a mutant that was not caught is a failed rung',
    ctlFailed.checks.find(c => c.id === 'control/data-target').verdict, 'fail');

  // Observed 2026-08-14: journey-findings.json is a single slot, so the control file
  // is a copy. If someone copies a REAL walk into it, it must not read as proof.
  const ctlCopy = normalize({ ...base,
    journeyFindingsControl: ctlFile(CONTROL_RUNGS.map(([r]) => ctlRow(r, 'PASS')), false) });
  t('a non-control file in the control slot proves nothing',
    inst(ctlCopy, 'positive-control').verdict, 'fault');
  t('no instrument is silently absent', empty.instruments.length >= 8, true);
  t('walkthrough weakness is machine-readable',
    [inst(empty, 'full-app-walkthrough').canExpressFault, inst(empty, 'full-app-walkthrough').evidenceStrength],
    [false, 'weak']);

  // ---- 4. an INVALID row lands as fault on the check, not fail ---------------
  const jf1 = {
    status: 'ok', path: 'x',
    data: {
      capturedAt: '2026-01-01T00:00:00Z', positiveControl: false,
      results: [{ rung: 'ui', name: 'login', verdict: 'INVALID', detail: 'fell back', requirement: '' }],
    },
  };
  const r1 = normalize({ ...base, journeyFindings: jf1 });
  t('INVALID check verdict', r1.checks[0].verdict, 'fault');
  t('empty requirement is null on the check', r1.checks[0].requirement, null);
  t('journey-runner present → instrument passes', inst(r1, 'journey-runner').verdict, 'pass');

  // ---- 5. blocks[]: a failed landing guard expands into the CONTRACT ---------
  const contract = {
    id: 'J-T-01',
    requirement: [],
    steps: [
      { name: 'open', ui: { ready: '.mx-name-a' } },
      { name: 'commit',
        ui: { ready: '.mx-name-b', checks: ['w1'], textPresent: ['Done'], textAbsent: ['No rows'] },
        spans: { ordered: ['M.ACT_Commit'], mustNotFire: ['ACT_Other'] },
        data: { creates: 'M.Row', delta: 1,
                assocMustBeSet: [{ assoc: 'M.Row_Thing', target: 'M.Thing',
                                   mustPointAt: { attr: 'Code', value: '{{c}}' } }],
                oql: [{ label: 'a linked row exists', sql: 'SELECT 1', atLeast: 1 }] } },
      { name: 'after', ui: { ready: '.mx-name-c', checks: ['w2'] } },
    ],
    outcome: { sql: 'SELECT 1', atLeast: 1 },
  };
  const jf2 = {
    status: 'ok', path: 'x',
    data: {
      capturedAt: '2026-01-01T00:00:00Z', positiveControl: false,
      results: [
        { rung: 'ui', name: 'open: reached', verdict: 'PASS', detail: '.mx-name-a', requirement: '' },
        { rung: 'ui', name: 'commit: reached', verdict: 'FAIL',
          detail: '".mx-name-b" never appeared — screenshot J-T-01-step2-NOT-REACHED.png', requirement: '' },
        { rung: 'ui', name: 'commit: downstream rungs', verdict: 'INVALID', detail: 'not reached', requirement: '' },
      ],
    },
  };
  const r2 = normalize({
    ...base, journeyFindings: jf2,
    contracts: [{ path: 'journeys/M.journey.json', data: contract }],
    journeyModule: new Map([['journeys/M.journey.json', 'M']]),
  });
  const guard = r2.checks.find(c => c.title === 'reached' && c.verdict === 'fail');
  t('guard failure is attributed to its journey+step', [guard.journey, guard.stepIndex], ['J-T-01', 2]);
  t('guard screenshot lifted into evidence', guard.evidence[0].type, 'screenshot');
  t('guard blocks a non-empty set', guard.blocks.length > 0, true);

  const blocked = r2.checks.filter(c => c.notRun === true);
  const titles = blocked.map(c => c.title).sort();
  t('blocked titles are the DECLARED expectations', titles, [
    'J-T-01 end state',
    'M.Row row count +1',
    'M.Row_Thing points at the seeded Code',
    'M.Row_Thing set on every M.Row row',
    'a linked row exists',
    'no ERROR span at microflow or activity level',
    'reached',                       // step 3's own landing guard never ran either
    'span capture non-empty',
    'spans in order: M.ACT_Commit',
    'widget w1 visible',
    'widget w2 visible',
    'ACT_Other did not run',
    'page does NOT say "No rows"',
    'page says "Done"',
  ].sort());
  t('every blocked entry is a fault', blocked.every(c => c.verdict === 'fault'), true);
  t('no blocked entry is provenance:measured', blocked.every(c => c.provenance === 'declared'), true);
  t('blocked entries point back at the guard', blocked.every(c => c.blockedBy === guard.id), true);
  t('guard.blocks lists exactly the generated ids',
    guard.blocks.slice().sort(), blocked.map(c => c.id).sort());
  t('the guard step itself is expanded (step 2 spans/data), not just later steps',
    blocked.some(c => c.stepIndex === 2 && c.kind === 'trace'), true);
  t('a check that DID run is not re-emitted as blocked',
    blocked.filter(c => c.stepIndex === 2 && c.title === 'reached').length, 0);
  t('ids are unique', new Set(r2.checks.map(c => c.id)).size, r2.checks.length);
  t('checks are sorted by id',
    r2.checks.map(c => c.id), r2.checks.map(c => c.id).slice().sort((a, b) => a.localeCompare(b)));
  t('two runs over the same input are byte-identical',
    JSON.stringify(sortKeysDeep(normalize({ ...base, journeyFindings: jf2,
        contracts: [{ path: 'journeys/M.journey.json', data: contract }],
        journeyModule: new Map([['journeys/M.journey.json', 'M']]) }))),
    JSON.stringify(sortKeysDeep(r2)));

  // ---- 6. walkthrough dialect + mobile tagging -------------------------------
  const wf = {
    status: 'ok', path: 'x',
    data: { target: 'mobile-fieldscan', capturedAt: '2026-01-02T00:00:00Z',
            configuredUser: 'u', user: 'u',
            pages: [{ key: 'p', label: 'P', screenshot: 'app/p.png',
                      widgets: [{ name: 'w', status: 'ok' }, { name: 'x', status: 'missing' }],
                      oqlRows: [{ label: 'n', sql: 'SELECT 1', value: '3', pass: true }],
                      steps: [{ label: 's', status: 'fail', detail: 'nope' }] }] } };
  const r3 = normalize({ ...base, findingsMobile: wf });
  t('walkthrough ok → pass', r3.checks.find(c => /widget w$/.test(c.title)).verdict, 'pass');
  t('walkthrough missing → fail', r3.checks.find(c => /widget x$/.test(c.title)).verdict, 'fail');
  t('mobile checks are tagged', r3.checks.every(c => c.tags.includes('mobile')), true);
  t('walkthrough carries no invented requirement', r3.checks.every(c => c.requirement === null), true);
  t('oql value lands in evidence',
    r3.checks.find(c => c.kind === 'data').evidence.some(e => e.type === 'query' && e.value === '3'), true);

  // ---- 7. summary.tsv with the REAL four-column shape ------------------------
  const r4 = normalize({ ...base, summaries: [{ module: 'RM', mtime: null,
    file: { status: 'ok', path: 's.tsv', text: 'stack (check)\tFINDING\t1\t.claude/loop/verify/RM/00.log\n' } }] });
  const li = inst(r4, 'verify-loop/RM/stack (check)');
  t('4-column summary.tsv parses', [li.verdict, li.rc, li.elapsedSec, li.log],
    ['fail', 1, null, '.claude/loop/verify/RM/00.log']);
  t('a FINDING row also becomes a check', r4.checks.filter(c => c.instrument === 'verify-loop').length, 1);

  // ---- 8. conformance pointer is read, never synthesised ---------------------
  const r5 = normalize({ ...base, conformance: { status: 'ok', path: 'c.tsv',
    text: 'module\tpointer\tstored\tobserved\tverdict\tcommand\n' +
          'RM\t`/actors/*` (6)\tbuilt\tPRESENT\tOK\tSHOW MODULE ROLES\n' +
          'RM\tno-pointer-here\tpartial\tUNRUNNABLE\tUNRUNNABLE\tDESCRIBE PAGE\n' } });
  t('decorated pointer is cleaned, not invented',
    r5.checks.find(c => c.id.includes('actors')).requirement, '/actors/*');
  t('a non-pointer cell becomes null, never a synthesised pointer',
    r5.checks.find(c => c.id.includes('no-pointer')).requirement, null);
  t('UNRUNNABLE row → fault check', r5.checks.find(c => c.id.includes('no-pointer')).verdict, 'fault');

  // ---- 9. ledger parsing: declared vs counted, and absent ≠ zero -------------
  const ledgerText = [
    '# F009 (Test) — BRD Coverage Ledger', '',
    'Generated 2026-07-31. Every leaf of `analysis/x/brd/F009-test.brd.json` is claimed.', '',
    '→ **100 leaves**.', '',
    '## Totals', '', '| | rows | leaves |', '|---|---|---|',
    '| BUILDABLE | 3 | 90 |', '| NON-BUILDABLE | 1 | 10 |', '',
    '## BUILDABLE status counts (leaf-rows, not leaves)', '',
    '| status | rows |', '|---|---|', '| built | 2 |', '| partial | 0 |', '| not-built | 1 |', '',
    '## BUILDABLE', '',
    '| pointer | type | title | slice | writeMode | acceptance | status |',
    '|---|---|---|---|---|---|---|',
    '| `/a` (1) | entity | A | s1 | CLI | ok | built |',
    '| `/b` (1) | page | B | s1 | CLI | ok | **built** |',
    '| `/c` (1) | page | C | s1 | CLI | ok | not-built |', '',
    '## NON-BUILDABLE', '', '| pointer | category | reason |', '|---|---|---|', '| `/d` | x | y |', '',
  ].join('\n');
  const r6 = normalize({ ...base, ledgers: [{ module: 'Test', file: { status: 'ok', path: 'l.md', text: ledgerText } }] });
  const cv = r6.coverage[0];
  t('leaf count from the header', cv.leaves.total, 100);
  t('absent coverage-check line → null, NOT 0', cv.leaves.unclaimed, null);
  t('brd id recovered', cv.brd, 'F009');
  t('per-row statuses counted (bold stripped)', cv.rows.byStatus, { built: 2, partial: 0, notBuilt: 1 });
  t('declared counts kept alongside', cv.rows.byStatusDeclared, { built: 2, partial: 0, notBuilt: 1 });
  t('reconcile check passes when they agree',
    r6.checks.find(c => c.id.endsWith('status-counts-reconcile')).verdict, 'pass');
  t('a module no journey walks is a fault, not a silent pass',
    r6.checks.find(c => c.id.endsWith('has-a-journey')).verdict, 'fault');
  const r6b = normalize({ ...base, ledgers: [{ module: 'Test',
    file: { status: 'ok', path: 'l.md', text: ledgerText.replace('| built | 2 |', '| built | 9 |') } }] });
  t('reconcile check FAILS when the ledger contradicts itself',
    r6b.checks.find(c => c.id.endsWith('status-counts-reconcile')).verdict, 'fail');

  // ---- 10. deferrals: consent nulls survive ----------------------------------
  const r7 = normalize({ ...base, deferrals: { status: 'ok', path: 'd.jsonl',
    text: '{"id":"D-2","question":"q2"}\n{"id":"D-1","question":"q1","requirement":""}\n' } });
  t('deferrals sorted by id', r7.deferrals.map(d => d.id), ['D-1', 'D-2']);
  t('UNRAISED stays null on both consent fields',
    [r7.deferrals[0].consentBy, r7.deferrals[0].consentAt], [null, null]);
  t('deferral "" requirement → null', r7.deferrals[0].requirement, null);

  // ---- 12. schema 1.1: the design rungs, the page join, the denominator ------
  // Fixtures, not artifacts: this must prove the rules with the app down and the
  // artifacts directory empty, which is the state the whole feature has to survive.
  const daFile = (checks, perPage) => ({ status: 'ok', path: 'design-audit.json', data: {
    schemaVersion: '1.1', instrument: 'design-audit', positiveControl: false,
    run: { mode: 'static-only', finishedAt: '2026-01-01T00:00:00Z' },
    perPage: perPage || [], checks } });
  const scopeFile = (inScope, roles, extra) => ({ status: 'ok', path: 'page-scope.json', data:
    Object.assign({ generatedAt: '2026-01-01T00:00:00Z', inScope, orphans: [], roles }, extra || {}) });
  const wStep = (n, name, landsOn, checks, over) => Object.assign(
    { n, name, requirement: [], actions: [], checks,
      expects: { landsOn, pageSays: [], pageDoesNotSay: [], microflows: [], writes: null } },
    over || {});
  const jfWalk = steps => ({ status: 'ok', path: 'jf.json', data: {
    capturedAt: '2026-01-01T00:00:00Z', positiveControl: false,
    results: steps.flatMap(s => s.checks.map(c => ({ rung: c.rung, name: c.name,
      verdict: c.verdict, detail: c.detail || '', requirement: '' }))),
    walks: [{ journey: 'J-T-01', title: 't', persona: 'p', requirement: [], seeds: null, steps }] } });

  // A page walked, with a wireframe; and a second in-scope page nothing walks.
  const r8 = normalize({ ...base,
    journeyFindings: jfWalk([
      wStep(1, 'open A', '.mx-name-wA', [{ rung: 'ui', name: 'open A: reached', verdict: 'PASS', detail: '' }]),
    ]),
    contracts: [{ path: 'journeys/M.journey.json', data: { id: 'J-T-01', steps: [{ name: 'open A' }] } }],
    journeyModule: new Map([['journeys/M.journey.json', 'M']]),
    journeysByModule: new Map([['M', ['J-T-01']]]),
    widgetIndex: { wA: ['M.A'] },
    pageScope: scopeFile(['M.A', 'M.B'], [{ role: 'R', inScopePages: 2, pages: ['M.A', 'M.B'] }]),
    designAudit: daFile([
      { id: 'design-audit/rung6/wireframe-conformance/M.A', page: 'M.A', module: 'M', kind: 'ui',
        title: 'wireframe conformance', verdict: 'pass', detail: 'ok' },
      { id: 'design-audit/rung7/a11y/M.A', page: 'M.A', module: 'M', kind: 'ui',
        title: 'a11y', verdict: 'skipped', detail: 'needs a rendered page' },
      { id: 'design-audit/rung6/wireframe-conformance/M.B', page: 'M.B', module: 'M', kind: 'ui',
        title: 'wireframe conformance', verdict: 'skipped', detail: 'no wireframe' },
    ], [{ page: 'M.A', wireframe: 'a.html' }, { page: 'M.B', wireframe: null }]),
  });
  const s8 = r8.walks[0].steps[0];
  t('a walk step is attributed to a page', s8.page.qualifiedName, 'M.A');
  t('the page block carries the wireframe path', s8.page.wireframe, 'design/wireframes/a.html');
  t('the page block carries rung 6 as a single verdict', s8.page.rung6, 'pass');
  t('and rung 7 as a list of checks', s8.page.rung7.map(c => c.id), ['design-audit/rung7/a11y/M.A']);
  t('the page block says which roles can see it', s8.page.role, ['R']);
  t('the denominator is the in-scope set, not the walked set',
    [r8.pageCoverage.inScope, r8.pageCoverage.walked, r8.pageCoverage.uncovered], [2, 1, 1]);

  // THE RULE: in scope, never walked → fault, filed under the journey that owed it.
  const unc = r8.checks.find(c => c.id === 'scope/uncovered/M.B');
  t('an in-scope page with no walk is a check, not a silent absence', !!unc, true);
  t('  …and its verdict is fault, never skipped and never pass', unc && unc.verdict, 'fault');
  t('  …and it is filed under the journey that should have covered it',
    r8.pageCoverage.byJourney, [{ journey: 'J-T-01', pages: ['M.B'] }]);

  // No wireframe → rung 6 skipped; rung 7 runs anyway. That is the point of rung 7.
  const r9 = normalize({ ...base,
    journeyFindings: jfWalk([
      wStep(1, 'open B', '.mx-name-wB', [{ rung: 'ui', name: 'open B: reached', verdict: 'PASS', detail: '' }]),
    ]),
    contracts: [{ path: 'journeys/M.journey.json', data: { id: 'J-T-01', steps: [{ name: 'open B' }] } }],
    journeyModule: new Map([['journeys/M.journey.json', 'M']]),
    widgetIndex: { wB: ['M.B'] },
    pageScope: scopeFile(['M.B'], [{ role: 'R', inScopePages: 1, pages: ['M.B'] }]),
    designAudit: daFile([
      { id: 'design-audit/rung6/wireframe-conformance/M.B', page: 'M.B', module: 'M', kind: 'ui',
        title: 'wireframe conformance', verdict: 'skipped',
        reason: 'no wireframe was drawn for this page' },
      { id: 'design-audit/rung7/unmatched-class/M.B', page: 'M.B', module: 'M', kind: 'ui',
        title: 'unmatched class sweep', verdict: 'fail', detail: '3 unmatched' },
    ], [{ page: 'M.B', wireframe: null }]),
  });
  const p9 = r9.walks[0].steps[0].page;
  t('no wireframe → rung 6 is skipped', p9.rung6, 'skipped');
  t('no wireframe → wireframe path is null, never a guessed one', p9.wireframe, null);
  t('rung 7 still runs without a wireframe', p9.rung7.length, 1);
  t('  …and can still fail', p9.rung7[0].verdict, 'fail');

  // #891: a partially-read page cannot yield a clean rung 6.
  const r10 = normalize({ ...base,
    journeyFindings: jfWalk([
      wStep(1, 'open C', '.mx-name-wC', [{ rung: 'ui', name: 'open C: reached', verdict: 'PASS', detail: '' }]),
    ]),
    widgetIndex: { wC: ['M.C'] },
    pageScope: scopeFile(['M.C'], [{ role: 'R', inScopePages: 1, pages: ['M.C'] }]),
    designAudit: daFile([
      { id: 'design-audit/read/M.C/complete', page: 'M.C', module: 'M', kind: 'ui',
        title: 'ELK tree carries the whole page', verdict: 'fault', detail: 'partially-read' },
      { id: 'design-audit/rung6/wireframe-conformance/M.C', page: 'M.C', module: 'M', kind: 'ui',
        title: 'wireframe conformance', verdict: 'pass', detail: 'clean' },
    ], [{ page: 'M.C', wireframe: 'c.html' }]),
  });
  t('partially-read (mxcli #891) degrades a green rung 6 to fault',
    r10.walks[0].steps[0].page.rung6, 'fault');

  // An unresolvable page never guesses, and never renders green.
  const r11 = normalize({ ...base,
    journeyFindings: jfWalk([
      wStep(1, 'open ?', '.mx-name-shared', [{ rung: 'ui', name: 'open ?: reached', verdict: 'PASS', detail: '' }]),
    ]),
    widgetIndex: { shared: ['M.X', 'M.Y'] },
    pageScope: scopeFile(['M.X', 'M.Y'], [{ role: 'R', inScopePages: 2, pages: ['M.X', 'M.Y'] }]),
    designAudit: daFile([], []),
  });
  t('an ambiguous page is null, never one of the candidates',
    r11.walks[0].steps[0].page.qualifiedName, null);
  t('  …and its design rungs are fault, not skipped and not pass',
    r11.walks[0].steps[0].page.rung6, 'fault');
  t('  …and the join failure is its own check',
    r11.checks.find(c => c.instrument === 'page-join').verdict, 'fault');

  // Role sets: one per distinct SET, and the shared-set finding is raised.
  const r12 = normalize({ ...base, pageScope: scopeFile(['M.A', 'M.B'], [
    { role: 'Administrator', pages: ['M.A', 'M.B'] },
    { role: 'MxRole_Operator', pages: ['M.A'] },
    { role: 'MxRole_Auditor', pages: ['M.A'] },
    { role: 'ShowcaseUser', pages: [] },
  ]) });
  t('roles collapse to distinct page SETS', r12.roleSets.length, 3);
  t('the shared set names every role that shares it',
    r12.roleSets.find(s => s.pageCount === 1).roles, ['MxRole_Auditor', 'MxRole_Operator']);
  t('a role that reaches nothing is still its own distinct set, never dropped',
    r12.roleSets.filter(s => s.empty).map(s => s.roles), [['ShowcaseUser']]);
  t('identical persona sets are raised as a finding',
    r12.checks.find(c => c.id === 'scope/security-does-not-differentiate-personas').verdict, 'fail');
  const r12b = normalize({ ...base, pageScope: scopeFile(['M.A', 'M.B'], [
    { role: 'A', pages: ['M.A'] }, { role: 'B', pages: ['M.B'] }]) });
  t('distinct sets are NOT reported as a differentiation failure',
    r12b.checks.find(c => c.id === 'scope/security-does-not-differentiate-personas').verdict, 'pass');

  // checks[] is derived from walks[], and the derivation is itself checked.
  const derivedRep = r8.checks.filter(c => c.derivedFrom === 'walks[]');
  t('journey checks are derived from the walk', derivedRep.length, 1);
  t('a derived check keeps the id the results path would have produced',
    derivedRep[0].id, 'journey/J-T-01/step1/open-a-reached');
  t('the derivation is reconciled against results[], not merely asserted',
    r8.checks.find(c => c.id === 'derivation/j-t-01/walk-is-the-source').verdict, 'pass');
  const disagree = normalize({ ...base, journeyFindings: { status: 'ok', path: 'jf.json', data: {
    capturedAt: '2026-01-01T00:00:00Z', positiveControl: false,
    results: [{ rung: 'ui', name: 'open A: reached', verdict: 'FAIL', detail: '', requirement: '' }],
    walks: [{ journey: 'J-T-01', title: 't', persona: 'p', requirement: [], seeds: null,
      steps: [wStep(1, 'open A', '.mx-name-wA',
        [{ rung: 'ui', name: 'open A: reached', verdict: 'PASS', detail: '' }])] }] } } });
  t('walks[] and results[] disagreeing is a FAILING check, not a silent preference',
    disagree.checks.find(c => c.id === 'derivation/j-t-01/walk-is-the-source').verdict, 'fail');
  t('no walk at all is a fault on the derivation, never a quiet fallback',
    normalize({ ...base, journeyFindings: { status: 'ok', path: 'jf.json', data: {
      capturedAt: '2026-01-01T00:00:00Z', positiveControl: false,
      results: [{ rung: 'ui', name: 'login', verdict: 'PASS', detail: '', requirement: '' }] } } })
      .checks.find(c => c.id === 'derivation/no-walk').verdict, 'fault');

  // Absent 1.1 inputs are faults like every other input (rule 1).
  for (const n of ['design-audit', 'page-scope']) {
    t(`missing ${n} → fault instrument`, inst(empty, n).verdict, 'fault');
    t(`missing ${n} → carries a reason`, !!inst(empty, n).reason, true);
  }
  t('no page scope → no roleSets invented', empty.roleSets, []);
  t('no page scope → no denominator invented', empty.pageCoverage, null);

  // ---- 11. ownership is never optimistic -------------------------------------
  t('no metadata → ownership unknown', empty.run.env.ownership, 'unknown');
  t('schemaVersion emitted', empty.schemaVersion, SCHEMA_VERSION);
  t('seeds are null, not {} (the runner does not persist them)', empty.run.reproduce.seeds, null);

  // ---- 12. remediation (schema 1.2) -----------------------------------------
  // The rule this suite enforces: a non-pass without a remediation is a bug in the
  // table, and a remediation that INVENTS advice for a row it does not understand is
  // worse than one that says "unclassified". Both are asserted.
  const mkc = o => Object.assign({
    id: 'x/y', instrument: 'design-audit', kind: 'ui', module: 'M', page: 'M.A',
    journey: null, stepIndex: null, stepName: null, requirement: null, title: 't',
    verdict: 'fail', provenance: 'measured', detail: 'd', evidence: [], blocks: [],
  }, o);
  const rc = (o, idx) => classifyRemediation(mkc(o), idx || new Map());

  t('a pass gets no remediation', classifyRemediation(mkc({ verdict: 'pass' }), new Map()), null);
  t('an unrecognised row is `unclassified`, not given invented advice',
    rc({ instrument: 'nope', detail: 'who knows' }).class, 'unclassified');
  t('and an unclassified row carries NO action rather than a plausible one',
    rc({ instrument: 'nope', detail: 'who knows' }).action, null);

  t('a zero-span trace fault is classified and names its own verification recipe',
    rc({ kind: 'trace', instrument: 'journey-runner', verdict: 'fault',
         detail: 'zero spans captured — Jaeger down or OTel off.' }).class, 'trace-zero-spans');
  t('the trace remediation refuses to repeat the detail string’s guess as a diagnosis',
    /not itself measured/.test(rc({ kind: 'trace', instrument: 'journey-runner',
      verdict: 'fault', detail: 'zero spans captured — Jaeger down or OTel off.' }).why), true);

  const remGuard = mkc({ id: 'journey/J-1/step1/reached', instrument: 'journey-runner',
    verdict: 'fail', title: 'reached', stepIndex: 1, stepName: 's1', journey: 'J-1',
    detail: '".mx-name-dgX" never appeared — screenshot J-1-step1-NOT-REACHED.png' });
  const gr = classifyRemediation(remGuard, new Map());
  t('a failed landing guard is classified as the process blocker',
    gr.class, 'journey-landing-guard-failed');
  t('and its action names the journey file to open', gr.where, 'journeys/M.journey.json');
  t('and it distinguishes a wrong selector from an unreachable route',
    /a rendered page with a different widget means the selector/.test(gr.action), true);

  const sev = classifyRemediation(mkc({ id: 'journey/J-1/step1/spans', verdict: 'fault',
    instrument: 'journey-runner', kind: 'trace', journey: 'J-1', stepIndex: 1,
    blockedBy: 'journey/J-1/step1/reached', detail: 'declared but never measured. Expectation: >= 1 span' }),
    new Map([['journey/J-1/step1/reached', remGuard]]));
  t('a severed check follows blockedBy to the guard that severed it',
    /step 1 \("s1"\)/.test(sev.why), true);
  t('and it is ranked BELOW the guard, so the reader is told what to do before what to skip',
    REMEDIATION_TIER['journey-landing-guard-failed'] < REMEDIATION_TIER['journey-severed'], true);

  t('the axe rung is classified, not filed as unclassified (the a11y→ay regex bug)',
    rc({ id: 'design-audit/rung7/a11y/M.A', instrument: 'design-audit' }).class, 'design-a11y');
  t('a screen that contradicts the data is flagged as a MODEL write needing approval',
    rc({ instrument: 'journey-runner', verdict: 'fail', title: 'page does NOT say "No items found"' })
      .needsApproval, true);
  t('rung 6 SKIPPED is a design deliverable, never a pass',
    rc({ verdict: 'skipped', detail: 'rung 6 does not apply to this page; rung 7 measures it anyway' })
      .class, 'design-no-wireframe');
  t('a page-join with no module still names the journey file, via the page prefix',
    rc({ instrument: 'page-join', verdict: 'manual', module: null, page: 'M.A' }).where,
    'journeys/M.journey.json');

  // Grouping ------------------------------------------------------------------
  const gchecks = [
    mkc({ id: 'a', verdict: 'fault', page: 'M.A', kind: 'ui', stepIndex: 1,
          remediation: null, instrument: 'journey-runner', journey: 'J-1',
          blockedBy: 'g', detail: 'x. Expectation: E1' }),
    mkc({ id: 'b', verdict: 'fault', page: 'M.A', kind: 'trace', stepIndex: 2,
          instrument: 'journey-runner', journey: 'J-1',
          blockedBy: 'g', detail: 'x. Expectation: E2' }),
  ];
  gchecks.forEach(c => { c.remediation = classifyRemediation(c, new Map()); });
  const ns = buildNextSteps(gchecks);
  t('identical faults collapse into ONE next step carrying its count', ns.length, 1);
  t('and the group keeps every check id it stands for', ns[0].checkIds, ['a', 'b']);
  t('a group with differing expectations summarises them instead of quoting the first',
    /2 distinct expectations/.test(ns[0].measures), true);
  t('next steps are ranked, starting at 1', ns[0].rank, 1);
  t('nextSteps[] is emitted on the report', Array.isArray(empty.nextSteps), true);
  t('a run with no findings derives no next steps (never a fabricated one)',
    empty.nextSteps.filter(s => s.class !== 'unclassified').length >= 0, true);

  console.log(bad ? `\n${bad} FAILED` : '\nall ok');
  return bad ? 1 : 0;
}

// ============================================================================
// MAIN
// ============================================================================
function main() {
  const argv = process.argv.slice(2);
  if (argv.includes('--selftest')) process.exit(selftest());

  const oi = argv.indexOf('--out');
  const outFile = oi >= 0 && argv[oi + 1] ? argv[oi + 1] : 'docs/report.json';
  process.env.__OUT = outFile;                 // used by relTo() inside collectLoop

  const inputs = loadInputs(outFile);
  const report = sortKeysDeep(normalize(inputs));

  const outPath = abs(outFile);
  try {
    fs.mkdirSync(path.dirname(outPath), { recursive: true });
    fs.writeFileSync(outPath, JSON.stringify(report, null, 2) + '\n');
  } catch (e) {
    // The ONLY failure mode that is fatal. Everything else is reported IN the report.
    console.error(`report-normalize: cannot write ${outFile}: ${e.message}`);
    process.exit(1);
  }

  const n = v => report.checks.filter(c => c.verdict === v).length;
  const i = v => report.instruments.filter(x => x.verdict === v).length;
  console.log(`report-normalize → ${outFile}`);
  console.log(`  checks      ${report.checks.length}  (pass ${n('pass')}  fail ${n('fail')}  fault ${n('fault')}  skipped ${n('skipped')}  manual ${n('manual')})`);
  console.log(`  of which declared-but-never-run (blocks): ${report.checks.filter(c => c.notRun).length}`);
  console.log(`  instruments ${report.instruments.length}  (pass ${i('pass')}  fail ${i('fail')}  fault ${i('fault')}  skipped ${i('skipped')}  manual ${i('manual')})`);
  for (const x of report.instruments.filter(x => x.verdict === 'fault'))
    console.log(`    FAULT  ${x.name} — ${x.reason || 'no reason recorded'}`);
  console.log(`  coverage    ${report.coverage.length} module(s)   deferrals ${report.deferrals.length}`);
  // Exit 0 always (requirement 8): this is a reporting tool, not a gate. A non-zero
  // exit here would make a red report indistinguishable from a broken normalizer, and
  // CI would start "fixing" the reporter.
  process.exit(0);
}

if (require.main === module) main();

module.exports = { normalize, normReq, declaredChecks, parseLedger,
                   V_JOURNEY, V_LOOP, V_WALK, V_CONF, selftest };
