#!/usr/bin/env bash
# verify-module.sh — the module-end deep pass. Runs the instruments, never fixes anything.
#
# WHY THIS EXISTS
# Deep verification was always specified and never ran. The most complete spec in the corpus put it
# at "Step 10" of a build — review agents ×6, UI loop, e2e+DB, monkey, OTel, OQL — and step 10.0
# BLOCKED before 10.1 could start, 29 scripts deep, because that project had never once loaded.
# Scheduling deep verification last is the same as not having it. This script makes it ONE command
# so it can run at every module boundary instead of at the end of a project that never arrives.
#
# THE RULE THAT MAKES THE REPORT WORTH READING
#   Instrument fault  ≠  feature failure.
# Every instrument below already distinguishes them: exit 2 means the instrument could not run,
# exit 1 means it ran and found something. This script keeps those apart to the end and refuses to
# print a PASS while any instrument is faulted. A suite that reports "clean" because half of it never
# executed is the exact false green the loop exists to retire.
#
# DIAGNOSTIC ONLY. No mxcli exec, no MDL, no writes to the .mpr. Findings go to a report; a human
# decides what to do with them. (`mxcli test` and `mxcli docker check` DO write to the model and are
# therefore deliberately absent from this chain, however read-only they sound.)
#
# Usage:
#   bin/verify-module.sh <Module> [--skip-monkey] [--skip-journeys] [--quick]
#
# Optional inputs, discovered not assumed. Each missing one is a FAULT with a named reason, never a
# silent skip:
#   architecture/modules/<Module>/coverage-ledger.md   requirement traceability
#   analysis/*/brd/*.brd.json | analysis/*/knowledge-base/brd/*.brd.json   the BRD
#   journeys/<Module>.journey.json                     the golden-path walk
#   tests/e2e/journey-runner.js, tests/e2e/monkey.js   the runtime instruments
# Override any of them: JOURNEY_DIR, JOURNEY_RUNNER, MONKEY_JS, BRD_FILE, LEDGER_FILE.
#
# Exit: 0 all instruments ran and found nothing · 1 findings · 2 an instrument could not run

set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
ROOT="$PROJECT_ROOT"
cd "$ROOT" || exit 2
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODULE="${1:-}"
[ -n "$MODULE" ] && [ "${MODULE#--}" = "$MODULE" ] || {
  sed -n '2,40p' "$0"; exit 2; }
shift

SKIP_MONKEY=0; SKIP_JOURNEYS=0; QUICK=0
for a in "$@"; do
  case "$a" in
    --skip-monkey)   SKIP_MONKEY=1 ;;
    --skip-journeys) SKIP_JOURNEYS=1 ;;
    --quick)         QUICK=1; SKIP_MONKEY=1 ;;
    *) echo "unknown arg: $a" >&2; exit 2 ;;
  esac
done

OUTDIR="$ROOT/.claude/loop/verify/$MODULE"
mkdir -p "$OUTDIR"
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
SUMMARY="$OUTDIR/summary.tsv"
printf 'instrument\tverdict\trc\telapsed\tlog\n' > "$SUMMARY"

c_ok()   { printf '\033[32m%s\033[0m' "$1"; }
c_bad()  { printf '\033[31m%s\033[0m' "$1"; }
c_warn() { printf '\033[33m%s\033[0m' "$1"; }

FINDINGS=0
FAULTED=0

# The scope of a verdict is GENERATED from what actually ran, never hardcoded.
#
# This existed as a fixed sentence claiming "the golden-path journey and a 24-round crash net",
# printed verbatim after `--skip-journeys --skip-monkey` and on any project where monkey.js is
# simply not installed. That is a false green inside the harness whose entire purpose is to retire
# false greens — see the header of this file. Measured 2026-08-18.
#
# A flag-skip stays exit 0: the operator asked for it. What must not survive is a verdict sentence
# claiming coverage the flag suppressed.
print_scope() {
  awk -F'\t' '
    NR > 1 {
      if      ($2 == "PASS")    pass = pass ? pass ", " $1 : $1
      else if ($2 == "INFO")    info = info ? info ", " $1 : $1
      else if ($2 == "SKIPPED") skip = skip ? skip "; " $1 " " $5 : $1 " " $5
    }
    END {
      if (pass) print "  Verified: " pass
      if (info) print "  Ran, informational — does not gate: " info
      if (skip) print "  NOT MEASURED: " skip
      if (skip) print "                These are absent, not green."
    }' "$SUMMARY"
}

# Record a fault for something that could not even be attempted. Same bucket as a crashed
# instrument, because the consequence is identical: that property of the module is UNMEASURED.
fault() {
  local name="$1" why="$2" extra="${3:-}"
  printf '\n\033[1m── %s\033[0m\n' "$name"
  c_warn "  ! INSTRUMENT FAULT"; echo " — $why"
  [ -n "$extra" ] && echo "      $extra"
  printf '%s\tFAULT\t2\t-\t(%s)\n' "$name" "$why" >> "$SUMMARY"
  FAULTED=$((FAULTED+1))
}

# Portable timeout. macOS ships no `timeout(1)`, and coreutils' `gtimeout` is not a safe assumption
# either, so this is a watchdog around a backgrounded child.
#
# A timeout is a FAULT, never a FAIL. "The instrument did not finish" and "the feature is broken" are
# different reports, and collapsing them sends you to debug a page that was never measured. Measured:
# conformance-check spends ~25s per ledger row (a 22-row module ≈ 9 min), so these budgets are
# generous on purpose — a budget tight enough to clip a healthy run manufactures faults, which is its
# own kind of lie.
with_timeout() {
  local secs="$1"; shift
  "$@" & local child=$!
  ( sleep "$secs"; kill -9 "$child" 2>/dev/null ) & local watchdog=$!
  wait "$child" 2>/dev/null; local rc=$?
  kill "$watchdog" 2>/dev/null; wait "$watchdog" 2>/dev/null
  # 137 = SIGKILL from the watchdog. Remap to 2 so it lands in the FAULT bucket.
  [ "$rc" -eq 137 ] && return 2
  return "$rc"
}

# run <name> <logfile> <kind> <timeout_s> -- <cmd...>
#   kind=gate   exit 1 => finding, exit 2 => instrument fault
#   kind=info   never fails the pass; recorded for the trend line
run() {
  local name="$1" log="$2" kind="$3" tmo="$4"; shift 5   # the literal --
  printf '\n\033[1m── %s\033[0m  \033[2m(budget %ss)\033[0m\n' "$name" "$tmo"
  local t0; t0=$(date +%s)
  with_timeout "$tmo" "$@" > "$log" 2>&1
  local rc=$?
  local secs=$(( $(date +%s) - t0 ))
  [ "$rc" -eq 2 ] && [ "$secs" -ge "$tmo" ] && \
    echo "TIMED OUT after ${tmo}s — did not finish, so nothing was measured." >> "$log"
  local verdict
  case "$kind:$rc" in
    *:0)      verdict=PASS ;;
    *:2)      verdict=FAULT ;;
    info:*)   verdict=INFO ;;
    *)        verdict=FINDING ;;
  esac
  case "$verdict" in
    PASS)    c_ok    "  ✓ clean"; echo "  (${secs}s)" ;;
    FINDING) c_bad   "  ✗ findings"; echo " (exit $rc, ${secs}s) — $log"; FINDINGS=$((FINDINGS+1)) ;;
    FAULT)   c_warn  "  ! INSTRUMENT FAULT"; echo " (${secs}s) — did NOT complete: $log"; FAULTED=$((FAULTED+1)) ;;
    INFO)    c_warn  "  · info"; echo " (exit $rc, ${secs}s) — $log" ;;
  esac
  printf '%s\t%s\t%s\t%ss\t%s\n' "$name" "$verdict" "$rc" "$secs" "${log#$ROOT/}" >> "$SUMMARY"
  # Show the tail of anything that was not clean — a log path alone gets ignored.
  [ "$verdict" = PASS ] || tail -12 "$log" | sed 's/^/      /'
  return 0
}

echo "══ verify-module: $MODULE ══  $STAMP"

# ── 0. Stack ────────────────────────────────────────────────────────────────
# First, and separately, because everything downstream reads as "the feature is broken" when it is
# actually "nothing was listening". test-stack-up --check also resolves and PUBLISHES the real port,
# so the runtime instruments below cannot be pointed at a guessed one.
STACK_OK=0
if [ -x "$BIN/test-stack-up.sh" ]; then
  run "stack (test-stack-up --check)" "$OUTDIR/00-stack.log" gate 60 -- \
    "$BIN/test-stack-up.sh" --check
  grep -q "^stack (test-stack-up --check)	PASS" "$SUMMARY" && STACK_OK=1
else
  fault "stack (test-stack-up --check)" "bin/test-stack-up.sh not installed" \
        "Without it the app port is a guess, so no runtime instrument below can be trusted."
fi

# ── 1. Model-side instruments (no app required) ─────────────────────────────
if [ -x "$BIN/conformance-check.sh" ]; then
  run "conformance (ledger claims vs live model)" "$OUTDIR/10-conformance.log" gate "${VM_TMO_CONFORMANCE:-1200}" -- \
    "$BIN/conformance-check.sh" --module "$MODULE"
else
  fault "conformance (ledger claims vs live model)" "bin/conformance-check.sh not installed"
fi

if [ -x "$BIN/graph-sweep.sh" ]; then
  run "graph sweep (orphans + wiring shape)" "$OUTDIR/11-graph.log" gate 300 -- \
    "$BIN/graph-sweep.sh" --module "$MODULE"
else
  fault "graph sweep (orphans + wiring shape)" "bin/graph-sweep.sh not installed"
fi

# Coverage needs a BRD and a ledger. If either is missing that is a FAULT and not a pass: "no
# requirements to check against" is precisely the hole that let several projects ship with no
# coverage ledger at all, so coverage-check.sh and the review agent had nothing to run and their
# absence read as silence.
LEDGER="${LEDGER_FILE:-$ROOT/architecture/modules/$MODULE/coverage-ledger.md}"
[ -f "$LEDGER" ] || LEDGER="$ROOT/architecture/coverage-ledger.md"
BRD="${BRD_FILE:-}"
if [ -z "$BRD" ]; then
  for pat in "$ROOT"/analysis/*/brd/*.brd.json "$ROOT"/analysis/*/knowledge-base/brd/*.brd.json; do
    [ -f "$pat" ] && { BRD="$pat"; break; }
  done
fi
# coverage-check.sh lives in the TOOLKIT's bin/, not in project-bin/, so a wired project does not
# automatically receive a copy. Look in the project first (a hardened local copy wins), then at the
# toolkit itself via $MXTK_ROOT. Faulting with "not installed" when the toolkit is sitting right
# there would be a fault we manufactured ourselves.
COVERAGE_CHECK="${COVERAGE_CHECK:-}"
if [ -z "$COVERAGE_CHECK" ]; then
  for c in "$BIN/coverage-check.sh" "${MXTK_ROOT:-}/bin/coverage-check.sh"; do
    [ -n "$c" ] && [ -x "$c" ] && { COVERAGE_CHECK="$c"; break; }
  done
fi
if [ -z "$COVERAGE_CHECK" ]; then
  fault "coverage (BRD leaves)" "coverage-check.sh not found" \
        "Looked in bin/ and \$MXTK_ROOT/bin. Set COVERAGE_CHECK=<path>, or copy the toolkit's bin/coverage-check.sh into the project."
elif [ -f "$LEDGER" ] && [ -n "$BRD" ]; then
  run "coverage (BRD leaves: UNCLAIMED/PHANTOM/DOUBLE)" "$OUTDIR/12-coverage.log" gate 300 -- \
    "$COVERAGE_CHECK" --summary "$BRD" "$LEDGER"
else
  fault "coverage (BRD leaves)" \
        "missing $( [ -f "$LEDGER" ] || echo 'coverage-ledger.md' )$( [ -n "$BRD" ] || echo ' BRD' ) for $MODULE" \
        "Requirement traceability for this module is UNMEASURED, not clean."
fi

# ── 1b. Review: the model-side instruments, as one report.json ──────────────
# INFO, not gate. The rungs above already gate on these same measurements; gating again would
# double-count one finding and make the summary read worse than the model is. What this rung adds is
# the ARTEFACT: a schema-conformant report.json carrying the wiring/orphan findings structurally and
# an explicit journey `fault`, so nobody can read a model-side pass as app-side evidence. run() still
# lands rc 2 in the FAULT bucket even for an info rung — a report that could not be written is a
# hole, not a formality.
#
# --reuse-conformance: conformance was measured at rung 1 (~9 min for a 22-row ledger). Measuring it
# a second time in the same pass buys nothing. The path is passed unconditionally: if rung 1 faulted
# the file is absent, review says so and FAULTS, which is the truth — nothing was measured — and it
# costs seconds instead of minutes.
if [ -x "$BIN/review-module.sh" ]; then
  run "review (model vs decided — report.json)" "$OUTDIR/13-review.log" info 600 -- \
    "$BIN/review-module.sh" "$MODULE" --json-only \
    --out "$OUTDIR/review-report.json" \
    --reuse-conformance "docs/conformance/report-$(date +%Y-%m-%d).tsv"
else
  fault "review (model vs decided — report.json)" "bin/review-module.sh not installed" \
        "No structured report.json for this module; the summary below is the only artefact."
fi

# ── 2. Runtime instruments (need the app) ───────────────────────────────────
JOURNEY_DIR="${JOURNEY_DIR:-$ROOT/journeys}"
JOURNEY_RUNNER="${JOURNEY_RUNNER:-$ROOT/tests/e2e/journey-runner.js}"
MONKEY_JS="${MONKEY_JS:-$ROOT/tests/e2e/monkey.js}"

if [ "$STACK_OK" -eq 0 ]; then
  fault "runtime instruments" "stack not up" \
        "Journeys and monkey did NOT run. This report covers the model only."
else
  JOURNEY="$JOURNEY_DIR/$MODULE.journey.json"
  if [ "$SKIP_JOURNEYS" -eq 1 ]; then
    printf '\n\033[1m── journeys\033[0m\n'; c_warn "  · skipped by flag"; echo ""
    printf 'journeys\tSKIPPED\t0\t-\t(--skip-journeys)\n' >> "$SUMMARY"
  elif [ ! -f "$JOURNEY_RUNNER" ]; then
    fault "journeys" "no journey runner at ${JOURNEY_RUNNER#$ROOT/}" \
          "Set JOURNEY_RUNNER, or see the journey-proof.md skill for the harness this expects."
  elif [ -f "$JOURNEY" ]; then
    run "journeys (UI + ordered spans + data effects)" "$OUTDIR/20-journeys.log" gate 900 -- \
      node "$JOURNEY_RUNNER" "$JOURNEY"
    # Non-vacuity: a journey that cannot fail is not evidence. Skipped under --quick because it
    # re-walks every step.
    [ "$QUICK" -eq 1 ] || run "journeys (positive control — MUST detect a broken precondition)" \
      "$OUTDIR/21-journeys-control.log" gate 900 -- \
      node "$JOURNEY_RUNNER" "$JOURNEY" --positive-control
  else
    fault "journeys" "no ${JOURNEY#$ROOT/}" \
          "The golden path for $MODULE is UNTESTED end-to-end. Page-stop specs, if any, check that pages render — not that the journey through them does what was specified."
  fi

  if [ "$SKIP_MONKEY" -eq 1 ]; then
    printf '\n\033[1m── monkey\033[0m\n'; c_warn "  · skipped by flag"; echo ""
    printf 'monkey\tSKIPPED\t0\t-\t(--skip-monkey)\n' >> "$SUMMARY"
  elif [ ! -f "$MONKEY_JS" ]; then
    # Absence is a FAULT; findings stay informational. Those are two different questions and the
    # two sources that own them each answer one:
    #   module-completion-loop.md — a monkey pass "skipped because happy-path was green" is NOT
    #     acceptable. Presence is required.
    #   this file, below — letting its findings gate the module "would give it an authority the
    #     measured yield does not support". Authority is not.
    # Recording absence as SKIPPED/rc 0 conflated them, and let a fresh project (where monkey.js is
    # simply not installed) reach a CLEAN verdict having never run a crash net at all.
    fault "monkey" "not installed at ${MONKEY_JS#$ROOT/}" \
          "Set MONKEY_JS, or see journey-proof.md for the harness this expects. Crash-on-input for $MODULE is UNMEASURED — its findings are informational, its absence is not."
  else
    # info, not gate: on one project the monkey pass scored 0 fail while its scripted journeys found
    # all 9 real defects. It is a crash net. Letting it gate the module would give it an authority
    # the measured yield does not support.
    run "monkey (crash net — informational)" "$OUTDIR/30-monkey.log" info 1800 -- \
      node "$MONKEY_JS" --rounds 24
  fi
fi

# ── 3. Verdict ──────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════"
column -t -s "$(printf '\t')" "$SUMMARY" 2>/dev/null | sed 's/^/  /' || cat "$SUMMARY"
echo "════════════════════════════════════════════════════════"
echo "  logs: ${OUTDIR#$ROOT/}"

if [ "$FAULTED" -gt 0 ]; then
  echo ""
  c_warn "  INCOMPLETE"; echo " — $FAULTED instrument(s) did not run, $FINDINGS with findings."
  echo "  This is NOT a pass with caveats. The unrun checks are absent, not green:"
  echo "  do not read this report as evidence that $MODULE is verified."
  exit 2
fi
if [ "$FINDINGS" -gt 0 ]; then
  echo ""; c_bad "  FINDINGS"; echo " — $FINDINGS instrument(s) reported. Every one that ran did so completely; the model/app disagreed with the claim."
  print_scope
  exit 1
fi
echo ""; c_ok "  CLEAN"; echo " — every instrument that ran found nothing."
print_scope
echo "  It is not a claim about anything unledgered, and it says nothing about UI/design"
echo "  quality — that instrument is not part of this chain."
exit 0
