**From:** vb-usi-main
**Date:** 2026-09-14
**Kind:** fix
**Field evidence:** installed toolkit scripts in vb-usi-main/bin that differ from the shipped copy — a local patch here is a fix that never traveled (how graph-sweep's stat bug got patched twice)
**Proposed target:** see per-item notes below

---

## bin/_common.sh differs from shipped project-bin/_common.sh — LOCAL-FIX

Not byte-identical to any shipped version in toolkit history — a real local fix. Closest historical base: d33d23f (2026-08-04), 75 diff line(s) from this project's copy. Diff (shipped -> project), truncated at 120 lines:

```diff
--- shipped/project-bin/_common.sh
+++ project/bin/_common.sh
@@ -11,38 +11,8 @@
 # Bash 3.2 compatible on purpose: `env bash` on stock macOS is 3.2.57. No
 # mapfile, no readarray, no associative arrays, no ${var,,}.
 
-# Resolve the project root. Three tiers, because these scripts run from two places.
-#
-#   1. $PROJECT_ROOT, if the caller set it — always wins.
-#   2. The sourcing script's location (bin/ -> ..), when that parent IS a project.
-#      This is the installed-copy case: <project>/bin/verify-module.sh.
-#   3. The current directory's project root, found by walking up for an .mpr.
-#
-# Tier 3 is why this is not a one-liner any more. The toolkit's own copy of these
-# scripts used to resolve tier 2 to the TOOLKIT, so running
-#     ~/mxcli-project-toolkit/project-bin/verify-module.sh <Module>
-# from inside a project pointed every instrument at the toolkit, which has no .mpr
-# and no tests/e2e — and the run reported instrument faults rather than saying the
-# obvious thing, that it was aimed at the wrong directory. Copying the script into
-# every project was the workaround. Tier 3 removes the need for it: the shared
-# toolkit copy now works from inside any wired project, no env var, no install.
-_mxtk_resolve_root() {
-  local self_parent d
-  self_parent=$(cd "$(dirname "${BASH_SOURCE[2]:-${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}}")/.." 2>/dev/null && pwd)
-  # tier 2: the script sits in a real project's bin/
-  if [ -n "$self_parent" ] && ls "$self_parent"/*.mpr >/dev/null 2>&1; then
-    printf '%s\n' "$self_parent"; return 0
-  fi
-  # tier 3: walk up from $PWD looking for the .mpr
-  d=$(pwd)
-  while [ "$d" != "/" ]; do
-    if ls "$d"/*.mpr >/dev/null 2>&1; then printf '%s\n' "$d"; return 0; fi
-    d=$(dirname "$d")
-  done
-  # nothing found: keep the old behaviour so the caller's own error is the one seen
-  printf '%s\n' "${self_parent:-$(pwd)}"
-}
-PROJECT_ROOT="${PROJECT_ROOT:-$(_mxtk_resolve_root)}"
+# Resolve the project root from the sourcing script's location (bin/ -> ..).
+PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")/.." && pwd)}"
 
 # ---------------------------------------------------------------------------
 # find_mpr — echo the project's single .mpr, or fail loudly.
@@ -67,16 +37,6 @@
     count=$((count + 1))
     found="$f"
   done
-  # Two-tree checkout: repo at the root, the `mxcli new --output-dir ./app` app under app/.
-  # cloud-dev-environment.md prescribes exactly that layout, and every script here refused it
-  # with "no .mpr found" (field run, greenfield pilot, 2026-09-04). Same probe, one level down.
-  if [ "$count" -eq 0 ] && [ -d "$PROJECT_ROOT/app" ]; then
-    for f in "$PROJECT_ROOT"/app/*.mpr; do
-      [ -e "$f" ] || continue
-      count=$((count + 1))
-      found="$f"
-    done
-  fi
 
   if [ "$count" -eq 0 ]; then
     echo "ERROR: no .mpr found in $PROJECT_ROOT" >&2
@@ -92,65 +52,7 @@
 }
 
 # ---------------------------------------------------------------------------
-# find_model_dir — echo the directory that holds the .mpr AND its mprcontents/.
-#
-# WHY THIS EXISTS (2026-08-31, field-found on a dashboard-publishing migration).
-# A Mendix model is two things in ONE directory: `Project.mpr` and `mprcontents/`.
-# On a single-tree checkout that directory happens to equal $PROJECT_ROOT, so every
-# script here simply said $PROJECT_ROOT and was right by accident. On a two-tree
-# checkout — repo at the root, `mxcli new` app under `app/` — it is not, and
-# $PROJECT_ROOT points at a directory containing neither file.
-#
-# The failure was silent and total. snapshot-mpr.sh globbed `$PROJECT_ROOT/*.mpr`,
-# matched nothing, copied nothing, printed "mpr snapshot ok", and pruned the older
-# (equally empty) snapshots. exec.sh then ran twelve execs behind a crash-net that
-# held zero bytes; the first gate failure tried to auto-restore, found a snapshot
-# with no mprcontents/, and left the broken model on disk while reporting the
-# restore path. The same wrong root also drove exec.sh's "PROJECT IS IN v1
-# SINGLE-FILE FORMAT — Studio Pro WILL crash" warning, which fired after every
-# successful exec on a perfectly healthy v2 model.
-#
-# Resolve from the .mpr itself (which honours MPR_FILE) instead of from the repo.
-find_model_dir() {
-  local mpr
-  mpr=$(find_mpr) || return 1
-  (cd "$(dirname "$mpr")" && pwd)
-}
-
-# ---------------------------------------------------------------------------
-# mxtk_platform — "macos" | "windows" | "linux".
-#
-# WHY THIS EXISTS (2026-08-25). Everything below used to assume macOS: Studio Pro
-# was looked for at /Applications/*.app and Java at /usr/libexec/java_home. Under
-# Git Bash on Windows both lookups return nothing, so exec.sh's gate guard
-# `[ -x "$MXBUILD" ] && [ -x "$JAVA_EXE" ]` was false on every run and the whole
-# mxbuild block was skipped. The gate reported `skipped` — honestly, it was built
-# "three states, not two" for exactly this reason — but nobody reads a skip as a
-# problem, so every MDL exec on a Windows machine went unverified. That is the
-# BSON-corruption class iterative-build-loop.md:243 says mxbuild is the ONLY
-# reliable detector for. Found during a Windows training round.
-#
-# $OSTYPE is set by the shell; `uname -s` is the fallback for shells that do not
-# export it. Git Bash reports MINGW64_NT-*, MSYS2 reports MSYS_NT-*.
-# ---------------------------------------------------------------------------
-mxtk_platform() {
-  case "${OSTYPE:-}" in
-    darwin*)            echo macos   ; return ;;
-    msys*|cygwin*|win*) echo windows ; return ;;
-  esac
-  case "$(uname -s 2>/dev/null)" in
-    Darwin)                    echo macos   ;;
-    MINGW*|MSYS*|CYGWIN*|Windows*) echo windows ;;
-    *)                         echo linux   ;;
-  esac
-}
-
-# ---------------------------------------------------------------------------
-# find_sp_app — newest installed Studio Pro root.
-#
```

- bin/build-plan-status.sh — STALE: identical to shipped 2b4ef35 (2026-08-19); fix: bin/sync-project.sh <project-root> --upgrade-bin build-plan-status.sh

- bin/check-design-portability.sh — STALE: identical to shipped e3ee6fb (2026-08-26); fix: bin/sync-project.sh <project-root> --upgrade-bin check-design-portability.sh

- bin/check-page-shell.sh — STALE: identical to shipped 7149145 (2026-08-27); fix: bin/sync-project.sh <project-root> --upgrade-bin check-page-shell.sh

- bin/check-sp-health.sh — STALE: identical to shipped ffff50e (2026-08-04); fix: bin/sync-project.sh <project-root> --upgrade-bin check-sp-health.sh

- bin/coherence-cadence.sh — STALE: identical to shipped 2b4ef35 (2026-08-19); fix: bin/sync-project.sh <project-root> --upgrade-bin coherence-cadence.sh

- bin/conformance-check.sh — STALE: identical to shipped 239af75 (2026-08-19); fix: bin/sync-project.sh <project-root> --upgrade-bin conformance-check.sh

## bin/exec.sh differs from shipped project-bin/exec.sh — LOCAL-FIX

Not byte-identical to any shipped version in toolkit history — a real local fix. Closest historical base: d33d23f (2026-08-04), 29 diff line(s) from this project's copy. Diff (shipped -> project), truncated at 120 lines:

```diff
--- shipped/project-bin/exec.sh
+++ project/bin/exec.sh
@@ -1,20 +1,19 @@
 #!/usr/bin/env bash
 # exec.sh — the guard chain around a model write.
 #
-#   concurrent-writer guard → module-brief advisory → mxcli check → snapshot → baseline → exec
-#   → mxbuild gate → auto-restore on regression → SP reopen
+#   concurrent-writer guard → snapshot → baseline → exec → mxbuild gate
+#   → auto-restore on regression → manual SP reopen
 #
 # Usage: ./bin/exec.sh <script.mdl>
 #
-# Overrides: FORCE_EXEC=1 (skip refusals), SKIP_CHECK=1 (skip the pre-exec
-#            mxcli check), SKIP_BASELINE=1 (skip pre-flight mxbuild),
+# Overrides: FORCE_EXEC=1 (skip refusals), SKIP_BASELINE=1 (skip pre-flight),
 #            MXBUILD_PATH=..., MENDIX_APP=..., MPR_FILE=...
 set -e
-_T0=$(date +%s)
 
 . "$(dirname "$0")/_common.sh"
 
 MPR="$(find_mpr)" || exit 1
+MXCLI_BIN="$(find_mxcli)" || exit 1
 MPR_BASE="$(basename "$MPR")"
 NAME="$(basename "$MPR" .mpr)"
 SCRIPT="${1:-}"
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
@@ -74,140 +67,27 @@
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
```

- bin/fixture-manifest.sh — STALE: identical to shipped 6e04418 (2026-08-18); fix: bin/sync-project.sh <project-root> --upgrade-bin fixture-manifest.sh

## bin/graph-sweep.sh differs from shipped project-bin/graph-sweep.sh — LOCAL-FIX

Not byte-identical to any shipped version in toolkit history — a real local fix. Closest historical base: 239af75 (2026-08-19), 6 diff line(s) from this project's copy. Diff (shipped -> project), truncated at 120 lines:

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
@@ -70,14 +47,10 @@
 
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
+# `stat -f` is BSD, `stat -c` is GNU coreutils (Linux, and Git Bash on Windows). Both forms
+# are tried. The third case matters most: if NEITHER works, MPR_MTIME is empty and the
+# freshness guard below reports "catalog is stale" against a blank mtime — a real fault
+# reported as the wrong fault. Fail on the read instead of comparing against nothing.
 MPR_MTIME="$(stat -c "%y" "$MPR" 2>/dev/null | cut -c1-19 | tr ' ' 'T')"
 [ -n "$MPR_MTIME" ] || MPR_MTIME="$(stat -f "%Sm" -t "%Y-%m-%dT%H:%M:%S" "$MPR" 2>/dev/null)"
 [ -n "$MPR_MTIME" ] || {
```

## bin/lint-gate.sh differs from shipped project-bin/lint-gate.sh — LOCAL-FIX

Not byte-identical to any shipped version in toolkit history — a real local fix. Closest historical base: 607c1b1 (2026-08-18), 18 diff line(s) from this project's copy. Diff (shipped -> project), truncated at 120 lines:

```diff
--- shipped/project-bin/lint-gate.sh
+++ project/bin/lint-gate.sh
@@ -30,27 +30,27 @@
 # sync-project.sh installs a missing _common.sh and REPORTS a locally-modified one rather than
 # overwriting it — deliberately, since projects harden their crash net. So every project that
 # has already tuned _common.sh would receive this script and have it die on line 1 with
-# "require_py: command not found". Measured on PROJECT-C before this fallback existed.
+# "require_py: command not found". Measured on WMS-Demo-main before this fallback existed.
 if [ -f "$(dirname "${BASH_SOURCE[0]}")/_common.sh" ]; then
   . "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
 fi
 if ! type require_py >/dev/null 2>&1; then
   require_py() {
     _c=""
-    for _c in python3 python py; do  # portability-ok: this IS the interpreter probe
+    for _c in python3 python py; do
       case "$(command -v "$_c" 2>/dev/null)" in *[Ww]indows[Aa]pps*) continue ;; esac
       if "$_c" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then
         PY="$_c"; export PY; return 0
       fi
     done
-    echo "lint-gate: Python 3 is required and was not found (tried python3, python, py)." >&2  # portability-ok: names in a diagnostic
+    echo "lint-gate: Python 3 is required and was not found (tried python3, python, py)." >&2
     exit 2
   }
 fi
 require_py
 
 # The .mpr is discovered, not hardcoded. A per-project default here is how this script
-# was previously un-promotable: it named PROJECT-C.mpr and silently linted nothing anywhere
+# was previously un-promotable: it named WMS-Demo.mpr and silently linted nothing anywhere
 # else (mxcli exits 0 on a missing project, so the gate reported a clean PASS).
 if [ -z "${MPR:-}" ]; then
   MPR="$(ls "$ROOT"/*.mpr 2>/dev/null | head -1)"
@@ -79,7 +79,13 @@
   esac
 done
 
-[ -x ./mxcli ] || { echo "lint-gate: ./mxcli not found in $ROOT" >&2; exit 2; }
+# _common.sh is sourced conditionally above, so find_mxcli may not exist here.
+if declare -F find_mxcli >/dev/null 2>&1; then
+  MXCLI_BIN="$(find_mxcli)" || exit 2
+else
+  MXCLI_BIN="./mxcli"
+  [ -x "$MXCLI_BIN" ] || { echo "lint-gate: ./mxcli not found in $ROOT" >&2; exit 2; }
+fi
 [ -e "$MPR" ]  || { echo "lint-gate: $MPR not found" >&2; exit 2; }
 
 # Build the --exclude list from the vendor file (comments and blanks stripped).
@@ -97,12 +103,12 @@
   cp "$LINT_JSON" "$OUT"
 else
   echo "==> linting $MPR${EXCLUDE:+ (excluding vendor modules)}"
-  # First run on a cold catalog can take MINUTES (measured: 717s on PROJECT-A, 2s warm) --
+  # First run on a cold catalog can take MINUTES (measured: 717s on VB-USI, 2s warm) --
   # the catalog rebuild dominates, not the lint. Do not treat a slow first run as a hang.
   if [ -n "$EXCLUDE" ]; then
-    ./mxcli lint -p "$MPR" -e "$EXCLUDE" --format json > "$OUT" 2>/dev/null
+    "$MXCLI_BIN" lint -p "$MPR" -e "$EXCLUDE" --format json > "$OUT" 2>/dev/null
   else
-    ./mxcli lint -p "$MPR" --format json > "$OUT" 2>/dev/null
+    "$MXCLI_BIN" lint -p "$MPR" --format json > "$OUT" 2>/dev/null
   fi
 fi
 [ -s "$OUT" ] || { echo "lint-gate: lint produced no output" >&2; exit 2; }
@@ -132,7 +138,7 @@
 #      documents but activities_for() hands back nothing.
 #   2. A hard Starlark crash: mxcli reports these as severity=error with an EMPTY
 #      module and a "Starlark rule error:" message prefix -- NOT as "_rule". Observed
-#      on PROJECT-E 2026-08-14: CONV018 died with '"page" struct has no .widgets
+#      on TFC-TCXGraphPOC 2026-08-14: CONV018 died with '"page" struct has no .widgets
 #      attribute'. Keying only on "_rule" meant the gate baselined a crashed rule as a
 #      legitimate error-severity finding and then reported PASS while CONV018 saw
 #      nothing at all. A crashed rule must never be ratcheted.
```

## bin/page-scope.sh differs from shipped project-bin/page-scope.sh — LOCAL-FIX

Not byte-identical to any shipped version in toolkit history — a real local fix. Closest historical base: a1e27d2 (2026-08-28), 18 diff line(s) from this project's copy. Diff (shipped -> project), truncated at 120 lines:

```diff
--- shipped/project-bin/page-scope.sh
+++ project/bin/page-scope.sh
@@ -49,6 +49,23 @@
 . "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
 cd "$PROJECT_ROOT" || exit 2
 
+# require_py lives in _common.sh, but this script must not assume a sibling of its own
+# vintage — this project's _common.sh predates it, so the script died on line 69 with
+# "require_py: command not found". Same fallback lint-gate.sh already carries.
+if ! type require_py >/dev/null 2>&1; then
+  require_py() {
+    _c=""
+    for _c in python3 python py; do
+      case "$(command -v "$_c" 2>/dev/null)" in *[Ww]indows[Aa]pps*) continue ;; esac
+      if "$_c" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then
+        PY="$_c"; export PY; return 0
+      fi
+    done
+    echo "page-scope: Python 3 is required and was not found (tried python3, python, py)." >&2
+    exit 2
+  }
+fi
+
 MODULES=""
 NO_ROLES=0
 while [ $# -gt 0 ]; do
```

- bin/restart-sp.sh — STALE: identical to shipped ffff50e (2026-08-04); fix: bin/sync-project.sh <project-root> --upgrade-bin restart-sp.sh

- bin/restore-mpr.sh — STALE: identical to shipped d33d23f (2026-08-04); fix: bin/sync-project.sh <project-root> --upgrade-bin restore-mpr.sh

- bin/review-module.sh — STALE: identical to shipped 239af75 (2026-08-19); fix: bin/sync-project.sh <project-root> --upgrade-bin review-module.sh

- bin/save-sp.sh — STALE: identical to shipped d33d23f (2026-08-04); fix: bin/sync-project.sh <project-root> --upgrade-bin save-sp.sh

- bin/snapshot-mpr.sh — STALE: identical to shipped d33d23f (2026-08-04); fix: bin/sync-project.sh <project-root> --upgrade-bin snapshot-mpr.sh

- bin/page-fidelity.js — STALE: identical to shipped fd103f0 (2026-08-27); fix: bin/sync-project.sh <project-root> --upgrade-bin page-fidelity.js

13 stale (one line each) · 5 local fix(es) (diffs above)
