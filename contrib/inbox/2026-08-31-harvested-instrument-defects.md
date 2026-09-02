# Instrument defects harvested from a PLM-workflow migration project (2 open items)

**From:** a PLM-workflow migration project (harvest run 2026-08-31; project referred to descriptively per the bug-log provenance convention)
**Date:** 2026-08-31 (triaged and slimmed 2026-08-31 — see disposition note below)
**Kind:** bug
**Field evidence:** each item is a confirmed finding from that project's own bug log, hit repeatedly in real sessions — verbatim impact notes below.
**Proposed target:** `project-bin/test-stack-up.sh`, `project-tests/e2e/design-audit.js`
**Why still queued, not promoted:** both fixes touch blocking/gated instruments and so owe
the full field-proof bar (captured golden input, one cited field run) — this triage session
has no field environment with a running local app or a populated page-scope to prove them
against. Promote from a session on a real project.

**Disposition of the original 4 items (2026-08-31 triage):** the harvest listed four.
Item "exec.sh mxbuild auto-detection assumes a macOS Studio Pro install" is fixed in the
current tree — `find_mxbuild`/`find_java` in `project-bin/_common.sh` now probe the
`~/.mxcli/mxbuild/<version>/` standalone-toolchain cache after Studio Pro, and `exec.sh`'s
gate-skipped branch warns loudly. Item "design-audit.js always exits 0" is fixed —
`main()` now sets `process.exitCode` 2 on faults, 1 on failures, from the tally. The two
items below remain open.

---

### 1. `project-bin/test-stack-up.sh` — false negative on mxcli-local (non-docker) ownership
**Found:** repeatedly, on every e2e/journey/monkey/verify-module invocation in that project.
The app-ownership auto-detection does not recognize an app started via `./mxcli run --local`
as owned by the current session, and refuses with "REFUSING TO RUN — app ownership is
unverified" unless `ALLOW_UNVERIFIED_APP=1` is passed.
**Impact:** the env var has to be bolted onto every single e2e invocation, forever, on any
project using local run mode — load-bearing tribal knowledge written down nowhere in the
toolkit.
**Suggested fix:** teach the detector the mxcli-local signals (`runtimelauncher.jar` process
+ the port mxcli just published — the same signal `test-stack-up.sh --check` already
resolves), or allow a project-level config default instead of a per-invocation env var.
**Triage note (2026-08-31):** confirmed still open — current ownership detection is
docker-compose-only (`find_app_port`); no runtimelauncher.jar / mxcli-local signal exists.

### 2. `project-tests/e2e/design-audit.js` — single shared default output path, no `--module`
**Found:** 2026-08-20, while scoping wiring it into `verify-module.sh`.
Without `--out` it always writes `tests/e2e/artifacts/design-audit.json`, and its page list
comes from one fixed `.claude/loop/page-scope.json` rather than a `--module` argument. Two
sequential or concurrent per-module invocations clobber each other unless the caller
remembers `--out` and hand-curates the scope file.
**Suggested fix:** accept `--module <Name>`: derive the output path as
`design-audit-<Module>.json` when `--out` is omitted, and filter `page-scope.json` to that
module. This makes design-audit safe as a per-module loop rung (the exit-code half of that
pairing has since shipped).
**Triage note (2026-08-31):** confirmed still open — current option parsing has only
staticOnly/positiveControl/page/out; the output path and scope file are fixed.
