**From:** tfc-tcxgraphpoc
**Date:** 2026-09-14
**Kind:** fix
**Field evidence:** installed toolkit scripts in tfc-tcxgraphpoc/bin that differ from the shipped copy — a local patch here is a fix that never traveled (how graph-sweep's stat bug got patched twice)
**Proposed target:** see per-item notes below

---

## bin/exec.sh differs from shipped project-bin/exec.sh — LOCAL-FIX

Not byte-identical to any shipped version in toolkit history — a real local fix. Closest historical base: d33d23f (2026-08-04), 567 diff line(s) from this project's copy. Diff (shipped -> project), truncated at 120 lines:

```diff
--- shipped/project-bin/exec.sh
+++ project/bin/exec.sh
@@ -1,704 +1,232 @@
 #!/usr/bin/env bash
-# exec.sh — the guard chain around a model write.
-#
-#   concurrent-writer guard → module-brief advisory → mxcli check → snapshot → baseline → exec
-#   → mxbuild gate → auto-restore on regression → SP reopen
-#
+# exec.sh — snapshot → exec → mx check gate → tell user to reopen SP
 # Usage: ./bin/exec.sh <script.mdl>
-#
-# Overrides: FORCE_EXEC=1 (skip refusals), SKIP_CHECK=1 (skip the pre-exec
-#            mxcli check), SKIP_BASELINE=1 (skip pre-flight mxbuild),
-#            MXBUILD_PATH=..., MENDIX_APP=..., MPR_FILE=...
+# Override: FORCE_EXEC=1 ./bin/exec.sh <script.mdl>  (skips guards — use only if you know why)
 set -e
-_T0=$(date +%s)
 
-. "$(dirname "$0")/_common.sh"
-
-MPR="$(find_mpr)" || exit 1
-MPR_BASE="$(basename "$MPR")"
-NAME="$(basename "$MPR" .mpr)"
-SCRIPT="${1:-}"
+SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
+PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
+MPR="$PROJECT_ROOT/TFC-TCXGraphPOC.mpr"
+SCRIPT="$1"
+
+# Resolve a working, native `mx` binary for the model-check gate.
+# `mx check` (not mxbuild --target=deploy) is used deliberately: it's the
+# lightweight validator (loads + checks the model, no deployment packaging),
+# it has clean documented exit codes, and it sidesteps a standalone-invocation
+# assembly-loading issue seen with mxbuild's deploy target on this host.
+#
+# 2026-07-22 incident: the cached ~/.mxcli/mxbuild/*/modeler/mxbuild was a
+# Linux ELF binary (from a `setup mxbuild --force` for Docker use) sitting
+# unusable on this macOS/arm64 host — `exec format error`, but the old gate
+# code didn't verify the binary before trusting it, so a real MPR corruption
+# (BSON KeyNotFoundException from a 04-tfc-vendor-supplier.mdl exec) went
+# uncaught for several commits. Never trust a cached path without checking
+# it's actually a native, runnable Mach-O binary for this host's arch first.
+resolve_mx() {
+  local host_arch candidate file_out
+  host_arch="$(uname -m)"
+  # Newest Studio Pro version first (app bundle dirs sort naturally by
+  # version string), then fall back to whatever mxcli cached.
+  while IFS= read -r candidate; do
+    [[ -f "$candidate" ]] || continue
+    file_out="$(file -b "$candidate" 2>/dev/null || true)"
+    if [[ "$file_out" == *"Mach-O"* && "$file_out" == *"$host_arch"* ]]; then
+      echo "$candidate"
+      return 0
+    fi
+  done < <(
+    ls -d "/Applications/Mendix Studio Pro"*".app/Contents/modeler/mx" 2>/dev/null | sort -rV
+    ls ~/.mxcli/mxbuild/*/modeler/mx 2>/dev/null | sort -rV
+  )
+  return 1
+}
+MX_TOOL="$(resolve_mx || true)"
+FORCE="${FORCE_EXEC:-0}"
+LOCK="$PROJECT_ROOT/.mpr-snapshots/.exec.lock"
+mkdir -p "$(dirname "$LOCK")"
 
-if [ -z "$SCRIPT" ]; then
+if [[ -z "$SCRIPT" ]]; then
   echo "Usage: ./bin/exec.sh <script.mdl>"
   exit 1
 fi
 
 cd "$PROJECT_ROOT"
 
-# ── Concurrent-writer guard ──────────────────────────────────────────────────
-# The .mpr must have exactly ONE writer. Two mxcli/SP writers on the same file
-# silently clobber each other and have caused near-total module loss.
-# Override (at your own risk): FORCE_EXEC=1 ./bin/exec.sh <script>
-# The model tree (.mpr + mprcontents/) is NOT always $PROJECT_ROOT — on a two-tree
-# checkout the app lives under app/. Every mprcontents/ path below goes through
-# MODEL_DIR; see the find_model_dir header in _common.sh for what silently broke
-# when they did not.
-MODEL_DIR="$(find_model_dir 2>/dev/null || echo "$PROJECT_ROOT")"
-
-LOCK="$PROJECT_ROOT/.mpr-snapshots/.exec.lock"
-mkdir -p "$(dirname "$LOCK")"
-FORCE="${FORCE_EXEC:-0}"
-
-# 1. Studio Pro must not hold the project open (SP's in-memory model vs a direct
-#    file write = split-brain).
-if [ -f "$MPR.lock" ]; then
+# Guard 1: SP must not have the project open (split-brain = data loss).
+if [[ -f "$MPR.lock" ]]; then
   SP_PID=$(grep -oE '"ProcessId":[0-9]+' "$MPR.lock" 2>/dev/null | grep -oE '[0-9]+' || true)
-  if [ -n "$SP_PID" ] && kill -0 "$SP_PID" 2>/dev/null; then
-    echo "✗ Studio Pro has $NAME open (lock PID $SP_PID alive) — refusing exec (split-brain corruption risk)."
-    echo "  → Close the project in Studio Pro (or quit SP), then re-run."
+  if [[ -n "$SP_PID" ]] && kill -0 "$SP_PID" 2>/dev/null; then
+    echo "✗ Studio Pro has the project open (PID $SP_PID) — refusing exec (split-brain risk)."
+    echo "  → Close the project in Studio Pro, then re-run."
     echo "    Override (NOT recommended): FORCE_EXEC=1 ./bin/exec.sh $SCRIPT"
-    [ "$FORCE" = "1" ] || exit 1
+    [[ "$FORCE" == "1" ]] || exit 1
     echo "  (FORCE_EXEC set — proceeding despite open SP)"
-  elif [ -n "$SP_PID" ]; then
-    echo "  (stale $MPR_BASE.lock from dead PID $SP_PID — SP not actually open, proceeding)"
+  elif [[ -n "$SP_PID" ]]; then
+    echo "  (stale $MPR.lock from dead PID $SP_PID — SP not actually open, proceeding)"
   fi
 fi
 
-# 2. No other exec.sh run in progress (e.g. a second agent session).
-if [ -f "$LOCK" ]; then
+# Guard 2: No other exec.sh already running.
+if [[ -f "$LOCK" ]]; then
   OTHER=$(cat "$LOCK" 2>/dev/null || true)
-  if [ -n "$OTHER" ] && kill -0 "$OTHER" 2>/dev/null; then
-    echo "✗ Another exec is already running (PID $OTHER) — refusing to write the .mpr concurrently."
-    echo "  → Wait for it to finish. If it is stale (process dead): rm '$LOCK'"
+  if [[ -n "$OTHER" ]] && kill -0 "$OTHER" 2>/dev/null; then
```

## bin/restart-sp.sh differs from shipped project-bin/restart-sp.sh — LOCAL-FIX

Not byte-identical to any shipped version in toolkit history — a real local fix. Closest historical base: d33d23f (2026-08-04), 90 diff line(s) from this project's copy. Diff (shipped -> project), truncated at 120 lines:

```diff
--- shipped/project-bin/restart-sp.sh
+++ project/bin/restart-sp.sh
@@ -1,150 +1,20 @@
 #!/usr/bin/env bash
-# restart-sp.sh — kill this project's Studio Pro instance + runtime, reopen cleanly.
-#
-# Targets ONLY the SP process holding this project's .mpr, found via lsof — not
-# every SP on the machine. Two projects open at once is normal; killing the
-# wrong one loses unsaved work.
-#
-# macOS only (lsof/open/sample). See restart-sp.ps1 for the Windows port
-# (added 2026-08-04, far less proven — no `sample`-equivalent hang check).
-#
-# AUTO_SP=1 skips BOTH the reopen confirmation below and the post-launch hang
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
-
-if [ "${AUTO_SP:-0}" != "1" ]; then
-  read -r -p "This will force-quit and reopen Studio Pro (any unsaved work is lost). Continue? [y/N] " REPLY
-  case "$REPLY" in
-    [Yy]*) ;;
-    *) echo "Aborted — nothing was touched. (Override: AUTO_SP=1 ./bin/restart-sp.sh)"; exit 0 ;;
-  esac
-fi
-
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
-SP_PID=$(lsof -t "$MPR" 2>/dev/null || true)
-if [ -n "$SP_PID" ]; then
-  kill -TERM $SP_PID 2>/dev/null || true
-  for _ in $(seq 1 25); do
-    kill -0 $SP_PID 2>/dev/null || break
-    sleep 1
-  done
-  kill -9 $SP_PID 2>/dev/null || true
-fi
-
-echo "→ Killing child processes (mxcli + orphaned modeler helpers)..."
-[ -d "$DEPLOYMENT" ] && { lsof -t "$DEPLOYMENT" 2>/dev/null | xargs kill -9 2>/dev/null || true; }
-pkill -9 -f "mxcli" 2>/dev/null || true
-# The modeler spawns a deno helper per live-preview session that is not reliably
-# cleaned up on close; they accumulate across restarts. Safe to kill here since
-# we are already force-restarting SP.
-pkill -9 -f "Mendix Studio Pro.*tools/deno" 2>/dev/null || true
-
-echo "→ Waiting for SP to release $NAME..."
-for _ in $(seq 1 20); do
-  lsof -t "$MPR" >/dev/null 2>&1 || break
-  sleep 1
-done
-
-echo "→ Checking $(basename "$MPR").lock..."
-if [ -f "$MPR.lock" ]; then
-  LOCK_PID=$(grep -oE '"ProcessId":[0-9]+' "$MPR.lock" 2>/dev/null | grep -oE '[0-9]+' || true)
-  if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
-    echo "  (lock PID $LOCK_PID still alive — force-killing before removing lock)"
-    kill -9 "$LOCK_PID" 2>/dev/null || true
-  elif [ -n "$LOCK_PID" ]; then
-    echo "  (stale lock from dead PID $LOCK_PID — safe to remove)"
-  fi
-  chmod 644 "$MPR.lock" 2>/dev/null || true
-  rm -f "$MPR.lock"
-fi
-
-echo "→ Waiting for the MPR to be fully released..."
-for _ in $(seq 1 15); do
-  lsof "$MPR" >/dev/null 2>&1 || break
-  sleep 1
-done
-
-echo "→ Reopening $NAME..."
-# NOT `open -a "Mendix Version Selector" "$MPR"`: confirmed 2026-08-04 that this
-# fails silently on macOS. `open -a` without --args delivers the file path via
-# an "open documents" Apple Event, and the unified log shows tccd denying it —
-# Mendix Version Selector.app is missing the com.apple.security.automation.
-# apple-events entitlement in its own code signature. The process launches,
-# never receives the project path, and quits within seconds with no window.
-# That's a bug in Mendix's app bundle, not fixable via a permission toggle.
-#
-# Fix: skip Version Selector and launch the resolved Studio Pro app directly
-# with --args, which passes the path as a plain argv argument — no Apple Events
-# involved. find_sp_app already exists for exactly this (used by find_mxbuild);
-# it picks the newest installed version, same tradeoff mxbuild already accepts
-# — if this project needs an older version, set MENDIX_APP to pin it.
-SP_APP="$(find_sp_app)" || exit 1
-open -a "$SP_APP" --args "$MPR"
-
-if [ -x "$HEALTH_CHECK" ]; then
-  echo "→ Waiting for the new instance to claim the lock file..."
```

## bin/restore-mpr.sh differs from shipped project-bin/restore-mpr.sh — LOCAL-FIX

Not byte-identical to any shipped version in toolkit history — a real local fix. Closest historical base: d33d23f (2026-08-04), 72 diff line(s) from this project's copy. Diff (shipped -> project), truncated at 120 lines:

```diff
--- shipped/project-bin/restore-mpr.sh
+++ project/bin/restore-mpr.sh
@@ -1,56 +1,24 @@
 #!/usr/bin/env bash
-# restore-mpr.sh — restore the .mpr + mprcontents/ from a snapshot-mpr.sh snapshot.
-#
-# Usage: ./bin/restore-mpr.sh [timestamp]    (defaults to the newest snapshot)
+# Restore MPR + mprcontents from a snapshot.
+# Usage: bash bin/restore-mpr.sh [snapshot-dir]   (defaults to newest)
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
-
-SNAP="${1:-$(ls -dt "$SNAP_DIR"/*/ 2>/dev/null | head -1)}"
-[ -z "$SNAP" ] && { echo "ERROR: no timestamped snapshots in $SNAP_DIR (a flat .mpr-only copy is not a snapshot — it has no mprcontents/ and restores to garbage)"; exit 1; }
-[ ! -f "$SNAP/$MPR" ] && { echo "ERROR: snapshot $SNAP is missing $MPR"; exit 1; }
+MPR="$(ls *.mpr | head -1)"
+CONTENTS_DIR="mprcontents"
+SNAP_DIR=".mpr-snapshots"
+
+SNAP="${1:-$(ls -dt "$SNAP_DIR"/20* 2>/dev/null | head -1)}"
+[ -z "$SNAP" ] && { echo "ERROR: no snapshots in $SNAP_DIR"; exit 1; }
+[ ! -f "$SNAP/$MPR" ] && { echo "ERROR: snapshot missing $MPR"; exit 1; }
 
 echo "Restoring from: $SNAP"
-
-# Stage mprcontents/ in a temp dir and swap only on success. The obvious form,
-#   rm -rf mprcontents && cp -r "$SNAP/mprcontents" mprcontents
-# deletes first, and under `set -e` a failed cp aborts AFTER the delete — leaving
-# no mprcontents/ at all and a project recoverable only from git.
-if [ -d "$SNAP/mprcontents" ]; then
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
+cp "$SNAP/$MPR" "$MPR" && echo "  Restored: $MPR"
+if [ -d "$SNAP/$CONTENTS_DIR" ]; then
+  rm -rf "$CONTENTS_DIR"
+  cp -r "$SNAP/$CONTENTS_DIR" "$CONTENTS_DIR"
+  echo "  Restored: $CONTENTS_DIR"
 else
-  echo "  ⚠  Snapshot has no mprcontents/ — refusing to restore the index alone."
-  echo "     Recover with: git checkout HEAD -- $MPR mprcontents/"
-  exit 1
+  echo "  WARNING: snapshot has no $CONTENTS_DIR — MPR index only (may be incomplete)"
 fi
-
-echo "Restore complete. Verify with: ./mxcli docker check -p $MPR --no-update-widgets"
+echo "Restore complete."
```

## bin/snapshot-mpr.sh differs from shipped project-bin/snapshot-mpr.sh — LOCAL-FIX

Not byte-identical to any shipped version in toolkit history — a real local fix. Closest historical base: d33d23f (2026-08-04), 52 diff line(s) from this project's copy. Diff (shipped -> project), truncated at 120 lines:

```diff
--- shipped/project-bin/snapshot-mpr.sh
+++ project/bin/snapshot-mpr.sh
@@ -1,90 +1,18 @@
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
+# Snapshot MPR + mprcontents before a script batch. Prunes to 5 newest.
 set -euo pipefail
-. "$(dirname "$0")/_common.sh"
+cd "$(dirname "$0")/.."
 
-MODEL_DIR="$(find_model_dir)" || exit 1
+MPR="$(ls *.mpr | head -1)"
+CONTENTS_DIR="mprcontents"
+SNAP_DIR=".mpr-snapshots"
+TIMESTAMP=$(date +%Y%m%d-%H%M%S)
+DEST="$SNAP_DIR/$TIMESTAMP"
 
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
 mkdir -p "$DEST"
+cp "$MPR" "$DEST/$MPR"
+[ -d "$CONTENTS_DIR" ] && cp -r "$CONTENTS_DIR" "$DEST/$CONTENTS_DIR"
 
-MPR_COUNT=0
-for f in "$MODEL_DIR"/*.mpr; do
-  [ -e "$f" ] || continue
-  cp "$f" "$DEST/$(basename "$f")"
-  MPR_COUNT=$((MPR_COUNT + 1))
-done
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
-
-# Prune: keep the 5 newest timestamped dirs.
-ls -dt "$PROJECT_ROOT"/.mpr-snapshots/*/ 2>/dev/null | tail -n +6 | while read -r old; do
-  rm -rf "$old"
-done
-
-echo "mpr snapshot ok ($MPR_COUNT .mpr + $UNIT_COUNT units) — $(ls -d "$PROJECT_ROOT"/.mpr-snapshots/*/ 2>/dev/null | wc -l | tr -d ' ') kept in .mpr-snapshots/"
+echo "Snapshot saved: $DEST"
+ls -dt "$SNAP_DIR"/20* 2>/dev/null | tail -n +6 | while read -r old; do rm -rf "$old"; echo "Pruned: $old"; done
+echo "$(ls -d "$SNAP_DIR"/20* 2>/dev/null | wc -l | tr -d ' ') snapshot(s) kept"
```

0 stale (one line each) · 4 local fix(es) (diffs above)
