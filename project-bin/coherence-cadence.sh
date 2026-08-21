#!/usr/bin/env bash
# coherence-cadence.sh — the mechanical trip-wire for process-coherence-pass.md's cluster cadence.
#
# WHY THIS EXISTS
# process-coherence-pass.md already specifies WHEN to run: "every N=2-3 modules (a cluster), not
# only once at Stage 6" — because waiting for the whole app means a composition defect planted
# early is only found after everything built on top of it (the 2026-08-19 incident this skill's
# own header cites). But the trigger was prose only: an agent has to remember to count modules
# since the last cluster pass. That is the exact shape that already failed once in this toolkit —
# `gate-agent` was routed and invoked 0/21 sessions because nothing forced the moment. This script
# is the forcing function: it counts, it does not judge. Whether to run the pass, and what its
# findings mean, stays in process-coherence-pass.md (skills-over-scripts.md).
#
# WHAT COUNTS AS "A MODULE SINCE LAST PASS"
# A module that has been through verify-module.sh at least once (a
# .claude/loop/verify/<Module>/summary.tsv exists) and is not yet recorded in the marker written
# by the last --record call. Modules still mid-build are not counted — this cadence is about
# composition risk between PROVEN pieces, same scoping process-coherence-pass.md itself uses
# ("once requirements-conformance and UI/Data testing are both clean for that module or cluster").
#
# Usage:
#   coherence-cadence.sh [project-dir] [--threshold N]   # check; default N=2 (COHERENCE_CLUSTER_N)
#   coherence-cadence.sh [project-dir] --record          # call from process-coherence-pass.md's
#                                                          # CONFIRM step once the pass is done —
#                                                          # records which modules it covered
#
# Exit: 0 not due yet · 1 due (a cluster pass should run before the next module starts) · 2 usage

set -uo pipefail

ROOT="${1:-}"
[ -n "$ROOT" ] && [ "${ROOT#--}" = "$ROOT" ] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
shift 2>/dev/null || true

THRESHOLD="${COHERENCE_CLUSTER_N:-2}"
RECORD=0
while [ $# -gt 0 ]; do
  case "$1" in
    --threshold) THRESHOLD="${2:-2}"; shift ;;
    --record)    RECORD=1 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

cd "$ROOT" || exit 2

MODULES_DIR="$ROOT/architecture/modules"
MARKER="$ROOT/.claude/loop/coherence/last-cluster-pass.tsv"
mkdir -p "$(dirname "$MARKER")"

# Every module that has ever completed a verify-module.sh pass (proven, per the header note above).
PROVEN=""
if [ -d "$MODULES_DIR" ]; then
  for d in "$MODULES_DIR"/*/; do
    [ -d "$d" ] || continue
    m="$(basename "$d")"
    [ -f "$ROOT/.claude/loop/verify/$m/summary.tsv" ] && PROVEN="${PROVEN}${m}
"
  done
fi
PROVEN="$(printf '%s' "$PROVEN" | sed '/^$/d' | sort -u)"

# Modules already credited to a past cluster/full pass, one per line.
COVERED=""
[ -f "$MARKER" ] && COVERED="$(sed '/^$/d' "$MARKER" | sort -u)"

NEW="$(comm -23 <(printf '%s\n' "$PROVEN") <(printf '%s\n' "$COVERED") 2>/dev/null | sed '/^$/d')"
NEW_COUNT=0
[ -n "$NEW" ] && NEW_COUNT=$(printf '%s\n' "$NEW" | grep -c .)

if [ "$RECORD" -eq 1 ]; then
  printf '%s\n' "$PROVEN" | sed '/^$/d' > "$MARKER"
  echo "recorded $(printf '%s\n' "$PROVEN" | grep -c . 2>/dev/null || echo 0) proven module(s) as covered by a coherence pass just now."
  exit 0
fi

echo "coherence cadence: $NEW_COUNT proven module(s) since the last cluster/full pass (threshold: $THRESHOLD)"
if [ "$NEW_COUNT" -gt 0 ]; then
  echo "  new since last pass:"
  printf '%s\n' "$NEW" | sed 's/^/    - /'
fi

if [ "$NEW_COUNT" -ge "$THRESHOLD" ]; then
  echo ""
  echo "  DUE — run process-coherence-pass.md before starting the next module."
  # The cross-module REGRESSION half of the same cadence. process-coherence-pass.md
  # reads the call graph; this walks the built prefix of the business process in a
  # browser, as the real roles, and is the only instrument that exercises the handoff
  # BETWEEN two modules' journeys. --built-only scopes it to modules that have been
  # through verify-module.sh; out-of-scope acts report as not-measured, never green.
  if [ -f "$ROOT/tests/e2e/full-app-walkthrough.js" ]; then
    echo "  And re-run the cross-module regression over what is built so far:"
    echo "      node tests/e2e/full-app-walkthrough.js --built-only"
    echo "      (exit 2 = nothing in scope yet; the report states 'k of N acts in scope')"
  fi
  echo "  When both finish, run: $0 $ROOT --record"
  exit 1
fi

echo "  not due yet ($NEW_COUNT of $THRESHOLD)."
exit 0
