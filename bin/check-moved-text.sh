#!/usr/bin/env bash
# check-moved-text.sh — prove a "move, never delete" trim lost no line.
#
# WHY. CLAUDE.md "Always-loaded skill text — the word budget": room in the baseline is made by
# MOVING stories, examples and old numbers to an on-demand file, never by deleting the rules.
# The first such trim (#315) was checked by hand, line by line. This makes the mechanical half of
# that review a command: every line the diff removes from the source files must still exist,
# verbatim, in the file it moved to. What it cannot judge is whether a line that stayed behind
# should have — that half stays with the reviewer.
#
#   bin/check-moved-text.sh [--base <ref>] <destination-file> <source-file>...
#   bin/check-moved-text.sh process/baseline-incident-history.md skills/ui-preflight-pages.md
#
# Compares the working tree against merge-base(<ref>, HEAD) (default ref origin/master), so it
# runs the same before and after the commit. A removed line counts as found when `grep -F` finds
# it (trailing whitespace trimmed) anywhere in the destination's working-tree copy. Blank lines
# are not counted. Each line not found is printed for hand review — a line rewritten in place
# (a sentence kept, its neighbour moved) shows up here, and the PR says why.
#
# LIMIT. `grep -F` matches substrings, and a line that occurs twice in the sources is satisfied
# by one copy in the destination. So a very short line (`|---|`, "```", "---") is found almost
# anywhere and proves nothing. Lines under 15 characters are listed separately as "trivially
# found, review by hand"; they count as found, but the reviewer reads them.
#
# A named source with no diff (a mistyped path, or a file nothing was removed from) exits 2,
# and so does a run that removed 0 lines in total: "0 of 0 found" is not a pass.
#
# Field run: the T4 stub-diet trim, 2026-10-14 (four baseline skills into
# process/baseline-incident-history.md).
#
# Exit: 0 every removed line found · 1 some not found, listed · 2 could not run, a source with
#       no diff, or nothing removed at all.
set -u

BASE="origin/master"
if [ "${1:-}" = "--base" ]; then BASE="${2:-}"; shift 2; fi
DEST="${1:-}"
[ -n "$DEST" ] && [ "$#" -ge 2 ] || { grep '^#   bin/check-moved-text.sh' "$0" | sed 's/^# *//' >&2; exit 2; }
shift
[ -f "$DEST" ] || { echo "check-moved-text: destination '$DEST' not found." >&2; exit 2; }
MB="$(git merge-base "$BASE" HEAD 2>/dev/null)" || {
  echo "check-moved-text: no merge base with '$BASE' (fetch it first)." >&2; exit 2; }

TOTAL=0; FOUND=0; MISSING=""; SHORT=""; NODIFF=""
for SRC in "$@"; do
  REMOVED="$(git diff --no-color -U0 "$MB" -- "$SRC" | awk '
    /^--- (a\/|\/dev\/null)/ { next }
    /^-/ { print substr($0, 2) }')"
  if [ -z "$(printf '%s' "$REMOVED" | tr -d '[:space:]')" ]; then
    NODIFF="${NODIFF}  ${SRC}
"
    continue
  fi
  while IFS= read -r line; do
    t="$(printf '%s' "$line" | sed 's/[[:space:]]*$//')"
    [ -n "$(printf '%s' "$t" | tr -d '[:space:]')" ] || continue
    TOTAL=$((TOTAL + 1))
    if grep -F -q -- "$t" "$DEST"; then
      FOUND=$((FOUND + 1))
      if [ "${#t}" -lt 15 ]; then SHORT="${SHORT}  ${SRC}: ${t}
"; fi
    else
      MISSING="${MISSING}  ${SRC}: ${t}
"
    fi
  done <<LINES
$REMOVED
LINES
done

if [ -n "$NODIFF" ]; then
  echo "check-moved-text: no removed lines in these source(s) — mistyped path, or nothing moved:" >&2
  printf '%s' "$NODIFF" >&2
  exit 2
fi
if [ "$TOTAL" -eq 0 ]; then
  echo "check-moved-text: 0 removed lines in total — nothing was checked, which is not a pass." >&2
  exit 2
fi
echo "check-moved-text: $FOUND of $TOTAL removed non-blank line(s) found verbatim in $DEST."
if [ -n "$SHORT" ]; then
  echo "Trivially found (under 15 characters, a substring match proves little — review by hand):"
  printf '%s' "$SHORT"
fi
if [ -n "$MISSING" ]; then
  echo "Not found (review by hand; each needs a reason in the PR):"
  printf '%s' "$MISSING"
  exit 1
fi
exit 0
