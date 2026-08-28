#!/usr/bin/env bash
# check-page-shell.sh — fail a page script whose SHELL contradicts the wireframe it was
# built from, BEFORE it is exec'd against the .mpr.
#
# WHY THIS EXISTS. A page's shell — the column it sits in, the layout chrome around it,
# whether it has a title at all — is stated unambiguously in every wireframe and is
# invisible to every other instrument. `mxcli check --references` sees an opaque string.
# mxbuild compiles a model, and a layout choice is a valid model. `design-audit.js`
# computes a wireframe-vs-page delta and deliberately declines to score it (design-audit.js
# ~line 606: "scoring on that turns every page red for no defect") — correct about raw
# CLASS delta, which is why this script scores the shell instead, where the wireframe is
# explicit and chrome is not a confound.
#
# MEASURED, ToeicBuddy field run 2026-08-25/26 (process/first-build-page-fidelity-2026-08-27.md):
#
#   * 14 of 14 wireframes declare `main{max-width:900px}`. 0 of 10 pages capped their
#     width. Content rendered at 1360px: three buttons stretched to ~440px each around
#     25-char captions; Speaking prompts at ~160 characters per line; a Reading page
#     rendering at two different measures at once. Repaired wholesale at script 67 —
#     fifty-five scripts after the pages were built. From that script's own header:
#     "Nothing chose that; it is simply what a container does when nothing caps it, and
#     no script ever capped it."
#
#   * Every wireframe draws `<nav class="tabs">`, a top bar. 0 of 10 pages used
#     Atlas_TopBar; all 10 got Atlas_Default, whose collapsed sidebar clipped labels
#     ("All task" for "All tasks"). Repaired wholesale at script 20.
#
#   * First-build fidelity across those 10 pages measured 32% median against a target of
#     80%. The UI pre-flight had been followed — script 12's header cites
#     ui-preflight-pages.md Step 3 and design-spacing.md by name. The discipline ran; it
#     terminated in a prose block nothing scored.
#
# THE PROPERTY THAT MAKES THIS WORTH A PRE-EXEC GATE: a shell defect is uniform across
# every page built from the same template, so no page stands out as a diff and per-page
# review does not surface it. All ten were wrong the same way. That is also what makes it
# cheap: one check, one file, one grep, ten pages saved.
#
#   bin/check-page-shell.sh <script.mdl>...      # the drafted page scripts
#   bin/check-page-shell.sh                      # every .mdl under mdlsource/ naming a page
#
# Exit 0 clean, 1 violations found, 2 inspected nothing (NOT a pass).
#
# Per-line opt-out, same idiom as check-design-portability.sh: a trailing
# `-- page-shell-ok: <reason>` on the CREATE PAGE line. The reason is not optional; a bare
# opt-out is indistinguishable from a suppression.
#
# CHECKS DELIBERATELY NOT HERE, and this is the admission bar for adding a fourth — every
# check above cites a measured, uniform, unambiguous defect:
#   heading-text match     A wireframe h2 "Listening - Parts 1 to 4" against a page H1
#                          "Listening" is a real divergence and a bad gate: wording
#                          legitimately differs, and a binary verdict on it cries wolf.
#                          It belongs in the scored fidelity report, not here.
#   bound content          Wireframe sample copy becomes an attribute binding. A page that
#                          correctly binds it contains none of the literal text.
#   class-by-class delta   Exactly what design-audit.js declined to score, for good reason.
#   spacing rhythm         design-spacing.md §2 is judgement over a rendered page; this
#                          script never renders anything.

set -uo pipefail

if [ "$#" -gt 0 ]; then
  TARGETS="$*"
else
  TARGETS="$(find mdlsource -name '*.mdl' 2>/dev/null | sort | tr '\n' ' ')"
fi

WF_DIR="${WF_DIR:-design/wireframes}"

VIOLATIONS=0
SCANNED=0
PAGES=0

report() { printf '%s: %s\n     %s\n' "$1" "$2" "$3"; VIOLATIONS=$((VIOLATIONS + 1)); }

if [ ! -d "$WF_DIR" ]; then
  printf 'check-page-shell: no wireframe directory at %s\n' "$WF_DIR"
  printf '  ui-preflight-pages.md Step 1 says a page without a wireframe is a STOP, not a\n'
  printf '  pass. This script inspected nothing and is not evidence of anything.\n'
  exit 2
fi

for f in $TARGETS; do
  [ -f "$f" ] || continue
  SCANNED=$((SCANNED + 1))

  # One line per page declaration: `<line no>:CREATE [OR MODIFY|OR REPLACE] PAGE "Mod"."Page"`
  # Both quoted and bare module.page forms appear in the wild; match either.
  while IFS= read -r decl; do
    [ -n "$decl" ] || continue
    ln="${decl%%:*}"; txt="${decl#*:}"

    case "$txt" in *page-shell-ok:*) continue ;; esac

    page="$(printf '%s' "$txt" | sed -E 's/.*[Pp][Aa][Gg][Ee][[:space:]]+"?[A-Za-z0-9_]+"?\."?([A-Za-z0-9_]+)"?.*/\1/')"
    [ -n "$page" ] || continue

    wf="$WF_DIR/$page.html"
    if [ ! -f "$wf" ]; then
      report "$f:$ln" "page $page has no wireframe at $wf" \
        'ui-preflight-pages.md Step 1: no wireframe is a STOP. Draw it (design-artifacts.md) or map it; do not build the page against a guess.'
      continue
    fi
    PAGES=$((PAGES + 1))

    # The page body: from this declaration to the closing brace at column 0.
    body="$(awk -v start="$ln" 'NR>=start{print} NR>start && /^\}/{exit}' "$f")"

    # A popup owns neither the app column nor a page title — the popup chrome supplies
    # both, and restating the title in the body is its own documented defect
    # (learned-page-patterns.md, "Popup Pages — Never Duplicate the Chrome Title").
    # Checks 1 and 3 do not apply; check 2 never did.
    layout="$(printf '%s' "$body" | grep -oE 'Layout:[[:space:]]*"?[A-Za-z0-9_]+"?\."?[A-Za-z0-9_]+"?' | head -1)"
    case "$layout" in *[Pp]opup*) continue ;; esac

    # --- 1. The page column ---------------------------------------------------------------
    # The wireframe's own `main{max-width:Npx}` is the design's page column, not a
    # per-screen choice. A Mendix container fills its layout region unless something caps
    # it, and nothing in a default page tree does.
    col="$(grep -oE 'main\{[^}]*max-width:[0-9]+px' "$wf" | grep -oE '[0-9]+px' | head -1)"
    if [ -n "$col" ]; then
      if ! printf '%s' "$body" | grep -qE "Class:[^)]*(page-column|page-body|kt-page|container|max-w|measure)"; then
        report "$f:$ln" "page $page is built full-bleed; its wireframe draws a $col column" \
          "Wrap the page body in the project's page-column container (ds.css supplies 'margin: 0 auto'; the wireframe narrows it to $col). Uncapped, this renders at the full layout region — measured at 1360px on a 900px design."
      fi
    fi

    # --- 2. The layout shell --------------------------------------------------------------
    # A wireframe that draws a horizontal nav is specifying a top-bar shell. Atlas_Default
    # and Atlas_SideBar are responsive sidebars; collapsed, they need per-item icons or
    # they clip label text (learned-sidebar-collapse-icons.md).
    if grep -qE '<nav[^>]*class="[^"]*tabs' "$wf"; then
      case "$layout" in
        *TopBar*|*Top_Bar*) ;;
        '')  report "$f:$ln" "page $page declares no Layout; its wireframe draws a top-bar shell" \
               'Set Layout to the project top-bar layout (Atlas_Core.Atlas_TopBar unless the project has its own). Confirm the name with `mxcli -c "SHOW LAYOUTS"` before writing it.' ;;
        *)   report "$f:$ln" "page $page uses ${layout#Layout:} but its wireframe draws a top-bar shell" \
               'Set Layout to the project top-bar layout. A responsive sidebar collapses to an icon-only rail; with no icons configured it clips labels ("All task" for "All tasks").' ;;
      esac
    fi

    # --- 3. The page scaffold -------------------------------------------------------------
    # design-spacing.md §3: every full page opens with a header block carrying exactly one
    # page title. Measured escape (module-review.md, 2026-08-22): a page passed its LOOK
    # review with no page title at all, because the rubric only interrogated the content region.
    #
    # The title LEVEL is the wireframe's to state, not this script's: ToeicBuddy titles
    # pages with <h1>, VB-USI with <h2> (its topbar design), and hardcoding H1 here flagged
    # every correct VB-USI page as defective (field run 2026-08-27). The first h1/h2 in the
    # wireframe is the design's page-title level; H1 is only the fallback when the wireframe
    # draws neither.
    lvl="$(grep -oiE '<h[12][^>]*>' "$wf" | head -1 | grep -oiE 'h[12]' | tr 'a-z' 'A-Z')"
    [ -n "$lvl" ] || lvl="H1"
    n="$(printf '%s' "$body" | grep -cE "RenderMode:[[:space:]]*$lvl\b")"
    if [ "$n" -eq 0 ]; then
      report "$f:$ln" "page $page has no RenderMode: $lvl title block (its wireframe titles with <${lvl}>)" \
        "design-spacing.md §3: a full page opens with crumb + one page title at the wireframe's level (+ subtitle/actions where the wireframe has them). A full page with no title is a defect, not a layout choice."
    elif [ "$n" -gt 1 ]; then
      report "$f:$ln" "page $page declares $n $lvl titles; its wireframe draws one" \
        "design-spacing.md §3: exactly one page title per full page. A second $lvl is usually a section heading that should be one level down."
    fi

    # `--` is an MDL comment; a leading `*` is a `/* ... */` block-comment continuation line
    # (this project's own doc-comment style, e.g. "* BUILD-LOG 08-07 ... CREATE OR MODIFY
    # PAGE re-specifies the whole page"). Script 12's own header narrates "CREATE OR MODIFY
    # PAGE" in prose four times; matching those invents pages that do not exist and reports
    # a missing wireframe for each. A finding that cries wolf gets the script switched off.
    #
    # MDL itself is case-insensitive (`create or replace page` and `CREATE OR MODIFY PAGE`
    # are the same statement) — matching CREATE/PAGE case-sensitively silently skipped every
    # lowercase declaration in this project's own build scripts (done-09-productnumbers-
    # pages.mdl among them), reporting "no page declaration found" instead of scanning them.
  done <<EOF
$(grep -inE 'CREATE([[:space:]]+OR[[:space:]]+(MODIFY|REPLACE))?[[:space:]]+PAGE[[:space:]]' "$f" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*(--|\*)')
EOF
done

printf '\n'
if [ "$SCANNED" -eq 0 ]; then
  printf 'check-page-shell: no .mdl files inspected — this is NOT a pass.\n'
  exit 2
fi
if [ "$PAGES" -eq 0 ]; then
  printf 'check-page-shell: %s file(s) read, no page declaration with a wireframe found — NOT a pass.\n' "$SCANNED"
  exit 2
fi
printf 'check-page-shell: %s page(s) across %s file(s); %s violation(s).\n' "$PAGES" "$SCANNED" "$VIOLATIONS"
[ "$VIOLATIONS" -eq 0 ] || exit 1
