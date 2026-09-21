---
name: Bug
about: A reproducible defect in a script, skill, or pipeline
title: "[bug] "
labels: kind/bug, lane/direct, needs/triage
---

<!-- docs/RELEASE-PROCESS.md lane 3 (Issue). No client data: no client/vendor/person names,
     codenames, internal hosts, or real local paths anywhere below — see CLAUDE.md's leak-guard
     rule. Redact the real project name to a role ("the migration project") if you need it. -->

**What broke:**

**Command / script run (exact invocation):**

**Expected vs. actual:**

**Field evidence** — which real project this was hit on, and what it produced there
(CLAUDE.md → "Shipping an instrument", rule 4 — required before this can grade above
`needs-changes` on the triage rubric in `docs/RELEASE-PROCESS.md` §2):

**Golden input, if this is a parser/instrument bug** — a verbatim capture of the real output that
tripped it (`tests/wave2/fixtures/`-shaped, never hand-written) — attach or link:
