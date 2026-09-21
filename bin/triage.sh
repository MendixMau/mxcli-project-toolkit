#!/usr/bin/env bash
# triage.sh — read-only triage table for contrib/inbox/*.md (docs/RELEASE-PROCESS.md §1).
#
# Input: contrib/inbox/*.md, written against contrib/inbox/TEMPLATE.md's four front-matter
# lines (**From:** / **Date:** / **Kind:** / **Field evidence:** / **Proposed target:**) by a
# contributor by hand, or drafted by bin/harvest-learnings.sh (whose own header documents its
# output naming convention, <date>-<project>-{bugs,promotions,patches}.md — the filename
# pattern this script's lane guess falls back to). TEMPLATE.md itself is always skipped.
#
#   bin/triage.sh              # table for the toolkit's own contrib/inbox/
#   bin/triage.sh <dir>        # table for another inbox-shaped directory
#
# Read-only: no network, no writes, no verdicts (skills-over-scripts — grading against the
# rubric in docs/RELEASE-PROCESS.md §2 is a session's job, not this script's). Exit 0 always
# once it has scanned at least one file; exit 2 on a bad path or an empty directory, the same
# "zero scanned is not a pass" rule bin/check-portability.sh follows, for the same reason: an
# inbox nobody can find looks identical to an inbox that is genuinely empty unless the script
# says which one happened.
#
# Bash 3.2 compatible (macOS ships 3.2.57): no mapfile, no associative arrays, no ${var,,}.
# No python. Age is computed from the file's own **Date:** front-matter line via a pure-awk
# proleptic-Gregorian day count (Howard Hinnant's days_from_civil) rather than `date -d`/
# `date -j -f`, which take mutually incompatible flags on GNU vs. BSD date and have no portable
# common form for "parse an arbitrary YYYY-MM-DD string" — every existing date helper in this
# toolkit (bin/lib/portable.sh) only ever reads a file's OWN mtime, never an arbitrary date
# string, so there was no precedent to follow either way; awk arithmetic sidesteps the
# incompatibility entirely instead of adding a new BSD/GNU flag fallback chain.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/portable.sh
. "$SCRIPT_DIR/lib/portable.sh"

DIR="${1:-$ROOT/contrib/inbox}"
[ -d "$DIR" ] || { echo "triage.sh: not a directory: $DIR" >&2; exit 2; }

TODAY_Y="$(date +%Y)"; TODAY_M="$(date +%m)"; TODAY_D="$(date +%d)"
TODAY_DAYNUM="$(awk -v y="$TODAY_Y" -v m="$TODAY_M" -v d="$TODAY_D" '
  function days_from_civil(y, m, d,    era, yoe, doy, doe) {
    if (m <= 2) y -= 1
    era = int((y >= 0 ? y : y - 399) / 400)
    yoe = y - era * 400
    doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
    doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
    return era * 146097 + doe - 719468
  }
  BEGIN { print days_from_civil(y + 0, m + 0, d + 0) }
')"

SCANNED=0
DEBT=0
printf '%-46s %-10s %-14s %6s %6s  %s\n' "FILE" "LANE" "KIND" "WORDS" "AGE" "NOTE"

for f in "$DIR"/*.md; do
  [ -f "$f" ] || continue
  base="$(basename "$f")"
  [ "$base" = "TEMPLATE.md" ] && continue
  SCANNED=$((SCANNED + 1))

  # Lane: a **Lane:** front-matter header takes priority (no inbox file carries one today —
  # contrib/inbox/TEMPLATE.md doesn't define the field yet — but a future template revision
  # may add it, and this is the one place that should notice without a script change).
  # Falls back to the filename pattern bin/harvest-learnings.sh's own header documents.
  lane="$(sed -n 's/^\*\*Lane:\*\* *//p' "$f" | head -1)"
  if [ -z "$lane" ]; then
    case "$base" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*-bugs.md|[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*-patches.md|[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*-promotions.md)
        lane="harvest (guess)" ;;
      *)
        lane="inbox (guess)" ;;
    esac
  fi

  kind="$(sed -n 's/^\*\*Kind:\*\* *//p' "$f" | head -1)"
  [ -n "$kind" ] || kind="(none)"

  words="$(wc -w < "$f" 2>/dev/null | tr -d ' ')"
  [ -n "$words" ] || words="?"

  note=""
  age="?"
  fdate="$(sed -n 's/^\*\*Date:\*\* *//p' "$f" | head -1)"
  case "$fdate" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
      fy="${fdate%%-*}"; rest="${fdate#*-}"; fm="${rest%%-*}"; fd="${rest#*-}"
      fdaynum="$(awk -v y="$fy" -v m="$fm" -v d="$fd" '
        function days_from_civil(y, m, d,    era, yoe, doy, doe) {
          if (m <= 2) y -= 1
          era = int((y >= 0 ? y : y - 399) / 400)
          yoe = y - era * 400
          doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
          doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
          return era * 146097 + doe - 719468
        }
        BEGIN { print days_from_civil(y + 0, m + 0, d + 0) }
      ')"
      age=$((TODAY_DAYNUM - fdaynum))
      ;;
    *)
      # No usable **Date:** line — fall back to the file's own mtime (bin/lib/portable.sh),
      # flagged, since a fresh clone/checkout resets mtimes and this is a lower-confidence
      # signal than the front-matter date.
      mt="$(portable_file_mtime_epoch "$f" 2>/dev/null || true)"
      if [ -n "$mt" ]; then
        now_epoch="$(date +%s)"
        age=$(( (now_epoch - mt) / 86400 ))
        note="mtime, no Date: line"
      else
        note="no Date: line, mtime unavailable"
      fi
      ;;
  esac

  if [ "$age" != "?" ] && [ "$age" -ge 14 ]; then
    DEBT=$((DEBT + 1))
    if [ -n "$note" ]; then note="$note; TRIAGE DEBT (>=14d)"; else note="TRIAGE DEBT (>=14d)"; fi
  fi

  printf '%-46s %-10s %-14s %6s %6s  %s\n' "$base" "$lane" "$kind" "$words" "$age" "$note"
done

if [ "$SCANNED" -eq 0 ]; then
  printf 'triage.sh: inspected ZERO files under: %s\n' "$DIR" >&2
  printf '  This is NOT a pass. Check the path, or that the directory still holds *.md files.\n' >&2
  exit 2
fi

echo
echo "triage.sh: $SCANNED file(s) scanned, $DEBT over the 14-day triage-debt threshold."
