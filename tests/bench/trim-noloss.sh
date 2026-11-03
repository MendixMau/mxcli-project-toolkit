#!/usr/bin/env bash
# trim-noloss.sh — the mechanical half of a trim PR's review (CLAUDE.md "Always-loaded skill
# text — the word budget", rule 4): every line a commit range removed from a .md file must be
# found again somewhere in the tree, or be a generated routing row whose path the table still
# routes. Whatever is left is printed for a human to read line by line.
#
#   tests/bench/trim-noloss.sh <base-ref> [<head-ref>] [--reviewed <file>]
#
#   <base-ref>   the commit the trim started from (the PR's merge base)
#   <head-ref>   the trimmed commit; default HEAD
#   --reviewed   a file of removed lines a human has already read and accepted, one per line,
#                verbatim (leading/trailing space ignored); they print as REVIEWED, not LEFT
#
# Classes, one line each on stdout:
#   FOUND    <file>  ->  <first file at head that still contains the line, grep -F>
#   ROUTING  <file>  ->  <path>   a row from inside a ROUTING:BEGIN block; the path is still in
#                                  bin/lib/skill-routing.tsv at head, so the row re-renders elsewhere
#   REVIEWED <file>  :   <line>
#   LEFT     <file>  :   <line>   needs a human; any protected line (rule, STOP row, denominator,
#                                  failure example) here is a HOLD
#
# Exit: 0 nothing LEFT · 1 at least one LEFT line · 2 usage / git error
#
# Written 2026-10-14 for the stub-diet trim (runbook baseline table out, helper runbook slice);
# generic on purpose, so the next trim PR runs the same check instead of eyeballing a diff.
set -uo pipefail

BASE=""; HEAD_REF="HEAD"; REVIEWED=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --reviewed) REVIEWED="${2:?--reviewed needs a file}"; shift 2 ;;
    -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) if [ -z "$BASE" ]; then BASE="$1"; else HEAD_REF="$1"; fi; shift ;;
  esac
done
[ -n "$BASE" ] || { echo "usage: trim-noloss.sh <base-ref> [<head-ref>] [--reviewed <file>]" >&2; exit 2; }
git rev-parse --verify -q "$BASE^{commit}" >/dev/null || { echo "trim-noloss: no such commit: $BASE" >&2; exit 2; }
git rev-parse --verify -q "$HEAD_REF^{commit}" >/dev/null || { echo "trim-noloss: no such commit: $HEAD_REF" >&2; exit 2; }

trim() { sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }
is_reviewed() {
  [ -n "$REVIEWED" ] && [ -f "$REVIEWED" ] || return 1
  trim < "$REVIEWED" | grep -qxF -- "$1"
}

# The per-line loop runs in a pipeline subshell, so the tallies go through a scratch file.
TMPC="$(mktemp "${TMPDIR:-/tmp}/noloss.XXXXXX")"
trap 'rm -f "$TMPC"' EXIT
TSV_HEAD="$(git show "$HEAD_REF:bin/lib/skill-routing.tsv" 2>/dev/null | cut -f2)"

for f in $(git diff --name-only --diff-filter=MD "$BASE" "$HEAD_REF" -- '*.md'); do
  # Line numbers inside generated ROUTING blocks in the BASE version of the file.
  GEN="$(git show "$BASE:$f" 2>/dev/null | awk '/ROUTING:BEGIN/{b=1; next} /ROUTING:END/{b=0} b{print NR}' | tr '\n' ' ')"
  # Removed lines with their base line numbers, from a zero-context diff.
  git diff -U0 "$BASE" "$HEAD_REF" -- "$f" | awk '
    /^@@/ { h = 1; split($2, a, ","); n = substr(a[1], 2) + 0; next }
    !h && /^---/ { next }
    /^-/ { printf "%d\t%s\n", n, substr($0, 2); n++ }' |
  while IFS=$'\t' read -r ln line; do
    t="$(printf '%s' "$line" | trim)"
    # Blank lines and bare markup carry no text to lose.
    case "$t" in ''|'---'|'|---|'*|'<!--'*'-->') continue ;; esac
    case " $GEN " in
      *" $ln "*)
        p="$(printf '%s' "$t" | sed -n 's/^|[^`]*`\([^`]*\)`.*/\1/p')"
        if [ -n "$p" ] && printf '%s\n' "$TSV_HEAD" | grep -qxF -- "$p"; then
          printf 'ROUTING  %s  ->  %s\n' "$f" "$p"; echo R >> "$TMPC"; continue
        fi ;;
    esac
    hit="$(git grep -l -F -e "$t" "$HEAD_REF" -- . 2>/dev/null | head -1 | sed "s|^$HEAD_REF:||")"
    if [ -n "$hit" ]; then
      printf 'FOUND    %s  ->  %s\n' "$f" "$hit"; echo F >> "$TMPC"
    elif is_reviewed "$t"; then
      printf 'REVIEWED %s  :   %s\n' "$f" "$t"; echo V >> "$TMPC"
    else
      printf 'LEFT     %s  :   %s\n' "$f" "$t"; echo L >> "$TMPC"
    fi
  done
done

c() { grep -c "^$1\$" "$TMPC" 2>/dev/null || true; }
printf '\nremoved lines: %s found elsewhere, %s routing rows still routed, %s reviewed, %s LEFT\n' \
  "$(c F)" "$(c R)" "$(c V)" "$(c L)"
[ "$(c L)" = "0" ]
