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
# The model tree is resolved with find_model_dir, NOT $PROJECT_ROOT: on a two-tree
# checkout (repo at the root, `mxcli new` app under app/) they are different
# directories, and globbing the repo root matched nothing while still printing
# "mpr snapshot ok" — see the find_model_dir header in _common.sh for the field
# incident. The snapshots themselves stay under $PROJECT_ROOT/.mpr-snapshots so
# they land in one gitignored place regardless of layout.
#
# Git commits at phase gates remain the real history — this only covers
# mid-session corruption between commits.
set -euo pipefail
. "$(dirname "$0")/_common.sh"

MODEL_DIR="$(find_model_dir)" || exit 1

# A producer guarantees its own output is ignored. This writes a FULL copy of the .mpr and
# every mprcontents unit, five deep — so a project that does not gitignore it commits the
# client's whole model several times over, and then reports thousands of phantom deletions
# the next time the rotation below prunes one.
#
# Measured on a MOC/PSSR app replacement, 2026-09-09: 2,089 snapshot files tracked, and
# `mxcli exec` then REFUSED to run, because exec.sh read the pruned snapshot as uncommitted
# model changes — this script's output blocking this script's own guard. It is written here
# rather than in init-project.sh on purpose: here it also reaches every project that already
# exists, on its next exec, instead of only the ones scaffolded after today.
if [ -d "$PROJECT_ROOT/.git" ] || [ -f "$PROJECT_ROOT/.git" ]; then
  GI="$PROJECT_ROOT/.gitignore"
  if ! { [ -f "$GI" ] && grep -qE '^/?\.mpr-snapshots/?$' "$GI"; }; then
    if [ -f "$GI" ] && [ -s "$GI" ] && [ -n "$(tail -c 1 "$GI")" ]; then printf '\n' >> "$GI"; fi
    printf '# Pre-exec model snapshots (project-bin/snapshot-mpr.sh). A full .mpr + mprcontents\n' >> "$GI"
    printf '# copy per exec, five kept. Never committed: it is the client model, several times over.\n' >> "$GI"
    printf '/.mpr-snapshots/\n' >> "$GI"
    printf 'snapshot-mpr: added /.mpr-snapshots/ to .gitignore (it was not ignored).\n' >&2
  fi
fi

mkdir -p "$PROJECT_ROOT/.mpr-snapshots"
DEST="$PROJECT_ROOT/.mpr-snapshots/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$DEST"

MPR_COUNT=0
for f in "$MODEL_DIR"/*.mpr; do
  [ -e "$f" ] || continue
  cp "$f" "$DEST/$(basename "$f")"
  MPR_COUNT=$((MPR_COUNT + 1))
done
[ -d "$MODEL_DIR/mprcontents" ] && cp -r "$MODEL_DIR/mprcontents" "$DEST/mprcontents"

UNIT_COUNT=$(find "$DEST/mprcontents" -name '*.mxunit' 2>/dev/null | wc -l | tr -d ' ')

# An empty snapshot is worse than no snapshot: exec.sh proceeds believing it has a
# net, and the prune below has already thrown away the older ones. Refuse loudly,
# and refuse BEFORE pruning, so a bad resolve cannot destroy good history.
if [ "$MPR_COUNT" -eq 0 ]; then
  rm -rf "$DEST"
  echo "✗ snapshot FAILED: no .mpr found in $MODEL_DIR — refusing to record an empty snapshot." >&2
  echo "  Set MPR_FILE=<path>.mpr (relative to $PROJECT_ROOT) so the model tree resolves." >&2
  exit 1
fi
if [ "$UNIT_COUNT" -eq 0 ]; then
  rm -rf "$DEST"
  echo "✗ snapshot FAILED: $MODEL_DIR has no mprcontents/*.mxunit — .mpr alone restores to garbage." >&2
  echo "  If the model is genuinely v1 single-file, commit it and skip the snapshot net." >&2
  exit 1
fi

# Prune: keep the 5 newest timestamped dirs.
ls -dt "$PROJECT_ROOT"/.mpr-snapshots/*/ 2>/dev/null | tail -n +6 | while read -r old; do
  rm -rf "$old"
done

echo "mpr snapshot ok ($MPR_COUNT .mpr + $UNIT_COUNT units) — $(ls -d "$PROJECT_ROOT"/.mpr-snapshots/*/ 2>/dev/null | wc -l | tr -d ' ') kept in .mpr-snapshots/"
