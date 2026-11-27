**From:** MendixUseCaseDiscovery
**Date:** 2026-11-19
**Kind:** fix
**Field evidence:** installed toolkit scripts in MendixUseCaseDiscovery/bin that differ from the shipped copy — a local patch here is a fix that never traveled (how graph-sweep's stat bug got patched twice)
**Proposed target:** see per-item notes below

---

- bin/_common.sh — STALE: identical to shipped 6f4d0527 (2026-11-15); fix: bin/sync-project.sh <project-root> --only-bin _common.sh --upgrade-bin _common.sh

- bin/exec.sh — STALE: identical to shipped cd70dd7a (2026-11-17); fix: bin/sync-project.sh <project-root> --only-bin exec.sh --upgrade-bin exec.sh

- bin/test-stack-up.sh — STALE: identical to shipped a692a59f (2026-11-13); fix: bin/sync-project.sh <project-root> --only-bin test-stack-up.sh --upgrade-bin test-stack-up.sh

3 stale (one line each) · 0 local fix(es) (diffs above)
