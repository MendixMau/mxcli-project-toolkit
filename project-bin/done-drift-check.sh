#!/usr/bin/env bash
# done-drift-check.sh — mechanically catch two things that only used to live in memory:
#
#   1. A script exec'd clean (BUILD-LOG says "applied", no later failure/rollback row)
#      but was never renamed to done-<name>.mdl (iterative-build-loop.md's DONE rule).
#   2. Scripts have landed in docs/BUILD-LOG.md since architecture/build-plan.md was
#      last touched, i.e. the plan's phase-status prose may no longer match reality.
#
# THE POINT: both of these were previously "remember to do it" steps with no mechanical
# backstop, and both were found silently skipped on a live project: several scripts passed
# their gate — "✅ applied", mx check / mxbuild 0 errors — and were never done-renamed,
# some dating back to early build phases, not just a recent fast-paced cycle.
#
# THIS SCRIPT DOES NOT AUTO-RENAME. done- means "the feature works", which requires
# the happy-path/coverage verification a human or e2e run confirms — a gate-clean exec
# is necessary but not sufficient (iterative-build-loop.md's Core Principle: CE-error-
# free ≠ done). It only makes the drift visible instead of silently accumulating.
# exec.sh now also prints this reminder at the moment of a clean gate pass — this script
# is the backstop for anything missed at that moment, not the primary mechanism.
#
# USAGE
#   done-drift-check.sh [project-dir]      # defaults to the git root / cwd
#
# Exit 0 always (informational) — wired into close-task.sh's output; never gates a run.

set -uo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT" || exit 0

MDLSOURCE="$ROOT/mdlsource"
BUILD_LOG="$ROOT/docs/BUILD-LOG.md"
BUILD_PLAN="$ROOT/architecture/build-plan.md"

[ -d "$MDLSOURCE" ] || exit 0

echo "## done- drift check — $(date '+%Y-%m-%d %H:%M')"
echo

# ---- 1. gate-clean scripts missing their done- rename ------------------
CANDIDATES=""
if [ -f "$BUILD_LOG" ]; then
  while IFS= read -r -d '' f; do
    base=$(basename "$f")
    case "$base" in done-*) continue ;; esac
    # Last BUILD-LOG row mentioning this exact filename (backtick-quoted, so a
    # substring match on a shorter script's name can't false-positive on a longer one).
    last=$(grep -F "\`$base\`" "$BUILD_LOG" | tail -1)
    [ -n "$last" ] || continue
    case "$last" in
      *"✅ applied"*)
        # Exclude the "applied but caveated" states: dirty-model keep, unverified,
        # partial exec. Only an unqualified "✅ applied" counts as gate-clean.
        case "$last" in
          *"dirty model"*|*PARTIAL*|*UNVERIFIED*) : ;;
          *) CANDIDATES="${CANDIDATES}${base}"$'\n' ;;
        esac
        ;;
    esac
  done < <(find "$MDLSOURCE" -type f \( -name '*.mdl' -o -name '*.sql' \) -print0)
fi

if [ -n "$CANDIDATES" ]; then
  echo "### Gate-clean but not done-renamed — confirm feature/coverage verified, then rename"
  echo
  printf '%s\n' "$CANDIDATES" | sed '/^$/d' | sort -u | while read -r base; do
    path=$(find "$MDLSOURCE" -name "$base" | head -1)
    echo "- \`$path\` — BUILD-LOG shows a clean apply; not yet \`done-\`-prefixed"
  done
  echo
  echo "  If the happy path / coverage checklist is confirmed for these:"
  echo "    git mv <path>/<name> <path>/done-<name>"
  echo
else
  echo "### Gate-clean but not done-renamed"
  echo
  echo "- none found"
  echo
fi

# ---- 2. build-plan.md staleness vs BUILD-LOG activity -------------------
if [ -f "$BUILD_PLAN" ] && git rev-parse --git-dir >/dev/null 2>&1; then
  PLAN_TS=$(git log -1 --format=%ct -- "$BUILD_PLAN" 2>/dev/null || echo 0)
  case "$PLAN_TS" in ''|*[!0-9]*) PLAN_TS=0 ;; esac
  if [ "$PLAN_TS" -gt 0 ] && [ -f "$BUILD_LOG" ]; then
    PLAN_DATE=$(date -r "$PLAN_TS" '+%Y-%m-%d' 2>/dev/null || echo "unknown")
    # Count applied/gated rows added to BUILD-LOG since build-plan.md's last commit,
    # via git log timestamps on BUILD-LOG lines rather than parsing prose dates.
    NEW_ROWS=$(git log --since="@$PLAN_TS" --format="" -p -- "$BUILD_LOG" 2>/dev/null \
      | grep -c '^+| ' || true)
    NEW_ROWS=${NEW_ROWS:-0}
    if [ "$NEW_ROWS" -ge 3 ]; then
      echo "### build-plan.md may be stale"
      echo
      echo "- last touched $PLAN_DATE; $NEW_ROWS BUILD-LOG row(s) landed since — confirm phase"
      echo "  status/checkboxes in \`architecture/build-plan.md\` still match reality"
      echo
    fi
  fi
fi

exit 0
