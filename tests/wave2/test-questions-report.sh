#!/bin/bash
# test-questions-report.sh — the HTML triage report must be honest about what it read.
#
# The report exists because a terminal dump is invisible to everyone except the agent that
# ran it. The failure modes it must not have are the ones this toolkit keeps hitting:
#   - rendering "no open questions" over a project where nothing was examined (false green);
#   - swallowing questions that arrived with no proposed answer, which is the exact defect
#     the report was added to surface;
#   - exiting 0 while blocking questions exist, so a caller reads it as clean.
#
# Usage: bash test-questions-report.sh [path-to-questions-report.sh]

SUBJECT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../bin" && pwd)/questions-report.sh}"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/qreport.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT

echo "== subject: $SUBJECT"
command -v jq >/dev/null 2>&1 || { echo "  SKIP — jq not installed; the collector cannot run"; exit 0; }

# --- 1. Nothing examined must NOT produce a clean-looking report ---------------------
EMPTY="$WORK/empty"; mkdir -p "$EMPTY"
out=$(bash "$SUBJECT" "$EMPTY" -o "$EMPTY/r.html" 2>&1); rc=$?
[ "$rc" -eq 3 ] && ok "empty project exits 3 (nothing examined), got $rc" \
                || bad "empty project should exit 3, got $rc — a caller would read this as clean"
[ ! -f "$EMPTY/r.html" ] && ok "empty project writes no report file" \
                         || bad "wrote a report for a project with no sources — that file reads as an all-clear"

# --- 2. A project with a bare, never-raised question ---------------------------------
# One BRD, one openQuestion, no drafting position and no raisedAtGate: UNRAISED + no proposal.
P="$WORK/bare"; mkdir -p "$P/analysis/knowledge-base/brd"
cat > "$P/analysis/knowledge-base/brd/F001-thing.brd.json" <<'JSON'
{
  "id": "F001",
  "title": "Thing",
  "stage": 2,
  "openQuestions": [
    { "id": "Q1", "question": "Should discounts compound?", "status": "Open" }
  ]
}
JSON
out=$(bash "$SUBJECT" "$P" -o "$P/r.html" 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "blocking questions exit 1 (got $rc)" \
               || bad "expected exit 1 with a blocking question, got $rc"
if [ -f "$P/r.html" ]; then
  ok "report written"
  html=$(cat "$P/r.html")
  case "$html" in
    *"Should discounts compound?"*) ok "the question text appears in the report" ;;
    *) bad "the question is missing from the report it exists to show" ;;
  esac
  case "$html" in
    *UNRAISED*) ok "state UNRAISED is shown" ;;
    *) bad "state UNRAISED not shown — the reader cannot tell it blocks" ;;
  esac
  # The point of the report: a question with no proposed answer is called out, not hidden.
  case "$html" in
    *"No proposed answer"*) ok "bare question is flagged as having no proposed answer" ;;
    *) bad "bare question NOT flagged — this is the defect the report was added to surface" ;;
  esac
  # Self-contained: a report that pulls a stylesheet off the network is unreadable when
  # forwarded to an SME, which is the whole use case.
  case "$html" in
    *"http://"*|*"https://"*) bad "report references an external URL — not self-contained" ;;
    *) ok "report is self-contained (no external URLs)" ;;
  esac
  case "$html" in
    *"<style"*) ok "styles are inlined" ;;
    *) bad "no inline <style> — the report will render unstyled" ;;
  esac
else
  bad "no report written for a project that has a question"
  FAIL=$((FAIL+4))
fi

# --- 3. A question that WAS raised and answered must not be reported as blocking ------
P2="$WORK/answered"; mkdir -p "$P2/analysis/knowledge-base/brd"
cat > "$P2/analysis/knowledge-base/brd/F002-thing.brd.json" <<'JSON'
{
  "id": "F002",
  "title": "Thing",
  "stage": 2,
  "openQuestions": [
    { "id": "Q1", "question": "Should discounts compound?", "status": "ANSWERED",
      "answer": "No — flat only.", "raisedAtGate": 2 }
  ]
}
JSON
out=$(bash "$SUBJECT" "$P2" -o "$P2/r.html" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "an answered question exits 0 (got $rc)" \
               || bad "answered question should not block, got exit $rc"
grep -q 'No proposed answer' "$P2/r.html" 2>/dev/null \
  && bad "an ANSWERED question was flagged as lacking a proposal — that flag is for blocking rows only" \
  || ok "answered question carries no 'no proposed answer' flag"

# --- 4. Default output location, and --stage scoping ----------------------------------
bash "$SUBJECT" "$P" --quiet >/dev/null 2>&1
[ -f "$P/docs/open-questions.html" ] && ok "default output is docs/open-questions.html" \
                                     || bad "default output not written to docs/open-questions.html"

# A stage filter below the question's own stage must exclude it, and with nothing left in
# scope the report must still be honest rather than silently empty.
bash "$SUBJECT" "$P" --stage 0 -o "$WORK/s0.html" >/dev/null 2>&1; rc=$?
if [ -f "$WORK/s0.html" ]; then
  grep -q 'Should discounts compound' "$WORK/s0.html" \
    && bad "--stage 0 still reported a stage-2 question — the filter does nothing" \
    || ok "--stage 0 excludes the stage-2 question"
else
  ok "--stage 0 produced no report (rc=$rc) — acceptable, nothing in scope"
fi

# --- 5. Usage errors are distinguishable from findings --------------------------------
bash "$SUBJECT" >/dev/null 2>&1
[ $? -eq 2 ] && ok "no arguments exits 2 (usage)" || bad "missing project-dir should exit 2"
bash "$SUBJECT" "$WORK/does-not-exist" >/dev/null 2>&1
[ $? -eq 2 ] && ok "nonexistent directory exits 2" || bad "nonexistent directory should exit 2"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
