#!/usr/bin/env bash
# check-design-portability.sh — fail the design-system gate when a stylesheet rule cannot
# match the HTML Mendix actually emits.
#
# WHY THIS EXISTS. A design system's *tokens* port into Mendix perfectly — colours, radii and
# spacing variables survive the SCSS port intact. Its *rules* may not, because they were
# authored against a DOM the app does not have. Measured on a field run (2026-08-26): 10 of a
# 70-line ds.css styled through child HTML tags Mendix never emits, and every rem in the file
# rendered at 62.5% of intent. Nothing warned. `mx check` returned 0 errors, `mxcli check` and
# `mxcli lint` were green, the app built, and the pages rendered — small, and grey.
#
# THE PROPERTY THAT MAKES THIS WORTH A GATE: a design-system defect is DORMANT until some
# widget carries the class. So the defects are all present from the first build and surface
# one at a time, months later, as UI work attaches classes to pages. "The build is green and
# the pages look fine" is not evidence that the design system is correct — it is evidence that
# the design system is not being exercised yet. Nothing else in the harness looks here:
# mx check validates the model and CSS is not in the model; a class name is an opaque string
# to `mxcli check --references`; wireframe comparison is per-page and these defects are
# uniform, so no page stands out as a diff.
#
# WHY THIS IS NOT AN mxcli .star LINT RULE, for the second time in this repo: the Starlark API
# exposed to `mxcli lint` is entirely Mendix-model-scoped, with no filesystem access of any
# kind — see the same paragraph in bin/check-portability.sh, which is this script's sibling and
# its precedent. A rule that reads a stylesheet has nothing to read it with.
#
#   bin/check-design-portability.sh                 # defaults below, from the project root
#   bin/check-design-portability.sh <css>...        # explicit stylesheets
#
# Exit 0 clean, 1 violations found, 2 inspected nothing (NOT a pass).
#
# EVERY CHECK HERE HAS A MEASURED MENDIX DOM FACT BEHIND IT, and that is the admission bar for
# adding a fourth. A denylist that cries wolf gets switched off — bin/check-portability.sh's
# header records that happening to the lint gate once already. Checks deliberately NOT here:
#   !important        sometimes correct; theme/web/main.scss compiles last and rarely needs it,
#                     but a module theme source legitimately might.
#   background w/o color   real (a rule that paints a background and inherits an unknown text
#                     colour is how white-on-pale-green happens), but hover/focus/disabled
#                     variants set a background alone perfectly legitimately, so it is a WARN
#                     below, never a violation.

set -uo pipefail

if [ "$#" -gt 0 ]; then
  TARGETS="$*"
else
  TARGETS=""
  for c in design/ds.css design/design-system.css theme/web/main.scss; do
    [ -f "$c" ] && TARGETS="$TARGETS $c"
  done
  # Every app-level partial main.scss imports, which is where the ported rules actually live.
  for c in theme/web/*.scss themesource/*/web/*.scss; do
    [ -f "$c" ] && case " $TARGETS " in *" $c "*) ;; *) TARGETS="$TARGETS $c" ;; esac
  done
fi

VIOLATIONS=0
WARNINGS=0
SCANNED=0

report() { printf '%s:%s: %s\n     %s\n' "$1" "$2" "$3" "$4"; VIOLATIONS=$((VIOLATIONS + 1)); }
warn()   { printf '%s:%s: WARN %s\n     %s\n' "$1" "$2" "$3" "$4"; WARNINGS=$((WARNINGS + 1)); }

# --- The root font size, measured, not assumed -------------------------------------------
# Atlas Core sets html{font-size:10px} (body 14px). A design system authored against the CSS
# default 16px therefore renders every rem at 62.5%: a 1.6rem KPI value intended at 25.6px
# paints at 16px, and a .75rem badge at 7.5px. Read it from the compiled theme rather than
# hardcoding 10px, because a project may legitimately restate the root in its own stylesheet —
# and if it has, rem is safe here and this check must not fire.
ROOT_DECL=""
for compiled in deployment/web/theme.compiled.css deployment/web/theme.css; do
  [ -f "$compiled" ] || continue
  ROOT_DECL="$(grep -oE 'html\{font-size:[^;}]+' "$compiled" | head -1 | sed 's/.*font-size://')"
  [ -n "$ROOT_DECL" ] && break
done

if [ -z "$ROOT_DECL" ]; then
  printf 'check-design-portability: no compiled theme found — run a build first, or the rem\n'
  printf '  check below is measured against an assumed 10px Atlas root rather than yours.\n\n'
  ROOT_DECL="10px (ASSUMED — no deployment/web/theme.compiled.css)"
  ROOT_IS_16=0
elif printf '%s' "$ROOT_DECL" | grep -qE '^ *(16px|100%|1rem|1em)'; then
  ROOT_IS_16=1
else
  ROOT_IS_16=0
fi

# Strip comment lines and blank lines before matching, but keep original line numbers.
code_lines() { grep -n '' "$1" | grep -vE ':[[:space:]]*(/\*|\*|//)' ; }

for f in $TARGETS; do
  [ -f "$f" ] || continue
  SCANNED=$((SCANNED + 1))

  while IFS= read -r hit; do
    # code_lines emits `NN:content` — ONE colon. Do not strip twice: a second strip eats the
    # selector up to the first `color:` and every selector check below silently sees nothing.
    ln="${hit%%:*}"; txt="${hit#*:}"

    # Per-line opt-out, same idiom as bin/check-portability.sh:
    #   `/* design-portability-ok: <reason> */` trailing the offending line.
    # The reason is not optional. A bare opt-out is indistinguishable from a suppression.
    case "$txt" in *design-portability-ok:*) continue ;; esac

    # 1. rem, against a root that is not 16px.
    if [ "$ROOT_IS_16" -eq 0 ] && printf '%s' "$txt" | grep -qE '[0-9.]+rem'; then
      report "$f" "$ln" "rem unit, but the app root font-size is $ROOT_DECL" \
        'Every rem here renders at that fraction of a 16px-root design. Author component sizes in px, or restate the root in the app stylesheet.'
    fi

    # 2. Selectors naming an HTML element Mendix does not emit.
    #    Mendix emits div, span and button and essentially nothing else. CONTAINER -> <div>,
    #    DYNAMICTEXT -> inline <span>, ACTIONBUTTON -> <button class="btn mx-button ...">.
    #    DataGrid2 in particular emits role="grid" <div>s, so table/th/td/tr match nothing at
    #    all — the whole responsive-table component is unreachable through `table.x`.
    #    Only selector lines: a declaration mentioning these words is not a selector.
    #
    #    THE LIST IS SHORT ON PURPOSE, and every omission below is deliberate. Mendix DOES
    #    emit these, so denying them would cry wolf and get the whole script switched off:
    #      a           navigation menu items, and ACTIONBUTTON in "link" render mode
    #      input,label TEXTBOX and every other input widget
    #      form        a form-shaped dataview
    #      img         the image widget
    #      p, em, strong, code   rich-text output
    #      h1-h6       DYNAMICTEXT in a heading render mode; Atlas styles these itself
    #    What remains is the measured set: tags no Mendix widget produces. Add to it only with
    #    a DOM fact you measured in a running app, recorded next to the tag.
    case "$txt" in *'{'*)
      sel="${txt%%\{*}"
      if printf '%s' "$sel" | grep -qE '(^|[[:space:]>+~,])(b|i|table|thead|tbody|th|td|tr|ul|ol|li)([[:space:].:,>+~]|$)'; then
        report "$f" "$ln" "selector styles through an HTML element Mendix does not emit" \
          'Mendix emits div/span/button. table|th|td|tr never appear (DataGrid2 is role="grid" divs). Restate as a class-only rule and give the class a widget carrier.'
      fi
      # 2b. A child-tag selector that DOES match, by accident, and outranks its own class.
      #     `.foo span` is 0-1-1 and beats the class-only `.foo-value` at 0-1-0, so the caption
      #     rule paints the headline. This is worse than a dead rule: it renders, wrongly.
      if printf '%s' "$sel" | grep -qE '\.[A-Za-z_-][A-Za-z0-9_-]*[[:space:]]+(span|div|button)([[:space:].:,]|$)'; then
        report "$f" "$ln" "class-descendant-tag selector outranks your own class rules" \
          'DYNAMICTEXT emits <span>, so this matches by accident at 0-1-1 and beats a class-only rule at 0-1-0. Give the inner widget its own class.'
      fi
      # 3. Row alternation driven from the DOM.
      #    Each listview row is wrapped in its own div.mx-dataview > div.mx-dataview-content,
      #    so EVERY row is :nth-of-type(1) in its own parent. Alternation must come from data.
      if printf '%s' "$sel" | grep -qE ':nth-(of-type|child|last-child|last-of-type)'; then
        report "$f" "$ln" "positional selector on Mendix-generated rows" \
          'Each listview row sits in its own div.mx-dataview wrapper, so every row is :nth-of-type(1). Drive alternation from data via DynamicClasses.'
      fi
      # WARN: background without colour on a non-state selector.
      if printf '%s' "$txt" | grep -qE 'background(-color)?[[:space:]]*:' \
         && ! printf '%s' "$txt" | grep -qE '(^|[;{[:space:]])color[[:space:]]*:' \
         && ! printf '%s' "$sel" | grep -qE ':(hover|focus|active|disabled|visited)'; then
        warn "$f" "$ln" "paints a background but not a text colour" \
          'Text colour is then inherited from whatever widget carries the class. A rule that paints a background should paint its text.'
      fi
      ;;
    esac
  done <<EOF
$(code_lines "$f")
EOF
done

# A checker that inspected nothing must not report a pass — the identical hole this repo has
# now found in bin/lint-gate.sh, bin/check-portability.sh and tests/e2e/design-audit.js.
if [ "$SCANNED" -eq 0 ]; then
  printf 'check-design-portability: inspected ZERO stylesheets.\n' >&2
  printf '  Searched: design/ds.css, design/design-system.css, theme/web/*.scss, themesource/*/web/*.scss\n' >&2
  printf '  This is NOT a pass. Name the stylesheet explicitly, or run from the project root.\n' >&2
  exit 2
fi

printf '\nroot font-size: %s\n' "$ROOT_DECL"
if [ "$WARNINGS" -gt 0 ]; then
  printf 'check-design-portability: %s warning(s) — read them, they are not automatic failures.\n' "$WARNINGS"
fi
if [ "$VIOLATIONS" -gt 0 ]; then
  printf 'check-design-portability: %s violation(s) across %s stylesheet(s).\n' "$VIOLATIONS" "$SCANNED"
  printf 'Each one is a rule that will not render as authored once a widget carries the class.\n'
  printf 'Fix it in the design system AND the SCSS port, same commit — a fix that lands only in\n'
  printf 'the compiled SCSS drifts, and the next project inherits the original defect.\n'
  exit 1
fi
printf 'check-design-portability: clean — %s stylesheet(s) inspected.\n' "$SCANNED"
