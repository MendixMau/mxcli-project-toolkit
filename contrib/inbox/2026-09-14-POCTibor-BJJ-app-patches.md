**From:** POCTibor-BJJ-app
**Date:** 2026-09-14
**Kind:** fix
**Field evidence:** installed toolkit scripts in POCTibor-BJJ-app/bin that differ from the shipped copy — a local patch here is a fix that never traveled (how graph-sweep's stat bug got patched twice)
**Proposed target:** see per-item notes below

---

- bin/_common.sh — STALE: identical to shipped d33d23f (2026-08-04); fix: bin/sync-project.sh <project-root> --upgrade-bin _common.sh

- bin/build-plan-status.sh — STALE: identical to shipped 2b4ef35 (2026-08-19); fix: bin/sync-project.sh <project-root> --upgrade-bin build-plan-status.sh

- bin/check-design-portability.sh — STALE: identical to shipped e3ee6fb (2026-08-26); fix: bin/sync-project.sh <project-root> --upgrade-bin check-design-portability.sh

- bin/check-page-shell.sh — STALE: identical to shipped 7149145 (2026-08-27); fix: bin/sync-project.sh <project-root> --upgrade-bin check-page-shell.sh

- bin/check-sp-health.sh — STALE: identical to shipped ffff50e (2026-08-04); fix: bin/sync-project.sh <project-root> --upgrade-bin check-sp-health.sh

- bin/coherence-cadence.sh — STALE: identical to shipped e75c912 (2026-08-21); fix: bin/sync-project.sh <project-root> --upgrade-bin coherence-cadence.sh

- bin/conformance-check.sh — STALE: identical to shipped 239af75 (2026-08-19); fix: bin/sync-project.sh <project-root> --upgrade-bin conformance-check.sh

## bin/exec.sh differs from shipped project-bin/exec.sh — LOCAL-FIX

Not byte-identical to any shipped version in toolkit history — a real local fix. Closest historical base: 3d8a3fe (2026-08-12), 28 diff line(s) from this project's copy. Diff (shipped -> project), truncated at 120 lines:

```diff
--- shipped/project-bin/exec.sh
+++ project/bin/exec.sh
@@ -1,7 +1,7 @@
 #!/usr/bin/env bash
 # exec.sh — the guard chain around a model write.
 #
-#   concurrent-writer guard → module-brief advisory → mxcli check → snapshot → baseline → exec
+#   concurrent-writer guard → mxcli check → snapshot → baseline → exec
 #   → mxbuild gate → auto-restore on regression → SP reopen
 #
 # Usage: ./bin/exec.sh <script.mdl>
@@ -10,7 +10,6 @@
 #            mxcli check), SKIP_BASELINE=1 (skip pre-flight mxbuild),
 #            MXBUILD_PATH=..., MENDIX_APP=..., MPR_FILE=...
 set -e
-_T0=$(date +%s)
 
 . "$(dirname "$0")/_common.sh"
 
@@ -30,12 +29,6 @@
 # The .mpr must have exactly ONE writer. Two mxcli/SP writers on the same file
 # silently clobber each other and have caused near-total module loss.
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
@@ -74,112 +67,18 @@
 # 4. Uncommitted model changes. The snapshot taken below would not cover them,
 #    so a failed gate would auto-restore to a state pre-dating those changes and
 #    silently lose work.
-MPR_DIRTY=$(git status --porcelain "$MPR" "$MODEL_DIR/mprcontents" 2>/dev/null | grep -v "^$" || true)
+MPR_DIRTY=$(git status --porcelain "$MPR_BASE" mprcontents/ 2>/dev/null | grep -v "^$" || true)
 if [ -n "$MPR_DIRTY" ]; then
   echo "✗ Uncommitted model changes — refusing exec to prevent snapshot regression."
   echo ""
   echo "$MPR_DIRTY" | sed 's/^/    /'
   echo ""
-  echo "  → git add $MPR $MODEL_DIR/mprcontents && git commit -m 'Commit model changes before exec'"
+  echo "  → git add $MPR_BASE mprcontents/ && git commit -m 'Commit model changes before exec'"
   echo "  Override (accepts silent-loss risk): FORCE_EXEC=1 ./bin/exec.sh $SCRIPT"
   [ "$FORCE" = "1" ] || exit 1
   echo "  (FORCE_EXEC set — proceeding despite uncommitted changes)"
 fi
 
-# 5. Module brief advisory (WARNS, never blocks).
-#
-# WHY THE BRIEF. It is the mdl-agent's single per-module input: the access-table slice,
-# screens-per-role, field-level validation rules, edge cases, and the wireframe->page map.
-# Nothing else in the project carries them. Without it the agent synthesises them from
-# training data, and every access-rights / wrong-binding / invented-validation incident
-# traces back to that. Real incident (a customer training round, 2026-08-25): 12 domain
-# scripts and 13 feature scripts executed against a module whose architecture/modules/<M>/
-# held only definition.md.
-#
-# WHY THIS ONLY WARNS. The brief is a build-plan artifact — "write the module brief" is a
-# numbered row at the head of each phase (brd-to-build-plan.md Step 5). That is where the
-# ordering guarantee belongs, because that is the document every build follows. exec.sh is
-# not the pipeline's gatekeeper and must not become one: the toolkit is deliberately usable
-# a la carte, and refusing a write is the wrong answer to "this project chose not to run the
-# pipeline". A hard block here would also have needed FORCE_EXEC on every legitimate
-# non-pipeline write, and a guard routinely overridden teaches people to override guards.
-#
-# So: no architecture/build-plan.md means the project never opted in, and this block says
-# nothing at all. With a build plan, a missing brief means a row was skipped — worth saying
-# once, out loud, and then getting out of the way.
-#
-# Satisfied by EITHER form, because single-module projects merge the brief into the plan
-# rather than maintaining two documents that overlap ~70%:
-#   a) architecture/modules/<Module>/module-brief.md
-#   b) a "## Module brief - <Module>" heading in architecture/build-plan.md
-#
-# Platform and marketplace modules are skipped - this project does not author their briefs.
-brief_missing=""
-if [ -f "$SCRIPT" ] && [ -f "$PROJECT_ROOT/architecture/build-plan.md" ]; then
-  # Comments FIRST, before any pattern match. A `-- ... CREATE MODULE errors if ...` line in a
-  # real workshop script otherwise yielded a module named "errors" and would have demanded a
-  # brief for it forever. A guard that cries wolf gets switched off — same reasoning as
-  # bin/check-portability.sh's "NOT on the denylist" note. POSIX awk, no python/perl: Git Bash
-  # on Windows has to run this too.
-  # Assigned single-quoted, invoked double-quoted: bash does not re-expand the *result* of a
-  # variable expansion, so awk's $0 survives. The alternative (inlining the program in quotes)
-  # was tried and mangled it — $0 expanded to the shell script's own name.
-  awk_strip_comments='
-    {
-      s = $0; out = ""; i = 1
-      while (i <= length(s)) {
-        c = substr(s, i, 2)
-        if (!inblk && c == "/*") { inblk = 1; i += 2; continue }
-        if (inblk  && c == "*/") { inblk = 0; i += 2; continue }
-        if (!inblk && c == "--") { break }
-        if (!inblk) out = out substr(s, i, 1)
-        i++
-      }
-      print out
-    }'
-  script_body=$(awk "$awk_strip_comments" "$SCRIPT" 2>/dev/null)
-
-  # Modules written to by this script: the qualified name on a create/alter/drop target.
-  script_modules=$(printf '%s\n' "$script_body" \
-    | grep -oiE '(create|alter|drop)[[:space:]]+(or[[:space:]]+modify[[:space:]]+)?(persistent[[:space:]]+|non-persistent[[:space:]]+)?[a-z_ ]*[[:space:]]"?([A-Za-z_][A-Za-z0-9_]*)"?\.' \
-    | grep -oE '"?[A-Za-z_][A-Za-z0-9_]*"?\.$' | tr -d '".' | sort -u)
-  # DELIBERATELY NOT `CREATE MODULE <X>` on its own. Creating an empty module is scaffolding; the
-  # brief describes what goes *inside* one, so demanding it before the module exists is backwards.
-  # It also keeps tests/wave2/test-bug07-08.sh working — its fixture project execs
-  # `CREATE MODULE "Nope";` with no architecture/ at all, and would otherwise fail every case.
-  #
-  # Everything else about a module DOES need the brief first, including `create or modify module
-  # role <M>.<Role>` — module roles are the subject of the brief's access table, so authoring them
-  # unspecified is the exact gap this guard exists to close. Replaying that round's real day
-  # 1 (28 scripts, empty architecture/) the first refusal lands on script 1, at the module-role
-  # line in 01-app-scaffold.mdl. That is the intended blast radius: the brief is row 0, so nothing
-  # numbered after it may run first.
-
-  for m in $(echo "$script_modules" | grep -v '^$' | sort -u); do
```

- bin/fixture-manifest.sh — STALE: identical to shipped 6e04418 (2026-08-18); fix: bin/sync-project.sh <project-root> --upgrade-bin fixture-manifest.sh

## bin/graph-sweep.sh differs from shipped project-bin/graph-sweep.sh — LOCAL-FIX

Not byte-identical to any shipped version in toolkit history — a real local fix. Closest historical base: 239af75 (2026-08-19), 18 diff line(s) from this project's copy. Diff (shipped -> project), truncated at 120 lines:

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
@@ -33,21 +23,8 @@
 . "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
 cd "$PROJECT_ROOT" || exit 2
 
+DB=".mxcli/catalog.db"
 MPR="$(find_mpr)" || exit 2
-
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
 MODULE=""
 MIN_ELEMENTS=20
 TSV=0
@@ -70,21 +47,11 @@
 
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
+if [ "$(uname -s)" = "Linux" ]; then
+  MPR_MTIME="$(stat -c "%y" "$MPR" | cut -c1-19 | tr ' ' 'T')"
+else
+  MPR_MTIME="$(stat -f "%Sm" -t "%Y-%m-%dT%H:%M:%S" "$MPR" 2>/dev/null || stat -c "%y" "$MPR" | cut -c1-19 | tr ' ' 'T')"
+fi
 BUILD_MODE="$(q "SELECT value FROM catalog_meta WHERE key='build_mode';")"
 
 if [ "$CAT_MTIME" != "$MPR_MTIME" ]; then
```

- bin/lint-gate.sh — STALE: identical to shipped a0af58e (2026-08-19); fix: bin/sync-project.sh <project-root> --upgrade-bin lint-gate.sh

- bin/restart-sp.sh — STALE: identical to shipped ffff50e (2026-08-04); fix: bin/sync-project.sh <project-root> --upgrade-bin restart-sp.sh

- bin/restore-mpr.sh — STALE: identical to shipped d33d23f (2026-08-04); fix: bin/sync-project.sh <project-root> --upgrade-bin restore-mpr.sh

- bin/review-module.sh — STALE: identical to shipped 239af75 (2026-08-19); fix: bin/sync-project.sh <project-root> --upgrade-bin review-module.sh

- bin/save-sp.sh — STALE: identical to shipped d33d23f (2026-08-04); fix: bin/sync-project.sh <project-root> --upgrade-bin save-sp.sh

- bin/snapshot-mpr.sh — STALE: identical to shipped d33d23f (2026-08-04); fix: bin/sync-project.sh <project-root> --upgrade-bin snapshot-mpr.sh

- bin/verify-module.sh — STALE: identical to shipped fb7f613 (2026-08-19); fix: bin/sync-project.sh <project-root> --upgrade-bin verify-module.sh

- bin/page-fidelity.js — STALE: identical to shipped 102f0e4 (2026-08-28); fix: bin/sync-project.sh <project-root> --upgrade-bin page-fidelity.js

16 stale (one line each) · 2 local fix(es) (diffs above)
