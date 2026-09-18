#!/usr/bin/env bash
# restore-mpr.sh — restore the .mpr + mprcontents/ from a snapshot-mpr.sh snapshot.
#
# Usage: ./bin/restore-mpr.sh [timestamp]    (defaults to the newest snapshot)
set -euo pipefail
. "$(dirname "$0")/_common.sh"

# Snapshots live under $PROJECT_ROOT; the model tree they restore INTO may not
# (two-tree checkout: app/ holds the .mpr and mprcontents/). Resolve both.
SNAP_DIR="$PROJECT_ROOT/.mpr-snapshots"
MODEL_DIR="$(find_model_dir)" || exit 1
cd "$MODEL_DIR"

MPR_PATH="$(find_mpr)"
MPR="$(basename "$MPR_PATH")"

SNAP="${1:-$(ls -dt "$SNAP_DIR"/*/ 2>/dev/null | head -1)}"
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
  cp "$SNAP/$MPR" "$MPR"
  echo "  Restored: $MPR [v1 single-file — no mprcontents/ in model or snapshot]"
else
  echo "  ⚠  Snapshot has no mprcontents/ but the live model does — refusing to restore the index alone."
  echo "     Recover with: git checkout HEAD -- $MPR mprcontents/"
  exit 1
fi

echo "Restore complete. Verify with: ./mxcli docker check -p $MPR --no-update-widgets"
