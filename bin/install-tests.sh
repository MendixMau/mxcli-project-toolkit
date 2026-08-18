#!/usr/bin/env bash
# install-tests.sh — copy the journey-proof verification engine into a project.
#
# WHY THIS IS A SEPARATE SCRIPT AND NOT A BLOCK IN init-project.sh
# The engine is .js into a nested tests/e2e/, while init-project.sh's installer loop handles
# flat shell scripts into bin/. Folding it in means editing init-project.sh and sync-project.sh,
# both of which were mid-edit in another session when this landed. A standalone entry point
# ships the capability today and costs one call to adopt later:
#     "$MXTK_ROOT/bin/install-tests.sh" "$PROJECT_ROOT"
# is the whole integration. Until then this is the supported way to get the engine.
#
# WHAT IT WILL NOT DO
# project.config.js is the one file a project is expected to edit. It is installed from the
# template ONLY when absent. Overwriting it would silently revert a project's pages, menu
# paths and credentials to another app's, and the audits would then walk the wrong page names
# and report fault on every one — which reads as "the harness is broken", not "I clobbered
# your config". --force still refuses to touch it.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT="$(cd "$HERE/.." && pwd)"
SRC="$TOOLKIT/project-tests/e2e"
# shellcheck source=lib/install-manifest.sh
. "$HERE/lib/install-manifest.sh"

FORCE=0
TARGET=""
for a in "$@"; do
  case "$a" in
    --force) FORCE=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) TARGET="$a" ;;
  esac
done

# Resolve the project the same way close-task.sh does: argument, else the git root of $PWD.
# Never a hardcoded path — this script installs into many projects on many machines.
if [ -z "$TARGET" ]; then
  TARGET="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
[ -d "$TARGET" ] || { echo "install-tests.sh: no such directory: $TARGET" >&2; exit 1; }

DST="$TARGET/tests/e2e"
mkdir -p "$DST"

copied=0 skipped=0
for f in $MXTK_PROJECT_TESTS; do
  if [ -f "$DST/$f" ] && [ "$FORCE" -eq 0 ] && ! cmp -s "$SRC/$f" "$DST/$f"; then
    echo "  differs, kept  $f   (--force to overwrite)"
    skipped=$((skipped+1))
    continue
  fi
  cp "$SRC/$f" "$DST/$f"
  copied=$((copied+1))
done

# The config: install from template only if absent, --force or not.
if [ -f "$DST/project.config.js" ]; then
  echo "  kept           project.config.js   (yours; never overwritten)"
else
  cp "$SRC/$MXTK_PROJECT_TESTS_TEMPLATE" "$DST/project.config.js"
  echo "  NEW            project.config.js   <-- EDIT THIS BEFORE RUNNING ANYTHING"
fi

echo
echo "engine -> $DST   ($copied copied, $skipped kept)"
echo
echo "Next, in this order:"
echo "  1. node $DST/project.config.js        # print what it derived; check id and .mpr"
echo "  2. edit NAV / TARGETS / PAGE_WIREFRAME / exemplars / walkthroughs in project.config.js"
echo "  3. node $DST/report-normalize.js --selftest   # must print 'all ok'"
echo "  4. node $DST/journey-runner.selftest.js"
echo
echo "Step 2 is not optional. Unedited, the audits walk another app's page names and report"
echo "fault on every page — which looks like a broken harness, not an unedited config."
