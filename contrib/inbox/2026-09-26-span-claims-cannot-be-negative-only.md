# journey-runner rung 2: a span claim cannot be purely negative

**From:** card-disbursement requirements-driven build (build-plan row 3.9)
**Date:** 2026-09-26
**Kind:** learning
**Field evidence:** writing span claims for a 9-step admin-console journey; rung 2's guard at `project-tests/e2e/journey-runner.js` ~l.697 is `if (step.spans && step.spans.ordered && step.spans.ordered.length)`.
**Proposed target:** `project-tests/e2e/journey-runner.js` rung 2; `skills/testing-shape.md` (claim shapes)

---

`mustNotFire` is honoured only next to a non-empty `ordered` list. A step whose whole proof is
"this did NOT run" cannot say so:

- the step: Cancel on a "Reset all mock state?" confirmation. The correct outcome is that the
  reset action microflow never fires — no microflow fires at all.
- `spans: { ordered: [], mustNotFire: ["ACT_Mock_Reset"] }` is silently skipped (rung 2 does
  not run), so the claim reads as declared and proves nothing.

The project left that step without a span claim; its data rung (rows unchanged) carries the proof.

Suggested shape: run rung 2 when `ordered` OR `mustNotFire` is non-empty; for a negative-only
claim, wait the normal capture window (there is nothing to `until` on), then assert no match.
A positive-control mutant for it would inject the forbidden name into the captured list. Also
worth a loud INVALID when a step declares `spans` that rung 2 will not evaluate, instead of the
silent skip.
