#!/usr/bin/env bash
# exec.sh — the guard chain around a model write.
#
#   concurrent-writer guard → snapshot → baseline → exec → mxbuild gate
#   → auto-restore on regression → manual SP reopen
#
# Usage: ./bin/exec.sh <script.mdl>
#
# Overrides: FORCE_EXEC=1 (skip refusals), SKIP_BASELINE=1 (skip pre-flight),
#            MXBUILD_PATH=..., MENDIX_APP=..., MPR_FILE=...
set -e

. "$(dirname "$0")/_common.sh"

MPR="$(find_mpr)" || exit 1
MPR_BASE="$(basename "$MPR")"
NAME="$(basename "$MPR" .mpr)"
SCRIPT="${1:-}"

if [ -z "$SCRIPT" ]; then
  echo "Usage: ./bin/exec.sh <script.mdl>"
  exit 1
fi

cd "$PROJECT_ROOT"

# ── Concurrent-writer guard ──────────────────────────────────────────────────
# The .mpr must have exactly ONE writer. Two mxcli/SP writers on the same file
# silently clobber each other and have caused near-total module loss.
# Override (at your own risk): FORCE_EXEC=1 ./bin/exec.sh <script>
LOCK="$PROJECT_ROOT/.mpr-snapshots/.exec.lock"
mkdir -p "$(dirname "$LOCK")"
FORCE="${FORCE_EXEC:-0}"

# 1. Studio Pro must not hold the project open (SP's in-memory model vs a direct
#    file write = split-brain).
if [ -f "$MPR.lock" ]; then
  SP_PID=$(grep -oE '"ProcessId":[0-9]+' "$MPR.lock" 2>/dev/null | grep -oE '[0-9]+' || true)
  if [ -n "$SP_PID" ] && kill -0 "$SP_PID" 2>/dev/null; then
    echo "✗ Studio Pro has $NAME open (lock PID $SP_PID alive) — refusing exec (split-brain corruption risk)."
    echo "  → Close the project in Studio Pro (or quit SP), then re-run."
    echo "    Override (NOT recommended): FORCE_EXEC=1 ./bin/exec.sh $SCRIPT"
    [ "$FORCE" = "1" ] || exit 1
    echo "  (FORCE_EXEC set — proceeding despite open SP)"
  elif [ -n "$SP_PID" ]; then
    echo "  (stale $MPR_BASE.lock from dead PID $SP_PID — SP not actually open, proceeding)"
  fi
fi

# 2. No other exec.sh run in progress (e.g. a second agent session).
if [ -f "$LOCK" ]; then
  OTHER=$(cat "$LOCK" 2>/dev/null || true)
  if [ -n "$OTHER" ] && kill -0 "$OTHER" 2>/dev/null; then
    echo "✗ Another exec is already running (PID $OTHER) — refusing to write the .mpr concurrently."
    echo "  → Wait for it to finish. If it is stale (process dead): rm '$LOCK'"
    exit 1
  fi
fi

# 3. No stray raw `mxcli exec` from another session.
if pgrep -fl "mxcli exec" 2>/dev/null | grep -qv "$$"; then
  echo "✗ A raw 'mxcli exec' is already running elsewhere — refusing to write concurrently."
  [ "$FORCE" = "1" ] || exit 1
fi

# 4. Uncommitted model changes. The snapshot taken below would not cover them,
#    so a failed gate would auto-restore to a state pre-dating those changes and
#    silently lose work.
MPR_DIRTY=$(git status --porcelain "$MPR_BASE" mprcontents/ 2>/dev/null | grep -v "^$" || true)
if [ -n "$MPR_DIRTY" ]; then
  echo "✗ Uncommitted model changes — refusing exec to prevent snapshot regression."
  echo ""
  echo "$MPR_DIRTY" | sed 's/^/    /'
  echo ""
  echo "  → git add $MPR_BASE mprcontents/ && git commit -m 'Commit model changes before exec'"
  echo "  Override (accepts silent-loss risk): FORCE_EXEC=1 ./bin/exec.sh $SCRIPT"
  [ "$FORCE" = "1" ] || exit 1
  echo "  (FORCE_EXEC set — proceeding despite uncommitted changes)"
fi

echo $$ > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
# ─────────────────────────────────────────────────────────────────────────────

# ── Build log (auto) ─────────────────────────────────────────────────────────
# One line per exec, written by the script rather than by hand, so it stays true
# when someone forgets. Added after cross-workstream collisions where a session
# left the model non-building and it was only found by running something else.
BUILD_LOG="$PROJECT_ROOT/docs/BUILD-LOG.md"
log_build() {   # $1=status  $2=detail
  mkdir -p "$(dirname "$BUILD_LOG")"
  [ -f "$BUILD_LOG" ] || cat > "$BUILD_LOG" <<'HDR'
# Build log — auto-appended by bin/exec.sh

One line per exec against the model. Written by the script, not by hand, so it is
true even when someone forgets. Read this before assuming the model builds.

| when | script | result | detail |
|---|---|---|---|
HDR
  printf '| %s | `%s` | %s | %s |\n' \
    "$(date '+%m-%d %H:%M')" "$(basename "$SCRIPT")" "$1" "$2" >> "$BUILD_LOG"
}

echo "→ Snapshotting model..."
./bin/snapshot-mpr.sh

MXBUILD="$(find_mxbuild)" || true
JAVA_HOME=$(/usr/libexec/java_home 2>/dev/null || true)
JAVA_EXE="${JAVA_HOME}/bin/java"

err_count() {  # $1=errors json
  python3 -c "import json;d=json.load(open('$1'));print(len([x for x in d.get('problems',[]) if x.get('severity')=='Error']))" 2>/dev/null || echo "?"
}
err_codes() {
  python3 -c "import json;d=json.load(open('$1'));print(','.join(sorted({x.get('errorCode','?') for x in d.get('problems',[]) if x.get('severity')=='Error'})))" 2>/dev/null || echo "?"
}
err_set() {
  python3 -c "import json;d=json.load(open('$1'));print('|'.join(sorted(x.get('message','') for x in d.get('problems',[]) if x.get('severity')=='Error')))" 2>/dev/null || echo ""
}

# ── Pre-flight baseline ──────────────────────────────────────────────────────
# Capture the CURRENT error set before touching anything, so the gate can tell
# "this script broke it" from "it was already broken". Costs one extra mxbuild;
# skip with SKIP_BASELINE=1 when you know the tree is clean.
BASELINE_SET=""
if [ "${SKIP_BASELINE:-0}" != "1" ] && [ -x "$MXBUILD" ] && [ -x "$JAVA_EXE" ]; then
  echo "→ Pre-flight: checking whether the model already has errors..."
  _BF=$(mktemp /tmp/mxbuild-baseline.XXXXXX)
  "$MXBUILD" --java-home="$JAVA_HOME" --java-exe-path="$JAVA_EXE" \
             --write-errors="$_BF" --target=deploy "$MPR" >/dev/null 2>&1 || true
  BASELINE_SET=$(err_set "$_BF")
  _BC=$(err_count "$_BF"); _BCODES=$(err_codes "$_BF")
  rm -f "$_BF"
  if [ "$_BC" != "0" ]; then
    echo "  ⚠  Model ALREADY has $_BC error(s) [$_BCODES] before this script runs."
    echo "     Not yours. The gate will keep your changes if you add nothing new."
  else
    echo "  ✓ baseline clean"
  fi
fi

# ── Execute ──────────────────────────────────────────────────────────────────
# The exit status is CAPTURED, not allowed to trip `set -e`.
#
# This is the fix for a defect that fired three times before anyone traced it:
# with a bare `./mxcli exec`, a mid-script failure aborted exec.sh instantly —
# skipping the mxbuild gate, the restore, and the build-log entry. And mxcli is
# NOT transactional across statements, so every statement before the failing one
# was already applied. The result was live, ungated, unlogged model changes,
# arrived at by the guard chain exiting through the one path with no guards on
# it. A failed exec is precisely when the gate matters most.
echo "→ Executing $SCRIPT..."
EXEC_STATUS=0
./mxcli exec "$SCRIPT" -p "$MPR" || EXEC_STATUS=$?

if [ "$EXEC_STATUS" -ne 0 ]; then
  echo ""
  echo "  ✗ mxcli exec exited $EXEC_STATUS — PARTIAL APPLICATION LIKELY."
  echo "    mxcli is not transactional across statements: everything before the"
  echo "    failing statement is already in the model. Running the gate anyway."
fi

echo ""
echo "→ Running mxbuild model check (catches BSON corruption before SP opens)..."
echo "  (mxbuild: $MXBUILD)"

# Three states, not two. "did not fail" is not "passed": the gate can be
# skipped entirely (no mxbuild) or produce an unparseable result, and reporting
# either as clean is the same false-green this script exists to prevent.
GATE_STATE="not-run"   # not-run | skipped | unverified | pass | fail

if [ -x "$MXBUILD" ] && [ -x "$JAVA_EXE" ]; then
  ERRORS_FILE=$(mktemp /tmp/mxbuild-errors.XXXXXX)
  # Capture status directly. The previous form was
  #     MXBUILD_OUT=$(... ) || true ; MXBUILD_EXIT=${PIPESTATUS[0]:-$?}
  # where `|| true` had already reset the status to 0, so MXBUILD_EXIT was
  # always 0 and the "mxbuild failed to run" branch below was unreachable.
  MXBUILD_EXIT=0
  MXBUILD_OUT=$("$MXBUILD" \
    --java-home="$JAVA_HOME" \
    --java-exe-path="$JAVA_EXE" \
    --write-errors="$ERRORS_FILE" \
    --target=deploy \
    "$MPR" 2>&1) || MXBUILD_EXIT=$?

  if [ -f "$ERRORS_FILE" ] && [ -s "$ERRORS_FILE" ]; then
    CE_COUNT=$(err_count "$ERRORS_FILE")
    if [ "$CE_COUNT" = "?" ]; then
      GATE_STATE="unverified"
      echo "  ⚠  mxbuild errors file could not be parsed — check manually."
      echo "$MXBUILD_OUT" | grep -v "^$\|icon\|Microsoft\|Assembly\|__" | head -10 || true
    elif [ "$CE_COUNT" = "0" ]; then
      # mxbuild ALWAYS writes an errors file, even on success ({"problems":[]}).
      # A guard that tested only "file is non-empty" therefore took the restore
      # branch on a clean build and rolled back good work, while printing
      # "0 error(s) found". Test the parsed count, never the file's existence.
      GATE_STATE="pass"
      echo "  ✓ mxbuild: 0 errors — model is clean."
      [ "$EXEC_STATUS" -eq 0 ] && log_build "✅ applied" "mxbuild clean"
    else
      # ── Delta gate ─────────────────────────────────────────────────────────
      # A shared model means another workstream can leave it non-building; an
      # absolute "zero errors" gate would then block every good script forever.
      POST_SET=$(err_set "$ERRORS_FILE")
      if [ -n "$BASELINE_SET" ] && [ "$BASELINE_SET" = "$POST_SET" ]; then
        GATE_STATE="pass"
        KEEP_CODES=$(err_codes "$ERRORS_FILE")
        echo "  ⚠  mxbuild: $CE_COUNT error(s) — IDENTICAL to the pre-flight baseline."
        echo "     Pre-existing [$KEEP_CODES], not introduced by this script. KEEPING the changes."
        echo "     The model still will not deploy until those are cleared in Studio Pro."
        [ "$EXEC_STATUS" -eq 0 ] && log_build "⚠️ applied (dirty model)" "no new errors; pre-existing $KEEP_CODES still blocks deploy"
        cp "$ERRORS_FILE" "$PROJECT_ROOT/.mpr-snapshots/last-mxbuild-errors.json"
        rm -f "$ERRORS_FILE"
      else
        GATE_STATE="fail"
        echo "  ✗ mxbuild: $CE_COUNT error(s) found — restoring snapshot to avoid loading a corrupt MPR."
        CE_CODES=$(err_codes "$ERRORS_FILE")
        NEWEST_SNAP=$(ls -dt "$PROJECT_ROOT/.mpr-snapshots"/[0-9]*/ 2>/dev/null | head -1)
        if [ -n "$NEWEST_SNAP" ] && [ -f "$NEWEST_SNAP/$MPR_BASE" ]; then
          # Stage then swap — see restore-mpr.sh for why deleting first is fatal.
          SNAP_UNITS=$(find "$NEWEST_SNAP/mprcontents" -name '*.mxunit' 2>/dev/null | wc -l | tr -d ' ')
          if [ "$SNAP_UNITS" -gt 0 ]; then
            TMP_MC="$PROJECT_ROOT/.mprcontents.restore.$$"
            rm -rf "$TMP_MC"
            if cp -r "$NEWEST_SNAP/mprcontents" "$TMP_MC"; then
              rm -rf "$PROJECT_ROOT/mprcontents"
              mv "$TMP_MC" "$PROJECT_ROOT/mprcontents"
              cp "$NEWEST_SNAP/$MPR_BASE" "$MPR"
              LIVE_UNITS=$(find "$PROJECT_ROOT/mprcontents" -name '*.mxunit' 2>/dev/null | wc -l | tr -d ' ')
              if [ "$LIVE_UNITS" -eq "$SNAP_UNITS" ]; then
                echo "  → Auto-restored from: $NEWEST_SNAP ($LIVE_UNITS units verified)"
              else
                echo "  ⚠  RESTORE INCOMPLETE: $LIVE_UNITS of $SNAP_UNITS units."
                echo "     Recover with: git checkout HEAD -- $MPR_BASE mprcontents/"
              fi
            else
              rm -rf "$TMP_MC"
              echo "  ⚠  RESTORE FAILED — working tree left untouched, model may be mid-write."
              echo "     Recover with: git checkout HEAD -- $MPR_BASE mprcontents/"
            fi
          else
            echo "  ⚠  Snapshot has no mprcontents/ — refusing to restore from it."
            echo "     Recover with: git checkout HEAD -- $MPR_BASE mprcontents/"
          fi
        fi
        python3 -c "import json; d=json.load(open('$ERRORS_FILE')); [print('  ', e.get('errorCode','?'), e.get('message','')) for e in d.get('problems',[]) if e.get('severity')=='Error']" 2>/dev/null || true
        cp "$ERRORS_FILE" "$PROJECT_ROOT/.mpr-snapshots/last-mxbuild-errors.json"
        echo "  → Full error detail: .mpr-snapshots/last-mxbuild-errors.json"

        # ── Whose error is it? ───────────────────────────────────────────────
        # The model is now back at its pre-exec state. If it STILL fails, the
        # error predates this script, which was merely the first thing to hit
        # it. Costs one extra mxbuild, only on the failure path.
        BASE_ERRS=$(mktemp /tmp/mxbuild-base.XXXXXX)
        "$MXBUILD" --java-home="$JAVA_HOME" --java-exe-path="$JAVA_EXE" \
                   --write-errors="$BASE_ERRS" --target=deploy "$MPR" >/dev/null 2>&1 || true
        BASE_COUNT=$(err_count "$BASE_ERRS"); BASE_CODES=$(err_codes "$BASE_ERRS")
        rm -f "$BASE_ERRS"

        echo ""
        if [ "$BASE_COUNT" != "0" ] && [ "$BASE_COUNT" != "?" ]; then
          echo "  ⚠  PRE-EXISTING: the restored model already fails with $BASE_COUNT error(s) [$BASE_CODES]."
          echo "     This script is NOT the cause. Nothing will exec until that is cleared."
          case "$BASE_CODES" in
            *CE0066*|*CE0463*)
              echo "     Those codes are Studio-Pro-only fixes:"
              echo "       CE0066  security overview → update entity access"
              echo "       CE0463  right-click a widget → Update all widgets" ;;
          esac
          log_build "🚫 blocked" "PRE-EXISTING $BASE_CODES — not caused by this script; needs Studio Pro"
        else
          echo "  → The restored model builds clean, so this script introduced [$CE_CODES]."
          log_build "❌ gate failed" "$CE_COUNT error(s): $CE_CODES — script rolled back"
        fi
        rm -f "$ERRORS_FILE"
      fi
    fi
  elif [ "$MXBUILD_EXIT" -ne 0 ]; then
    GATE_STATE="fail"
    echo "  ✗ mxbuild failed to run (exit $MXBUILD_EXIT) — gate could not verify the model."
    echo "$MXBUILD_OUT" | grep -v "^$\|icon\|Microsoft\|Assembly\|__" | head -20 || true
    echo "  → Snapshot preserved. Open in SP to verify manually before proceeding."
    log_build "❌ gate could not run" "mxbuild exit $MXBUILD_EXIT"
  else
    GATE_STATE="pass"
    echo "  ✓ mxbuild: 0 errors — model is clean."
  fi
  rm -f "$ERRORS_FILE"
else
  GATE_STATE="skipped"
  echo "  ✗ mxbuild or java not found — GATE SKIPPED. Paths checked:"
  echo "    MXBUILD=$MXBUILD (exists+exec: $([ -x "$MXBUILD" ] && echo YES || echo NO))"
  echo "    JAVA_EXE=$JAVA_EXE (exists+exec: $([ -x "$JAVA_EXE" ] && echo YES || echo NO))"
  echo "  → Override with MXBUILD_PATH=/path/to/mxbuild, or MENDIX_APP=/Applications/....app"
  echo "  → Verify manually in SP before proceeding."
fi

# ── v1 leak guard ────────────────────────────────────────────────────────────
# `mxcli exec` repacks v2 (small .mpr + mprcontents/ across thousands of
# .mxunit files) into v1 (one large SQLite blob). A FAILED gate restores v2; a
# SUCCESSFUL one never did, so every clean exec silently left the repo in v1:
#   * `git add mprcontents/` fails — the directory is gone
#   * `git add -A` commits a ~100 MB blob and deletes thousands of tracked files
#   * Studio Pro refuses to open, throwing InvalidOperationException at
#     LibGit2RepositoryProvider.WriteBaseFile, because git HEAD describes files
#     that no longer exist on disk
# mxbuild validates the model, not the on-disk format, so the gate passes and
# nothing looks wrong until git or SP is touched.
if [ ! -d "$PROJECT_ROOT/mprcontents" ]; then
  MPR_BYTES=$(wc -c < "$MPR" | tr -d ' ')
  echo ""
  echo "  ⚠️  PROJECT IS IN v1 SINGLE-FILE FORMAT — DO NOT COMMIT AS-IS."
  echo ""
  echo "     mprcontents/ is absent and $MPR_BASE is $(( MPR_BYTES / 1048576 )) MB."
  echo "     mxcli exec repacked v2 -> v1. Expected after a successful exec;"
  echo "     it is not corruption and no work has been lost."
  echo ""
  if git -C "$PROJECT_ROOT" ls-tree -r HEAD --name-only 2>/dev/null | grep -q '\.mxunit$'; then
    echo "     git HEAD still describes the v2 tree, so disk and git disagree."
    echo "     Studio Pro WILL crash on open in this state (WriteBaseFile null ref)."
    echo ""
    echo "     Pick one:"
    echo "       • Open in Studio Pro and save — SP writes v2 natively. Best option;"
    echo "         first make git agree with disk, or SP cannot open at all."
    echo "       • Discard this exec:  git checkout HEAD -- $MPR_BASE mprcontents/"
  else
    echo "     git HEAD is also v1, so git and disk agree — SP will open."
    echo "     Save in SP to get back to v2 before the next commit."
  fi
  echo ""
fi

# ── Verdict ──────────────────────────────────────────────────────────────────
# A non-zero exec is never reported as success, even when the gate is clean:
# the model then holds a PARTIAL script, which builds fine and is still wrong.
if [ "$EXEC_STATUS" -ne 0 ]; then
  echo ""
  echo "✗ mxcli exec FAILED (exit $EXEC_STATUS) — $NAME holds a PARTIAL application."
  case "$GATE_STATE" in
    pass)
      echo "  The gate passed, so what landed is structurally valid — but it is only"
      echo "  the statements up to the failure. Review the model before continuing."
      log_build "⚠️ PARTIAL" "mxcli exec exit $EXEC_STATUS; gate passed; statements before the failure are live"
      ;;
    fail)
      echo "  The gate also failed; see above for whether it was restored."
      ;;
    *)
      # Never say "clean" here. The gate did not run, so nothing has looked at
      # what landed — and a partial application is exactly when you need it to.
      echo "  AND THE GATE DID NOT RUN ($GATE_STATE) — nothing has verified what landed."
      echo "  Do not treat this as applied. Install mxbuild or set MXBUILD_PATH, then"
      echo "  re-check the model before continuing."
      log_build "⚠️ PARTIAL, UNVERIFIED" "mxcli exec exit $EXEC_STATUS; gate $GATE_STATE; model not verified"
      ;;
  esac
  exit "$EXEC_STATUS"
fi

if [ "$GATE_STATE" = "fail" ]; then
  exit 1
fi

if [ "$GATE_STATE" != "pass" ]; then
  echo ""
  echo "⚠️  Script applied to $MPR_BASE, but THE GATE DID NOT RUN ($GATE_STATE)."
  echo "    Nothing has verified the model. Verify in Studio Pro before continuing."
  log_build "⚠️ applied, UNVERIFIED" "gate $GATE_STATE — model not verified"
  exit 0
fi

echo ""
echo "✓ Script applied to $MPR_BASE."
echo ""
echo "  ⚠️  Studio Pro needs a restart to pick up these changes."
echo "      Close $NAME in Studio Pro, reopen it, then click Run Locally."
echo "      Or: ./bin/restart-sp.sh"
echo ""
