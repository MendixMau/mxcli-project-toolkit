#!/usr/bin/env bash
# bug-lookup.sh — print the bug-log entries that match a CE code, a BUG number, or a keyword,
# so a session reads the ONE entry it needs instead of the whole ledger.
#
#   bin/bug-lookup.sh CE0117            # every entry mentioning CE0117
#   bin/bug-lookup.sh BUG-102           # that entry
#   bin/bug-lookup.sh "widget name"     # keyword, case-insensitive, headers first
#   bin/bug-lookup.sh --index           # one line per entry: id, title, status flags
#
# WHY. bug-logs/mxcli-bugs.md is 32k words — a third of everything a session read on every
# project before writing a line of MDL (baseline tier, measured 2026-09-04: 118k words across
# 29 rows). Nobody needs all 115 entries; they need the one that matches the error in front
# of them. This turns the ledger into a lookup. The routing row for the ledger now points here.
#
# Output: matching entries in full (header + body up to the next `## `), headers-only with
# --index or when more than 6 entries match a keyword (then narrow it). POSIX awk + grep.
set -eu
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="${MXTK_BUG_LOG:-$ROOT/bug-logs/mxcli-bugs.md}"
[ -f "$LOG" ] || { echo "bug-lookup: no ledger at $LOG" >&2; exit 2; }
Q="${1:-}"
[ -n "$Q" ] || { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

index() {
  grep -n '^## ' "$LOG" | grep -v '^[0-9]*:## Provenance' | sed -E 's/^([0-9]+):## /\1\t/' \
    | awk -F'\t' '{ flags=""; if ($2 ~ /RESOLVED|NOT REPRODUCED|RETIRED|SUPERSEDED/) flags=" [closed]"; if ($2 ~ /NOT YET FILED|unfiled/) flags=flags " [unfiled]"; print $2 flags }'
}
if [ "$Q" = "--index" ]; then index; exit 0; fi

# Entry boundaries: line numbers of every `## ` header.
mapfile -t HDR < <(grep -n '^## ' "$LOG" | cut -d: -f1)
TOTAL=$(wc -l < "$LOG")
entry_range() { # $1 = header line no → prints "start end"
  local i n=${#HDR[@]} start=$1 end=$TOTAL
  for ((i=0;i<n;i++)); do if [ "${HDR[$i]}" -gt "$start" ]; then end=$((HDR[$i]-1)); break; fi; done
  echo "$start $end"
}
# Which entries match: header match first, then body match.
matches=""
for h in "${HDR[@]}"; do
  read -r a b < <(entry_range "$h")
  if sed -n "${a},${b}p" "$LOG" | grep -qiF -- "$Q"; then matches="$matches $h"; fi
done
set -- $matches
if [ "$#" -eq 0 ]; then echo "bug-lookup: nothing in the ledger mentions '$Q' — it may be a modelling mistake, not a tool quirk. Try a shorter keyword or the CE code."; exit 1; fi
if [ "$#" -gt 6 ]; then
  echo "bug-lookup: $# entries mention '$Q' — headers only; narrow the query to read one:"
  for h in "$@"; do sed -n "${h}p" "$LOG" | sed 's/^## /  /'; done; exit 0
fi
for h in "$@"; do read -r a b < <(entry_range "$h"); sed -n "${a},${b}p" "$LOG"; echo; done
