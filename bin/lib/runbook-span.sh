#!/usr/bin/env bash
# runbook-span.sh — locate the runbook sections a stage session needs, by heading, never by a
# hard-coded line number. Source it; do not execute it.
#
# Callers: bin/gate-check.sh (the "Read for this gate" line), bin/runbook-slice.sh (prints the
# lines), bin/lib/skill-routing.sh (counts the slice's words for the per-role budget lines).
# One copy, so the three never disagree about where a section starts or ends.
#
# What a stage session needs is §1b (the Live Checklist Protocol, which applies to every stage)
# plus its own stage's section under §2. A helper reading through bin/runbook-slice.sh also gets
# the gate-verdict table and §3b's ownership paragraph (runbook_verdicts_span, runbook_3b_owner_span).
# Stage headings are keyed on the " — " every one carries:
# "### Stage 0 runs in every entry mode" (under Entry Modes) also starts with "### Stage 0", and
# matched first without it.
#
# bash 3.2 (stock macOS) and POSIX awk.

# runbook_span <file> <start-regex> <end-regex> — "A–B" (1-based, inclusive) or ""
runbook_span() {
  awk -v h="$2" -v e="$3" '
    !start && $0 ~ h { start = NR; next }
    start && $0 ~ e   { end = NR - 1; exit }
    END { if (start) { if (!end) end = NR; printf "%d–%d", start, end } }' "$1" 2>/dev/null
}

# runbook_stage_token <stage-arg> — P, 0-7 as the runbook spells them ("build-ready" reads Stage
# 5's section; "p" is "P"). Prints nothing for anything else.
runbook_stage_token() {
  case "$1" in
    build-ready) echo "5" ;;
    p|P) echo "P" ;;
    0|1|2|3|4|5|6|7) echo "$1" ;;
    *) : ;;
  esac
}

# runbook_stage_span <file> <stage-token>  — the "A–B" span of "### Stage N — …"
runbook_stage_span() { runbook_span "$1" "^### Stage $2 — " "^###? "; }
# runbook_1b_span <file>                   — the "A–B" span of "## 1b. …"
runbook_1b_span()    { runbook_span "$1" "^## 1b\\." "^## "; }

# runbook_span_through <file> <start-regex> <anchor-regex> — "A–B" from the start line through
# the first line matching <anchor-regex> (inclusive), or through the line before the next heading
# if the anchor is gone, so a reworded anchor shortens the span instead of running to EOF.
runbook_span_through() {
  awk -v h="$2" -v a="$3" '
    !start && $0 ~ h { start = NR; next }
    start && $0 ~ a  { end = NR; exit }
    start && /^#/    { end = NR - 1; exit }
    END { if (start) { if (!end) end = NR; printf "%d–%d", start, end } }' "$1" 2>/dev/null
}

# Two spans every helper needs whatever its stage (review of PR #378):
# runbook_verdicts_span <file> — the gate-verdict table under "### What a gate verdict means"
#   (PASS/PENDING/FAIL/WAIVED/MANUAL and their exit codes), through "An informational run …".
runbook_verdicts_span() { runbook_span_through "$1" "^### What a gate verdict means" "^An informational run"; }
# runbook_3b_owner_span <file> — §3b's "Ownership is split" paragraph and its bullets ("a helper
#   that hits a BRD-touching decision reports it to the lead"), through the next blank line.
runbook_3b_owner_span() {
  awk '
    !in3b && /^## 3b\./ { in3b = 1; next }
    in3b && /^## /      { exit }
    in3b && !start && /^\*\*Ownership is split/ { start = NR; next }
    start && /^[[:space:]]*$/ { end = NR - 1; exit }
    END { if (start) { if (!end) end = NR; printf "%d–%d", start, end } }' "$1" 2>/dev/null
}

# runbook_print_span <file> <"A–B"> — the lines themselves.
runbook_print_span() {
  local a b
  a="${2%%–*}"; b="${2##*–}"
  [ -n "$a" ] && [ -n "$b" ] || return 1
  sed -n "${a},${b}p" "$1"
}
