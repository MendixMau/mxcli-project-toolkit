#!/usr/bin/env bash
# check-no-private-citations.sh — the public toolkit never cites a private tier.
#
#   bin/check-no-private-citations.sh [root]     # exit 1 on any hit
#
# Real incident (USI workshop research, 2026-08): five skills cited by this public repo existed
# only in a private repo, so an engineer following the pointer got nothing. A company brain
# (templates/company-brain/) may cite the toolkit; the toolkit must never cite a company brain,
# a personal repo, or any path under a user's home that is not this repo. This is the CI floor
# for that rule.
#
# Matches: a path segment named like a private tier (`personal-toolkit/`, `<x>company-brain<y>/`),
# or `~/Mendix/<repo>/` where <repo> is not mxcli-project-toolkit. Override or extend with
# PRIVATE_TIER_REGEX (extended regex). Prose mentions without a path ("a personal-toolkit design
# note") are credits, not pointers, and do not match.
#
# Exempt: CHANGELOG.md (history), contrib/inbox/ (unreviewed by definition; nothing may cite it),
# process/ and dated bug-log retest/archive records (evidence, not routing), tests/ and evals/ (fixtures plant hits on purpose), templates/ (must
# name what it forbids), and
# this script. Everything else tracked (or, outside git, every regular file) is scanned.
set -u
ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit 2
RE="${PRIVATE_TIER_REGEX:-(personal-toolkit/|company-brain/|(~|\\\$HOME|/Users/[^/\` ]+|/home/[^/\` ]+)/Mendix/[A-Za-z0-9_.-]+/)}"
# The toolkit's own paths are not private tiers: its template directory, and its own clone path.
ALLOW="${PRIVATE_TIER_ALLOW:-templates/company-brain/|/Mendix/mxcli-project-toolkit/}"
if git rev-parse --show-toplevel >/dev/null 2>&1; then
  files="$(git ls-files)"
else
  files="$(find . -type f -not -path './.git/*' | sed 's|^\./||')"
fi
hits=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  case "$f" in
    CHANGELOG.md|process/*|bug-logs/*retest*|bug-logs/archive-*|contrib/inbox/*|tests/*|evals/*|templates/*|bin/check-no-private-citations.sh|*.mpk|*.png|*.jpg|*.webp|*.zip|*.pdf) continue ;;
  esac
  m="$(grep -nE "$RE" "$f" 2>/dev/null | grep -vE "$ALLOW")" || continue
  printf '❌ %s\n%s\n' "$f" "$(printf '%s\n' "$m" | sed 's/^/    /')"
  hits=$((hits+1))
done <<< "$files"
if [ "$hits" -gt 0 ]; then
  echo "check-no-private-citations: $hits file(s) cite a private tier. Reword to the toolkit's own file, or drop the pointer." >&2
  exit 1
fi
echo "check-no-private-citations: clean"
