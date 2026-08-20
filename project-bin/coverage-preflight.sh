#!/usr/bin/env bash
#
# coverage-preflight.sh — decide WHAT CAN BE MEASURED before bin/coverage-check.sh measures it.
#
# The toolkit's bin/coverage-check.sh is the measurement ENGINE: give it a BRD and a coverage
# ledger and it returns CLAIMED / LEDGERED / UNCLAIMED / PHANTOM / DOUBLE-CLAIMED. This script
# is the layer in front of it that answers the question the engine cannot: *is there a ledger,
# and if not, what does that absence actually mean here?*
#
# Why it exists (2026-08-20). A missing coverage-ledger.md was a hard FAULT, and the same FAULT
# was printed in two opposite situations:
#
#   (a) an existing-app audit (skills/existing-app-assurance.md — "no pipeline, no BRD, no
#       stages"). No ledger was ever going to exist. The fault is permanent, meaningless noise.
#   (b) a migration project that genuinely should have ledgers and has none. Measured case:
#       PROJECT-A — 12 BRDs, a blueprint, a build plan, 7 module briefs, zero ledgers. Here the
#       fault is real and the remedy is real.
#
# Same message, opposite meanings. This script separates them into four levels, keyed on WHAT IS
# PRESENT and never on a declared entry mode — a project onboarded as Migration can be running a
# Track B assurance pass on the same day, and PROJECT-A is doing exactly that.
#
#   LEVEL 1  MEASURED        ledger found            -> run the engine, verdicts unchanged
#   LEVEL 2  DERIVED         no ledger, but BRD +    -> join those two into a labelled derived
#                            build-plan `claims`        ledger under docs/coverage/, then measure
#   LEVEL 3  NOT MEASURED    BRDs, but no `claims`   -> report the honest DENOMINATOR (leaf count)
#                            anywhere in the plan       and name the remedy. Not a pass, not a crash
#   LEVEL 4  NOT APPLICABLE  no BRD at all           -> say so, with the reason. Never a fault
#
# HARD BOUNDARY: levels 2 and 3 derive from the BRD and the build plan ONLY. Nothing here ever
# reads the live model or shipped code to invent a requirement. A ledger records what was
# DECIDED; reverse-deriving one from what happens to exist inverts its meaning, and
# skills/report-schema.md is explicit that a requirement pointer must never be synthesized.
# See process/improvement-plan-e2e-reporting.md, Finding 3, option 2 (rejected).
#
# NOTHING BLOCKS. No new gate, no exit code made more severe than it was. Level 1 passes the
# engine's own verdict through unchanged; every other level is strictly *less* severe than
# today's FAULT. Every level states what it knows, what it does not, and what would upgrade it.
#
# Ledger path shapes — all three are read, the first is canonical:
#   architecture/modules/<Module>/coverage-ledger.md    canonical (per-module, scales)
#   architecture/modules/<Module>-coverage-ledger.md    flat module layout (PROJECT-A's shape)
#   architecture/coverage-ledger.md                     single-BRD project (sanctioned by
#                                                       skills/coverage-ledger.md's header)
# When none exists the message names all three, so an operator can act without reading source.
#
# Usage:
#   project-bin/coverage-preflight.sh [--summary] [--module <Name>] [<brd.json> [<ledger.md>]]
#   project-bin/coverage-preflight.sh --assess [--module <Name>]     # levels only, no measurement
#
# Exit: 0 clean (level 1/2)  ·  1 coverage findings (level 1/2)  ·  2 instrument fault
#       3 NOT MEASURED (level 3)  ·  4 NOT APPLICABLE (level 4)
# rc 3 follows bin/open-questions.sh's "NOTHING EXAMINED" precedent: an instrument that examined
# nothing must not exit 0, because 0 reads as green everywhere it is consumed.
#
# Bash 3.2 compatible (stock macOS). Read-only: never touches the .mpr, never writes to
# architecture/. Derived output goes to docs/coverage/ precisely so it cannot be mistaken for a
# decided artifact.
#
# ---------------------------------------------------------------------------------------------
# WHY THIS IS NOT A SECOND bin/coverage-check.sh, and why it lives in project-bin/
#
# It contains NO leaf enumeration and NO verdict logic. Look for `jq` in this file: there is none.
# That is deliberate. The enumeration in bin/coverage-check.sh §4.1 is subtle — `paths(f)` silently
# drops every false/null leaf, which once lost 44 security-relevant flags from F013 — and a second
# copy of it here is exactly the failure CLAUDE.md's "generic first" section and the header of
# bin/lib/discover-brds.sh record: *the fix does not travel*. So even LEVEL 3, whose whole output
# is a leaf count, gets that count by running the ENGINE against an empty ledger rather than by
# counting leaves itself. One enumeration, one home.
#
# It also never parses BRD CONTENT. It discovers BRD *paths* and hands them to the engine. The
# "anything reading BRDs lives in bin/" rule is about readers that must not care where a BRD came
# from; this script does not read them at all.
#
# It lives in project-bin/ because everything it does is project-local and project-relative:
# it resolves PROJECT_ROOT via project-bin/_common.sh, globs architecture/ and analysis/ relative
# to it, writes into that project's docs/coverage/, and is invoked as a sibling by
# project-bin/conformance-check.sh — which is itself a project-bin script for the same reasons.
# bin/coverage-check.sh takes two explicit file paths and resolves nothing; it could not do this
# job without growing a project-root resolver it has no other use for.
#
# It is named coverage-PREFLIGHT, not coverage-check, so the two are never confused and so
# verify-module.sh's `_tool` lookup (which searches $MXTK_ROOT/bin before $MXTK_ROOT/project-bin)
# cannot silently resolve one when the caller meant the other.
# ---------------------------------------------------------------------------------------------

set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
cd "$PROJECT_ROOT" || exit 2

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

MODULE=""
SUMMARY=0
ASSESS=0
ARG_BRD=""
ARG_LEDGER=""

while [ $# -gt 0 ]; do
  case "$1" in
    --summary)  SUMMARY=1; shift ;;
    --assess)   ASSESS=1; shift ;;
    --module)   MODULE="${2:-}"; shift 2 ;;
    -h|--help)  sed -n '2,60p' "$0"; exit 0 ;;
    -*)         echo "unknown argument: $1" >&2; exit 2 ;;
    *)          if [ -z "$ARG_BRD" ]; then ARG_BRD="$1"; else ARG_LEDGER="$1"; fi; shift ;;
  esac
done

# ---------------------------------------------------------------------------
# The engine. The self-path guard stays even though the names now differ: a project that copies
# this script into its own bin/ under the engine's name would otherwise re-enter it forever.
# ---------------------------------------------------------------------------
find_engine() {
  local c
  for c in "${COVERAGE_ENGINE:-}" \
           "${MXTK_ROOT:-}/bin/coverage-check.sh" \
           "$(dirname "$SELF")/../bin/coverage-check.sh" \
           "$PROJECT_ROOT/bin/coverage-check.sh"; do
    [ -n "$c" ] || continue
    [ -x "$c" ] || continue
    [ "$(cd "$(dirname "$c")" && pwd)/$(basename "$c")" = "$SELF" ] && continue
    printf '%s\n' "$c"; return 0
  done
  return 1
}

# ---------------------------------------------------------------------------
# Discovery
# ---------------------------------------------------------------------------
LEDGER_CANON=""
LEDGER_FLAT=""
LEDGER_PROJECT="architecture/coverage-ledger.md"
if [ -n "$MODULE" ]; then
  LEDGER_CANON="architecture/modules/$MODULE/coverage-ledger.md"
  LEDGER_FLAT="architecture/modules/$MODULE-coverage-ledger.md"
fi

find_ledger() {
  local c
  for c in "$ARG_LEDGER" "${LEDGER_FILE:-}" "$LEDGER_CANON" "$LEDGER_FLAT" "$LEDGER_PROJECT"; do
    [ -n "$c" ] && [ -f "$c" ] && { printf '%s\n' "$c"; return 0; }
  done
  return 1
}

# Every BRD in the project, one per line. Both layouts the pipelines actually write.
find_brds() {
  local p
  if [ -n "$ARG_BRD" ]; then printf '%s\n' "$ARG_BRD"; return 0; fi
  if [ -n "${BRD_FILE:-}" ]; then printf '%s\n' "$BRD_FILE"; return 0; fi
  # sort -u, because the globs overlap: analysis/knowledge-base/brd/*.brd.json is matched by
  # BOTH the second and third pattern, and a doubled BRD doubles the level-3 leaf count.
  for p in analysis/*/brd/*.brd.json analysis/*/knowledge-base/brd/*.brd.json \
           analysis/knowledge-base/brd/*.brd.json; do
    [ -f "$p" ] && printf '%s\n' "$p"
  done | sort -u
}

# Build plans that could carry `claims`, project-level and per-module.
find_plans() {
  local p
  for p in architecture/build-plan.md \
           architecture/modules/build-plan.md \
           architecture/modules/"$MODULE"/build-plan.md; do
    [ -n "$p" ] && [ -f "$p" ] && printf '%s\n' "$p"
  done
}

# ---------------------------------------------------------------------------
# Claim extraction — the `claims:` block form defined by skills/brd-to-build-plan.md Step 5b:
#
#     5 · 05-orders-pages.mdl | Order_List page + supporting microflows
#     claims:
#       /pages/0/buildComposition/gridColumns/* (7)
#       /pages/0/buildComposition/rowClick
#
# One pointer cell per line, block ends at the first line that is not a pointer. The row's
# identity is the nearest preceding non-blank line, which is all a derived ledger needs to say
# WHICH row claimed a leaf.
# ---------------------------------------------------------------------------
extract_claims() {
  awk '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    /^[ \t]*claims:[ \t]*$/ { inblock = 1; next }
    /^[ \t]*claims:[ \t]*\// {
      line = $0; sub(/^[ \t]*claims:[ \t]*/, "", line)
      print row "\t" trim(line); inblock = 1; next
    }
    {
      if (inblock) {
        if ($0 ~ /^[ \t]+\//) { print row "\t" trim($0); next }
        inblock = 0
      }
      if (trim($0) != "") { row = trim($0) }
    }
  ' "$@"
}

# ---------------------------------------------------------------------------
# Level decision
# ---------------------------------------------------------------------------
LEDGER="$(find_ledger || true)"
BRDS="$(find_brds)"
PLANS="$(find_plans)"
NBRD=0; [ -n "$BRDS" ] && NBRD=$(printf '%s\n' "$BRDS" | grep -c .)
CLAIMS=""
[ -n "$PLANS" ] && CLAIMS="$(extract_claims $PLANS 2>/dev/null || true)"
NCLAIMS=0; [ -n "$CLAIMS" ] && NCLAIMS=$(printf '%s\n' "$CLAIMS" | grep -c .)

if   [ -n "$LEDGER" ];                              then LEVEL=1
elif [ "$NBRD" -gt 0 ] && [ "$NCLAIMS" -gt 0 ];     then LEVEL=2
elif [ "$NBRD" -gt 0 ];                             then LEVEL=3
else                                                     LEVEL=4
fi

WHERE="${MODULE:-this project}"

# The paths tried, printed verbatim so "not found" is actionable rather than a riddle.
print_paths_tried() {
  echo "  looked for a ledger at:"
  [ -n "$LEDGER_CANON" ] && printf '    %-50s (canonical, per-module)\n' "$LEDGER_CANON"
  [ -n "$LEDGER_FLAT" ]  && printf '    %-50s (flat module layout)\n' "$LEDGER_FLAT"
  printf '    %-50s (single-BRD project)\n' "$LEDGER_PROJECT"
  [ -z "$MODULE" ] && echo "    (no --module given, so the two per-module shapes were not tried)"
  return 0
}

print_assessment() {
  case "$LEVEL" in
    1) echo "coverage · LEVEL 1 · MEASURED — ledger found for $WHERE"
       echo "  ledger: $LEDGER"
       ;;
    2) echo "coverage · LEVEL 2 · DERIVED — no ledger for $WHERE, deriving one from decided artifacts"
       print_paths_tried
       echo "  found instead: $NBRD BRD(s) and $NCLAIMS build-plan claim pointer(s)."
       echo "  skills/coverage-ledger.md defines the ledger as generated from exactly those two,"
       echo "  so this is a join over decided artifacts, not invention. Verdicts below are real,"
       echo "  but the ledger they were measured against is DERIVED and was never signed off."
       echo "  To upgrade to LEVEL 1: review the derived ledger and commit it as $( [ -n "$LEDGER_CANON" ] && printf '%s' "$LEDGER_CANON" || printf '%s' "$LEDGER_PROJECT" )."
       ;;
    3) echo "coverage · LEVEL 3 · NOT MEASURED — a denominator exists, traceability does not"
       print_paths_tried
       echo "  found instead: $NBRD BRD(s), and ZERO \`claims:\` blocks in:"
       if [ -n "$PLANS" ]; then printf '    %s\n' $PLANS; else echo "    (no build plan found)"; fi
       echo "  The build plan predates the \`claims\` convention (skills/brd-to-build-plan.md Step 5b),"
       echo "  so no requirement leaf can be traced to a row. This is not a pass and not a crash:"
       echo "  the leaf count below is real, the coverage over it is unknown."
       echo "  To upgrade to LEVEL 2: add a \`claims:\` block under each build-plan row."
       ;;
    4) echo "coverage · LEVEL 4 · NOT APPLICABLE — no pipeline produced a spec for $WHERE"
       echo "  No BRD was found under analysis/*/brd/ or analysis/*/knowledge-base/brd/, so there"
       echo "  is no set of requirements to measure coverage against. Nothing is broken."
       echo "  This is the normal, permanent state for an existing-app audit"
       echo "  (skills/existing-app-assurance.md — \"no pipeline, no BRD, no stages\"): such an app"
       echo "  is audited against itself, never traced back to a spec it never had."
       echo "  To upgrade: this instrument only becomes applicable if the app is taken through the"
       echo "  migration or requirements-driven pipeline, which produces BRDs at Stage 2."
       ;;
  esac
}

if [ "$ASSESS" -eq 1 ]; then
  print_assessment
  case "$LEVEL" in 1|2) exit 0 ;; 3) exit 3 ;; 4) exit 4 ;; esac
fi

print_assessment
echo ""

# ---------------------------------------------------------------------------
# LEVEL 4 — stop here. Quietly, with the reason already printed.
# ---------------------------------------------------------------------------
[ "$LEVEL" -eq 4 ] && exit 4

ENGINE="$(find_engine || true)"
if [ -z "$ENGINE" ]; then
  # Verbatim phrasing from bin/gate-check.sh — the toolkit already has one sentence for this.
  echo "FAULT: bin/coverage-check.sh not found or not executable — cannot evaluate, which is not a pass." >&2
  echo "       Set COVERAGE_ENGINE=<path> or MXTK_ROOT=<toolkit clone>." >&2
  exit 2
fi

DERIVED_DIR="docs/coverage"
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/coverage-front.XXXXXX")" || exit 2
trap 'rm -rf "$TMPD"' EXIT

# ---------------------------------------------------------------------------
# LEVEL 3 — denominator only.
#
# The leaf count is produced by the ENGINE, run against an empty ledger, rather than by a second
# copy of the jq enumeration. That enumeration is subtle (bin/coverage-check.sh §4.1: `paths(f)`
# silently drops every false/null leaf, which once lost 44 security-relevant flags), and a second
# copy of it here would be exactly the duplication CLAUDE.md's "generic first" section was written
# about: the fix would not travel.
# ---------------------------------------------------------------------------
if [ "$LEVEL" -eq 3 ]; then
  EMPTY="$TMPD/empty-ledger.md"
  {
    echo "| pointer | type | title | slice | writeMode | acceptance | status |"
    echo "|---|---|---|---|---|---|---|"
  } > "$EMPTY"

  TOTAL=0
  for b in $BRDS; do
    n="$("$ENGINE" --summary "$b" "$EMPTY" 2>/dev/null | awk '/^  leaves:/ {print $2}')"
    [ -n "$n" ] || n=0
    printf '  %-60s %6s leaves\n' "$b" "$n"
    TOTAL=$((TOTAL + n))
  done

  echo ""
  echo "  $TOTAL requirement leaves across $NBRD BRD(s); 0 traceable to a build-plan row."
  echo "  Add \`claims:\` to build-plan rows to close this (skills/brd-to-build-plan.md Step 5b)."
  echo "  Coverage for $WHERE is UNMEASURED, not clean."
  exit 3
fi

# ---------------------------------------------------------------------------
# LEVEL 2 — derive, label, measure.
#
# The derived ledger lands in docs/coverage/, NEVER in architecture/. architecture/ holds decided
# artifacts that a human signed off; a file this script generated is evidence, not a decision, and
# putting it there would let the next run read its own output back as LEVEL 1.
# ---------------------------------------------------------------------------
if [ "$LEVEL" -eq 2 ]; then
  mkdir -p "$DERIVED_DIR" || exit 2
  DERIVED="$DERIVED_DIR/derived-ledger${MODULE:+-$MODULE}.md"
  {
    echo "# DERIVED coverage ledger — ${MODULE:-project}"
    echo ""
    echo "**DERIVED — not a decided artifact.** Generated by \`project-bin/coverage-preflight.sh\` on"
    echo "$(date +%Y-%m-%d) by joining the build plan's \`claims\` blocks with the project's BRDs,"
    echo "because no \`coverage-ledger.md\` exists. Nobody signed this off, and it contains only"
    echo "what the plan already claimed — it invents nothing and it reads no code and no model."
    echo ""
    echo "It has no NON-BUILDABLE table, so a leaf that is deliberately deferred or descoped will"
    echo "show as UNCLAIMED here. To fix that properly, review this file and commit it as"
    echo "\`$( [ -n "$LEDGER_CANON" ] && printf '%s' "$LEDGER_CANON" || printf '%s' "$LEDGER_PROJECT" )\` with the reasons filled in."
    echo ""
    echo "Sources:"
    printf '  - %s\n' $PLANS
    printf '  - %s\n' $BRDS
    echo ""
    echo "| pointer | type | title | slice | writeMode | acceptance | status |"
    echo "|---|---|---|---|---|---|---|"
    # A build-plan row line normally CONTAINS a pipe ("5 · 05-orders.mdl | Order_List page"), and
    # dropping it into a markdown cell unescaped turns a 7-column row into a 9-column one — which
    # is how the engine decides which table it is reading. Escape it.
    printf '%s\n' "$CLAIMS" | while IFS=$'\t' read -r row ptr; do
      [ -n "$ptr" ] || continue
      row="$(printf '%s' "${row:-unattributed}" | sed 's/|/\\|/g')"
      printf '| %s | derived | %s | - | - | - | derived |\n' "$ptr" "$row"
    done
  } > "$DERIVED"

  echo "  derived ledger written to $DERIVED ($NCLAIMS claim cell(s))"
  echo ""
  LEDGER="$DERIVED"
fi

# ---------------------------------------------------------------------------
# LEVEL 1 (and LEVEL 2 measuring its derived ledger) — the engine, verdict passed through.
# ---------------------------------------------------------------------------
ENGINE_ARGS=""
[ "$SUMMARY" -eq 1 ] && ENGINE_ARGS="--summary"

if [ "$NBRD" -eq 0 ]; then
  echo "FAULT: a ledger exists at $LEDGER but no BRD was found to measure it against." >&2
  echo "       Looked under analysis/*/brd/ and analysis/*/knowledge-base/brd/." >&2
  echo "       Set BRD_FILE=<path>. Cannot evaluate, which is not a pass." >&2
  exit 2
fi

RC=0
for b in $BRDS; do
  # shellcheck disable=SC2086
  "$ENGINE" $ENGINE_ARGS "$b" "$LEDGER" || RC=$?
done

if [ "$LEVEL" -eq 2 ]; then
  echo ""
  echo "  Read the verdicts above as LEVEL 2 (DERIVED): they are measured against a ledger this"
  echo "  script generated, not one anybody approved. UNCLAIMED here may be a real gap or may be"
  echo "  work that was deliberately deferred and has no ledger entry saying so yet."
fi

exit "$RC"
