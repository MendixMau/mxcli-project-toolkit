'use strict';
// ============================================================================
// settle.js — wait until a Mendix page has finished, instead of sleeping a fixed time.
// ----------------------------------------------------------------------------
// A page counts as SETTLED when, for `stableMs` in a row:
//   - no visible loading indicator (Mendix progress bar, data view / list view / grid
//     loading state, spinner, aria-busy) — see BUSY;
//   - the DOM size (document.body.innerHTML length) did not change;
// after at most one bounded try at Playwright's 'networkidle' (a Mendix client that
// polls never idles, so that try is capped and never fatal).
//
// settle(page) never throws. It returns { ok, ms, reason, stuck }: ok false means the
// page was still loading when the time ran out. STUCK: the time ran out with a loading
// indicator still shown but the DOM unchanged for `stuckMs` (a Data grid 2 with 0 rows
// can keep its progress bar) — the caller decides what that means.
//
// WHY (field run 2026-10-07, requirements-driven build). journey-runner slept 1200 ms
// after every action and page-audit waited for 'networkidle' up to 20 s per page, which
// a polling client only ends by timing out. Waiting on the page's own state is faster
// on a quick page and still correct on a slow one, where a fixed sleep screenshots or
// asserts on a half-loaded screen. Ported from a field-proven upgrade-test runner,
// where the fixed 1.5 s sleep had captured a progress bar instead of the page.
//
// SETTLE_MODE=fixed restores the old fixed waits (callers pass `fallbackMs`) — keep it
// for an A/B run: the same journeys must reach the same verdicts either way.
// ============================================================================

const BUSY = [
  '.mx-progress', '.mx-progress-indicator', '.mx-progress-line',
  '.mx-dataview-loading', '.mx-listview-loading', '.mx-templategrid-loading', '.mx-datagrid-loading',
  '.widget-datagrid-loading', '.widget-gallery-loading', '.mx-loading',
  '.spinner', '.spinner-border', '.loading-spinner', '[aria-busy="true"]',
];

// Runs in the browser (page.evaluate). Self-contained: no closure over node values.
function pageSettled(busySel) {
  try {
    const sel = busySel.join(', ');
    const shown = (e) => {
      try {
        if (e.getClientRects && !e.getClientRects().length) return false;
        const s = getComputedStyle(e);
        return s.display !== 'none' && s.visibility !== 'hidden' && s.opacity !== '0';
      } catch (x) { return false; }
    };
    const busy = [...document.querySelectorAll(sel)].filter(shown)
      .map((e) => (e.className && String(e.className).split(/\s+/)[0]) || e.tagName || '?');
    return { busy, size: document.body ? document.body.innerHTML.length : 0 };
  } catch (e) {
    return { busy: ['error: ' + String(e && e.message || e).slice(0, 80)], size: -1 };
  }
}

async function settle(page, opts = {}) {
  if (process.env.SETTLE_MODE === 'fixed' && opts.fallbackMs != null) {
    await page.waitForTimeout(opts.fallbackMs).catch(() => {});
    return { ok: true, ms: opts.fallbackMs, reason: 'SETTLE_MODE=fixed' };
  }
  const timeout = opts.timeout ?? Number(process.env.SETTLE_MS || 15000);
  const stableMs = opts.stableMs ?? 500;
  const minMs = opts.minMs ?? 300;      // let an action's own request start before judging
  const stuckMs = opts.stuckMs ?? 5000;
  const idleMs = opts.networkIdleMs ?? 1500;
  const poll = 150;
  const t0 = Date.now();
  let last = null, stableSince = 0, sizeSince = 0, lastBusy = [];
  if (idleMs > 0) await page.waitForLoadState('networkidle', { timeout: Math.min(idleMs, timeout) }).catch(() => {});
  while (Date.now() - t0 < timeout) {
    const s = await page.evaluate(pageSettled, BUSY)
      .catch((e) => ({ busy: ['evaluate: ' + String(e.message).split('\n')[0]], size: -1 }));
    lastBusy = s.busy;
    if (s.size !== last || s.size < 0) sizeSince = Date.now();
    if (!s.busy.length && s.size === last) {
      if (!stableSince) stableSince = Date.now();
      if (Date.now() - stableSince >= stableMs && Date.now() - t0 >= minMs) return { ok: true, ms: Date.now() - t0 };
    } else {
      stableSince = 0;
    }
    last = s.size;
    await page.waitForTimeout(poll).catch(() => {});
  }
  const ms = Date.now() - t0, still = Date.now() - sizeSince;
  const busy = [...new Set(lastBusy)].slice(0, 4).join(', ');
  const real = lastBusy.length && !lastBusy.some((b) => /^(error|evaluate):/.test(b));
  if (real && sizeSince && still >= stuckMs)
    return { ok: false, stuck: true, ms, reason: `stuck: ${busy} shown, DOM unchanged for ${still}ms` };
  return { ok: false, ms, reason: lastBusy.length ? 'still loading: ' + busy : 'DOM still changing' };
}

module.exports = { BUSY, pageSettled, settle };
