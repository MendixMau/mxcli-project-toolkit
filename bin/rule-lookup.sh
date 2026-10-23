#!/usr/bin/env bash
# rule-lookup.sh — inline the trigger-only rules whose trigger appears in what a step is about.
#
#   bin/rule-lookup.sh <file>... | -          # matched rule sections, Markdown, to stdout
#   bin/rule-lookup.sh --list <file>... | -   # matched rule ids only, one per line
#   [--root <toolkit>]                        # default: this script's toolkit
#
# EXPERIMENT (task-routed rules, process/task-routed-rules-proposal-2026-10-23.md). A rule with a
# narrow trigger — one API, one widget, one error text — costs every helper its words if it lives
# in an always-read file, and fires in a small share of steps. bin/lib/rule-triggers.tsv lists
# such rules with a regex; this prints a rule's section only when the regex matches the input:
# the step's Builds/Reads names and live DESCRIBE output (project-bin/context-pack.sh, via
# bin/lib/task-rules.sh), a drafted .mdl script, or a pasted error message.
#
# The match only fetches; the rule text and its judgement stay in skills/ (skills-over-scripts.md).
# Same idea as bin/bug-lookup.sh, which maps an error to a bug-ledger entry.
#
# Exit: 0 ran (zero or more matches) · 2 usage error (no input, unreadable file, table missing).
# Bash 3.2 + POSIX awk.
set -u
usage() { sed -n '4,7p' "$0" >&2; exit 2; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; LIST=0; INPUTS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || usage; ROOT="$2"; shift 2 ;;
    --list) LIST=1; shift ;;
    -h|--help) usage ;;
    -) INPUTS="$INPUTS -"; shift ;;
    -*) usage ;;
    *) [ -r "$1" ] || { echo "rule-lookup: cannot read $1" >&2; exit 2; }; INPUTS="$INPUTS $1"; shift ;;
  esac
done
[ -n "$INPUTS" ] || usage
TABLE="$ROOT/bin/lib/rule-triggers.tsv"
[ -r "$TABLE" ] || { echo "rule-lookup: $TABLE missing" >&2; exit 2; }

TEXT="$(mktemp "${TMPDIR:-/tmp}/rule-lookup.XXXXXX")"; trap 'rm -f "$TEXT"' EXIT
# shellcheck disable=SC2086
cat $INPUTS > "$TEXT"

grep -v '^#' "$TABLE" | while IFS="$(printf '\t')" read -r id path heading regex; do
  [ -n "${regex:-}" ] || continue
  grep -qiE "$regex" "$TEXT" || continue
  if [ "$LIST" = 1 ]; then printf '%s\n' "$id"; continue; fi
  [ -r "$ROOT/$path" ] || { printf '_rule %s: %s missing_\n\n' "$id" "$path"; continue; }
  printf '#### %s (from %s)\n\n' "$id" "$path"
  # the section: from the exact heading line to the next heading of the same or higher level
  awk -v h="$heading" '
    $0 == h { on = 1; split(h, a, " "); lvl = length(a[1]); next }
    on && /^#+ / { split($0, b, " "); if (length(b[1]) <= lvl) exit }
    on { print }' "$ROOT/$path"
  printf '\n'
done
