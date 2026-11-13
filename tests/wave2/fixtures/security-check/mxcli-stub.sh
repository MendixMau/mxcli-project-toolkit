#!/usr/bin/env bash
# mxcli-stub.sh — replays CAPTURED mxcli output (see CAPTURE.md) for tests/wave2/test-security-check.sh.
# SECX_DIR  = scenario folder holding lint.txt and dump.txt (captured with the secdump command set)
# SECX_BASE = folder holding the captured `show entities` / `show user roles` tables
# SECX_FAIL = 1 makes every call fail like an unreadable model; SECX_FAILCMD=<command> fails just that command.
# SECX_LISTRULES = file answering `lint --list-rules` (default list-rules.txt beside this stub).
# It splits the captured dump back into the per-command answers; it invents no content, except one
# `show entities` row for an entity the m1b capture proves exists (see CAPTURE.md).
[ "${SECX_FAIL:-0}" = 1 ] && { echo "Error: failed to connect: mpr file not found" >&2; exit 1; }
echo "WARNING: This is a vibe-coded PoC, alpha quality, use with caution." >&2
D="$SECX_DIR/dump.txt"
sect() {  # sect <heading-regex>: lines of one secdump section (stops at the next secdump heading)
  awk -v h="$1" '
    /^## (project security|user roles|module roles|demo users|security matrix|access rules per entity)/ { on = ($0 ~ ("^## " h)); next }
    on { print }' "$D"
}
if [ "${1:-}" = lint ] && [ "${2:-}" = --list-rules ]; then cat "${SECX_LISTRULES:-$(dirname "$0")/list-rules.txt}"; exit 0; fi
if [ "${1:-}" = lint ]; then cat "$SECX_DIR/lint.txt"; exit 0; fi
[ "${1:-}" = -p ] && [ "${3:-}" = -c ] || { echo "stub: unsupported call: $*" >&2; exit 1; }
cmd="$4"
[ -n "${SECX_FAILCMD:-}" ] && [ "$cmd" = "$SECX_FAILCMD" ] && { echo "Error: the model could not be read (stub failure on request)" >&2; exit 1; }
case "$cmd" in
  "show project security") sect "project security" ;;
  "show user roles") cat "$SECX_BASE/show-user-roles.txt" ;;
  "describe user role "*)
    n=${cmd#describe user role }; n=${n#\'}; n=${n%\'}
    sect "user roles" | awk -v n="$n" '$0=="mdl 1;" {buf=$0; next} buf!="" && $0 ~ ("^create or modify user role " n " \\(") {print buf; on=1; buf=""} buf!="" {buf=""} on {print} on && /^\);/ {on=0}' ;;
  "show module roles") sect "module roles" ;;
  "show demo users") sect "demo users" ;;
  "show security matrix") sect "security matrix" ;;
  "show entities")
    cat "$SECX_BASE/show-entities.txt"
    grep '^No access rules on ' "$D" | sed 's/^No access rules on //' | while IFS= read -r e; do
      grep -q "| $e " "$SECX_BASE/show-entities.txt" || printf '| %-35s | Persistent     |                     | 1     | 0      | 0           | 0       | 0      | 0           |\n' "$e"
    done ;;
  "show access on "*)
    e=${cmd#show access on }
    { sect "access rules per entity"; echo; cat "$SECX_BASE/access-other-modules.txt"; } | awk -v e="$e" '
      $0=="Access rules for " e ":" {on=1}
      /^Access rules for / && $0!="Access rules for " e ":" {on=0}
      $0=="No access rules on " e {print; next}
      on {print}' ;;
  *) echo "stub: unsupported command: $cmd" >&2; exit 1 ;;
esac
