#!/usr/bin/env bash
# Fails (rc 1) when a denylisted customer name appears in the tracked files of a folder.
# Usage: customer_names_check.sh [folder]   (default: the upgrade-toolkit folder; tracked files via git, else every file)
# The names come from the private list (bin/private_names.sh); without it the check says so and passes.
# Exempt: the scrub script of the private mirror, which must name what it replaces.
set -u
DIR=${1:-$(cd "$(dirname "$0")/.." && pwd)}
source "$(dirname "$0")/private_names.sh"
[ -n "$DENY" ] || { echo "customer-names: no private list (set UPG_PRIVATE_NAMES), nothing to check"; exit 0; }
EXEMPT='(^|/)sync-from-personal\.sh$'
cd "$DIR" || exit 2
if git rev-parse --is-inside-work-tree >/dev/null 2>&1 && [ -n "$(git ls-files . | head -1)" ]; then files=$(git ls-files .); else files=$(find . -type f | sed 's|^\./||'); fi
hits=$(echo "$files" | grep -Ev "$EXEMPT" | while IFS= read -r f; do [ -f "$f" ] && grep -nIHE "$DENY" -- "$f"; done | cut -c1-200)
if [ -n "$hits" ]; then echo "$hits"; echo "customer names in tracked files (see above)" >&2; exit 1; fi
echo "customer-names: clean"
