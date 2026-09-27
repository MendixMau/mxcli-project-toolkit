# Story acceptance invariant (1-to-1) silently downgraded to 1-* with no gate

**Source:** marketplace-rnd guest-groups (`story-test-results.json`). **Status:** unreviewed.

The story said one guest group per app (1-1). mxcli could not set owner Both cross-module, so the
build fell back to a 1-* association plus a convention. That downgrade was never put to the PO;
the test run recorded it only as a DB invariant. Nothing in the chain compares the story's
cardinality/invariants against the built model.

Proposed: a module-review / story-test step that lists each story invariant and marks it
ENFORCED (model), CONVENTION (code only — needs a register line `ASSUMED`/`CONFIRMED`) or
MISSING. A tooling-forced downgrade is a gate question, not a comment.
