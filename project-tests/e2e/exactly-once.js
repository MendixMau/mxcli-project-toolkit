'use strict';
// Exactly-once assertion keyed on an idempotency id. Node, no dependencies.
// Feed it what the receiving side recorded (rows, mock request log, DB select), one id per delivery.
//   const { countById, assertExactlyOnce } = require('./exactly-once');
//   const r = assertExactlyOnce(ids, expected);   // r.ok, r.missing, r.duplicates, r.unexpected, r.message
// ids      array of idempotency ids as seen by the receiver (repeats = redelivery that was NOT deduplicated)
// expected array of ids the sender is known to have submitted; each must appear exactly once
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
  const ok = !missing.length && !duplicates.length && !unexpected.length;
  const message = ok ? `exactly once: ${want.size} of ${want.size}` : `missing ${missing.length}, duplicated ${duplicates.length}, unexpected ${unexpected.length}`;
  return { ok, missing, duplicates, unexpected, message };
}
module.exports = { countById, assertExactlyOnce };
