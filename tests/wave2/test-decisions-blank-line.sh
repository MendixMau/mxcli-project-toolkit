#!/usr/bin/env bash
# Fixture for #676: a blank line inside the Decisions table must not end the table.
#
# The Decisions-table readers in bin/gate-check.sh (has_confirmed_decision,
# has_auto_assumed_decision, auto_hand_pending, stage_exit_recorded, check_stage_7) all ended
# the table at the first non-pipe line, blank lines included. A register written as
#
#   | 1 | scope | OPEN | |
#
#   | 4 | Build plan | CONFIRMED | |
#
# FAILed Stage 4 with "no Stage-4 CONFIRMED decision" over a CONFIRMED row in plain sight.
# The fix (DECISIONS_TABLE_AWK) skips blank lines but still ends the table at a heading, at
# prose, or at a new header row whose first cell is not "Stage" — so an Open-questions table
# after a blank line is never read as Decisions.
#
#   tests/wave2/test-decisions-blank-line.sh /path/to/gate-check.sh
#
# POSITIVE CONTROL. Against the pre-fix script (origin/master ee12a615) D1, D2 and D4 FAIL.
# D3 is a [guard]: it passes on master, and FAILs on a naive fix that only skips blank lines
# (measured: the Open-questions rows then pass Stages 4 and 7). D4 would also FAIL on a fix
# that kept NR for the line id, since NR counts both passes of the two-pass read.
#
# Keep gate-check.sh under the toolkit's bin/ (it derives TOOLKIT_DIR from BASH_SOURCE).
set -uo pipefail

GATE="${1:?usage: test-decisions-blank-line.sh /path/to/gate-check.sh}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/dec676.XXXXXX")"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

# mkproj <name> — a project with a build plan and the register body read from stdin.
mkproj() {
  local d="$WORK/$1"
  mkdir -p "$d/architecture" "$d/analysis/X/knowledge-base"
  printf '# plan\n' > "$d/architecture/build-plan.md"
  cat > "$d/PROJECT.md"
  printf '%s\n' "$d"
}
# stage_line <out> <N> — the first "Stage N (" verdict line of a run.
stage_line() { local l; while IFS= read -r l; do case "$l" in "Stage $2 ("*) printf '%s\n' "$l"; return ;; esac; done <<< "$1"; }

echo "== D1: blank line, then a Stage-4 CONFIRMED row — Stage 4 PASS =="
P="$(mkproj d1 <<'EOF'
# Project

## Decisions

| Stage | Decision | Status | Notes |
|---|---|---|---|
| 1 | Scope | OPEN | |

| 4 | Build plan | CONFIRMED | |
EOF
)"
L="$(stage_line "$("$GATE" --no-html "$P" 4 2>&1)" 4)"
case "$L" in
  *': PASS'*) ok "the row after the blank line is read (Stage 4 PASS)" ;;
  *) bad "row after a blank line ignored: $L" ;;
esac

echo "== D2: blank line, then a Stage-7 CONFIRMED row — Stage 7 PASS =="
P="$(mkproj d2 <<'EOF'
| Stage | Decision | Status | Notes |
|---|---|---|---|
| 3 | Architecture | CONFIRMED | |

| 7 | Cutover: big bang | CONFIRMED | |
EOF
)"
L="$(stage_line "$("$GATE" --no-html "$P" 7 2>&1)" 7)"
case "$L" in
  *': PASS'*) ok "check_stage_7 reads past the blank line" ;;
  *) bad "Stage 7 row after a blank line ignored: $L" ;;
esac

echo "== D3: [guard] blank line, then an Open-questions table — its rows are NOT decisions =="
P="$(mkproj d3 <<'EOF'
| Stage | Decision | Status | Notes |
|---|---|---|---|
| 3 | Architecture | CONFIRMED | |

| # | Question | Raised at | Status |
|---|---|---|---|
| 4 | Who signs the plan? | Stage 2 | CONFIRMED |
| 7 | Cutover weekend? | Stage 2 | CONFIRMED |
EOF
)"
O="$("$GATE" --no-html "$P" 4 2>&1)"
L4="$(stage_line "$O" 4)"; L7="$(stage_line "$("$GATE" --no-html "$P" 7 2>&1)" 7)"
case "$L4" in
  *': FAIL'*'no Stage-4 CONFIRMED decision'*) ok "an Open-questions '| 4 | … | CONFIRMED |' row does not pass Stage 4" ;;
  *) bad "Open-questions row read as a Stage-4 decision: $L4" ;;
esac
case "$L7" in
  *': PASS'*) bad "Open-questions row read as the Stage-7 cutover decision: $L7" ;;
  *) ok "an Open-questions '| 7 | … | CONFIRMED |' row does not pass Stage 7" ;;
esac

echo "== D4: auto_hand_pending still names the register line, not a doubled one =="
P="$(mkproj d4 <<'EOF'
Interview mode: auto

| Stage | Decision | Status | Notes |
|---|---|---|---|

| 3 | Architecture | ASSUMED | consentBy: auto-mode, consentAt: 2026-11-06 |
EOF
)"
O="$("$GATE" --no-html "$P" 2>&1)"
case "$O" in
  *'PROJECT.md:6 (Stage 3)'*) ok "the auto-mode ✋ row is listed at PROJECT.md:6" ;;
  *) bad "auto-mode ✋ row not listed at PROJECT.md:6 — output has: $(grep -o 'PROJECT.md:[0-9]* (Stage [0-9])' <<< "$O" | head -3 | tr '\n' ' ')" ;;
esac

printf '\n%s: %d ok, %d FAIL\n' "$(basename "$0")" "$PASS" "$FAIL"
rm -rf "$WORK"
[ "$FAIL" -eq 0 ]
