#!/bin/bash
# test-design-reaches-app.sh — pin check-design-reaches-app.sh against the state that shipped.
#
# The instrument under test answers one question no other check in this toolkit asks: did the
# design system ARRIVE in the built app. It exists because on a real field run (2026-09-09) the
# answer was no for two whole build phases while every other check was green.
#
# What is worth pinning here, and the happy path is the least of it:
#
#   1. THE SHIPPED STATE MUST FAIL. `built-broken.css` is the real thing: 18 tokens present in
#      the built sheet, every framework knob still on its own default, not one component class
#      ported. If this fixture ever passes, the instrument has stopped instrumenting.
#
#   2. TOKENS ARRIVING IS NOT THE DESIGN SYSTEM ARRIVING. `built-broken-classes.css` binds every
#      knob correctly and still ships zero classes. The sibling script
#      check-design-portability.sh opens by asserting "tokens port into Mendix perfectly", and
#      that sentence is what made everyone comfortable — so the two halves are pinned apart.
#
#   3. A SCOPED BINDING IS NOT A BINDING. `built-scoped-only.css` binds every knob inside
#      `:root.theme-neutral`, a theme the app is not wearing. This case exists in BOTH
#      directions: the instrument's first draft read "last occurrence in the file" and reported
#      a correctly bound knob as unbound, because the real Atlas sheet declares
#      --brand-primary inside `:root.theme-neutral` AFTER the bare `:root`. See
#      fixtures/design-reaches-app/CAPTURE.md.
#
#   4. NO BUILD IS NOT A PASS. The whole defect class lives between the source and the build, so
#      an instrument that green-lights a project with no compiled stylesheet is worse than
#      absent. Exit 2, and 2 must not be confused with 0.
#
#   5. BOTH LAYOUTS, AND NO SILENT ZERO. On a two-tree checkout the knob file sits under app/;
#      a knob file the instrument cannot find or read reports UNMEASURED and exits 2, never
#      "0 of 0 knobs bound" under a clean verdict (field run 2026-09-28).
#
# Usage: bash test-design-reaches-app.sh [path-to-check-design-reaches-app.sh]

set -u

TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
SUT="${1:-$TOOLKIT/project-bin/check-design-reaches-app.sh}"
SUT="$(cd "$(dirname "$SUT")" && pwd)/$(basename "$SUT")"   # fixtures cd away; a relative $1 must survive
FIX="$TOOLKIT/tests/wave2/fixtures/design-reaches-app"

PASS=0; FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$3', got '$2'"; fi; }
has()  { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing '$3'" ;; esac; }
hasnt(){ case "$2" in *"$3"*) bad "$1" "unexpected '$3'" ;; *) ok "$1" ;; esac; }

if [ ! -x "$SUT" ]; then
  printf 'test-design-reaches-app: %s is not executable\n' "$SUT" >&2
  exit 2
fi

# A project root shaped the way the instrument reads one: a design system, a built stylesheet,
# and the framework's customization file that enumerates its own knobs.
#   $1 project dir   $2 which built-*.css   $3 $use-css-variables value ("" to omit)
project() {
  d="$TMP/$1"; rm -rf "$d"
  mkdir -p "$d/design" "$d/deployment/web" "$d/theme/web" "$d/themesource/moc/web"
  cp "$FIX/ds.css" "$d/design/ds.css"
  [ -n "$2" ] && cp "$FIX/$2" "$d/deployment/web/theme.compiled.css"
  # The framework customization file: its uncommented :root declarations ARE the knob list.
  cat > "$d/theme/web/custom-variables.scss" <<'EOF'
:root {
  --brand-primary: #264ae5;
  --font-family-base: "Poppins", sans-serif;
  --font-size-default: 14px;
  --border-radius-default: 4px;
//   --link-color: var(--brand-primary);
}
EOF
  [ -n "$3" ] && printf '$use-css-variables: %s;\n' "$3" >> "$d/theme/web/custom-variables.scss"
  printf '%s' "$d"
}

run() { ( cd "$1" && bash "$SUT" 2>&1 ); }
code() { ( cd "$1" && bash "$SUT" >/dev/null 2>&1; printf '%s' "$?" ); }

printf 'test-design-reaches-app: %s\n' "$SUT"

# ── 1. the state that shipped ───────────────────────────────────────────────────────────────
d="$(project broken built-broken.css true)"
out="$(run "$d")"
check "the shipped state exits 1"                 "$(code "$d")" "1"
has   "names the unbound knobs with a denominator" "$out" "of 4 framework knobs are bound"
has   "reports 0 knobs bound"                      "$out" "0 of 4 framework knobs are bound"
has   "reports the classes never arrived"          "$out" "design-system classes exist"
has   "states the token denominator"               "$out" "tokens arrived  18 of 18"

# ── 2. tokens arriving is not the design system arriving ────────────────────────────────────
d="$(project bc built-broken-classes.css true)"
out="$(run "$d")"
check "bound knobs + zero classes still exits 1"  "$(code "$d")" "1"
has   "says the classes are the failure"           "$out" "0 of 5 design-system classes exist"
hasnt "does not blame the knobs"                   "$out" "0 of 4 framework knobs are bound"

# ── 3. a scoped binding is not a binding ────────────────────────────────────────────────────
d="$(project scoped built-scoped-only.css true)"
out="$(run "$d")"
check "a theme-scoped binding exits 1"            "$(code "$d")" "1"
has   "counts the scoped binding as unbound"       "$out" "0 of 4 framework knobs are bound"

# ── 4. the fixed state ──────────────────────────────────────────────────────────────────────
d="$(project fixed built-fixed.css true)"
out="$(run "$d")"
check "the fixed state exits 0"                   "$(code "$d")" "0"
has   "reports all four knobs bound"               "$out" "knobs bound     4 of 4"
has   "reports all classes arrived"                "$out" "classes arrived 5 of 5"
has   "reports all tokens arrived"                 "$out" "tokens arrived  18 of 18"

# ── 5. no build is not a pass ───────────────────────────────────────────────────────────────
d="$(project nobuild "" true)"
check "a project with no built stylesheet exits 2" "$(code "$d")" "2"
out="$(run "$d")"
has   "says so out loud"                           "$out" "no BUILT stylesheet found"
has   "refuses to be read as a pass"               "$out" "NOT a pass"

# ── 5b. the toolkit's full build output (.mxtk/build/model/deployment/, #686) ──────────────
# Toolkit builds no longer write the app's deployment/; the copy's compiled theme is read, and
# the newer of the two wins (the same rule as the .docker/ tree).
d="$(project mxtkonly "" true)"; mkdir -p "$d/.mxtk/build/model/deployment/web"
cp "$FIX/built-fixed.css" "$d/.mxtk/build/model/deployment/web/theme.compiled.css"
check "only the toolkit build copy has a compiled theme: measured, exits 0" "$(code "$d")" "0"
d="$(project mxtknewer built-broken.css true)"; mkdir -p "$d/.mxtk/build/model/deployment/web"
touch -t 202601010000 "$d/deployment/web/theme.compiled.css"
cp "$FIX/built-fixed.css" "$d/.mxtk/build/model/deployment/web/theme.compiled.css"
check "the copy's theme is newer than deployment/'s: the copy wins (exit 0)" "$(code "$d")" "0"
touch -t 202601010000 "$d/.mxtk/build/model/deployment/web/theme.compiled.css"; touch "$d/deployment/web/theme.compiled.css"
check "deployment/'s theme is newer: it wins (the broken one, exit 1)" "$(code "$d")" "1"

# ── 6. no design system is not a pass either ────────────────────────────────────────────────
d="$(project nods built-fixed.css true)"
rm -f "$d/design/ds.css"
check "a project with no design system exits 2"    "$(code "$d")" "2"

# ── 7. the dead SCSS bridge, and only where it is dead ──────────────────────────────────────
d="$(project bridge built-fixed.css true)"
printf '$brand-primary: var(--brand);\n' > "$d/themesource/moc/web/main.scss"
out="$(run "$d")"
check "a dead SCSS bridge exits 1"                "$(code "$d")" "1"
has   "names the file and line"                    "$out" "main.scss:1"
has   "explains it compiles to nothing"            "$out" "compiles to nothing"

# The SAME line is the CORRECT bridge where the theme does not run on custom properties, and
# reporting it there is how a check earns being switched off.
d="$(project bridge-false built-fixed.css false)"
printf '$brand-primary: var(--brand);\n' > "$d/themesource/moc/web/main.scss"
out="$(run "$d")"
hasnt "does not fire when \$use-css-variables is false" "$out" "compiles to nothing"

# ── 8. the framework's own themesource is not the project's to fix ──────────────────────────
d="$(project vendor built-fixed.css true)"
mkdir -p "$d/themesource/atlas_core/web"
printf '$brand-primary: var(--brand);\n' > "$d/themesource/atlas_core/web/main.scss"
check "a vendored atlas_core file is not reported" "$(code "$d")" "0"

# ── 9. both layouts: the app under app/ ─────────────────────────────────────────────────────
# The theme, themesource and deployment trees sit beside the .mpr. On a two-tree checkout
# (design/ and mdlsource/ at the repo root, the app under app/) the instrument used to read
# theme/web/custom-variables.scss from the root, find nothing, and print "0 of 0 knobs bound"
# under a clean verdict. Field run 2026-09-28: 0 of 0 by default, 26 of 30 with the path given
# by hand. The layout below is the real one's, path for path (see CAPTURE.md).
two_tree() {
  d="$(project "$1" "$2" "$3")"
  mkdir -p "$d/app" "$d/mdlsource"
  mv "$d/theme" "$d/deployment" "$d/themesource" "$d/app/"
  [ "$4" = "mpr" ] && : > "$d/app/App.mpr"
  printf '%s' "$d"
}
d="$(two_tree tt built-fixed.css true mpr)"
out="$(run "$d")"
check "two-tree (.mpr under app/) exits 0"         "$(code "$d")" "0"
has   "two-tree finds the knob file under app/"     "$out" "knob file       app/theme/web/custom-variables.scss"
has   "two-tree measures the knobs"                 "$out" "knobs bound     4 of 4"
has   "two-tree finds the built sheet under app/"   "$out" "built stylesheet app/deployment/web/theme.compiled.css"
has   "two-tree reads \$use-css-variables"          "$out" "css-vars mode   \$use-css-variables: true"
hasnt "two-tree never says 0 of 0"                  "$out" "knobs bound     0 of 0"

d="$(two_tree tt-broken built-broken.css true mpr)"
check "two-tree shipped state still exits 1"       "$(code "$d")" "1"
has   "two-tree reports 0 of 4 knobs"               "$(run "$d")" "0 of 4 framework knobs are bound"

# No .mpr (an installed copy beside an older _common.sh, or a bare tree): probe app/ anyway.
d="$(two_tree tt-nompr built-fixed.css true "")"
has   "two-tree without an .mpr still finds app/"   "$(run "$d")" "knobs bound     4 of 4"

d="$(two_tree tt-bridge built-fixed.css true mpr)"
printf '$brand-primary: var(--brand);\n' > "$d/app/themesource/moc/web/main.scss"
out="$(run "$d")"
check "two-tree dead SCSS bridge exits 1"          "$(code "$d")" "1"
has   "two-tree names the bridge file under app/"   "$out" "app/themesource/moc/web/main.scss:1"

# ── 10. a knob file it cannot read is a fault, never clean ──────────────────────────────────
d="$(project noknobs built-fixed.css true)"
rm -f "$d/theme/web/custom-variables.scss"
out="$(run "$d")"
check "a missing knob file exits 2"               "$(code "$d")" "2"
has   "says the knob pass is UNMEASURED"            "$out" "UNMEASURED"
has   "names the missing file"                      "$out" "custom-variables.scss not found"
hasnt "does not call it clean"                      "$out" "check-design-reaches-app: clean"
hasnt "does not print 0 of 0"                       "$out" "knobs bound     0 of 0"

d="$(project emptyknobs built-fixed.css true)"
printf ':root {\n//   --brand-primary: #264ae5;\n}\n$use-css-variables: true;\n' > "$d/theme/web/custom-variables.scss"
check "a knob file declaring no knobs exits 2"    "$(code "$d")" "2"
has   "says no knobs were declared"                 "$(run "$d")" "no framework knobs declared"

# A knob file given by hand is still honoured, as the third argument and as CUSTOM_VARS.
d="$(project override built-fixed.css true)"
mkdir -p "$d/elsewhere"; mv "$d/theme/web/custom-variables.scss" "$d/elsewhere/cv.scss"
has   "third argument names the knob file"          "$( cd "$d" && bash "$SUT" design/ds.css deployment/web/theme.compiled.css elsewhere/cv.scss 2>&1 )" "knobs bound     4 of 4"
has   "CUSTOM_VARS names the knob file"             "$( cd "$d" && CUSTOM_VARS=elsewhere/cv.scss bash "$SUT" 2>&1 )" "knobs bound     4 of 4"

# ── 11. themed palettes: compare the same block, not a bare :root that does not exist ───────
# A design system whose palette lives only in `:root.theme-light` / `:root.theme-dark` used to
# read "0 of N tokens carry the design value" because the comparison looked in a bare `:root`
# of the built sheet. Synthetic fixture; the themed blocks are compared block for block.
themed() {
  d="$(project "$1" "$2" true)"
  cp "$FIX/ds-themed.css" "$d/design/ds.css"
  printf ':root {\n  --brand-primary: #264ae5;\n}\n$use-css-variables: true;\n' > "$d/theme/web/custom-variables.scss"
  printf '%s' "$d"
}
d="$(themed themed built-themed.css)"
out="$(run "$d")"
check "a correctly ported themed palette exits 0"   "$(code "$d")" "0"
has   "counts every themed token as valued"          "$out" "tokens valued   9 of 9"
hasnt "no false 'carry the design's value' warning"  "$out" "carry the design's value"

d="$(themed themed-wrong built-themed-wrong.css)"
out="$(run "$d")"
has   "a wrong themed value is still caught"         "$out" "7 carry the design's value"
has   "names the block, token and both values"       "$out" "--brand (:root.theme-light built #0F6E6B, designed #AA1122)"

# A descendant rule (`:root .theme-light`, with a space) does not set the variable on the root, so
# it is not the block the design declared in `:root.theme-light`. It must not read as valued.
d="$(themed themed-descendant built-themed-descendant.css)"
out="$(run "$d")"
hasnt "a descendant selector is not the root theme block" "$out" "tokens valued   9 of 9"
has   "the descendant block counts as built absent"       "$out" "carry the design's value"

# ── 12. CSS layout must not change the reading (#670) ──────────────────────────────────────
# Golden input is REAL (see CAPTURE.md, "#670 captures"): real-ds.css is a design stylesheet with
# several tokens per line, real-built-excerpt.css is verbatim line ranges of a compiled theme
# (bare :root with the design's tokens, a multi-line selector list `.card, ...`, two rules
# inside @media, and `.card-body`). The old readers saw 10 of the design's 38 tokens.
real() {  # $1 name  $2 design  $3 built  [$4 "two" for the app/ layout]
  d="$TMP/$1"; rm -rf "$d"; mkdir -p "$d/design" "$d/deployment/web" "$d/theme/web"
  cp "$2" "$d/design/ds.css"; cp "$3" "$d/deployment/web/theme.compiled.css"
  cp "$FIX/real-custom-variables.scss" "$d/theme/web/custom-variables.scss"
  if [ "${4:-}" = "two" ]; then
    mkdir -p "$d/app"; mv "$d/theme" "$d/deployment" "$d/app/"; : > "$d/app/App.mpr"
  fi
  printf '%s' "$d"
}
summ() { printf '%s\n' "$1" | grep -E '^(knobs bound|tokens arrived|tokens valued|classes arrived)'; }
tr '\n' ' ' < "$FIX/real-ds.css"            > "$TMP/min-ds.css"
tr '\n' ' ' < "$FIX/real-built-excerpt.css" > "$TMP/min-built.css"

d="$(real realml "$FIX/real-ds.css" "$FIX/real-built-excerpt.css")"
base="$(summ "$(run "$d")")"
has   "real sheets: every design token is counted, several per line" "$base" "tokens arrived  32 of 38"
has   "real sheets: values compared with the \`}\` gone"             "$base" "tokens valued   30 of 38"
has   "real sheets: knobs bound through var() are counted"          "$base" "knobs bound     31 of 46"
has   "real sheets: whole-class count"                              "$base" "classes arrived 1 of 66"

# The same two sheets with every newline removed (one line each, comments left in) must read
# identically: nothing in the numbers may depend on how the CSS is laid out.
d="$(real realmin "$TMP/min-ds.css" "$TMP/min-built.css")"
check "one-line design + one-line built read as the multi-line pair" "$(summ "$(run "$d")")" "$base"
check "one-line pair exits like the multi-line pair"                 "$(code "$d")" "$(code "$(real realml2 "$FIX/real-ds.css" "$FIX/real-built-excerpt.css")")"

# Both layouts: the same real pair with the app under app/ (.mpr present).
d="$(real realtwo "$FIX/real-ds.css" "$FIX/real-built-excerpt.css" two)"
check "two-tree reads the real pair like the single tree" "$(summ "$(run "$d")")" "$base"
has   "two-tree names the built sheet under app/"          "$(run "$d")" "built stylesheet app/deployment/web/theme.compiled.css"

# Small synthetic twins for the individual faults; the real pair above is the golden input.
mini() {  # $1 name  $2 design css  $3 built css
  d="$(project "$1" "" true)"; printf '%s' "$2" > "$d/design/ds.css"; printf '%s' "$3" > "$d/deployment/web/theme.compiled.css"; printf '%s' "$d"
}
# fault 1: a one-line :root; the value must not keep its `}`; a later rule's --leak is no token
d="$(mini oneline ':root{--a:1px;--b:2px;--c:3px}.x{--leak:9px}' ':root{--a:1px;--b:2px;--c:3px}')"
out="$(run "$d")"
has   "one-line :root declares 3 tokens, not 1"        "$out" "tokens arrived  3 of 3"
has   "values compare without a trailing brace"        "$out" "tokens valued   3 of 3"
# fault 2: minified built sheet still has its bare :root
d="$(mini minbuilt ':root{--brand-primary:#111111}' ':root{--brand-primary:#111111}.x{color:red}')"
has   "minified built sheet: bare :root is found, knob bound by literal" "$(run "$d")" "knobs bound     1 of 4"
# fault 3: .card is not arrived because .card-header is
d="$(mini wholeclass '.card{a:b}.hdr{a:b}' '.card-header{a:b}.hdr{a:b}')"
out="$(run "$d")"
has   ".card is NOT counted by .card-header"           "$out" "classes arrived 1 of 2"
has   "names the missing class"                        "$out" "Absent: .card"
d="$(mini wholeclass2 '.card{a:b}.hdr{a:b}' '.card, .x > .y{a:b}.hdr:hover{a:b}')"
has   "a class inside a selector list / pseudo still counts" "$(run "$d")" "classes arrived 2 of 2"
# fault 4: multi-line selector list, rule inside @media
d="$(mini media '@media (min-width: 1px) {
  .m1 { a: b }
}
.ml-a,
.ml-b { a: b }' '.m1{a:b}.ml-a{a:b}.ml-b{a:b}')"
has   "rules in @media and multi-line selector lists are read" "$(run "$d")" "classes arrived 3 of 3"
# fault 5: var(--x, fallback) uses --x
d="$(mini fallback ':root{--t1:#abcdef}' ':root{--brand-primary:var(--t1, #fff);--font-size-default:var( --nope , 1px)}')"
has   "var(--t1, fallback) counts as bound to --t1"    "$(run "$d")" "knobs bound     1 of 4"
# a model class: whole-class match against the built sheet
d="$(mini modelcls '.a{a:b}' '.a{a:b}.card-header{a:b}')"
mkdir -p "$d/mdlsource"; printf "Class: 'card'\n" > "$d/mdlsource/p.mdl"
has   "model class .card is not defined by .card-header" "$(run "$d")" "1 of 1 classes the MODEL asks for are not defined"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
