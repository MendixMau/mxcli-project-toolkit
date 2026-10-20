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

echo "  -- DynamicClasses in both shapes: quoted (a headerless script) and bare (mxcli v0.25 DESCRIBE)"
# v0.25.0 DESCRIBE prints `DynamicClasses: if … then 'is-active' else 'is-idle'` with no outer
# quotes, under --mdl 0 too; the quoted-form regex read is-active as undeclared (classes 1/2).
# The describe input is a verbatim capture; the wireframe is synthetic and marked.
OUT12=$(cd "$TMP" && node "$SUT" --no-log "$FIX/dynclasses.html" Dyn_Probe "$FIX/dynclasses-describe-v025.mdl" 2>&1)
has   "bare DynamicClasses (v0.25 DESCRIBE) declares its classes" "$OUT12" "classes 2/2"
OUT13=$(cd "$TMP" && node "$SUT" --no-log "$FIX/dynclasses.html" Dyn_Probe "$FIX/dynclasses-script.mdl" 2>&1)
has   "quoted DynamicClasses (headerless script) still does"      "$OUT13" "classes 2/2"

echo "  -- #158: text is matched against what the page SHOWS, on whole words"
# The MDL is a REAL capture: mxcli DESCRIBE of Sales.Product_Overview (context-pack fixture).
# product-overview.html is synthetic and marked; see CAPTURE.md. On master every heading and
# action below read as present — "Product overview" from the page NAME, "Deactivate product"
# from the microflow and entity names, "Add" because a label with no >3-char word passed
# vacuously — and the run printed 89%.
CAP="$TOOLKIT/tests/wave2/fixtures/context-pack/capture/describe/PAGE__Sales.Product_Overview.out"
OUT14=$(cd "$TMP" && node "$SUT" --no-log "$FIX/product-overview.html" Product_Overview - < "$CAP" 2>&1)
echo "$OUT14" | sed 's/^/    | /'
has   "a heading the page shows (Title/H1 'Catalog') is found"     "$OUT14" "headings 1/2"
has   "a heading only the page NAME carries is missed"             "$OUT14" "heading: Product overview"
has   "a button caption is matched on the button, all words"       "$OUT14" "action:  Deactivate product"
has   "a short label is required, not vacuous"                     "$OUT14" "action:  Add"
has   "real captions still match (New item, Edit, Delete)"         "$OUT14" "actions 3/5"
has   "the sub-title paragraph is still found"                     "$OUT14" "content 1/1"

echo "  -- #157: ButtonStyle renders btn + btn-<style>; no ButtonStyle is btn-default"
has   "btn / btn-primary / btn-danger / btn-default are declared"  "$OUT14" "classes 8/9"
CLS14=$(printf '%s\n' "$OUT14" | grep '^  classes:' || true)
hasnt "btn-primary is not missed"                                  "$CLS14" "btn-primary"
hasnt "btn-default (DESCRIBE omits Default) is not missed"         "$CLS14" "btn-default"
has   "a class the page really lacks is still missed"              "$CLS14" "row-actions"

echo "  -- #157: chrome comes from the page's layout, or from --chrome"
# layout-app-default.mdl is upstream mxcli's own layout example (verbatim, see CAPTURE.md);
# master scored the layout's region classes as classes the page failed to declare (0/2).
LA="$FIX/layout-app-default.mdl"
OUT15=$(cd "$TMP" && node "$SUT" --no-log "$FIX/layout-app-default.html" Home "$LA" 2>&1)
echo "$OUT15" | sed 's/^/    | /'
has   "the layout's classes leave the denominator"                 "$OUT15" "classes 0/0"
has   "and are reported as chrome, not dropped silently"           "$OUT15" "chrome (layout-supplied, not scored): region-sidebar region-content"
has   "the run names the layout it read"                           "$OUT15" "layout LayoutTest.App_Default read from input"
PAGEONLY=$(sed -n '/^create or modify page/,$p' "$LA")
OUT16=$(cd "$TMP" && printf '%s\n' "$PAGEONLY" | node "$SUT" --no-log "$FIX/layout-app-default.html" Home - 2>&1)
has   "without the layout, its classes are owed (unchanged default)" "$OUT16" "classes 0/2"
OUT17=$(cd "$TMP" && printf '%s\n' "$PAGEONLY" | node "$SUT" --no-log --chrome region-sidebar,region-content "$FIX/layout-app-default.html" Home - 2>&1)
has   "--chrome names them instead"                                "$OUT17" "classes 0/0"
has   "--chrome classes are reported as chrome too"                "$OUT17" "chrome (layout-supplied, not scored): region-sidebar region-content"

echo "  -- a multi-line ALTER set, plurals, and a re-styled button (review of #318)"
# alter-multiline-* is a SYNTHETIC counter-case (see CAPTURE.md). The first cut of the caption
# match ended an ALTER `set` segment at the first newline and dropped 'Approve order'; and
# whole-word matching read "Orders" against the title 'Order' as missing.
AM="$FIX/alter-multiline"
OUT18=$(cd "$TMP" && node "$SUT" --no-log "$AM.html" Order_Overview "$AM-page.mdl" "$AM-alter.mdl" 2>&1)
echo "$OUT18" | sed 's/^/    | /'
hasnt "a caption set by a multi-line ALTER is seen"         "$OUT18" "action:  Approve order"
hasnt "a plural heading matches its singular title"         "$OUT18" "heading: Orders"
has   "the multi-line ALTER's ButtonStyle is seen"          "$OUT18" "classes 2/2"
has   "a different caption is still a miss"                 "$OUT18" "action:  Save changes"
RESTYLE="$TMP/restyle.mdl"
printf "create page M.R (Title: 'R', Layout: Atlas_Core.Atlas_Default) {\n  actionbutton bGo (Caption: 'Go', Action: close_page, ButtonStyle: Warning)\n}\nalter page M.R {\n  set ButtonStyle = Success on bGo;\n}\n" > "$RESTYLE"
printf '<main><h1>R</h1><button class="btn btn-warning">Go</button></main>' > "$TMP/restyle.html"
OUT19=$(cd "$TMP" && node "$SUT" --no-log "$TMP/restyle.html" R "$RESTYLE" 2>&1)
has   "an ALTER that re-styles a button drops its old class" "$OUT19" "classes: btn-warning"
hasnt "no layout hint when no missed class looks like chrome" "$OUT19" "is not in the input"
hasnt "no layout hint for page classes (seg-tabs, dg-*)"     "$OUT6"  "is not in the input"
has   "the hint names the layout when region-* is missed"   "$OUT16" "layout LayoutTest.App_Default is not in the input"

echo "  -- a popup wireframe scores the dialog, not the caller's page behind it (#471)"
# fixtures/page-fidelity-popup/CAPTURE.md: the MDL is a verbatim mxcli v0.23.0 describe of a
# popup page; the wireframe draws it in the issue's shape, .popup-stage > .shell-behind +
# .dialog-scrim > .dialog, with the caller's overview (div.main, h1, card) behind the scrim.
PF="$TOOLKIT/tests/wave2/fixtures/page-fidelity-popup"
OUT20=$(cd "$TMP" && node "$SUT" --no-log "$PF/product-newedit-popup.html" Product_NewEdit "$PF/product-newedit-describe-v023.mdl" 2>&1)
echo "$OUT20" | sed 's/^/    | /'
hasnt "the caller's h1 behind the scrim is not scored"      "$OUT20" "heading: Product catalog"
hasnt "the caller's card behind the scrim is not scored"    "$OUT20" "heading: Active items"
hasnt "the caller's button is not an owed action"           "$OUT20" "action:  New item"
has   "the dialog's fields and buttons all match"           "$OUT20" "text-match 100%"
sed 's/class="dialog" /class="sheet" /' "$PF/product-newedit-popup.html" > "$TMP/stage-only.html"
OUT21=$(cd "$TMP" && node "$SUT" --no-log "$TMP/stage-only.html" Product_NewEdit "$PF/product-newedit-describe-v023.mdl" 2>&1)
hasnt "a .popup-stage with no .dialog still drops the shell" "$OUT21" "heading: Product catalog"
has   "...and still scores what is in front of it"           "$OUT21" "headings 1/1"
sed 's/class="dialog" /class="panel" /; s/class="popup-stage"/class="stage"/' "$PF/product-newedit-popup.html" > "$TMP/no-popup.html"
OUT22=$(cd "$TMP" && node "$SUT" --no-log "$TMP/no-popup.html" Product_NewEdit "$PF/product-newedit-describe-v023.mdl" 2>&1)
has   "popup evidence but no .dialog and no stage: the old div.main boundary, as before" "$OUT22" "heading: Product catalog"
# Popup evidence from the page alone: no stage, no scrim, but the MDL names Atlas_Core.PopupLayout.
sed 's/class="popup-stage"/class="stage"/; s/class="dialog-scrim"/class="scrim"/' "$PF/product-newedit-popup.html" > "$TMP/layout-only.html"
OUT23=$(cd "$TMP" && node "$SUT" --no-log "$TMP/layout-only.html" Product_NewEdit "$PF/product-newedit-describe-v023.mdl" 2>&1)
hasnt "a popup layout in the MDL is evidence enough: the shell is not scored" "$OUT23" "heading: Product catalog"
has   "...and the dialog is"                                                    "$OUT23" "text-match 100%"
echo "  -- a full-page wireframe with an inline .dialog scores as before (review of #482)"
# .dialog is the design system's component; a full page may draw an open confirm with it. On
# master this wireframe scored 39% (the confirm counted as page content); the first cut of #471
# scored the confirm alone, 5%. No stage, no scrim, a full-page layout: no popup evidence.
sed 's#<div class="wf-screen">#&<div class="dialog" role="dialog"><div class="dialog-head"><h2>Delete project?</h2></div><p>This cannot be undone.</p><div class="dialog-foot"><button class="btn">Cancel</button><button class="btn btn-danger">Delete</button></div></div>#' \
  "$FIX/grouped-overview.html" > "$TMP/inline-dialog.html"
grep -q 'Delete project' "$TMP/inline-dialog.html" || bad "inline-dialog setup: the sed did not insert the confirm" ""
OUT24=$(cd "$TMP" && node "$SUT" --no-log "$TMP/inline-dialog.html" Demo_Overview "$FIX/demo-overview.mdl" 2>&1)
echo "$OUT24" | sed 's/^/    | /'
has   "an inline confirm does not become the boundary: the master score, unchanged" "$OUT24" "text-match 39%   headings 1/2  actions 1/3  content 1/2  classes 1/5"

echo
printf 'test-page-fidelity-mocks: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
