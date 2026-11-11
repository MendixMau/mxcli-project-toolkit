'use strict';
// Exactly-once assertion keyed on an idempotency id. Node, no dependencies.
// Feed it what the receiving side recorded (rows, mock request log, DB select), one id per delivery.
//   const { countById, assertExactlyOnce } = require('./exactly-once');
//   const r = assertExactlyOnce(ids, expected);   // r.ok, r.missing, r.duplicates, r.unexpected, r.message
// ids      array of idempotency ids as seen by the receiver (repeats = redelivery that was NOT deduplicated)
// expected array of ids the sender is known to have submitted; each must appear exactly once.
//          An EMPTY expected list fails ("0 of 0" would be a vacuous green): the denominator must be real.
function countById(ids) {
  const m = new Map();
  for (const id of ids) if (id !== null && id !== undefined && id !== '') m.set(String(id), (m.get(String(id)) || 0) + 1);
  return m;
}
function assertExactlyOnce(ids, expected) {
  const seen = countById(ids), want = new Set(expected.map(String));
  const missing = [...want].filter((id) => !seen.has(id));
  const duplicates = [...seen].filter(([id, n]) => want.has(id) && n > 1).map(([id, n]) => ({ id, n }));
  const unexpected = [...seen.keys()].filter((id) => !want.has(id));
  const empty = want.size === 0;
  const ok = !empty && !missing.length && !duplicates.length && !unexpected.length;
  const message = empty ? 'FAIL: expected list is empty, nothing was asserted (0 of 0 is not a pass)' : ok ? `exactly once: ${want.size} of ${want.size}` : `missing ${missing.length}, duplicated ${duplicates.length}, unexpected ${unexpected.length}`;
  return { ok, empty, missing, duplicates, unexpected, message };
}
module.exports = { countById, assertExactlyOnce };
