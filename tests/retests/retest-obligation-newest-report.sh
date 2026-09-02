#!/usr/bin/env bash
# retest-obligation-newest-report.sh — does _ob_find return the NEWEST matching artifact?
#
# The defect (found 2026-09-01 on a dashboard-publishing migration): _ob_find's `match=names`
# branch iterated the glob and returned the FIRST hit. Glob order is alphabetical, and the
# review-report schema is `ui-review-<YYYY-MM-DD>*.html`, so alphabetical means OLDEST FIRST.
#
# The project reviewed its module again — properly, five pages, five PROOF-OF-LOOK citations,
# five committed captures — and the gate still reported:
#
#     Obligation look  FAULT — 0 of 1 discharged; NO PROOF-OF-LOOK
#
# because a superseded report from an earlier date sorted ahead of it and was the only file ever
# read. That is the worst shape a guard can take: the remedy it names cannot clear it. Adding
# more proof to the new report changed nothing, and the only way out was to read the checker.
#
# Usage:  tests/retests/retest-obligation-newest-report.sh
# Exit 0 the fix holds · 1 the defect reproduces · 2 could not run.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$HERE/bin/lib/obligation-check.sh"
[ -r "$LIB" ] || { echo "retest: no obligation-check.sh at $LIB"; exit 2; }

# shellcheck disable=SC1090
. "$LIB" 2>/dev/null
command -v _ob_find >/dev/null 2>&1 || { echo "retest: _ob_find not defined after sourcing"; exit 2; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/design/ui-reviews" "$T/dateless"
FAIL=0
# _ob_find prints ALL matching candidates, newest first; `check` asserts on the first line,
# which is the one the caller reaches for before any disqualifier is applied.
check() { # check <label> <expected-basename> <actual-output>
  local got; got="$(printf '%s\n' "${3:-}" | head -1)"
  if [ "$(basename "$got")" = "$2" ]; then printf '  ok   %s\n' "$1"
  else printf '  FAIL %s — expected %s, got %s\n' "$1" "$2" "$(basename "${got:-<nothing>}")"; FAIL=1; fi
}
checkn() { # checkn <label> <expected-count> <actual-output>
  local n; n="$(printf '%s' "${3:-}" | grep -c . || true)"
  if [ "$n" = "$2" ]; then printf '  ok   %s\n' "$1"
  else printf '  FAIL %s — expected %s candidates, got %s\n' "$1" "$2" "$n"; FAIL=1; fi
}

# 1. Newest date wins — and wins even when the OLD file has the newer mtime, which is the real
#    field shape: an old report gets touched by a formatting pass long after it was superseded.
printf 'old DashboardPublishing no proof\n'   > "$T/design/ui-reviews/ui-review-2026-08-31.html"
printf 'mid DashboardPublishing\n'            > "$T/design/ui-reviews/ui-review-2026-09-01-a.html"
printf 'new DashboardPublishing PROOF-OF-LOOK: X = y.png\n' > "$T/design/ui-reviews/ui-review-2026-09-01-b.html"
touch "$T/design/ui-reviews/ui-review-2026-08-31.html"
check "newest date wins over newer mtime" "ui-review-2026-09-01-b.html" \
  "$(_ob_find "$T" names 'design/ui-reviews/ui-review-*.html' DashboardPublishing)"

# 1b. Same-date reports: BOTH are returned, so the caller can fall through to the older one
#     when the newer is disqualified. This is what makes tie order harmless — mtime resolution
#     is a filesystem property (this suite has run on an ext filesystem that stamped two files
#     written milliseconds apart with identical nanoseconds), so a same-date tie cannot be
#     resolved by timestamp and must not need to be.
printf 'first DashboardPublishing\n'  > "$T/design/ui-reviews/ui-review-2026-08-30-zzz.html"
printf 'second DashboardPublishing\n' > "$T/design/ui-reviews/ui-review-2026-08-30-aaa.html"
checkn "same-date pair: both offered, not one" 2 \
  "$(_ob_find "$T" names 'design/ui-reviews/ui-review-2026-08-30-*.html' DashboardPublishing)"

# 1c. Ordering is DETERMINISTIC whatever the tie — arbitrary is tolerable, unstable is not.
touch -r "$T/design/ui-reviews/ui-review-2026-08-30-aaa.html" \
         "$T/design/ui-reviews/ui-review-2026-08-30-zzz.html"
o1="$(_ob_find "$T" names 'design/ui-reviews/ui-review-2026-08-30-*.html' DashboardPublishing)"
o2="$(_ob_find "$T" names 'design/ui-reviews/ui-review-2026-08-30-*.html' DashboardPublishing)"
if [ "$o1" = "$o2" ]; then printf '  ok   exact tie is deterministic\n'
else printf '  FAIL exact tie is not deterministic\n'; FAIL=1; fi

# 2. Dateless filenames fall back to mtime, newest first.
printf 'alpha DashboardPublishing\n' > "$T/dateless/a.html"; sleep 1
printf 'beta DashboardPublishing\n'  > "$T/dateless/b.html"
check "dateless falls back to mtime" "b.html" \
  "$(_ob_find "$T" names 'dateless/*.html' DashboardPublishing)"

# 3. The unit filter still applies: the newest file that does NOT mention the unit is skipped,
#    not returned. Recency must not override relevance.
printf 'newest but mentions OtherModule only\n' > "$T/design/ui-reviews/ui-review-2026-09-02.html"
check "unit filter beats recency" "ui-review-2026-09-01-b.html" \
  "$(_ob_find "$T" names 'design/ui-reviews/ui-review-*.html' DashboardPublishing)"

# 4. Empty files are never returned, however new.
: > "$T/design/ui-reviews/ui-review-2026-09-03.html"
check "empty file skipped" "ui-review-2026-09-01-b.html" \
  "$(_ob_find "$T" names 'design/ui-reviews/ui-review-*.html' DashboardPublishing)"

# 5. match=path is untouched by the sort.
mkdir -p "$T/architecture/modules/DashboardPublishing"
printf 'brief\n' > "$T/architecture/modules/DashboardPublishing/module-brief.md"
check "match=path unaffected" "module-brief.md" \
  "$(_ob_find "$T" path 'architecture/modules/<Module>/module-brief.md' DashboardPublishing)"

[ "$FAIL" -eq 0 ] && { echo "retest-obligation-newest-report: PASS"; exit 0; }
echo "retest-obligation-newest-report: FAIL — the oldest-report defect is back"; exit 1
