**From:** T-WF-migration
**Date:** 2026-09-14
**Kind:** fix
**Field evidence:** installed toolkit scripts in T-WF-migration/bin that differ from the shipped copy — a local patch here is a fix that never traveled (how graph-sweep's stat bug got patched twice)
**Proposed target:** see per-item notes below

---

- bin/_common.sh — STALE: identical to shipped 07d11cb (2026-08-31); fix: bin/sync-project.sh <project-root> --upgrade-bin _common.sh

- bin/build-plan-status.sh — STALE: identical to shipped 2b4ef35 (2026-08-19); fix: bin/sync-project.sh <project-root> --upgrade-bin build-plan-status.sh

- bin/check-design-portability.sh — STALE: identical to shipped e3ee6fb (2026-08-26); fix: bin/sync-project.sh <project-root> --upgrade-bin check-design-portability.sh

- bin/check-page-shell.sh — STALE: identical to shipped 02a3b62 (2026-08-31); fix: bin/sync-project.sh <project-root> --upgrade-bin check-page-shell.sh

## bin/conformance-check.sh differs from shipped project-bin/conformance-check.sh — LOCAL-FIX

Not byte-identical to any shipped version in toolkit history — a real local fix. Closest historical base: 1d91513 (2026-09-07), 8 diff line(s) from this project's copy. Diff (shipped -> project), truncated at 120 lines:

```diff
--- shipped/project-bin/conformance-check.sh
+++ project/bin/conformance-check.sh
@@ -216,13 +216,13 @@
   tmp="$(mktemp)"
   "$MXCLI" -p "$MPR" -c "$cmd" >"$tmp" 2>&1 </dev/null &
   pid=$!
-  # THE WATCHDOG POLLS INSTEAD OF SLEEPING ONCE (fixed 2026-09-02, found on a workflow-migration project).
+  # THE WATCHDOG POLLS INSTEAD OF SLEEPING ONCE (fixed 2026-09-02, found on t-wf-migration).
   # It used to be `( sleep "$TIMEOUT_S"; kill -9 "$pid" )`, cancelled afterwards with
   # `kill "$killer"; wait "$killer"`. That cancellation does not work: a bash subshell blocked
   # inside `sleep` does not act on SIGTERM until the sleep RETURNS, so `wait "$killer"` sat for
   # the whole timeout window on EVERY probe -- whatever the command did, however fast.
   #
-  # Field measurement (a workflow-migration project, 61-row ledger, 30 measurable rows): each mxcli DESCRIBE
+  # Field measurement (t-wf-migration, 61-row ledger, 30 measurable rows): each mxcli DESCRIBE
   # took 0.144s and each probe took 24s with TIMEOUT_S=25. Conformance needed ~12 minutes to do
   # ~5 seconds of work and was killed by every reasonable outer timeout before it printed a
   # verdict. The instrument looked hung; it was only ever waiting on its own guard. Nobody had
```

## bin/coverage-check-all.sh differs from shipped project-bin/coverage-check-all.sh — LOCAL-FIX

Not byte-identical to any shipped version in toolkit history — a real local fix. Closest historical base: 1d91513 (2026-09-07), 34 diff line(s) from this project's copy. Diff (shipped -> project), truncated at 120 lines:

```diff
--- shipped/project-bin/coverage-check-all.sh
+++ project/bin/coverage-check-all.sh
@@ -3,7 +3,7 @@
 # exit clean only when every one is.
 #
 # WHY THIS EXISTS. coverage-check.sh measures exactly one (BRD, ledger) pair per invocation.
-# A module with several BRDs — real on a workflow-migration project, five of them — either measures one and
+# A module with several BRDs — real on t-wf-migration, five of them — either measures one and
 # silently reports it as the module's coverage, or needs a human to remember to run it N times.
 # review-module.sh's own denominator fix (2026-09-02) stopped the FIRST failure mode by stating
 # "coverage · 1 of 5 BRDs" instead of staying silent about the other four. This script is the
@@ -16,25 +16,21 @@
 # this at all — the single-file convention (coverage-ledger.md, coverage-check.sh directly) is
 # simpler and stays correct.
 #
-# Usage: coverage-check-all.sh <ledger-dir> <brd-path-or-glob>...
+# Usage: coverage-check-all.sh <ledger-dir> <brd-glob>
 #   coverage-check-all.sh architecture/modules/DashboardPublishing/coverage-ledger \
 #                         'analysis/*/knowledge-base/brd/*.brd.json'
-#   coverage-check-all.sh <ledger-dir> analysis/x/brd/F001.brd.json analysis/x/brd/F003.brd.json
-# review-module.sh passes the explicit list the module's ledgers name — a glob over a BRD
-# directory shared by several modules would demand ledgers here for the other modules' BRDs.
 #
 # Exit 0: every BRD clean. Exit 1: at least one has findings (UNCLAIMED/PHANTOM/etc). Exit 2:
 # a BRD has no matching ledger file, or coverage-check.sh itself is not reachable.
 set -uo pipefail
 
-LEDGER_DIR="${1:?usage: coverage-check-all.sh <ledger-dir> <brd-path-or-glob>...}"
-shift
-[ "$#" -ge 1 ] || { echo "usage: coverage-check-all.sh <ledger-dir> <brd-path-or-glob>..." >&2; exit 2; }
+LEDGER_DIR="${1:?usage: coverage-check-all.sh <ledger-dir> <brd-glob>}"
+BRD_GLOB="${2:?usage: coverage-check-all.sh <ledger-dir> <brd-glob>}"
 
 # Same resolution order review-module.sh's own _tool() uses: beside this script (the
 # installed-in-project-bin case), then $MXTK_ROOT/bin (coverage-check.sh lives in the
 # toolkit's bin/, not project-bin/, on a project that only installed project-bin/ scripts --
-# exactly a workflow-migration project's layout, which is what caught this), then PATH.
+# exactly t-wf-migration's layout, which is what caught this), then PATH.
 COV="$(dirname "${BASH_SOURCE[0]}")/coverage-check.sh"
 [ -x "$COV" ] || COV="${MXTK_ROOT:-}/bin/coverage-check.sh"
 [ -x "$COV" ] || COV="${MXTK_ROOT:-}/project-bin/coverage-check.sh"
@@ -45,13 +41,10 @@
 fi
 
 shopt -s nullglob
-brds=()
-for arg in "$@"; do
-  for f in $arg; do brds+=("$f"); done      # each argument is a path or a glob
-done
+brds=($BRD_GLOB)
 shopt -u nullglob
 if [ "${#brds[@]}" -eq 0 ]; then
-  echo "coverage-check-all: no BRDs matched: $*" >&2
+  echo "coverage-check-all: no BRDs matched $BRD_GLOB" >&2
   exit 2
 fi
 
```

- bin/exec.sh — STALE: identical to shipped 07d11cb (2026-08-31); fix: bin/sync-project.sh <project-root> --upgrade-bin exec.sh

## bin/graph-sweep.sh differs from shipped project-bin/graph-sweep.sh — LOCAL-FIX

Not byte-identical to any shipped version in toolkit history — a real local fix. Closest historical base: 1d91513 (2026-09-07), 4 diff line(s) from this project's copy. Diff (shipped -> project), truncated at 120 lines:

```diff
--- shipped/project-bin/graph-sweep.sh
+++ project/bin/graph-sweep.sh
@@ -40,7 +40,7 @@
 # that is the project root and the old hardcoded ".mxcli/catalog.db" was right; on a TWO-TREE
 # checkout, where the model sits under app/, the catalog lands in app/.mxcli/ and this script
 # reported "catalog.db not found -- run REFRESH CATALOG" at a project that had just run exactly
-# that. Found on a workflow-migration project, where the operator's fix was a hand-made symlink.
+# that. Found on t-wf-migration, where the operator's fix was a hand-made symlink.
 #
 # This is the third time the same both-layouts assumption has been shipped in this directory
 # (F-020, F-042, now this one), which is why field-proof rule 2 says to probe BOTH layouts
```

## bin/review-module.sh differs from shipped project-bin/review-module.sh — LOCAL-FIX

Not byte-identical to any shipped version in toolkit history — a real local fix. Closest historical base: 1d91513 (2026-09-07), 34 diff line(s) from this project's copy. Diff (shipped -> project), truncated at 120 lines:

```diff
--- shipped/project-bin/review-module.sh
+++ project/bin/review-module.sh
@@ -374,7 +374,7 @@
   # ALL the BRDs the ledger names, not just the first — and the COUNT is reported, because
   # coverage-check.sh measures one BRD per run and a module with five of them was silently
   # having one fifth of its requirements measured and printed as the module's coverage
-  # (a workflow-migration project, 2026-09-02: five BRDs, F001 measured, F002-F005 never looked at, output
+  # (t-wf-migration, 2026-09-02: five BRDs, F001 measured, F002-F005 never looked at, output
   # indistinguishable from full coverage). That is the exact shape of false green this repo's
   # own rule against unstated denominators exists to prevent.
   #
@@ -404,7 +404,7 @@
     "the ledger names no reachable *.brd.json" \
     "Refusing to substitute another module's BRD — that would report its leaves as this module's."
 else
-  # MULTI-LEDGER MODE (added 2026-09-02, field-proven on a workflow-migration project's five BRDs going
+  # MULTI-LEDGER MODE (added 2026-09-02, field-proven on t-wf-migration's five BRDs going
   # from "coverage · 1 of 5 BRDs" to all five clean). A module split one-ledger-per-BRD keeps
   # its files at architecture/modules/<Module>/coverage-ledger/<BRDID>.md — a DIRECTORY beside
   # where the single-file convention would put coverage-ledger.md, named after that same base.
@@ -415,25 +415,16 @@
   LEDGER_DIR="$(dirname "$LEDGER")/coverage-ledger"
   if [ -d "$LEDGER_DIR" ]; then
     ALL="$(_tool coverage-check-all.sh)"
-    # Pass the BRDs THIS ledger set names, not a glob over the BRD directory: on a
-    # multi-module project every module's BRDs share analysis/.../brd/, so a directory glob
-    # would demand a ledger here for other modules' BRDs and FAULT on each (merge review,
-    # 2026-09-07; the field run was a single-module project where the two sets coincide).
-    BRD_ARGS=""
-    while IFS= read -r c; do
-      [ -n "$c" ] && BRD_ARGS="$BRD_ARGS $ROOT/$c"
-    done <<EOF2
-$BRD_ALL
-EOF2
-    run "coverage (BRD leaves: UNCLAIMED/PHANTOM/DOUBLE · all $BRD_N BRDs, one ledger each)" coverage \
+    BRD_GLOB="$(dirname "$BRD")/*.brd.json"
+    run "coverage (BRD leaves: UNCLAIMED/PHANTOM/DOUBLE · all BRDs, one ledger each)" coverage \
       "$OUTDIR/coverage.txt" gate 300 -- \
-      "$ALL" "$LEDGER_DIR" $BRD_ARGS
+      "$ALL" "$LEDGER_DIR" "$BRD_GLOB"
   else
     if [ "${BRD_N:-1}" -gt 1 ]; then
       printf '  \033[33m! coverage measures ONE BRD per run; this ledger names %s\033[0m\n' "$BRD_N"
       printf '    measuring %s — the other %s are NOT covered by this verdict.\n' \
         "$BRD_REL" "$((BRD_N - 1))"
-      printf '    Run coverage-check.sh per BRD, or split the ledger one-per-BRD (a worked example exists on a workflow-migration project).\n'
+      printf '    Run coverage-check.sh per BRD, or split the ledger one-per-BRD (see t-wf-migration for a worked example).\n'
     fi
     run "coverage (BRD leaves: UNCLAIMED/PHANTOM/DOUBLE${BRD_N:+ · 1 of $BRD_N BRDs})" coverage \
       "$OUTDIR/coverage.txt" gate 300 -- \
@@ -441,6 +432,8 @@
   fi
 fi
 
+# ── 4. Journeysfi
+
 # ── 4. Journeys: NOT run here, and the report must say so ───────────────────
 # Stated in the terminal as well as the report, because a reader who sees three clean
 # model instruments and no mention of the app will supply the wrong conclusion.
```

- bin/snapshot-mpr.sh — STALE: identical to shipped 07d11cb (2026-08-31); fix: bin/sync-project.sh <project-root> --upgrade-bin snapshot-mpr.sh

- bin/page-fidelity.js — STALE: identical to shipped 02a3b62 (2026-08-31); fix: bin/sync-project.sh <project-root> --upgrade-bin page-fidelity.js

7 stale (one line each) · 4 local fix(es) (diffs above)
