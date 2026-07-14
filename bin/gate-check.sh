#!/usr/bin/env bash
# Mechanical stage-gate checker — replaces "remember to self-check" with file-existence/grep checks.
#
# Always evaluates all stages (0-7) and regenerates index.html in the project directory from the
# real results, so the dashboard can never silently drift from actual project state.
#
# Usage: bin/gate-check.sh <project-dir> [stage-number]
#   - With a stage-number, additionally exits non-zero if that specific stage's check fails.
#   - Without one, evaluates and reports all stages, exits 0 regardless (informational run).

set -uo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <project-dir> [stage-number]" >&2
  exit 1
fi

PROJECT_DIR="$1"
REQUESTED_STAGE="${2:-}"

if [ ! -d "$PROJECT_DIR" ]; then
  echo "Error: project directory does not exist: $PROJECT_DIR" >&2
  exit 1
fi

# Resolve the knowledge-base dir the same way this project's artifacts actually live.
# Convention: analysis/<name>/knowledge-base/ under the project dir; fall back to
# knowledge-base/ directly under the project dir if that's how the project is laid out.
KB_DIR=""
for candidate in "$PROJECT_DIR"/analysis/*/knowledge-base "$PROJECT_DIR/analysis/knowledge-base" "$PROJECT_DIR/knowledge-base"; do
  if [ -d "$candidate" ]; then
    KB_DIR="$candidate"
    break
  fi
done

check_stage_P() {
  local f="$PROJECT_DIR/intake.md"
  if [ ! -f "$f" ]; then
    echo "FAIL|intake.md not found"
    return
  fi
  # Every "## " question section must contain an "Answered" or "Unverified — how to verify" line.
  local blanks
  blanks=$(awk '
    /^## /{ if (insec && !ok) bad++; insec=1; ok=0; next }
    insec && (/Answered/ || /Unverified/) { ok=1 }
    END { if (insec && !ok) bad++; print bad+0 }' "$f")
  local total
  total=$(grep -c '^## ' "$f")
  if [ "$total" -eq 0 ]; then
    echo "FAIL|intake.md has no question sections"
  elif [ "$blanks" -eq 0 ]; then
    echo "PASS|all $total intake questions answered or explicitly Unverified"
  else
    echo "FAIL|$blanks of $total intake questions have no answer and no 'Unverified — how to verify' line"
  fi
}

check_stage_0() {
  local f="$PROJECT_DIR/triage.md"
  if [ ! -f "$f" ]; then
    echo "FAIL|triage.md not found"
    return
  fi
  if grep -q "^## Sign-off" "$f" && grep -q "Confirmed by:" "$f"; then
    echo "PASS|triage.md has a signed-off ## Sign-off section"
  else
    echo "FAIL|triage.md exists but missing a ## Sign-off section with Confirmed by:"
  fi
}

check_stage_1() {
  if [ -z "$KB_DIR" ]; then
    echo "FAIL|no knowledge-base directory found"
    return
  fi
  local report="$KB_DIR/extraction-report.html"
  if [ ! -s "$report" ]; then
    echo "FAIL|$report missing or empty"
    return
  fi
  local kb_md="$KB_DIR/share/KB.md"
  if [ -f "$kb_md" ] && [ ! -s "$kb_md" ]; then
    echo "FAIL|share/KB.md exists but is empty"
    return
  fi
  echo "PASS|extraction-report.html present and non-empty$( [ -f "$kb_md" ] && echo ", KB.md present and non-empty")"
}

check_stage_2() {
  if [ -z "$KB_DIR" ]; then
    echo "FAIL|no knowledge-base directory found"
    return
  fi
  local brd_dir="$KB_DIR/brd"
  if [ ! -d "$brd_dir" ] || [ -z "$(find "$brd_dir" -maxdepth 1 -name '*.brd.json' -print -quit 2>/dev/null)" ]; then
    echo "FAIL|no brd/*.brd.json scaffolds found"
    return
  fi
  local validation="$KB_DIR/reports/validation-report.md"
  if [ ! -f "$validation" ]; then
    echo "FAIL|reports/validation-report.md not found"
    return
  fi
  if grep -A2 "^## Stop condition" "$validation" | grep -qi "clean"; then
    echo "PASS|brd/*.brd.json present, validation-report.md Stop condition is Clean"
  else
    echo "FAIL|validation-report.md exists but Stop condition is not Clean"
  fi
}

check_stage_3() {
  local fit_gap="$PROJECT_DIR/architecture/fit-gap.md"
  local design_system="$PROJECT_DIR/design/design-system.html"
  if [ -f "$fit_gap" ] && [ -f "$design_system" ]; then
    echo "PASS|architecture/fit-gap.md and design/design-system.html both present"
  else
    echo "FAIL|missing $( [ ! -f "$fit_gap" ] && echo "architecture/fit-gap.md ")$( [ ! -f "$design_system" ] && echo "design/design-system.html")"
  fi
}

check_stage_4() {
  local build_plan="$PROJECT_DIR/architecture/build-plan.md"
  if [ -f "$build_plan" ]; then
    echo "PASS|architecture/build-plan.md present"
  else
    echo "FAIL|architecture/build-plan.md not found"
  fi
}

check_stage_6() {
  local f
  for f in "$PROJECT_DIR/test-report.html" "$PROJECT_DIR"/reports/test-report.html; do
    if [ -s "$f" ]; then
      echo "PASS|$(basename "$f") present and non-empty"
      return
    fi
  done
  echo "FAIL|no test-report.html found (project root or reports/)"
}

check_stage_7() {
  local f="$PROJECT_DIR/PROJECT.md"
  if [ ! -f "$f" ]; then
    echo "FAIL|PROJECT.md not found"
    return
  fi
  if grep -i "cutover" "$f" | grep -q "CONFIRMED"; then
    echo "PASS|CONFIRMED cutover decision found in PROJECT.md"
  else
    echo "FAIL|no CONFIRMED cutover decision in PROJECT.md (✋ gate — ASSUMED does not pass)"
  fi
}

check_stage_manual() {
  echo "MANUAL|not file-existence-checkable — fill in status manually"
}

STAGE_NAMES=(0 1 2 3 4 5 6 7)
STAGE_TITLES=(
  "Triage"
  "Analysis"
  "Requirements"
  "Architecture & Design"
  "Build Plan"
  "Build"
  "Test"
  "Cutover"
)

declare -a RESULTS
declare -a NOTES

# Stage P is checked outside the numeric loop (bash 3.2 arrays need integer indices).
P_RESULT="$(check_stage_P)"
P_STATUS="${P_RESULT%%|*}"
P_NOTE="${P_RESULT#*|}"
printf "Stage P (Kickoff): %s — %s\n" "$P_STATUS" "$P_NOTE"

for stage in "${STAGE_NAMES[@]}"; do
  case "$stage" in
    0) result="$(check_stage_0)" ;;
    1) result="$(check_stage_1)" ;;
    2) result="$(check_stage_2)" ;;
    3) result="$(check_stage_3)" ;;
    4) result="$(check_stage_4)" ;;
    6) result="$(check_stage_6)" ;;
    7) result="$(check_stage_7)" ;;
    *) result="$(check_stage_manual)" ;;
  esac
  status="${result%%|*}"
  note="${result#*|}"
  RESULTS[$stage]="$status"
  NOTES[$stage]="$note"
  printf "Stage %s (%s): %s — %s\n" "$stage" "${STAGE_TITLES[$stage]}" "$status" "$note"
done

# Regenerate index.html from these exact results.
INDEX="$PROJECT_DIR/index.html"
PROJECT_NAME="$(basename "$PROJECT_DIR")"

{
  cat <<HTML_HEAD
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>${PROJECT_NAME} — Conversion Dashboard</title>
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #f8fafc; color: #1e293b; padding: 32px 40px; }
  h1 { font-size: 22px; margin-bottom: 4px; }
  .subtitle { color: #64748b; font-size: 13px; margin-bottom: 24px; }
  table { border-collapse: collapse; width: 100%; max-width: 900px; background: #fff; border: 1px solid #e2e8f0; border-radius: 8px; overflow: hidden; }
  th, td { text-align: left; padding: 10px 14px; font-size: 13px; border-bottom: 1px solid #e2e8f0; }
  th { background: #1e293b; color: #e2e8f0; font-weight: 600; }
  tr:last-child td { border-bottom: none; }
  .status { font-weight: 700; padding: 2px 10px; border-radius: 999px; font-size: 11px; display: inline-block; }
  .PASS { background: #dcfce7; color: #166534; }
  .FAIL { background: #fee2e2; color: #991b1b; }
  .MANUAL { background: #fef3c7; color: #92400e; }
  .footer { margin-top: 20px; font-size: 11px; color: #94a3b8; }
</style>
</head>
<body>
<h1>${PROJECT_NAME} — Conversion Dashboard</h1>
<div class="subtitle">Generated by bin/gate-check.sh — derived from real project files, not hand-maintained.</div>
<table>
<tr><th>Stage</th><th>Title</th><th>Status</th><th>Detail</th></tr>
HTML_HEAD

  printf '<tr><td>P</td><td>Kickoff</td><td><span class="status %s">%s</span></td><td>%s</td></tr>\n' \
    "$P_STATUS" "$P_STATUS" "$P_NOTE"
  for stage in "${STAGE_NAMES[@]}"; do
    printf '<tr><td>%s</td><td>%s</td><td><span class="status %s">%s</span></td><td>%s</td></tr>\n' \
      "$stage" "${STAGE_TITLES[$stage]}" "${RESULTS[$stage]}" "${RESULTS[$stage]}" "${NOTES[$stage]}"
  done

  cat <<HTML_TAIL
</table>
<div class="footer">Re-run bin/gate-check.sh $PROJECT_DIR to refresh.</div>
</body>
</html>
HTML_TAIL
} > "$INDEX"

echo ""
echo "index.html regenerated at $INDEX"

if [ -n "$REQUESTED_STAGE" ]; then
  if [ "$REQUESTED_STAGE" = "P" ] || [ "$REQUESTED_STAGE" = "p" ]; then
    if [ "$P_STATUS" = "FAIL" ]; then
      echo "" >&2
      echo "Stage P gate FAILED: $P_NOTE" >&2
      exit 1
    fi
    exit 0
  fi
  requested_status="${RESULTS[$REQUESTED_STAGE]:-}"
  if [ -z "$requested_status" ]; then
    echo "Error: unknown stage number: $REQUESTED_STAGE" >&2
    exit 1
  fi
  if [ "$requested_status" = "FAIL" ]; then
    echo "" >&2
    echo "Stage $REQUESTED_STAGE gate FAILED: ${NOTES[$REQUESTED_STAGE]}" >&2
    exit 1
  fi
fi

exit 0
