#!/usr/bin/env bash
# conformance-check.sh — recompute coverage-ledger status against the live model.
#
# A stored status is a claim; this script measures it. For every BUILDABLE ledger row
# whose `acceptance` cell contains a runnable `SHOW ...` / `DESCRIBE ...`, the command is
# re-run against the .mpr and the observed result is compared with the stored `status`.
#
# Read-only: runs only SHOW/DESCRIBE. Never `exec`, never MDL, never touches the .mpr.
#
# Verdicts
#   OK          stored status agrees with the model
#   STALE       status says built/partial, but the element is ABSENT   <- the one that matters
#   UNDERSTATED status says not-built, but the element is PRESENT
#
# Failure policy: regressions only. A row that was OK in the baseline and is no longer OK
# fails the run. Pre-existing mismatches are reported but do not fail — the lesson from lint,
# which was made optional because day-one noise made it unusable, and now never runs at all.
#
# When there is no ledger
#
# A missing ledger used to be a hard FAULT, and the same FAULT was printed in two opposite
# situations: an existing-app audit that was never going to have one, and a migration project
# that should have one and doesn't. Both read identically, so an operator could not tell
# permanent noise from a real gap. This script now defers that judgement to
# `coverage-preflight.sh --assess`, which grades it into four levels on WHAT IS PRESENT (BRDs,
# build-plan `claims`) rather than on a declared entry mode. See that script's header for the
# levels and process/improvement-plan-e2e-reporting.md Finding 3 for the incident.
#
# Nothing here blocks that did not block before, and no exit code got more severe: a missing
# ledger now exits 3 (NOT MEASURED) or 4 (NOT APPLICABLE) instead of 2 (FAULT).
#
# Ledger path shapes, all read, first is canonical:
#   architecture/modules/<Module>/coverage-ledger.md   canonical (per-module)
#   architecture/modules/<Module>-coverage-ledger.md   flat module layout
#   architecture/coverage-ledger.md                    single-BRD project
#
# Usage:
#   bin/conformance-check.sh [--module <Name>] [--update-baseline] [--quiet]
#
# Exit: 0 clean or baseline written · 1 regression · 2 instrument fault (refuses to guess)
#       3 NOT MEASURED (no ledger, but a spec exists) · 4 NOT APPLICABLE (no spec at all)

set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
cd "$PROJECT_ROOT" || exit 2

MPR="$(find_mpr)" || exit 2
MXCLI="./mxcli"
OUTDIR="docs/conformance"
BASELINE="$OUTDIR/baseline.tsv"
MODULE=""
UPDATE_BASELINE=0
QUIET=0

while [ $# -gt 0 ]; do
  case "$1" in
    --module)          MODULE="${2:-}"; shift 2 ;;
    --update-baseline) UPDATE_BASELINE=1; shift ;;
    --quiet)           QUIET=1; shift ;;
    -h|--help)         sed -n '2,43p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -x "$MXCLI" ] || { echo "FAULT: $MXCLI not found or not executable" >&2; exit 2; }
[ -f "$MPR" ]   || { echo "FAULT: $MPR not found" >&2; exit 2; }
mkdir -p "$OUTDIR"

# --- find the ledger(s) ------------------------------------------------------------------
# Three path shapes are in the wild and all three are legitimate. The canonical one is the
# per-module directory; the flat one exists because real projects lay architecture/modules/ out
# flat (VB-USI: `Approval-brief.md`, `ProductNumbers.md`, no subdirectories at all); the
# project-level one is sanctioned by skills/coverage-ledger.md's own header for a single-BRD
# project. Globbing only the canonical shape is why a project with ledgers in the flat shape
# would still be told it had none.
#
# LEDGER_COUNT is tracked separately rather than read back as ${#LEDGERS[@]}: under `set -u`,
# bash 3.2 (stock macOS) treats an EMPTY array as unset and aborts on that expansion — which is
# precisely the case this block exists to handle gracefully.
LEDGERS=()
LEDGER_COUNT=0
if [ -n "$MODULE" ]; then
  for c in "${LEDGER_FILE:-}" \
           "architecture/modules/$MODULE/coverage-ledger.md" \
           "architecture/modules/$MODULE-coverage-ledger.md" \
           "architecture/coverage-ledger.md"; do
    [ -n "$c" ] && [ -f "$c" ] && { LEDGERS=("$c"); LEDGER_COUNT=1; break; }
  done
else
  for c in architecture/modules/*/coverage-ledger.md \
           architecture/modules/*-coverage-ledger.md \
           architecture/coverage-ledger.md; do
    if [ -f "$c" ]; then LEDGERS[$LEDGER_COUNT]="$c"; LEDGER_COUNT=$((LEDGER_COUNT+1)); fi
  done
fi

# --- no ledger: grade the absence instead of faulting on it -------------------------------
# The absence itself carries no information — the same missing file means "this project skipped
# a step" and "this entry mode never had the step" — so hand the judgement to the one place that
# grades it, rather than printing a verdict this script cannot justify.
if [ "$LEDGER_COUNT" -eq 0 ]; then
  echo "conformance · no coverage ledger for ${MODULE:-this project}"
  echo ""
  # The paths tried are printed by the assessor below, once, rather than by both scripts.

  ASSESSOR=""
  for c in "$(dirname "${BASH_SOURCE[0]}")/coverage-preflight.sh" \
           "${MXTK_ROOT:-}/project-bin/coverage-preflight.sh"; do
    [ -x "$c" ] && { ASSESSOR="$c"; break; }
  done

  if [ -z "$ASSESSOR" ]; then
    echo "  coverage-preflight.sh not found or not executable — cannot evaluate what this absence" >&2
    echo "  means, which is not a pass." >&2
    exit 2
  fi

  if [ -n "$MODULE" ]; then "$ASSESSOR" --assess --module "$MODULE"; else "$ASSESSOR" --assess; fi
  LEVEL_RC=$?

  echo ""
  case "$LEVEL_RC" in
    0)  # A spec exists (level 1 says a ledger does after all, level 2 says one is derivable).
        # Conformance still cannot run: it measures the ledger's `acceptance` commands against
        # the live model, and a ledger derived from BRD + `claims` carries no acceptance cells.
        # Synthesizing them would mean reading the model to decide what the requirement was,
        # which is the reverse-derivation this whole change exists to refuse.
        echo "  A ledger is derivable here, but a DERIVED ledger carries no \`acceptance\` cells,"
        echo "  and conformance measures exactly those. Synthesizing acceptance commands would"
        echo "  mean asking the model what the requirement was — the inversion this instrument"
        echo "  refuses. Conformance for ${MODULE:-this project} is UNMEASURED, not clean."
        echo "  To measure it: write the ledger with acceptance cells (skills/coverage-ledger.md)."
        exit 3 ;;
    3)  echo "  Conformance for ${MODULE:-this project} is UNMEASURED, not clean."
        exit 3 ;;
    4)  echo "  Conformance does not apply to ${MODULE:-this project}: with no ledger and no BRD"
        echo "  there is no stored claim to measure the model against. Nothing is broken."
        exit 4 ;;
    *)  exit 2 ;;
  esac
fi

# --- extract (module, pointer, status, command) from BUILDABLE rows -------------------
# A BUILDABLE row is a 7-column table row whose first cell is a JSON Pointer. awk sees 9
# fields because of the leading and trailing pipes. Only rows with a backticked
# SHOW/DESCRIBE in the acceptance cell are measurable; the rest are counted, not run.
# The module label comes from the path, and the path has three shapes (above), so read it per
# shape instead of assuming the parent directory is always the module.
ledger_module() {
  local ledger="$1" base parent
  base="$(basename "$ledger")"
  parent="$(basename "$(dirname "$ledger")")"
  case "$base" in
    *-coverage-ledger.md) printf '%s\n' "${base%-coverage-ledger.md}"; return ;;
  esac
  case "$parent" in
    architecture) printf '%s\n' "${MODULE:-project}"; return ;;
    *)            printf '%s\n' "$parent"; return ;;
  esac
}

extract() {
  local ledger="$1" mod
  mod="$(ledger_module "$ledger")"
  awk -F'|' -v mod="$mod" '
    NF==9 && $2 ~ /^ *`\// {
      total++
      ptr=$2; acc=$7; st=$8
      gsub(/^ +| +$/, "", ptr); gsub(/^ +| +$/, "", st)
      if (match(acc, /`(SHOW|DESCRIBE)[^`]*`/)) {
        cmd = substr(acc, RSTART+1, RLENGTH-2)
        print "ROW\t" mod "\t" ptr "\t" st "\t" cmd
      } else {
        print "PROSE\t" mod "\t" ptr "\t" st "\t"
      }
    }
  ' "$ledger"
}

ROWS="$(for l in "${LEDGERS[@]}"; do [ -f "$l" ] && extract "$l"; done)"

MEASURABLE=$(printf '%s\n' "$ROWS" | grep -c '^ROW' || true)
PROSE=$(printf '%s\n' "$ROWS" | grep -c '^PROSE' || true)

# Non-vacuous guard: an instrument that measured nothing must not report "all clean".
if [ "$MEASURABLE" -eq 0 ]; then
  echo "FAULT: 0 measurable rows extracted from ${#LEDGERS[@]} ledger(s)." >&2
  echo "       Either the ledger table shape changed or the glob matched nothing." >&2
  echo "       Refusing to report a clean run over zero measurements." >&2
  exit 2
fi

# --- measure --------------------------------------------------------------------------
# Not every backticked fragment in an acceptance cell is a command. Ledgers contain prose
# like `DESCRIBE PAGE` (no operand) and `DESCRIBE PAGE …Route_List` (an ellipsis placeholder).
# Running those wastes time and, worse, invites a hang. Classify them instead of guessing.
runnable() {
  local c="$1"
  case "$c" in
    *…*|*"..."*) return 1 ;;                       # elided placeholder, not a real command
  esac
  # Must be VERB [NOUN...] OPERAND — i.e. end in something that looks like an identifier.
  printf '%s' "$c" | grep -Eq '^(SHOW|DESCRIBE)( +[A-Z]+)+ +[A-Za-z_][A-Za-z0-9_.]*( .*)?$' && return 0
  # SHOW <PLURAL> with no operand is legitimate (e.g. "SHOW MODULES", "SHOW PAGES").
  printf '%s' "$c" | grep -Eq '^SHOW +[A-Z]+$' && return 0
  return 1
}

# Portable timeout: macOS has no coreutils `timeout`. Running mxcli unguarded risks a stall
# that looks identical to a slow project. (An earlier version of this script used `timeout`
# and silently measured nothing at all, because the binary does not exist here — rc=127.)
TIMEOUT_S=25
run_guarded() {
  local cmd="$1" tmp rc pid killer
  tmp="$(mktemp)"
  "$MXCLI" -p "$MPR" -c "$cmd" >"$tmp" 2>&1 </dev/null &
  pid=$!
  ( sleep "$TIMEOUT_S"; kill -9 "$pid" 2>/dev/null ) & killer=$!
  wait "$pid" 2>/dev/null; rc=$?
  kill "$killer" 2>/dev/null; wait "$killer" 2>/dev/null
  cat "$tmp"; rm -f "$tmp"
  return $rc
}

# PRESENT = mxcli exited 0, produced output, and the output is not an empty result set.
probe() {
  local cmd="$1" out rc
  if ! runnable "$cmd"; then echo "UNRUNNABLE"; return; fi
  out="$(run_guarded "$cmd")"; rc=$?
  if [ $rc -ge 128 ]; then echo "TIMEOUT"; return; fi
  if [ $rc -ne 0 ]; then echo "ABSENT"; return; fi
  if [ -z "$(printf '%s' "$out" | tr -d '[:space:]')" ]; then echo "ABSENT"; return; fi
  case "$out" in
    Error:*|*"not found"*) echo "ABSENT"; return ;;
    *"(0 "*)               echo "ABSENT"; return ;;   # empty result set, e.g. "(0 entities)"
  esac
  echo "PRESENT"
}

RESULTS=""
n=0
while IFS=$'\t' read -r kind mod ptr status cmd; do
  [ "$kind" = "ROW" ] || continue
  n=$((n+1))
  [ "$QUIET" -eq 1 ] || printf '\r  measuring %d/%d ' "$n" "$MEASURABLE" >&2
  observed="$(probe "$cmd")"
  case "$observed" in
    UNRUNNABLE) verdict="UNRUNNABLE" ;;   # acceptance cell looks executable but is not
    TIMEOUT)    verdict="TIMEOUT" ;;      # never treated as a pass
    *)
      case "$status:$observed" in
        built:PRESENT|partial:PRESENT|not-built:ABSENT|accepted:PRESENT) verdict="OK" ;;
        built:ABSENT|partial:ABSENT|accepted:ABSENT)                     verdict="STALE" ;;
        not-built:PRESENT)                                               verdict="UNDERSTATED" ;;
        *)                                                               verdict="UNKNOWN-STATUS" ;;
      esac ;;
  esac
  RESULTS+="$mod	$ptr	$status	$observed	$verdict	$cmd"$'\n'
done 3<<< "$ROWS" <&3
[ "$QUIET" -eq 1 ] || printf '\r%*s\r' 30 '' >&2

RESULTS="$(printf '%s' "$RESULTS" | sed '/^$/d' | sort)"

# --- baseline / regression --------------------------------------------------------------
KEYED="$(printf '%s\n' "$RESULTS" | awk -F'\t' '{print $1"\t"$2"\t"$5}')"

if [ "$UPDATE_BASELINE" -eq 1 ] || [ ! -f "$BASELINE" ]; then
  printf '%s\n' "$KEYED" > "$BASELINE"
  WROTE_BASELINE=1
else
  WROTE_BASELINE=0
fi

REGRESSIONS=""
if [ "$WROTE_BASELINE" -eq 0 ]; then
  while IFS=$'\t' read -r mod ptr verdict; do
    [ -n "$mod" ] || continue
    was="$(awk -F'\t' -v m="$mod" -v p="$ptr" '$1==m && $2==p {print $3}' "$BASELINE")"
    if [ "$was" = "OK" ] && [ "$verdict" != "OK" ]; then
      REGRESSIONS+="$mod	$ptr	was OK, now $verdict"$'\n'
    fi
  done <<< "$KEYED"
fi

# --- report ------------------------------------------------------------------------------
STAMP="$(date +%Y-%m-%d)"
REPORT="$OUTDIR/report-$STAMP.tsv"
{ printf 'module\tpointer\tstored\tobserved\tverdict\tcommand\n'; printf '%s\n' "$RESULTS"; } > "$REPORT"

count() { printf '%s\n' "$RESULTS" | awk -F'\t' -v v="$1" '$5==v' | grep -c . || true; }
OK=$(count OK); STALE=$(count STALE); UNDER=$(count UNDERSTATED); UNK=$(count UNKNOWN-STATUS)
UNRUN=$(count UNRUNNABLE); TMO=$(count TIMEOUT)
TOTAL=$((MEASURABLE + PROSE))
NREG=$(printf '%s' "$REGRESSIONS" | grep -c . || true)

echo "conformance-check · $STAMP"
echo "  ledger rows            $TOTAL   (measured $MEASURABLE · prose-only $PROSE)"
echo "  OK                     $OK"
echo "  STALE                  $STALE   (claims built/partial, model says absent)"
echo "  UNDERSTATED            $UNDER"
[ "$UNRUN" -gt 0 ] && echo "  UNRUNNABLE             $UNRUN   (backticked prose, not a command)"
[ "$TMO" -gt 0 ]   && echo "  TIMEOUT                $TMO   (>${TIMEOUT_S}s — never counted as a pass)"
[ "$UNK" -gt 0 ]   && echo "  UNKNOWN-STATUS         $UNK"
echo "  report                 $REPORT"

if [ "$STALE" -gt 0 ] || [ "$UNDER" -gt 0 ]; then
  echo
  echo "  mismatches:"
  printf '%s\n' "$RESULTS" | awk -F'\t' '$5!="OK" {printf "    %-24s %-28s %-11s -> %-7s %s\n", $1, $2, $3, $4, $5}'
fi

if [ "$WROTE_BASELINE" -eq 1 ]; then
  echo
  echo "  baseline written to $BASELINE ($MEASURABLE rows). Regressions are measured from here."
  exit 0
fi

if [ "$NREG" -gt 0 ]; then
  echo
  echo "  REGRESSIONS ($NREG) — these passed at baseline and do not now:"
  printf '%s' "$REGRESSIONS" | sed 's/^/    /'
  exit 1
fi

echo
echo "  no regressions against baseline."
exit 0
