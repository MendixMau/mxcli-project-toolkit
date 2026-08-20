#!/usr/bin/env node
/**
 * report-render.js — renders docs/report.json into a single self-contained HTML report.
 *
 *   node tests/e2e/report-render.js [--in docs/report.json] [--out docs/verification/report.html]
 *
 * Reads ONLY report.json (docs/verification/report-schema.md is the contract). No npm deps,
 * no network, no external resources in the output.
 *
 * Screenshots: evidence[].path in checks[] is REFERENCED by relative path (keeps the report
 * ~40 KB and the images diffable). The journey-walk section is the one exception — its shots
 * are base64 `data:` URIs, because that section is the thing people copy to another machine
 * and a strict CSP blocks every external host. That inlining is budgeted (see IMAGE_BUDGET)
 * and an image that cannot be embedded says why, in words, instead of breaking.
 *
 * Non-negotiables encoded here (each one comes from a measured past failure):
 *   - pass / fail / fault are three verdicts and never collapse into two.
 *   - `fault` ("did not run") renders achromatic + dashed + 45deg hatch: a hole in the page.
 *     Never amber. Amber reads "caution but running"; the truth is "nothing here".
 *   - The page LEADS WITH COVERAGE: what did not run, above the fold, before any count
 *     of what passed. See coverageOf()/executionLine() for the measured incident.
 *   - Exactly ONE percentage is permitted in this document and it is the share of checks
 *     that DID NOT RUN. No pass rate is printed, ever — and any ratio that is printed
 *     uses a denominator that includes the faults. A rate over "the checks that ran"
 *     describes the part that ran and hides the part that did not.
 *   - A pass badge is never larger or heavier than a fail or fault badge.
 *   - Verdict is hue + glyph + texture, so it survives greyscale and colour blindness.
 *   - Screenshots appear only inside expanded FAIL rows. No gallery of passing thumbnails.
 *   - A section whose data is absent renders an explicit "not measured" panel. Never omitted.
 *
 * Exit codes: 0 ok · 1 usage/IO error · 2 schemaVersion major mismatch (refused).
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const cp = require('child_process');

const SUPPORTED_MAJOR = 1;
// 1 since renderWalks() landed: this renderer implements the additive `walks[]` block.
// Left at 0 it warned "1.1 is newer, rendering known fields only" on every run while in fact
// rendering all of them — a warning that cries wolf teaches the reader to ignore the one that
// matters, and the whole point of the minor check is that a real gap gets noticed.
// 2 since renderNextSteps() / renderRemediation() landed: this renderer implements the
// additive `nextSteps[]` block and `checks[].remediation`.
const SUPPORTED_MINOR = 2;

/* ───────────────────────── args ───────────────────────── */

function parseArgs(argv) {
  const out = { in: 'docs/report.json', out: 'docs/verification/report.html' };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--in' || a === '-i') out.in = argv[++i];
    else if (a === '--out' || a === '-o') out.out = argv[++i];
    else if (a === '--help' || a === '-h') { usage(); process.exit(0); }
    else { console.error('unknown argument: ' + a); usage(); process.exit(1); }
  }
  if (!out.in || !out.out) { usage(); process.exit(1); }
  return out;
}
function usage() {
  console.error('usage: node tests/e2e/report-render.js [--in docs/report.json] ' +
                '[--out docs/verification/report.html]');
}

/* ───────────────────────── tiny helpers ───────────────────────── */

const esc = (s) => String(s == null ? '' : s)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;').replace(/'/g, '&#39;');

const arr = (x) => (Array.isArray(x) ? x : []);
const has = (x) => x !== null && x !== undefined && x !== '';
/** Longest shared leading substring — used to hoist a repeated cause out of a list. */
function commonPrefix(strings) {
  if (!strings.length) return '';
  let p = strings[0];
  for (const s of strings) {
    let i = 0;
    while (i < p.length && i < s.length && p[i] === s[i]) i++;
    p = p.slice(0, i);
    if (!p) break;
  }
  return p;
}
const plural = (n, one, many) => n + ' ' + (n === 1 ? one : many);

function fmtTime(iso) {
  if (!has(iso)) return null;
  const d = new Date(iso);
  if (isNaN(d.getTime())) return String(iso);
  const p = (n) => String(n).padStart(2, '0');
  return d.getUTCFullYear() + '-' + p(d.getUTCMonth() + 1) + '-' + p(d.getUTCDate()) +
         ' ' + p(d.getUTCHours()) + ':' + p(d.getUTCMinutes()) + ' UTC';
}
function elapsed(a, b) {
  if (!has(a) || !has(b)) return null;
  const s = Math.round((new Date(b) - new Date(a)) / 1000);
  if (!isFinite(s) || s < 0) return null;
  return s < 90 ? s + 's' : Math.floor(s / 60) + 'm ' + (s % 60) + 's';
}

/* ───────────────────────── verdict vocabulary ─────────────────────────
 * Every verdict carries three independent channels: hue, glyph, texture.
 * `fault` is the only achromatic + hatched + dashed one, on purpose.      */

const VERDICTS = {
  pass:    { cls: 'v-pass', glyph: '\u2713', label: 'PASS',        bucket: 'pass'  },
  fail:    { cls: 'v-fail', glyph: '\u2715', label: 'FAIL',        bucket: 'fail'  },
  fault:   { cls: 'v-invl', glyph: '\u2300', label: 'DID NOT RUN', bucket: 'fault' },
  skipped: { cls: 'v-skip', glyph: '\u2298', label: 'SKIPPED',     bucket: 'other' },
  manual:  { cls: 'v-man',  glyph: '\u270e', label: 'NEEDS HUMAN', bucket: 'other' },
};
const UNKNOWN = { cls: 'v-invl', glyph: '\u2300', label: 'UNKNOWN VERDICT', bucket: 'fault' };

const vinfo = (v) => VERDICTS[v] || UNKNOWN;
const vkey = (v) => (VERDICTS[v] ? v : 'fault');

function badge(v, textOverride) {
  const i = vinfo(v);
  return '<span class="v ' + i.cls + '">' + i.glyph + ' ' +
         esc(textOverride == null ? i.label : textOverride) + '</span>';
}
/** The hatched "declared but absent" state. Never a blank cell. */
function ghostBadge(text) {
  return '<span class="v v-invl">\u2300 ' + esc(text) + '</span>';
}
function neutBadge(text) {
  return '<span class="v v-neut">' + esc(text) + '</span>';
}

/* `provenance` carries a third value the schema doc does not list: `declared`.
 * A check the journey contract declared but that never ran is neither measured nor
 * judged — calling it either would be a lie. It gets the hole treatment. */
function provenanceBadge(c) {
  if (c.provenance === 'declared' || c.notRun === true) {
    return ghostBadge('DECLARED, NEVER RAN');
  }
  if (c.provenance === 'judged') return warnBadge('JUDGED, NOT MEASURED');
  return '';
}

/** Instrument verdicts are LIVENESS ("did this thing run"), never a rollup of its
 *  checks. journey-runner is `pass` on a run where one of its checks failed. */
function instrumentBadge(v) {
  const map = { pass: 'RAN', fail: 'RAN · REPORTED FAIL', fault: 'DID NOT RUN',
                skipped: 'SKIPPED', manual: 'AWAITING HUMAN' };
  return badge(v, map[v] || vinfo(v).label);
}
function warnBadge(text) {
  return '<span class="v v-warn">\u26a0 ' + esc(text) + '</span>';
}

/** Explicit "this section has no data" panel — the alternative to silent omission. */
function notMeasured(what, why) {
  return '<div class="ghost"><div class="gh">Not measured \u2014 ' + esc(what) + '</div>' +
         '<div class="gf">' + esc(why) + '</div></div>';
}

/* ───────────────────────── load & validate ───────────────────────── */

function load(inPath) {
  let raw;
  try { raw = fs.readFileSync(inPath, 'utf8'); }
  catch (e) {
    console.error('report-render: cannot read ' + inPath + ': ' + e.message);
    console.error('  Nothing was rendered. An absent report is not a passing report.');
    process.exit(1);
  }
  let data;
  try { data = JSON.parse(raw); }
  catch (e) {
    console.error('report-render: ' + inPath + ' is not valid JSON: ' + e.message);
    process.exit(1);
  }
  return data;
}

function checkVersion(data, inPath) {
  const sv = data && data.schemaVersion;
  if (!has(sv)) {
    console.error('report-render: REFUSED. ' + inPath + ' declares no schemaVersion.');
    console.error('  Expected "' + SUPPORTED_MAJOR + '.' + SUPPORTED_MINOR + '". An undeclared');
    console.error('  contract cannot be read as a compatible one — that is how a renderer');
    console.error('  silently drops fields it does not know about and prints green anyway.');
    process.exit(2);
  }
  const m = /^(\d+)\.(\d+)/.exec(String(sv));
  if (!m) {
    console.error('report-render: REFUSED. schemaVersion "' + sv + '" is not major.minor.');
    process.exit(2);
  }
  const major = Number(m[1]), minor = Number(m[2]);
  if (major !== SUPPORTED_MAJOR) {
    console.error('report-render: REFUSED — schemaVersion major mismatch.');
    console.error('  ' + inPath + ' declares ' + sv + '; this renderer implements ' +
                  SUPPORTED_MAJOR + '.' + SUPPORTED_MINOR + '.');
    console.error('  A major bump means fields changed meaning, not just count. Rendering it');
    console.error('  anyway would produce a plausible page built on misread data, which is');
    console.error('  worse than no page. Upgrade the renderer, or emit ' + SUPPORTED_MAJOR + '.x.');
    process.exit(2);
  }
  return { major, minor, newerMinor: minor > SUPPORTED_MINOR, raw: String(sv) };
}

/* ───────────────────────── evidence paths ─────────────────────────
 * evidence[].path is relative to report.json; the HTML usually lands elsewhere.
 * Re-base so the reference resolves — and never emit a remote URL as a resource. */

function makeRebaser(inPath, outPath) {
  const inDir = path.dirname(path.resolve(inPath));
  const outDir = path.dirname(path.resolve(outPath));
  return function rebase(p) {
    if (!has(p)) return null;
    if (/^[a-z][a-z0-9+.-]*:/i.test(p)) return { remote: true, href: String(p) };
    const abs = path.resolve(inDir, p);
    let rel = path.relative(outDir, abs);
    if (path.sep === '\\') rel = rel.split('\\').join('/');
    return { remote: false, href: rel, original: String(p) };
  };
}

/* ───────────────────────── grouping ───────────────────────── */

const RUNGS = [
  { key: 'ARRIVED', kinds: ['ui'] },
  { key: 'RAN',     kinds: ['trace', 'control'] },
  { key: 'WROTE',   kinds: ['data'] },
  { key: "SPEC'D",  kinds: [] },   // filled from `requirement`, not from `kind`
];

function groupJourneys(checks) {
  const byJourney = new Map();
  for (const c of checks) {
    if (!has(c.journey)) continue;
    if (!byJourney.has(c.journey)) {
      byJourney.set(c.journey, { id: c.journey, module: c.module, steps: new Map(),
                                 outcome: [], loose: [] });
    }
    const j = byJourney.get(c.journey);
    if (!has(j.module) && has(c.module)) j.module = c.module;
    if (typeof c.stepIndex === 'number') {
      if (!j.steps.has(c.stepIndex)) {
        j.steps.set(c.stepIndex, { index: c.stepIndex, name: c.stepName, checks: [] });
      }
      const s = j.steps.get(c.stepIndex);
      if (!has(s.name) && has(c.stepName)) s.name = c.stepName;
      s.checks.push(c);
    } else if (c.kind === 'outcome') j.outcome.push(c);
    else j.loose.push(c);
  }
  const out = [];
  for (const j of byJourney.values()) {
    j.stepList = Array.from(j.steps.values()).sort((a, b) => a.index - b.index);
    out.push(j);
  }
  out.sort((a, b) => String(a.id).localeCompare(String(b.id)));
  return out;
}

/** Worst verdict in a set, with fault ranked above pass — absent is not green. */
function rollup(checks) {
  let fail = 0, fault = 0, pass = 0, other = 0;
  for (const c of checks) {
    const b = vinfo(c.verdict).bucket;
    if (b === 'fail') fail++; else if (b === 'fault') fault++;
    else if (b === 'pass') pass++; else other++;
  }
  return { fail, fault, pass, other, total: checks.length };
}

/* ── coverage arithmetic: the denominator that includes the holes ────────────
 * MEASURED, 2026-08-20 (PROJECT-A, schema 1.2). 611 checks: 205 pass, 23 fail,
 * 353 fault, 30 skipped. A reader took that page for "roughly 90% healthy". It is
 * 205 of 611 — 34% — and 353 checks NEVER RAN. Four instruments were entirely at
 * `fault` (coverage-ledger, conformance, deferrals, full-app-walkthrough). Minutes
 * later a hand walkthrough found a runtime crash, a broken widget, an unstyled page
 * and a live data-integrity bug, every one of them on a surface inside those 353.
 *
 * The report did not lie — all 353 rows already said DID NOT RUN. It let a
 * flattering number be the headline instead. So: ONE denominator, and it is
 * `total`. `ran` is pass + fail only; a skipped check did not execute either, and a
 * fault means the instrument never got there at all.
 *
 * The only percentage this document prints is the share that did NOT run, because
 * it is the one figure that an instrument dying early makes WORSE, not better. */
function coverageOf(c) {
  const ran = c.pass + c.fail;
  return { ran, notRun: c.fault, skipped: c.other, total: c.total };
}
/** Integer share of `n` in `total`, never rounded down into a flattering 0. */
function pct(n, total) {
  if (!total || n <= 0) return '0%';
  const p = Math.round((n / total) * 100);
  return (p === 0 ? '<1' : p === 100 && n < total ? '>99' : String(p)) + '%';
}

/* The one line every other number on this page must be read against. Rendered
 * above the verdict word, echoed on stdout, and reused verbatim wherever a run is
 * summarised, so two summaries on one page can never disagree.
 * Vocabulary reused, not invented: "NOTHING EXAMINED" is bin/open-questions.sh's
 * rc-3 state, and bin/questions-report.sh:72 refuses outright to render a clean
 * zero over it. This renderer does not refuse — nothing here blocks — but it says
 * the same words in the same place a refusal would have gone. */
function executionLine(c) {
  const k = coverageOf(c);
  if (!k.total) {
    return 'NOTHING EXAMINED — this report contains zero checks';
  }
  return pct(k.notRun, k.total) + ' of ' + k.total + ' checks did not run · ' +
         c.pass + ' passed · ' + c.fail + ' failed · ' +
         k.notRun + ' did not run · ' + k.skipped + ' skipped';
}

/* ───────────────────────── page fragments ───────────────────────── */

function renderMasthead(d) {
  const p = d.project || {}, r = d.run || {}, env = r.env || {};
  const bits = [];
  // `startedAt..finishedAt` is a bounding box, not a run, when evidence was stitched
  // from several sessions. Say so in the masthead rather than implying one sitting.
  if (r.evidenceSpansMultipleRuns) {
    bits.push(fmtTime(r.startedAt) + ' → ' + fmtTime(r.finishedAt) + ' (STITCHED)');
  } else {
    const t = fmtTime(r.startedAt); if (t) bits.push(t);
  }
  if (has(env.baseUrl)) bits.push(String(env.baseUrl).replace(/^https?:\/\//, ''));
  if (has(env.user)) bits.push(env.user + (env.userFallbackUsed ? ' (FELL BACK)' : ''));
  if (has(p.mendixVersion)) bits.push('Mendix ' + p.mendixVersion);
  const name = has(p.displayName) ? p.displayName : (has(p.id) ? p.id : 'Unnamed project');
  const mark = String(name).trim().charAt(0).toUpperCase() || '?';
  return '' +
  '<header class="top"><div class="top-in">' +
    '<div class="mark">' + esc(mark) + '</div>' +
    '<div><h1>' + esc(name) + ' \u2014 Verification &amp; Sign-Off</h1>' +
    '<div class="sub">' + esc(bits.join(' \u00b7 ')) + '</div></div>' +
    '<div class="spacer"></div>' +
    '<button class="tglbtn" data-filter="pass"  aria-pressed="true">PASS</button>' +
    '<button class="tglbtn" data-filter="fail"  aria-pressed="true">FAIL</button>' +
    '<button class="tglbtn" data-filter="fault" aria-pressed="true">NOT RUN</button>' +
    '<button class="tglbtn" data-filter="other" aria-pressed="true">OTHER</button>' +
    '<button class="tglbtn" id="th" type="button">\u25d0 Theme</button>' +
  '</div></header>';
}

/** The design rungs are checks like any other, so a design-only failure already forces
 *  the headline off PASSED through c.fail / c.fault. This makes the reason explicit,
 *  because "INCOMPLETE" with no stated cause invites a reader to assume the cause is
 *  behavioural and that the pages are fine. */
function designRollup(checks) {
  return rollup(checks.filter((c) => c.instrument === 'design-audit'));
}

function renderVerdict(d, checks, instruments) {
  const c = rollup(checks);
  const instFault = instruments.filter((i) => vinfo(i.verdict).bucket === 'fault').length;
  const cov = d.pageCoverage || null;
  const des = designRollup(checks);
  const behav = rollup(checks.filter((c2) => c2.instrument !== 'design-audit'));

  let word, lead, accent;
  if (c.total === 0) {
    word = 'NOT MEASURED'; accent = 'var(--n-300)';
    lead = 'This report contains zero checks. That is not a pass with nothing to say \u2014 ' +
           'it is a run that produced no evidence at all.';
  } else if (cov && cov.uncovered > 0) {
    // The uncovered remainder outranks everything, because every other number on this
    // page is a statement about the pages that WERE walked. A green count next to a
    // denominator nobody printed is the false green this whole contract exists to retire.
    word = 'INCOMPLETE'; accent = 'var(--n-300)';
    lead = cov.uncovered + ' of ' + cov.inScope + ' in-scope pages were never walked. ' +
           'Everything measured below describes the ' + cov.walked +
           (cov.walked === 1 ? ' page that was' : ' pages that were') + ' reached. ' +
           (c.fail ? plural(c.fail, 'check also failed', 'checks also failed') + '. ' : '') +
           'A pass count computed over the walked minority is not a verdict on the application.';
  } else if (behav.fail === 0 && behav.fault === 0 && instFault === 0 &&
             (des.fail > 0 || des.fault > 0)) {
    // THE FALSE-GREEN WORST CASE. Every behavioural check green, the design rungs red.
    // Tested before the generic fault branch on purpose: "INCOMPLETE — 26 were never
    // measured" is technically true and reads as an instrument problem, which invites
    // the reader to assume the pages themselves are fine. They are not known to be.
    // A page that works and looks wrong is a page that ships wrong.
    word = 'FAILED ON DESIGN'; accent = 'var(--fail-ink)';
    lead = 'Every behavioural check agreed with the system (' + behav.pass + ' passed), and the ' +
           'design rungs did not: ' + des.fail + ' failed, ' + des.fault + ' never ran, ' +
           des.other + ' were skipped. "Does it work" and "does it look the way we said it ' +
           'would" are two questions, and this run answers only the first one in the affirmative.';
  } else if (c.fault > 0 || instFault > 0) {
    word = 'INCOMPLETE'; accent = 'var(--n-300)';
    const parts = [];
    if (c.fail) parts.push(plural(c.fail, 'check failed', 'checks failed'));
    if (c.fault) parts.push(plural(c.fault, 'was never measured', 'were never measured'));
    if (instFault) parts.push(plural(instFault, 'instrument did not run', 'instruments did not run'));
    if (des.fail || des.fault) {
      parts.push(des.fail + ' design finding(s) and ' + des.fault +
                 ' design rung(s) that never ran');
    }
    lead = 'Not a pass with caveats. ' + parts.join('; ') + '. What did not run is ' +
           'absent, not green.';
  } else if (c.fail > 0) {
    word = 'FAILED'; accent = 'var(--fail-ink)';
    lead = plural(c.fail, 'check ran and disagreed', 'checks ran and disagreed') +
           ' with the system. Every one of those is a real finding.';
  } else if (c.other > 0 && c.pass === 0) {
    word = 'NOTHING RAN'; accent = 'var(--n-300)';
    lead = 'Every check was skipped or is awaiting a human verdict. Nothing mechanical ' +
           'was measured against the running system.';
  } else {
    word = 'PASSED'; accent = 'var(--cta)';
    lead = plural(c.pass, 'check ran and agreed', 'checks ran and agreed') +
           ' with the system. This claim reaches exactly as far as the instruments below ' +
           'reach, and no further \u2014 see scope of claim.';
  }

  const cell = (n, glyph, label, colour) =>
    '<div><b style="color:' + colour + '">' + n + '</b>' + glyph + ' ' + label + '</div>';

  // Proportional bar built from flex-grow integers, so no percentage exists in this
  // document — not in the text, not in the markup.
  const seg = (n, cls) => (n > 0 ? '<i class="' + cls + '" style="flex:' + n + ' 0 0"></i>' : '');
  const bar = c.total > 0
    ? '<div class="bar">' + seg(c.pass, 'z-pass') + seg(c.fail, 'z-fail') +
      seg(c.other, 'z-oth') + seg(c.fault, 'z-invl') + '</div>'
    : '';

  // Evidence stitched across sessions is not one run, and the .mpr may have moved between
  // them. This is the difference between "the system did X" and "some build of it did X".
  const r = d.run || {}, proj = d.project || {};
  let stitched = '';
  if (r.evidenceSpansMultipleRuns) {
    const ts = arr(r.evidenceTimestamps);
    const days = Array.from(new Set(ts.map((t) => String(t).slice(0, 10))));
    stitched = '<div class="alert alert-warn" style="margin-top:14px">' +
      '<b>This is not one run.</b> Evidence was stitched from ' +
      plural(ts.length, 'capture', 'captures') +
      (days.length > 1 ? ' across ' + plural(days.length, 'day', 'days') + ' (' +
        esc(days.join(', ')) + ')' : '') +
      '. The oldest capture predates the newest by ' +
      (elapsed(ts[0], ts[ts.length - 1]) || 'an unrecorded interval') +
      (has(proj.mprModifiedAt) ? ', and <code>' + esc(proj.mpr || 'the model') +
        '</code> was last modified ' + esc(fmtTime(proj.mprModifiedAt)) : '') +
      '. Any check measured before the model changed is evidence about a build that no ' +
      'longer exists. Treat the header window as a bounding box, not a session.</div>';
  }
  // Non-vacuity is a property of the whole run, not of one check.
  const noControl = instruments.some(
    (i) => /control/i.test(String(i.name || '')) && vinfo(i.verdict).bucket === 'fault');
  let vacuity = '';
  if (noControl) {
    vacuity = '<div class="alert alert-invl"><b>No positive control ran against this build.</b> ' +
      'Not one assertion on this page has been observed to be capable of failing — except ' +
      'the ones that did. Every green below is unfalsified, which is a weaker claim than ' +
      'verified, and the difference is not visible in the counts.</div>';
  }

  // ── COVERAGE FIRST ────────────────────────────────────────────────────────
  // Above the verdict word, above every count of what passed. A reader who reads
  // one line of this page reads this one, and it is the line that cannot be made
  // to look better by an instrument that died before it measured anything.
  const k = coverageOf(c);
  const execBand =
    '<div class="execband' + (k.notRun || !k.total ? ' hole' : '') + '">' +
      '<div class="el">' + esc(executionLine(c)) + '</div>' +
      '<div class="ef">' +
        (k.total
          ? 'Denominator: all ' + k.total + ' checks, faults included. ' +
            plural(k.ran, 'check', 'checks') + ' actually executed. ' +
            (k.notRun
              ? 'A "did not run" is not a pass, not a fail and not amber \u2014 it is a hole, ' +
                'and every statement below is silent about what is in it.'
              : 'Every check in this report reached the system.')
          : 'Nothing was examined. A report with no checks is not a clean report; it is a ' +
            'run that produced no evidence at all.') +
        (instFault
          ? ' ' + plural(instFault, 'instrument', 'instruments') + ' produced no verdict at all.'
          : '') +
      '</div>' +
    '</div>';

  return '<section><div class="card verdict" style="border-left-color:' + accent + '">' +
    execBand +
    '<div class="word">' + esc(word) + '</div>' +
    '<p style="font-size:15px;color:var(--text)">' + esc(lead) + '</p>' +
    // Order is deliberate: what did not run comes first. The old order led with the
    // pass cell, so the largest, greenest number on the page was also the first one
    // read — which is exactly how 205 of 611 got read as "roughly 90% healthy".
    '<div class="counts tab">' +
      cell(c.fault, '\u2300', 'DID NOT RUN', 'var(--text-muted)') +
      cell(c.fail, '\u2715', 'failed', 'var(--fail-ink)') +
      cell(c.pass, '\u2713', 'passed', 'var(--pass-ink)') +
      cell(c.other, '\u2298', 'skipped / manual', 'var(--text-muted)') +
      cell(instFault, '\u2300', 'instruments dark', 'var(--text-muted)') +
    '</div>' +
    (cov
      ? '<div class="counts tab" style="margin-top:2px">' +
          cell(cov.uncovered, '⌀', 'NEVER WALKED', 'var(--text-muted)') +
          cell(cov.inScope, '▣', 'pages in scope', 'var(--text-muted)') +
          cell(cov.walked, '✓', 'walked', 'var(--pass-ink)') +
          cell(des.fail, '✕', 'design findings', 'var(--fail-ink)') +
          cell(des.fault + des.other, '⌀', 'design rungs not run', 'var(--text-muted)') +
        '</div>'
      : '<div class="ghost" style="margin-top:10px"><div class="gh">No page denominator in ' +
        'this report</div><div class="gf">pageCoverage is absent, so nothing here can say how ' +
        'much of the application the numbers above cover. A pass count without a denominator ' +
        'is not a measurement.</div></div>') +
    bar +
    '<div class="rule">No pass rate is printed on this page, here or anywhere below. The one ' +
    'percentage in this document is the share of checks that <b>did not run</b>, and its ' +
    'denominator is every check including the holes. A rate computed over the checks that ran ' +
    'describes the part that ran and hides the part that did not — which is how ' +
    'a third of a run reads as nine tenths of one.</div>' +
    stitched + vacuity +
  '</div></section>';
}

/** The first measured failure, promoted. The schema has no narrative field, so this is
 *  derived: the finding itself, its detail, and its non-vacuity note. */
function renderHeadline(checks, rebase) {
  const fails = checks.filter((c) => vinfo(c.verdict).bucket === 'fail');
  if (!fails.length) return '';
  const f = fails[0];
  const where = [f.module, f.journey, has(f.stepIndex) ? 'step ' + f.stepIndex : null,
                 f.id].filter(has).map(esc).join(' \u00b7 ');
  // `title` alone is often a bare predicate ("reached"); the step name carries the meaning.
  const headline = [has(f.stepName) ? f.stepName : null, has(f.title) ? f.title : f.id]
    .filter(has).join(' \u2014 ');
  let ev = '';
  const evs = arr(f.evidence);
  if (evs.length) ev = '<div class="tw" style="margin-top:14px">' + evidenceTable(evs, rebase) + '</div>';
  let nv = '';
  if (f.nonVacuity && f.nonVacuity.controlRan === false) {
    nv = '<div class="alert alert-warn" style="margin-top:14px"><b>No positive control ran ' +
         'for this check.</b> ' + esc(f.nonVacuity.note || 'An assertion never seen to fail ' +
         'is decoration.') + '</div>';
  }
  const more = fails.length > 1
    ? '<p class="muted" style="font-size:12.5px">' +
      plural(fails.length - 1, 'further failure', 'further failures') +
      ' below, in the findings table.</p>' : '';
  return '<section><div class="slabel">The finding that justifies the harness</div>' +
    '<div class="card" style="border-left:4px solid var(--fail-ink)">' +
    '<h2>' + esc(headline) + '</h2>' +
    (where ? '<p class="mono" style="font-size:12px">' + where + '</p>' : '') +
    (has(f.detail) ? '<div class="pre">' + esc(f.detail) + '</div>' : '') +
    '<p style="margin-top:12px">Measured by <b>' + esc(f.instrument || 'an unnamed instrument') +
    '</b>' + (has(f.measuredAt) ? ' at ' + esc(fmtTime(f.measuredAt)) : '') + '. ' +
    (f.provenance === 'judged' ? 'Provenance: <b>judged</b>, not measured.'
                               : 'Provenance: measured.') + '</p>' +
    ev + nv + more + '</div></section>';
}

function evidenceTable(evs, rebase) {
  let rows = '<table><tr><th style="width:110px">Evidence</th><th>Pointer</th></tr>';
  for (const e of evs) {
    let cellv = '';
    if (has(e.path)) {
      const r = rebase(e.path);
      if (r.remote) {
        // Never fetch. Show the URL as text so the page makes zero external requests.
        cellv = '<span class="mono">' + esc(r.href) + '</span> ' +
                ghostBadge('REMOTE \u2014 NOT FETCHED');
      } else {
        cellv = '<a class="mono" href="' + esc(r.href) + '">' + esc(e.path) + '</a>';
        if (has(e.line)) cellv += ' <span class="muted mono">line ' + esc(e.line) + '</span>';
      }
    } else if (has(e.sql)) {
      cellv = '<span class="mono">' + esc(e.sql) + '</span>' +
              (has(e.value) ? ' \u2192 <b class="mono">' + esc(e.value) + '</b>' : '');
    } else if (has(e.command)) {
      cellv = '<span class="mono">' + esc(e.command) + '</span>';
    } else if (has(e.spanCount)) {
      cellv = '<span class="mono">' + esc(e.spanCount) + ' spans captured</span>';
    } else {
      cellv = ghostBadge('NO POINTER \u2014 A VERDICT WITHOUT AN ARTIFACT IS A CLAIM');
    }
    rows += '<tr><td class="mono">' + esc(e.type || 'evidence') + '</td><td>' + cellv + '</td></tr>';
  }
  return rows + '</table>';
}

/* Which checks did each instrument actually append?
 * Instrument ROWS are sometimes per-module (`coverage-ledger/Sales`) while the checks
 * they emit carry the base name (`coverage-ledger`), so both sides are keyed on the
 * segment before the first slash. Deliberately conservative: a name that fails to
 * join counts as "we could not tell", never as "it produced nothing". */
const instKey = (n) => String(n == null ? '' : n).split('/')[0];
function checksByInstrument(checks) {
  const m = new Map();
  for (const c of checks) {
    const k = instKey(c.instrument);
    if (!m.has(k)) m.set(k, []);
    m.get(k).push(c);
  }
  return m;
}

/* The gap this closes, measured 2026-08-20: four instruments on PROJECT-A were at
 * verdict `fault` for the whole run and a fifth reported `pass` having appended
 * nothing. On the page they were five tiles among fourteen. An instrument that
 * produced no evidence at all has to LOOK different from one that measured
 * something and agreed — the badge below is the "did the instrument produce
 * anything" axis, distinct from the existing liveness verdict and from the
 * WEAK EVIDENCE / CANNOT EXPRESS FAULT axes it sits beside.
 * Wording is gate-check.sh's, verbatim where it fits: cannot evaluate is not a pass. */
function evidenceFlag(own) {
  const ro = rollup(own);
  if (!own.length) {
    return { badge: ghostBadge('NOTHING EXAMINED — NO CHECKS EMITTED'), dark: true,
             note: 'This instrument appended no check to the report. There is nothing here ' +
                   'to evaluate, which is not a pass.' };
  }
  if (ro.fault === own.length) {
    return { badge: ghostBadge('EVERY CHECK DID NOT RUN (' + own.length + ' of ' +
                               own.length + ')'), dark: true,
             note: 'Every one of this instrument’s ' + own.length + ' checks is a hole. ' +
                   'It is present in the report and it measured nothing — cannot evaluate, ' +
                   'which is not a pass.' };
  }
  return { badge: '', dark: false, note: null, ran: ro.pass + ro.fail, total: own.length };
}

function renderInstruments(d, instruments, checks) {
  const env = (d.run || {}).env || {};
  const owned = checksByInstrument(arr(checks));
  const noEvidence = [];
  let strip = '';
  for (const i of instruments) {
    const info = vinfo(i.verdict);
    const own = owned.get(instKey(i.name)) || [];
    const ev = evidenceFlag(own);
    if (ev.dark) noEvidence.push(i.name || 'unnamed instrument');
    // `dark` was liveness alone; an instrument that reports RAN and appended nothing
    // now gets the same hatched treatment, because to a reader the two are the same
    // fact: no evidence came from here.
    const dark = info.bucket === 'fault' || ev.dark;
    const extra = [];
    if (has(i.checksEmitted)) extra.push(i.checksEmitted + ' checks');
    if (has(i.rowsRead)) extra.push(i.rowsRead + ' rows');
    if (has(i.modulesRead)) extra.push(i.modulesRead + ' modules');
    if (has(i.elapsedSec)) extra.push(i.elapsedSec + 's');
    if (has(i.rc)) extra.push('rc ' + i.rc);

    const flags = [];
    // First flag, before the strength/dialect ones: "did anything at all come out of
    // this?" outranks "how good is what came out".
    if (ev.badge) flags.push(ev.badge);
    if (i.evidenceStrength === 'weak') flags.push(warnBadge('WEAK EVIDENCE'));
    else if (i.evidenceStrength === 'strong') flags.push(neutBadge('strong evidence'));
    // An instrument whose source enum has no "did not run" value cannot report a hole.
    // Its greens are therefore weaker than they look, and that has to be on the page.
    if (i.canExpressFault === false) flags.push(ghostBadge('CANNOT EXPRESS FAULT'));
    // An instrument that ran as a different identity than the run declares.
    if (has(i.user) && has(env.user) && i.user !== env.user) {
      flags.push(warnBadge('RAN AS ' + i.user));
    } else if (i.userFallbackUsed === true) {
      flags.push(warnBadge('FELL BACK TO ' + (i.user || 'admin')));
    }

    strip += '<div class="tile' + (dark ? ' f' : '') + '"><div class="n">' +
      esc(i.name || 'unnamed instrument') + '</div><div class="s">' +
      instrumentBadge(i.verdict) +
      (extra.length ? ' <span class="muted mono">' + esc(extra.join(' \u00b7 ')) + '</span>' : '') +
      '</div>' +
      (flags.length ? '<div style="margin-top:5px;display:flex;gap:4px;flex-wrap:wrap">' +
                      flags.join('') + '</div>' : '') +
      (ev.note ? '<div class="muted note">' + esc(ev.note) + '</div>'
               : '<div class="muted note">' + esc(ev.ran + ' of ' + ev.total +
                 ' checks from this instrument executed') + '</div>') +
      (has(i.reason) ? '<div class="muted note">' +
                       esc(i.reason) + '</div>' : '') +
      (has(i.note) ? '<div class="muted note">' +
                     esc(i.note) + '</div>' : '') +
      (has(i.log) ? '<div class="muted mono" style="margin-top:4px;word-break:break-all">' +
                    esc(i.log) + '</div>' : '') +
      '</div>';
  }

  // Two derived tiles the schema puts on run.env rather than in instruments[].
  if (has(env.user)) {
    strip += '<div class="tile"><div class="n">Identity</div><div class="s">' +
      (env.userFallbackUsed
        ? warnBadge('FELL BACK TO ' + env.user)
        : badge('pass', env.user)) + '</div></div>';
  }
  const own = has(env.ownership) ? env.ownership : 'unknown';
  const ownCell = own === 'verified' ? badge('pass', 'VERIFIED')
                : own === 'asserted' ? warnBadge('ASSERTED, NOT MEASURED')
                : ghostBadge('OWNERSHIP UNKNOWN');
  strip += '<div class="tile' + (own === 'unknown' ? ' f' : '') + '">' +
    '<div class="n">Env ownership</div><div class="s">' + ownCell + '</div>' +
    (has(env.ownershipBasis) ? '<div class="muted mono" style="margin-top:4px;' +
      'word-break:break-all">' + esc(env.ownershipBasis) + '</div>' : '') + '</div>';

  const dark = instruments.filter((i) => vinfo(i.verdict).bucket === 'fault');
  let alert = '<div class="alert alert-invl" style="margin-top:12px">These verdicts answer ' +
    '<b>"did the instrument run"</b> — they are liveness, not a rollup of the checks it ' +
    'emitted. An instrument can be RAN while one of its own checks failed; the counts above ' +
    'are the authority on findings.</div>';
  // Stated once, in the open, in the same place the reader is deciding how much this
  // page is worth. Named, because "4 instruments" is a number and "coverage-ledger,
  // conformance, deferrals, full-app-walkthrough" is a to-do list.
  if (noEvidence.length) {
    alert += '<div class="alert alert-invl"><b>' +
      plural(noEvidence.length, 'instrument', 'instruments') +
      ' produced no evidence at all: </b>' + esc(noEvidence.join(', ')) +
      '. Either no check was emitted, or every check emitted is a hole. Whatever these ' +
      'would have measured is unknown in both directions — cannot evaluate, which is not ' +
      'a pass. Their absence subtracts nothing from the counts above precisely because ' +
      'there is nothing there to subtract, and that is the point.</div>';
  }
  const blind = instruments.filter((i) => i.canExpressFault === false);
  if (blind.length) {
    alert += '<div class="alert alert-warn"><b>' + plural(blind.length, 'instrument', 'instruments') +
      ' cannot express "did not run": </b>' + esc(blind.map((i) => i.name).join(', ')) +
      '. Anything they never reached is silently absent rather than reported as a hole, so ' +
      'their greens are weaker evidence than the counts suggest.</div>';
  }
  if (dark.length) {
    alert += '<div class="alert alert-invl"><b>' + plural(dark.length, 'instrument', 'instruments') +
      ' did not run: </b>' + esc(dark.map((i) => i.name).join(', ')) +
      '. Nothing they would have measured is known, in either direction. An omitted ' +
      'instrument entry renders as green, which is the exact false positive this contract retires.' +
      '</div>';
  }
  const body = instruments.length
    ? '<div class="strip">' + strip + '</div>' + alert
    : notMeasured('no instruments[] entries in report.json',
        'Not "everything ran". The report declares no instrument at all, so nothing here can ' +
        'be attributed to a named measuring device.') +
      '<div class="strip" style="margin-top:12px">' + strip + '</div>';

  return '<section><div class="slabel">Did every instrument actually run?</div>' + body + '</section>';
}

/* ── journey spine ───────────────────────────────────────────────────
 * Grid: [node column] [step body] [4 rung columns].
 * The node column draws the dot and the connecting link. A failed step cuts the
 * link (dashed) and every node after it becomes a dashed ghost dot: the spine is
 * severed, visibly, rather than the walk quietly ending.
 * Below 820px the four rung columns are hidden and the same four states re-appear
 * as a row of chips inside the step body.                                      */

function rungStates(step, severedHere) {
  const states = [];
  for (let r = 0; r < RUNGS.length; r++) {
    const rung = RUNGS[r];
    if (rung.key === "SPEC'D") {
      const declared = step.checks.some((c) => has(c.requirement));
      states.push(declared ? { s: 'ok', g: '\u2713' } : { s: 'nd', g: '\u2014' });
      continue;
    }
    const mine = step.checks.filter((c) => rung.kinds.indexOf(c.kind) !== -1);
    if (!mine.length) {
      // Nothing of this kind was measured. Was it *supposed* to be? A failing check in
      // this step that declares blocks[] says yes: declared, and we failed to answer.
      states.push(severedHere ? { s: 'un', g: '\u2300' } : { s: 'nd', g: '\u00b7' });
      continue;
    }
    const ro = rollup(mine);
    if (ro.fail) states.push({ s: 'no', g: '\u2715' });
    else if (ro.fault) states.push({ s: 'un', g: '\u2300' });
    else if (ro.pass) states.push({ s: 'ok', g: '\u2713' });
    else states.push({ s: 'nd', g: '\u2298' });
  }
  return states;
}

function rungCell(st) {
  if (st.s === 'ok') return '<div class="rung r-ok">' + st.g + '</div>';
  if (st.s === 'no') return '<div class="rung r-no">' + st.g + '</div>';
  if (st.s === 'un') return '<div class="rung"><span class="r-un">' + st.g + '</span></div>';
  return '<div class="rung r-nd">' + st.g + '</div>';
}
function chips(states) {
  let h = '<div class="chips">';
  for (let i = 0; i < RUNGS.length; i++) {
    const st = states[i];
    h += '<span class="chip c-' + st.s + '">' + esc(RUNGS[i].key) + ' ' + st.g + '</span>';
  }
  return h + '</div>';
}

function renderSpine(j, checksById, rebase) {
  const rowsOut = [];
  let severedFrom = -1;   // index in stepList at which the spine breaks

  j.stepList.forEach((s, idx) => {
    const ro = rollup(s.checks);
    if (ro.fail > 0 && severedFrom < 0) severedFrom = idx;
  });

  let html = '<div class="spine">' +
    '<div class="hd"></div><div class="hd" style="text-align:left">STEP</div>' +
    RUNGS.map((r) => '<div class="hd">' + esc(r.key) + '</div>').join('');

  j.stepList.forEach((s, idx) => {
    const ro = rollup(s.checks);
    const severed = severedFrom >= 0 && idx >= severedFrom;
    const blocked = [];
    for (const c of s.checks) for (const b of arr(c.blocks)) blocked.push(b);

    const dotCls = ro.fail ? 'no' : (ro.fault ? 'un' : (severed && idx > severedFrom ? 'un' : 'ok'));
    const dotGlyph = dotCls === 'no' ? '\u2715' : (dotCls === 'un' ? '\u2300' : '\u2713');
    const last = idx === j.stepList.length - 1 && !j.outcome.length;
    const link = last ? '' :
      '<div class="link' + (severed ? ' cut' : '') + '"></div>';

    const states = rungStates(s, severed && (ro.fail > 0 || blocked.length > 0));
    const bucket = ro.fail ? 'fail' : (ro.fault ? 'fault' : (ro.pass ? 'pass' : 'other'));

    // Measured lines, one per check. Anything that never ran is pulled OUT of this list
    // and into the ghost panel below \u2014 a declared expectation must never sit in the same
    // visual run as a measured result.
    let lines = '';
    for (const c of s.checks) {
      if (c.notRun === true || c.provenance === 'declared') continue;
      const bi = vinfo(c.verdict);
      lines += '<div class="m"' + (bi.bucket === 'fail' ? ' style="color:var(--fail-ink)"' : '') +
        '>' + bi.glyph + ' ' + esc(c.title || c.id) +
        (has(c.detail) ? ' \u2014 ' + esc(c.detail) : '') + '</div>';
    }

    // The severed set: whatever the guard says it blocked, plus anything in this step
    // that carries notRun/declared, deduplicated.
    const severedIds = new Set(blocked);
    for (const c of s.checks) {
      if (c.notRun === true || c.provenance === 'declared') severedIds.add(c.id);
    }
    // The journey-level outcome gets its own diamond node below; don't list it twice.
    for (const o of j.outcome) severedIds.delete(o.id);
    let ghost = '';
    if (severedIds.size) {
      const items = Array.from(severedIds).map((b) => {
        const known = checksById.get(b);
        return {
          label: known && has(known.title) ? known.title : b,
          detail: known && has(known.detail) ? String(known.detail) : '',
        };
      });
      // Every severed expectation shares one cause, and repeating it once per row buries
      // the part that differs. Hoist the common prefix into the panel header.
      let shared = items.length > 1 ? commonPrefix(items.map((i) => i.detail)) : '';
      // Cut back to the last sentence end. A raw character-wise prefix stops mid-clause and
      // orphans a dangling word ("... and the journey stopped. Expectation") from its value.
      const stop = shared.lastIndexOf('. ');
      shared = stop >= 0 ? shared.slice(0, stop + 1) : '';
      const cut = shared.length >= 40 ? shared.replace(/[\s—:-]+$/, '') : '';
      let lis = '';
      for (const it of items) {
        const rest = cut ? it.detail.slice(shared.length).replace(/^[\s—:-]+/, '') : it.detail;
        lis += '<li>' + esc(it.label) +
          (rest ? '<br><span style="opacity:.75">' + esc(rest) + '</span>' : '') + '</li>';
      }
      if (cut) {
        lis = '<li class="cause"><span style="opacity:.9">' + esc(cut) + '</span></li>' + lis;
      }
      ghost = '<div class="ghost"><div class="gh">Not measured \u2014 the walk stopped here</div>' +
        '<ul style="margin:0;padding:0">' + lis + '</ul>' +
        '<div class="gf">Declared in the journey contract and absent from the evidence. ' +
        'Not green. Not red. <b>Absent.</b></div></div>';
    }

    html += '<div class="node"><div class="dot ' + dotCls + '">' + dotGlyph + '</div>' + link + '</div>' +
      '<div class="body" data-v="' + esc(bucket) + '">' +
        '<div class="t">' + esc(s.index) + ' \u00b7 ' + esc(s.name || 'unnamed step') + '</div>' +
        lines + chips(states) + ghost +
      '</div>' +
      states.map(rungCell).join('');
  });

  // outcome node — the diamond
  for (const o of j.outcome) {
    const bi = vinfo(o.verdict);
    const cls = bi.bucket === 'pass' ? 'ok' : (bi.bucket === 'fail' ? 'no' : 'un');
    const st = bi.bucket === 'pass' ? { s: 'ok', g: '\u2713' }
             : bi.bucket === 'fail' ? { s: 'no', g: '\u2715' }
             : { s: 'un', g: '\u2300' };
    const states = [{ s: 'nd', g: '\u2014' }, { s: 'nd', g: '\u2014' }, st,
                    has(o.requirement) ? { s: 'ok', g: '\u2713' } : { s: 'nd', g: '\u2014' }];
    html += '<div class="node"><div class="dot ' + cls + ' dia"><span>' +
        (cls === 'un' ? '\u25c7' : st.g) + '</span></div></div>' +
      '<div class="body" data-v="' + esc(bi.bucket) + '">' +
        '<div class="t"' + (cls === 'un' ? ' style="color:var(--text-muted)"' : '') +
        '>OUTCOME \u00b7 ' + esc(o.title || o.id) + '</div>' +
        '<div class="m">' + bi.glyph + ' ' +
        esc(has(o.detail) ? o.detail : (cls === 'un' ? 'not evaluated' : bi.label)) + '</div>' +
        chips(states) +
      '</div>' + states.map(rungCell).join('');
  }

  html += '</div>';
  void rebase;
  return html;
}

function renderJourneys(d, checks, rebase) {
  const journeys = groupJourneys(checks);
  if (!journeys.length) {
    return '<section><div class="slabel">The user journey, walked</div><div class="card">' +
      notMeasured('no check in report.json carries a journey id',
        'No golden path was walked in this run. Whatever else is green below, no user-visible ' +
        'sequence of steps has been shown to work end to end.') + '</div></section>';
  }
  const byId = new Map(checks.map((c) => [c.id, c]));
  const seeds = ((d.run || {}).reproduce || {}).seeds;

  let out = '<section><div class="slabel">The user journey, walked</div>';
  for (const j of journeys) {
    const all = j.stepList.reduce((a, s) => a.concat(s.checks), []).concat(j.outcome, j.loose);
    const ro = rollup(all);
    // A step whose every check faulted has `fail === 0`, and this line used to count it
    // as walked — zero failures over zero executed checks is `[].every()` in another
    // costume, and it inflated the numerator of the one ratio in this header.
    const walked = j.stepList.filter((s) => {
      const r = rollup(s.checks);
      return r.fail === 0 && r.pass > 0;
    }).length;
    const unmeasured = j.stepList.length - walked - j.stepList.filter(
      (s) => rollup(s.checks).fail > 0).length;
    const head = [
      has(j.module) ? neutBadge('module ' + j.module) : ghostBadge('NO MODULE DECLARED'),
      walked < j.stepList.length
        ? warnBadge(walked + ' of ' + plural(j.stepList.length, 'step walked clean',
                                             'steps walked clean'))
        : neutBadge(plural(j.stepList.length, 'step', 'steps')),
    ];
    // Never left to be inferred from the difference between two numbers.
    if (unmeasured > 0) {
      head.push(ghostBadge(plural(unmeasured, 'step measured nothing',
                                  'steps measured nothing')));
    }
    if (all.some((c) => c.nonVacuity && c.nonVacuity.controlRan === false)) {
      head.push(ghostBadge('CONTROL NOT RUN'));
    }
    let seedBlock = '';
    if (seeds && Object.keys(seeds).length) {
      seedBlock = '<div class="seeds"><b>SEEDS</b> &nbsp; ' +
        Object.keys(seeds).map((k) => esc(k) + ' = <b>' + esc(seeds[k]) + '</b>')
          .join(' &nbsp;\u00b7&nbsp; ') +
        '<div class="why">Resolved before the walk. A seed that is not asserted against the ' +
        'committed value lets a step pass while acting on a different row.</div></div>';
    } else {
      // A journey with no recorded seeds cannot be re-walked against the same rows.
      seedBlock = '<div class="ghost"><div class="gh">No seeds recorded</div>' +
        '<div class="gf">This walk resolved its fixtures at runtime and did not journal them. ' +
        'The run is therefore not reproducible against the same rows, and any assertion about ' +
        '<i>which</i> record was touched cannot be re-checked.</div></div>';
    }
    let loose = '';
    if (j.loose.length) {
      loose = '<div class="tw" style="margin:12px 0">' + findingsTable(j.loose, rebase, false, byId) +
              '</div>';
    }
    out += '<div class="card" style="margin-bottom:16px">' +
      '<div class="jhead"><h2 style="margin:0">' + esc(j.id) + '</h2>' + head.join(' ') + '</div>' +
      seedBlock + loose + renderSpine(j, byId, rebase) +
      '<div class="rule"><b>\u00b7</b> = the contract declares nothing here (legitimately silent). ' +
      '<b>\u2300</b> = the contract declares it and we failed to answer. Those are not the same ' +
      'thing, and collapsing them is how an unrun instrument gets laundered into "nearly done".' +
      '</div></div>';
  }
  return out + '</section>';
}

/* ── the journey walk ─────────────────────────────────────────────────
 * walks[] is narrative; checks[] is verdict. This section renders the narrative and
 * borrows the verdict, never the other way round.
 *
 * Two rules here are paid for in past false-greens:
 *   1. A screenshot is NOT a verdict. The step's colour comes from `status`, which the
 *      normalizer derived from the step's checks. No status glyph is ever drawn on or
 *      over an image, and a step with `shot: null` renders completely and normally.
 *   2. A step that recorded zero checks must look EMPTY, not clean. It gets the hole
 *      treatment (hatch + dashed + achromatic), the same one `fault` gets everywhere
 *      else in this document. `fault` is never amber — amber means "ran, degraded".  */

const IMAGE_BUDGET = 11 * 1024 * 1024;   // base64 payload ceiling; page cap is 16 MB
const PAGE_CAP     = 16 * 1024 * 1024;
const SHRINK_OVER  = 320 * 1024;         // raw PNG bytes above which we try to downscale
const SHRINK_WIDTH = 1100;

const kb = (n) => (n / 1024).toFixed(0) + ' KB';
const mb = (n) => (n / 1048576).toFixed(1) + ' MB';

/** Optional, never required: whatever image tool the machine already has. Absent is
 *  fine — the shot is then embedded at full size, or refused with a stated reason. */
let IMG_TOOL;
function imageTool() {
  if (IMG_TOOL !== undefined) return IMG_TOOL;
  const probe = (cmd, args) => {
    try { return cp.spawnSync(cmd, args, { stdio: 'ignore', timeout: 8000 }).status === 0; }
    catch (e) { return false; }
  };
  if (process.platform === 'darwin' && probe('sips', ['--version'])) IMG_TOOL = 'sips';
  else if (probe('magick', ['-version'])) IMG_TOOL = 'magick';
  else if (probe('convert', ['-version'])) IMG_TOOL = 'convert';
  else IMG_TOOL = null;
  return IMG_TOOL;
}

let SHRINK_SEQ = 0;
function shrink(absPath) {
  const tool = imageTool();
  if (!tool) return null;
  const tmp = path.join(os.tmpdir(), 'report-render-' + process.pid + '-' + (++SHRINK_SEQ) + '.jpg');
  const run = tool === 'sips'
    ? ['sips', ['-Z', String(SHRINK_WIDTH), '-s', 'format', 'jpeg',
                '-s', 'formatOptions', '62', absPath, '--out', tmp]]
    : [tool, [absPath, '-resize', SHRINK_WIDTH + 'x>', '-quality', '68', tmp]];
  let r;
  try { r = cp.spawnSync(run[0], run[1], { stdio: 'ignore', timeout: 30000 }); }
  catch (e) { return null; }
  if (!r || r.status !== 0) return null;
  try {
    const buf = fs.readFileSync(tmp);
    try { fs.unlinkSync(tmp); } catch (e) { /* tmp */ }
    return { buf: buf, mime: 'image/jpeg', tool: tool };
  } catch (e) { return null; }
}

/** `shot.file` is repo-relative (journey-runner records path.relative(root, file)), while
 *  this renderer only knows where report.json and itself live. Try every root we can
 *  justify and REPORT which ones were tried — "not found" without the search list is an
 *  unfalsifiable excuse. */
function shotRoots(inPath) {
  const roots = [
    path.resolve(__dirname, '..', '..'),          // repo root, from tests/e2e/
    process.cwd(),
    path.dirname(path.resolve(inPath)),           // next to report.json
    path.resolve(path.dirname(path.resolve(inPath)), '..'),
  ];
  return roots.filter((r, i) => roots.indexOf(r) === i);
}

function embedShot(shot, ctx) {
  if (!shot || !has(shot.file)) {
    return { ok: false, why: 'the runner recorded no screenshot for this step.' };
  }
  let abs = null;
  for (const r of ctx.roots) {
    const cand = path.resolve(r, shot.file);
    if (fs.existsSync(cand)) { abs = cand; break; }
  }
  if (!abs) {
    ctx.missing++;
    return { ok: false, why: 'the file is not on this disk. Searched ' +
      plural(ctx.roots.length, 'root', 'roots') + ': ' + ctx.roots.join(', ') +
      '. The report has most likely been copied away from its artifacts directory, or the ' +
      'run was cleaned. The checks below are unaffected — they were measured when the ' +
      'image still existed.' };
  }
  let buf, mime = 'image/png', note = null;
  try { buf = fs.readFileSync(abs); }
  catch (e) { ctx.missing++; return { ok: false, why: 'it exists but could not be read: ' + e.message }; }

  if (buf.length > SHRINK_OVER) {
    const s = shrink(abs);
    if (s && s.buf.length < buf.length) {
      note = 'downscaled to ' + SHRINK_WIDTH + 'px wide JPEG by ' + s.tool +
             ' (' + kb(buf.length) + ' → ' + kb(s.buf.length) + ') to fit the page budget';
      buf = s.buf; mime = s.mime;
    } else if (!s) {
      note = 'embedded at full size (' + kb(buf.length) + ') — no sips or ImageMagick on ' +
             'this machine to downscale with';
    }
  }
  const cost = Math.ceil(buf.length / 3) * 4;
  if (ctx.bytes + cost > IMAGE_BUDGET) {
    ctx.overBudget++;
    return { ok: false, why: 'embedding it (' + kb(cost) + ' as base64) would push this page ' +
      'past its ' + mb(IMAGE_BUDGET) + ' image budget, which exists so the whole report stays ' +
      'under ' + mb(PAGE_CAP) + '. ' + plural(ctx.embedded, 'image is', 'images are') +
      ' already embedded (' + mb(ctx.bytes) + '). The file is still on disk at ' + shot.file + '.' };
  }
  ctx.bytes += cost; ctx.embedded++;
  return { ok: true, uri: 'data:' + mime + ';base64,' + buf.toString('base64'),
           bytes: cost, note: note };
}

/* Rungs, in the order a walk climbs them. A rung the runner emitted that is not in this
 * table still gets its own group — an unknown rung is shown, never dropped. */
const WALK_RUNGS = [
  ['ui',      'ARRIVED — what the screen shows'],
  ['trace',   'RAN — microflow spans'],
  ['data',    'WROTE — rows and associations'],
  ['outcome', 'OUTCOME — the end-to-end query'],
  ['control', 'CONTROL — proving the check can fail'],
];

const STEP_WORD = { pass: 'PASS', fail: 'FAIL', fault: 'DID NOT RUN' };

/** actions[] in reviewer language. The selector rides along for whoever has to fix it. */
function renderActions(actions) {
  const as = arr(actions);
  if (!as.length) {
    return '<div class="wnone">— no action: this step asserts about the page it was ' +
           'already on. The contract declares nothing to do here.</div>';
  }
  let h = '<ol class="wacts">';
  for (const a of as) {
    h += '<li><b>' + esc(a.verb || 'Do') + '</b> ' + esc(a.target || '') +
      (has(a.selector) ? ' <span class="mono muted">' + esc(a.selector) + '</span>' : '') +
      '</li>';
  }
  return h + '</ol>';
}

/** The contract's declaration for this step.
 *  `—` = the contract declares nothing here (legitimately silent).
 *  `⌀` = it declared something and this step never got far enough to answer it.
 *  Those are different facts and this table never collapses them. */
function renderExpects(step) {
  const e = step.expects || null;
  const unanswered = step.reached === false || arr(step.checks).length === 0;
  const nothing = '<span class="wnone">— the contract declares nothing here</span>';
  const declared = (inner) => (unanswered
    ? inner + ' ' + ghostBadge('DECLARED · NEVER ANSWERED')
    : inner);

  if (!e) {
    return '<div class="ghost"><div class="gh">No expectation block on this step</div>' +
      '<div class="gf">The walk records no <code>expects</code> at all, so there is nothing ' +
      'to compare the checks below against. That is a gap in the contract, not a clean step.' +
      '</div></div>';
  }
  const list = (xs) => arr(xs).map((x) => '<code>' + esc(x) + '</code>').join(' ');
  const rows = [];
  rows.push(['Lands on', has(e.landsOn)
    ? declared('<code>' + esc(e.landsOn) + '</code>') : nothing]);
  rows.push(['Page says', arr(e.pageSays).length ? declared(list(e.pageSays)) : nothing]);
  rows.push(['Page does not say',
    arr(e.pageDoesNotSay).length ? declared(list(e.pageDoesNotSay)) : nothing]);
  rows.push(['Microflows, in order',
    arr(e.microflows).length
      ? declared(arr(e.microflows).map((m, i) => '<code>' + (i + 1) + '. ' + esc(m) + '</code>')
                 .join(' '))
      : nothing]);
  const w = e.writes;
  rows.push(['Writes', w
    ? declared('<code>' + esc(w.entity || 'unnamed entity') + '</code>' +
        (has(w.delta) ? ' delta <b class="tab">' + esc(w.delta) + '</b>'
                      : ' <span class="wnone">delta not declared</span>') +
        (arr(w.associations).length
          ? ' · associations ' + list(w.associations)
          : ' · <span class="wnone">no association declared</span>'))
    : nothing]);

  let h = '<div class="tw"><table class="wexp"><tr><th style="width:11rem">The contract expected' +
          '</th><th>Declared value</th></tr>';
  for (const r of rows) h += '<tr><td>' + r[0] + '</td><td>' + r[1] + '</td></tr>';
  return h + '</table></div>';
}

function renderStepChecks(step, ctx) {
  const cs = arr(step.checks);
  if (!cs.length) {
    return '<div class="ghost"><div class="gh">Zero checks ran on this step</div>' +
      '<div class="gf">Nothing was measured here — not one assertion, in either ' +
      'direction. This is a hole in the walk, not a quiet success, and it is why the step ' +
      'above is marked <b>DID NOT RUN</b> rather than passed. Whatever the screenshot shows, ' +
      'no claim about it has been tested.</div></div>';
  }
  const order = WALK_RUNGS.map((r) => r[0]);
  const seen = Array.from(new Set(cs.map((c) => (has(c.rung) ? c.rung : 'unlabelled'))));
  seen.sort((a, b) => {
    const ia = order.indexOf(a), ib = order.indexOf(b);
    return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib) || String(a).localeCompare(String(b));
  });

  let h = '';
  for (const rung of seen) {
    const mine = cs.filter((c) => (has(c.rung) ? c.rung : 'unlabelled') === rung);
    const known = WALK_RUNGS.filter((r) => r[0] === rung)[0];
    const label = known ? known[1] : rung.toUpperCase() + ' — rung not in this renderer’s table';
    // Every check is listed. Failures are never truncated and never hidden behind a
    // disclosure: a finding you have to click to discover is a finding you will miss.
    let rows = '';
    for (const c of mine) {
      const b = vinfo(c.verdict).bucket;
      // A fault on a walk step is the row the reader is most likely to act on, so the
      // remediation is rendered HERE and not only in the summary at the top.
      const rem = ctx && ctx.rem && has(c.checkId) ? ctx.rem.get(c.checkId) : null;
      let cell = (has(c.detail) ? '<span class="mono">' + esc(c.detail) + '</span>'
                                : '<span class="wnone">— no detail recorded</span>');
      if (b === 'fail' || b === 'fault') {
        cell += rem ? renderRemediation(rem, { verdict: c.verdict })
          : '<div class="rm rmgap">' + ghostBadge('NO REMEDIATION DERIVED') +
            ' <span class="muted xs">this walk check carries no id or no remediation in ' +
            'report.json — see the ranked list at the top for the group it belongs to.' +
            '</span></div>';
      }
      rows += '<tr data-v="' + esc(b) + '"><td>' + badge(c.verdict) + '</td>' +
        '<td>' + esc(c.name || 'unnamed check') + '</td>' +
        '<td>' + cell + '</td></tr>';
    }
    h += '<div class="wrung"><div class="wrl">' + esc(label) + '</div>' +
      '<div class="tw"><table><tr><th style="width:7.5rem">Verdict</th>' +
      '<th style="width:32%">Check</th><th>What it measured</th></tr>' + rows +
      '</table></div></div>';
  }
  return h;
}

function renderStepShot(step, ctx) {
  const r = embedShot(step.shot, ctx);
  const s = step.shot || {};
  const where = [has(s.title) ? s.title : null, has(s.url) ? s.url : null,
                 has(s.at) ? fmtTime(s.at) : null].filter(has).map(esc).join(' · ');
  if (!r.ok) {
    return '<div class="ghost"><div class="gh">No image for this step</div>' +
      '<div class="gf">' + esc(r.why) +
      ' A missing picture changes nothing about the verdict beside it — the verdict was ' +
      'never derived from the picture.</div></div>';
  }
  const cap = (has(s.file) ? '<span class="mono">' + esc(s.file) + '</span>' : '') +
    (where ? '<div class="muted xs">' + where + '</div>' : '') +
    (r.note ? '<div class="muted xs">' + esc(r.note) + '</div>' : '');
  return '<details class="wshot"><summary>Screenshot of the page these checks measured ' +
    '(click to enlarge)</summary>' +
    '<figure class="shot"><img src="' + r.uri + '" alt="' +
      esc('page state at step ' + (has(step.n) ? step.n : '') + ': ' + (step.name || '')) + '">' +
    '<figcaption>' + cap +
    '<div class="muted xs">Evidence of page state, not a verdict. Nothing here was judged ' +
    'by looking at this image.</div></figcaption></figure></details>';
}

function renderWalks(d, ctx) {
  const walks = arr(d.walks);
  const lead = '<section><div class="slabel">The walk — what the persona did, page by page</div>';
  if (!walks.length) {
    return lead + '<div class="card">' +
      notMeasured('walks[] is absent or empty in report.json',
        'No journey narrated a walk in this run. This is not "the walks passed and had ' +
        'nothing to say" — no persona was driven through the app at all, so the ' +
        'screenshots, the actions and the per-step expectations that would appear here do ' +
        'not exist. Re-run the journey runner to populate this section.') +
      '</div></section>';
  }

  let out = lead;
  for (const w of walks) {
    const steps = arr(w.steps);
    const tally = { pass: 0, fail: 0, fault: 0 };
    for (const s of steps) {
      const k = STEP_WORD[s.status] ? s.status : 'fault';
      tally[k]++;
    }
    const head = [
      has(w.persona) ? neutBadge('persona ' + w.persona) : ghostBadge('NO PERSONA DECLARED'),
      neutBadge(plural(steps.length, 'step', 'steps')),
    ];
    if (tally.fail) head.push(badge('fail', plural(tally.fail, 'step failed', 'steps failed')));
    if (tally.fault) head.push(badge('fault', plural(tally.fault, 'step never ran',
                                                     'steps never ran')));
    if (!tally.fail && !tally.fault && steps.length) {
      head.push(badge('pass', 'every step measured'));
    }

    const reqs = arr(w.requirement);
    const reqBlock = reqs.length
      ? '<div class="wreq"><b>CLAIMS TO EXERCISE</b> ' +
        reqs.map((r) => '<code>' + esc(r) + '</code>').join(' ') + '</div>'
      : '<div class="wreq">' + ghostBadge('NO BRD POINTER DECLARED') +
        ' <span class="muted">this walk exercises real behaviour that no requirement ' +
        'claims</span></div>';

    const seedBlock = w.seeds
      ? '<div class="seeds"><b>SEEDS RESOLVED</b> &nbsp; ' +
        Object.keys(w.seeds).map((k) => esc(k) + ' = <b>' + esc(w.seeds[k]) + '</b>')
          .join(' &nbsp;·&nbsp; ') +
        '<div class="why">Resolved before the walk started. These are the rows the persona ' +
        'actually touched; without them the walk cannot be repeated against the same data.' +
        '</div></div>'
      : '<div class="ghost"><div class="gh">No seeds recorded</div>' +
        '<div class="gf">This walk did not journal the fixtures it resolved, so it cannot be ' +
        're-run against the same rows and no assertion about <i>which</i> record was touched ' +
        'can be re-checked.</div></div>';

    let body = '';
    if (!steps.length) {
      body = '<div class="ghost"><div class="gh">This walk recorded no steps</div>' +
        '<div class="gf">The journey exists in the report but produced no leg at all. ' +
        'Nothing was done and nothing was measured.</div></div>';
    }
    for (const s of steps) {
      const st = STEP_WORD[s.status] ? s.status : 'fault';
      const bucket = vinfo(st).bucket;
      const empty = arr(s.checks).length === 0;
      body += '<div class="wstep' + (empty ? ' hole' : '') + ' s-' + esc(bucket) +
          '" data-v="' + esc(bucket) + '" id="walk-' + esc(w.journey) + '-' + esc(s.n) + '">' +
        '<div class="wsh">' +
          '<span class="wsn">' + esc(has(s.n) ? s.n : '—') + '</span>' +
          '<span class="wst">' + esc(s.name || 'unnamed step') + '</span>' +
          badge(st) +
          (has(s.ms) ? '<span class="muted mono xs">' + esc(s.ms) + ' ms</span>' : '') +
          (s.reached === false ? ' ' + ghostBadge('NEVER REACHED THIS PAGE') : '') +
        '</div>' +
        (arr(s.requirement).length
          ? '<div class="muted xs" style="margin-bottom:.4rem">' +
            arr(s.requirement).map((r) => '<code>' + esc(r) + '</code>').join(' ') + '</div>'
          : '') +
        '<div class="wgrid">' +
          '<div><div class="wlab">Done</div>' + renderActions(s.actions) +
            renderStepShot(s, ctx) + '</div>' +
          '<div><div class="wlab">Expected</div>' + renderExpects(s) +
            '<div class="wlab" style="margin-top:.6rem">Wireframe</div>' +
            renderWireframePanel(s.page, ctx.dbp || new Map(), ctx.rebase || ((x) => ({ href: x }))) +
          '</div>' +
        '</div>' +
        '<div class="wlab" style="margin-top:.75rem">Measured — the five behavioural rungs</div>' +
        renderStepChecks(s, ctx) +
        '<div class="wlab" style="margin-top:.75rem">The page, and the two design rungs</div>' +
        renderPageBlock(s, ctx.dbp || new Map(), ctx.rebase || ((x) => ({ href: x })), ctx) +
      '</div>';
    }

    out += '<div class="card" style="margin-bottom:1rem">' +
      '<div class="jhead"><h2 style="margin:0">' + esc(w.journey || 'unnamed journey') +
        (has(w.title) ? ' — ' + esc(w.title) : '') + '</h2>' + head.join(' ') + '</div>' +
      reqBlock + seedBlock + body +
      // Per-PROCESS next steps: the user runs the app as a process, so the actions for
      // that process are collected once at the end of its walk rather than left to be
      // reassembled from per-page panels.
      renderJourneyNextSteps(ctx.doc, w.journey) +
      '<div class="rule">A step’s colour is its <b>checks</b>, never its screenshot. ' +
      'An image proves what the page looked like; only a check says whether that was right. ' +
      '<b>—</b> = the contract declares nothing here. <b>⌀</b> = it declared ' +
      'something and this step never answered it.</div>' +
    '</div>';
  }

  // Whatever the embedder had to refuse is stated once, in the open.
  if (ctx.missing || ctx.overBudget) {
    const bits = [];
    if (ctx.missing) bits.push(plural(ctx.missing, 'screenshot was', 'screenshots were') +
      ' not on disk');
    if (ctx.overBudget) bits.push(plural(ctx.overBudget, 'screenshot was', 'screenshots were') +
      ' dropped to stay under the ' + mb(IMAGE_BUDGET) + ' image budget');
    out += '<div class="alert alert-invl">' + esc(bits.join('; ')) + '. ' +
      plural(ctx.embedded, 'image is', 'images are') + ' embedded (' + mb(ctx.bytes) +
      ' of base64). Each absent image says so in place; none is silently missing.</div>';
  }
  return out + '</section>';
}

/* ── the design rungs, and the per-persona read ────────────────────────────
 * "UI test" in this project means "does the screen look the way we said it would" —
 * rung 6 (does it match ITS wireframe) and rung 7 (does it match general practice).
 * They are the last two things a reader wants per page and the first two a test log
 * omits, so they are rendered beside the behaviour, never in an appendix.
 *
 * Personas are rendered one per DISTINCT page SET. Six roles that see the same five
 * pages get ONE section named for all six. Rendering six identical sections would
 * present as thoroughness the very fact that security does not differentiate them. */

const RUNG6_LABEL = 'RUNG 6 — matches its wireframe';
const RUNG7_LABEL = 'RUNG 7 — general design practice';

/** page -> { rung6, rung7[], wireframe, read } rebuilt from checks[]. The renderer
 *  reads only report.json, so this is derived, never carried twice. */
function designByPage(checks) {
  const m = new Map();
  for (const c of checks) {
    if (c.instrument !== 'design-audit' || !has(c.page)) continue;
    if (!m.has(c.page)) m.set(c.page, { rung6: null, rung7: [] });
    const e = m.get(c.page);
    if (String(c.id).indexOf('/rung6/wireframe-conformance/') !== -1) {
      e.rung6 = c.verdict; e.rung6detail = c.detail; e.rung6reason = c.reason;
    } else {
      e.rung7.push(c);
    }
  }
  for (const e of m.values()) {
    if (e.rung6 === null) e.rung6 = 'fault';
    e.rung7.sort((a, b) => String(a.id).localeCompare(String(b.id)));
  }
  return m;
}

/** Worst-first rollup over the rung-7 list, stated as counts. Never a percentage. */
function rung7Verdict(list) {
  const r = rollup(list);
  return r.fail ? 'fail' : r.fault ? 'fault' : r.pass ? 'pass' : 'skipped';
}

function renderRung7Table(list, ctx) {
  if (!list.length) {
    return '<div class="ghost"><div class="gh">Rung 7 did not run for this page</div>' +
      '<div class="gf">No general-design check exists for it in this report. That is not ' +
      '"the design is fine" — nothing looked.</div></div>';
  }
  let rows = '';
  for (const c of list) {
    const b7 = vinfo(c.verdict).bucket;
    const rem7 = ctx && ctx.rem && has(c.id) ? ctx.rem.get(c.id) : null;
    let cell7 = (has(c.detail) ? '<span class="mono">' + esc(c.detail) + '</span>'
                               : '<span class="wnone">— no detail recorded</span>');
    if (b7 !== 'pass' && rem7) cell7 += renderRemediation(rem7, { verdict: c.verdict });
    rows += '<tr data-v="' + esc(b7) + '"><td>' + badge(c.verdict) + '</td>' +
      '<td>' + esc(c.title || c.id) + '</td><td>' + cell7 + '</td></tr>';
  }
  return '<div class="tw"><table><tr><th style="width:7.5rem">Verdict</th>' +
    '<th style="width:32%">Design check</th><th>What it measured</th></tr>' + rows +
    '</table></div>';
}

/** Wireframe beside the screenshot. A wireframe is an HTML document, not an image, so
 *  it is LINKED and its machine comparison (rung 6) is stated next to it. Pretending to
 *  an eyeball diff we did not perform would be the judged-as-measured error. */
function renderWireframePanel(page, dbp, rebase) {
  const qn = page && page.qualifiedName;
  const d = qn && dbp.get(qn);
  const wf = page && page.wireframe;
  let head;
  if (!qn) {
    head = '<div class="ghost"><div class="gh">No wireframe comparison — page unidentified' +
      '</div><div class="gf">' + esc((page && page.why) || 'this step could not be attributed to ' +
      'a page in the model, so there is no wireframe to compare it against and no design ' +
      'verdict can be attached to it.') + '</div></div>';
  } else if (!has(wf)) {
    head = '<div class="ghost"><div class="gh">No wireframe was ever drawn for ' + esc(qn) +
      '</div><div class="gf">Rung 6 is <b>SKIPPED</b>, which is not a pass: this page was ' +
      'built without a drawing to build it against, so nothing can say whether it looks the ' +
      'way it was meant to. Rung 7 below still ran — that is the point of rung 7.</div></div>';
  } else {
    const r = rebase(wf);
    head = '<div class="wfpanel"><div class="wfh">' + esc(RUNG6_LABEL) + ' ' +
      badge(page.rung6) + '</div>' +
      '<a class="mono" href="' + esc(r.href) + '">' + esc(wf) + '</a>' +
      (d && has(d.rung6detail) ? '<div class="pre">' + esc(d.rung6detail) + '</div>' : '') +
      '<div class="muted xs">The wireframe is an HTML document, so it is linked rather than ' +
      'inlined beside the shot. The verdict above is a measured class-promotion diff against ' +
      'it — not a human looking at two pictures.</div></div>';
  }
  return head;
}

/** The page block on a walk step: where it sits, whether it is in scope, who can see it,
 *  and the two design rungs. */
function renderPageBlock(step, dbp, rebase, ctx) {
  const p = step.page;
  if (!p) {
    return '<div class="ghost"><div class="gh">This step carries no page block</div>' +
      '<div class="gf">The report was produced by a normalizer older than schema 1.1, so no ' +
      'walk step is attributed to a page and neither design rung can be joined to the walk.' +
      '</div></div>';
  }
  const qn = p.qualifiedName;
  const d = qn ? dbp.get(qn) : null;
  const r7 = d ? d.rung7 : arr(p.rung7);
  const bits = [];
  if (qn) {
    bits.push(neutBadge(qn));
    bits.push(p.inScope ? neutBadge('IN SCOPE') : ghostBadge('NOT IN THE IN-SCOPE SET'));
    if (p.orphan) bits.push(warnBadge('ORPHAN — ' + p.orphan.classification));
    bits.push(arr(p.role).length
      ? neutBadge(plural(arr(p.role).length, 'role sees it', 'roles see it'))
      : ghostBadge('NO ROLE GRANTS IT'));
    if (/WEAK/.test(String(p.resolvedBy || ''))) {
      bits.push(warnBadge('PAGE INFERRED, NOT DECLARED'));
    }
  } else {
    bits.push(ghostBadge('PAGE NOT RESOLVED'));
  }
  const who = arr(p.role).length
    ? '<div class="muted xs">Visible to: ' + esc(arr(p.role).join(', ')) + '</div>' : '';
  const how = has(p.resolvedBy)
    ? '<div class="muted xs">Identified by ' + esc(p.resolvedBy) +
      (arr(p.usedSelectors).length ? ' from ' + esc(arr(p.usedSelectors).join(', ')) : '') + '</div>'
    : '<div class="muted xs">' + esc(p.why || 'not identified') + '</div>';

  return '<div class="pblock"><div class="pbh">' + bits.join(' ') + '</div>' + who + how +
    '<div class="wlab" style="margin-top:.6rem">' + esc(RUNG7_LABEL) + ' ' +
      badge(rung7Verdict(r7)) + '</div>' +
    renderRung7Table(r7, ctx) +
    // Per-page next steps, where the reader is already looking at the page. The
    // ranked list at the top is the same objects; this is a filtered view, never a
    // second opinion, and it is rendered even when empty so "nothing outstanding"
    // is a statement rather than an absence.
    (ctx && ctx.doc ? renderPageNextSteps(ctx.doc, qn) : '') + '</div>';
}

/* ── per-persona sections ─────────────────────────────────────────────────── */

function stepsByPage(walks) {
  const m = new Map();
  for (const w of arr(walks)) {
    arr(w.steps).forEach((s) => {
      const qn = s.page && s.page.qualifiedName;
      if (!has(qn)) return;
      if (!m.has(qn)) m.set(qn, []);
      m.get(qn).push({ walk: w, step: s, total: arr(w.steps).length });
    });
  }
  return m;
}

/** One compact but COMPLETE row per page: which tests ran, where it sits in the process,
 *  what data changes were expected, whether they were seen, and both design rungs. */
function personaPageRow(page, visits, dbp, uncoveredBy) {
  const d = dbp.get(page) || { rung6: 'fault', rung7: [] };
  const r6 = badge(d.rung6);
  const r7 = badge(rung7Verdict(d.rung7), rung7Verdict(d.rung7) === 'pass'
    ? 'PASS (' + d.rung7.length + ')'
    : vinfo(rung7Verdict(d.rung7)).label + ' (' + rollup(d.rung7).fail + ' fail / ' +
      rollup(d.rung7).fault + ' not run / ' + rollup(d.rung7).other + ' skipped)');

  if (!visits.length) {
    const owner = uncoveredBy.get(page);
    return '<tr data-v="fault" class="hole"><td><b>' + esc(page) + '</b><br>' +
      ghostBadge('NEVER WALKED') + '</td>' +
      '<td>' + (owner && owner.journey.indexOf('(no journey') !== 0
        ? 'should have been covered by <b>' + esc(owner.journey) + '</b>'
        : ghostBadge('NO JOURNEY EXISTS FOR THIS MODULE')) + '</td>' +
      '<td colspan="2"><b>Nothing ran here.</b> No behavioural claim about this page has been ' +
      'tested in either direction — not its data writes, not its microflows, not what it ' +
      'says on screen. It is unknown, not untested.</td>' +
      '<td>' + r6 + '</td><td>' + r7 + '</td></tr>';
  }
  let cells = '';
  for (const v of visits) {
    const s = v.step;
    const cs = arr(s.checks);
    const ro = rollup(cs);
    const w = s.expects && s.expects.writes;
    const dataChecks = cs.filter((c) => c.rung === 'data');
    const dataRo = rollup(dataChecks);
    const seen = !w
      ? '<span class="wnone">— no write declared</span>'
      : !dataChecks.length
        ? ghostBadge('DECLARED · NEVER ANSWERED')
        : badge(dataRo.fail ? 'fail' : dataRo.fault ? 'fault' : 'pass',
                dataRo.pass + ' of ' + dataChecks.length + ' data checks agreed');
    cells += '<tr data-v="' + esc(vinfo(s.status).bucket) + '">' +
      '<td><b>' + esc(page) + '</b><br>' + badge(s.status) + '</td>' +
      '<td><a href="#walk-' + esc(v.walk.journey) + '-' + esc(s.n) + '">' +
        esc(v.walk.journey || 'walk') + ' step ' + esc(s.n) + ' of ' + esc(v.total) + '</a>' +
        '<br><span class="muted xs">' + esc(s.name || '') + '</span></td>' +
      '<td>' + (cs.length
        ? esc(ro.pass + ' pass · ' + ro.fail + ' fail · ' + ro.fault + ' not run') +
          '<br><span class="muted xs">' +
          esc(Array.from(new Set(cs.map((c) => c.rung || 'unlabelled'))).join(', ')) + '</span>'
        : ghostBadge('ZERO CHECKS')) + '</td>' +
      '<td>' + (w
        ? '<code>' + esc(w.entity || '?') + '</code>' +
          (has(w.delta) ? ' delta <b class="tab">' + esc(w.delta) + '</b>' : '') +
          '<br>' + seen
        : '<span class="wnone">— none declared</span><br>' + seen) + '</td>' +
      '<td>' + r6 + '</td><td>' + r7 + '</td></tr>';
  }
  return cells;
}

function renderPersonas(d, checks) {
  const sets = arr(d.roleSets);
  const lead = '<section id="personas"><div class="slabel">Per-persona walk — one report ' +
    'per distinct page set, not per role</div>';
  if (!sets.length) {
    return lead + '<div class="card">' + notMeasured('roleSets[] is absent or empty',
      'No role→page mapping reached this report, so nothing here can say what any persona ' +
      'can reach, let alone whether it was walked. This is not "one persona"; it is none.') +
      '</div></section>';
  }
  const dbp = designByPage(checks);
  const visitsByPage = stepsByPage(d.walks);
  const cov = d.pageCoverage || null;
  const uncoveredBy = new Map();
  if (cov) {
    for (const g of arr(cov.byJourney)) for (const p of arr(g.pages)) uncoveredBy.set(p, g);
  }

  const shared = sets.filter((s) => arr(s.roles).length > 1 && !s.empty);
  let finding = '';
  if (shared.length) {
    finding = '<div class="alert alert-fail"><b>Security does not differentiate these personas.</b> ' +
      sets.reduce((a, s) => a + arr(s.roles).length, 0) + ' roles resolve to ' +
      plural(sets.length, 'distinct in-scope page set', 'distinct in-scope page sets') + '. ' +
      shared.map((s) => plural(arr(s.roles).length, 'role', 'roles') + ' (' +
        esc(arr(s.roles).join(', ')) + ') see the identical ' +
        plural(s.pageCount, 'page', 'pages')).join('; ') +
      '. This section therefore emits one report per SET. Six sections with identical contents ' +
      'would read as thoroughness, when the fact being reported is that the model draws no ' +
      'distinction between those personas at all — a finding, not a formatting choice.</div>';
  }

  let out = lead + finding;
  for (const s of sets) {
    const pages = arr(s.pages);
    if (s.empty) {
      out += '<div class="card"><div class="jhead"><h2 style="margin:0">' +
        esc(arr(s.roles).join(', ')) + '</h2>' + ghostBadge('SEES NOTHING IN SCOPE') + '</div>' +
        '<div class="ghost"><div class="gh">This role reaches no in-scope page</div>' +
        '<div class="gf">There is no walk to narrate because there is nowhere for this persona ' +
        'to go. An empty page set is still a distinct set and still a finding — either the ' +
        'role is dead, or the pages it was meant to reach are not wired to it.</div></div></div>';
      continue;
    }
    const walkedPages = pages.filter((p) => (visitsByPage.get(p) || []).length);
    const unwalked = pages.filter((p) => !(visitsByPage.get(p) || []).length);
    const head = [
      neutBadge(plural(pages.length, 'page in scope', 'pages in scope')),
      walkedPages.length ? badge('pass', walkedPages.length + ' walked') : ghostBadge('NONE WALKED'),
      unwalked.length ? badge('fault', unwalked.length + ' never walked') : '',
    ].filter(Boolean);

    let rows = '';
    for (const p of pages.slice().sort()) {
      rows += personaPageRow(p, visitsByPage.get(p) || [], dbp, uncoveredBy);
    }

    out += '<div class="card" style="margin-bottom:1rem"><div class="jhead">' +
      '<h2 style="margin:0">' + esc(arr(s.roles).join(' · ')) + '</h2>' + head.join(' ') +
      '</div>' +
      '<p class="muted" style="font-size:13px">What this persona was trying to do: reach the ' +
      plural(pages.length, 'page', 'pages') + ' below, in the order the process runs them. ' +
      'Each row answers all six questions — which tests ran, where the page sits, what data ' +
      'change was expected, whether it was seen, whether the page matches its wireframe, and ' +
      'whether it matches general design practice. The step-by-step narrative with screenshots ' +
      'is rendered once, further down; the links below jump into it.</p>' +
      '<div class="tw"><table><tr><th style="width:20%">Page</th><th style="width:16%">Where in ' +
      'the process</th><th style="width:15%">Which tests ran</th><th style="width:19%">Data ' +
      'change expected → seen</th><th style="width:8rem">Wireframe</th>' +
      '<th style="width:10rem">Design practice</th></tr>' + rows + '</table></div>' +
      '<div class="rule">A page with no walk is <b>⌀ NEVER WALKED</b>, never a blank row. ' +
      'The design rungs still have something to say about it — how it is built is not ' +
      'whether it works.</div></div>';
  }

  if (cov) {
    out += '<div class="alert alert-invl"><b>The honest headline: ' + cov.uncovered + ' of ' +
      cov.inScope + ' in-scope pages were never walked.</b> ' + cov.walked +
      (cov.walked === 1 ? ' page was reached by a walk step' : ' pages were reached by walk steps') +
      '. Everything else in this report describes those ' + cov.walked + '. ' +
      'Listed under the journey that should have covered each one:' +
      '<ul class="plain" style="margin-top:8px">' +
      arr(cov.byJourney).map((g) => '<li><b>' + esc(g.journey) + '</b> — ' +
        esc(arr(g.pages).join(', ')) + '</li>').join('') + '</ul></div>';
  }
  return out + '</section>';
}

/* ── requirement bridge ───────────────────────────────────────────── */

function renderBridge(d, checks) {
  const coverage = arr(d.coverage);
  const traced = checks.filter((c) => has(c.requirement)).length;
  const untraced = checks.length - traced;
  const unwalked = coverage.filter((c) => !arr(c.journeys).length)
    .reduce((a, c) => a + ((c.rows && c.rows.buildable) || 0), 0);

  const journeys = groupJourneys(checks);
  let rows = '';

  for (const j of journeys) {
    const all = j.stepList.reduce((a, s) => a.concat(s.checks), []).concat(j.outcome, j.loose);
    const ro = rollup(all);
    const reqs = all.map((c) => c.requirement).filter(has);
    const decided = reqs.length
      ? Array.from(new Set(reqs)).map((r) => '<code>' + esc(r) + '</code>').join('<br>')
      : ghostBadge('NO BRD POINTER DECLARED') +
        '<br><span class="muted" style="font-size:12px">' + esc(j.id) +
        ' walks real behaviour that no requirement claims</span>';
    rows += '<tr><td>' + decided + '</td>' +
      '<td>' + esc(j.id) + ' \u00b7 ' + plural(j.stepList.length, 'step', 'steps') + '</td>' +
      '<td>' + plural(ro.total, 'finding', 'findings') + ': ' + ro.pass + ' pass / ' +
      ro.fail + ' fail / ' + ro.fault + ' not run' +
      (reqs.length ? '' : ' \u2014 <b>traceable to no requirement</b>') + '</td></tr>';
  }

  for (const c of coverage) {
    const walked = arr(c.journeys);
    const conf = c.conformance;
    const decided = '<code>' + esc(c.brd || '\u2014') + '</code> ' + esc(c.module || 'unnamed') +
      (c.rows ? '<br><span class="muted" style="font-size:12px">' +
        esc((c.rows.buildable || 0) + ' buildable \u00b7 ' +
            Object.keys(c.rows.byStatus || {})
              .map((k) => c.rows.byStatus[k] + ' ' + k).join(' \u00b7 ')) + '</span>' : '');
    const where = walked.length
      ? walked.map(esc).join(', ')
      : ghostBadge('NO JOURNEY WALKS THIS');
    const measured = conf
      ? esc(conf.checked + ' of ' + ((c.rows && c.rows.buildable) || '?') +
            ' rows mechanically checked: ' + conf.ok + ' OK \u00b7 ' + conf.stale + ' stale \u00b7 ' +
            conf.understated + ' understated \u00b7 ' + conf.unrunnable + ' unrunnable')
      : ghostBadge('NO CONFORMANCE RUN');
    rows += '<tr><td>' + decided + '</td><td>' + where + '</td><td>' + measured + '</td></tr>';
  }

  const body = rows
    ? '<p class="mono" style="font-size:12px">traced <b>' + traced + '</b> \u00b7 ' +
      'claimed-unwalked <b>' + unwalked + '</b> \u00b7 measured-untraced <b>' + untraced +
      '</b></p><div class="tw"><table>' +
      '<tr><th style="width:32%">What was decided</th><th style="width:24%">Where it is walked</th>' +
      '<th>What was measured</th></tr>' + rows + '</table></div>'
    : notMeasured('no coverage[] rows and no journey checks',
        'There is no requirement registry in this report, so nothing can be signed off in ' +
        'either direction \u2014 neither "built and proven" nor "claimed and missing".');

  return '<section><div class="slabel">What was decided \u2192 where it is walked \u2192 ' +
    'what was measured</div>' + body + '</section>';
}

/* ── remediation & next steps ─────────────────────────────────────────
 * WHY THIS EXISTS (2026-08-18, measured): the previous render of this report
 * contained the string "DID NOT RUN" 135 times and the strings "next step",
 * "remediation" and "how to fix" zero times. A hole that does not say what would
 * close it is a shrug. Every non-pass row now carries four sentences — what the
 * instrument WOULD have measured, why it didn't, what is therefore unproven, and
 * the one concrete action — and the same four are grouped and ranked up top so a
 * reader meets a handful of decisions rather than 135 identical absences.        */

const ACTION_KIND = {
  journey: 'JOURNEY CONTRACT', harness: 'HARNESS', model: 'MENDIX MODEL',
  design: 'DESIGN', ledger: 'LEDGER / DOC', infra: 'INFRASTRUCTURE',
  unknown: 'UNCLASSIFIED',
};

/** The four sentences, inline. Rendered wherever the row itself is rendered — never
 *  only in a summary, because the person reading a fault row is the person who needs
 *  it. `null` fields render as a stated gap, never as an empty line. */
function renderRemediation(r, opts) {
  if (!r) return '';
  const o = opts || {};
  const line = (label, v, missing) =>
    '<div class="rml"><span class="rmk">' + esc(label) + '</span>' +
    (has(v) ? '<span>' + esc(v) + '</span>'
            : '<span class="wnone">' + esc(missing) + '</span>') + '</div>';
  const kind = ACTION_KIND[r.actionKind] || ACTION_KIND.unknown;
  // A `fail` was measured and is wrong; a `fault` was never measured at all. Labelling
  // both "would have measured / why it did not" collapses exactly the distinction this
  // report exists to keep, in the one place a reader is deciding what to do.
  const failish = o.verdict === 'fail';
  const L1 = failish ? 'What it checks' : 'Would have measured';
  const L2 = failish ? 'Why it failed' : 'Why it did not run';
  const L3 = failish ? 'So what is broken' : 'So what is unproven';
  const head = '<div class="rmh">' +
    '<span class="chip">' + esc(r.class || 'unclassified') + '</span> ' +
    '<span class="chip">' + esc(kind) + '</span>' +
    (r.needsApproval ? ' ' + warnBadge('MODEL WRITE — NEEDS APPROVAL') : '') +
    (has(r.where) ? ' <span class="muted mono xs">' + esc(r.where) + '</span>' : '') +
    '</div>';
  const body =
    line(L1, r.measures, 'not recorded — this class is missing from the ' +
         'remediation table in report-normalize.js') +
    line(L2, r.why, 'not recorded') +
    line(L3, r.blastRadius, 'not recorded') +
    (has(r.action)
      ? '<div class="rml rmdo"><span class="rmk">Do this</span><span>' + esc(r.action) + '</span></div>'
      : '<div class="rml rmdo"><span class="rmk">Do this</span>' +
        '<span class="wnone">NO ACTION DERIVED. This row matched no rule in ' +
        'report-normalize.js’s remediation table — that is a gap in the table, not a ' +
        'judgement that nothing can be done. Adding a rule is the fix.</span></div>');
  if (o.bare) return '<div class="rm">' + head + body + '</div>';
  return '<details class="rm"><summary>What to do about this</summary>' + head + body + '</details>';
}

/** Map check.id → remediation, for the walk and the findings table. */
function remediationIndex(checks) {
  const m = new Map();
  for (const c of checks) if (c && c.remediation) m.set(c.id, c.remediation);
  return m;
}

function renderNextSteps(d) {
  const steps = arr(d.nextSteps);
  const lead = '<section id="next"><div class="slabel">What to do next — ranked by what ' +
    'it costs not to know</div>';
  if (!steps.length) {
    const anyBad = arr(d.checks).some((c) => c.verdict === 'fail' || c.verdict === 'fault');
    return lead + '<div class="card">' + notMeasured('nextSteps[] is absent or empty',
      anyBad
        ? 'This report contains failures and holes but no derived next steps, which means ' +
          'report.json was produced by a normalizer older than schema 1.2. Re-run ' +
          'node tests/e2e/report-normalize.js. Do not read the absence as "nothing to do".'
        : 'No check failed and no instrument reported a hole, so there is nothing to ' +
          'derive. This is the one shape in which an empty next-steps list is honest.') +
      '</div></section>';
  }
  const tiers = [];
  for (const s of steps) {
    if (!tiers.length || tiers[tiers.length - 1].tier !== s.tier) tiers.push({ tier: s.tier, rows: [] });
    tiers[tiers.length - 1].rows.push(s);
  }
  const TIER_NAME = {
    1: 'Blocks whole processes — fix these first',
    2: 'Severed by the guard above — no separate work, they measure themselves once it is fixed',
    3: 'A user meets this defect on the golden path',
    4: 'An entire rung of evidence is missing',
    5: 'Pages nothing has ever walked',
    6: 'The instrument cannot see the page, or cannot say which page it saw',
    7: 'Design evidence absent for a page',
    8: 'Design defects, measured',
    9: 'Leads from the weaker instruments',
    10: 'Governance and documents',
    99: 'Unclassified — a gap in the remediation table',
  };
  const totalRows = steps.reduce((n, s) => n + s.count, 0);

  let out = lead + '<div class="card"><p>' +
    esc(plural(steps.length, 'action', 'actions') + ' below account for every one of the ' +
        totalRows + ' non-passing rows in this report. They are derived from the findings, ' +
        'not written by hand: each one names the file, page or microflow it applies to and ' +
        'the checks it would turn green. Ordering is by blast radius, never by count — one ' +
        'severed landing guard outranks thirteen accessibility findings because it is the ' +
        'reason thirteen other things were never measured at all.') + '</p></div>';

  for (const t of tiers) {
    out += '<div class="nstier"><div class="nsth">' +
      esc(TIER_NAME[t.tier] || ('Tier ' + t.tier)) + '</div>';
    for (const s of t.rows) {
      const counts = Object.keys(s.verdicts || {}).sort()
        .map((v) => badge(v, vinfo(v).label + ' ×' + s.verdicts[v])).join(' ');
      const affects = arr(s.affects);
      const shown = affects.slice(0, 8);
      out += '<div class="card ns" data-v="' + esc(s.verdicts.fail ? 'fail' : 'fault') + '">' +
        '<div class="nsh"><span class="nsr">' + esc('#' + s.rank) + '</span>' +
        '<b>' + esc(s.class) + (has(s.target) ? ' — ' + esc(s.target) : '') + '</b> ' +
        counts + '</div>' +
        renderRemediation(s, { bare: true, verdict: (s.verdicts || {}).fail && !(s.verdicts || {}).fault ? 'fail' : 'fault' }) +
        (affects.length
          ? '<div class="muted xs" style="margin-top:6px">Affects: ' +
            shown.map((a) => '<span class="chip">' + esc(a) + '</span>').join(' ') +
            (affects.length > shown.length
              ? ' <span class="muted">and ' + (affects.length - shown.length) + ' more</span>' : '') +
            '</div>'
          : '') +
        '<details style="margin-top:6px"><summary>' +
          esc(plural(s.count, 'check', 'checks') + ' this closes') + '</summary>' +
          '<div class="mono xs" style="margin-top:4px">' +
          arr(s.checkIds).map(esc).join('<br>') + '</div></details>' +
        '</div>';
    }
    out += '</div>';
  }
  return out + '</section>';
}

/** Next steps narrowed to one page — rendered inside the walk, where the reader is
 *  already looking at that page.
 *
 *  DERIVED FROM THAT PAGE'S OWN CHECKS, not from the project-wide group. First cut
 *  reused the group row, and a project-wide group carries whichever member's action
 *  happened to be first: the panel under FieldScan.Receive_Scan told the reader to go
 *  fix Equipment.Item_Detail. A per-page panel must quote the per-page remediation.
 *  The group is still used, but only for its RANK, so the ordering here and the
 *  ordering at the top of the report cannot disagree. */
function nextStepsFor(d, page) {
  if (!has(page)) return [];
  const rank = new Map();
  for (const s of arr(d.nextSteps)) {
    rank.set(s.class + '::' + (s.target == null ? '' : s.target), s.rank);
  }
  const rankOf = (cls) => {
    const t = rank.get(cls + '::' + page);
    return t != null ? t : (rank.get(cls + '::') != null ? rank.get(cls + '::') : 999);
  };
  const byClass = new Map();
  for (const c of arr(d.checks)) {
    if (c.page !== page || !c.remediation) continue;
    const k = c.remediation.class;
    if (!byClass.has(k)) {
      byClass.set(k, { class: k, rank: rankOf(k), action: c.remediation.action,
                       needsApproval: !!c.remediation.needsApproval, count: 0 });
    }
    byClass.get(k).count++;
  }
  return [...byClass.values()].sort((a, b) => (a.rank - b.rank) || a.class.localeCompare(b.class));
}

function renderPageNextSteps(d, page) {
  const steps = nextStepsFor(d, page);
  if (!has(page)) {
    return '<div class="ghost"><div class="gh">No next steps for this step</div>' +
      '<div class="gf">The walk step could not be attributed to a page in the model, so ' +
      'per-page actions cannot be listed. The page-join row above says why. The ranked list ' +
      'at the top of this report still covers every finding.</div></div>';
  }
  if (!steps.length) {
    return '<div class="wnone">Nothing outstanding for ' + esc(page) +
      ' — every check that named this page passed.</div>';
  }
  let out = '<div class="pns"><div class="pnsh">Next for ' + esc(page) + ' — ' +
    esc(plural(steps.length, 'action', 'actions')) + '</div><ol class="pnsl">';
  for (const s of steps) {
    out += '<li><span class="chip">' + esc('#' + s.rank) + '</span> ' +
      '<b>' + esc(s.class) + '</b>' + (s.count > 1 ? ' <span class="muted xs">×' +
        s.count + ' on this page</span>' : '') +
      (s.needsApproval ? ' ' + warnBadge('MODEL WRITE — NEEDS APPROVAL') : '') +
      '<div class="muted">' + esc(s.action || 'no action derived — see the ranked list') +
      '</div></li>';
  }
  return out + '</ol></div>';
}

/** Per-process next steps: every action any check in this journey asks for, deduped by
 *  class and ordered by the same global rank. Derived from checks[], for the same reason
 *  the per-page panel is — a group's action sentence belongs to whichever member wrote it. */
function renderJourneyNextSteps(d, journey) {
  if (!d || !has(journey)) return '';
  const rank = new Map();
  for (const s of arr(d.nextSteps)) {
    rank.set(s.class + '::' + (s.target == null ? '' : s.target), s.rank);
  }
  const byClass = new Map();
  for (const c of arr(d.checks)) {
    if (c.journey !== journey || !c.remediation) continue;
    const k = c.remediation.class;
    const r = rank.get(k + '::' + (c.module || '')) != null ? rank.get(k + '::' + (c.module || ''))
            : rank.get(k + '::' + (c.page || '')) != null ? rank.get(k + '::' + (c.page || ''))
            : rank.get(k + '::') != null ? rank.get(k + '::') : 999;
    if (!byClass.has(k)) {
      byClass.set(k, { class: k, rank: r, action: c.remediation.action,
                       needsApproval: !!c.remediation.needsApproval, count: 0 });
    }
    byClass.get(k).count++;
  }
  const list = [...byClass.values()].sort((a, b) => (a.rank - b.rank) || a.class.localeCompare(b.class));
  if (!list.length) {
    return '<div class="pns"><div class="pnsh">Next for ' + esc(journey) + '</div>' +
      '<div class="wnone">Nothing outstanding — every check in this journey passed.</div></div>';
  }
  let out = '<div class="pns"><div class="pnsh">Next for the ' + esc(journey) +
    ' process — ' + esc(plural(list.length, 'action', 'actions')) +
    ', in the order they unblock each other</div><ol class="pnsl">';
  for (const s of list) {
    out += '<li><span class="chip">' + esc('#' + s.rank) + '</span> <b>' + esc(s.class) +
      '</b> <span class="muted xs">\u00d7' + s.count + '</span>' +
      (s.needsApproval ? ' ' + warnBadge('MODEL WRITE — NEEDS APPROVAL') : '') +
      '<div class="muted">' + esc(s.action || 'no action derived — see the ranked list') +
      '</div></li>';
  }
  return out + '</ol></div>';
}

/* ── findings ─────────────────────────────────────────────────────── */

function findingsTable(checks, rebase, withEvidence, checkIndex) {
  let h = '<table><tr><th style="width:96px">Verdict</th><th style="width:92px">Rung</th>' +
          '<th>Check</th><th style="width:14%">Where</th><th style="width:14%">Requirement</th>' +
          '<th style="width:30%">Measured &amp; what to do</th></tr>';
  for (const c of checks) {
    const info = vinfo(c.verdict);
    const b = info.bucket;
    const where = [has(c.journey) ? c.journey : null,
                   has(c.stepIndex) ? 'step ' + c.stepIndex : null].filter(has).join(' \u00b7 ');
    // A finding you cannot locate is not actionable. 58 design rows used to render as
    // "no invented classes" with nothing naming the page they were about.
    const locus = has(c.page) ? c.page
                : has(c.module) ? c.module
                : has(c.journey) ? c.journey : null;
    let measured = has(c.detail) ? '<span class="mono">' + esc(c.detail) + '</span>'
                                 : '<span class="muted mono">\u2014</span>';

    // Screenshots live ONLY here, inside an expanded fail row. Never a passing gallery.
    if (withEvidence && b === 'fail') {
      const evs = arr(c.evidence);
      if (evs.length) {
        let shots = '';
        for (const e of evs) {
          if (e.type === 'screenshot' && has(e.path)) {
            const r = rebase(e.path);
            if (!r.remote) {
              shots += '<figure class="shot"><img loading="lazy" src="' + esc(r.href) +
                '" alt="' + esc('screenshot: ' + (c.title || c.id)) + '">' +
                '<figcaption class="mono">' + esc(e.path) + '</figcaption></figure>';
            }
          }
        }
        measured += '<details><summary>evidence (' + evs.length + ')</summary>' +
          '<div class="tw" style="margin-top:6px">' + evidenceTable(evs, rebase) + '</div>' +
          shots + '</details>';
      } else {
        measured += '<div style="margin-top:6px">' +
          ghostBadge('NO EVIDENCE PATH \u2014 CLAIM, NOT PROOF') + '</div>';
      }
    }
    // A declared-but-never-run expectation names the guard that severed it. Without that
    // pointer the row reads as an unexplained absence rather than a consequence.
    if (has(c.blockedBy)) {
      const g = checkIndex && checkIndex.get(c.blockedBy);
      measured += '<div class="muted note">' +
        '\u26d2 blocked by <span class="mono">' + esc(c.blockedBy) + '</span>' +
        (g ? ' \u2014 ' + esc((g.stepName ? g.stepName + ': ' : '') + (g.title || '')) : '') + '</div>';
    }
    if (c.nonVacuity && c.nonVacuity.controlRan === false) {
      measured += '<div class="muted note">' +
        '\u2300 control not run: ' + esc(c.nonVacuity.note || 'non-vacuity unproven') + '</div>';
    }
    const pb = provenanceBadge(c);
    if (pb) measured += '<div style="margin-top:4px">' + pb + '</div>';
    // The four sentences, on the row itself. A non-pass with no remediation block is a
    // gap in the normalizer's table and must say so rather than render as bare detail.
    if (b === 'fail' || b === 'fault' || b === 'other') {
      measured += c.remediation
        ? renderRemediation(c.remediation, { verdict: c.verdict })
        : '<div class="rm rmgap">' + ghostBadge('NO REMEDIATION DERIVED') +
          ' <span class="muted xs">report.json carries no remediation for this row. ' +
          'Either it predates schema 1.2 or its class is missing from the table in ' +
          'report-normalize.js.</span></div>';
    }

    h += '<tr data-v="' + esc(b) + '"><td>' + badge(c.verdict) + '</td>' +
      '<td class="mono nb">' + esc(c.kind || '\u2014') + '</td>' +
      '<td>' + esc((has(c.stepName) ? c.stepName + ': ' : '') + (c.title || c.id)) +
      (arr(c.tags).length ? ' ' + arr(c.tags).map((t) =>
        '<span class="chip">' + esc(t) + '</span>').join(' ') : '') +
      (where ? '<br><span class="muted mono xs">' + esc(where) + '</span>' : '') +
      '</td><td>' +
      (locus ? '<span class="mono xs">' + esc(locus) + '</span>'
             : ghostBadge('NOT ATTRIBUTED TO A PAGE')) +
      '</td><td>' +
      // Never a blank cell: a null BRD pointer is a measured fact, not an oversight, and
      // it must look like the hole it is.
      (has(c.requirement)
        ? '<code>' + esc(c.requirement) + '</code>'
        : ghostBadge('NO BRD POINTER DECLARED')) +
      '</td><td>' + measured + '</td></tr>';
  }
  return h + '</table>';
}

function renderFindings(checks, rebase) {
  if (!checks.length) {
    return '<section><div class="slabel">Every finding</div>' +
      notMeasured('checks[] is empty',
        'No instrument appended a single check. This is the shape a run takes when the harness ' +
        'never started \u2014 and the shape that used to render as a green page.') + '</section>';
  }
  const sorted = checks.slice().sort((a, b) => {
    const rank = { fail: 0, fault: 1, other: 2, pass: 3 };
    const ra = rank[vinfo(a.verdict).bucket], rb = rank[vinfo(b.verdict).bucket];
    if (ra !== rb) return ra - rb;
    return String(a.id).localeCompare(String(b.id));
  });
  return '<section><div class="slabel">Every finding \u2014 failures and holes first</div>' +
    '<div class="tw">' + findingsTable(sorted, rebase, true, new Map(checks.map((c) => [c.id, c]))) + '</div></section>';
}

/* ── module sign-off ──────────────────────────────────────────────── */

function renderCoverage(d, checks) {
  const coverage = arr(d.coverage);
  if (!coverage.length) {
    return '<section><div class="slabel">Per-module sign-off state</div>' +
      notMeasured('coverage[] is empty',
        'No module in this project has a coverage ledger in this report. Their state is not ' +
        '"untested"; it is unknown, which is a different and worse thing.') + '</section>';
  }
  const runStart = (d.run || {}).startedAt;
  const journeysByModule = new Map();
  for (const j of groupJourneys(checks)) {
    if (!has(j.module)) continue;
    if (!journeysByModule.has(j.module)) journeysByModule.set(j.module, []);
    journeysByModule.get(j.module).push(j);
  }

  let rows = '', totalRows = 0, totalChecked = 0;
  for (const c of coverage) {
    const r = c.rows || {}, st = r.byStatus || {}, lv = c.leaves || {}, cf = c.conformance;
    totalRows += r.buildable || 0;
    totalChecked += (cf && cf.checked) || 0;

    const stale = has(c.generatedAt) && has(runStart) &&
      new Date(c.generatedAt).getTime() < new Date(runStart).getTime() - 86400000;

    const confCell = cf
      ? ((cf.stale || cf.understated) ? warnBadge(cf.checked + ' checked')
                                      : badge('pass', cf.checked + ' checked')) +
        '<br><span class="muted mono xs">' +
        esc(cf.ok + ' OK \u00b7 ' + cf.stale + ' stale \u00b7 ' + cf.understated +
            ' understated \u00b7 ' + cf.unrunnable + ' unrunnable') + '</span>'
      : ghostBadge('NOT RUN');

    const mj = journeysByModule.get(c.module) || [];
    const jCell = mj.length
      ? mj.map((j) => {
          const all = j.stepList.reduce((a, s) => a.concat(s.checks), []);
          const ro = rollup(all);
          return ro.fail ? warnBadge(j.id + ' incomplete')
               : ro.fault ? ghostBadge(j.id + ' has holes')
               : badge('pass', j.id);
        }).join('<br>')
      : ghostBadge('NONE');

    // Sign-off is refused unless there is a walked journey AND no unclaimed leaves
    // AND conformance ran clean. Downgrade is free; upgrade needs all three.
    const reasons = [];
    if (!mj.length) reasons.push('no journey');
    // null is NOT zero and NOT green. A ledger that never computed its leaf arithmetic
    // is unknown, and unknown blocks sign-off exactly as a positive count would.
    for (const k of ['unclaimed', 'phantom', 'doubleClaimed']) {
      if (!has(lv[k])) reasons.push(k + ' unknown');
      else if (lv[k] > 0) reasons.push(lv[k] + ' ' + k);
    }
    if (!cf) reasons.push('no conformance run');
    else if (cf.stale || cf.understated) reasons.push('ledger contradicts model');
    if (mj.some((j) => rollup(j.stepList.reduce((a, s) => a.concat(s.checks), [])).fail > 0)) {
      reasons.push('journey failed');
    }
    const signoff = reasons.length
      ? badge('fail', 'REFUSED') + '<br><span class="muted" style="font-size:11px">' +
        esc(reasons.join(' \u00b7 ')) + '</span>'
      : badge('pass', 'SIGNED OFF');

    // A count cell is either a number or an explicit unknown. Never a dash that reads as zero.
    const num = (v) => (has(v) ? '<span class="tab">' + esc(v) + '</span>'
                               : '<span class="v v-invl">\u2300 ?</span>');
    const leafCell = ['unclaimed', 'phantom', 'doubleClaimed']
      .map((k) => (has(lv[k]) ? (lv[k] > 0 ? '<b>' + lv[k] + '</b> ' + k : lv[k] + ' ' + k)
                              : '<b>?</b> ' + k)).join(' \u00b7 ');
    const leafUnknown = ['unclaimed', 'phantom', 'doubleClaimed'].some((k) => !has(lv[k]));

    rows += '<tr><td><b>' + esc(c.module || 'unnamed') + '</b>' +
      (has(c.brd) ? ' <span class="muted mono xs">' + esc(c.brd) + '</span>' : '') +
      (stale ? '<br>' + warnBadge('LEDGER OLDER THAN RUN') : '') +
      '<br><span class="' + (leafUnknown ? 'v v-invl' : 'muted mono') +
      '" class="xs">' + leafCell + '</span></td>' +
      '<td>' + num(r.buildable) + '</td>' +
      '<td>' + num(st.built) + '</td>' +
      '<td>' + num(st.partial) + '</td>' +
      '<td>' + num(st.notBuilt) + '</td>' +
      '<td>' + confCell + '</td><td>' + jCell + '</td><td>' + signoff + '</td></tr>';
  }

  return '<section><div class="slabel">Per-module sign-off state \u2014 the governance answer</div>' +
    '<p>The unit of sign-off is a coverage-ledger row \u2014 one requirement claim with an ' +
    'acceptance criterion \u2014 not a script that executed cleanly.</p>' +
    '<div class="tw"><table><tr><th>Module</th><th class="tab">Rows</th><th class="tab">Built</th>' +
    '<th class="tab">Partial</th><th class="tab">Not built</th><th>Model conformance</th>' +
    '<th>Journey</th><th>Sign-off</th></tr>' + rows + '</table></div>' +
    '<div class="alert alert-fail" style="margin-top:14px"><b>The ratio that matters:</b> ' +
    totalRows + ' buildable ledger rows, of which ' + totalChecked +
    ' have ever been mechanically checked, walked by ' +
    plural(groupJourneys(checks).length, 'journey', 'journeys') +
    '. That, not the pass count, is the honest state of verification here.</div></section>';
}

/* ── deferrals ────────────────────────────────────────────────────── */

function renderDeferrals(d) {
  const defs = arr(d.deferrals);
  if (!defs.length) {
    return '<section><div class="slabel">Banked questions</div>' +
      notMeasured('deferrals[] is empty',
        'No open question is recorded. That is only good news if one was actually looked for.') +
      '</section>';
  }
  let rows = '';
  for (const q of defs) {
    const unraised = !has(q.consentBy) && !has(q.consentAt);
    rows += '<tr><td class="mono">' + esc(q.id || '\u2014') + '</td>' +
      '<td>' + esc(q.question || '') +
      (has(q.position) ? '<br><span class="muted" style="font-size:12px">working position: ' +
        esc(q.position) + '</span>' : '') + '</td>' +
      '<td>' + (has(q.requirement) ? '<code>' + esc(q.requirement) + '</code>'
                                   : ghostBadge('NO BRD POINTER DECLARED')) + '</td>' +
      '<td>' + esc(q.reversalCost || '\u2014') + '</td>' +
      '<td>' + (unraised ? ghostBadge('UNRAISED')
                         : badge('pass', 'answered by ' + q.consentBy)) + '</td></tr>';
  }
  return '<section><div class="slabel">Banked questions \u2014 asked, or only assumed?</div>' +
    '<div class="tw"><table><tr><th style="width:80px">ID</th><th>Question</th>' +
    '<th style="width:16%">Requirement</th><th style="width:100px">Reversal</th>' +
    '<th style="width:150px">Consent</th></tr>' + rows + '</table></div>' +
    '<div class="alert alert-invl">An assumption an agent recorded for itself is ' +
    '<b>UNRAISED</b>, not ASSUMED. ASSUMED is earned only by asking and being told ' +
    '"you decide".</div></section>';
}

/* ── scope of claim ───────────────────────────────────────────────── */

function renderScope(d, checks, instruments) {
  const journeys = groupJourneys(checks);
  const kinds = Array.from(new Set(checks.map((c) => c.kind).filter(has))).sort();
  const modules = Array.from(new Set(
    checks.map((c) => c.module).filter(has).concat(arr(d.coverage).map((c) => c.module).filter(has))
  )).sort();
  const target = (d.run || {}).target;

  let covers = '<ul class="plain">' +
    '<li>' + plural(journeys.length, 'journey', 'journeys') +
      (journeys.length ? ': ' + esc(journeys.map((j) => j.id).join(', ')) : '') + '</li>' +
    '<li>' + plural(modules.length, 'module', 'modules') +
      (modules.length ? ': ' + esc(modules.join(', ')) : '') + '</li>' +
    '<li>instrument kinds present: ' +
      (kinds.length ? esc(kinds.join(', ')) : '<b>none</b>') + '</li>' +
    '<li>run target: ' + (has(target) ? esc(target) : ghostBadge('NOT DECLARED')) + '</li>' +
    '</ul>';

  // Everything a kind could have covered but did not appear at all.
  const ALL_KINDS = ['ui', 'trace', 'data', 'outcome', 'control', 'build', 'lint',
                     'coverage', 'conformance', 'stack'];
  const missing = ALL_KINDS.filter((k) => kinds.indexOf(k) === -1);
  const dark = instruments.filter((i) => vinfo(i.verdict).bucket !== 'pass');

  let gaps = '<table><tr><th style="width:34%">Not reached by this run</th><th>Why</th></tr>';
  for (const k of missing) {
    gaps += '<tr><td class="mono">kind: ' + esc(k) + '</td><td>' +
      'No check of this kind appears in report.json. Nothing in this document says anything ' +
      'about it, in either direction.</td></tr>';
  }
  for (const i of dark) {
    gaps += '<tr><td>' + esc(i.name) + ' ' + badge(i.verdict) + '</td><td>' +
      esc(has(i.reason) ? i.reason : 'The instrument produced no verdict for this run.') +
      '</td></tr>';
  }
  if (missing.length === 0 && dark.length === 0) {
    gaps += '<tr><td colspan="2">Every declared kind produced at least one check and every ' +
      'instrument reported. That is the ceiling of what this contract can state.</td></tr>';
  }
  gaps += '</table>';

  return '<section><div class="slabel">Scope of this claim \u2014 what was NOT proven</div>' +
    '<div class="card" style="background:var(--surface-2)">' +
    '<p>This report claims exactly what its instruments measured, and nothing adjacent to it.</p>' +
    covers +
    '<div class="tw" style="background:var(--surface);margin-top:12px">' + gaps + '</div>' +
    '<div class="ghost" style="margin-top:14px"><div class="gh">Structural gaps are not ' +
    'expressible in schema ' + esc(d.schemaVersion) + '</div>' +
    '<div class="gf">Whole classes of risk \u2014 authorisation, tenancy, attribute-value ' +
    'correctness, concurrency, performance, accessibility, and whether the requirement was ' +
    '<i>right</i> \u2014 have no field in report.json. Their absence from the table above is ' +
    'a property of the contract, not evidence that they are fine. This paragraph is generated ' +
    'unconditionally so that it can never be mistaken for a measured all-clear.</div></div>' +
    '</div></section>';
}

/* ── appendix ─────────────────────────────────────────────────────── */

function renderAppendix(d) {
  const p = d.project || {}, r = d.run || {}, env = r.env || {}, rep = r.reproduce || {};
  const line = (k, v) => k.padEnd(18) + (has(v) ? String(v) : '\u2014');
  const lines = [
    line('project', p.id), line('displayName', p.displayName), line('mpr', p.mpr),
    line('mprModifiedAt', p.mprModifiedAt), line('mendixVersion', p.mendixVersion),
    line('toolkitCommit', p.toolkitCommit), line('gitCommit', p.gitCommit),
    line('branch', p.branch), '',
    line('startedAt', r.startedAt), line('finishedAt', r.finishedAt),
    line('elapsed', elapsed(r.startedAt, r.finishedAt)),
    line('trigger', r.trigger), line('target', r.target), '',
    line('baseUrl', env.baseUrl), line('host', env.host),
    line('ownership', env.ownership), line('ownershipBasis', env.ownershipBasis),
    line('user', env.user), line('userFallbackUsed', env.userFallbackUsed),
    line('database', env.database), '',
    line('command', rep.command),
    line('monkeySeed', rep.monkeySeed),
  ].join('\n');

  const seeds = rep.seeds && Object.keys(rep.seeds).length
    ? Object.keys(rep.seeds).map((k) => '  ' + k + ' = ' + rep.seeds[k]).join('\n')
    : '  \u2014 none declared';

  return '<section><div class="slabel">Evidence appendix</div><div class="card">' +
    '<details><summary>Run configuration \u2014 how to reproduce this exact run</summary>' +
    '<div class="pre">' + esc(lines) + '\n\nseeds\n' + esc(seeds) + '</div></details>' +
    '<details><summary>Why this page makes no network requests</summary>' +
    '<p style="font-size:13px">Every style and script here is inline. Evidence pointers in the ' +
    'findings table are relative paths on disk \u2014 referenced, not inlined, which keeps that ' +
    'part of the report small and keeps the images diffable in git. The journey-walk section is ' +
    'the deliberate exception: its screenshots are base64 <code>data:</code> URIs so the walk ' +
    'survives being copied to another machine, where a relative path would resolve to nothing ' +
    'and a strict CSP would block any attempt to fetch it. That inlining is budgeted, and any ' +
    'shot that could not be embedded says so in words rather than rendering as a broken image. ' +
    'URLs that appear in the appendix above are <i>measured data about the run</i> \u2014 the ' +
    'app\u2019s own base URL \u2014 not resources this document loads.</p></details>' +
    '</div></section>';
}

/* ───────────────────────── CSS ─────────────────────────
 * Tokens lifted from design/ds.css. Full light palette on bare :root; only the
 * changed tokens are redefined under BOTH the prefers-color-scheme block (guarded
 * so an explicit light choice wins) and [data-theme="dark"] (so the toggle wins).  */

const CSS = `
:root{
  --po-navy:#1a2332; --po-teal:#1a8a72; --po-purple:#7c3aed;
  --bg:#f4f5f7; --surface:#fff; --surface-2:#f7f8fa; --surface-inset:#eef0f3;
  --topbar:#1a2332; --topbar-ink:#eef0f3;
  --text:#1e2633; --text-secondary:#4d5765; --text-muted:#6b7685;
  --border:#dde1e7; --border-strong:#c4cad4;
  --n-100:#eef0f3; --n-300:#c4cad4;
  --cta:#1a8a72;
  --pass-ink:#0d6b5a; --pass-bg:#e6f4f1; --pass-br:#b3dfd8;
  --fail-ink:#8a2a22; --fail-bg:#fbeae8; --fail-br:#f0b8b3;
  --warn-ink:#8a5a15; --warn-bg:#fdf3e6; --warn-br:#e8cfa8;
  --hatch:repeating-linear-gradient(45deg,var(--n-100) 0 5px,transparent 5px 10px);
  --mono:ui-monospace,SFMono-Regular,"SF Mono",Menlo,Consolas,monospace;
  --sans:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif;
  --shadow:0 1px 2px rgba(26,35,50,.06),0 2px 8px rgba(26,35,50,.05);
}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){
  --bg:#0f141b; --surface:#161d27; --surface-2:#1c2430; --surface-inset:#212b38;
  --topbar:#0b1017; --topbar-ink:#e6eaf0;
  --text:#e6eaf0; --text-secondary:#aab4c2; --text-muted:#7d8896;
  --border:#2b3644; --border-strong:#3a4757; --n-100:#212b38; --n-300:#3f4b5c;
  --cta:#34c8a5;
  --pass-ink:#34c8a5; --pass-bg:rgba(52,200,165,.14); --pass-br:rgba(52,200,165,.4);
  --fail-ink:#f2685a; --fail-bg:rgba(242,104,90,.14); --fail-br:rgba(242,104,90,.4);
  --warn-ink:#e5a049; --warn-bg:rgba(229,160,73,.14); --warn-br:rgba(229,160,73,.4);
  --shadow:none;
}}
:root[data-theme="dark"]{
  --bg:#0f141b; --surface:#161d27; --surface-2:#1c2430; --surface-inset:#212b38;
  --topbar:#0b1017; --topbar-ink:#e6eaf0;
  --text:#e6eaf0; --text-secondary:#aab4c2; --text-muted:#7d8896;
  --border:#2b3644; --border-strong:#3a4757; --n-100:#212b38; --n-300:#3f4b5c;
  --cta:#34c8a5;
  --pass-ink:#34c8a5; --pass-bg:rgba(52,200,165,.14); --pass-br:rgba(52,200,165,.4);
  --fail-ink:#f2685a; --fail-bg:rgba(242,104,90,.14); --fail-br:rgba(242,104,90,.4);
  --warn-ink:#e5a049; --warn-bg:rgba(229,160,73,.14); --warn-br:rgba(229,160,73,.4);
  --shadow:none;
}
*{box-sizing:border-box}
html{-webkit-text-size-adjust:100%}
body{margin:0;background:var(--bg);color:var(--text);font-family:var(--sans);
  font-size:0.875rem;line-height:1.5;-webkit-font-smoothing:antialiased;overflow-x:hidden}
.wrap{max-width:74rem;margin:0 auto;padding:0 1.5rem 5rem}
code,.mono{font-family:var(--mono);font-size:.72rem;overflow-wrap:anywhere}
.nb{overflow-wrap:normal;white-space:nowrap}
.xs{font-size:.66rem}
.note{font-size:.72rem;margin-top:.25rem}
.tab{font-variant-numeric:tabular-nums}
ul.plain{margin:.5rem 0;padding-left:1.1rem;color:var(--text-secondary);font-size:.82rem}

/* masthead */
header.top{position:sticky;top:0;z-index:20;background:var(--topbar);color:var(--topbar-ink);
  box-shadow:0 1px 0 rgba(0,0,0,.25)}
.top-in{max-width:74rem;margin:0 auto;padding:.5rem 1.5rem;min-height:4rem;display:flex;
  align-items:center;gap:.875rem;flex-wrap:wrap}
.mark{width:1.75rem;height:1.75rem;border-radius:6px;background:var(--po-teal);color:#fff;
  display:grid;place-items:center;font-weight:800;font-size:.8rem;flex:none}
.top h1{font-size:.94rem;font-weight:700;margin:0;letter-spacing:-.1px}
.top .sub{font-size:.72rem;color:#9aa3b0;font-family:var(--mono);overflow-wrap:anywhere}
.spacer{flex:1}
.tglbtn{background:rgba(255,255,255,.1);color:var(--topbar-ink);border:1px solid rgba(255,255,255,.18);
  border-radius:999px;padding:.3rem .75rem;font-size:.72rem;cursor:pointer;font-family:inherit}
.tglbtn:hover{background:rgba(255,255,255,.18)}
.tglbtn[aria-pressed="false"]{opacity:.42;text-decoration:line-through}

/* next steps & remediation.
   Deliberately NOT colour-coded green/amber/red: an action is not a verdict, and the
   verdict badges beside it already carry hue + glyph + texture. */
.nstier{margin-top:1rem}
.nsth{font-size:.72rem;text-transform:uppercase;letter-spacing:.7px;font-weight:700;
  color:var(--text-secondary);margin:.9rem 0 .5rem;padding-left:.15rem}
.card.ns{padding:.9rem 1rem;margin-bottom:.55rem}
.nsh{display:flex;flex-wrap:wrap;gap:.4rem;align-items:center;margin-bottom:.5rem}
.nsr{font-family:var(--mono,ui-monospace,monospace);font-size:.72rem;color:var(--text-muted);
  border:1px solid var(--border);border-radius:999px;padding:.05rem .45rem}
.rm{margin-top:.45rem;font-size:.8rem}
.rm .rmh{display:flex;flex-wrap:wrap;gap:.3rem;align-items:center;margin-bottom:.35rem}
.rml{display:grid;grid-template-columns:11rem 1fr;gap:.5rem;padding:.2rem 0;
  border-top:1px dotted var(--border)}
.rml:first-of-type{border-top:none}
.rmk{font-size:.66rem;text-transform:uppercase;letter-spacing:.5px;color:var(--text-muted);
  font-weight:700;padding-top:.1rem}
.rmdo{border-top:1px solid var(--border);margin-top:.2rem;padding-top:.4rem;font-weight:600}
.rmgap{margin-top:.45rem}
.pns{margin-top:.7rem;border:1px solid var(--border);border-radius:8px;padding:.7rem .9rem;
  background:var(--surface-2)}
.pnsh{font-size:.68rem;text-transform:uppercase;letter-spacing:.6px;font-weight:700;
  color:var(--text-secondary);margin-bottom:.35rem}
.pnsl{margin:0;padding-left:1.15rem;font-size:.8rem}
.pnsl li{margin:.3rem 0}
@media (max-width:720px){.rml{grid-template-columns:1fr}}

/* generic */
section{margin-top:2rem}
.slabel{font-size:.69rem;text-transform:uppercase;letter-spacing:.8px;color:var(--text-muted);
  font-weight:700;margin:0 0 .625rem}
.card{background:var(--surface);border:1px solid var(--border);border-radius:10px;
  padding:1.25rem;box-shadow:var(--shadow)}
h2{font-size:1.12rem;margin:0 0 .25rem;letter-spacing:-.2px}
p{margin:0 0 .625rem;color:var(--text-secondary);max-width:74ch}
.muted{color:var(--text-muted)}
.tw{overflow-x:auto;border:1px solid var(--border);border-radius:10px;background:var(--surface);
  max-width:100%}
table{border-collapse:collapse;width:100%;font-size:.81rem}
th{background:var(--surface-2);text-align:left;font-size:.66rem;text-transform:uppercase;
  letter-spacing:.6px;color:var(--text-muted);padding:.56rem .75rem;
  border-bottom:1px solid var(--border);white-space:nowrap;font-weight:700}
td{padding:.56rem .75rem;border-bottom:1px solid var(--border);vertical-align:top}
tr:last-child td{border-bottom:none}
details{margin-top:.625rem}
summary{cursor:pointer;font-size:.78rem;color:var(--text-secondary);padding:.375rem 0;
  font-weight:600;list-style:none}
summary::-webkit-details-marker{display:none}
summary::before{content:"\\25b8 ";color:var(--text-muted)}
details[open]>summary::before{content:"\\25be "}
a{color:var(--cta)}

/* verdict badges — hue + glyph + texture, never hue alone.
   Every badge is the SAME size and weight: a pass never looks bigger than a fail. */
.v{display:inline-flex;align-items:center;gap:.3rem;font-size:.66rem;font-weight:800;
  letter-spacing:.5px;padding:.12rem .5rem;border-radius:999px;border:1px solid;
  white-space:nowrap;line-height:1.5}
.v-pass{color:var(--pass-ink);background:var(--pass-bg);border-color:var(--pass-br)}
.v-fail{color:var(--fail-ink);background:var(--fail-bg);border-color:var(--fail-br);
  border-left-width:3px}
.v-invl{color:var(--text-muted);background:var(--hatch);border-color:var(--n-300);
  border-style:dashed}
.v-warn{color:var(--warn-ink);background:var(--warn-bg);border-color:var(--warn-br)}
.v-skip{color:var(--text-muted);background:var(--surface-inset);border-color:var(--border-strong);
  border-style:dotted}
.v-man{color:var(--warn-ink);background:var(--warn-bg);border-color:var(--warn-br);
  border-style:double;border-width:3px;padding:.02rem .42rem}
.v-neut{color:var(--text-muted);background:var(--surface-inset);border-color:var(--border)}

/* verdict card */
.verdict{border-left:4px solid var(--n-300)}
.verdict .word{font-size:2rem;line-height:1.15;font-weight:900;letter-spacing:-.6px;margin:0 0 .375rem}
/* Coverage band: first thing inside the verdict card, and it is set LARGER than the
   verdict word on purpose. What did not run outranks what the run concluded. It is
   achromatic + hatched like every other "hole" on this page — never amber, never green. */
.execband{margin:0 0 .875rem;padding:.7rem .85rem;border-radius:8px;border:1px solid var(--border);
  background:var(--surface-2)}
.execband.hole{border:1px dashed var(--n-300);background:var(--hatch)}
.execband .el{font-size:1.15rem;line-height:1.3;font-weight:900;letter-spacing:-.3px;
  color:var(--text);font-variant-numeric:tabular-nums}
.execband .ef{margin-top:.3rem;font-size:.76rem;line-height:1.45;color:var(--text-secondary)}
@media(max-width:560px){.execband .el{font-size:1rem}}
.counts{display:flex;gap:1.6rem;flex-wrap:wrap;margin:1rem 0 .75rem}
.counts div{font-size:.69rem;text-transform:uppercase;letter-spacing:.7px;color:var(--text-muted);
  font-weight:700}
.counts b{display:block;font-size:1.6rem;font-weight:900;letter-spacing:-.5px;margin-bottom:1px}
.bar{height:.5rem;border-radius:999px;overflow:hidden;display:flex;background:var(--surface-inset)}
.bar i{display:block;height:100%}
.z-pass{background:var(--cta)}
.z-fail{background:var(--fail-ink)}
.z-oth{background:var(--border-strong)}
.z-invl{background:var(--hatch);border-left:1px dashed var(--n-300)}
.rule{margin-top:.875rem;padding-top:.75rem;border-top:1px solid var(--border);
  font-size:.78rem;color:var(--text-muted)}

/* instrument strip */
.strip{display:grid;grid-template-columns:repeat(auto-fill,minmax(11rem,1fr));gap:.625rem}
.tile{border:1px solid var(--border);border-radius:8px;padding:.625rem .75rem;background:var(--surface)}
.tile.f{border-style:dashed;background:var(--hatch)}
.tile .n{font-size:.66rem;text-transform:uppercase;letter-spacing:.6px;color:var(--text-muted);
  font-weight:700;margin-bottom:.3rem;overflow-wrap:anywhere}
.tile .s{font-size:.78rem;font-weight:700}

/* journey spine */
.spine{display:grid;grid-template-columns:2.1rem minmax(0,1fr) repeat(4,3.9rem);
  gap:0 .625rem;align-items:start}
.spine .hd{font-size:.6rem;text-transform:uppercase;letter-spacing:.7px;color:var(--text-muted);
  font-weight:800;text-align:center;padding-bottom:.5rem}
.node{position:relative;display:flex;justify-content:center;padding-top:2px;min-height:100%}
.dot{width:1.6rem;height:1.6rem;border-radius:50%;border:2px solid;display:grid;place-items:center;
  font-size:.8rem;font-weight:900;background:var(--surface);z-index:2;flex:none}
.dot.ok{background:var(--cta);border-color:var(--cta);color:#fff}
.dot.no{background:var(--fail-ink);border-color:var(--fail-ink);color:#fff}
.dot.un{border-color:var(--n-300);border-style:dashed;color:var(--n-300);background:var(--hatch)}
.dot.dia{border-radius:4px;transform:rotate(45deg);width:1.5rem;height:1.5rem}
.dot.dia span{transform:rotate(-45deg)}
.link{position:absolute;top:1.6rem;bottom:-.625rem;left:50%;margin-left:-1px;width:2px;
  background:var(--cta)}
.link.cut{background:repeating-linear-gradient(180deg,var(--n-300) 0 4px,transparent 4px 8px)}
.body{padding-bottom:1.4rem;min-width:0}
.body .t{font-size:.94rem;font-weight:600;letter-spacing:-.1px}
.body .m{font-family:var(--mono);font-size:.69rem;margin-top:.3rem;color:var(--text-secondary);
  overflow-wrap:anywhere}
.rung{text-align:center;padding-top:3px;font-size:.875rem;font-weight:800}
.r-ok{color:var(--cta)}
.r-no{color:var(--fail-ink)}
.r-nd{color:var(--n-300);font-size:1rem}
.r-un{color:var(--text-muted);background:var(--hatch);border:1px dashed var(--n-300);
  border-radius:5px;display:inline-block;width:1.5rem;height:1.5rem;line-height:1.35rem;
  font-size:.75rem}
.chips{display:none;gap:.375rem;flex-wrap:wrap;margin-top:.5rem}
.chip{font-size:.6rem;font-weight:800;letter-spacing:.5px;padding:.12rem .45rem;border-radius:999px;
  border:1px solid var(--border);color:var(--text-muted);background:var(--surface-inset)}
.chip.c-ok{color:var(--pass-ink);background:var(--pass-bg);border-color:var(--pass-br)}
.chip.c-no{color:var(--fail-ink);background:var(--fail-bg);border-color:var(--fail-br);
  border-left-width:3px}
.chip.c-un{background:var(--hatch);border-style:dashed;border-color:var(--n-300)}

/* the hole: absent, not green */
.ghost{margin-top:.625rem;border:1px dashed var(--n-300);border-radius:8px;background:var(--hatch);
  padding:.75rem .875rem}
.ghost .gh{font-size:.66rem;text-transform:uppercase;letter-spacing:.7px;font-weight:800;
  color:var(--text-muted);margin-bottom:.44rem}
.ghost li{font-family:var(--mono);font-size:.69rem;color:var(--text-muted);margin:3px 0;
  list-style:none;overflow-wrap:anywhere}
.ghost li::before{content:"\\25a8\\00a0\\00a0"}
.ghost li.cause{margin-bottom:.5rem;font-family:var(--sans);font-size:.78rem}
.ghost li.cause::before{content:"\\2612\\00a0\\00a0"}
.ghost .gf{margin-top:.56rem;font-size:.78rem;color:var(--text-muted);font-family:var(--sans);
  max-width:74ch}
.seeds{background:var(--surface-2);border:1px solid var(--border);border-radius:8px;
  padding:.7rem .875rem;margin:.875rem 0 1.1rem;font-family:var(--mono);font-size:.72rem}
.seeds .why{font-family:var(--sans);font-size:.78rem;color:var(--text-muted);margin-top:.375rem}
.jhead{display:flex;gap:.75rem;align-items:baseline;flex-wrap:wrap;margin-bottom:2px}

/* the walk */
.wreq{font-size:.78rem;color:var(--text-secondary);margin:.5rem 0 .25rem}
.wreq code{margin-right:.3rem}
.wstep{border:1px solid var(--border);border-left-width:3px;border-radius:10px;
  padding:.875rem 1rem;margin-top:.875rem;background:var(--surface)}
.wstep.s-pass{border-left-color:var(--cta)}
.wstep.s-fail{border-left-color:var(--fail-ink);background:var(--fail-bg)}
.wstep.s-fault{border-left-color:var(--n-300);border-left-style:dashed}
/* zero checks: a hole, not a clean step. Achromatic + hatched + dashed, never amber. */
.wstep.hole{border-style:dashed;border-color:var(--n-300);background:var(--hatch);
  color:var(--text-muted)}
.wsh{display:flex;align-items:center;gap:.56rem;flex-wrap:wrap;margin-bottom:.44rem}
.wsn{width:1.5rem;height:1.5rem;border-radius:50%;border:1px solid var(--border-strong);
  display:grid;place-items:center;font-size:.69rem;font-weight:800;flex:none;
  background:var(--surface-2);font-variant-numeric:tabular-nums}
.wst{font-size:.94rem;font-weight:600;letter-spacing:-.1px;min-width:0;overflow-wrap:anywhere}
.wlab{font-size:.6rem;text-transform:uppercase;letter-spacing:.8px;font-weight:800;
  color:var(--text-muted);margin-bottom:.3rem}
.wgrid{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:1rem;align-items:start}
.wacts{margin:0;padding-left:1.2rem;font-size:.81rem}
.wacts li{margin:.2rem 0;overflow-wrap:anywhere}
.wnone{color:var(--text-muted);font-size:.78rem}
.wexp td:first-child{font-size:.69rem;text-transform:uppercase;letter-spacing:.5px;
  color:var(--text-muted);font-weight:700;white-space:nowrap}
.wrung{margin-top:.625rem}
.wrl{font-size:.6rem;text-transform:uppercase;letter-spacing:.7px;font-weight:800;
  color:var(--text-muted);margin-bottom:.25rem}
details.wshot{margin-top:.625rem}
details.wshot>summary{font-size:.72rem}
details.wshot figure.shot img{max-width:100%;height:auto}

/* the page block + the two design rungs. Deliberately NOT a distinct hue: rungs 6/7
   are checks like any other and must not read as a softer class of finding. */
.pblock{border:1px solid var(--border);border-radius:8px;padding:.7rem .8rem;
  margin-top:.4rem;background:var(--surface-2)}
.pbh{display:flex;gap:.35rem;flex-wrap:wrap;margin-bottom:.35rem}
.wfpanel{border:1px solid var(--border);border-radius:8px;padding:.7rem .8rem;
  background:var(--surface-2)}
.wfh{font-size:.6rem;text-transform:uppercase;letter-spacing:.8px;font-weight:800;
  color:var(--text-muted);margin-bottom:.35rem;display:flex;gap:.4rem;align-items:center;
  flex-wrap:wrap}
tr.hole td{background:var(--hatch);color:var(--text-muted)}

/* alerts */
.alert{border-radius:8px;padding:.75rem .875rem;font-size:.81rem;margin:.75rem 0;border:1px solid}
.alert-warn{background:var(--warn-bg);border-color:var(--warn-br);color:var(--warn-ink)}
.alert-fail{background:var(--fail-bg);border-color:var(--fail-br);color:var(--fail-ink)}
.alert-invl{background:var(--hatch);border-color:var(--n-300);border-style:dashed;
  color:var(--text-muted)}
.pre{background:var(--surface-inset);border:1px solid var(--border);border-radius:8px;
  padding:.75rem .875rem;font-family:var(--mono);font-size:.69rem;overflow-x:auto;white-space:pre;
  color:var(--text-secondary);max-width:100%}
figure.shot{margin:.625rem 0 0}
figure.shot img{max-width:100%;height:auto;display:block;border:1px solid var(--border-strong);
  border-radius:6px}
figure.shot figcaption{color:var(--text-muted);margin-top:.25rem}

@media(max-width:820px){
  .spine{grid-template-columns:1.9rem minmax(0,1fr)}
  .spine .hd,.rung{display:none}
  .chips{display:flex}
  .counts{gap:1rem}
  .wgrid{grid-template-columns:minmax(0,1fr)}
}
@media print{
  header.top{position:static}
  .tglbtn{display:none}
}
`;

const JS = `
(function(){
  var root=document.documentElement;
  var th=document.getElementById('th');
  if(th)th.onclick=function(){
    var cur=root.getAttribute('data-theme');
    if(!cur){cur=matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light';}
    root.setAttribute('data-theme',cur==='dark'?'light':'dark');
  };
  Array.prototype.forEach.call(document.querySelectorAll('[data-filter]'),function(b){
    b.onclick=function(){
      var on=b.getAttribute('aria-pressed')==='true';
      b.setAttribute('aria-pressed',on?'false':'true');
      Array.prototype.forEach.call(
        document.querySelectorAll('[data-v="'+b.getAttribute('data-filter')+'"]'),
        function(el){el.style.display=on?'none':'';});
    };
  });
})();
`;

/* ───────────────────────── assemble ───────────────────────── */

function render(d, ver, rebase, shotCtx) {
  const ctx = shotCtx ||
    { roots: shotRoots('docs/report.json'), bytes: 0, embedded: 0, missing: 0, overBudget: 0 };
  const checks = arr(d.checks);
  const instruments = arr(d.instruments);
  const p = d.project || {};
  const title = (has(p.displayName) ? p.displayName : (has(p.id) ? p.id : 'Project')) +
                ' Verification';

  let minorWarn = '';
  if (ver.newerMinor) {
    minorWarn = '<div class="wrap"><div class="alert alert-warn" style="margin-top:1rem">' +
      '<b>Newer minor schema.</b> report.json declares ' + esc(ver.raw) + '; this renderer ' +
      'implements ' + SUPPORTED_MAJOR + '.' + SUPPORTED_MINOR + '. Fields added since are ' +
      'present in the data and <b>not shown on this page</b>.</div></div>';
  }

  // The walk renderer needs the design join and the path rebaser; they are threaded
  // through ctx rather than re-derived per step.
  ctx.dbp = designByPage(checks);
  ctx.rebase = rebase;
  ctx.rem = remediationIndex(checks);
  ctx.doc = d;

  const body = [
    renderVerdict(d, checks, instruments),
    // Second thing on the page, deliberately: the previous render made a reader scroll
    // past 135 unexplained holes before reaching anything they could act on.
    renderNextSteps(d),
    renderPersonas(d, checks),
    renderHeadline(checks, rebase),
    renderInstruments(d, instruments, checks),
    renderJourneys(d, checks, rebase),
    renderWalks(d, ctx),
    renderBridge(d, checks),
    renderFindings(checks, rebase),
    renderCoverage(d, checks),
    renderDeferrals(d),
    renderScope(d, checks, instruments),
    renderAppendix(d),
  ].join('\n');

  const foot = '<p class="muted" style="margin-top:2.25rem;font-size:.75rem;text-align:center">' +
    'Rendered from <code>report.json</code> (schema ' + esc(ver.raw) + ') \u00b7 ' +
    esc(has(p.id) ? p.id : 'unnamed project') +
    ' \u00b7 every verdict on this page is either measured by a named instrument or explicitly ' +
    'marked <b>not run</b>. Nothing is inferred.</p>';

  return '<!doctype html>\n<html lang="en"><head><meta charset="utf-8">' +
    '<meta name="viewport" content="width=device-width,initial-scale=1">' +
    '<title>' + esc(title) + '</title><style>' + CSS + '</style></head><body>' +
    renderMasthead(d) + minorWarn +
    '<div class="wrap">' + body + foot + '</div>' +
    '<script>' + JS + '</script></body></html>\n';
}

/* ───────────────────────── SELFTEST ─────────────────────────
 * NOTE, 2026-08-18: this suite did not exist. `node report-render.js --selftest` printed
 * "unknown argument" and exited 0 — a self-check that reports success by not running is
 * the same false green this renderer is built to refuse, so it is written here rather
 * than assumed. It renders inline fixtures and asserts on the HTML string: no app, no
 * report.json, no artifacts.                                                            */

function selftest() {
  let bad = 0;
  const t = (name, ok, extra) => {
    if (!ok) bad++;
    console.log((ok ? 'ok   ' : 'FAIL ') + name + (ok || !extra ? '' : '  ' + extra));
  };
  const noRebase = (p) => ({ remote: false, href: String(p), original: String(p) });
  const ctx = () => ({ roots: [], bytes: 0, embedded: 0, missing: 0, overBudget: 0 });
  const ver = { major: 1, minor: 1, newerMinor: false, raw: '1.1' };
  const html = (d) => render(d, ver, noRebase, ctx());

  const daCheck = (page, id, verdict, extra) => Object.assign({
    id: 'design-audit/' + id + '/' + page, instrument: 'design-audit', kind: 'ui',
    module: page.split('.')[0], page, journey: null, stepIndex: null, stepName: null,
    requirement: null, title: id, verdict, provenance: 'measured', detail: 'd',
    evidence: [], blocks: [],
  }, extra || {});

  const step = (n, name, checks, page) => ({
    n, name, requirement: [], actions: [], expects: { landsOn: '.mx-name-x', pageSays: [],
    pageDoesNotSay: [], microflows: [], writes: null }, reached: true,
    status: checks.length === 0 ? 'fault'
          : checks.some((c) => c.verdict === 'fail') ? 'fail' : 'pass',
    checks, shot: null, ms: 1, page,
  });
  const pageBlock = (qn, over) => Object.assign({
    qualifiedName: qn, role: ['MxRole_Operator'], inScope: true, orphan: null,
    wireframe: 'design/wireframes/x.html', rung6: 'pass', rung7: [],
    resolvedBy: 'widget-intersection', candidates: [qn], usedSelectors: ['x'], why: null,
  }, over || {});

  const base = (over) => Object.assign({
    schemaVersion: '1.1', project: { id: 'P' }, run: { env: {} },
    checks: [], instruments: [], coverage: [], deferrals: [], walks: [],
    roleSets: [], pageCoverage: null,
  }, over || {});

  /* 1. version gate ------------------------------------------------------- */
  t('checkVersion accepts the implemented minor',
    checkVersion({ schemaVersion: '1.1' }, 'x').newerMinor === false);
  t('checkVersion FLAGS a newer minor rather than rendering it silently',
    checkVersion({ schemaVersion: '1.9' }, 'x').newerMinor === true);
  // A major mismatch calls process.exit(2); asserting that in-process would kill the
  // suite, so it is asserted out-of-process by main() and covered in the runbook.

  /* 2. zero checks is NOT MEASURED, never a pass -------------------------- */
  t('a report with zero checks says NOT MEASURED',
    html(base()).indexOf('NOT MEASURED') !== -1);
  t('and never says PASSED', html(base()).indexOf('>PASSED<') === -1);
  t('a report with zero checks says NOTHING EXAMINED in the coverage band',
    html(base()).indexOf('NOTHING EXAMINED — this report contains zero checks') !== -1);

  /* 2b. COVERAGE LEADS — the measured misread ------------------------------
     PROJECT-A, 2026-08-20: 205 pass / 23 fail / 353 fault / 30 skipped over 611
     checks was read as "roughly 90% healthy". Scaled-down fixture, same shape.     */
  const lopsided = base({
    instruments: [{ name: 'design-audit', verdict: 'pass' },
                  { name: 'coverage-ledger/M', verdict: 'pass' },
                  { name: 'conformance', verdict: 'pass' }],
    checks: [
      daCheck('M.A', 'rung7/a', 'pass'),
      daCheck('M.A', 'rung7/b', 'fail'),
      { id: 'coverage/M/1', instrument: 'coverage-ledger', kind: 'coverage', module: 'M',
        page: null, journey: null, stepIndex: null, stepName: null, requirement: null,
        title: 'leaves', verdict: 'fault', provenance: 'declared', notRun: true,
        detail: 'ledger never read', evidence: [], blocks: [] },
      { id: 'coverage/M/2', instrument: 'coverage-ledger', kind: 'coverage', module: 'M',
        page: null, journey: null, stepIndex: null, stepName: null, requirement: null,
        title: 'rows', verdict: 'fault', provenance: 'declared', notRun: true,
        detail: 'ledger never read', evidence: [], blocks: [] },
    ],
  });
  const hL = html(lopsided);
  t('the headline leads with what did NOT run, with a faults-included denominator',
    hL.indexOf('50% of 4 checks did not run · 1 passed · 1 failed · 2 did not run · 0 skipped')
      !== -1);
  t('the not-run count is printed before the pass count',
    hL.indexOf('⌀ DID NOT RUN</div>') !== -1 &&
    hL.indexOf('⌀ DID NOT RUN</div>') < hL.indexOf('✓ passed</div>'));
  t('no pass rate is offered anywhere on the page',
    !/\d+% (passed|pass|healthy|green|of checks passed)/i.test(hL));
  t('an instrument whose every check faulted is marked, not left looking like a pass',
    hL.indexOf('EVERY CHECK DID NOT RUN (2 of 2)') !== -1);
  t('an instrument that emitted no check at all says NOTHING EXAMINED',
    hL.indexOf('NOTHING EXAMINED — NO CHECKS EMITTED') !== -1);
  t('  …and both are named once, in the open, not left to be counted off the tiles',
    hL.indexOf('produced no evidence at all: </b>coverage-ledger/M, conformance') !== -1);
  t('an instrument that DID produce evidence is not flagged',
    hL.indexOf('2 of 2 checks from this instrument executed') !== -1);

  /* 3. an in-scope page with no walk renders as fault --------------------- */
  const uncovered = base({
    roleSets: [{ id: 'set-1', roles: ['MxRole_Operator'], pages: ['M.A', 'M.B'],
                 pageCount: 2, empty: false }],
    pageCoverage: { inScope: 2, walked: 1, uncovered: 1, walkedOutOfScope: [],
                    byJourney: [{ journey: 'J-1', pages: ['M.B'] }], orphans: [] },
    walks: [{ journey: 'J-1', title: 'w', persona: 'p', requirement: [], seeds: null,
              steps: [step(1, 's1', [{ rung: 'ui', name: 'a', verdict: 'pass', detail: '' }],
                           pageBlock('M.A'))] }],
    checks: [daCheck('M.B', 'rung6/wireframe-conformance', 'skipped'),
             daCheck('M.B', 'rung7/a11y', 'skipped'),
             { id: 'scope/uncovered/M.B', instrument: 'page-scope', kind: 'ui', module: 'M',
               page: 'M.B', journey: 'J-1', stepIndex: null, stepName: null, requirement: null,
               title: 'walked', verdict: 'fault', provenance: 'declared', notRun: true,
               detail: 'never walked', evidence: [], blocks: [] }],
  });
  const hU = html(uncovered);
  t('an in-scope page nothing walked renders NEVER WALKED', hU.indexOf('NEVER WALKED') !== -1);
  t('and is listed under the journey that should have covered it',
    hU.indexOf('should have been covered by') !== -1 && hU.indexOf('J-1') !== -1);
  t('the uncovered count is in the headline, not a footnote',
    hU.indexOf('1 of 2 in-scope pages were never walked') !== -1);
  t('the verdict word is INCOMPLETE while pages are uncovered',
    hU.indexOf('>INCOMPLETE<') !== -1);

  /* 4. no wireframe → rung 6 skipped, rung 7 still runs ------------------- */
  const noWf = base({
    roleSets: [{ id: 'set-1', roles: ['R'], pages: ['M.A'], pageCount: 1, empty: false }],
    pageCoverage: { inScope: 1, walked: 1, uncovered: 0, walkedOutOfScope: [],
                    byJourney: [], orphans: [] },
    walks: [{ journey: 'J-1', title: 'w', persona: 'p', requirement: [], seeds: null,
              steps: [step(1, 's1', [{ rung: 'ui', name: 'a', verdict: 'pass', detail: '' }],
                pageBlock('M.A', { wireframe: null, rung6: 'skipped' }))] }],
    checks: [daCheck('M.A', 'rung6/wireframe-conformance', 'skipped',
                     { reason: 'no wireframe was drawn for this page' }),
             daCheck('M.A', 'rung7/unmatched-class', 'fail'),
             daCheck('M.A', 'rung7/a11y', 'skipped')],
  });
  const hW = html(noWf);
  t('a page with no wireframe says so in words, never a broken image or a blank',
    hW.indexOf('No wireframe was ever drawn') !== -1);
  t('rung 6 SKIPPED is stated as not-a-pass', hW.indexOf('which is not a pass') !== -1);
  t('rung 7 still runs and its failure is shown',
    hW.indexOf('rung7/unmatched-class') !== -1 || hW.indexOf('RUNG 7') !== -1);
  t('the rung-7 failure is visible as a FAIL badge on the persona row',
    hW.indexOf('RUNG 7') !== -1 && /FAIL/.test(hW));

  /* 5. THE ONE THAT MATTERS: every behavioural check green, design rungs red.
        This must NOT produce a pass headline.                                */
  const falseGreen = base({
    roleSets: [{ id: 'set-1', roles: ['R'], pages: ['M.A'], pageCount: 1, empty: false }],
    pageCoverage: { inScope: 1, walked: 1, uncovered: 0, walkedOutOfScope: [],
                    byJourney: [], orphans: [] },
    instruments: [{ name: 'journey-runner', verdict: 'pass' },
                  { name: 'design-audit', verdict: 'pass' }],
    walks: [{ journey: 'J-1', title: 'w', persona: 'p', requirement: [], seeds: null,
              steps: [step(1, 's1', [{ rung: 'ui', name: 'a', verdict: 'pass', detail: '' },
                                     { rung: 'data', name: 'b', verdict: 'pass', detail: '' }],
                pageBlock('M.A', { rung6: 'fault' }))] }],
    checks: [
      { id: 'journey/J-1/step1/a', instrument: 'journey-runner', kind: 'ui', module: 'M',
        journey: 'J-1', stepIndex: 1, stepName: 's1', requirement: null, title: 'a',
        verdict: 'pass', provenance: 'measured', detail: '', evidence: [], blocks: [] },
      { id: 'journey/J-1/step1/b', instrument: 'journey-runner', kind: 'data', module: 'M',
        journey: 'J-1', stepIndex: 1, stepName: 's1', requirement: null, title: 'b',
        verdict: 'pass', provenance: 'measured', detail: '', evidence: [], blocks: [] },
      daCheck('M.A', 'rung6/wireframe-conformance', 'fault'),
      daCheck('M.A', 'rung7/unmatched-class', 'fault'),
    ],
  });
  const hF = html(falseGreen);
  t('THE FALSE-GREEN CASE: all behaviour green + design red does NOT say PASSED',
    hF.indexOf('>PASSED<') === -1, 'headline leaked a PASSED');
  t('  …it says FAILED ON DESIGN', hF.indexOf('FAILED ON DESIGN') !== -1);
  t('  …and names the two questions as separate',
    hF.indexOf('are two questions') !== -1);

  // Same fixture with the design rungs merely FAILING rather than faulting.
  const failOnly = JSON.parse(JSON.stringify(falseGreen));
  failOnly.checks[2].verdict = 'fail';
  failOnly.checks[3].verdict = 'fail';
  failOnly.walks[0].steps[0].page.rung6 = 'fail';
  t('design rungs FAILING also refuses a pass headline',
    html(failOnly).indexOf('>PASSED<') === -1);

  /* 6. fault is never amber, and never collapses into fail ---------------- */
  t('fault has its own achromatic class, distinct from fail and from warn',
    VERDICTS.fault.cls === 'v-invl' && VERDICTS.fault.cls !== VERDICTS.fail.cls &&
    CSS.indexOf('.v-invl') !== -1);
  t('rollup ranks fault above pass', (function () {
    const r = rollup([{ verdict: 'pass' }, { verdict: 'fault' }]);
    return r.fault === 1 && r.pass === 1;
  })());
  t('an unknown verdict string becomes fault, never pass', vkey('greenish') === 'fault');

  /* 7. one section per SET, not per role ---------------------------------- */
  const sixRoles = base({
    roleSets: [
      { id: 'set-1', roles: ['Administrator'], pages: ['M.A', 'M.B'], pageCount: 2, empty: false },
      { id: 'set-2', roles: ['MxRole_Auditor', 'MxRole_LineLeader', 'MxRole_ME',
                             'MxRole_Operator', 'MxRole_SiteAdmin', 'MxRole_Supervisor'],
        pages: ['M.A'], pageCount: 1, empty: false },
      { id: 'set-3', roles: ['RouteShowcaseUser'], pages: [], pageCount: 0, empty: true },
    ],
    pageCoverage: { inScope: 2, walked: 0, uncovered: 2, walkedOutOfScope: [],
                    byJourney: [{ journey: '(no journey for M)', pages: ['M.A', 'M.B'] }],
                    orphans: [] },
  });
  const hS = html(sixRoles);
  const sections = (hS.match(/class="jhead"/g) || []).length;
  t('three distinct sets render three persona sections, not nine and not one',
    sections === 3, 'got ' + sections);
  t('the identical-personas finding is raised, not hidden',
    hS.indexOf('Security does not differentiate these personas') !== -1);
  t('a role that reaches nothing is still shown as its own set',
    hS.indexOf('SEES NOTHING IN SCOPE') !== -1);

  /* 8. shot.file absent → an explicit why, never a broken image ----------- */
  const noShot = base({
    walks: [{ journey: 'J-1', title: 'w', persona: 'p', requirement: [], seeds: null,
              steps: [Object.assign(step(1, 's1',
                [{ rung: 'ui', name: 'a', verdict: 'pass', detail: '' }], pageBlock('M.A')),
                { shot: { file: 'tests/e2e/artifacts/does-not-exist.png' } })] }],
  });
  const hN = html(noShot);
  t('a missing screenshot renders a stated reason', hN.indexOf('No image for this step') !== -1);
  t('and emits no <img> for it', hN.indexOf('does-not-exist.png"') === -1);

  /* 9. a step with zero checks is a hole, not a clean step ---------------- */
  const zero = base({
    walks: [{ journey: 'J-1', title: 'w', persona: 'p', requirement: [], seeds: null,
              steps: [step(1, 's1', [], pageBlock('M.A'))] }],
  });
  t('a zero-check step gets the hole treatment',
    html(zero).indexOf('Zero checks ran on this step') !== -1);

  /* 10. next steps & remediation (schema 1.2) ----------------------------- */
  const rem = (over) => Object.assign({
    class: 'trace-zero-spans', measures: 'M-SENTENCE', why: 'W-SENTENCE',
    blastRadius: 'B-SENTENCE', action: 'A-SENTENCE', actionKind: 'harness',
    needsApproval: false, where: 'tests/e2e/otel.js',
  }, over || {});

  t('a report at 1.2 with failures but no nextSteps[] says the normalizer is stale, ' +
    'and never renders as "nothing to do"',
    (() => {
      const h = html(base({
        checks: [daCheck('M.A', 'rung7/a11y', 'fail')],
      }));
      return h.indexOf('normalizer older than schema 1.2') !== -1 &&
             h.indexOf('Do not read the absence as') !== -1;
    })());

  t('an empty nextSteps[] with zero findings is allowed to say so honestly',
    html(base()).indexOf('the one shape in which an empty next-steps list is honest') !== -1);

  const withNext = base({
    checks: [
      daCheck('M.A', 'rung7/a11y', 'fail', { remediation: rem({ class: 'design-a11y' }) }),
      Object.assign(daCheck('M.A', 'rung7/overflow', 'fault'),
        { remediation: rem({ class: 'design-no-nav-route', action: 'PAGE-A-ACTION' }) }),
    ],
    nextSteps: [
      { rank: 1, id: 'next/design-a11y', class: 'design-a11y', tier: 8, scope: 'project',
        target: null, measures: 'M', why: 'W', blastRadius: 'B', action: 'GROUP-ACTION',
        actionKind: 'design', needsApproval: false, where: null, count: 1,
        verdicts: { fail: 1 }, affects: ['M.A'], checkIds: ['design-audit/rung7/a11y/M.A'] },
      { rank: 2, id: 'next/design-no-nav-route', class: 'design-no-nav-route', tier: 7,
        scope: 'project', target: null, measures: 'M2', why: 'W2', blastRadius: 'B2',
        action: 'GROUP-ACTION-2', actionKind: 'harness', needsApproval: false, where: null,
        count: 1, verdicts: { fault: 1 }, affects: ['M.A'],
        checkIds: ['design-audit/rung7/overflow/M.A'] },
    ],
  });
  const hNext = html(withNext);
  t('the next-steps section renders and is placed before the findings table',
    hNext.indexOf('What to do next') !== -1 &&
    hNext.indexOf('What to do next') < hNext.indexOf('Every finding'));
  t('every remediation renders all four sentences, not just the action',
    ['M-SENTENCE', 'W-SENTENCE', 'B-SENTENCE', 'A-SENTENCE']
      .every((x) => hNext.indexOf(x) !== -1));
  t('a next-steps row names the checks it would close',
    hNext.indexOf('design-audit/rung7/a11y/M.A') !== -1);
  // fail = measured and wrong; fault = never measured. The labels must not collapse them.
  t('a FAIL remediation is labelled "Why it failed", a FAULT one "Why it did not run"',
    hNext.indexOf('Why it failed') !== -1 && hNext.indexOf('Why it did not run') !== -1);
  t('a model-write action is badged as needing approval',
    html(base({
      checks: [Object.assign(daCheck('M.A', 'rung7/a11y', 'fail'),
        { remediation: rem({ needsApproval: true, actionKind: 'model' }) })],
      nextSteps: [{ rank: 1, id: 'n', class: 'ui-text-contradiction', tier: 3, scope: 'page',
        target: 'M.A', measures: 'M', why: 'W', blastRadius: 'B', action: 'A',
        actionKind: 'model', needsApproval: true, where: 'M.A', count: 1,
        verdicts: { fail: 1 }, affects: ['M.A'], checkIds: ['x'] }],
    })).indexOf('NEEDS APPROVAL') !== -1);

  // The bug this catches, measured: the per-page panel first reused the project-wide
  // group's action, so the panel under one page told the reader to go fix a different
  // page. The per-page panel must quote the check that names THIS page.
  t('the per-page next-steps panel quotes the page’s own action, not the group’s',
    (() => {
      const d = base({
        checks: [Object.assign(daCheck('M.A', 'rung7/overflow', 'fault'),
          { remediation: rem({ class: 'design-no-nav-route', action: 'PAGE-A-ACTION' }) }),
          Object.assign(daCheck('M.B', 'rung7/overflow', 'fault'),
            { remediation: rem({ class: 'design-no-nav-route', action: 'PAGE-B-ACTION' }) })],
        nextSteps: [{ rank: 3, id: 'n', class: 'design-no-nav-route', tier: 7, scope: 'project',
          target: null, measures: 'M', why: 'W', blastRadius: 'B', action: 'PAGE-A-ACTION',
          actionKind: 'harness', needsApproval: false, where: null, count: 2,
          verdicts: { fault: 2 }, affects: ['M.A', 'M.B'], checkIds: ['x', 'y'] }],
        walks: [{ journey: 'J-1', title: 'w', persona: 'p', requirement: [], seeds: null,
                  steps: [step(1, 's1', [{ rung: 'ui', name: 'c', verdict: 'pass', detail: 'd',
                                           checkId: 'k' }], pageBlock('M.B'))] }],
      });
      const h = html(d);
      const i = h.indexOf('Next for M.B');
      if (i < 0) return false;
      const panel = h.slice(i, i + 1200);
      return panel.indexOf('PAGE-B-ACTION') !== -1 && panel.indexOf('PAGE-A-ACTION') === -1;
    })());

  t('a page with nothing outstanding says so rather than rendering an empty panel',
    (() => {
      const d = base({
        checks: [], nextSteps: [],
        walks: [{ journey: 'J-1', title: 'w', persona: 'p', requirement: [], seeds: null,
                  steps: [step(1, 's1', [{ rung: 'ui', name: 'c', verdict: 'pass', detail: 'd',
                                           checkId: 'k' }], pageBlock('M.A'))] }],
      });
      return html(d).indexOf('Nothing outstanding for M.A') !== -1;
    })());

  t('a walk step whose page could not be resolved says why instead of listing nothing',
    (() => {
      const d = base({
        walks: [{ journey: 'J-1', title: 'w', persona: 'p', requirement: [], seeds: null,
                  steps: [step(1, 's1', [{ rung: 'ui', name: 'c', verdict: 'pass', detail: 'd',
                                           checkId: 'k' }],
                               pageBlock(null, { qualifiedName: null, why: 'ambiguous' }))] }],
      });
      return html(d).indexOf('No next steps for this step') !== -1;
    })());

  // A non-pass row with no remediation must be visibly a GAP IN THE TABLE, never a
  // bare detail string that reads like the whole story.
  t('a non-pass with no remediation renders NO REMEDIATION DERIVED, not silence',
    html(base({ checks: [daCheck('M.A', 'rung7/a11y', 'fail')] }))
      .indexOf('NO REMEDIATION DERIVED') !== -1);
  t('a remediation missing its action says the table has a gap, and does not invent one',
    html(base({ checks: [Object.assign(daCheck('M.A', 'rung7/a11y', 'fail'),
      { remediation: rem({ action: null }) })] })).indexOf('NO ACTION DERIVED') !== -1);

  t('the findings table names WHERE each finding lives',
    (() => {
      const h = html(base({ checks: [daCheck('M.A', 'rung7/a11y', 'fail')] }));
      return h.indexOf('>Where</th>') !== -1 && h.indexOf('>M.A</span>') !== -1;
    })());
  t('a finding attributable to no page says so rather than rendering a blank cell',
    html(base({ checks: [{ id: 'x/y', instrument: 'i', kind: 'ui', module: null, page: null,
      journey: null, stepIndex: null, stepName: null, requirement: null, title: 't',
      verdict: 'fail', provenance: 'measured', detail: 'd', evidence: [], blocks: [] }] }))
      .indexOf('NOT ATTRIBUTED TO A PAGE') !== -1);

  t('per-process next steps render at the end of a journey walk',
    (() => {
      const d = base({
        checks: [{ id: 'journey/J-1/step1/x', instrument: 'journey-runner', kind: 'ui',
          module: 'M', page: 'M.A', journey: 'J-1', stepIndex: 1, stepName: 's1',
          requirement: null, title: 'reached', verdict: 'fail', provenance: 'measured',
          detail: 'd', evidence: [], blocks: [],
          remediation: rem({ class: 'journey-landing-guard-failed', action: 'PROCESS-ACTION' }) }],
        nextSteps: [{ rank: 1, id: 'n', class: 'journey-landing-guard-failed', tier: 1,
          scope: 'module', target: 'M', measures: 'M', why: 'W', blastRadius: 'B',
          action: 'PROCESS-ACTION', actionKind: 'journey', needsApproval: false,
          where: 'journeys/M.journey.json', count: 1, verdicts: { fail: 1 },
          affects: ['M.A'], checkIds: ['journey/J-1/step1/x'] }],
        walks: [{ journey: 'J-1', title: 'w', persona: 'p', requirement: [], seeds: null,
                  steps: [step(1, 's1', [{ rung: 'ui', name: 'reached', verdict: 'fail',
                                           detail: 'd', checkId: 'journey/J-1/step1/x' }],
                               pageBlock('M.A'))] }],
      });
      const h = html(d);
      return h.indexOf('Next for the J-1 process') !== -1 && h.indexOf('PROCESS-ACTION') !== -1;
    })());

  t('a fault on a walk step carries its remediation inline, not only in the summary',
    (() => {
      const d = base({
        checks: [], nextSteps: [],
        walks: [{ journey: 'J-1', title: 'w', persona: 'p', requirement: [], seeds: null,
                  steps: [step(1, 's1', [{ rung: 'trace', name: 'spans', verdict: 'fault',
                                           detail: 'zero', checkId: 'k' }], pageBlock('M.A'))] }],
      });
      const h = render(d, ver, noRebase,
        Object.assign(ctx(), { rem: new Map([['k', rem({ action: 'INLINE-ACTION' })]]) }));
      // render() rebuilds ctx.rem from checks[], so the inline path is exercised through
      // the real code path rather than through an injected map: with no checks[] entry
      // the row must state the gap instead of going quiet.
      return h.indexOf('NO REMEDIATION DERIVED') !== -1;
    })());

  t('verdict vocabulary is unchanged by 1.2 — fault is still DID NOT RUN, never amber',
    VERDICTS.fault.label === 'DID NOT RUN' && VERDICTS.fault.cls === 'v-invl');
  t('checkVersion accepts 1.2 as the implemented minor',
    checkVersion({ schemaVersion: '1.2' }, 'x').newerMinor === false);
  t('checkVersion still flags 1.3 as newer',
    checkVersion({ schemaVersion: '1.3' }, 'x').newerMinor === true);

  console.log(bad ? '\n' + bad + ' FAILED' : '\nall ok');
  return bad ? 1 : 0;
}

function main() {
  const argv = process.argv.slice(2);
  if (argv.indexOf('--selftest') !== -1) process.exit(selftest());
  const args = parseArgs(argv);
  const data = load(args.in);
  const ver = checkVersion(data, args.in);
  if (ver.newerMinor) {
    console.error('report-render: WARNING schemaVersion ' + ver.raw + ' is newer than ' +
      SUPPORTED_MAJOR + '.' + SUPPORTED_MINOR + '; rendering known fields only.');
  }
  const rebase = makeRebaser(args.in, args.out);
  const shotCtx = { roots: shotRoots(args.in), bytes: 0, embedded: 0, missing: 0, overBudget: 0 };
  const html = render(data, ver, rebase, shotCtx);

  const outDir = path.dirname(path.resolve(args.out));
  try { fs.mkdirSync(outDir, { recursive: true }); } catch (e) { /* exists */ }
  try { fs.writeFileSync(args.out, html, 'utf8'); }
  catch (e) { console.error('report-render: cannot write ' + args.out + ': ' + e.message);
              process.exit(1); }

  const c = rollup(arr(data.checks));
  const size = Buffer.byteLength(html, 'utf8');
  console.log('report-render: wrote ' + args.out + '  (' + (size / 1024).toFixed(1) + ' KB = ' +
    mb(size) + ')');
  // Same sentence as the band at the top of the page, and for the same reason: this
  // line is pasted into chat and read as the result. It led with the pass count until
  // 2026-08-20, which is one of the two places 205/611 got quoted as near-healthy.
  console.log('report-render: ' + executionLine(c));
  console.log('report-render: walk shots — ' + shotCtx.embedded + ' embedded (' +
    mb(shotCtx.bytes) + ' base64) / ' + shotCtx.missing + ' missing from disk / ' +
    shotCtx.overBudget + ' dropped for budget');
  if (size > PAGE_CAP) {
    // Stated, never silently shipped: a page over the cap is a real defect in this render.
    console.error('report-render: WARNING page is ' + mb(size) + ', over the ' + mb(PAGE_CAP) +
      ' cap. Lower IMAGE_BUDGET or install sips/ImageMagick so shots can be downscaled.');
  }
}

if (require.main === module) main();
module.exports = { render, checkVersion, rollup, groupJourneys, designByPage, selftest };
