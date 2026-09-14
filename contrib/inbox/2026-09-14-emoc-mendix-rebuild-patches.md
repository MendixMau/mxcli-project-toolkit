**From:** emoc-mendix-rebuild
**Date:** 2026-09-14
**Kind:** fix
**Field evidence:** installed toolkit scripts in emoc-mendix-rebuild/bin that differ from the shipped copy — a local patch here is a fix that never traveled (how graph-sweep's stat bug got patched twice)
**Proposed target:** see per-item notes below

---

- bin/_common.sh — STALE: identical to shipped 07d11cb (2026-08-31); fix: bin/sync-project.sh <project-root> --upgrade-bin _common.sh

- bin/build-plan-status.sh — STALE: identical to shipped 2b4ef35 (2026-08-19); fix: bin/sync-project.sh <project-root> --upgrade-bin build-plan-status.sh

- bin/check-design-portability.sh — STALE: identical to shipped e3ee6fb (2026-08-26); fix: bin/sync-project.sh <project-root> --upgrade-bin check-design-portability.sh

- bin/check-page-shell.sh — STALE: identical to shipped 02a3b62 (2026-08-31); fix: bin/sync-project.sh <project-root> --upgrade-bin check-page-shell.sh

- bin/conformance-check.sh — STALE: identical to shipped ea275ea (2026-08-20); fix: bin/sync-project.sh <project-root> --upgrade-bin conformance-check.sh

- bin/exec.sh — STALE: identical to shipped 07d11cb (2026-08-31); fix: bin/sync-project.sh <project-root> --upgrade-bin exec.sh

- bin/graph-sweep.sh — STALE: identical to shipped ad922a2 (2026-08-31); fix: bin/sync-project.sh <project-root> --upgrade-bin graph-sweep.sh

- bin/review-module.sh — STALE: identical to shipped e75c912 (2026-08-21); fix: bin/sync-project.sh <project-root> --upgrade-bin review-module.sh

- bin/snapshot-mpr.sh — STALE: identical to shipped 07d11cb (2026-08-31); fix: bin/sync-project.sh <project-root> --upgrade-bin snapshot-mpr.sh

- bin/page-fidelity.js — STALE: identical to shipped f3d7b49 (2026-09-01); fix: bin/sync-project.sh <project-root> --upgrade-bin page-fidelity.js

10 stale (one line each) · 0 local fix(es) (diffs above)
