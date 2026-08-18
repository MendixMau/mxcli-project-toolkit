'use strict';
// ============================================================================
// OpenTelemetry assertions for the e2e suite — microflow-level truth
// ----------------------------------------------------------------------------
// The suite could assert UI ("the page rendered") and DB ("the row count
// changed") but nothing in between. These helpers close that: which microflow
// fired, which activity failed, and whether trace internals agree with the DB.
//
// Requires Jaeger on :16686 and OTel enabled in App Settings. Setup and the
// full span vocabulary: docs/handoffs/2026-08-03-otel-microflow-testing.md
//
// ---------------------------------------------------------------------------
// READ THIS BEFORE WRITING AN ASSERTION — two ways these go vacuously green:
//
// 1. EMPTY CAPTURE. `[].every(...)` is `true`, so every assertion passes on
//    zero spans. Always `guard(spans)` first. (Also: navigating to the page you
//    are already on fires nothing — park elsewhere, then navigate back.)
//
// 2. MICROFLOW STATUS IS NOT ACTIVITY STATUS. Verified 2026-08-03 with the C01
//    mock stopped: `ACT_Route_Search` reported otel.status_code=OK while its own
//    CallRest and Import-with-mapping activities were ERROR — the microflow's
//    error handler (SUB_HandleProblemDetails) swallowed it. The UI rendered
//    normally with an empty grid. A microflow-level check is BLIND to this.
//    Use `assertNoErrors`, which walks activity spans too.
// ============================================================================

const JAEGER = process.env.JAEGER_URL || 'http://localhost:16686';
// The service name the Mendix runtime tags its spans with. Derived from the
// project identity in project.config.js (OTEL_SERVICE still overrides) rather
// than hardcoded here — this file is engine and must not name a project.
const SVC = require('./project.config').otelService;
const sleep = ms => new Promise(r => setTimeout(r, ms));

/**
 * Collect every span the service emitted at or after `t0` (ms epoch).
 * Polls, because the exporter batches — spans lag the click by a second or two.
 * Retains `logs`, which is where OTel exception events land in Jaeger.
 */
async function capture(t0, { min = 1, retries = 8, waitMs = 1500 } = {}) {
  let out = [];
  for (let i = 0; i < retries; i++) {
    await sleep(waitMs);
    let data = [];
    try {
      const r = await fetch(`${JAEGER}/api/traces?service=${SVC}&limit=400&lookback=1h`);
      data = (await r.json()).data || [];
    } catch (e) {
      // A flaky query shouldn't kill a run mid-suite; retry.
      continue;
    }
    out = [];
    for (const t of data) for (const s of t.spans) {
      if (s.startTime / 1000 < t0) continue;
      out.push({
        op: s.operationName,
        // Microseconds since epoch, as Jaeger reports it. Retained (it used to be
        // dropped) because ordering assertions need it: assertFired can only say a
        // microflow ran, which cannot tell a skipped step from a reordered one.
        start: s.startTime,
        dur: s.duration / 1000,
        traceID: s.traceID,
        tags: Object.fromEntries(s.tags.map(x => [x.key, x.value])),
        logs: (s.logs || []).map(l => Object.fromEntries(l.fields.map(f => [f.key, f.value]))),
      });
    }
    if (out.length >= min) break;
  }
  return out;
}

// --- shape helpers ---------------------------------------------------------

const microflowSpans = spans => spans.filter(s => s.tags['mx.microflow.name']);
const activitySpans  = spans => spans.filter(s => s.tags['mx.activity.name']);
const microflowNames = spans => [...new Set(microflowSpans(spans).map(s => s.tags['mx.microflow.name']))];

/** Every span whose status is ERROR, at any level. This is the real check. */
const errorSpans = spans => spans.filter(s =>
  s.tags['otel.status_code'] === 'ERROR' || s.tags['error'] === true || s.tags['error'] === 'true');

/**
 * Activity spans carry no `mx.microflow.name`. The owning microflow appears
 * only inside the status description, as:
 *   Error calling REST service
 *     at RoutingManagement.ACT_Route_Search (CallRest : 'Call REST (GET)')
 * Returns a one-line human summary per error span.
 */
function describeError(s) {
  const desc = String(s.tags['otel.status_description'] ?? s.logs[0]?.['exception.message'] ?? '');
  const first = desc.split('\n')[0].trim();
  const at = desc.match(/at\s+([\w.]+)\s*\(([^)]*)\)/);
  const where = at ? `${at[1]} (${at[2]})` : s.op;
  return `${first} — ${where}`;
}

// --- assertions ------------------------------------------------------------

/**
 * MUST be asserted before any other OTel assertion in a spec. Without it, an
 * empty capture makes everything below it pass.
 */
function guard(spans, reporter, label = 'spans captured — no vacuous pass') {
  const ok = spans.length > 0;
  reporter(`[GUARD] ${label}`, ok, `${spans.length} spans`);
  return ok;
}

/** A named microflow fired at all. */
function assertFired(spans, name, reporter) {
  const names = microflowNames(spans);
  reporter(`[MF] ${name} fired`, names.includes(name),
    names.length ? names.join(', ') : '(no microflows in capture)');
}

/**
 * Nothing failed anywhere — microflow OR activity. Catches swallowed errors
 * that leave the microflow green. Reports the actual failure text, not a count.
 */
function assertNoErrors(spans, reporter, label = 'no ERROR span at any level') {
  const errs = errorSpans(spans);
  const acts = activitySpans(spans);
  const detail = errs.length
    ? errs.slice(0, 4).map(describeError).join(' | ')
    : `${microflowSpans(spans).length} microflow + ${acts.length} activity spans, all OK`;
  reporter(`[MF] ${label}`, spans.length > 0 && errs.length === 0, detail);
  return errs;
}

/** A microflow that must NOT have run — e.g. no Delete on a read-only nav. */
function assertNotFired(spans, pattern, reporter, label) {
  const hit = microflowNames(spans).filter(n => pattern.test(n));
  reporter(`[MF] NEGATIVE: ${label}`, hit.length === 0, hit.join(', ') || 'none ran');
}

/**
 * Cross-rung: a loop in the trace iterated exactly `expected` times. This is
 * the assertion no UI check can make — the difference between "the chart
 * rendered" and "the chart rendered over the right rows".
 */
function assertLoopCount(spans, expected, reporter, label = 'a loop processed the DB row count') {
  const counts = spans.filter(s => s.tags['mx.microflow.loop.item_count'])
                      .map(s => String(s.tags['mx.microflow.loop.item_count']));
  reporter(`[X] ${label}`, counts.includes(String(expected)),
    `expected=${expected}, loops=[${counts.join(',') || 'none'}]`);
}

/**
 * The named microflows fired IN THIS ORDER. Extra microflows in between are fine
 * — this is a subsequence check, because a real page fires plenty of incidental
 * flows we do not want to enumerate.
 *
 * Why this exists: `assertFired` is existence-only. A golden path where the commit
 * runs before the validation, or where step 3 never ran but step 4 did, satisfies
 * every existence check in the suite. Ordering is the difference between "these
 * microflows exist" and "this journey happened".
 *
 * Ordered by span start time. Where two spans share a start time (batched export
 * granularity), they are treated as concurrent and either order is accepted —
 * asserting on tie-break noise would produce flaky failures, which are worse than
 * a slightly weaker check.
 */
function assertSequence(spans, names, reporter, label = null) {
  const fired = microflowSpans(spans)
    .slice()
    .sort((a, b) => a.start - b.start)
    .map(s => ({ name: s.tags['mx.microflow.name'], start: s.start }));

  let i = 0;
  const matchedAt = [];
  for (const f of fired) {
    if (i < names.length && f.name === names[i]) { matchedAt.push(f.start); i++; }
  }
  let ok = i === names.length;

  // Tie-break tolerance: if the only thing that failed is two spans sharing a
  // start time, accept it. Checked by seeing whether the missing name fired at
  // all at a timestamp equal to one already matched.
  if (!ok && i > 0 && i < names.length) {
    const missing = names[i];
    const tie = fired.some(f => f.name === missing && matchedAt.includes(f.start));
    if (tie && i + 1 === names.length) ok = true;
  }

  const detail = ok
    ? names.join(' → ')
    : `expected ${names.join(' → ')} | actual ${fired.map(f => f.name).join(' → ') || '(none)'}` +
      (i < names.length ? ` | first missing/out-of-order: ${names[i]}` : '');
  reporter(`[MF] ${label || 'ordered: ' + names.join(' → ')}`, spans.length > 0 && ok, detail);
  return ok;
}

module.exports = {
  capture, guard,
  microflowSpans, activitySpans, microflowNames, errorSpans, describeError,
  assertFired, assertNoErrors, assertNotFired, assertLoopCount, assertSequence,
  JAEGER, SVC,
};
