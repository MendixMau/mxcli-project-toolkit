#!/usr/bin/env bash
# gate-check.sh must report the runbook's Surface column, and must not enforce it.
#
# The thing under test is a PARSER OVER PROSE. skills/conversion-runbook.md §2's Surface cells
# are written for humans — parentheticals, em-dash glosses, backticked commands next to
# backticked artifacts — and gate-check reads them at runtime rather than keeping a second copy
# (see the block comment above stage_surface_cells for why). That trade buys a single source of
# truth and costs fragility: reword a cell and the parse can quietly return nothing. So the
# assertions below pin the two prose shapes that actually bit during development, not just the
# happy path.
set -uo pipefail
GATE="${1:-$(cd "$(dirname "$0")/../.." && pwd)/bin/gate-check.sh}"
TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
INIT="$TOOLKIT/bin/init-project.sh"
OK=0; BAD=0
ok(){ echo "  ok   $1"; OK=$((OK+1)); }
bad(){ echo "  FAIL $1"; BAD=$((BAD+1)); }
has(){ printf '%s' "$2" | grep -qF -- "$3" && ok "$1" || bad "$1 (looked for: $3)"; }

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
P="$W/p"; mkdir -p "$P"; : > "$P/Fixture.mpr"
MXTK_NO_GUIDE=1 "$INIT" "$P" >/dev/null 2>&1
OUT="$("$GATE" "$P" 2>&1)"; RC=$?

echo "== the column is reported at all =="
has "every stage line carries a Surface clause" "$OUT" "· Surface"
has "the calibration sentence is printed once" "$OUT" "it is a stage nobody can review"

echo "== the parse survives the prose it is aimed at =="
# Stage 3's cell has an em-dash INSIDE a parenthetical. Cutting at the gloss before stripping
# parentheticals drops everything after blueprint.html, so these two are the regression pin.
has "stage 3 keeps design-system.html (em-dash inside a parenthetical)" "$OUT" "design-system.html"
has "stage 3 keeps the wireframes glob"                                 "$OUT" "wireframes/*.html"
# Stage 2's cell names the RENAMED file after its em-dash gloss. Reporting it would tell every
# project it still owes an artifact the toolkit deleted — the exact drift this check exists for.
printf '%s' "$OUT" | grep -q 'enrichment-summary' \
  && bad "stage 2 reported the renamed enrichment-summary.html as an owed surface" \
  || ok "stage 2 ignores the historical name behind the gloss"
# A toolkit COMMAND sits in the same cell as the artifact it renders.
printf '%s' "$OUT" | grep -qE 'Surface [^—]*bin/' \
  && bad "a bin/ command was reported as a project surface" \
  || ok "toolkit commands are not mistaken for surfaces"

echo "== placeholders become globs =="
has "ui-review-<YYYY-MM-DD>.html is globbed" "$OUT" "ui-review-*.html"

echo "== absence is stated, never silent =="
has "a stage with no Surface row says so"  "$OUT" "Surface not declared in runbook §2"
has "a fresh project's missing surfaces are named" "$OUT" "Surface MISSING: analysis/brd-report.html"
has "index.html counts as present after init"      "$OUT" "Stage P (Kickoff): FAIL · Surface present"

echo "== reported, never enforced =="
# The whole contract: this must not be able to change a verdict or the exit code.
BEFORE_RC=$RC
touch "$P/test-report.html" "$P/build-plan.html"
OUT2="$("$GATE" "$P" 2>&1)"; RC2=$?
[ "$RC2" = "$BEFORE_RC" ] && ok "adding surfaces did not change the exit code" \
  || bad "exit code moved $BEFORE_RC -> $RC2 — a surface must not be a gate"
has "the now-present surface flips to present" "$OUT2" "Stage 4 (Build Plan): FAIL · Surface present"
printf '%s' "$OUT2" | grep -q 'Stage 4 (Build Plan): FAIL' \
  && ok "and the GATE verdict is untouched by it" \
  || bad "the gate verdict changed when only a surface appeared"

echo ""
echo "$(basename "$0"): $OK ok, $BAD FAIL"
[ "$BAD" -eq 0 ]
