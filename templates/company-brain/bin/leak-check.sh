#!/usr/bin/env bash
# leak-check.sh — run the shared toolkit's leak guard over THIS repo, probes-only.
#
# The toolkit's check-no-client-data.sh has two halves: a gitignored NAME denylist (optional
# here — client names are allowed in a company brain) and generic PROBES for real data (strings
# copied from a live app, typed GUIDs, absolute local paths, contact details). This wrapper runs
# the probes half; add a .leakguard-deny (gitignored) beside this repo's root to enable names.
#
#   bin/leak-check.sh            # exit 1 on any hit
#   MXTK_TOOLKIT_ROOT=/path/to/mxcli-project-toolkit bin/leak-check.sh
set -u
TOOLKIT="${MXTK_TOOLKIT_ROOT:-{{TOOLKIT_ROOT}}}"
GUARD="$TOOLKIT/bin/check-no-client-data.sh"
[ -f "$GUARD" ] || { echo "leak-check: toolkit guard not found at $GUARD (set MXTK_TOOLKIT_ROOT)" >&2; exit 2; }
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
DENY="$(pwd)/.leakguard-deny"
if [ -f "$DENY" ]; then
  LEAKGUARD_DENYFILE="$DENY" bash "$GUARD"
else
  LEAKGUARD_ALLOW_NO_DENYLIST=1 bash "$GUARD"
fi
