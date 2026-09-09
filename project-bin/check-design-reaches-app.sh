#!/usr/bin/env bash
# check-design-reaches-app.sh — did any of the design system ARRIVE in the built app?
#
# Sibling of check-design-portability.sh, and its correction. That script asks whether the
# design system's RULES can match the DOM Mendix emits, and its header opens by asserting the
# premise this one exists to test:
#
#     "A design system's *tokens* port into Mendix perfectly — colours, radii and spacing
#      variables survive the SCSS port intact. Its *rules* may not."
#
# The first half is false, and it was the sentence that made everyone comfortable. Tokens
# survive the port into a FILE. Nothing about surviving into the file makes the framework read
# them, and nothing about the file makes the app wear them.
#
# ── THE FIELD RUN (2026-09-09, a requirements-driven MOC/PSSR app replacement) ──────────────
#
# 55 tokens sampled from the customer's own screenshots were ported into
# themesource/<app>/web/main.scss correctly, on time, at the stage that owed them. The app then
# rendered every screen in the framework's default blue for two more phases of build.
#
# Three independent failures, none of them visible to any check in this toolkit:
#
#   1. THE BRIDGE TARGETED A DEAD LAYER. The port wrote SCSS variables:
#
#          $brand-primary: var(--brand);
#
#      Atlas 3 with `$use-css-variables: true` — the default in Mendix 10/11 — reads CSS custom
#      properties and never reads that SCSS variable. The assignment compiled to NOTHING.
#      Measured in deployment/web/theme.compiled.css:
#
#          --brand:         #FC3122     <- ours, present, correct
#          --brand-primary: #264ae5     <- the framework default, untouched
#          var(--brand)     0 occurrences
#
#   2. THE COMPONENT CLASSES WERE NEVER PORTED AT ALL. 20 classes defined in the design system,
#      0 present in the built stylesheet. `ds-muted` sat on 12 widgets and resolved to the body
#      colour, so every caption on every page rendered at full ink.
#
#   3. THE PORT ALSO WON NOTHING IT DID SET, because a project theme module's :root is emitted
#      BEFORE theme/web/custom-variables.scss in the compiled sheet. Anything the module said
#      about a framework knob lost the cascade to the stock value.
#
# `mx check` returned 0 errors. `mxcli lint` returned 0 errors. The MDL suite was green, both
# e2e journeys passed, and check-design-portability.sh had nothing to say, because every one of
# those looks at the model or at the authored stylesheet and none of them looks at the BUILT one.
# It was found by a human opening a screenshot and asking why the UI was poor.
#
# ── WHAT THIS CHECKS, AND WHY IT NEEDS NO TABLE OF FRAMEWORK DEFAULTS ───────────────────────
#
# The tempting check is "is --brand-primary still #264ae5". That is a cache of one framework's
# one version — the defect CLAUDE.md's authoring rule 5 forbids, and it goes stale on the next
# Atlas release. So the question is inverted, and then it needs no such table:
#
#     For every knob the framework declares in its own customization file, is the winning
#     definition in the BUILT stylesheet pointed at a design-system token?
#
# A framework's customization file enumerates its own knobs; that is what it is for. Count how
# many are bound. Zero bound is not a style opinion, it is a wire that was never connected.
#
# Four passes, each with a denominator, because a pass that cannot say what it covered has not
# covered it:
#
#   1  knobs bound        N of M framework knobs point at a design-system token.  0 = VIOLATION
#   2  tokens arrived     N of M design-system tokens exist in the built sheet.   0 = VIOLATION
#   3  classes arrived    N of M design-system classes exist in the built sheet.  0 = VIOLATION
#   4  dead SCSS bridge   `$x: var(--y)` while the theme runs on custom properties. any = VIOL
#
# Plus one WARN pass: classes the MODEL asks for that the built sheet does not define. That is
# how `ds-help` was found on the same run — a class name typed from memory, on a live widget,
# styling nothing.
#
#   project-bin/check-design-reaches-app.sh                     # defaults, from the project root
#   project-bin/check-design-reaches-app.sh <design.css> <built.css>
#
# Exit 0 clean, 1 violations, 2 inspected nothing (NOT a pass).
#
# THIS CHECK REQUIRES A BUILD. That is the point: there is no way to answer "did it reach the
# app" from source alone, which is exactly why nothing answered it. With no built stylesheet it
# exits 2 and says so, and 2 is not green.

set -uo pipefail

DESIGN="${1:-}"
BUILT="${2:-}"

if [ -z "$DESIGN" ]; then
  for c in design/ds.css design/design-system.css; do
    [ -f "$c" ] && { DESIGN="$c"; break; }
  done
fi
if [ -z "$BUILT" ]; then
  for c in deployment/web/theme.compiled.css deployment/web/theme.css; do
    [ -f "$c" ] && { BUILT="$c"; break; }
  done
fi

# The framework's own customization surface. Atlas has called this file the same thing since
# Atlas 2; a project that renamed it passes it as a third argument via CUSTOM_VARS.
CUSTOM_VARS="${CUSTOM_VARS:-theme/web/custom-variables.scss}"

if [ -z "$DESIGN" ] || [ ! -f "$DESIGN" ]; then
  printf 'check-design-reaches-app: no design system stylesheet found.\n' >&2
  printf '  Searched: design/ds.css, design/design-system.css\n' >&2
  printf '  This is NOT a pass. Name it explicitly, or run from the project root.\n' >&2
  exit 2
fi
if [ -z "$BUILT" ] || [ ! -f "$BUILT" ]; then
  printf 'check-design-reaches-app: no BUILT stylesheet found.\n' >&2
  printf '  Searched: deployment/web/theme.compiled.css, deployment/web/theme.css\n' >&2
  printf '  Run a build first. "Did the design system reach the app" cannot be answered from\n' >&2
  printf '  source, and answering it from source is how this defect shipped.\n' >&2
  printf '  This is NOT a pass.\n' >&2
  exit 2
fi

VIOLATIONS=0
WARNINGS=0

report() { printf 'FAIL  %s\n      %s\n' "$1" "$2"; VIOLATIONS=$((VIOLATIONS + 1)); }
warn()   { printf 'WARN  %s\n      %s\n' "$1" "$2"; WARNINGS=$((WARNINGS + 1)); }

# ── Pass 0: read the design system ──────────────────────────────────────────────────────────
# Tokens: custom properties declared in a :root block. Values too, because a knob may be bound
# by repeating the literal rather than by var() — still bound, and still correct.
TOKENS="$(awk '
  /:root/            { inroot = 1 }
  inroot && /^[[:space:]]*}/ { inroot = 0 }
  inroot && match($0, /--[a-z0-9-]+[[:space:]]*:/) {
    name = substr($0, RSTART, RLENGTH); sub(/[[:space:]]*:$/, "", name)
    rest = substr($0, RSTART + RLENGTH); sub(/;.*$/, "", rest)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", rest)
    if (!(name in seen)) { seen[name] = 1; print name "\t" rest }
  }
' "$DESIGN")"
TOKEN_COUNT="$(printf '%s\n' "$TOKENS" | grep -c '^--' || true)"

# Classes: any `.name` appearing at the head of a rule. Compound selectors contribute each.
CLASSES="$(grep -oE '^[^{@}]*\{' "$DESIGN" \
  | grep -oE '\.[A-Za-z_-][A-Za-z0-9_-]*' | sort -u)"
CLASS_COUNT="$(printf '%s\n' "$CLASSES" | grep -c '^\.' || true)"

if [ "$TOKEN_COUNT" -eq 0 ] && [ "$CLASS_COUNT" -eq 0 ]; then
  printf 'check-design-reaches-app: %s declares neither tokens nor classes.\n' "$DESIGN" >&2
  printf '  Nothing to trace. This is NOT a pass.\n' >&2
  exit 2
fi

# ── Pass 1: are the framework's knobs bound to our tokens? ──────────────────────────────────
# Declarations in BARE `:root {` blocks of the built sheet, last one winning. Anything scoped
# — `:root.theme-dark`, `:root.theme-neutral`, a class, a media query — is a theme or a state
# the app is not necessarily wearing, and counting it misreads the cascade.
BUILT_ROOT="$(awk '
  /^[[:space:]]*:root[[:space:]]*\{[[:space:]]*$/ { inroot = 1; next }
  inroot && /^[[:space:]]*\}/                     { inroot = 0; next }
  inroot && match($0, /--[a-zA-Z0-9-]+[[:space:]]*:/) {
    name = substr($0, RSTART, RLENGTH); sub(/[[:space:]]*:$/, "", name)
    rest = substr($0, RSTART + RLENGTH); sub(/;[[:space:]]*$/, "", rest)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", rest)
    map[name] = rest
  }
  END { for (k in map) print k "\t" map[k] }
' "$BUILT")"

KNOB_TOTAL=0
KNOB_BOUND=0
UNBOUND_SAMPLE=""
if [ -f "$CUSTOM_VARS" ]; then
  # Uncommented custom-property declarations in the framework's customization file. A `//`
  # commented line is a knob the framework OFFERS and the project has not taken; it is not
  # unbound, it is unclaimed, and counting it would drown the signal.
  KNOBS="$(grep -oE '^[[:space:]]*--[a-z0-9-]+[[:space:]]*:' "$CUSTOM_VARS" \
    | grep -oE '\-\-[a-z0-9-]+' | sort -u)"
  for knob in $KNOBS; do
    KNOB_TOTAL=$((KNOB_TOTAL + 1))
    # The WINNING definition, read from BARE `:root` blocks only.
    #
    # A plain "last occurrence in the file" reading is wrong and was measured wrong: the last
    # definition of --brand-primary in a real built sheet sits inside `:root.theme-neutral`,
    # a THEME the app does not wear, and reading it reported a correctly bound knob as unbound.
    # An instrument that miscounts its own denominator teaches people to ignore it.
    val="$(printf '%s\n' "$BUILT_ROOT" | awk -F'\t' -v k="$knob" '$1 == k { v = $2 } END { print v }')"
    [ -z "$val" ] && continue
    bound=0
    # (a) bound by reference
    while IFS="$(printf '\t')" read -r tname tval; do
      [ -z "$tname" ] && continue
      case "$val" in *"var($tname)"*) bound=1; break ;; esac
      # (b) bound by repeating the literal. Only for values that look like a value, so an
      #     empty or inherit-ish token cannot mark every knob bound.
      if [ -n "$tval" ] && [ "${#tval}" -ge 3 ]; then
        stripped="$(printf '%s' "$val" | tr -d ' ')"
        tstripped="$(printf '%s' "$tval" | tr -d ' ')"
        if [ "$stripped" = "$tstripped" ]; then bound=1; break; fi
      fi
    done <<EOF
$TOKENS
EOF
    if [ "$bound" -eq 1 ]; then
      KNOB_BOUND=$((KNOB_BOUND + 1))
    elif [ "$(printf '%s' "$UNBOUND_SAMPLE" | wc -w)" -lt 6 ]; then
      UNBOUND_SAMPLE="$UNBOUND_SAMPLE $knob"
    fi
  done
fi

# ── Pass 2: did the tokens arrive? ──────────────────────────────────────────────────────────
TOKENS_ARRIVED=0
while IFS="$(printf '\t')" read -r tname tval; do
  [ -z "$tname" ] && continue
  grep -qE -- "$tname[[:space:]]*:" "$BUILT" && TOKENS_ARRIVED=$((TOKENS_ARRIVED + 1))
done <<EOF
$TOKENS
EOF

# ── Pass 3: did the classes arrive? ─────────────────────────────────────────────────────────
CLASSES_ARRIVED=0
MISSING_CLASS_SAMPLE=""
for cls in $CLASSES; do
  if grep -qF -- "$cls" "$BUILT"; then
    CLASSES_ARRIVED=$((CLASSES_ARRIVED + 1))
  elif [ "$(printf '%s' "$MISSING_CLASS_SAMPLE" | wc -w)" -lt 6 ]; then
    MISSING_CLASS_SAMPLE="$MISSING_CLASS_SAMPLE $cls"
  fi
done

# ── Pass 4: the dead SCSS-variable bridge ───────────────────────────────────────────────────
# Only dead where the theme actually runs on custom properties. Where it does not, assigning a
# framework SCSS variable is the CORRECT bridge and must not be reported.
CSS_VARS_MODE="unknown"
if grep -rqE '^[[:space:]]*\$use-css-variables[[:space:]]*:[[:space:]]*true' theme/web/ 2>/dev/null; then
  CSS_VARS_MODE="true"
elif grep -rqE '^[[:space:]]*\$use-css-variables[[:space:]]*:[[:space:]]*false' theme/web/ 2>/dev/null; then
  CSS_VARS_MODE="false"
fi
if [ "$CSS_VARS_MODE" = "true" ]; then
  for f in theme/web/*.scss themesource/*/web/*.scss; do
    [ -f "$f" ] || continue
    case "$f" in themesource/atlas_*|themesource/atlas_*/*) continue ;; esac
    while IFS= read -r hit; do
      [ -z "$hit" ] && continue
      ln="${hit%%:*}"
      report "$f:$ln assigns a framework SCSS variable while the theme runs \$use-css-variables: true" \
        'That assignment compiles to nothing. Set the matching CSS custom property in the framework customization file instead.'
    done <<EOF
$(grep -nE '^[[:space:]]*\$[a-z0-9-]+[[:space:]]*:[[:space:]]*var\(--' "$f" 2>/dev/null)
EOF
  done
fi

# ── WARN pass: classes the model asks for that the built sheet does not define ──────────────
MODEL_CLASS_TOTAL=0
MODEL_CLASS_MISSING=0
MODEL_MISSING_SAMPLE=""
if [ -d mdlsource ]; then
  MODEL_CLASSES="$(grep -rhoE "Class:[[:space:]]*'[^']+'" mdlsource 2>/dev/null \
    | sed "s/.*'\\(.*\\)'/\\1/" | tr ' ' '\n' | grep -E '^[A-Za-z_-][A-Za-z0-9_-]*$' | sort -u)"
  for cls in $MODEL_CLASSES; do
    MODEL_CLASS_TOTAL=$((MODEL_CLASS_TOTAL + 1))
    if ! grep -qF -- ".$cls" "$BUILT"; then
      MODEL_CLASS_MISSING=$((MODEL_CLASS_MISSING + 1))
      if [ "$(printf '%s' "$MODEL_MISSING_SAMPLE" | wc -w)" -lt 8 ]; then
        MODEL_MISSING_SAMPLE="$MODEL_MISSING_SAMPLE $cls"
      fi
    fi
  done
fi

# ── Verdicts ────────────────────────────────────────────────────────────────────────────────
if [ "$KNOB_TOTAL" -eq 0 ]; then
  warn "no framework knobs found in $CUSTOM_VARS" \
    'Pass 1 could not run. Set CUSTOM_VARS to the framework customization file, or say in the review why this project has none.'
elif [ "$KNOB_BOUND" -eq 0 ]; then
  report "0 of $KNOB_TOTAL framework knobs are bound to a design-system token" \
    "The framework is still wearing its own defaults. Unbound:${UNBOUND_SAMPLE:- (all)}"
fi

if [ "$TOKENS_ARRIVED" -eq 0 ] && [ "$TOKEN_COUNT" -gt 0 ]; then
  report "0 of $TOKEN_COUNT design-system tokens exist in $BUILT" \
    'The port did not reach the build at all. Check that the theme module directory name matches a real module.'
fi

if [ "$CLASS_COUNT" -gt 0 ] && [ "$CLASSES_ARRIVED" -eq 0 ]; then
  report "0 of $CLASS_COUNT design-system classes exist in $BUILT" \
    'Every class the pages reference resolves to nothing. Port the component rules, not only the tokens.'
elif [ "$CLASS_COUNT" -gt 0 ] && [ "$CLASSES_ARRIVED" -lt "$CLASS_COUNT" ]; then
  warn "$CLASSES_ARRIVED of $CLASS_COUNT design-system classes exist in $BUILT" \
    "Absent:${MISSING_CLASS_SAMPLE:- (none sampled)} — dormant until a widget carries one, then silently inert."
fi

if [ "$MODEL_CLASS_MISSING" -gt 0 ]; then
  warn "$MODEL_CLASS_MISSING of $MODEL_CLASS_TOTAL classes the MODEL asks for are not defined in $BUILT" \
    "Sample:${MODEL_MISSING_SAMPLE} — a class on a live widget that styles nothing. Atlas's own class names are legitimate; anything project-shaped here is a name typed from memory."
fi

printf '\n'
printf 'design system   %s\n' "$DESIGN"
printf 'built stylesheet %s\n' "$BUILT"
printf 'knobs bound     %s of %s framework knobs point at a design-system token\n' "$KNOB_BOUND" "$KNOB_TOTAL"
printf 'tokens arrived  %s of %s\n' "$TOKENS_ARRIVED" "$TOKEN_COUNT"
printf 'classes arrived %s of %s\n' "$CLASSES_ARRIVED" "$CLASS_COUNT"
printf 'model classes   %s of %s asked for by the model are undefined\n' "$MODEL_CLASS_MISSING" "$MODEL_CLASS_TOTAL"
printf 'css-vars mode   $use-css-variables: %s\n' "$CSS_VARS_MODE"

if [ "$VIOLATIONS" -gt 0 ]; then
  printf '\ncheck-design-reaches-app: %s violation(s).\n' "$VIOLATIONS"
  printf 'The design system exists and the app is not wearing it. Fix the BINDING, not the tokens\n'
  printf '—-the tokens were never the problem, which is why every other check stayed green.\n'
  exit 1
fi
if [ "$WARNINGS" -gt 0 ]; then
  printf '\ncheck-design-reaches-app: clean, %s warning(s) — read them.\n' "$WARNINGS"
  exit 0
fi
printf '\ncheck-design-reaches-app: clean.\n'
