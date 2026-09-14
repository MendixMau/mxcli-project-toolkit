**From:** PlantOps
**Date:** 2026-09-14
**Kind:** fix
**Field evidence:** installed toolkit scripts in PlantOps/bin that differ from the shipped copy — a local patch here is a fix that never traveled (how graph-sweep's stat bug got patched twice)
**Proposed target:** see per-item notes below

---

## bin/check-root-clean.sh differs from shipped project-bin/check-root-clean.sh — LOCAL-FIX

Not byte-identical to any shipped version in toolkit history — a real local fix. Closest historical base: 512fc57 (2026-08-18), 43 diff line(s) from this project's copy. Diff (shipped -> project), truncated at 120 lines:

```diff
--- shipped/project-bin/check-root-clean.sh
+++ project/bin/check-root-clean.sh
@@ -1,31 +1,18 @@
 #!/usr/bin/env bash
 # check-root-clean.sh — fail if stray .md/.html appear in the project root.
 #
-# WHY THIS EXISTS. Working artifacts belong in docs/ analysis/ architecture/ design/ bug-logs/.
-# The root is reserved for the handful of files tools open by exact path. Agents scatter files
-# into the root by default — it is the working directory, so it is the path of least resistance —
-# and once a report lands there nobody moves it. This is the backstop. Run it from the gate or a
-# pre-commit hook.
-#
-# Usage:
-#   bin/check-root-clean.sh              # check the project root
-#   ROOT_ALLOWED="A.md B.md" bin/...     # override the allowlist wholesale
-#   ROOT_ALLOWED_EXTRA="NOTES.md" bin/.. # add to it (the normal case)
-#
-# Exit: 0 clean · 1 strays found
-
-set -u
-PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
-cd "$PROJECT_ROOT" || { echo "cannot cd to project root" >&2; exit 1; }
-
-# index.html is allowed because bin/gate-check.sh regenerates it at the project root on every run,
-# by design. Two scripts disagreed once: gate-check wrote it, this script failed on it. Allowlisting
-# is the pragmatic resolution — it is gitignored, so it never lands in a commit.
-#
-# AGENTS.md is allowed as a POINTER to CLAUDE.md, never as a copy: two copies of the instructions
-# drift, and the one the agent reads is whichever its harness happens to prefer.
-ALLOWED="${ROOT_ALLOWED:-AGENTS.md CLAUDE.md CLAUDE.local.md PROJECT.md README.md index.html} ${ROOT_ALLOWED_EXTRA:-}"
+# Working artifacts belong in docs/ analysis/ architecture/ design/ bug-logs/.
+# The root is reserved for files tools read by exact path. Agents scatter files
+# by default; this is the backstop. Run it from the gate or a pre-commit hook.
+set -e
+cd "$(dirname "$0")/.."
 
+# index.html is allowed because the toolkit's own bin/gate-check.sh regenerates it at the
+# project root on every run, by design. Two toolkit scripts disagreed: gate-check writes it,
+# this script failed on it. Allowlisting is the pragmatic resolution — it is gitignored so it
+# never lands in a commit. Note DEMO-PLAN.md lists root index.html under "do not open":
+# it is a mostly-FAIL dashboard and reads badly on a projector.
+ALLOWED="AGENTS.md CLAUDE.md CLAUDE.local.md PROJECT.md README.md index.html"
 STRAY=""
 for f in *.md *.html; do
   [ -e "$f" ] || continue
@@ -46,8 +33,7 @@
   echo "    design/          wireframes, design system"
   echo "    bug-logs/        confirmed tool bugs"
   echo ""
-  echo "  Use 'git mv' so history follows, and fix any cross-references —"
-  echo "  several of these documents cite each other by path."
+  echo "  Use 'git mv' so history follows, and fix any cross-references."
   exit 1
 fi
 
```

- bin/check-sp-health.sh — STALE: identical to shipped ffff50e (2026-08-04); fix: bin/sync-project.sh <project-root> --upgrade-bin check-sp-health.sh

## bin/conformance-check.sh differs from shipped project-bin/conformance-check.sh — LOCAL-FIX

Not byte-identical to any shipped version in toolkit history — a real local fix. Closest historical base: 239af75 (2026-08-19), 10 diff line(s) from this project's copy. Diff (shipped -> project), truncated at 120 lines:

```diff
--- shipped/project-bin/conformance-check.sh
+++ project/bin/conformance-check.sh
@@ -16,36 +16,17 @@
 # fails the run. Pre-existing mismatches are reported but do not fail — the lesson from lint,
 # which was made optional because day-one noise made it unusable, and now never runs at all.
 #
-# When there is no ledger
-#
-# A missing ledger used to be a hard FAULT, and the same FAULT was printed in two opposite
-# situations: an existing-app audit that was never going to have one, and a migration project
-# that should have one and doesn't. Both read identically, so an operator could not tell
-# permanent noise from a real gap. This script now defers that judgement to
-# `coverage-preflight.sh --assess`, which grades it into four levels on WHAT IS PRESENT (BRDs,
-# build-plan `claims`) rather than on a declared entry mode. See that script's header for the
-# levels and process/improvement-plan-e2e-reporting.md Finding 3 for the incident.
-#
-# Nothing here blocks that did not block before, and no exit code got more severe: a missing
-# ledger now exits 3 (NOT MEASURED) or 4 (NOT APPLICABLE) instead of 2 (FAULT).
-#
-# Ledger path shapes, all read, first is canonical:
-#   architecture/modules/<Module>/coverage-ledger.md   canonical (per-module)
-#   architecture/modules/<Module>-coverage-ledger.md   flat module layout
-#   architecture/coverage-ledger.md                    single-BRD project
-#
 # Usage:
 #   bin/conformance-check.sh [--module <Name>] [--update-baseline] [--quiet]
 #
 # Exit: 0 clean or baseline written · 1 regression · 2 instrument fault (refuses to guess)
-#       3 NOT MEASURED (no ledger, but a spec exists) · 4 NOT APPLICABLE (no spec at all)
 
 set -uo pipefail
 
-. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
-cd "$PROJECT_ROOT" || exit 2
+ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
+cd "$ROOT" || exit 2
 
-MPR="$(find_mpr)" || exit 2
+MPR="WMS-Demo.mpr"
 MXCLI="./mxcli"
 OUTDIR="docs/conformance"
 BASELINE="$OUTDIR/baseline.tsv"
@@ -58,7 +39,7 @@
     --module)          MODULE="${2:-}"; shift 2 ;;
     --update-baseline) UPDATE_BASELINE=1; shift ;;
     --quiet)           QUIET=1; shift ;;
-    -h|--help)         sed -n '2,43p' "$0"; exit 0 ;;
+    -h|--help)         sed -n '2,26p' "$0"; exit 0 ;;
     *) echo "unknown argument: $1" >&2; exit 2 ;;
   esac
 done
@@ -67,102 +48,20 @@
 [ -f "$MPR" ]   || { echo "FAULT: $MPR not found" >&2; exit 2; }
 mkdir -p "$OUTDIR"
 
-# --- find the ledger(s) ------------------------------------------------------------------
-# Three path shapes are in the wild and all three are legitimate. The canonical one is the
-# per-module directory; the flat one exists because real projects lay architecture/modules/ out
-# flat (PROJECT-A: `Approval-brief.md`, `ProductNumbers.md`, no subdirectories at all); the
-# project-level one is sanctioned by skills/coverage-ledger.md's own header for a single-BRD
-# project. Globbing only the canonical shape is why a project with ledgers in the flat shape
-# would still be told it had none.
-#
-# LEDGER_COUNT is tracked separately rather than read back as ${#LEDGERS[@]}: under `set -u`,
-# bash 3.2 (stock macOS) treats an EMPTY array as unset and aborts on that expansion — which is
-# precisely the case this block exists to handle gracefully.
-LEDGERS=()
-LEDGER_COUNT=0
 if [ -n "$MODULE" ]; then
-  for c in "${LEDGER_FILE:-}" \
-           "architecture/modules/$MODULE/coverage-ledger.md" \
-           "architecture/modules/$MODULE-coverage-ledger.md" \
-           "architecture/coverage-ledger.md"; do
-    [ -n "$c" ] && [ -f "$c" ] && { LEDGERS=("$c"); LEDGER_COUNT=1; break; }
-  done
+  LEDGERS=(architecture/modules/"$MODULE"/coverage-ledger.md)
+  [ -f "${LEDGERS[0]}" ] || { echo "FAULT: no ledger for module '$MODULE'" >&2; exit 2; }
 else
-  for c in architecture/modules/*/coverage-ledger.md \
-           architecture/modules/*-coverage-ledger.md \
-           architecture/coverage-ledger.md; do
-    if [ -f "$c" ]; then LEDGERS[$LEDGER_COUNT]="$c"; LEDGER_COUNT=$((LEDGER_COUNT+1)); fi
-  done
-fi
-
-# --- no ledger: grade the absence instead of faulting on it -------------------------------
-# The absence itself carries no information — the same missing file means "this project skipped
-# a step" and "this entry mode never had the step" — so hand the judgement to the one place that
-# grades it, rather than printing a verdict this script cannot justify.
-if [ "$LEDGER_COUNT" -eq 0 ]; then
-  echo "conformance · no coverage ledger for ${MODULE:-this project}"
-  echo ""
-  # The paths tried are printed by the assessor below, once, rather than by both scripts.
-
-  ASSESSOR=""
-  for c in "$(dirname "${BASH_SOURCE[0]}")/coverage-preflight.sh" \
-           "${MXTK_ROOT:-}/project-bin/coverage-preflight.sh"; do
-    [ -x "$c" ] && { ASSESSOR="$c"; break; }
-  done
-
-  if [ -z "$ASSESSOR" ]; then
-    echo "  coverage-preflight.sh not found or not executable — cannot evaluate what this absence" >&2
-    echo "  means, which is not a pass." >&2
-    exit 2
-  fi
-
-  if [ -n "$MODULE" ]; then "$ASSESSOR" --assess --module "$MODULE"; else "$ASSESSOR" --assess; fi
-  LEVEL_RC=$?
-
-  echo ""
-  case "$LEVEL_RC" in
-    0)  # A spec exists (level 1 says a ledger does after all, level 2 says one is derivable).
-        # Conformance still cannot run: it measures the ledger's `acceptance` commands against
-        # the live model, and a ledger derived from BRD + `claims` carries no acceptance cells.
-        # Synthesizing them would mean reading the model to decide what the requirement was,
-        # which is the reverse-derivation this whole change exists to refuse.
-        echo "  A ledger is derivable here, but a DERIVED ledger carries no \`acceptance\` cells,"
-        echo "  and conformance measures exactly those. Synthesizing acceptance commands would"
-        echo "  mean asking the model what the requirement was — the inversion this instrument"
-        echo "  refuses. Conformance for ${MODULE:-this project} is UNMEASURED, not clean."
```

## bin/coverage-check.sh differs from shipped bin/coverage-check.sh — LOCAL-FIX

Not byte-identical to any shipped version in toolkit history — a real local fix. Closest historical base: 9a53c3d (2026-08-04), 16 diff line(s) from this project's copy. Diff (shipped -> project), truncated at 120 lines:

```diff
--- shipped/bin/coverage-check.sh
+++ project/bin/coverage-check.sh
@@ -2,16 +2,10 @@
 #
 # coverage-check.sh — make BRD coverage mechanical instead of remembered.
 #
-# Flattens a BRD to one JSON Pointer per scalar leaf, extracts claimed pointers
-# from a coverage ledger (two markdown tables: BUILDABLE and NON-BUILDABLE), and
-# reports which leaves are CLAIMED, LEDGERED, UNCLAIMED, PHANTOM or
-# DOUBLE-CLAIMED.
-#
-# The ledger format and the pointer-cell grammar this script parses are defined
-# by the build-plan method, which has NOT landed in the toolkit yet (it is a
-# per-project doc today, promotion tracked as §3 of TOOLKIT-UPGRADE-PLAN.md).
-# Everything needed to run the script is documented in this header on purpose —
-# do not reintroduce a path reference to a file the toolkit does not ship.
+# Implements architecture/build-plan-method.md §4: flattens a BRD to one JSON
+# Pointer per scalar leaf, extracts claimed pointers from a coverage ledger
+# (two markdown tables: BUILDABLE and NON-BUILDABLE), and reports which
+# leaves are CLAIMED, LEDGERED, UNCLAIMED, PHANTOM or DOUBLE-CLAIMED.
 #
 # Usage: bin/coverage-check.sh [--summary] <brd.json> <ledger.md>
 #
```

## bin/exec.sh differs from shipped project-bin/exec.sh — LOCAL-FIX

Not byte-identical to any shipped version in toolkit history — a real local fix. Closest historical base: d33d23f (2026-08-04), 535 diff line(s) from this project's copy. Diff (shipped -> project), truncated at 120 lines:

```diff
--- shipped/project-bin/exec.sh
+++ project/bin/exec.sh
@@ -1,25 +1,12 @@
 #!/usr/bin/env bash
-# exec.sh — the guard chain around a model write.
-#
-#   concurrent-writer guard → module-brief advisory → mxcli check → snapshot → baseline → exec
-#   → mxbuild gate → auto-restore on regression → SP reopen
-#
-# Usage: ./bin/exec.sh <script.mdl>
-#
-# Overrides: FORCE_EXEC=1 (skip refusals), SKIP_CHECK=1 (skip the pre-exec
-#            mxcli check), SKIP_BASELINE=1 (skip pre-flight mxbuild),
-#            MXBUILD_PATH=..., MENDIX_APP=..., MPR_FILE=...
+# exec.sh — snapshot → exec → mxbuild gate → prompt for manual SP restart
 set -e
-_T0=$(date +%s)
 
-. "$(dirname "$0")/_common.sh"
+PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
+MPR="$PROJECT_ROOT/WMS-Demo.mpr"
+SCRIPT="$1"
 
-MPR="$(find_mpr)" || exit 1
-MPR_BASE="$(basename "$MPR")"
-NAME="$(basename "$MPR" .mpr)"
-SCRIPT="${1:-}"
-
-if [ -z "$SCRIPT" ]; then
+if [[ -z "$SCRIPT" ]]; then
   echo "Usage: ./bin/exec.sh <script.mdl>"
   exit 1
 fi
@@ -28,39 +15,33 @@
 
 # ── Concurrent-writer guard ──────────────────────────────────────────────────
 # The .mpr must have exactly ONE writer. Two mxcli/SP writers on the same file
-# silently clobber each other and have caused near-total module loss.
+# silently clobber each other and have caused near-total module loss (see
+# bug-logs/mxcli-bugs.md). This block refuses to run if another writer is active.
 # Override (at your own risk): FORCE_EXEC=1 ./bin/exec.sh <script>
-# The model tree (.mpr + mprcontents/) is NOT always $PROJECT_ROOT — on a two-tree
-# checkout the app lives under app/. Every mprcontents/ path below goes through
-# MODEL_DIR; see the find_model_dir header in _common.sh for what silently broke
-# when they did not.
-MODEL_DIR="$(find_model_dir 2>/dev/null || echo "$PROJECT_ROOT")"
-
 LOCK="$PROJECT_ROOT/.mpr-snapshots/.exec.lock"
 mkdir -p "$(dirname "$LOCK")"
 FORCE="${FORCE_EXEC:-0}"
 
-# 1. Studio Pro must not hold the project open (SP's in-memory model vs a direct
-#    file write = split-brain).
-if [ -f "$MPR.lock" ]; then
+# 1. Studio Pro must not have WMS-Demo open (SP in-memory model vs direct file write = split-brain).
+if [[ -f "$MPR.lock" ]]; then
   SP_PID=$(grep -oE '"ProcessId":[0-9]+' "$MPR.lock" 2>/dev/null | grep -oE '[0-9]+' || true)
-  if [ -n "$SP_PID" ] && kill -0 "$SP_PID" 2>/dev/null; then
-    echo "✗ Studio Pro has $NAME open (lock PID $SP_PID alive) — refusing exec (split-brain corruption risk)."
-    echo "  → Close the project in Studio Pro (or quit SP), then re-run."
+  if [[ -n "$SP_PID" ]] && kill -0 "$SP_PID" 2>/dev/null; then
+    echo "✗ Studio Pro has WMS-Demo open (lock PID $SP_PID alive) — refusing exec (split-brain corruption risk)."
+    echo "  → Close the PlantOps project in Studio Pro (or quit SP), then re-run this script."
     echo "    Override (NOT recommended): FORCE_EXEC=1 ./bin/exec.sh $SCRIPT"
-    [ "$FORCE" = "1" ] || exit 1
+    [[ "$FORCE" == "1" ]] || exit 1
     echo "  (FORCE_EXEC set — proceeding despite open SP)"
-  elif [ -n "$SP_PID" ]; then
-    echo "  (stale $MPR_BASE.lock from dead PID $SP_PID — SP not actually open, proceeding)"
+  elif [[ -n "$SP_PID" ]]; then
+    echo "  (stale WMS-Demo.mpr.lock from dead PID $SP_PID — SP not actually open, proceeding)"
   fi
 fi
 
-# 2. No other exec.sh run in progress (e.g. a second agent session).
-if [ -f "$LOCK" ]; then
+# 2. No other exec.sh run in progress (e.g. a second Claude session).
+if [[ -f "$LOCK" ]]; then
   OTHER=$(cat "$LOCK" 2>/dev/null || true)
-  if [ -n "$OTHER" ] && kill -0 "$OTHER" 2>/dev/null; then
+  if [[ -n "$OTHER" ]] && kill -0 "$OTHER" 2>/dev/null; then
     echo "✗ Another exec is already running (PID $OTHER) — refusing to write the .mpr concurrently."
-    echo "  → Wait for it to finish. If it is stale (process dead): rm '$LOCK'"
+    echo "  → Wait for it to finish. If it's stale (process dead): rm '$LOCK'"
     exit 1
   fi
 fi
@@ -68,541 +49,267 @@
 # 3. No stray raw `mxcli exec` from another session.
 if pgrep -fl "mxcli exec" 2>/dev/null | grep -qv "$$"; then
   echo "✗ A raw 'mxcli exec' is already running elsewhere — refusing to write concurrently."
-  [ "$FORCE" = "1" ] || exit 1
+  echo "  → Wait for it to finish, or verify no other Claude session is building."
+  [[ "$FORCE" == "1" ]] || exit 1
 fi
 
-# 4. Uncommitted model changes. The snapshot taken below would not cover them,
-#    so a failed gate would auto-restore to a state pre-dating those changes and
-#    silently lose work.
-MPR_DIRTY=$(git status --porcelain "$MPR" "$MODEL_DIR/mprcontents" 2>/dev/null | grep -v "^$" || true)
-if [ -n "$MPR_DIRTY" ]; then
-  echo "✗ Uncommitted model changes — refusing exec to prevent snapshot regression."
+# 4. Uncommitted MPR changes guard — prevents silent snapshot regression.
+#    If WMS-Demo.mpr or mprcontents/ have uncommitted changes, the snapshot this
+#    exec.sh is about to take will not cover them. A mxbuild failure would then
+#    auto-restore to a snapshot that pre-dates those MCP changes — silently losing
+#    work. Override with FORCE_EXEC=1 only if you accept the restore-regression risk.
+MPR_DIRTY=$(git status --porcelain WMS-Demo.mpr mprcontents/ 2>/dev/null | grep -v "^$" || true)
+if [[ -n "$MPR_DIRTY" ]]; then
+  echo "✗ Uncommitted MPR changes detected — refusing exec to prevent snapshot regression."
   echo ""
+  echo "  The following paths have unsaved/uncommitted changes:"
   echo "$MPR_DIRTY" | sed 's/^/    /'
   echo ""
-  echo "  → git add $MPR $MODEL_DIR/mprcontents && git commit -m 'Commit model changes before exec'"
-  echo "  Override (accepts silent-loss risk): FORCE_EXEC=1 ./bin/exec.sh $SCRIPT"
-  [ "$FORCE" = "1" ] || exit 1
-  echo "  (FORCE_EXEC set — proceeding despite uncommitted changes)"
-fi
-
```

## bin/graph-sweep.sh differs from shipped project-bin/graph-sweep.sh — LOCAL-FIX

Not byte-identical to any shipped version in toolkit history — a real local fix. Closest historical base: 239af75 (2026-08-19), 40 diff line(s) from this project's copy. Diff (shipped -> project), truncated at 120 lines:

```diff
--- shipped/project-bin/graph-sweep.sh
+++ project/bin/graph-sweep.sh
@@ -9,16 +9,6 @@
 # standard module. It compiles, it behaves identically, and the graph shows the standard
 # module with zero inbound edges.
 #
-# Relationship to `mxcli lint` QUAL004 ("Orphaned Elements"): QUAL004 answers the same
-# element-level question as this script's "orphaned microflows" finding, natively, from the
-# same catalog — prefer it when it's available (`mxcli lint`, or `mxcli report`) rather than
-# reading this script's ORPHANS query as ground truth; the exclusion lists here (entry-point
-# prefixes, RefKind set) are hand-maintained and can drift from QUAL004's. This script earns
-# its keep on the "module wiring shape" finding (aggregate inbound/outbound edges per module),
-# which is a different, coarser question than any single element's orphan status — that finding
-# has no direct mxcli-native equivalent yet (closest is `GRAPH_MODULE_COUPLING`, which is edge-
-# weighted, not this script's plain in/out counts). See `skills/process-coherence-pass.md`.
-#
 # Read-only: opens the catalog database. Never runs mxcli exec, never touches the .mpr.
 #
 # IMPORTANT — an unwired marketplace module is not a defect. Most are legitimately unused.
@@ -30,24 +20,11 @@
 
 set -uo pipefail
 
-. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
-cd "$PROJECT_ROOT" || exit 2
-
-MPR="$(find_mpr)" || exit 2
+ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
+cd "$ROOT" || exit 2
 
-# THE CATALOG LIVES BESIDE THE .mpr, NOT ALWAYS AT THE PROJECT ROOT (fixed 2026-09-02).
-# `mxcli ... REFRESH CATALOG` writes <dir-of-mpr>/.mxcli/catalog.db. On a single-tree checkout
-# that is the project root and the old hardcoded ".mxcli/catalog.db" was right; on a TWO-TREE
-# checkout, where the model sits under app/, the catalog lands in app/.mxcli/ and this script
-# reported "catalog.db not found -- run REFRESH CATALOG" at a project that had just run exactly
-# that. Found on a workflow-migration project, where the operator's fix was a hand-made symlink.
-#
-# This is the third time the same both-layouts assumption has been shipped in this directory
-# (F-020, F-042, now this one), which is why field-proof rule 2 says to probe BOTH layouts
-# before merging an instrument. Derive the path from the .mpr that find_mpr already resolved,
-# and keep the root as a fallback so a project that puts it there still works.
-DB="$(dirname "$MPR")/.mxcli/catalog.db"
-[ -f "$DB" ] || [ ! -f ".mxcli/catalog.db" ] || DB=".mxcli/catalog.db"
+DB=".mxcli/catalog.db"
+MPR="WMS-Demo.mpr"
 MODULE=""
 MIN_ELEMENTS=20
 TSV=0
@@ -70,21 +47,7 @@
 
 # --- guard 1: freshness ------------------------------------------------------------------
 CAT_MTIME="$(q "SELECT value FROM catalog_meta WHERE key='mpr_mod_time';" | cut -c1-19)"
-# `stat -c` is GNU coreutils (Linux, and Git Bash on Windows), `stat -f` is BSD/macOS.
-# GNU must be tried FIRST: on GNU, `stat -f` does not fail — it reads `-f`/`-t` as
-# filesystem-info flags and prints plausible-looking garbage, so a BSD-first chain's
-# fallback never fires and every Linux run FAULTs as "catalog is stale" against a bogus
-# mtime (found independently on two projects, 2026-08-19 and 2026-08-14). The third case
-# still matters most: if NEITHER works, MPR_MTIME is empty and the freshness guard below
-# reports "catalog is stale" against a blank mtime — a real fault reported as the wrong
-# fault. Fail on the read instead of comparing against nothing.
-MPR_MTIME="$(stat -c "%y" "$MPR" 2>/dev/null | cut -c1-19 | tr ' ' 'T')"
-[ -n "$MPR_MTIME" ] || MPR_MTIME="$(stat -f "%Sm" -t "%Y-%m-%dT%H:%M:%S" "$MPR" 2>/dev/null)"
-[ -n "$MPR_MTIME" ] || {
-  echo "FAULT: cannot read the modification time of $MPR." >&2
-  echo "       Neither 'stat -f' (BSD/macOS) nor 'stat -c' (GNU/Linux/Git Bash) worked here." >&2
-  echo "       Refusing to compare catalog freshness against an unknown timestamp." >&2
-  exit 2; }
+MPR_MTIME="$(stat -f "%Sm" -t "%Y-%m-%dT%H:%M:%S" "$MPR" 2>/dev/null || stat -c "%y" "$MPR" | cut -c1-19 | tr ' ' 'T')"
 BUILD_MODE="$(q "SELECT value FROM catalog_meta WHERE key='build_mode';")"
 
 if [ "$CAT_MTIME" != "$MPR_MTIME" ]; then
@@ -111,12 +74,8 @@
   exit 2
 fi
 
-WIRING_FILTER=""
-ORPHAN_FILTER=""
-if [ -n "$MODULE" ]; then
-  WIRING_FILTER="AND e.m = '$MODULE'"
-  ORPHAN_FILTER="AND m.ModuleName = '$MODULE'"
-fi
+MODFILTER=""
+[ -n "$MODULE" ] && MODFILTER="AND o.ModuleName = '$MODULE'"
 
 # --- finding 1: module wiring shape ---------------------------------------------------------
 # A module carrying real weight with no inbound edges from any other module is the signature
@@ -142,7 +101,7 @@
 )
 SELECT e.m, e.n, COALESCE(i.n,0), COALESCE(o.n,0)
 FROM elems e LEFT JOIN inb i ON i.m=e.m LEFT JOIN outb o ON o.m=e.m
-WHERE e.n >= $MIN_ELEMENTS $WIRING_FILTER
+WHERE e.n >= $MIN_ELEMENTS
 ORDER BY COALESCE(i.n,0) ASC, e.n DESC;
 ")"
 
@@ -166,7 +125,6 @@
         SELECT 1 FROM refs r
         WHERE r.TargetName = m.QualifiedName
           AND r.RefKind IN ('call','action','menu_item','show_page','datasource'))
-  $ORPHAN_FILTER
 ORDER BY m.ModuleName, m.Name;
 ")"
 
```

## bin/restart-sp.sh differs from shipped project-bin/restart-sp.sh — LOCAL-FIX

Not byte-identical to any shipped version in toolkit history — a real local fix. Closest historical base: d33d23f (2026-08-04), 173 diff line(s) from this project's copy. Diff (shipped -> project), truncated at 120 lines:

```diff
--- shipped/project-bin/restart-sp.sh
+++ project/bin/restart-sp.sh
@@ -1,150 +1,129 @@
 #!/usr/bin/env bash
-# restart-sp.sh — kill this project's Studio Pro instance + runtime, reopen cleanly.
+# restart-sp.sh (macOS) — kill PlantOps SP instance + runtime, then reopen cleanly
 #
-# Targets ONLY the SP process holding this project's .mpr, found via lsof — not
-# every SP on the machine. Two projects open at once is normal; killing the
-# wrong one loses unsaved work.
-#
-# macOS only (lsof/open/sample). See restart-sp.ps1 for the Windows port
-# (added 2026-08-04, far less proven — no `sample`-equivalent hang check).
+# See bin/restart-sp.ps1 for the Windows equivalent (untested — this project only
+# runs on macOS today; the port exists for portability, keep the two in sync by hand).
 #
 # AUTO_SP=1 skips BOTH the reopen confirmation below and the post-launch hang
-# warning's retry gate. Default is interactive: a stray invocation should not
-# force-quit someone's live session, or silently loop retries unattended.
-set -euo pipefail
-# PLATFORM GUARD. macOS only: this drives the Studio Pro GUI through AppleScript
-# (`osascript`), which exists on no other platform. Without this guard a Windows or Linux
-# user gets a force-quit prompt followed by a silent no-op (there is no `lsof`) — a message about a directory their machine does not have, from a script
-# whose real problem is that it can never work there. Say it plainly and stop.
-case "$(uname -s)" in
-  Darwin) ;;
-  *) echo "restart-sp.sh: macOS only — it drives Studio Pro through AppleScript." >&2
-     echo "   On $(uname -s), do this by hand instead: close Studio Pro, stop the running app, and reopen the project yourself." >&2
-     echo "   See the Platform support section of the toolkit README." >&2
-     exit 2 ;;
-esac
-
-. "$(dirname "$0")/_common.sh"
-
-MPR="$(find_mpr)" || exit 1
-NAME="$(basename "$MPR" .mpr)"
-DEPLOYMENT="$PROJECT_ROOT/deployment"
-HEALTH_CHECK="$(dirname "$0")/check-sp-health.sh"
+# warning's wait-for-input — set it for scripted/unattended runs. Default is
+# interactive (asks) so a stray invocation doesn't force-quit someone's live
+# session or silently loop retries without them noticing.
+set -e
+
+MPR="$(cd "$(dirname "$0")/.." && pwd)/WMS-Demo.mpr"
+DEPLOYMENT="$(cd "$(dirname "$0")/.." && pwd)/deployment"
+SP_APP="/Applications/Mendix Studio Pro 11.13.0 Beta.app"
+SP_BIN="Mendix Studio Pro 11.13.0 Beta.app/Contents/MacOS/studiopro"
+HEALTH_CHECK="$(cd "$(dirname "$0")" && pwd)/check-sp-health.sh"
 
-if [ "${AUTO_SP:-0}" != "1" ]; then
+if [[ "${AUTO_SP:-0}" != "1" ]]; then
   read -r -p "This will force-quit and reopen Studio Pro (any unsaved work is lost). Continue? [y/N] " REPLY
   case "$REPLY" in
     [Yy]*) ;;
-    *) echo "Aborted — nothing was touched. (Override: AUTO_SP=1 ./bin/restart-sp.sh)"; exit 0 ;;
+    *) echo "Aborted — nothing was touched. (Set AUTO_SP=1 to skip this prompt.)"; exit 0 ;;
   esac
 fi
 
-# Ports: Mendix's own native runtime port defaults to 8080, but at least one
-# project's Docker-mode logs referenced 8081 for the same deployment — confirmed
-# 2026-08-04 against a Docker-mode deployment.
-# Kill both unconditionally; MENDIX_RUNTIME_PORT adds a third if this project
-# uses something else entirely.
-EXTRA_PORT="${MENDIX_RUNTIME_PORT:-}"
-PORTS="8080,8081${EXTRA_PORT:+,$EXTRA_PORT}"
-echo "→ Killing Mendix runtime (ports $PORTS + deployment-path processes)..."
-lsof -ti :"$PORTS" 2>/dev/null | xargs kill -9 2>/dev/null || true
-[ -d "$DEPLOYMENT" ] && { lsof -t "$DEPLOYMENT" 2>/dev/null | xargs kill -9 2>/dev/null || true; }
-
-echo "→ Killing the SP instance holding $NAME..."
-# Graceful TERM, then poll for exit — a blind `sleep 5` either wastes time or
-# force-kills a process that was still flushing.
+# Run Locally's runtime port per this project's own generated WMS_Demo_main.launch
+# is 8080 (MXCONSOLE_RUNTIME_PORT), not 8081 — an earlier version of this script only
+# checked 8081. Kill both: 8080 is the confirmed native port, 8081 shows up in this
+# project's Docker-mode logs (ApplicationRootUrl), so it's cheap insurance either way.
+echo "→ Killing Mendix runtime (ports 8080/8081 + deployment-path processes)..."
+lsof -ti :8080,:8081 2>/dev/null | xargs kill -9 2>/dev/null || true
+lsof -t "$DEPLOYMENT" 2>/dev/null | xargs kill -9 2>/dev/null || true
+
+echo "→ Killing PlantOps SP instance..."
+# Gracefully quit only the SP process holding our MPR; poll for exit instead of a blind sleep
 SP_PID=$(lsof -t "$MPR" 2>/dev/null || true)
-if [ -n "$SP_PID" ]; then
-  kill -TERM $SP_PID 2>/dev/null || true
-  for _ in $(seq 1 25); do
-    kill -0 $SP_PID 2>/dev/null || break
+if [[ -n "$SP_PID" ]]; then
+  kill -TERM "$SP_PID" 2>/dev/null || true
+  for i in $(seq 1 25); do
+    kill -0 "$SP_PID" 2>/dev/null || break
     sleep 1
   done
-  kill -9 $SP_PID 2>/dev/null || true
+  kill -9 "$SP_PID" 2>/dev/null || true
 fi
 
-echo "→ Killing child processes (mxcli + orphaned modeler helpers)..."
-[ -d "$DEPLOYMENT" ] && { lsof -t "$DEPLOYMENT" 2>/dev/null | xargs kill -9 2>/dev/null || true; }
+echo "→ Killing child processes (mxcli + orphaned modeler helper processes)..."
+lsof -t "$DEPLOYMENT" 2>/dev/null | xargs kill -9 2>/dev/null || true
 pkill -9 -f "mxcli" 2>/dev/null || true
-# The modeler spawns a deno helper per live-preview session that is not reliably
-# cleaned up on close; they accumulate across restarts. Safe to kill here since
-# we are already force-restarting SP.
+# The modeler spawns a deno helper subprocess per live-preview session that isn't
+# reliably cleaned up on close — these accumulate across restarts. Safe to kill
+# unconditionally here since we're already force-restarting SP.
 pkill -9 -f "Mendix Studio Pro.*tools/deno" 2>/dev/null || true
 
-echo "→ Waiting for SP to release $NAME..."
-for _ in $(seq 1 20); do
-  lsof -t "$MPR" >/dev/null 2>&1 || break
+echo "→ Waiting for SP to exit..."
+for i in $(seq 1 20); do
+  lsof -t "$MPR" > /dev/null 2>&1 || break
   sleep 1
 done
 
```

## bin/restore-mpr.sh differs from shipped project-bin/restore-mpr.sh — LOCAL-FIX

Not byte-identical to any shipped version in toolkit history — a real local fix. Closest historical base: d33d23f (2026-08-04), 66 diff line(s) from this project's copy. Diff (shipped -> project), truncated at 120 lines:

```diff
--- shipped/project-bin/restore-mpr.sh
+++ project/bin/restore-mpr.sh
@@ -1,56 +1,23 @@
 #!/usr/bin/env bash
-# restore-mpr.sh — restore the .mpr + mprcontents/ from a snapshot-mpr.sh snapshot.
-#
-# Usage: ./bin/restore-mpr.sh [timestamp]    (defaults to the newest snapshot)
+# Restore WMS-Demo.mpr + mprcontents/ from a snapshot taken by snapshot-mpr.sh.
+# Usage: ./bin/restore-mpr.sh [timestamp]   (defaults to newest snapshot)
 set -euo pipefail
-. "$(dirname "$0")/_common.sh"
+cd "$(dirname "$0")/.."
 
-# Snapshots live under $PROJECT_ROOT; the model tree they restore INTO may not
-# (two-tree checkout: app/ holds the .mpr and mprcontents/). Resolve both.
-SNAP_DIR="$PROJECT_ROOT/.mpr-snapshots"
-MODEL_DIR="$(find_model_dir)" || exit 1
-cd "$MODEL_DIR"
-
-MPR_PATH="$(find_mpr)"
-MPR="$(basename "$MPR_PATH")"
+MPR="WMS-Demo.mpr"
+SNAP_DIR=".mpr-snapshots"
 
 SNAP="${1:-$(ls -dt "$SNAP_DIR"/*/ 2>/dev/null | head -1)}"
-[ -z "$SNAP" ] && { echo "ERROR: no timestamped snapshots in $SNAP_DIR (a flat .mpr-only copy is not a snapshot — it has no mprcontents/ and restores to garbage)"; exit 1; }
-[ ! -f "$SNAP/$MPR" ] && { echo "ERROR: snapshot $SNAP is missing $MPR"; exit 1; }
+[ -z "$SNAP" ] && { echo "ERROR: no timestamped snapshots in $SNAP_DIR (old flat .mpr-only snapshots don't count — see BUG-LOCAL-02)"; exit 1; }
+[ ! -f "$SNAP/$MPR" ] && { echo "ERROR: snapshot $SNAP missing $MPR"; exit 1; }
 
 echo "Restoring from: $SNAP"
-
-# Stage mprcontents/ in a temp dir and swap only on success. The obvious form,
-#   rm -rf mprcontents && cp -r "$SNAP/mprcontents" mprcontents
-# deletes first, and under `set -e` a failed cp aborts AFTER the delete — leaving
-# no mprcontents/ at all and a project recoverable only from git.
+cp "$SNAP/$MPR" "$MPR" && echo "  Restored: $MPR"
 if [ -d "$SNAP/mprcontents" ]; then
-  SNAP_UNITS=$(find "$SNAP/mprcontents" -name '*.mxunit' 2>/dev/null | wc -l | tr -d ' ')
-  TMP_MC="$MODEL_DIR/.mprcontents.restore.$$"
-  rm -rf "$TMP_MC"
-  if cp -r "$SNAP/mprcontents" "$TMP_MC"; then
-    rm -rf mprcontents
-    mv "$TMP_MC" mprcontents
-    cp "$SNAP/$MPR" "$MPR"
-    LIVE_UNITS=$(find mprcontents -name '*.mxunit' 2>/dev/null | wc -l | tr -d ' ')
-    echo "  Restored: $MPR"
-    if [ "$LIVE_UNITS" -eq "$SNAP_UNITS" ]; then
-      echo "  Restored: mprcontents/ ($LIVE_UNITS units verified)"
-    else
-      echo "  ⚠  RESTORE INCOMPLETE: $LIVE_UNITS of $SNAP_UNITS units."
-      echo "     Recover with: git checkout HEAD -- $MPR mprcontents/"
-      exit 1
-    fi
-  else
-    rm -rf "$TMP_MC"
-    echo "  ⚠  RESTORE FAILED — working tree left untouched."
-    echo "     Recover with: git checkout HEAD -- $MPR mprcontents/"
-    exit 1
-  fi
+  rm -rf mprcontents
+  cp -r "$SNAP/mprcontents" mprcontents
+  echo "  Restored: mprcontents/"
 else
-  echo "  ⚠  Snapshot has no mprcontents/ — refusing to restore the index alone."
-  echo "     Recover with: git checkout HEAD -- $MPR mprcontents/"
-  exit 1
+  echo "  WARNING: snapshot has no mprcontents/ — MPR index only, may be incomplete"
 fi
-
 echo "Restore complete. Verify with: ./mxcli docker check -p $MPR --no-update-widgets"
```

## bin/review-module.sh differs from shipped project-bin/review-module.sh — LOCAL-FIX

Not byte-identical to any shipped version in toolkit history — a real local fix. Closest historical base: 239af75 (2026-08-19), 66 diff line(s) from this project's copy. Diff (shipped -> project), truncated at 120 lines:

```diff
--- shipped/project-bin/review-module.sh
+++ project/bin/review-module.sh
@@ -47,7 +47,7 @@
 # Usage:
 #   bin/review-module.sh <Module> [--json-only] [--out <path>] [--reuse-conformance <tsv>]
 #
-# --reuse-conformance exists for one caller: bin/verify-module.sh, which has just run
+# --reuse-conformance exists for one caller: bin/loop/verify-module.sh, which has just run
 # conformance itself. Re-running it there would add ~9 minutes to measure the same thing
 # twice. The reused TSV must exist and must carry rows for this module — a reuse that
 # finds nothing is a FAULT, never a silent skip, or the report inherits the exact false
@@ -60,30 +60,8 @@
 # instrument set. It is stated in the output and deliberately not counted in the verdict.
 
 set -uo pipefail
-. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
-ROOT="$PROJECT_ROOT"
+ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
 cd "$ROOT" || exit 2
-BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
-MPR="$(find_mpr)" || exit 2
-
-# _tool NAME — where does this helper script actually live?  (same contract as
-# verify-module.sh; kept identical on purpose.) BIN is the directory THIS script
-# sits in, which is the project's bin/ only when the script was copied in. Run the
-# shared toolkit copy against a project instead and BIN is the toolkit's
-# project-bin/, so a helper the project keeps in its own bin/ is invisible and the
-# run reports "not reachable" for a file that is right there.
-#   1. <project>/bin  — the project's own, possibly tuned, copy wins
-#   2. $BIN           — alongside this script (the installed-copy case)
-#   3. $MXTK_ROOT/bin and $MXTK_ROOT/project-bin — the shared toolkit
-# Echoes the first hit; echoes <project>/bin/NAME when there is none, so the
-# caller's own "not found" message names the place a reader would look first.
-_tool() {
-  local n="$1" d
-  for d in "$ROOT/bin" "$BIN" "${MXTK_ROOT:-}/bin" "${MXTK_ROOT:-}/project-bin"; do
-    [ -n "$d" ] && [ -x "$d/$n" ] && { printf '%s\n' "$d/$n"; return 0; }
-  done
-  printf '%s\n' "$ROOT/bin/$n"
-}
 
 MODULE=""
 JSON_ONLY=0
@@ -261,17 +239,17 @@
   [ "${n:-0}" -gt 0 ] 2>/dev/null && MODULE_KNOWN=1
 fi
 if [ "$MODULE_KNOWN" -eq 0 ]; then
-  MODLIST="$(with_timeout 60 ./mxcli -p "$MPR" -c "SHOW MODULES" 2>/dev/null)"
+  MODLIST="$(with_timeout 60 ./mxcli -p WMS-Demo.mpr -c "SHOW MODULES" 2>/dev/null)"
   printf '%s\n' "$MODLIST" | grep -qE "^\| *$MODULE +\|" && MODULE_KNOWN=1
 fi
 
 if [ "$MODULE_KNOWN" -eq 0 ]; then
   printf '\n'
-  c_warn "  ! INSTRUMENT FAULT"; echo " — no module named '$MODULE' in $(basename "$MPR")"
+  c_warn "  ! INSTRUMENT FAULT"; echo " — no module named '$MODULE' in WMS-Demo.mpr"
   echo "      Nothing was measured. This is not a clean review of an empty module:"
   echo "      every instrument below would have returned an empty result set, which is"
   echo "      indistinguishable from a clean one. Check the spelling against:"
-  echo "        ./mxcli -p $(basename "$MPR") -c 'SHOW MODULES'"
+  echo "        ./mxcli -p WMS-Demo.mpr -c 'SHOW MODULES'"
   printf 'module exists\tFAULT\t2\t-\t(no such module)\n' >> "$SUMMARY"
   for i in conformance graph-sweep coverage; do
     note_instrument "$i" fault 2 "" "" "not run — no module named '$MODULE' in the model"
@@ -322,7 +300,7 @@
 else
   run "conformance (ledger claims vs live model)" conformance \
     "$OUTDIR/10-conformance.log" gate "${RM_TMO_CONFORMANCE:-1800}" -- \
-    "$(_tool conformance-check.sh)" --module "$MODULE"
+    "$ROOT/bin/conformance-check.sh" --module "$MODULE"
   # Slice THIS run's conformance report down to this module for the structured checks.
   #
   # `ls -t | head -1` names the newest report, which is only this run's report if this run
@@ -356,40 +334,22 @@
 # the sweep refuses to report a clean shape from a graph it cannot trust.
 run "graph sweep (orphans + wiring shape)" graph-sweep \
   "$OUTDIR/graph.tsv" gate 300 -- \
-  "$(_tool graph-sweep.sh)" --module "$MODULE" --tsv
+  "$ROOT/bin/graph-sweep.sh" --module "$MODULE" --tsv
 
 # ── 3. Coverage (optional rung): BRD leaves vs ledger ───────────────────────
 # A DIFFERENT question from conformance — "does the requirement exist and is it claimed",
 # not "does the model match the claim". Run when reachable; a fault row when not.
 COV=""
-# coverage-check.sh lives in the toolkit's bin/, not project-bin/, so _tool finds it
-# via $MXTK_ROOT. It used to be looked up through one contributor's absolute clone
-# path, which resolves on exactly one laptop.
-cand="$(_tool coverage-check.sh)"
-[ -x "$cand" ] && COV="$cand"
+for cand in "$ROOT/bin/coverage-check.sh" \
+            "/Users/<user>/Mendix/mxcli-project-toolkit/bin/coverage-check.sh"; do
+  [ -x "$cand" ] && { COV="$cand"; break; }
+done
 # The BRD is named by the ledger itself; guessing with `ls | head -1` picks another
 # module's BRD and reports its leaves as this module's coverage.
 BRD=""
 if [ -f "$LEDGER" ]; then
-  # ALL the BRDs the ledger names, not just the first — and the COUNT is reported, because
-  # coverage-check.sh measures one BRD per run and a module with five of them was silently
-  # having one fifth of its requirements measured and printed as the module's coverage
-  # (a workflow-migration project, 2026-09-02: five BRDs, F001 measured, F002-F005 never looked at, output
-  # indistinguishable from full coverage). That is the exact shape of false green this repo's
-  # own rule against unstated denominators exists to prevent.
-  #
-  # The first RESOLVABLE path wins rather than the first match: a ledger that mentions the
-  # filename pattern in prose above its list hands `head -1` a string that is not a file, and
-  # the instrument then reports "names no reachable BRD" over a ledger that names five.
-  BRD_ALL=""
-  while IFS= read -r cand; do
-    [ -n "$cand" ] && [ -f "$ROOT/$cand" ] && BRD_ALL="$BRD_ALL$cand"$'\n'
-  done <<EOF
-$(grep -oE '[A-Za-z0-9_/.-]*\.brd\.json' "$LEDGER" 2>/dev/null | sort -u)
-EOF
-  BRD_N=$(printf '%s' "$BRD_ALL" | grep -c . || true)
-  BRD_REL="$(printf '%s' "$BRD_ALL" | head -1)"
-  [ -n "$BRD_REL" ] && BRD="$ROOT/$BRD_REL"
+  BRD_REL="$(grep -oE '[A-Za-z0-9_/.-]*\.brd\.json' "$LEDGER" 2>/dev/null | head -1)"
+  [ -n "$BRD_REL" ] && [ -f "$ROOT/$BRD_REL" ] && BRD="$ROOT/$BRD_REL"
 fi
 if [ -z "$COV" ]; then
```

## bin/save-sp.sh differs from shipped project-bin/save-sp.sh — LOCAL-FIX

Not byte-identical to any shipped version in toolkit history — a real local fix. Closest historical base: d33d23f (2026-08-04), 32 diff line(s) from this project's copy. Diff (shipped -> project), truncated at 120 lines:

```diff
--- shipped/project-bin/save-sp.sh
+++ project/bin/save-sp.sh
@@ -1,38 +1,6 @@
 #!/usr/bin/env bash
-# save-sp.sh — trigger Cmd+S in Studio Pro, flushing the in-memory model to disk.
-#
-# Run after any MCP write. SP holds the model in memory; until it saves, the
-# .mpr on disk does not contain your change, and anything reading the file
-# (mxbuild, mxcli, git) sees the older state.
-#
-# macOS only — it drives the GUI via AppleScript. Requires Accessibility
-# permission for the terminal app, or the keystroke is silently dropped.
-set -euo pipefail
-# PLATFORM GUARD. macOS only: this drives the Studio Pro GUI through AppleScript
-# (`osascript`), which exists on no other platform. Without this guard a Windows or Linux
-# user gets "no 'Mendix Studio Pro *.app' in /Applications" — a message about a directory their machine does not have, from a script
-# whose real problem is that it can never work there. Say it plainly and stop.
-case "$(uname -s)" in
-  Darwin) ;;
-  *) echo "save-sp.sh: macOS only — it drives Studio Pro through AppleScript." >&2
-     echo "   On $(uname -s), do this by hand instead: press Ctrl+S in Studio Pro to flush the model to disk." >&2
-     echo "   See the Platform support section of the toolkit README." >&2
-     exit 2 ;;
-esac
-
-. "$(dirname "$0")/_common.sh"
-
-APP_PATH="$(find_sp_app)" || exit 1
-APP_NAME="$(basename "$APP_PATH" .app)"
-
-osascript -e "tell application \"$APP_NAME\" to activate" 2>/dev/null || {
-  echo "✗ Could not activate '$APP_NAME' — is Studio Pro running?" >&2
-  exit 1
-}
+# save-sp.sh — trigger Cmd+S save in Studio Pro after any MCP write
+osascript -e 'tell application "Mendix Studio Pro 11.13.0 Beta" to activate' 2>/dev/null
 sleep 0.5
-osascript -e 'tell application "System Events" to keystroke "s" using command down' 2>/dev/null || {
-  echo "✗ Keystroke refused. Grant Accessibility permission to your terminal:" >&2
-  echo "  System Settings → Privacy & Security → Accessibility" >&2
-  exit 1
-}
-echo "✓ SP save triggered ($APP_NAME) — MPR flushed to disk."
+osascript -e 'tell application "System Events" to keystroke "s" using command down' 2>/dev/null
+echo "✓ SP save triggered — MPR flushed to disk."
```

## bin/snapshot-mpr.sh differs from shipped project-bin/snapshot-mpr.sh — LOCAL-FIX

Not byte-identical to any shipped version in toolkit history — a real local fix. Closest historical base: d33d23f (2026-08-04), 36 diff line(s) from this project's copy. Diff (shipped -> project), truncated at 120 lines:

```diff
--- shipped/project-bin/snapshot-mpr.sh
+++ project/bin/snapshot-mpr.sh
@@ -1,90 +1,26 @@
 #!/usr/bin/env bash
-# snapshot-mpr.sh — rotating .mpr safety net.
-#
-# Snapshots every *.mpr AND mprcontents/ into a timestamped subdirectory of
-# .mpr-snapshots/, keeping the 5 newest. Run BEFORE every `mxcli exec`;
-# bin/exec.sh does it for you.
-#
-# BOTH parts or nothing. An MPR is a SQLite index (.mpr) plus the BSON units
-# that hold the actual model (mprcontents/). A snapshot of either alone restores
-# to garbage. Ad-hoc `cp Project.mpr Project.mpr.backup` is exactly that mistake
-# and is why this script exists.
-#
-# The model tree is resolved with find_model_dir, NOT $PROJECT_ROOT: on a two-tree
-# checkout (repo at the root, `mxcli new` app under app/) they are different
-# directories, and globbing the repo root matched nothing while still printing
-# "mpr snapshot ok" — see the find_model_dir header in _common.sh for the field
-# incident. The snapshots themselves stay under $PROJECT_ROOT/.mpr-snapshots so
-# they land in one gitignored place regardless of layout.
-#
-# Git commits at phase gates remain the real history — this only covers
-# mid-session corruption between commits.
+# Rotating MPR safety net: snapshot every *.mpr AND mprcontents/ (the actual
+# BSON unit data — see bug-logs/mxcli-bugs.md BUG-LOCAL-02) into a timestamped
+# subdirectory of .mpr-snapshots/, keeping only the 5 newest. Run BEFORE every
+# `mxcli exec` (see CLAUDE.md). Git commits per build-gate remain the real
+# history — this only covers mid-session corruption between commits.
 set -euo pipefail
-. "$(dirname "$0")/_common.sh"
+cd "$(dirname "$0")/.."
+mkdir -p .mpr-snapshots
 
-MODEL_DIR="$(find_model_dir)" || exit 1
-
-# A producer guarantees its own output is ignored. This writes a FULL copy of the .mpr and
-# every mprcontents unit, five deep — so a project that does not gitignore it commits the
-# client's whole model several times over, and then reports thousands of phantom deletions
-# the next time the rotation below prunes one.
-#
-# Measured on a MOC/PSSR app replacement, 2026-09-09: 2,089 snapshot files tracked, and
-# `mxcli exec` then REFUSED to run, because exec.sh read the pruned snapshot as uncommitted
-# model changes — this script's output blocking this script's own guard. It is written here
-# rather than in init-project.sh on purpose: here it also reaches every project that already
-# exists, on its next exec, instead of only the ones scaffolded after today.
-if [ -d "$PROJECT_ROOT/.git" ] || [ -f "$PROJECT_ROOT/.git" ]; then
-  GI="$PROJECT_ROOT/.gitignore"
-  if ! { [ -f "$GI" ] && grep -qE '^/?\.mpr-snapshots/?$' "$GI"; }; then
-    # Never fatal: this runs under set -e BEFORE the snapshot, and exec.sh calls it bare — an
-    # unwritable .gitignore must not stop the snapshot (CLAUDE.md guard rule 7).
-    if {
-      if [ -f "$GI" ] && [ -s "$GI" ] && [ -n "$(tail -c 1 "$GI")" ]; then printf '\n'; fi
-      printf '# Pre-exec model snapshots (project-bin/snapshot-mpr.sh). A full .mpr + mprcontents\n'
-      printf '# copy per exec, five kept. Never committed: it is the client model, several times over.\n'
-      printf '/.mpr-snapshots/\n'
-    } >> "$GI" 2>/dev/null; then
-      printf 'snapshot-mpr: added /.mpr-snapshots/ to .gitignore (it was not ignored).\n' >&2
-    else
-      printf 'snapshot-mpr: WARN could not write %s — add /.mpr-snapshots/ to it yourself.\n' "$GI" >&2
-    fi
-  fi
-fi
-
-mkdir -p "$PROJECT_ROOT/.mpr-snapshots"
-DEST="$PROJECT_ROOT/.mpr-snapshots/$(date +%Y%m%d-%H%M%S)"
+TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
+DEST=".mpr-snapshots/${TIMESTAMP}"
 mkdir -p "$DEST"
 
-MPR_COUNT=0
-for f in "$MODEL_DIR"/*.mpr; do
+for f in *.mpr; do
   [ -e "$f" ] || continue
-  cp "$f" "$DEST/$(basename "$f")"
-  MPR_COUNT=$((MPR_COUNT + 1))
+  cp "$f" "$DEST/$f"
 done
-[ -d "$MODEL_DIR/mprcontents" ] && cp -r "$MODEL_DIR/mprcontents" "$DEST/mprcontents"
-
-UNIT_COUNT=$(find "$DEST/mprcontents" -name '*.mxunit' 2>/dev/null | wc -l | tr -d ' ')
-
-# An empty snapshot is worse than no snapshot: exec.sh proceeds believing it has a
-# net, and the prune below has already thrown away the older ones. Refuse loudly,
-# and refuse BEFORE pruning, so a bad resolve cannot destroy good history.
-if [ "$MPR_COUNT" -eq 0 ]; then
-  rm -rf "$DEST"
-  echo "✗ snapshot FAILED: no .mpr found in $MODEL_DIR — refusing to record an empty snapshot." >&2
-  echo "  Set MPR_FILE=<path>.mpr (relative to $PROJECT_ROOT) so the model tree resolves." >&2
-  exit 1
-fi
-if [ "$UNIT_COUNT" -eq 0 ]; then
-  rm -rf "$DEST"
-  echo "✗ snapshot FAILED: $MODEL_DIR has no mprcontents/*.mxunit — .mpr alone restores to garbage." >&2
-  echo "  If the model is genuinely v1 single-file, commit it and skip the snapshot net." >&2
-  exit 1
-fi
+[ -d mprcontents ] && cp -r mprcontents "$DEST/mprcontents"
 
-# Prune: keep the 5 newest timestamped dirs.
-ls -dt "$PROJECT_ROOT"/.mpr-snapshots/*/ 2>/dev/null | tail -n +6 | while read -r old; do
+# prune: keep the 5 newest timestamped snapshot dirs
+ls -dt .mpr-snapshots/*/ 2>/dev/null | tail -n +6 | while read -r old; do
   rm -rf "$old"
 done
 
-echo "mpr snapshot ok ($MPR_COUNT .mpr + $UNIT_COUNT units) — $(ls -d "$PROJECT_ROOT"/.mpr-snapshots/*/ 2>/dev/null | wc -l | tr -d ' ') kept in .mpr-snapshots/"
+echo "mpr snapshot ok (.mpr + mprcontents/) — $(ls -d .mpr-snapshots/*/ 2>/dev/null | wc -l | tr -d ' ') kept in .mpr-snapshots/"
```

## bin/test-stack-up.sh differs from shipped project-bin/test-stack-up.sh — LOCAL-FIX

Not byte-identical to any shipped version in toolkit history — a real local fix. Closest historical base: 512fc57 (2026-08-18), 364 diff line(s) from this project's copy. Diff (shipped -> project), truncated at 120 lines:

```diff
--- shipped/project-bin/test-stack-up.sh
+++ project/bin/test-stack-up.sh
@@ -1,70 +1,37 @@
 #!/usr/bin/env bash
 # test-stack-up.sh — bring the test stack up, and PROVE it is up.
 #
-# WHY THIS EXISTS. It is the precondition step for any e2e run, and the crash-net scripts cannot do
-# the job: every exit path of restart-sp.sh ends with "click Run Locally in Studio Pro", which blocks
-# every test run on a human. This script brings the stack up unattended and — the part that matters —
-# proves the thing that answered is THIS project's application.
+# This is the precondition step for any e2e run (see personal-toolkit/skills/testing-shape.md §5).
+# It exists because bin/restart-sp.sh cannot do this job: every one of its exit paths ends with
+# "click Run Locally in Studio Pro", which blocks every test run on a human.
 #
 # DESIGN RULES, all deliberate:
 #   1. NEVER touches Studio Pro. No force-quit, no kill. It detects SP and reports; that is all.
-#      restart-sp.sh owns crash recovery and warns that unsaved work is lost. This must be safe to
-#      run while someone else is working in SP.
+#      restart-sp.sh owns crash recovery and warns that unsaved work is lost. This script must be
+#      safe to run while someone else is working in SP.
 #   2. NEVER writes to the .mpr. `mxcli docker build` reads the model and writes only build output.
 #   3. Proves liveness with an actual HTTP response. "No error" is not "up".
 #   4. Idempotent. If the app already answers, it does nothing and exits 0.
-#   5. Starts an auxiliary service if it is down; NEVER stops one (another session may be using it).
+#   5. Starts the mock if it is down; NEVER stops it (another session may be using it).
 #
 # Usage:
 #   bin/test-stack-up.sh --check     # report only, change nothing. Exit 0 iff required deps are up.
 #   bin/test-stack-up.sh             # report, then bring up what is missing (may run a Docker build)
-#   bin/test-stack-up.sh --no-docker # bring up auxiliaries only; never build. "SP is already running it".
+#   bin/test-stack-up.sh --no-docker # bring up mock only; never build. For "SP is already running it".
 #
 # Exit codes: 0 = required stack is up · 1 = not up and could not fix · 2 = usage/env error
-#
-# PROJECT CONFIGURATION — no project name, port or service path is hardcoded here. Put anything
-# project-specific in <project>/.claude/loop/stack.conf, which this script sources if present:
-#
-#   APP_PORTS="8080 8081"                                # fallback scan list; ownership beats it
-#   JAEGER_PORT=16686                                    # OTel collector UI (optional)
-#   MOCK_HEALTH_URL="http://localhost:3001/api/health"   # set to enable the mock rung
-#   MOCK_PORT=3001
-#   MOCK_DIR="source/mock-api"                           # dir containing server.js
-#   MOCK_START="node server.js"                          # command run inside MOCK_DIR
-#   BOOT_TIMEOUT=240
-#
-# With no MOCK_HEALTH_URL the mock rung is reported as "not configured" and does not gate — most
-# projects have no mock, and a rung that fails for everyone gets switched off, taking the real
-# rungs with it.
 
 set -uo pipefail
 
-. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
-cd "$PROJECT_ROOT" || { echo "cannot cd to project root" >&2; exit 2; }
-ROOT="$PROJECT_ROOT"
-
-MPR="$(find_mpr)" || exit 2
-PROJ="$(project_name)" || PROJ="app"
-
-STACK_CONF="${STACK_CONF:-$ROOT/.claude/loop/stack.conf}"
-# shellcheck disable=SC1090
-[ -f "$STACK_CONF" ] && . "$STACK_CONF"
+ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
+cd "$ROOT" || { echo "cannot cd to project root" >&2; exit 2; }
 
+MPR="${MPR:-WMS-Demo.mpr}"
 APP_PORTS="${APP_PORTS:-8080 8081 8084}"
 JAEGER_PORT="${JAEGER_PORT:-16686}"
-MOCK_HEALTH_URL="${MOCK_HEALTH_URL:-}"
-MOCK_PORT="${MOCK_PORT:-}"
-MOCK_DIR="${MOCK_DIR:-}"
-MOCK_START="${MOCK_START:-node server.js}"
+MOCK_PORT="${MOCK_PORT:-3001}"
+MOCK_DIR="${MOCK_DIR:-source/USI scope/mock-api}"
 BOOT_TIMEOUT="${BOOT_TIMEOUT:-240}"
-LOGDIR="${LOGDIR:-${TMPDIR:-/tmp}}"
-MOCK_LOG="$LOGDIR/${PROJ}-mock.log"
-DOCKER_LOG="$LOGDIR/${PROJ}-docker-run.log"
-
-# mxcli lives in the project root on a wired project, but may be on PATH instead.
-if [ -x "$ROOT/mxcli" ]; then MXCLI="$ROOT/mxcli"
-elif command -v mxcli >/dev/null 2>&1; then MXCLI="mxcli"
-else MXCLI=""; fi
 
 MODE="up"
 case "${1:-}" in
@@ -78,138 +45,29 @@
 bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; }
 warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
 
-# HTTP liveness. Returns 0 only on a real status line — a served response, not a guess.
-# 4xx counts as "serving" (a login redirect or 403 still proves something answers).
+# HTTP liveness. Returns 0 only on a real 2xx/3xx/4xx status line — a served response, not a guess.
+# 4xx counts as "serving" (a login redirect or 403 still proves the runtime answers).
 http_up() {
   local url="$1" code
   code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 "$url" 2>/dev/null)"
   [ -n "$code" ] && [ "$code" != "000" ]
 }
 
-# Identify a MENDIX app, not merely "something is listening".
-#
-# CONFIRMED FALSE GREEN: an unrelated Node/Express process was bound to the expected port and this
-# script reported "✓ App serving". http_up() accepts any 4xx as "serving" — deliberate, a login
-# redirect or 403 is a real Mendix response — but Express answers /login.html with a 404, also 4xx.
-# A spec pointed at that port then hangs forever waiting for a login form that will never render,
-# and the symptom reads as "the app is broken".
-#
-# So: require a served login page (2xx/3xx) that actually contains Mendix markers. 4xx no longer
-# qualifies for identification — if the runtime is up but redirecting, /index.html carries the same
-# markers.
-mendix_at() {
-  local p="$1" body code path
-  for path in /login.html /index.html; do
-    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 "http://localhost:$p$path" 2>/dev/null)"
-    case "$code" in 2??|3??) ;; *) continue ;; esac
-    body="$(curl -s --max-time 4 "http://localhost:$p$path" 2>/dev/null | head -c 20000)"
-    case "$body" in
-      *mxui*|*mx-name*|*"Mendix"*|*mxclientsystem*) return 0 ;;
-    esac
-  done
```

1 stale (one line each) · 11 local fix(es) (diffs above)
