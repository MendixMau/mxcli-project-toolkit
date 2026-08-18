'use strict';
// monkey.selftest.js — proves the fuzzer is reproducible and its oracle can fire.
//
//   node tests/e2e/monkey.selftest.js     # exit 0 = the net has holes of a known size
//
// No app, no Jaeger. Two claims are checked, both of which the fuzzer is worthless
// without: (1) the same seed produces the same run, or findings cannot be triaged;
// (2) the payloads survive the base64 round-trip intact, or the app is being fuzzed
// with mojibake instead of the string we think we sent — a CJK payload that arrives
// as "????" tests nothing and passes.

const O = require(__dirname + '/otel.js');

let bad = 0;
const t = (name, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  if (!ok) bad++;
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}${ok ? '' : `  got=${JSON.stringify(got)} want=${JSON.stringify(want)}`}`);
};

// ── 1. seeded RNG is deterministic and not degenerate ───────────────────────
function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6D2B79F5) >>> 0;
    let x = Math.imul(a ^ (a >>> 15), 1 | a);
    x = (x + Math.imul(x ^ (x >>> 7), 61 | x)) ^ x;
    return ((x ^ (x >>> 14)) >>> 0) / 4294967296;
  };
}
const runA = Array.from({ length: 20 }, rng(4242));
const runB = Array.from({ length: 20 }, rng(4242));
const runC = Array.from({ length: 20 }, rng(4243));
t('same seed → same sequence', runA, runB);
t('different seed → different sequence', runA.join() === runC.join(), false);
t('values stay in [0,1)', runA.every(v => v >= 0 && v < 1), true);
t('not stuck on one value', new Set(runA).size > 15, true);

// ── 2. payloads survive base64 → atob → UTF-8 exactly ───────────────────────
// This is the transform typeSafely() performs inside the page. If it is lossy, a
// CJK or emoji payload silently degrades and the test measures nothing.
const roundTrip = s => {
  const b64 = Buffer.from(s, 'utf8').toString('base64');
  const latin1 = Buffer.from(b64, 'base64').toString('latin1');   // what atob() yields
  return decodeURIComponent(escape(latin1));                       // what the page then does
};
for (const s of ['', ' ', 'A'.repeat(5000), '\u5009\u5eab\u7ba1\u7406\u30b7\u30b9\u30c6\u30e0\u8a66\u9a13\u7528\u6587\u5b57\u5217', '🧪́́́ test',
                 'abc‮def', '<img src=x onerror=alert(1)>', "'; DROP TABLE x; --",
                 '../../../../etc/passwd', '%s%n%s%n', 'a\nb\r\nc']) {
  t(`round-trip intact: ${JSON.stringify(s).slice(0, 34)}`, roundTrip(s), s);
}

// ── 3. the OTel arm of the crash oracle actually fires ──────────────────────
// The signal no UI check can produce: ERROR activity under an OK microflow.
const swallowed = [
  { start: 1, op: 'mf',  tags: { 'mx.microflow.name': 'X.ACT_Commit', 'otel.status_code': 'OK' }, logs: [] },
  { start: 2, op: 'act', tags: { 'mx.activity.name': 'CallRest', 'otel.status_code': 'ERROR',
                                 'otel.status_description': 'Error calling REST service\n  at X.ACT_Commit (CallRest)' }, logs: [] },
];
t('oracle sees swallowed activity error', O.errorSpans(swallowed).length, 1);
t('oracle stays quiet on a clean capture', O.errorSpans([swallowed[0]]).length, 0);
t('oracle finds NOTHING in an empty capture (hence the traceRan flag)', O.errorSpans([]).length, 0);

process.exit(bad ? 1 : 0);
