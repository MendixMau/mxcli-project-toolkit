#!/usr/bin/env bash
# restore-mpr.sh — restore the .mpr + mprcontents/ from a snapshot-mpr.sh snapshot.
#
# Usage: ./bin/restore-mpr.sh [timestamp | snapshot path]    (defaults to the newest snapshot)
#   timestamp      a folder name under .mpr-snapshots/, e.g. 20261013-120000
#   snapshot path  absolute, or relative to the directory you call from
set -euo pipefail
. "$(dirname "$0")/_common.sh"

# Snapshots live under $PROJECT_ROOT; the model tree they restore INTO may not
# (two-tree checkout: app/ holds the .mpr and mprcontents/). Resolve both.
SNAP_DIR="$PROJECT_ROOT/.mpr-snapshots"

# Resolve the argument BEFORE the cd below (2026-10-13, field report via PR #309): the usage line
# promised [timestamp], but the argument was used as given after `cd "$MODEL_DIR"`, so a bare
# `20261013-120000` was looked up in the model directory and failed with "snapshot ... is missing
# App.mpr" — sending a recovering user to inspect a healthy snapshot. Order: a directory as given
# (absolute or caller-relative), else a folder of that name under $SNAP_DIR, else refuse by name.
SNAP=""
if [ -n "${1:-}" ]; then
  if [ -d "$1" ]; then
    SNAP="$(cd "$1" && pwd)"
  elif [ -d "$SNAP_DIR/$1" ]; then
    SNAP="$SNAP_DIR/$1"
  else
    echo "ERROR: no snapshot named '$1' in $SNAP_DIR (and no such directory from $(pwd))."
    NEWEST=$(ls -dt "$SNAP_DIR"/*/ 2>/dev/null | head -3) || true
    if [ -n "$NEWEST" ]; then
      echo "  Newest snapshots:"
      printf '%s\n' "$NEWEST" | while IFS= read -r d; do echo "    $(basename "$d")"; done
    fi
    exit 1
  fi
fi

MODEL_DIR="$(find_model_dir)" || exit 1
cd "$MODEL_DIR"

MPR_PATH="$(find_mpr)"
MPR="$(basename "$MPR_PATH")"

[ -n "$SNAP" ] || SNAP="$(ls -dt "$SNAP_DIR"/*/ 2>/dev/null | head -1)" || true
[ -z "$SNAP" ] && { echo "ERROR: no timestamped snapshots in $SNAP_DIR (a flat .mpr-only copy is not a snapshot — it has no mprcontents/ and restores to garbage)"; exit 1; }
[ ! -f "$SNAP/$MPR" ] && { echo "ERROR: snapshot $SNAP is missing $MPR"; exit 1; }

echo "Restoring from: $SNAP"

# Stage mprcontents/ in a temp dir and swap only on success. The obvious form,
#   rm -rf mprcontents && cp -r "$SNAP/mprcontents" mprcontents
# deletes first, and under `set -e` a failed cp aborts AFTER the delete — leaving
# no mprcontents/ at all and a project recoverable only from git.
if [ -d "$SNAP/mprcontents" ]; then
  SNAP_UNITS=$(find "$SNAP/mprcontents" -name '*.mxunit' 2>/dev/null | wc -l | tr -d ' ')
  TMP_MC="$MODEL_DIR/.mprcontents.restore.$$"
  rm -rf "$TMP_MC"
  if cp -r "$SNAP/mprcontents" "$TMP_MC"; then
    rm -rf mprcontents
    mv "$TMP_MC" mprcontents
    cp "$SNAP/$MPR" "$MPR"
    LIVE_UNITS=$(find mprcontents -name '*.mxunit' 2>/dev/null | wc -l | tr -d ' ')
    echo "  Restored: $MPR"
    if [ "$LIVE_UNITS" -eq "$SNAP_UNITS" ]; then
      echo "  Restored: mprcontents/ ($LIVE_UNITS units verified)"
    else
      echo "  ⚠  RESTORE INCOMPLETE: $LIVE_UNITS of $SNAP_UNITS units."
      echo "     Recover with: git checkout HEAD -- $MPR mprcontents/"
      exit 1
    fi
  else
    rm -rf "$TMP_MC"
    echo "  ⚠  RESTORE FAILED — working tree left untouched."
    echo "     Recover with: git checkout HEAD -- $MPR mprcontents/"
    exit 1
  fi
elif [ ! -d "$MODEL_DIR/mprcontents" ]; then
  # Mirror of the v1 arm in snapshot-mpr.sh. A snapshot with no mprcontents/ is the
  # index alone (refuse) ONLY when the live model has one. When neither has one the
  # model is v1 single-file and the .mpr IS the whole model. Without this arm the
  # fixed snapshotter produces v1 snapshots the restorer rejects, and exec.sh's
  # auto-restore on a failed gate would again silently do nothing.
  # Same discipline as the mprcontents/ branch above: verify, don't just copy and hope.
  # A v1 model has no unit count to check, so the assertion is the file itself landing
  # non-empty — the cheapest thing that still catches a truncated or failed copy.
  if cp "$SNAP/$MPR" "$MPR" && [ -s "$MPR" ]; then
    echo "  Restored: $MPR [v1 single-file — no mprcontents/ in model or snapshot]"
  else
    echo "  ⚠  RESTORE FAILED — could not copy $SNAP/$MPR, or it restored empty."
    echo "     Recover with: git checkout HEAD -- $MPR"
    exit 1
  fi
else
  echo "  ⚠  Snapshot has no mprcontents/ but the live model does — refusing to restore the index alone."
  echo "     Recover with: git checkout HEAD -- $MPR mprcontents/"
  exit 1
fi

# script-owners.sh's last-writer ledger described the model before this restore: mark it, so rows
# above the marker stop counting and its next replay check asks the model (DESCRIBE) instead.
# exec.sh's own rollback sets MXTK_RESTORE_SAME_LEDGER=1: that snapshot predates nothing recorded.
_SO_LEDGER="$PROJECT_ROOT/.claude/loop/script-owners/written.tsv"
if [ -f "$_SO_LEDGER" ] && [ "${MXTK_RESTORE_SAME_LEDGER:-0}" != 1 ]; then
  printf '%s\tRESTORE\t%s\n' "$(date +%s)" "$(basename "$SNAP")" >> "$_SO_LEDGER" || true
fi

echo "Restore complete. Verify with: ./mxcli docker check -p $MPR --no-update-widgets"
