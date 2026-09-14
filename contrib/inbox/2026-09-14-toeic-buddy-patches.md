**From:** toeic-buddy
**Date:** 2026-09-14
**Kind:** fix
**Field evidence:** installed toolkit scripts in toeic-buddy/bin that differ from the shipped copy — a local patch here is a fix that never traveled (how graph-sweep's stat bug got patched twice)
**Proposed target:** see per-item notes below

---

- bin/_common.sh — STALE: identical to shipped f0c775e (2026-08-19); fix: bin/sync-project.sh <project-root> --upgrade-bin _common.sh

- bin/build-plan-status.sh — STALE: identical to shipped 2b4ef35 (2026-08-19); fix: bin/sync-project.sh <project-root> --upgrade-bin build-plan-status.sh

- bin/coherence-cadence.sh — STALE: identical to shipped e75c912 (2026-08-21); fix: bin/sync-project.sh <project-root> --upgrade-bin coherence-cadence.sh

- bin/conformance-check.sh — STALE: identical to shipped ea275ea (2026-08-20); fix: bin/sync-project.sh <project-root> --upgrade-bin conformance-check.sh

- bin/exec.sh — STALE: identical to shipped ea275ea (2026-08-20); fix: bin/sync-project.sh <project-root> --upgrade-bin exec.sh

- bin/fixture-manifest.sh — STALE: identical to shipped 6e04418 (2026-08-18); fix: bin/sync-project.sh <project-root> --upgrade-bin fixture-manifest.sh

- bin/graph-sweep.sh — STALE: identical to shipped bf938bd (2026-08-19); fix: bin/sync-project.sh <project-root> --upgrade-bin graph-sweep.sh

- bin/page-scope.sh — STALE: identical to shipped 078c7d8 (2026-08-22); fix: bin/sync-project.sh <project-root> --upgrade-bin page-scope.sh

- bin/restore-mpr.sh — STALE: identical to shipped d33d23f (2026-08-04); fix: bin/sync-project.sh <project-root> --upgrade-bin restore-mpr.sh

- bin/review-module.sh — STALE: identical to shipped e75c912 (2026-08-21); fix: bin/sync-project.sh <project-root> --upgrade-bin review-module.sh

- bin/snapshot-mpr.sh — STALE: identical to shipped d33d23f (2026-08-04); fix: bin/sync-project.sh <project-root> --upgrade-bin snapshot-mpr.sh

- bin/verify-module.sh — STALE: identical to shipped 8923525 (2026-08-22); fix: bin/sync-project.sh <project-root> --upgrade-bin verify-module.sh

12 stale (one line each) · 0 local fix(es) (diffs above)
