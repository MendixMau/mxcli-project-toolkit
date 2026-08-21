# TOMBSTONED — falsification trial failed

This skill was self-declared **UNPROVEN**, personal-toolkit-only, and was never reachable from
README.md's routing tables or `conversion-runbook.md`. Its own closing section specified a
falsification trial and a gate: *"fail 2 or 4 and drop this."* The trial was run.

**2a — does the L1 spine reconcile against an existing target?** INVALID on every pairing tried:
the target carried no L1 step id, so the instrument could not decide whether steps corresponded.
**2b — does an L2/L3-bound source compile losslessly to a runnable target?** UNTESTED — no source
ever reached an L2/L3 layer, so there was nothing to compile from. Neither question passed.

This is **quarantined-and-failed, not quarantined-and-superseded**: the ideas here did not
graduate into `module-review.md`, `journey-proof.md`, or anywhere else. Do not cite this file in
a gate, a runbook stage, or a module brief, and do not restore its status to active on the
strength of a hunch — a different trial with different sources would need to re-run 2a and 2b,
not assume the schema was fine.

For proven journey/E2E testing guidance, see `journey-proof.md` (rungs, mutants, verdict
discipline) and `testing-shape.md` (routing). Kept short rather than deleted, per this repo's
tombstone convention (`ui-review-loop.md`); full history is in git if the trial is ever rerun.
