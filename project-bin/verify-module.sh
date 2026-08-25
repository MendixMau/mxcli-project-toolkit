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
#   bin/verify-module.sh <Module> [--skip-monkey] [--skip-journeys] [--quick] [--parallel-runtime]
#
# The model-side instruments (conformance, graph sweep, coverage) always run in parallel — they
# share no state and touch no app. The runtime instruments (journeys, monkey) stay sequential by
# default because they log into the Mendix runtime, and a trial licence caps concurrent sessions:
# racing two logins can produce a spurious refusal that reads as a finding but isn't one (measured
# 2026-08-18, see tests/e2e/journey-runner.js). Pass --parallel-runtime to opt into running them
# concurrently anyway; results are then reported as caveated, never as clean.
#
# design-audit.js (the UI/a11y instrument, harness-architecture.md §6) is NOT in that
# --parallel-runtime bucket — it always runs sequentially, flag or not. journeys and monkey have a
# measured positive control for racing each other; design-audit has none, so it is not assumed
# safe. It also does not need the runtime up: it runs --static-only (model + CSS only, reduced
# evidenceStrength, recorded as such in its own artifact) whenever the app isn't fully verified up,
# and the full rendered pass only once test-stack-up has verified ownership.
#
# Optional inputs, discovered not assumed. Each missing one is a FAULT with a named reason, never a
# silent skip:
#   architecture/modules/<Module>/coverage-ledger.md   requirement traceability
#   analysis/*/brd/*.brd.json | analysis/*/knowledge-base/brd/*.brd.json   the BRD
#   journeys/<Module>.journey.json                     the golden-path walk
#   tests/e2e/journey-runner.js, tests/e2e/monkey.js   the runtime instruments
#   tests/e2e/design-audit.js   the UI/a11y instrument — rungs 6-7, SEPARATE from the journey
#                               (harness-architecture.md §6); informational, never gates a run
#   tests/e2e/report-normalize.js + report-render.js   the report surfaces — docs/report.json
#                               and docs/verification/report.html, composed by emit_report()
#                               (§2d) — which `trap emit_report EXIT` runs on EVERY exit
#                               path: normal end, early fault, nonexistent module, SIGINT
#                               alike (review-module.sh's pattern), so "aborted" is never
#                               indistinguishable from "never started". Non-gating: their
#                               failure never moves the exit code
# Override any of them: JOURNEY_DIR, JOURNEY_RUNNER, MONKEY_JS, DESIGN_AUDIT_JS, BRD_FILE,
# LEDGER_FILE, REPORT_NORMALIZE_JS, REPORT_RENDER_JS.
#
# Exit: 0 all instruments ran and found nothing · 1 findings · 2 an instrument could not run
#       (SIGINT/SIGTERM exit 2: instruments incomplete). The report is emitted on every exit
#       path, and nothing inside that emission can change the exit status the run earned.

set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
ROOT="$PROJECT_ROOT"
cd "$ROOT" || exit 2
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# _tool NAME — where does this helper script actually live?
#
# BIN above is the directory THIS script sits in, which is only the project's bin/
# when the script was copied into the project. Run the shared toolkit copy against a
# project instead and BIN is the toolkit's project-bin/ — so a helper the project has
# in its own bin/ is invisible, and the run reports "not installed" for a file that is
# right there. Measured on PROJECT-C 2026-08-19: coverage-check.sh and review-module.sh
# both existed in <project>/bin/ and both came back INSTRUMENT FAULT.
#
# Search order, most specific first:
#   1. <project>/bin  — the project's own, possibly tuned, copy wins
#   2. $BIN           — alongside this script (the installed-copy case)
#   3. $MXTK_ROOT/bin and $MXTK_ROOT/project-bin — the shared toolkit
# Echoes the first hit; echoes <project>/bin/NAME when there is none, so the caller's
# own "not found" message names the place a reader would look first.
_tool() {
  local n="$1" d
  for d in "$ROOT/bin" "$BIN" "${MXTK_ROOT:-}/bin" "${MXTK_ROOT:-}/project-bin"; do
    [ -n "$d" ] && [ -x "$d/$n" ] && { printf '%s\n' "$d/$n"; return 0; }
  done
  printf '%s\n' "$ROOT/bin/$n"
}

MODULE="${1:-}"
[ -n "$MODULE" ] && [ "${MODULE#--}" = "$MODULE" ] || {
  sed -n '2,59p' "$0"; exit 2; }
shift

SKIP_MONKEY=0; SKIP_JOURNEYS=0; QUICK=0; PARALLEL_RUNTIME=0
for a in "$@"; do
  case "$a" in
    --skip-monkey)      SKIP_MONKEY=1 ;;
    --skip-journeys)    SKIP_JOURNEYS=1 ;;
    --quick)            QUICK=1; SKIP_MONKEY=1 ;;
    --parallel-runtime) PARALLEL_RUNTIME=1 ;;
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

# Parallel-job bookkeeping for run_launch/run_join_all below. Indexed arrays only — no
# associative arrays — and always declared, even empty: macOS ships bash 3.2, and under
# `set -u`, expanding an array that was never declared at all (as opposed to declared empty)
# throws "unbound variable" on bash <4.4.
JOB_NAMES=(); JOB_LOGS=(); JOB_KINDS=(); JOB_TMOS=(); JOB_T0S=(); JOB_PIDS=()

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

# _report_result <name> <log> <kind> <tmo> <rc> <secs> — the verdict/print/SUMMARY logic shared
# by run() (sequential) and run_join_all() (parallel), so the two paths cannot drift apart.
_report_result() {
  local name="$1" log="$2" kind="$3" tmo="$4" rc="$5" secs="$6"
  [ "$rc" -eq 2 ] && [ "$secs" -ge "$tmo" ] && \
    echo "TIMED OUT after ${tmo}s — did not finish, so nothing was measured." >> "$log"
  local verdict
  # ORDER IS THE LOGIC HERE. `*:0)` used to come first, which made the two arms below it
  # unreachable for a clean exit: every rc=0 stamped PASS, and `kind=info` could never produce
  # INFO at all. Harmless while every instrument exited nonzero on failure -- and actively
  # dangerous once one didn't. design-audit.js returned 0 on an instrument fault, so a run that
  # resolved zero pages and measured nothing was written to summary.tsv as PASS, and from there
  # into coherence-cadence.sh and build-plan-status.sh. Observed on a real field run:
  # `mode=static-only pages=0 fault=2` reported as PASS. Fault is checked FIRST because "did not
  # run" must never be readable as "ran and was clean".
  case "$kind:$rc" in
    *:2)      verdict=FAULT ;;
    info:*)   verdict=INFO ;;
    *:0)      verdict=PASS ;;
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
}

# run <name> <logfile> <kind> <timeout_s> -- <cmd...>
#   kind=gate   exit 1 => finding, exit 2 => instrument fault
#   kind=info   never fails the pass; recorded for the trend line
# Blocks until the instrument finishes.
run() {
  local name="$1" log="$2" kind="$3" tmo="$4"; shift 5   # the literal --
  printf '\n\033[1m── %s\033[0m  \033[2m(budget %ss)\033[0m\n' "$name" "$tmo"
  local t0; t0=$(date +%s)
  with_timeout "$tmo" "$@" > "$log" 2>&1
  local rc=$?
  local secs=$(( $(date +%s) - t0 ))
  _report_result "$name" "$log" "$kind" "$tmo" "$rc" "$secs"
  return 0
}

# run_launch <name> <logfile> <kind> <timeout_s> -- <cmd...>
# Same contract as run(), but starts the instrument in the background and returns immediately.
# Call run_join_all afterward to wait for every launched job and report it — in launch order, not
# completion order, so the summary stays deterministic across runs.
run_launch() {
  local name="$1" log="$2" kind="$3" tmo="$4"; shift 5   # the literal --
  printf '\n\033[1m▶ %s\033[0m  \033[2m(budget %ss, running in parallel)\033[0m\n' "$name" "$tmo"
  local t0; t0=$(date +%s)
  ( with_timeout "$tmo" "$@" > "$log" 2>&1 ) &
  local n=${#JOB_PIDS[@]}
  JOB_NAMES[$n]="$name"; JOB_LOGS[$n]="$log"; JOB_KINDS[$n]="$kind"
  JOB_TMOS[$n]="$tmo";   JOB_T0S[$n]="$t0";   JOB_PIDS[$n]=$!
}

# run_join_all — wait for every run_launch()ed job and report each one. No-op if nothing was
# launched. The `[ ... ] || return 0` guard is load-bearing, not decorative: it is what keeps the
# `${JOB_PIDS[@]}`-style expansions below from ever running against an empty array under `set -u`.
run_join_all() {
  [ "${#JOB_PIDS[@]}" -gt 0 ] || return 0
  local i rc secs
  for i in "${!JOB_PIDS[@]}"; do
    wait "${JOB_PIDS[$i]}"; rc=$?
    secs=$(( $(date +%s) - JOB_T0S[$i] ))
    printf '\n\033[1m── %s\033[0m  \033[2m(result)\033[0m\n' "${JOB_NAMES[$i]}"
    _report_result "${JOB_NAMES[$i]}" "${JOB_LOGS[$i]}" "${JOB_KINDS[$i]}" "${JOB_TMOS[$i]}" "$rc" "$secs"
  done
  JOB_NAMES=(); JOB_LOGS=(); JOB_KINDS=(); JOB_TMOS=(); JOB_T0S=(); JOB_PIDS=()
}

# _exec — dispatch a runtime instrument to run() or run_launch(), gated by --parallel-runtime.
# One call site so every runtime instrument obeys the same flag without repeating the if/else.
_exec() {
  if [ "$PARALLEL_RUNTIME" -eq 1 ]; then run_launch "$@"; else run "$@"; fi
}

# ── Report emission — on EVERY exit path (harness-architecture.md §5 improvement 1) ─────────
# This is §2d's body, lifted into a function so `trap emit_report EXIT` can run it on the
# paths the old end-of-script placement missed: SIGINT nine minutes into conformance, a
# `set -u` death, any early exit. review-module.sh's pattern, mirrored deliberately. The
# normal path calls it explicitly at the §2d position (so the summary table and the final
# "report:" lines keep their order); the guard makes the trap's second call a no-op.
#
# NON-GATING BY CONSTRUCTION, one step past the design-audit rung: not even its FAULTS gate.
# This step renders the evidence, it does not add any — a module whose instruments all passed
# must not read INCOMPLETE because the renderer hiccupped, and a broken report pipeline is
# report-normalize's own selftest's problem, not this module's. So the rungs run through
# run()/_report_result() as usual (the summary rows and 50-/51- logs stay honest), and the
# FAULTED/FINDINGS counters are restored afterwards so the exit code belongs to the
# instruments alone. On the trap path the exit status is decided before the trap runs — the
# restore is kept anyway for the normal-path call, which happens BEFORE the verdict.
#
# NOTHING IN HERE MAY CALL `exit`. An EXIT trap preserves the script's real exit status
# unless the trap body exits — that is the classic trap bug, and it would let a renderer
# failure overwrite a verdict the instruments earned. prior_rc is captured first (before any
# command in the body can clobber $?) and used only for the honest trap-path message.
RENDER_OK=0
REPORT_EMITTED=0
emit_report() {
  local prior_rc=$?
  local mode="${1:-trap}"
  [ "$REPORT_EMITTED" -eq 0 ] || return 0
  REPORT_EMITTED=1
  local pre_faulted=$FAULTED pre_findings=$FINDINGS
  local norm="${REPORT_NORMALIZE_JS:-$ROOT/tests/e2e/report-normalize.js}"
  local rend="${REPORT_RENDER_JS:-$ROOT/tests/e2e/report-render.js}"
  if [ ! -f "$SUMMARY" ]; then
    # Very-early death: not even the summary exists. There is nothing to normalize and no
    # fault() row to write it into — emit what can be emitted (nothing) and say so, once.
    echo "" >&2
    echo "  report: NOT PRODUCED — this run ended before any instrument wrote to the summary," >&2
    echo "          so there is nothing to normalize. Aborted before start, not clean." >&2
    return 0
  fi
  if [ ! -f "$norm" ] || [ ! -f "$rend" ]; then
    fault "report (normalize + render)" \
          "engine not installed at ${norm#$ROOT/} / ${rend#$ROOT/}" \
          "docs/report.json and docs/verification/report.html were NOT (re)generated. Run bin/sync-project.sh to install the tests/e2e engine, or set REPORT_NORMALIZE_JS / REPORT_RENDER_JS."
  else
    run "report (normalize → docs/report.json)" "$OUTDIR/50-report-normalize.log" info 300 -- \
      node "$norm" --out docs/report.json
    if [ -s "$ROOT/docs/report.json" ]; then
      run "report (render → docs/verification/report.html)" "$OUTDIR/51-report-render.log" info 300 -- \
        node "$rend" --in docs/report.json --out docs/verification/report.html
      [ -s "$ROOT/docs/verification/report.html" ] && RENDER_OK=1
    else
      fault "report (render → docs/verification/report.html)" \
            "normalize wrote no docs/report.json — nothing to render" \
            "See ${OUTDIR#$ROOT/}/50-report-normalize.log for why."
    fi
  fi
  # Restore the counters: the rows above stay in the summary (visible, named), the exit code
  # does not move on their account. See the NON-GATING note at the head of this function.
  FAULTED=$pre_faulted; FINDINGS=$pre_findings
  if [ "$mode" = "trap" ]; then
    # Abnormal end: §3 never runs, so its "report:" lines are printed here — an aborted run
    # must still say where its report landed, or "aborted" reads as "never started".
    echo ""
    if [ "$RENDER_OK" -eq 1 ]; then
      echo "  report: docs/verification/report.html (the human surface) · docs/report.json (machine)"
      echo "          Emitted by the EXIT trap after an early exit (status $prior_rc): it reflects"
      echo "          what the instruments had written when the run ended, NOT a completed pass."
    else
      echo "  report: NOT PRODUCED this run — see the report rows above; the exit status"
      echo "          ($prior_rc) is unaffected (the report renders evidence, it does not add any)."
    fi
  fi
  return 0
}
# The traps write to the SCRIPT's stdout/stderr, pinned here on fds 3/4 — not to whatever
# happens to be redirected when the signal lands. A trap that fires mid-instrument executes
# while run()'s `> "$log" 2>&1` redirection is active, so without this the INTERRUPTED
# message and the whole report emission vanish into the interrupted instrument's log file
# (measured 2026-08-22: SIGINT during the stack rung put all of it in 00-stack.log).
exec 3>&1 4>&2
trap 'emit_report trap 1>&3 2>&4' EXIT
# An interrupted run is still a run that happened, and it must still leave a report saying
# how far it got. Without this, Ctrl-C on the 9-minute conformance rung leaves nothing on
# disk and the next reader cannot tell an aborted verify from a verify nobody started.
# exit 2 is honest — instruments incomplete — and it lands in the EXIT trap above.
trap '{ echo ""; c_warn "  ! INTERRUPTED"; echo " — emitting the partial report"; } 1>&3 2>&4; exit 2' INT TERM

echo "══ verify-module: $MODULE ══  $STAMP"

# ── 0. Stack ────────────────────────────────────────────────────────────────
# First, and separately, because everything downstream reads as "the feature is broken" when it is
# actually "nothing was listening". test-stack-up --check also resolves and PUBLISHES the real port,
# so the runtime instruments below cannot be pointed at a guessed one.
STACK_OK=0
if [ -x "$(_tool test-stack-up.sh)" ]; then
  run "stack (test-stack-up --check)" "$OUTDIR/00-stack.log" gate 60 -- \
    "$(_tool test-stack-up.sh)" --check
  grep -q "^stack (test-stack-up --check)	PASS" "$SUMMARY" && STACK_OK=1
  # "app up with a caveat" is not "app down", and reporting it as one sends the reader
  # to debug a stack that is running fine. test-stack-up exits 1 for BOTH "nothing is
  # listening" and "the app is serving but something around it is wrong" (on 2026-08-19:
  # the Dockerised app could not reach the host mock). Split them: STACK_UP is about
  # whether anything answers, STACK_WHY carries the real reason downstream.
  STACK_UP=0; STACK_WHY=""
  if grep -q "App serving on" "$OUTDIR/00-stack.log" 2>/dev/null; then
    STACK_UP=1
    # Match on CONTENT, not on the leading marker: the log is coloured, so the "!" is
    # preceded by an ANSI escape and "^\s*!" never matches. Strip escapes, then filter.
    STACK_WHY=$(sed $'s/\033\[[0-9;]*m//g' "$OUTDIR/00-stack.log" 2>/dev/null \
                | grep -E "CANNOT|INVALID|not serving|→" | head -4 \
                | sed 's/^[[:space:]]*/      /')
  fi
else
  fault "stack (test-stack-up --check)" "bin/test-stack-up.sh not installed" \
        "Without it the app port is a guess, so no runtime instrument below can be trusted."
fi

# ── 1. Model-side instruments (no app required) ─────────────────────────────
# These three share no state and touch no app, so they always run in parallel — unlike the
# runtime instruments in §2 there is nothing here to race on and no login session to spend, so
# this needs no opt-in flag.
if [ -x "$(_tool conformance-check.sh)" ]; then
  run_launch "conformance (ledger claims vs live model)" "$OUTDIR/10-conformance.log" gate "${VM_TMO_CONFORMANCE:-1200}" -- \
    "$(_tool conformance-check.sh)" --module "$MODULE"
else
  fault "conformance (ledger claims vs live model)" "bin/conformance-check.sh not installed"
fi

if [ -x "$(_tool graph-sweep.sh)" ]; then
  run_launch "graph sweep (orphans + wiring shape)" "$OUTDIR/11-graph.log" gate 300 -- \
    "$(_tool graph-sweep.sh)" --module "$MODULE"
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
  for c in "$(_tool coverage-check.sh)" "${MXTK_ROOT:-}/bin/coverage-check.sh"; do
    [ -n "$c" ] && [ -x "$c" ] && { COVERAGE_CHECK="$c"; break; }
  done
fi
if [ -z "$COVERAGE_CHECK" ]; then
  fault "coverage (BRD leaves)" "coverage-check.sh not found" \
        "Looked in bin/ and \$MXTK_ROOT/bin. Set COVERAGE_CHECK=<path>, or copy the toolkit's bin/coverage-check.sh into the project."
else
  # Route through coverage-preflight.sh, which GRADES what is present instead of demanding the
  # ideal artefact. The old form here was `elif [ -f "$LEDGER" ] && [ -n "$BRD" ]` with a blanket
  # FAULT otherwise — which meant the four fallback levels added 2026-08-20 were unreachable from
  # the one command every module review runs, i.e. built and never invoked. That is the same
  # failure as report-normalize.js never being called from this script (improvement-plan Finding 2),
  # and it would have shipped the whole grading layer dead on arrival.
  #
  # The preflight resolves the ledger (all three path shapes) and the BRD itself, so the $LEDGER /
  # $BRD guesses above are passed only as hints. Its exit codes: 0/1 measured (levels 1-2, the
  # engine's own verdict), 3 NOT MEASURED (BRDs but no `claims` — an honest denominator plus the
  # named remedy), 4 NOT APPLICABLE (no BRD at all — nothing produced a spec for this module).
  # 3 and 4 are not passes and not faults; they are graded absences, and the rung says which.
  PREFLIGHT="$(_tool coverage-preflight.sh)"
  if [ -n "$PREFLIGHT" ] && [ -x "$PREFLIGHT" ]; then
    run_launch "coverage (BRD leaves: UNCLAIMED/PHANTOM/DOUBLE)" "$OUTDIR/12-coverage.log" gate 300 -- \
      "$PREFLIGHT" --summary ${MODULE:+--module "$MODULE"}
  elif [ -f "$LEDGER" ] && [ -n "$BRD" ]; then
    # Preflight absent (an older wired project that has not synced). Fall back to the engine
    # directly — level 1 only, which is what this rung did before the grading layer existed.
    run_launch "coverage (BRD leaves: UNCLAIMED/PHANTOM/DOUBLE)" "$OUTDIR/12-coverage.log" gate 300 -- \
      "$COVERAGE_CHECK" --summary "$BRD" "$LEDGER"
  else
    fault "coverage (BRD leaves)" \
          "coverage-preflight.sh not installed, and no ledger+BRD to measure directly" \
          "Requirement traceability for this module is UNMEASURED, not clean. Run bin/sync-project.sh to install coverage-preflight.sh, which grades what IS present instead of requiring a ledger."
  fi
fi

echo ""
echo "  waiting on model-side instrument(s)..."
run_join_all

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
if [ -x "$(_tool review-module.sh)" ]; then
  run "review (model vs decided — report.json)" "$OUTDIR/13-review.log" info 600 -- \
    "$(_tool review-module.sh)" "$MODULE" --json-only \
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

if [ "$STACK_OK" -eq 0 ] && [ "${STACK_UP:-0}" -eq 0 ]; then
  fault "runtime instruments" "app not serving" \
        "Journeys and monkey did NOT run. This report covers the model only."
elif [ "$STACK_OK" -eq 0 ] && [ "${ALLOW_CAVEATED_STACK:-0}" -ne 1 ]; then
  # The app IS up. Something around it is not, and running anyway would manufacture
  # findings: a journey whose REST feed is unreachable renders an empty grid and captures
  # zero spans, which reads as "the feature is broken" when nothing about the feature was
  # exercised. That false red costs more than the missing run, so it stays blocked — but
  # with the actual reason, not "stack not up".
  fault "runtime instruments" "app is up, but the stack has findings — running now would produce false failures" \
        "$(printf '%s\n' "${STACK_WHY:-      see 00-stack.log}" \
           "      Journeys and monkey did NOT run." \
           "      If this module does not depend on the above, re-run with ALLOW_CAVEATED_STACK=1;" \
           "      results are then reported as caveated, never as clean.")"
else
  if [ "$PARALLEL_RUNTIME" -eq 1 ]; then
    c_warn "  ! PARALLEL RUNTIME"; echo " — journeys/monkey below run concurrently (--parallel-runtime)."
    echo "      A Mendix trial licence caps concurrent sessions: two logins racing on the same"
    echo "      runtime can produce a spurious login refusal (INVALID, not a real FAIL) that has"
    echo "      nothing to do with $MODULE's correctness (measured 2026-08-18, see journey-runner.js)."
    echo "      Results below are reported as caveated, never as clean — if anything reads INVALID,"
    echo "      re-run with the flag omitted before trusting the result."
  fi

  JOURNEY="$JOURNEY_DIR/$MODULE.journey.json"
  if [ "$SKIP_JOURNEYS" -eq 1 ]; then
    printf '\n\033[1m── journeys\033[0m\n'; c_warn "  · skipped by flag"; echo ""
    printf 'journeys\tSKIPPED\t0\t-\t(--skip-journeys)\n' >> "$SUMMARY"
  elif [ ! -f "$JOURNEY_RUNNER" ]; then
    fault "journeys" "no journey runner at ${JOURNEY_RUNNER#$ROOT/}" \
          "Set JOURNEY_RUNNER, or see the journey-proof.md skill for the harness this expects."
  elif [ -f "$JOURNEY" ]; then
    _exec "journeys (UI + ordered spans + data effects)" "$OUTDIR/20-journeys.log" gate 900 -- \
      node "$JOURNEY_RUNNER" "$JOURNEY"
    # Non-vacuity: a journey that cannot fail is not evidence. Skipped under --quick because it
    # re-walks every step.
    [ "$QUICK" -eq 1 ] || _exec "journeys (positive control — MUST detect a broken precondition)" \
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
    #   module-review.md — a monkey pass "skipped because happy-path was green" is NOT
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
    _exec "monkey (crash net — informational)" "$OUTDIR/30-monkey.log" info 1800 -- \
      node "$MONKEY_JS" --rounds 24
  fi

  if [ "$PARALLEL_RUNTIME" -eq 1 ]; then
    echo ""
    echo "  waiting on parallel runtime instrument(s)..."
    run_join_all
  fi
fi

# ── 2b. Design audit — a SEPARATE instrument, not a sixth/seventh journey rung ──────────────
# harness-architecture.md §6: design-audit.js's rungs 6/7 compose with the journey and the crash
# net but never gate a run and must never be merged into the 1-5 rung numbering — they pass their
# own positive control but have not yet gone red on real work a human then confirmed was a real
# defect. So kind=info unconditionally below, same trichotomy as everything else (fault/finding/
# pass), just never the thing that turns FAULTED/FINDINGS nonzero on its own findings.
#
# Placed outside the runtime-instruments if/elif/else above on purpose: unlike journeys/monkey it
# does not need the app up at all. --static-only reads the model + CSS only ("the running app was
# not contacted" — design-audit.js) and is explicitly weaker evidence (evidenceStrength:
# static-model+css vs static-model+css+rendered, recorded IN its own artifact, never silently
# upgraded to look like a full run). So it still runs — at reduced strength — when the stack is
# down or only caveated-up; the full rendered pass runs only once test-stack-up has verified
# OWNERSHIP (STACK_OK=1), the same bar journeys/monkey require before trusting what they measure.
DESIGN_AUDIT_JS="${DESIGN_AUDIT_JS:-$ROOT/tests/e2e/design-audit.js}"
if [ ! -f "$DESIGN_AUDIT_JS" ]; then
  fault "design audit (rungs 6-7 — UI/a11y, informational)" "not installed at ${DESIGN_AUDIT_JS#$ROOT/}" \
        "Set DESIGN_AUDIT_JS, or see harness-architecture.md §6 for the instrument this expects. UI/a11y quality for $MODULE is UNMEASURED — it never gates a run even when present."
elif [ "${STACK_OK:-0}" -eq 1 ]; then
  run "design audit (rungs 6-7 — UI/a11y, informational)" "$OUTDIR/40-design-audit.log" info 900 -- \
    node "$DESIGN_AUDIT_JS"
else
  run "design audit (rungs 6-7 — UI/a11y, static-only — REDUCED EVIDENCE)" "$OUTDIR/40-design-audit.log" info 300 -- \
    node "$DESIGN_AUDIT_JS" --static-only
fi

# ── 2c. The LOOK is not in this chain, and must say so ──────────────────────
# module-review.md stage 4 — every page in the module assessed against wireframe, design system
# or the unaided rubric — is a judgement pass. It is performed by review-agent, never by this
# script, and it will never be performed by this script: a shell script cannot look at a page.
#
# But a report that simply omits it renders green. Absence is not green (report-schema.md rule 5),
# and the escaped defects an end-to-end run misses are overwhelmingly the ones only a person
# looking at the screen would have caught. So the row is emitted UNCONDITIONALLY, on every branch,
# and lands in print_scope's "NOT MEASURED" bucket where a reader cannot mistake it for coverage.
#
# SKIPPED, not FAULT, deliberately: FAULT increments FAULTED and turns every clean verify run into
# exit 2, which would make the honest row unusable and get it deleted within a week. The row's job
# is to be visible, not to gate. What gates it is gate-check.sh, which requires a ui-review-*.html
# per closed module.
printf 'look (module-review.md §4)\tSKIPPED\t0\t-\t(judgement pass — not performed by this chain; review-agent owns it)\n' >> "$SUMMARY"

# ── 2d. Report surface — normalize + render (closes improvement-plan Finding 2) ─────────────
# Every instrument above writes its own artifact; emit_report() composes them into the two
# report surfaces: docs/report.json (report-normalize.js — the machine half, versioned schema)
# and docs/verification/report.html (report-render.js — the human surface check_stage_6
# accepts). Until this rung existed, report-normalize.js was invoked by no orchestrator at all
# (harness-architecture.md §5), so the richest artifact in the harness was unreachable from
# the harness's one command and nothing anywhere produced Stage 6's test surface.
#
# The body lives in emit_report() above — installed as the EXIT trap, so an interrupted or
# early-faulted run still emits (harness-architecture.md §5 improvement 1, closed 2026-08-22).
# This explicit call is the normal-path invocation, at the same position §2d always ran;
# the guard inside makes the trap's later call a no-op, so the step runs exactly once.
emit_report normal

# ── 3. Verdict ──────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════"
column -t -s "$(printf '\t')" "$SUMMARY" 2>/dev/null | sed 's/^/  /' || cat "$SUMMARY"
echo "════════════════════════════════════════════════════════"
echo "  logs: ${OUTDIR#$ROOT/}"
if [ "$RENDER_OK" -eq 1 ]; then
  echo "  report: docs/verification/report.html (the human surface) · docs/report.json (machine)"
else
  echo "  report: NOT PRODUCED this run — see the report rows above; the verdict below is"
  echo "          unaffected (the report renders evidence, it does not add any)."
fi

if [ "$FAULTED" -gt 0 ]; then
  echo ""
  c_warn "  INCOMPLETE"; echo " — $FAULTED instrument(s) did not run, $FINDINGS with findings."
  echo "  This is NOT a pass with caveats. The unrun checks are absent, not green:"
  echo "  do not read this report as evidence that $MODULE is verified."
  print_scope
  exit 2
fi
if [ "$FINDINGS" -gt 0 ]; then
  echo ""; c_bad "  FINDINGS"; echo " — $FINDINGS instrument(s) reported. Every one that ran did so completely; the model/app disagreed with the claim."
  print_scope
  exit 1
fi
echo ""; c_ok "  CLEAN"; echo " — every instrument that ran found nothing."
print_scope
echo "  It is not a claim about anything unledgered. UI/design quality is listed above as"
echo "  NOT MEASURED and stays that way until module-review.md §4 has been performed."
exit 0
