#!/bin/bash
# test-assemble-prototype.sh: pin what assemble-prototype.js promises about prototype.html.
#
# The prototype is an ASSEMBLED OUTPUT that a stakeholder clicks and three instruments read a
# screen back out of (page-fidelity.js, check-page-shell.sh, check-prototype-links.js). So the
# properties worth pinning are the ones a reader relies on without looking: one section per
# screen under the right route, links between wireframe FILES turned into routes, ds.css inlined
# once, the annotation apparatus hidden by default, and the same input giving the same bytes
# (a generated file that changes on every run is a file nobody can review in a diff).
#
# Fixtures are generated at runtime in a mktemp dir, never committed.
#
# Usage: bash test-assemble-prototype.sh [path-to-assemble-prototype.js]

set -u

TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
SUT="${1:-$TOOLKIT/project-bin/assemble-prototype.js}"
SUT="$(cd "$(dirname "$SUT")" && pwd)/$(basename "$SUT")"   # fixtures cd away; a relative $1 must survive

PASS=0; FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$3', got '$2'"; fi; }
has()  { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing '$3'" ;; esac; }
hasnt(){ case "$2" in *"$3"*) bad "$1" "unexpected '$3'" ;; *) ok "$1" ;; esac; }
count(){ printf '%s' "$1" | grep -o -- "$2" | wc -l | tr -d ' '; }

command -v node >/dev/null 2>&1 || { echo "test-assemble-prototype: node not available, skipping"; exit 0; }

printf 'test-assemble-prototype: %s\n' "$SUT"

# ── fixture: three screens, one named by data-route, one kebab-cased, one home ───────────
P="$TMP/proj"
mkdir -p "$P/design/wireframes"
cat > "$P/design/ds.css" <<'EOF'
:root { --ds-sentinel-token: #123456; }
.btn { color: var(--ds-sentinel-token); }
EOF
cat > "$P/design/wireframes/Home.html" <<'EOF'
<!doctype html>
<html><head><title>Start screen</title><link rel="stylesheet" href="../ds.css">
<style>
/* a comment naming {braces} must not break the scoper */
body { margin: 0 }
main{max-width:900px}
.tile, .card:is(.a, .b) { padding: 4px }
@media (max-width: 600px) { .tile { padding: 0 } }
@keyframes spin { from { transform: rotate(0) } to { transform: rotate(1turn) } }
</style></head>
<body>
<main><h1>Start</h1><a class="tile" href="OrderList.html">Orders</a></main>
<div class="wf-note">annotation text</div>
<table class="bind"><tr><th>Element</th><th>Widget</th><th>Datasource</th></tr>
<tr><td>Orders tile</td><td>action button</td><td>Nav to Order_Overview</td></tr></table>
</body></html>
EOF
cat > "$P/design/wireframes/OrderList.html" <<'EOF'
<html><head><title>Orders</title><link rel="stylesheet" href="../ds.css"></head>
<body>
<main><h1>Orders</h1><a href="./OrderDetail.html#top">Open order</a> <a href="#/home">Back</a>
<a href="https://example.invalid/Elsewhere.html">external</a></main>
</body></html>
EOF
cat > "$P/design/wireframes/OrderDetail.html" <<'EOF'
<html><head><title>Order</title><link rel="stylesheet" href="../ds.css"></head>
<body data-route="detail">
<main><h1>Order</h1><a href="OrderList.html">Back to list</a></main>
</body></html>
EOF

run() { ( cd "$P" && node "$SUT" "$@" 2>&1 ); }
code(){ ( cd "$P" && node "$SUT" "$@" >/dev/null 2>&1; printf '%s' "$?" ); }

echo "  -- assembles"
out="$(run)"
check "exit 0 on a valid wireframe set" "$(code)" "0"
has   "reports the screen count and default route" "$out" "3 screen(s)"
[ -f "$P/design/prototype.html" ] && ok "writes design/prototype.html" || bad "writes design/prototype.html" "no file"
H="$(cat "$P/design/prototype.html" 2>/dev/null)"

echo "  -- one section per screen, under the right route"
check "three screen sections"                  "$(count "$H" '<section data-route=')" "3"
has   "data-route on <body> wins"               "$H" '<section data-route="detail" data-source="OrderDetail.html"'
has   "no data-route: kebab-cased filename"     "$H" '<section data-route="order-list" data-source="OrderList.html"'
has   "home is the default route"               "$H" 'data-default-route="home"'
has   "every section carries its end marker"    "$H" '<!-- proto-end:order-list -->'

echo "  -- links"
has   "Other.html becomes #/route"              "$H" '<a class="tile" href="#/order-list">Orders</a>'
has   "./Other.html#part becomes #/route"       "$H" 'href="#/detail">Open order'
has   "a file named by data-route maps to it"   "$H" 'href="#/order-list">Back to list'
has   "an existing #/route link is kept"        "$H" 'href="#/home">Back'
has   "a non-wireframe .html link is untouched" "$H" 'href="https://example.invalid/Elsewhere.html"'
hasnt "no wireframe file name survives as a link" "$H" 'href="OrderList.html"'

echo "  -- design system and screen CSS"
check "ds.css inlined exactly once"             "$(count "$H" 'ds-sentinel-token: #123456')" "1"
hasnt "no per-screen link to ds.css remains"    "$H" 'href="../ds.css"'
has   "screen CSS is scoped to its section"     "$H" 'section[data-route="home"] main{max-width:900px}'
has   "a body rule targets the section"         "$H" 'section[data-route="home"] { margin: 0 }'
has   "selectors inside :is() are not split"    "$H" 'section[data-route="home"] .card:is(.a, .b)'
has   "@media rules are scoped inside"          "$H" 'section[data-route="home"] .tile { padding: 0 }'
has   "@keyframes are left alone"               "$H" '@keyframes spin { from { transform: rotate(0) }'

echo "  -- bindings toggle and screen index"
has   "bindings are hidden unless toggled"      "$H" 'body:not(.proto-show-bindings) #proto-screens'
has   "table.bind is in the hidden set"         "$H" 'table.bind'
has   "the toggle control exists"               "$H" 'id="proto-bindings"'
has   "the annotation itself is still in the page" "$H" '<table class="bind">'
has   "the index lists every route"             "$H" '<a href="#/detail">Order</a>'
has   "the index uses the screen's <title>"     "$H" '<a href="#/home">Start screen</a>'

echo "  -- self-contained and deterministic"
hasnt "no external script"                      "$H" '<script src='
hasnt "no external stylesheet"                  "$H" '<link rel="stylesheet"'
cp "$P/design/prototype.html" "$TMP/first.html"
run >/dev/null
if cmp -s "$TMP/first.html" "$P/design/prototype.html"; then ok "same input, same bytes"; else bad "same input, same bytes" "second run differs"; fi

echo "  -- index beats home; first file is the fallback"
cp "$P/design/wireframes/Home.html" "$P/design/wireframes/index.html"
sed 's/<body>/<body data-route="start">/' "$P/design/wireframes/Home.html" > "$P/design/wireframes/Home.html.tmp" && mv "$P/design/wireframes/Home.html.tmp" "$P/design/wireframes/Home.html"
run >/dev/null
has   "index is the default when present"       "$(cat "$P/design/prototype.html")" 'data-default-route="index"'
rm "$P/design/wireframes/index.html"
run >/dev/null
has   "no index/home: first screen by filename" "$(cat "$P/design/prototype.html")" 'data-default-route="start"'

echo "  -- input errors exit 2"
sed 's/<body data-route="start">/<body data-route="detail">/' "$P/design/wireframes/Home.html" > "$P/design/wireframes/Dup.html"
out="$(run)"
check "a duplicate route exits 2"               "$(code)" "2"
has   "and names both files"                    "$out" "claimed by both"
rm "$P/design/wireframes/Dup.html"
mkdir -p "$TMP/empty/design/wireframes"
check "no wireframes exits 2"                   "$( cd "$TMP/empty" && node "$SUT" >/dev/null 2>&1; printf '%s' "$?" )" "2"

printf '\ntest-assemble-prototype: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
