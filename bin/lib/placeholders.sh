#!/usr/bin/env bash
# placeholders.sh — list the unfilled {{PLACEHOLDER}} slots left in agent stubs (#211).
#
#   . bin/lib/placeholders.sh
#   mxtk_placeholders <file>...   # one line per file that still has slots:
#                                 #   <file> TAB <count> TAB <NAME NAME ...>
#   mxtk_placeholder_total <file>...   # one number: all slots across the files
#
# WHY. init-project.sh scaffolds six agent stubs whose slots are filled when each agent's
# stage starts (agent-roles.md); a stub refuses to run until then. That is by design. What
# was missing is that nobody could SEE the count: init printed one generic reminder, and a
# field project reached Stage 5 with 30 unfilled slots in 6 files and an mdl-agent that
# refused work without saying why (2026-10-06). init, sync and status.sh now name them.
#
# {{DOUBLE_BRACE}} is EXCLUDED, and the exclusion is load-bearing: every agent template says
# "If any {{DOUBLE_BRACE}} placeholder remains in this file, refuse to proceed" — prose, not
# a slot. gate-check.sh's build-ready check and sync-project.sh's stub test exclude it too.
# A slot such as {{CUSTOMER_INDUSTRY — e.g. "telecom"}} is reported by its NAME only.
#
# Bash 3.2 + POSIX sed/grep. Never fails: an unreadable file is skipped.

_mxtk_slots() {   # $1=file → one slot name per line
  sed 's/{{DOUBLE_BRACE}}//g' "$1" 2>/dev/null | grep -o '{{[^}]*}}' \
    | sed -e 's/^{{ *//' -e 's/[^A-Za-z0-9_].*$//' -e 's/}}$//'
}

mxtk_placeholders() {
  local f n names
  for f in "$@"; do
    [ -f "$f" ] || continue
    n=$(_mxtk_slots "$f" | wc -l | tr -d ' ')
    [ "${n:-0}" -gt 0 ] || continue
    names=$(_mxtk_slots "$f" | sort -u | tr '\n' ' ' | sed 's/ $//')
    printf '%s\t%s\t%s\n' "$f" "$n" "$names"
  done
}

mxtk_placeholder_total() {
  local f t=0 n
  for f in "$@"; do
    [ -f "$f" ] || continue
    n=$(_mxtk_slots "$f" | wc -l | tr -d ' ')
    t=$((t + ${n:-0}))
  done
  echo "$t"
}
