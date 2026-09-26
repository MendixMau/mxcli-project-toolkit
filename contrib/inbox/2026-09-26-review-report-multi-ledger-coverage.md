# `review-report.js` cannot read multi-ledger coverage — every one-ledger-per-BRD module reports a coverage FAULT over a clean count

**From:** card-disbursement requirements-driven build (build-plan rows 4.8 and 5.7)
**Date:** 2026-09-26
**Kind:** bug
**Field evidence:** `bin/verify-module.sh <Module>` on two modules that keep one ledger per BRD
(`architecture/modules/<Module>/coverage-ledger/<BRD>.md`). In both runs the coverage rung itself
passed (`coverage … ✓ clean`), and `.claude/loop/review/<Module>/coverage.txt` read verbatim:

```
F002-system-availability-check: CLEAN —  CLAIMED: 289 LEDGERED: 48 UNCLAIMED: 0 PHANTOM: 0 DOUBLE-CLAIMED:0 COUNT-MISMATCH:0 

1 BRD(s) checked.
All clean.
```

Yet `review-report.json` carried `fault · review/coverage/<module>` — "coverage-check wrote output
but no total/claimed/unclaimed/phantom/doubleClaimed count could be read from it".
**Proposed target:** `project-tests/e2e/review-report.js` (the counter parser) and
`project-bin/coverage-check-all.sh` (the line it emits)

---

Two formats, one reader:

- In single-ledger mode `review-module.sh` runs `coverage-check.sh --summary`, which prints one
  counter per line (`  leaves:        N`, `  CLAIMED:       N`, …). `review-report.js` parses
  exactly that: regexes anchored at line start, `leaves:` included.
- In multi-ledger mode (added 2026-09-02) it runs `coverage-check-all.sh`, which greps the
  counter lines, **drops `leaves:`** (its pattern is `CLAIMED|LEDGERED|UNCLAIMED|…`), and flattens
  them onto one `<BRD>: CLEAN — …` line per BRD. No anchored regex matches, so every
  counter reads null, and the report says "unmeasured".

The fail-safe did its job, because an unreadable counter is reported as a fault, never as a zero.
But the fault is permanent on every multi-ledger module, so a reader learns to skip the row. That
is the false-red cousin of the false green the counter guard exists for.

Suggested fix:
1. In `coverage-check-all.sh`, keep `leaves:` in the grep, so each BRD line carries its total.
2. In `review-report.js`, when the file has `^<id>: (CLEAN|FINDINGS) — …` lines, sum each counter
   across them, and FAULT if any BRD line reads `FAULT` or lacks a counter. Keep the
   single-BRD branch as it is.
3. Fixture: the capture above as golden input (a real two-BRD capture would be better), with
   asserted sums. It should be red on the current parser.
