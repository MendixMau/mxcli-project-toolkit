#!/usr/bin/env bash
# check-pr-discipline.sh — the two merge-queue rules that kept breaking by hand, made mechanical.
#
# Born 2026-09-01, draining a five-PR queue: three of five PRs had no CHANGELOG line (the
# same-commit rule is stated in CLAUDE.md and the PR template, and it was on the honor
# system), and two parallel sessions branching from stale masters both assigned BUG-96..100 —
# to different bugs — in one day, which surfaced only as a merge conflict a human had to
# renumber by hand.
#
#   bin/check-pr-discipline.sh [<base-ref>]     # default origin/master
#
# Checks, over the merge-base diff to HEAD:
#   1. CHANGELOG. A diff touching skills/, bin/, project-bin/, project-tests/, bug-logs/ or
#      pipelines/ must also touch CHANGELOG.md — the "every user-visible change appends its
#      line in the same commit" rule from CLAUDE.md, enforced instead of trusted.
#      contrib/inbox/ is exempt (the inbox lane is triaged later, changelog lands at
#      promotion), and so is a diff that ONLY deletes files.
#   2. BUG numbers. A newly added '## BUG-<N>:' heading must not already exist on the base.
#      Write '## BUG-DRAFT-<slug>:' in a PR instead; whoever merges assigns the next free
#      number at merge time (one queue, one numberer, no collisions).
#
# Exit: 0 clean · 1 violation(s), listed · 2 could not run (say why, never a silent pass).
set -u

BASE="${1:-origin/master}"

MB="$(git merge-base "$BASE" HEAD 2>/dev/null)" || {
  echo "check-pr-discipline: cannot find a merge base with '$BASE'." >&2
  echo "  In CI make sure the checkout has history (fetch-depth: 0) and the base ref is fetched." >&2
  exit 2
}

FAIL=0

# --- 1. changelog rides in the same PR --------------------------------------------------------
CHANGED="$(git diff --name-status "$MB" HEAD)"
NEEDS_LOG="$(printf '%s\n' "$CHANGED" | awk '
  $1 == "D" { next }                                  # pure deletions owe nothing
  $2 ~ /^contrib\/inbox\// { next }                   # inbox lane: changelog lands at promotion
  $2 ~ /^(skills|bin|project-bin|project-tests|bug-logs|pipelines)\// { print $2 }
' | head -20)"
if [ -n "$NEEDS_LOG" ] && ! printf '%s\n' "$CHANGED" | awk '$2 == "CHANGELOG.md"' | grep -q .; then
  FAIL=1
  echo "FAIL  user-visible change with no CHANGELOG.md line in the same PR:"
  printf '%s\n' "$NEEDS_LOG" | sed 's/^/        /'
  echo "      Append the line(s) — format at the top of CHANGELOG.md, credit the source project."
fi

# --- 2. new BUG numbers must be free on the base ----------------------------------------------
NEW_BUGS="$(git diff "$MB" HEAD -- bug-logs/ | grep -E '^\+## BUG-[0-9]+:' | sed -E 's/^\+## (BUG-[0-9]+):.*/\1/' | sort)"
if [ -n "$NEW_BUGS" ]; then
  # Collisions are checked against the base TIP, not the merge base: the whole failure mode
  # is a branch forked BEFORE the base took the number — at the merge base the number is
  # always still free, which is exactly why the author picked it in good faith.
  #
  # But a heading that already existed AT the merge base is not a collision: the author is
  # RESTAMPING a bug both sides know (a retest verdict, an archive restructure rewrites the
  # heading line, so it shows as added in the diff). First field case, 2026-09-02: the
  # v0.20.0 retest PR re-stamped existing entries and this check flagged BUG-97 as "taken".
  # A collision is only: absent at the merge base AND present on the tip — two sessions
  # invented the same number for different bugs in parallel.
  while IFS= read -r b; do
    [ -n "$b" ] || continue
    if git show "$MB:bug-logs/mxcli-bugs.md" 2>/dev/null | grep -qE "^## $b:"; then
      continue   # existed when the author branched — a restamp, not an invention
    fi
    if git show "$BASE:bug-logs/mxcli-bugs.md" 2>/dev/null | grep -qE "^## $b:"; then
      FAIL=1
      echo "FAIL  $b is already taken on $BASE — a parallel PR got there first."
      echo "      Rename yours '## BUG-DRAFT-<slug>:'; the merger assigns the next free number."
    fi
  done <<EOF
$NEW_BUGS
EOF
  # duplicates within this PR itself
  DUP="$(printf '%s\n' "$NEW_BUGS" | uniq -d)"
  if [ -n "$DUP" ]; then
    FAIL=1
    printf 'FAIL  the same number is added twice in this PR: %s\n' "$DUP"
  fi
fi

if [ "$FAIL" -eq 0 ]; then
  echo "check-pr-discipline: clean (changelog rides along; no BUG-number collisions vs $BASE)"
  exit 0
fi
exit 1
