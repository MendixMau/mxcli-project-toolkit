#!/bin/bash
# test-prototype-route.sh: pin "same screen, same verdict, as a file and as a route".
#
# The build checks read a screen either from its per-screen wireframe
# (design/wireframes/<Screen>.html) or from the assembled clickable prototype
# (design/prototype.html#/<route>). The second form is only worth having if it is INVISIBLE to
# the verdict. The assembler scopes each screen's CSS under its section, and page-fidelity.js
# reads that CSS to tell bound-data mocks from structure; a reader that forgot to undo the
# scoping would score a different page and print a perfectly normal report about it. So every
# assertion below compares the two forms against each other, not against a number.
#
# Also pinned: an unknown route is an input error (exit 2) naming the routes that do exist, and
# a map row whose prototype file is missing is still reported as a stale row.
#
# Fixtures are generated at runtime in a mktemp dir, never committed.
#
# Usage: bash test-prototype-route.sh [path-to-prototype-route.js]

set -u

TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
SUT="${1:-$TOOLKIT/project-bin/prototype-route.js}"
SUT="$(cd "$(dirname "$SUT")" && pwd)/$(basename "$SUT")"   # fixtures cd away; a relative $1 must survive
BIN="$(dirname "$SUT")"

PASS=0; FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$3', got '$2'"; fi; }
has()  { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing '$3'" ;; esac; }

command -v node >/dev/null 2>&1 || { echo "test-prototype-route: node not available, skipping"; exit 0; }

printf 'test-prototype-route: %s\n' "$SUT"

# ── fixture: two screens; OrderList carries a wireframe-local mock class used twice ──────
P="$TMP/proj"
mkdir -p "$P/design/wireframes" "$P/mdlsource"
printf '.card { padding: 8px }\n' > "$P/design/ds.css"
cat > "$P/design/wireframes/Home.html" <<'EOF'
<html><head><link rel="stylesheet" href="../ds.css"><style>main{max-width:900px}</style></head>
<body>
<nav class="tabs"><a href="OrderList.html">Orders</a></nav>
<main><h1>Start</h1><p>Welcome back to the order desk, pick a queue.</p>
<button>Open orders</button></main>
</body></html>
EOF
cat > "$P/design/wireframes/OrderList.html" <<'EOF'
<html><head><link rel="stylesheet" href="../ds.css">
<style>
main{max-width:900px}
.qcard { border: 1px solid #ccc }
.page-head { display: flex }
</style></head>
<body>
<nav class="tabs"><a href="Home.html">Home</a></nav>
<main>
<div class="page-head"><h1>Orders</h1><button>New order</button></div>
<div class="qcard"><p>Sample order for a customer somewhere far away</p></div>
<div class="qcard"><p>Another sample order that a bound list would render</p></div>
<p class="card">Orders waiting for approval are listed first.</p>
</main>
<table class="bind"><tr><th>Element</th><th>Widget</th><th>Datasource</th></tr>
<tr><td>List</td><td>list view</td><td>Sales.Order</td></tr></table>
</body></html>
EOF
cat > "$P/mdlsource/pages.mdl" <<'EOF'
CREATE OR REPLACE PAGE Sales.Order_Overview
  (Title: 'Orders', Layout: Atlas_Core.Atlas_Default, Folder: 'F')
  {
    HEADER hdr { DYNAMICTEXT h1 (Content: 'Orders', RenderMode: H1) }
    ACTIONBUTTON btnNew (Caption: 'New order')
    LISTVIEW lv (DataSource: DATABASE Sales.Order) { }
  }
EOF
( cd "$P" && node "$BIN/assemble-prototype.js" >/dev/null 2>&1 )
[ -f "$P/design/prototype.html" ] || { echo "test-prototype-route: assembler produced nothing"; exit 1; }

echo "  -- prototype-route.js"
routes="$(node "$SUT" --list "$P/design/prototype.html" | tr '\n' ' ')"
check "lists every route"                         "$routes" "home order-list "
out="$(node "$SUT" "$P/design/prototype.html#/nope" 2>&1)"; rc=$?
check "unknown route exits 2"                     "$rc" "2"
has   "and names the known routes"                "$out" "known routes: #/home #/order-list"

echo "  -- page-fidelity.js: same score as a file and as a route"
FID="$BIN/page-fidelity.js"
a="$(cd "$P" && node "$FID" --no-log design/wireframes/OrderList.html Order_Overview mdlsource/pages.mdl 2>&1)"
b="$(cd "$P" && node "$FID" --no-log 'design/prototype.html#/order-list' Order_Overview mdlsource/pages.mdl 2>&1)"
check "identical report, every line"              "$b" "$a"
has   "and the mock rule saw the screen CSS"      "$b" "bound-data mocks (wireframe-local, text not scored): qcard"
out="$(cd "$P" && node "$FID" --no-log 'design/prototype.html#/orders' Order_Overview mdlsource/pages.mdl 2>&1)"; rc=$?
check "unknown route exits 2"                     "$rc" "2"
has   "and names the known routes"                "$out" "#/order-list"

echo "  -- check-page-shell.sh: same verdict as a file and as a route"
SHELL_SUT="$BIN/check-page-shell.sh"
shell_run() {   # $1 = map target
  printf 'Order_Overview\t%s\n' "$1" > "$P/design/wireframes/PAGE-MAP.tsv"
  ( cd "$P" && bash "$SHELL_SUT" mdlsource/pages.mdl 2>&1; printf 'rc=%s' "$?" )
}
a="$(shell_run OrderList.html)"
b="$(shell_run '../prototype.html#/order-list')"
c="$(shell_run 'design/prototype.html#/order-list')"
check "route relative to the wireframes dir"      "$b" "$a"
check "route relative to the project root"        "$c" "$a"
has   "and the checks did fire on the screen"     "$a" "its wireframe draws a 900px column"
has   "the top-bar check read the route too"      "$b" "its wireframe draws a top-bar shell"
out="$(shell_run '../prototype.html#/orders')"
has   "unknown route exits 2"                     "$out" "rc=2"
has   "and names the known routes"                "$out" "known routes: #/home #/order-list"
out="$(shell_run '../gone.html#/order-list')"
has   "a missing prototype file is a stale row"   "$out" "which does not exist"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
