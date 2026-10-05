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
hasnt "a wireframe drawing an h1 is never UNMEASURED" "$OUT" "UNMEASURED"
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

echo "  -- a DECLARED bound value leaves the denominator"
# grouped-overview.html carries an <h2 class="bound"> holding a record's own title and a
# <span class="bound"> holding a filename. Both are sample values a correctly BINDING page
# cannot contain, and the wireframe says so with the class. If either were scored, the page
# would report them as missed heading/content and fall below 100%.
hasnt "a bound heading is not a missed heading" "$OUT" "Environmental system improvement"
hasnt "a bound value is not missed content"     "$OUT" "ISO14001_Transition.pdf"
has   "the page still scores 100% with bound values present" "$OUT" "text-match 100%"
# The h2 must leave the HEADING DENOMINATOR, not merely stop being reported as missed —
# otherwise the score would be 1 of 2 and still pass the two assertions above.
has   "the bound heading is out of the denominator" "$OUT" "headings 1/1"

echo "  -- a genuinely mocked list page still reports its mocks"
OUT2=$(cd "$TMP" && node "$SUT" --no-log "$FIX/mocked-list.html" Demo_List "$FIX/demo-list.mdl" 2>&1)
echo "$OUT2" | sed 's/^/    | /'
MOCKLINE2=$(printf '%s\n' "$OUT2" | grep 'bound-data mocks' || true)
has   "the repeated list-item class is a mock"    "$MOCKLINE2" "x-item"
hasnt "the once-used card wrapper is not a mock"  "$MOCKLINE2" "x-card"
hasnt "a mocked list page is not UNMEASURED"    "$OUT2" "UNMEASURED"

echo "  -- bind table: struck/CUT rows are not owed; DESCRIBE's blind ImageUrl; ALTER bodies count"
# bind-contract.html reproduces rows of a real five-column bind table (field project
# CatalogView-redesign-v2.html, 2026-09-23); bind-contract-describe.mdl is the shape mxcli
# v0.23.0 DESCRIBE printed for the built page — two IMAGE widgets whose ImageUrl renders as a
# bare '{1}' although the model binds an attribute. See CAPTURE.md.
BD="$FIX/bind-contract-describe.mdl"
OUT3=$(cd "$TMP" && node "$SUT" --no-log "$FIX/bind-contract.html" Catalog - < "$BD" 2>&1)
echo "$OUT3" | sed 's/^/    | /'
hasnt "a struck-through CUT row is not a missed binding" "$OUT3" "DemoUrl"
has   "the CUT row leaves the binding denominator"       "$OUT3" "bindings 0/2"
has   "DESCRIBE alone cannot see the image bindings"     "$OUT3" "(LogoUrl)"
has   "and the scorer says why"                          "$OUT3" "DESCRIBE drops ImageUrl parameters"
OUT4=$(cd "$TMP" && node "$SUT" --no-log "$FIX/bind-contract.html" Catalog - "$FIX/bind-contract-alter.mdl" < "$BD" 2>&1)
echo "$OUT4" | sed 's/^/    | /'
has   "the ALTER script's ImageUrl bindings count"       "$OUT4" "bindings 2/2"
hasnt "no DESCRIBE note once the bindings are seen"      "$OUT4" "DESCRIBE drops"
OUT5=$(cd "$TMP" && node "$SUT" --no-log "$FIX/bind-contract.html" Catalog "$FIX/bind-contract-alter.mdl" 2>&1; echo "exit=$?")
has   "an ALTER with no CREATE is not a page"            "$OUT5" "exit=2"
if grep -q 'function contractRows' "$SUT"; then
  # The contract dimension reads the CSS column. "(already a ds.css candidate)" once
  # harvested `css` as an owed class; "#mxapp.theme-dark" is a compound selector whose class
  # IS owed — the fix must drop the first and keep the second.
  hasnt "a file name in the CSS cell is not a class"     "$OUT3" "(.css)"
  has   "a compound selector's class is still owed"      "$OUT3" "(.theme-dark)"
  has   "contract counts 4 classes, not 5"               "$OUT3" "contract 2/4"
else
  echo "  skip contract assertions: this page-fidelity.js has no contract dimension"
fi

echo "  -- a template comment naming <main> is not the page; nothing measured is not a score"
# commented-template.html reduces a field wireframe template (2026-10-02): its header comment
# says "inside <main>" and "AFTER </main>", and the scorer used to take the comment text as
# the page — every text dimension 0/0, the number made of bindings alone (master printed
# `fidelity 100% … bindings 2/2` for this file). See CAPTURE.md.
CT="$FIX/commented-template.html"
OUT6=$(cd "$TMP" && node "$SUT" --no-log "$CT" OrderInbox "$FIX/commented-template.mdl" 2>&1; echo "exit=$?")
echo "$OUT6" | sed 's/^/    | /'
has   "the comment is not the content boundary"         "$OUT6" "headings 2/2"
has   "the classes inside <main> are counted"           "$OUT6" "classes 6/22"
has   "the label says what it measures"                 "$OUT6" "text-match 85%"
has   "and says it is not a LOOK"                       "$OUT6" "it is not a LOOK"
has   "a scored page exits 0"                           "$OUT6" "exit=0"
EMPTY="$TMP/empty-main.html"
printf '<html><body><!-- inside <main> --><main></main><table class="bind"><tr><td>Grid</td><td>DATAGRID</td><td>Sales.ReviewTask</td></tr></table></body></html>' > "$EMPTY"
OUT7=$(cd "$TMP" && node "$SUT" --no-log "$EMPTY" OrderInbox "$FIX/commented-template.mdl" 2>&1; echo "exit=$?")
has   "bindings alone are UNMEASURED, not a score"      "$OUT7" "text-match UNMEASURED"
has   "UNMEASURED exits 3"                              "$OUT7" "exit=3"
hasnt "UNMEASURED prints no percentage"                 "$OUT7" "%   headings"

echo "  -- a Stub: caption scored as the build is 0%, and --stub still exempts it"
OUT8=$(cd "$TMP" && node "$SUT" --no-log "$CT" OrderInbox "$FIX/commented-template-stub.mdl" 2>&1; echo "exit=$?")
has   "a stub in the model scores 0%"                   "$OUT8" "text-match 0%"
has   "and says why"                                    "$OUT8" "STUB IN MODEL"
has   "stub-in-model exits 4"                           "$OUT8" "exit=4"
OUT9=$(cd "$TMP" && node "$SUT" --no-log --stub "$CT" OrderInbox "$FIX/commented-template-stub.mdl" 2>&1; echo "exit=$?")
hasnt "a declared stub is not flagged"                  "$OUT9" "STUB IN MODEL"
has   "a declared stub exits 0"                         "$OUT9" "exit=0"

echo "  -- snippet bodies in the input are page content; missing ones are named"
OUT10=$(cd "$TMP" && node "$SUT" --no-log "$CT" OrderInbox "$FIX/commented-template-snippets.mdl" 2>&1)
echo "$OUT10" | sed 's/^/    | /'
has   "the snippet's heading is found"                  "$OUT10" "headings 1/2"
has   "a run missing a snippet is marked partial"       "$OUT10" "(partial)"
has   "and names the snippet it could not see"          "$OUT10" "Sales.SNIPPET_InboxGrids"
SNIPONLY="$TMP/snip-only.mdl"
printf "create page Sales.OrderInbox (Title: 'x') {\n  snippetcall a (snippet: Sales.Gone)\n}\n" > "$SNIPONLY"
OUT11=$(cd "$TMP" && node "$SUT" --no-log "$CT" OrderInbox "$SNIPONLY" 2>&1; echo "exit=$?")
has   "a page made only of unseen snippets is UNMEASURED" "$OUT11" "exit=3"

echo
printf 'test-page-fidelity-mocks: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
