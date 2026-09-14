**From:** TransportOrderMgmt-conversion
**Date:** 2026-09-14
**Kind:** fix
**Field evidence:** installed toolkit scripts in TransportOrderMgmt-conversion/bin that differ from the shipped copy — a local patch here is a fix that never traveled (how graph-sweep's stat bug got patched twice)
**Proposed target:** see per-item notes below

---

- bin/_common.sh — STALE: identical to shipped f0c775e (2026-08-19); fix: bin/sync-project.sh <project-root> --upgrade-bin _common.sh

- bin/build-plan-status.sh — STALE: identical to shipped 2b4ef35 (2026-08-19); fix: bin/sync-project.sh <project-root> --upgrade-bin build-plan-status.sh

- bin/coherence-cadence.sh — STALE: identical to shipped e75c912 (2026-08-21); fix: bin/sync-project.sh <project-root> --upgrade-bin coherence-cadence.sh

- bin/conformance-check.sh — STALE: identical to shipped ea275ea (2026-08-20); fix: bin/sync-project.sh <project-root> --upgrade-bin conformance-check.sh

## bin/exec.sh differs from shipped project-bin/exec.sh — LOCAL-FIX

Not byte-identical to any shipped version in toolkit history — a real local fix. Closest historical base: ea275ea (2026-08-20), 19 diff line(s) from this project's copy. Diff (shipped -> project), truncated at 120 lines:

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

- bin/graph-sweep.sh — STALE: identical to shipped bf938bd (2026-08-19); fix: bin/sync-project.sh <project-root> --upgrade-bin graph-sweep.sh

- bin/page-scope.sh — STALE: identical to shipped 078c7d8 (2026-08-22); fix: bin/sync-project.sh <project-root> --upgrade-bin page-scope.sh

- bin/restore-mpr.sh — STALE: identical to shipped d33d23f (2026-08-04); fix: bin/sync-project.sh <project-root> --upgrade-bin restore-mpr.sh

- bin/review-module.sh — STALE: identical to shipped e75c912 (2026-08-21); fix: bin/sync-project.sh <project-root> --upgrade-bin review-module.sh

- bin/snapshot-mpr.sh — STALE: identical to shipped d33d23f (2026-08-04); fix: bin/sync-project.sh <project-root> --upgrade-bin snapshot-mpr.sh

- bin/verify-module.sh — STALE: identical to shipped 8923525 (2026-08-22); fix: bin/sync-project.sh <project-root> --upgrade-bin verify-module.sh

11 stale (one line each) · 1 local fix(es) (diffs above)
