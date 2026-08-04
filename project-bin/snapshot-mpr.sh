#!/usr/bin/env bash
# snapshot-mpr.sh — rotating .mpr safety net.
#
# Snapshots every *.mpr AND mprcontents/ into a timestamped subdirectory of
# .mpr-snapshots/, keeping the 5 newest. Run BEFORE every `mxcli exec`;
# bin/exec.sh does it for you.
#
# BOTH parts or nothing. An MPR is a SQLite index (.mpr) plus the BSON units
# that hold the actual model (mprcontents/). A snapshot of either alone restores
# to garbage. Ad-hoc `cp Project.mpr Project.mpr.backup` is exactly that mistake
# and is why this script exists.
#
# Git commits at phase gates remain the real history — this only covers
# mid-session corruption between commits.
set -euo pipefail
. "$(dirname "$0")/_common.sh"
cd "$PROJECT_ROOT"

mkdir -p .mpr-snapshots
DEST=".mpr-snapshots/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$DEST"

for f in *.mpr; do
  [ -e "$f" ] || continue
  cp "$f" "$DEST/$f"
done
[ -d mprcontents ] && cp -r mprcontents "$DEST/mprcontents"

# Prune: keep the 5 newest timestamped dirs.
ls -dt .mpr-snapshots/*/ 2>/dev/null | tail -n +6 | while read -r old; do
  rm -rf "$old"
done

echo "mpr snapshot ok (.mpr + mprcontents/) — $(ls -d .mpr-snapshots/*/ 2>/dev/null | wc -l | tr -d ' ') kept in .mpr-snapshots/"
