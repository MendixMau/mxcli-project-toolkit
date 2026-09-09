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

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
