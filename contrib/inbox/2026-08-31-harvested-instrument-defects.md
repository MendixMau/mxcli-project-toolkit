# Instrument defects harvested from a PLM-workflow migration project (4 open items)

**From:** a PLM-workflow migration project (harvest run 2026-08-31; project referred to descriptively per the bug-log provenance convention)
**Date:** 2026-08-31
**Kind:** bug
**Field evidence:** each item is a confirmed finding from that project's own bug log, hit repeatedly in real sessions — verbatim impact notes below. A fifth harvested item (graph-sweep GNU/BSD stat order) was promoted straight to `project-bin/graph-sweep.sh` in this triage round and is not repeated here.
**Proposed target:** per-item notes below — `project-bin/exec.sh`, `project-bin/test-stack-up.sh`, `project-tests/e2e/design-audit.js`

---

### 1. `project-bin/exec.sh` — mxbuild auto-detection assumes a macOS Studio Pro install
**Found:** 2026-08-19, executing a hotfix MDL script on a Linux sandbox.
The post-write gate tries to auto-locate `mxbuild`/`java` and fails with
`ERROR: no 'Mendix Studio Pro *.app' in /Applications` / `mxbuild or java not found — GATE
SKIPPED`, even though a working mxbuild sits at `~/.mxcli/mxbuild/{version}/modeler/mx`
(the path mxcli's own docs use). The gate silently downgrades to skipped.
**Impact:** every `exec.sh` run on that sandbox executed MDL against the live `.mpr` with
**no automatic build gate**; the operator had to remember a manual `mx check` afterward,
every time. Caught only because someone did.
**Suggested fix:** probe `~/.mxcli/mxbuild/*/modeler/mx` (and `$MXTK_ROOT`/project-local
installs) before the macOS-app-bundle lookup. Treat "gate skipped" as a loud warning
requiring an explicit `--allow-unverified` flag, not a silent default.

### 2. `project-bin/test-stack-up.sh` — false negative on mxcli-local (non-docker) ownership
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

### 3. `project-tests/e2e/design-audit.js` — always exits 0, can't be gated on
**Found:** 2026-08-20, while scoping wiring it into `verify-module.sh`.
`main()` writes its JSON report and prints a summary but never sets the exit code from the
`fail`/`fault` tally — it exits non-zero only if the script itself crashes. A run with real
findings still exits 0.
**Impact:** a finding that ran and still reports green if gated on exit code — which is how
every other instrument in the chain is gated (`kind=gate` maps `rc=0→PASS`). This is the
false green `verify-module.sh`'s own header warns about.
**Suggested fix:** exit 1 when `tally.fail > 0`, exit 2 when `tally.fault > 0` (fault takes
precedence, matching the FAULT≠FAILED distinction the harness already enforces). This one
change is the blocker for wiring design-audit into `verify-module.sh` as a gated rung.

### 4. `project-tests/e2e/design-audit.js` — single shared default output path, no `--module`
**Found:** 2026-08-20, same investigation.
Without `--out` it always writes `tests/e2e/artifacts/design-audit.json`, and its page list
comes from one fixed `.claude/loop/page-scope.json` rather than a `--module` argument. Two
sequential or concurrent per-module invocations clobber each other unless the caller
remembers `--out` and hand-curates the scope file.
**Suggested fix:** accept `--module <Name>`: derive the output path as
`design-audit-<Module>.json` when `--out` is omitted, and filter `page-scope.json` to that
module. Together with item 3 this makes design-audit safe as a per-module loop rung.
