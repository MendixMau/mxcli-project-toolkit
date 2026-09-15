#!/bin/bash
# test-prototype-links.sh: pin what check-prototype-links.js fails on, and what it only warns on.
#
# The check is the mechanical half of design-artifacts.md Step 3b (and, with --brd, of
# brd-validation.md check 8). Each failure kind gets its own fixture that differs from a clean
# prototype (or a clean BRD) in exactly one place, so a pass here means that one
# defect was seen, not that something else happened to trip the exit code. The lenient case
# (a screen with no table.bind warns instead of failing) is pinned too, because breaking it would
# fail every wireframe drawn before the data-bind convention existed.
#
# Fixtures are generated at runtime in a mktemp dir, never committed.
#
# Usage: bash test-prototype-links.sh [path-to-check-prototype-links.js]

set -u

TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
SUT="${1:-$TOOLKIT/project-bin/check-prototype-links.js}"
SUT="$(cd "$(dirname "$SUT")" && pwd)/$(basename "$SUT")"   # fixtures cd away; a relative $1 must survive
BIN="$(dirname "$SUT")"

PASS=0; FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$3', got '$2'"; fi; }
has()  { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing '$3'" ;; esac; }
hasnt(){ case "$2" in *"$3"*) bad "$1" "unexpected '$3'" ;; *) ok "$1" ;; esac; }

command -v node >/dev/null 2>&1 || { echo "test-prototype-links: node not available, skipping"; exit 0; }

printf 'test-prototype-links: %s\n' "$SUT"

TAB="$(printf '\t')"

# clean <dir>: home -> list -> detail -> home, every control bound, cut, or a live route link.
clean() {
  mkdir -p "$1/design/wireframes"
  cat > "$1/design/wireframes/Home.html" <<'EOF'
<html><body>
<main><h1>Home</h1><a href="#/order-list">Orders</a></main>
</body></html>
EOF
  cat > "$1/design/wireframes/OrderList.html" <<'EOF'
<html><body>
<main><h1>Orders</h1>
<a href="OrderDetail.html">Open</a>
<button data-bind="New order">New order</button>
<button data-bind="export-row">Export</button>
<button data-cut="no use case asks for printing">Print</button>
</main>
<table class="bind"><tr><th>Element</th><th>Widget</th><th>Datasource</th></tr>
<tr><td>New order</td><td>button</td><td>ACT_Order_New</td></tr>
<tr id="export-row"><td>Export button</td><td>button</td><td>ACT_Order_Export</td></tr></table>
</body></html>
EOF
  cat > "$1/design/wireframes/OrderDetail.html" <<'EOF'
<html><body>
<main><h1>Order</h1><a href="Home.html">Home</a></main>
</body></html>
EOF
}
assemble() { ( cd "$1" && node "$BIN/assemble-prototype.js" >/dev/null 2>&1 ); }
run()  { ( cd "$1" && node "$SUT" 2>&1 ); }
code() { ( cd "$1" && node "$SUT" >/dev/null 2>&1; printf '%s' "$?" ); }

echo "  -- a clean prototype passes"
d="$TMP/clean"; clean "$d"; assemble "$d"
out="$(run "$d")"
check "exit 0"                                    "$(code "$d")" "0"
has   "summary counts screens and failures"       "$out" "3 screen(s)"
has   "zero failures"                             "$out" "0 failure(s), 0 warning(s)"
hasnt "the Print cut is not reported"             "$out" "Print"

echo "  -- dead link"
d="$TMP/dead"; clean "$d"
sed -i.bak 's|href="Home.html"|href="#/start"|' "$d/design/wireframes/OrderDetail.html"
printf '<html><body><main><h1>Home</h1><a href="#/order-list">Orders</a><a href="#/order-detail">Last order</a></main></body></html>\n' \
  > "$d/design/wireframes/Home.html"
assemble "$d"
out="$(run "$d")"
check "exit 1"                                    "$(code "$d")" "1"
has   "one tab-separated line naming the route"   "$out" "order-detail${TAB}dead-link${TAB}#/start"
hasnt "no other failure kind"                     "$out" "orphan"

echo "  -- orphan"
d="$TMP/orphan"; clean "$d"
printf '<html><body><main><h1>Help</h1><a href="#/home">Home</a></main></body></html>\n' > "$d/design/wireframes/Help.html"
assemble "$d"
out="$(run "$d")"
check "exit 1"                                    "$(code "$d")" "1"
has   "names the unreachable screen"              "$out" "help${TAB}orphan"
hasnt "the default route is never an orphan"      "$out" "home${TAB}orphan"

echo "  -- unbound button"
d="$TMP/unbound"; clean "$d"
sed -i.bak 's|<button data-cut="no use case asks for printing">Print</button>|<button>Print</button>|' "$d/design/wireframes/OrderList.html"
assemble "$d"
out="$(run "$d")"
check "exit 1"                                    "$(code "$d")" "1"
has   "names the control"                         "$out" "order-list${TAB}unbound${TAB}Print: no data-bind and no data-cut"

echo "  -- data-bind naming a row that does not exist"
d="$TMP/stale"; clean "$d"
sed -i.bak 's|data-bind="New order"|data-bind="Create order"|' "$d/design/wireframes/OrderList.html"
assemble "$d"
out="$(run "$d")"
check "exit 1"                                    "$(code "$d")" "1"
has   "says the row is missing"                   "$out" "data-bind=\"Create order\" names no row"

echo "  -- a screen with no table.bind only warns"
d="$TMP/lenient"; clean "$d"
printf '<html><body><main><h1>Order</h1><a href="Home.html">Home</a><button>Cancel</button></main></body></html>\n' \
  > "$d/design/wireframes/OrderDetail.html"
assemble "$d"
out="$(run "$d")"
check "exit 0"                                    "$(code "$d")" "0"
has   "reported as a warning"                     "$out" "order-detail${TAB}unbound-warning${TAB}Cancel"
has   "and counted as one"                        "$out" "0 failure(s), 1 warning(s)"

echo "  -- inspecting nothing is not a pass"
d="$TMP/none"; mkdir -p "$d/design"
check "missing prototype exits 2"                 "$(code "$d")" "2"
printf '<html><body><p>not assembled</p></body></html>\n' > "$d/design/prototype.html"
check "a page with no screens exits 2"            "$(code "$d")" "2"

brd() { ( cd "$1" && shift && node "$SUT" "$@" 2>&1 ); }
brdcode() { ( cd "$1" && shift && node "$SUT" "$@" >/dev/null 2>&1; printf '%s' "$?" ); }

# A BRD whose use cases walk every screen of the clean prototype. The route sits in `routes` for
# UC1 and only in mainFlow prose for UC2, because both are how people write it.
brdfile() {
  cat > "$1" <<'EOF'
{ "id": "F001",
  "useCases": [
    { "id": "UC1", "title": "Open an order", "routes": ["#/home", "#/order-list", "#/order-detail"] },
    { "id": "UC2", "title": "Start an order", "mainFlow": ["1. User opens #/order-list."] }
  ],
  "pages": [ { "name": "Order_Overview", "route": "#/order-list" } ] }
EOF
}

echo "  -- --brd: every screen walked by a use case passes"
d="$TMP/clean"; mkdir -p "$d/brd"; brdfile "$d/brd/F001.brd.json"
out="$(brd "$d" --brd brd/F001.brd.json)"
check "exit 0"                                    "$(brdcode "$d" --brd brd/F001.brd.json)" "0"
has   "summary counts BRD routes"                 "$out" "3 BRD route(s)"
check "a directory reads its *.brd.json"          "$(brdcode "$d" --brd brd)" "0"

echo "  -- --brd: a route the BRD names that no screen has"
d="$TMP/brdunknown"; clean "$d"; assemble "$d"; mkdir -p "$d/brd"; brdfile "$d/brd/F001.brd.json"
sed -i.bak 's|"#/order-detail"\]|"#/order-detail", "#/order-edit"]|' "$d/brd/F001.brd.json"
out="$(brd "$d" --brd brd/F001.brd.json)"
check "exit 1"                                    "$(brdcode "$d" --brd brd/F001.brd.json)" "1"
has   "names the route and the use case"          "$out" "order-edit${TAB}brd-unknown-route${TAB}named by UC1 (F001.brd.json)"

echo "  -- --brd: a screen no use case walks"
sed -i.bak 's|, "#/order-detail", "#/order-edit"\]|]|' "$d/brd/F001.brd.json"
out="$(brd "$d" --brd brd/F001.brd.json)"
check "exit 1"                                    "$(brdcode "$d" --brd brd/F001.brd.json)" "1"
has   "names the uncovered screen"                "$out" "order-detail${TAB}uncovered"
hasnt "a walked screen is not reported"           "$out" "order-list${TAB}uncovered"

echo "  -- --brd: data-chrome exempts a screen, and a page listing alone does not cover"
sed -i.bak 's|<html><body>|<html><body data-chrome="shared footer target">|' "$d/design/wireframes/OrderDetail.html"
assemble "$d"
check "chrome screen is exempt: exit 0"           "$(brdcode "$d" --brd brd/F001.brd.json)" "0"
sed -i.bak 's|"mainFlow": \["1. User opens #/order-list."\]|"mainFlow": []|; s|"#/home", "#/order-list"\]|"#/home"]|' "$d/brd/F001.brd.json"
out="$(brd "$d" --brd brd/F001.brd.json)"
has   "order-list only in pages[] is uncovered"   "$out" "order-list${TAB}uncovered"

echo "  -- --brd: markdown is scanned as text"
printf '# F001\n\nUC1 walks `#/home -> #/order-list -> #/order-detail`.\n' > "$d/brd/F001.md"
check "exit 0"                                    "$(brdcode "$d" --brd brd/F001.md)" "0"

echo "  -- --brd: a BRD that names no route is not a pass"
printf '{"id":"F002","useCases":[{"id":"UC1","mainFlow":["1. User opens the list"]}]}\n' > "$d/brd/F002.brd.json"
check "exit 2"                                    "$(brdcode "$d" --brd brd/F002.brd.json)" "2"
check "a missing BRD exits 2"                     "$(brdcode "$d" --brd brd/nope.json)" "2"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
