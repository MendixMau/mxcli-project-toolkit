#!/bin/bash
# test-page-fidelity-mocks.sh — pin the mock-versus-structure rule in page-fidelity.js.
#
# page-fidelity.js is the SCORE OF RECORD: every run appends a row to the project's
# docs/PAGE-FIDELITY.tsv, and the first non-stub row per page is the first-build number a
# ≥80% gate is read off. It had no fixture, which is how the defect below survived.
#
# THE DEFECT. A wireframe's own <style> block defines two very different kinds of class:
# BOUND-DATA MOCKS (a repeated region holding sample rows — a page that correctly binds
# them contains none of that literal text, so scoring it against them measures nothing)
# and STRUCTURE (the wrapper, the page header, the toolbar — furniture the page script
# genuinely must declare). The classifier drops a mock's whole subtree, so a
# misclassified structural class DELETES PAGE CONTENT from the denominator.
#
# The test was `uses === 1 && kept < 0.4` — once-used AND dominant counts as structure —
# which contradicts the file's own stated principle that a mock is a REPEATED region. A
# once-used class whose subtree was small fell through the second conjunct and was dropped
# as sample data. Measured 2026-09-09 on a MOC/PSSR app replacement's project overview:
# `.page-head` (uses=1, kept=0.513) was deleted with the page's only <h1> inside it, and
# `.toolbar` (uses=1, kept=0.825) with it. Every dimension then reported 0 of 0.
#
# AND 0-OF-0 NORMALIZES TO `null%`, NOT TO A LOW SCORE. So the instrument printed a clean
# report over an empty corpus and the page looked unmeasured rather than wrong. That is
# the same silent-null failure the note in the file's own header says was worth fixing,
# arriving a second time through the other conjunct. THE FIRST ASSERTION HERE IS THEREFORE
# NOT "the score is high" BUT "the score is not null": a null on a wireframe that draws an
# h1 means the scorer gutted the page, whatever the eventual percentage.
#
# Usage: bash test-page-fidelity-mocks.sh [path-to-page-fidelity.js]

set -u

TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
SUT="${1:-$TOOLKIT/project-bin/page-fidelity.js}"
SUT="$(cd "$(dirname "$SUT")" && pwd)/$(basename "$SUT")"   # fixtures cd away; a relative $1 must survive
FIX="$TOOLKIT/tests/wave2/fixtures/page-fidelity-mocks"

PASS=0; FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
has()  { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing '$3'" ;; esac; }
hasnt(){ case "$2" in *"$3"*) bad "$1" "unexpected '$3'" ;; *) ok "$1" ;; esac; }

command -v node >/dev/null 2>&1 || { echo "test-page-fidelity-mocks: node not available, skipping"; exit 0; }

echo "test-page-fidelity-mocks: $SUT"

# --- the grouped-overview shape: one page-head, one toolbar, two repeated data tables ---
OUT=$(cd "$TMP" && node "$SUT" --no-log "$FIX/grouped-overview.html" Demo_Overview "$FIX/demo-overview.mdl" 2>&1)
echo "$OUT" | sed 's/^/    | /'

echo "  -- the null score is the failure, not the low one"
hasnt "a wireframe drawing an h1 never scores null" "$OUT" "fidelity null%"
has   "the h1 stays in the denominator"             "$OUT" "headings 1/1"

echo "  -- once-used classes are structure"
has "page-head is structure, not a mock" "$OUT" "not a mock)"
case "$OUT" in
  *"not a mock): "*page-head*) ok "page-head named as structure" ;;
  *) bad "page-head named as structure" "page-head is not in the structural list" ;;
esac
case "$OUT" in
  *"not a mock): "*toolbar*) ok "toolbar named as structure" ;;
  *) bad "toolbar named as structure" "toolbar is not in the structural list" ;;
esac
# The regression this pins in the other direction: page-head must NOT be reported as a
# bound-data mock. Both lists are printed, so name-presence alone is ambiguous — check the
# mock line specifically.
MOCKLINE=$(printf '%s\n' "$OUT" | grep 'bound-data mocks' || true)
hasnt "page-head is not a bound-data mock" "$MOCKLINE" "page-head"
hasnt "toolbar is not a bound-data mock"   "$MOCKLINE" "toolbar"

echo "  -- repeated regions are still mocks, at any subtree size"
has "the repeated table wrapper is a mock"   "$MOCKLINE" "x-tablewrap"
# `.x-chip` is repeated ten times and IS bound data — but it lives inside `.x-tablewrap`,
# which is dropped first, so by the time the classifier reaches it there is nothing left to
# match and it is skipped entirely. It must therefore appear in NEITHER list. Asserted as
# the absence it is, rather than as a mock it never gets to be: an assertion that expected
# it on the mock line failed here, and the fixture is the thing that said so.
STRUCTLINE=$(printf '%s\n' "$OUT" | grep 'not a mock)' || true)
hasnt "a chip already removed with its wrapper is not structure" "$STRUCTLINE" "x-chip"
hasnt "a chip already removed with its wrapper is not re-reported" "$MOCKLINE" "x-chip"

echo "  -- the sample text inside a mock is not scored against the page"
# grouped-overview.html's sample rows carry literal project names. A page that BINDS them
# contains none of that text; if the mock subtrees were scored, these would appear as
# missed content and the score would fall below 100%.
hasnt "sample row text is not a missed content block" "$OUT" "Reclaimer refurbishment"

echo "  -- a genuinely mocked list page still reports its mocks"
OUT2=$(cd "$TMP" && node "$SUT" --no-log "$FIX/mocked-list.html" Demo_List "$FIX/demo-list.mdl" 2>&1)
echo "$OUT2" | sed 's/^/    | /'
MOCKLINE2=$(printf '%s\n' "$OUT2" | grep 'bound-data mocks' || true)
has   "the repeated list-item class is a mock"    "$MOCKLINE2" "x-item"
hasnt "the once-used card wrapper is not a mock"  "$MOCKLINE2" "x-card"
hasnt "a mocked list page does not score null"    "$OUT2" "fidelity null%"

echo
printf 'test-page-fidelity-mocks: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
