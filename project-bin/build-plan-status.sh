#!/usr/bin/env bash
# build-plan-status.sh — mechanizes the progress tracker brd-to-build-plan.md already specifies
# and iterative-build-loop.md already assumes exists, and adds the per-module test/review status
# next to it. Neither previously had a renderer — see "WHY THIS EXISTS" below.
#
# WHY THIS EXISTS
# brd-to-build-plan.md Step 10 specifies a self-contained `architecture/build-plan.html` progress
# tracker, "regenerated whenever a phase's status changes." iterative-build-loop.md says the
# `build-plan.html` phase status and the `done-` filename prefixes "should agree — when every
# script for a phase is done-, that phase flips to check in the tracker." Neither statement had a
# script behind it (confirmed 2026-08-19: no file in bin/ or project-bin/ writes build-plan.html).
# That is the same shape as `gate-agent` (routed, never invoked, 0/21 sessions) and deep
# verification at "step 10" (specified, scheduled last, never ran) — a mechanism that only exists
# in prose does not exist. This script is the renderer.
#
# It also answers a question the phase view alone cannot: a phase can be 100% done-renamed and
# still not proven — "done" per iterative-build-loop.md means gate-clean AND happy-path verified,
# but only module-review.md's CONFIRM stage (via verify-module.sh) and improvement-register.md
# know whether that verification actually happened and what it found. So this renders TWO views,
# kept honestly separate because they answer different questions:
#
#   A. Build-plan phase progress   — from mdlsource/<phase>/ done- counts.  "How much is BUILT."
#   B. Per-module test/review view — from verify-module.sh summaries + the improvement register.
#                                     "How much is PROVEN, and what's still open."
#
# A phase at 100% in view A with no row in view B is exactly the gap this script exists to make
# visible: built, never proven. DIAGNOSTIC ONLY — reads files, writes nothing but the optional
# --html output and never touches the .mpr.
#
# Usage:
#   build-plan-status.sh [project-dir] [--html] [--quiet]
#     --html    also write architecture/build-plan.html (self-contained, no external deps)
#     --quiet   suppress the stdout table (useful when only --html output is wanted)
#
# Exit: always 0. This is a status view, not a gate — skills-over-scripts.md: a script reports
# facts, a human or a skill (module-review.md, iterative-build-loop.md) judges them.

set -uo pipefail

ROOT="${1:-}"
[ -n "$ROOT" ] && [ "${ROOT#--}" = "$ROOT" ] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
shift 2>/dev/null || true

WRITE_HTML=0
QUIET=0
for a in "$@"; do
  case "$a" in
    --html)  WRITE_HTML=1 ;;
    --quiet) QUIET=1 ;;
    *) echo "unknown arg: $a" >&2; exit 2 ;;
  esac
done

cd "$ROOT" || exit 0

MDLSOURCE="$ROOT/mdlsource"
MODULES_DIR="$ROOT/architecture/modules"
REGISTER="$ROOT/docs/improvement-register.md"
BUILD_PLAN="$ROOT/architecture/build-plan.md"
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ── A. Build-plan phase progress, from mdlsource/<phase>/done- counts ───────
# Phase folders are read as they exist on disk, not matched against build-plan.md's prose Phase
# headers — a fuzzy name-match would be a guess, and skills-over-scripts.md says code carries no
# opinion. If a reader wants the prose name for phase "3b-core-microflows", cross-reference the
# numeric prefix against architecture/build-plan.md by hand; this script does not invent the link.
PHASE_ROWS=""
PHASE_COUNT=0
if [ -d "$MDLSOURCE" ]; then
  for d in "$MDLSOURCE"/*/; do
    [ -d "$d" ] || continue
    phase="$(basename "$d")"
    total=$(find "$d" -maxdepth 1 -type f \( -name '*.mdl' -o -name '*.sql' \) | wc -l | tr -d ' ')
    [ "$total" -eq 0 ] && continue
    done_ct=$(find "$d" -maxdepth 1 -type f \( -name 'done-*.mdl' -o -name 'done-*.sql' \) | wc -l | tr -d ' ')
    pct=$(( total > 0 ? done_ct * 100 / total : 0 ))
    status="pending"
    [ "$done_ct" -gt 0 ] && status="in-progress"
    [ "$done_ct" -eq "$total" ] && status="done"
    PHASE_ROWS="${PHASE_ROWS}${phase}	${done_ct}/${total}	${pct}%	${status}
"
    PHASE_COUNT=$((PHASE_COUNT+1))
  done
fi

# ── B. Per-module test/review status ─────────────────────────────────────────
# "Reviewed" = verify-module.sh has run for this module at least once (a summary.tsv exists).
# Its own verdict is re-derived from that file's rows, never re-run here — this script is a
# reader, not another instrument.
MODULE_ROWS=""
MODULE_COUNT=0
REVIEWED_COUNT=0
if [ -d "$MODULES_DIR" ]; then
  for d in "$MODULES_DIR"/*/; do
    [ -d "$d" ] || continue
    module="$(basename "$d")"
    briefed="no"
    [ -f "$d/module-brief.md" ] && briefed="yes"

    summary="$ROOT/.claude/loop/verify/$module/summary.tsv"
    reviewed="not yet"
    if [ -f "$summary" ]; then
      REVIEWED_COUNT=$((REVIEWED_COUNT+1))
      if grep -q $'\tFAULT\t' "$summary" 2>/dev/null; then
        reviewed="INCOMPLETE (instrument fault)"
      elif grep -q $'\tFINDING\t' "$summary" 2>/dev/null; then
        reviewed="FINDINGS"
      else
        reviewed="CLEAN"
      fi
      age_s=$(( $(date +%s) - $(date -r "$summary" +%s 2>/dev/null || echo 0) ))
      age_d=$(( age_s / 86400 ))
      reviewed="$reviewed (${age_d}d ago)"
    fi

    open_findings="-"
    if [ -f "$REGISTER" ]; then
      # Register rows: | Date | Module/Cluster | Source pass | Defect class | Severity | Finding | Disposition |
      # Count rows for this module whose Disposition does not start with "fixed".
      open_findings=$(awk -F'|' -v m="$module" '
        NF >= 8 {
          mod=$3; gsub(/^[ \t]+|[ \t]+$/, "", mod)
          disp=$8; gsub(/^[ \t]+|[ \t]+$/, "", disp)
          if (mod == m && disp !~ /^fixed/) n++
        }
        END { print n+0 }' "$REGISTER")
    fi

    MODULE_ROWS="${MODULE_ROWS}${module}	${briefed}	${reviewed}	${open_findings}
"
    MODULE_COUNT=$((MODULE_COUNT+1))
  done
fi

# ── stdout summary ────────────────────────────────────────────────────────
if [ "$QUIET" -eq 0 ]; then
  echo "══ build-plan status ══  $STAMP"
  echo ""
  echo "── A. Build-plan phase progress (mdlsource/<phase>/, done- prefix) ──"
  if [ "$PHASE_COUNT" -eq 0 ]; then
    echo "  no phase folders found under mdlsource/ — nothing to report"
  else
    printf 'phase\tdone/total\t%%\tstatus\n%s' "$PHASE_ROWS" | (column -t -s "$(printf '\t')" 2>/dev/null || cat) | sed 's/^/  /'
  fi
  echo ""
  echo "── B. Per-module test/review status ──"
  if [ "$MODULE_COUNT" -eq 0 ]; then
    echo "  no module directories found under architecture/modules/ — nothing to report"
  else
    printf 'module\tbriefed\treviewed\topen findings\n%s' "$MODULE_ROWS" | (column -t -s "$(printf '\t')" 2>/dev/null || cat) | sed 's/^/  /'
  fi
  echo ""
  echo "  $REVIEWED_COUNT of $MODULE_COUNT module(s) have ever been through verify-module.sh."
  echo "  A phase at 100% in A with its module never appearing reviewed in B is built, not proven."
  echo "  Staleness backstop for A: project-bin/done-drift-check.sh"
fi

# ── optional HTML render ─────────────────────────────────────────────────
if [ "$WRITE_HTML" -eq 1 ]; then
  OUT="$ROOT/architecture/build-plan.html"
  mkdir -p "$ROOT/architecture"
  {
    echo '<!doctype html><html><head><meta charset="utf-8">'
    echo '<title>Build Plan Status</title>'
    echo '<style>
body{font:14px/1.5 -apple-system,Segoe UI,sans-serif;margin:2rem;color:#1a1a1a;background:#fff}
h1{font-size:1.3rem} h2{font-size:1.05rem;margin-top:2rem;border-bottom:1px solid #ddd;padding-bottom:.3rem}
table{border-collapse:collapse;width:100%;margin-top:.5rem}
th,td{text-align:left;padding:.4rem .6rem;border-bottom:1px solid #eee;font-size:.9rem}
th{color:#666;font-weight:600}
.done{color:#0a7d2c} .in-progress{color:#a66a00} .pending{color:#888}
.CLEAN{color:#0a7d2c} .FINDINGS{color:#b3261e} .INCOMPLETE{color:#a66a00}
.note{color:#666;font-size:.85rem;margin-top:1rem}
</style></head><body>'
    echo "<h1>Build Plan Status</h1><p class=note>Generated $STAMP by project-bin/build-plan-status.sh — regenerate after any phase status change, never hand-edit.</p>"

    echo "<h2>A. Build-plan phase progress</h2>"
    if [ "$PHASE_COUNT" -eq 0 ]; then
      echo "<p>No phase folders found under <code>mdlsource/</code>.</p>"
    else
      echo "<table><tr><th>Phase</th><th>Done / Total</th><th>%</th><th>Status</th></tr>"
      printf '%s' "$PHASE_ROWS" | while IFS=$'\t' read -r phase ratio pct status; do
        [ -n "$phase" ] || continue
        echo "<tr><td>$phase</td><td>$ratio</td><td>$pct</td><td class=\"$status\">$status</td></tr>"
      done
      echo "</table>"
    fi

    echo "<h2>B. Per-module test/review status</h2>"
    if [ "$MODULE_COUNT" -eq 0 ]; then
      echo "<p>No module directories found under <code>architecture/modules/</code>.</p>"
    else
      echo "<table><tr><th>Module</th><th>Briefed</th><th>Reviewed</th><th>Open findings</th></tr>"
      printf '%s' "$MODULE_ROWS" | while IFS=$'\t' read -r module briefed reviewed findings; do
        [ -n "$module" ] || continue
        cls="pending"
        case "$reviewed" in CLEAN*) cls=CLEAN ;; FINDINGS*) cls=FINDINGS ;; INCOMPLETE*) cls=INCOMPLETE ;; esac
        echo "<tr><td>$module</td><td>$briefed</td><td class=\"$cls\">$reviewed</td><td>$findings</td></tr>"
      done
      echo "</table>"
    fi
    echo "<p class=note>A: built, from mdlsource/ done- prefixes. B: proven, from verify-module.sh + docs/improvement-register.md. A phase at 100% with no reviewed row in B is built, not proven.</p>"
    echo '</body></html>'
  } > "$OUT"
  [ "$QUIET" -eq 0 ] && echo "" && echo "  wrote ${OUT#$ROOT/}"
fi

exit 0
