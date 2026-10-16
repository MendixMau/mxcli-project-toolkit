#!/usr/bin/env bash
# #381: a clean toolkit checkout must pass its own install-manifest self-check. Every file in
# project-bin/ is named by MXTK_PROJECT_BIN or MXTK_PROJECT_BIN_NOINSTALL, so the warning fires
# only when a contributor adds a file and forgets the manifest, never on every adopter's sync.
# This test FAILS (not warns) on an unnamed file.
#
# usage: test-manifest-clean-checkout.sh [toolkit-root]
set -uo pipefail
TK="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
. "$TK/bin/lib/install-manifest.sh" 2>/dev/null || { echo "FAIL cannot source install-manifest.sh"; exit 1; }
OUT="$(_mxtk_manifest_check_bin_unnamed 2>&1)"
if [ -z "$OUT" ]; then echo "  ok   project-bin/ is fully named by the manifest"; echo "test-manifest-clean-checkout: 1 passed, 0 failed"; exit 0; fi
echo "  FAIL project-bin/ holds files named by neither list:"; printf '%s\n' "$OUT" | sed 's/^/  /'
echo "test-manifest-clean-checkout: 0 passed, 1 failed"; exit 1
