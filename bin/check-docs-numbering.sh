#!/usr/bin/env bash
# check-docs-numbering.sh — refuse to commit a doc whose stated counts contradict itself.
#
# Two assertions, both cheap, both earned by real bugs found 2026-08-12 in
# skills/iterative-build-loop.md (wave-2 #9 and #10):
#
#   A. An "<N>-step" claim in prose must equal the number of top-level items in SOME
#      ordered list in the same file. A count in prose is a second copy of a fact the
#      list already states, and it drifts the moment anyone inserts an item.
#      The loop was called 12-step, 13-step and 15-step in one file; the list had 15.
#
#   B. "Gate <N>" ordinal labels in a file must start at 1 and ascend in document
#      order. The loop's gates ran 2 -> 4 -> 3 and there had never been a Gate 1.
#
# Preferred fix for a rule-A hit is to DELETE the count, not correct it.
# Preferred fix for a rule-B hit is to NAME the gate, not renumber it.
#
# PORTABILITY: POSIX ERE only. No \b, no \d, no grep -P. BSD awk/grep on macOS accept
# none of them and fail SILENTLY — matching nothing and printing a pass. The first
# draft of rule A used \b and no-opped on the maintainer's own machine; this repo's
# leak guard has been silently skipping its CJK check the same way for months. Every
# regex here was executed on macOS, not eyeballed.
#
# Usage: check-docs-numbering.sh [--all]
#   (no args) check staged .md files only — the pre-commit path
#   --all     sweep the whole repo
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
fail=0

if [ "${1:-}" = "--all" ]; then
  files=$(git -C "$root" ls-files 'skills/*.md' 'agents/*.md' 'process/*.md')
else
  files=$(git -C "$root" diff --cached --name-only --diff-filter=ACM -- \
            'skills/*.md' 'agents/*.md' 'process/*.md')
fi
# A scan that examined nothing must not read like a scan that found nothing wrong — that is
# the exact shape of the leak guard's silent CJK skip. No tick mark, and the count is always
# reported below, so "0 files" is visible rather than implied.
[ -n "$files" ] || { echo "doc numbering: 0 staged docs — nothing examined"; exit 0; }
n_files=$(printf '%s\n' "$files" | wc -l | tr -d ' ')

TMP="$(mktemp /tmp/ckdoc.XXXXXX)"
trap 'rm -f "$TMP"' EXIT

for f in $files; do
  p="$root/$f"
  [ -f "$p" ] || continue

  # --- Rule A: stated step count vs. list lengths -----------------------------
  # A top-level ordered list is a run of lines matching ^[0-9]+[.)]. Counting is
  # fence-agnostic on purpose: the loop this rule was written for lived inside a
  # ``` block, which is exactly why no markdown tool ever counted it.
  # Hyphenated form only, and N >= 3 — "§1 step 6" and "J001 steps" are prose.
  awk -v FNAME="$f" '
    /[0-9]+-[Ss]teps?/ {
      if (match($0, /[0-9]+-[Ss]teps?/)) {
        c = substr($0, RSTART, RLENGTH); gsub(/[^0-9]/, "", c)
        claims[++nc] = c + 0; cline[nc] = FNR
      }
    }
    /^[0-9]+[.)][ \t]/ { if (!inlist) { inlist = 1; ++nl; len[nl] = 0 } len[nl]++; next }
    # A blank line does not end a list (items wrap); a non-indented, non-item line does.
    /^[^ \t]/ { inlist = 0 }
    END {
      for (i = 1; i <= nc; i++) {
        ok = 0; sizes = ""
        for (j = 1; j <= nl; j++) {
          if (len[j] == claims[i]) ok = 1
          if (len[j] > 2) sizes = sizes " " len[j]
        }
        if (!ok && claims[i] >= 3)
          printf "%s:%d: prose says \"%d-step\" but no ordered list in this file has %d items (lists here:%s) — delete the count, the list is the fact\n", \
                 FNAME, cline[i], claims[i], claims[i], sizes
      }
    }
  ' "$p" > "$TMP" 2>/dev/null
  if [ -s "$TMP" ]; then cat "$TMP"; fail=1; fi
  : > "$TMP"

  # --- Rule B: Gate ordinals contiguous from 1, ascending in document order ----
  # Only **bold** `**Gate N` labels, which is how the loop marks a gate. The
  # `Gate 0`/`Gate 5` retest vocabulary in bug-logs/ is untouched (and bug-logs/
  # is outside the globs anyway).
  # tr to spaces: the loop must word-split on one line — zsh does not split on
  # embedded newlines the way bash does, and this file gets read by both.
  gates=$(grep -oE '\*\*Gate [0-9]+' "$p" | grep -oE '[0-9]+' | tr '\n' ' ')
  if [ -n "$gates" ]; then
    expected=1; prev=0
    for g in $gates; do
      if [ "$g" -le "$prev" ] || [ "$g" -ne "$expected" ]; then
        echo "$f: gate labels [$gates] — expected 1..N ascending in document order; name the gates instead of numbering them"
        fail=1
        break
      fi
      prev=$g; expected=$((expected + 1))
    done
  fi
done

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "✗ doc numbering check failed. Fix, or run with --all to see the whole repo."
  exit 1
fi
echo "✅ doc numbering: $n_files doc(s) examined — counts match their lists, gate ordinals contiguous"
