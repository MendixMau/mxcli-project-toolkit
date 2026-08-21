#!/usr/bin/env bash
# report-disposition-check.sh — did a report's own findings actually get filed?
#
# WHY THIS EXISTS
# skills/finding-disposition.md says every report-producing run must route its findings through
# close-the-loop.md to docs/improvement-register.md before the run is called done — but a skill is
# only read when someone remembers to read it. This is the mechanical backstop: it reads the most
# recent evidence report, greps it for the verdict vocabulary those skills already use, and checks
# whether docs/improvement-register.md picked up a matching entry the same day. It does not decide
# whether any one finding matters, whether a fix is right, or whether the register ROW is any
# good — that judgement stays in finding-disposition.md and close-the-loop.md, per
# skills/skills-over-scripts.md. This script only checks presence/absence of the paper trail.
#
# WHAT IT CHECKS
#   1. Locates the newest report/log this project has produced (see candidates below).
#   2. Greps its text for FAULT / FINDING / FAIL / NOT RUN / NOT reached, and for an "N of M"
#      denominator where N < M — the shape module-review.md and e2e-evidence-report.md already use
#      to state what ran short of what was promised.
#   3. Derives the report's own date (filename suffix, else "Generated <date>" in its text, else
#      falls back to the file's mtime and SAYS SO).
#   4. Counts docs/improvement-register.md rows whose Date column equals that date.
#   5. A report with findings/gaps and zero matching register rows is an un-filed report: a
#      FINDING, not a fault in this instrument.
#
# WHAT IT DOES NOT DO — per skills/skills-over-scripts.md, "judgement goes in a skill, code only
# fetches facts a reader cannot": it never reads a finding's SEVERITY, never decides a fix is
# correct, never edits the register. A human (or the finding-disposition.md pass) does that.
#
# Usage:
#   project-bin/report-disposition-check.sh [project-root]
#
# Exit: 0 clean — either no findings/gaps in the newest report, or they are filed for that date
#       1 FINDING — the report shows findings/gaps, but the register has no row dated that day
#       2 FAULT — no report AND no register could be located at all; nothing was measured

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_common.sh"

case "${1:-}" in
  -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
esac

# Positional project-root override — _common.sh already resolves PROJECT_ROOT by walking up for
# an .mpr, but the caller may want to point this at a specific project explicitly (default: cwd,
# via _common.sh's own tier-3 walk).
if [ -n "${1:-}" ]; then
  [ -d "$1" ] || { echo "FAULT: '$1' is not a directory" >&2; exit 2; }
  PROJECT_ROOT="$(cd "$1" && pwd)"
fi
cd "$PROJECT_ROOT" || exit 2

REGISTER="$PROJECT_ROOT/docs/improvement-register.md"

# --- locate the newest report ------------------------------------------------------------
# Candidates, in the shapes real projects actually use (checked against a live project, not
# guessed): e2e-evidence-report.md's own output lands in docs/progress/ (e.g.
# e2e-assurance-report-<date>.html, e2e-evidence-report-<date>.html, e2e-*-report-<date>.html,
# status-report-<date>.html); module-review.md's Stage-4 LOOK output lands under
# design/ui-reviews/ (ui-review-<date>*.html); a verify-module.sh run's own summary is a TSV
# under .claude/loop/verify/<Module>/summary.tsv (no date in the name — mtime is its only clock).
#
# All candidates are pooled and the single most recently modified file wins: this instrument
# checks "the newest thing a reader would open", not every report ever produced.
newest=""
newest_mtime=0
_consider() {
  local f="$1" mt
  [ -f "$f" ] || return 0
  mt="$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)"
  if [ "$mt" -gt "$newest_mtime" ]; then newest="$f"; newest_mtime="$mt"; fi
}
for f in "$PROJECT_ROOT"/docs/progress/*.html \
         "$PROJECT_ROOT"/design/ui-reviews/*.html; do
  _consider "$f"
done
# verify-module.sh's own summary.tsv, per module — a log, not an HTML report, but it carries the
# same PASS/FINDING/FAULT vocabulary (project-bin/verify-module.sh's own SUMMARY format).
for f in "$PROJECT_ROOT"/.claude/loop/verify/*/summary.tsv; do
  _consider "$f"
done

if [ -z "$newest" ] && [ ! -f "$REGISTER" ]; then
  echo "FAULT: no report (docs/progress/*.html, design/ui-reviews/*.html," >&2
  echo "       .claude/loop/verify/*/summary.tsv) and no $REGISTER found." >&2
  echo "       Nothing was measured — this is not a clean run." >&2
  exit 2
fi
if [ -z "$newest" ]; then
  echo "FAULT: no report found (docs/progress/*.html, design/ui-reviews/*.html," >&2
  echo "       .claude/loop/verify/*/summary.tsv all empty or absent)." >&2
  echo "       $REGISTER exists, but there is nothing to check it against." >&2
  exit 2
fi

echo "report-disposition-check · $(date +%Y-%m-%d)"
echo "  newest report          ${newest#$PROJECT_ROOT/}"

# --- derive the report's own date --------------------------------------------------------
# 1. A YYYY-MM-DD suffix in the filename (every real example — e2e-assurance-report-2026-08-21.html,
#    ui-review-2026-08-19.html — carries one).
# 2. Failing that, a "Generated <date>" string in the body (e2e-evidence-report.md's own report
#    structure states this is guaranteed on the HTML — see that skill's "Publishing" section).
# 3. Failing that, the file's own mtime — logged as a fallback, never silently used.
report_date=""
date_source=""
base="$(basename "$newest")"
case "$base" in
  *[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]*)
    report_date="$(printf '%s\n' "$base" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)"
    date_source="filename"
    ;;
esac
if [ -z "$report_date" ]; then
  report_date="$(grep -oiE 'Generated[[:space:]]+[0-9]{4}-[0-9]{2}-[0-9]{2}' "$newest" 2>/dev/null \
                  | head -1 | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')"
  [ -n "$report_date" ] && date_source="'Generated <date>' text"
fi
if [ -z "$report_date" ]; then
  report_date="$(date -u -d "@$newest_mtime" +%Y-%m-%d 2>/dev/null \
                  || date -u -r "$newest_mtime" +%Y-%m-%d 2>/dev/null)"
  date_source="file mtime (fallback — no date in filename or body)"
fi
echo "  report date             $report_date  (from: $date_source)"

# --- grep the verdict vocabulary ----------------------------------------------------------
# Plain substring/regex matching over the report's raw text. Deliberately not HTML-aware: the
# words this greps for (skills/module-review.md, skills/e2e-evidence-report.md, harness-
# architecture.md's own trichotomy) appear in the rendered text either way, and a real parser
# here would be exactly the "parser for a document you also wrote the format of" tell
# skills-over-scripts.md warns against.
#
# CASE-INSENSITIVE, and covers the prose forms reports actually use, not just the shouted
# instrument vocabulary. Found 2026-08-21: a report can be entirely CLEAN by this check's own
# reading while containing real un-filed gaps, if those gaps are phrased in prose ("not run",
# "unmeasured", "could not", "excluded", "no time budget") rather than the literal uppercase
# FAULT/FINDING/FAIL/NOT RUN tokens the original pattern looked for — those tokens only
# co-occurred with the prose forms by coincidence in the report that first exercised this script.
# A report whose only gap is phrased in prose must still be caught.
vocab_hits="$(grep -oiE 'FAULT|FINDING|\bFAIL(ED|URE)?\b|not[[:space:]]+run\b|not[[:space:]]+reached|not[[:space:]]+attempted|not[[:space:]]+(re)?written|could[[:space:]]*n.?t|unmeasured|not[[:space:]]+coverable|excluded|\bskipped\b|no time budget|zero[[:space:]-]+(journey[[:space:]]+)?coverage|never (run|authored|attempted)' "$newest" 2>/dev/null | grep -c . || true)"

# Denominator gaps: "N of M" where N < M — the shape module-review.md's and e2e-evidence-
# report.md's own denominator rule requires reports to state.
denom_gaps="$(grep -oE '[0-9]+[[:space:]]+of[[:space:]]+[0-9]+' "$newest" 2>/dev/null \
  | awk '{ n=$1; m=$3; if (n+0 < m+0) print n " of " m }' | sort -u)"
denom_gap_count="$(printf '%s\n' "$denom_gaps" | grep -c . || true)"

echo "  verdict-vocab hits      $vocab_hits  (FAULT/FINDING/FAIL/NOT RUN/not reached)"
if [ "$denom_gap_count" -gt 0 ]; then
  echo "  denominator gaps        $denom_gap_count  (N of M, N < M):"
  printf '%s\n' "$denom_gaps" | sed 's/^/    /'
else
  echo "  denominator gaps        0"
fi

has_findings=0
[ "$vocab_hits" -gt 0 ] && has_findings=1
[ "$denom_gap_count" -gt 0 ] && has_findings=1

# --- cross-check the register -------------------------------------------------------------
if [ ! -f "$REGISTER" ]; then
  reg_rows=0
else
  # Date is column 1 of the pipe table (skills/close-the-loop.md's own format,
  # `| Date | Module/Cluster | Source pass | Defect class | Severity | Finding | Disposition |`).
  reg_rows="$(awk -F'|' -v d="$report_date" '
    NF >= 7 {
      c=$2; gsub(/^[ \t]+|[ \t]+$/, "", c)
      if (c == d) n++
    }
    END { print n+0 }' "$REGISTER")"
fi
echo "  $REGISTER rows dated $report_date   $reg_rows"

if [ "$has_findings" -eq 0 ]; then
  echo ""
  echo "  CLEAN — the newest report states no FAULT/FINDING/FAIL/NOT-RUN/short-denominator; nothing owed filing."
  exit 0
fi

if [ "$reg_rows" -eq 0 ]; then
  echo ""
  echo "  FINDING — ${newest#$PROJECT_ROOT/} reports findings/gaps (vocab hits: $vocab_hits, denominator" >&2
  echo "  gaps: $denom_gap_count) dated $report_date, but $REGISTER has zero rows dated $report_date." >&2
  echo "  This is an un-filed report, not a broken instrument: route these findings via" >&2
  echo "  skills/close-the-loop.md into $REGISTER, per skills/finding-disposition.md, before" >&2
  echo "  calling the run done." >&2
  exit 1
fi

echo ""
echo "  CLEAN — $reg_rows register row(s) dated $report_date account for this report's findings/gaps."
exit 0
