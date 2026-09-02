#!/usr/bin/env bash
# review-module.sh — the review-agent's instruments, as one standalone command.
#
# WHY THIS EXISTS, AND WHY IT IS NOT coverage-check AND NOT A JOURNEY
# Three instruments answer three different questions and collapsing any two of them
# produces a report that reads green over an unmeasured hole:
#
#   coverage-check.sh   Does the requirement EXIST and is it CLAIMED?   (BRD leaves vs ledger)
#   review  (this)      Does the MODEL match what was DECIDED?          (ledger claim vs live model)
#   journey-proof       Does the RUNNING APP do what was decided?       (needs the app up)
#
# Review exists because it catches behaviourally-equivalent-but-architecturally-wrong
# drift — a module imported but never wired in, a ledger row whose claimed status has
# quietly stopped matching the model. mxbuild cannot see that (it compiles), and an e2e
# run cannot see it either (it behaves identically). Neither can tell you the thing that
# was built is not the thing that was decided.
#
# THE APP IS NOT NEEDED AND MUST NOT BE ASSUMED. Every instrument here reads the .mpr,
# the catalog database and the ledger. That is the point: this is a model question.
#
# DIAGNOSTIC ONLY. Read-only mxcli (SHOW/DESCRIBE) via conformance-check, SQL over
# .mxcli/catalog.db via graph-sweep. No `mxcli exec`, no MDL, no writes to the .mpr.
# (`mxcli test` and `docker check` DO write to the model and are deliberately absent.)
#
# THE REPORT IS EMITTED UNCONDITIONALLY — including on a fully faulted run, including
# when the module does not exist. A run that produced no report is indistinguishable
# from a run that never happened, and "the verification stage blocked at step 0 and
# produced nothing" is the exact failure this harness was built to retire.
#
# Precisely, `trap emit_report EXIT` guarantees a report on all of:
#   · the clean path, the findings path and the faulted path
#   · the module-does-not-exist early exit (instruments.tsv already has its fault rows)
#   · SIGINT / SIGTERM, via the INT/TERM trap that exits 2 into the EXIT trap
#   · any `set -u` unbound-variable death after the trap is installed
# The one thing it cannot cover is a failure BEFORE the trap is installed — the two
# `mkdir -p ... || exit 2` lines. Those exit 2 with a message and no report, which is
# correct: there is nowhere to write one.
#
# And if emitting itself fails, the run exits 2. A report that could not be written is an
# instrument fault like any other; letting the verdict stand at 0 would hand a caller a
# pass whose evidence does not exist.
#
# The standalone report contains ONLY the model-side instruments. Journey rows are
# present and are `fault` — "no journey run in this invocation" — never absent and never
# pass. Absent renders as green; that is schema rule 5.
#
# Usage:
#   bin/review-module.sh <Module> [--json-only] [--out <path>] [--reuse-conformance <tsv>]
#
# --reuse-conformance exists for one caller: bin/verify-module.sh, which has just run
# conformance itself. Re-running it there would add ~9 minutes to measure the same thing
# twice. The reused TSV must exist and must carry rows for this module — a reuse that
# finds nothing is a FAULT, never a silent skip, or the report inherits the exact false
# green it was built to prevent.
#
# Exit: 0 every instrument ran and found nothing · 1 findings · 2 an instrument could not run
#
# Note on the exit code: the journey `fault` carried in the report is a property of the
# REPORT (it must not imply journey coverage it does not have), not of this script's
# instrument set. It is stated in the output and deliberately not counted in the verdict.

set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
ROOT="$PROJECT_ROOT"
cd "$ROOT" || exit 2
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MPR="$(find_mpr)" || exit 2

# _tool NAME — where does this helper script actually live?  (same contract as
# verify-module.sh; kept identical on purpose.) BIN is the directory THIS script
# sits in, which is the project's bin/ only when the script was copied in. Run the
# shared toolkit copy against a project instead and BIN is the toolkit's
# project-bin/, so a helper the project keeps in its own bin/ is invisible and the
# run reports "not reachable" for a file that is right there.
#   1. <project>/bin  — the project's own, possibly tuned, copy wins
#   2. $BIN           — alongside this script (the installed-copy case)
#   3. $MXTK_ROOT/bin and $MXTK_ROOT/project-bin — the shared toolkit
# Echoes the first hit; echoes <project>/bin/NAME when there is none, so the
# caller's own "not found" message names the place a reader would look first.
_tool() {
  local n="$1" d
  for d in "$ROOT/bin" "$BIN" "${MXTK_ROOT:-}/bin" "${MXTK_ROOT:-}/project-bin"; do
    [ -n "$d" ] && [ -x "$d/$n" ] && { printf '%s\n' "$d/$n"; return 0; }
  done
  printf '%s\n' "$ROOT/bin/$n"
}

MODULE=""
JSON_ONLY=0
OUT=""
REUSE_CONF=""

# The help text IS the header block, read out of this file rather than duplicated below it —
# a hardcoded line range silently truncates the moment the header grows, which is how -h
# stops mentioning the flag you just added.
usage() { awk 'NR>1 && /^#/ { sub(/^# ?/, ""); print; next } NR>1 { exit }' "$0"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --json-only) JSON_ONLY=1; shift ;;
    --out)       OUT="${2:-}"; [ -n "$OUT" ] || { echo "--out needs a value" >&2; exit 2; }; shift 2 ;;
    --reuse-conformance) REUSE_CONF="${2:-}"
                 [ -n "$REUSE_CONF" ] || { echo "--reuse-conformance needs a value" >&2; exit 2; }; shift 2 ;;
    -h|--help)   usage; exit 0 ;;
    --*)         echo "unknown argument: $1" >&2; exit 2 ;;
    *)           [ -z "$MODULE" ] || { echo "only one module may be named (got '$MODULE' and '$1')" >&2; exit 2; }
                 MODULE="$1"; shift ;;
  esac
done

[ -n "$MODULE" ] || { usage; exit 2; }

OUTDIR="$ROOT/.claude/loop/review/$MODULE"
mkdir -p "$OUTDIR" || exit 2
[ -n "$OUT" ] || OUT="$OUTDIR/report.json"
case "$OUT" in /*) ;; *) OUT="$ROOT/$OUT" ;; esac
HTML="${OUT%.json}.html"
mkdir -p "$(dirname "$OUT")" || exit 2

STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
SUMMARY="$OUTDIR/summary.tsv"
INSTR="$OUTDIR/instruments.tsv"
printf 'instrument\tverdict\trc\telapsed\tlog\n' > "$SUMMARY"
: > "$INSTR"
# mtime marker: anything in docs/conformance/ older than this belongs to a previous run and
# must not be read as this run's measurement. A timestamp string cannot do this job — the
# report filenames carry only a date, so two runs on one day are indistinguishable by name.
: > "$OUTDIR/.started"
rm -f "$OUTDIR/conformance.tsv" "$OUTDIR/graph.tsv" "$OUTDIR/coverage.txt"

c_ok()   { printf '\033[32m%s\033[0m' "$1"; }
c_bad()  { printf '\033[31m%s\033[0m' "$1"; }
c_warn() { printf '\033[33m%s\033[0m' "$1"; }

FINDINGS=0
FAULTED=0

# Portable timeout — macOS ships no `timeout(1)` and `gtimeout` is not a safe assumption.
# A timeout is a FAULT, never a FAIL: "the instrument did not finish" and "the feature is
# broken" send you to different places, and collapsing them costs a day.
with_timeout() {
  local secs="$1"; shift
  "$@" & local child=$!
  ( sleep "$secs"; kill -9 "$child" 2>/dev/null ) & local watchdog=$!
  wait "$child" 2>/dev/null; local rc=$?
  kill "$watchdog" 2>/dev/null; wait "$watchdog" 2>/dev/null
  [ "$rc" -eq 137 ] && return 2   # SIGKILL from the watchdog -> FAULT bucket
  return "$rc"
}

# note_instrument <name> <verdict> <rc> <elapsed> <log> <reason>
note_instrument() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" >> "$INSTR"
}

# fault_instrument <display> <name> <reason> [extra lines...]
# A missing input is a FAULT with a row that says so, never silence.
fault_instrument() {
  local display="$1" name="$2" reason="$3"; shift 3
  printf '\n\033[1m── %s\033[0m\n' "$display"
  c_warn "  ! INSTRUMENT FAULT"; echo " — $reason"
  for l in "$@"; do echo "      $l"; done
  printf '%s\tFAULT\t2\t-\t(%s)\n' "$display" "$reason" >> "$SUMMARY"
  note_instrument "$name" fault 2 "" "" "$reason"
  FAULTED=$((FAULTED+1))
}

# run <display> <name> <logfile> <kind> <timeout_s> -- <cmd...>
#   kind=gate   exit 1 => finding, exit 2 => instrument fault
#   kind=info   never fails the pass; recorded for the trend line
run() {
  local display="$1" name="$2" log="$3" kind="$4" tmo="$5"; shift 6   # the literal --
  printf '\n\033[1m── %s\033[0m  \033[2m(budget %ss)\033[0m\n' "$display" "$tmo"
  local t0; t0=$(date +%s)
  with_timeout "$tmo" "$@" > "$log" 2>&1
  local rc=$?
  local secs=$(( $(date +%s) - t0 ))
  local reason=""
  if [ "$rc" -eq 2 ] && [ "$secs" -ge "$tmo" ]; then
    echo "TIMED OUT after ${tmo}s — did not finish, so nothing was measured." >> "$log"
    reason="timed out after ${tmo}s — nothing was measured"
  fi
  local verdict
  # shellcheck disable=SC2034  # read by callers that must branch on how the rung went
  case "$kind:$rc" in
    *:0)    verdict=PASS ;;
    *:2)    verdict=FAULT ;;
    info:*) verdict=INFO ;;
    *)      verdict=FINDING ;;
  esac
  case "$verdict" in
    PASS)    c_ok   "  ✓ clean";            echo "  (${secs}s)" ;;
    FINDING) c_bad  "  ✗ findings";         echo " (exit $rc, ${secs}s) — $log"; FINDINGS=$((FINDINGS+1)) ;;
    FAULT)   c_warn "  ! INSTRUMENT FAULT"; echo " (${secs}s) — did NOT complete: $log"; FAULTED=$((FAULTED+1)) ;;
    INFO)    c_warn "  · info";             echo " (exit $rc, ${secs}s) — $log" ;;
  esac
  printf '%s\t%s\t%s\t%ss\t%s\n' "$display" "$verdict" "$rc" "$secs" "${log#$ROOT/}" >> "$SUMMARY"
  case "$verdict" in
    PASS)    note_instrument "$name" pass    "$rc" "$secs" "${log#$ROOT/}" "" ;;
    FINDING) note_instrument "$name" pass    "$rc" "$secs" "${log#$ROOT/}" "" ;;  # liveness: it RAN
    FAULT)   note_instrument "$name" fault   "$rc" "$secs" "${log#$ROOT/}" "${reason:-exited 2 — see log}" ;;
    INFO)    note_instrument "$name" manual  "$rc" "$secs" "${log#$ROOT/}" "informational — a human still owes a verdict" ;;
  esac
  # A log path alone gets ignored; show the tail of anything that was not clean.
  [ "$verdict" = PASS ] || tail -12 "$log" | sed 's/^/      /'
  LAST_VERDICT="$verdict"
  return 0
}
LAST_VERDICT=""

# ── The report is emitted on EVERY exit path, including the early fault ones. ──
EMITTED=0
emit_report() {
  local rc=$?
  [ "$EMITTED" -eq 0 ] || return 0
  EMITTED=1
  if ! node "$ROOT/tests/e2e/review-report.js" \
        --dir "$OUTDIR" --module "$MODULE" --out "$OUT" --root "$ROOT" \
        --stamp "$STAMP" --finished "$(date -u +%Y-%m-%dT%H:%M:%SZ)"; then
    # Exit 2, not $rc. Previously this returned 0 and the ORIGINAL verdict stood: a clean
    # module printed "CLEAN" and exited 0 with no report.json on disk, so a caller keying
    # on $? saw a pass whose evidence did not exist. Verified 2026-08-18 by putting a
    # failing `node` on PATH: exit code unchanged, no report written.
    echo "" >&2
    c_warn "  ! INSTRUMENT FAULT" >&2
    echo " — could not emit ${OUT#$ROOT/} (review-report.js failed)" >&2
    echo "      The instruments above may have run, but this run produced no report, so" >&2
    echo "      there is nothing for anyone to read. Exiting 2 rather than standing by the" >&2
    echo "      verdict: an unrecorded result is not a result." >&2
    exit 2
  fi
  echo ""
  echo "  report  ${OUT#$ROOT/}"
  if [ "$JSON_ONLY" -eq 0 ]; then
    if node "$ROOT/tests/e2e/report-render.js" --in "$OUT" --out "$HTML" >/dev/null 2>&1; then
      echo "  html    ${HTML#$ROOT/}"
    else
      c_warn "  ! renderer refused or failed"; echo " — JSON is still at ${OUT#$ROOT/}"
      node "$ROOT/tests/e2e/report-render.js" --in "$OUT" --out "$HTML" 2>&1 | sed 's/^/      /'
    fi
  fi
  return "$rc"
}
trap emit_report EXIT
# An interrupted run is still a run that happened, and it must still leave a report saying
# how far it got. Without these, Ctrl-C on the 9-minute conformance rung leaves nothing on
# disk and the next reader cannot tell an aborted review from a review nobody started.
trap 'echo ""; c_warn "  ! INTERRUPTED"; echo " — emitting the partial report"; exit 2' INT TERM

echo "══ review-module: $MODULE ══  $STAMP"
echo "  scope: the MODEL against what was decided. Not the running app — no journey runs here."

# ── 0. Does this module exist at all? ───────────────────────────────────────
# Without this, every instrument below returns an empty result set for a typo'd name and
# an empty result set is indistinguishable from a clean one. Catalog first (instant),
# mxcli SHOW MODULES as the authority when the catalog is missing or says no.
MODULE_KNOWN=0
if [ -f "$ROOT/.mxcli/catalog.db" ] && command -v sqlite3 >/dev/null 2>&1; then
  n="$(sqlite3 -noheader "$ROOT/.mxcli/catalog.db" \
        "SELECT COUNT(*) FROM objects WHERE ModuleName='$MODULE';" 2>/dev/null || echo 0)"
  [ "${n:-0}" -gt 0 ] 2>/dev/null && MODULE_KNOWN=1
fi
if [ "$MODULE_KNOWN" -eq 0 ]; then
  MODLIST="$(with_timeout 60 ./mxcli -p "$MPR" -c "SHOW MODULES" 2>/dev/null)"
  printf '%s\n' "$MODLIST" | grep -qE "^\| *$MODULE +\|" && MODULE_KNOWN=1
fi

if [ "$MODULE_KNOWN" -eq 0 ]; then
  printf '\n'
  c_warn "  ! INSTRUMENT FAULT"; echo " — no module named '$MODULE' in $(basename "$MPR")"
  echo "      Nothing was measured. This is not a clean review of an empty module:"
  echo "      every instrument below would have returned an empty result set, which is"
  echo "      indistinguishable from a clean one. Check the spelling against:"
  echo "        ./mxcli -p $(basename "$MPR") -c 'SHOW MODULES'"
  printf 'module exists\tFAULT\t2\t-\t(no such module)\n' >> "$SUMMARY"
  for i in conformance graph-sweep coverage; do
    note_instrument "$i" fault 2 "" "" "not run — no module named '$MODULE' in the model"
  done
  FAULTED=3
  echo ""
  echo "  A report IS still written, so this run is distinguishable from one that never happened."
  exit 2
fi

# ── 1. Conformance: the ledger's claimed status vs the live model ───────────
# The ledger is a claim. This measures it. A module with no ledger has made no claims to
# measure, which is a FAULT and emphatically not a pass — "no ledger" is exactly the hole
# that let projects ship with no coverage-ledger.md at all and read as silence.
LEDGER="$ROOT/architecture/modules/$MODULE/coverage-ledger.md"
if [ ! -f "$LEDGER" ]; then
  fault_instrument "conformance (ledger claims vs live model)" conformance \
    "no architecture/modules/$MODULE/coverage-ledger.md" \
    "This module has made no recorded claims, so none could be measured." \
    "Its conformance is UNMEASURED, not clean: there is no row here saying" \
    "'the model matches the decision' because there is no decision on file."
elif [ -n "$REUSE_CONF" ]; then
  printf '\n\033[1m── conformance (reusing the caller'"'"'s run)\033[0m\n'
  case "$REUSE_CONF" in /*) RC_PATH="$REUSE_CONF" ;; *) RC_PATH="$ROOT/$REUSE_CONF" ;; esac
  if [ ! -f "$RC_PATH" ]; then
    c_warn "  ! INSTRUMENT FAULT"; echo " — $REUSE_CONF does not exist"
    echo "      The caller said it had already measured conformance and it had not."
    printf 'conformance (reused)\tFAULT\t2\t-\t(%s missing)\n' "$REUSE_CONF" >> "$SUMMARY"
    note_instrument conformance fault 2 "" "" "reuse requested but $REUSE_CONF does not exist"
    FAULTED=$((FAULTED+1))
  else
    awk -F'\t' -v m="$MODULE" 'NR==1 || $1==m' "$RC_PATH" > "$OUTDIR/conformance.tsv"
    RC_ROWS=$(awk -F'\t' -v m="$MODULE" '$1==m' "$RC_PATH" | grep -c . || true)
    if [ "${RC_ROWS:-0}" -eq 0 ]; then
      rm -f "$OUTDIR/conformance.tsv"
      c_warn "  ! INSTRUMENT FAULT"; echo " — $REUSE_CONF carries no rows for $MODULE"
      echo "      Reusing it would report zero measurements as a clean module."
      printf 'conformance (reused)\tFAULT\t2\t-\t(no rows for %s)\n' "$MODULE" >> "$SUMMARY"
      note_instrument conformance fault 2 "" "${REUSE_CONF}" \
        "reused report carries no rows for $MODULE — refusing to report a clean run over zero measurements"
      FAULTED=$((FAULTED+1))
    else
      c_ok "  ✓ reused"; echo "  ($RC_ROWS rows from ${REUSE_CONF})"
      printf 'conformance (reused)\tPASS\t0\t-\t%s\n' "$REUSE_CONF" >> "$SUMMARY"
      note_instrument conformance pass 0 "" "$REUSE_CONF" ""
    fi
  fi
else
  run "conformance (ledger claims vs live model)" conformance \
    "$OUTDIR/10-conformance.log" gate "${RM_TMO_CONFORMANCE:-1800}" -- \
    "$(_tool conformance-check.sh)" --module "$MODULE"
  # Slice THIS run's conformance report down to this module for the structured checks.
  #
  # `ls -t | head -1` names the newest report, which is only this run's report if this run
  # wrote one. conformance-check.sh writes it in its last few lines, so a rung that timed
  # out or crashed wrote nothing and the newest file is an EARLIER DAY's. Slicing that in
  # hands review-report.js a full set of rows to turn into `pass` checks stamped with this
  # run's timestamp, under an instrument row that says `fault`.
  #
  # Measured 2026-08-18, RM_TMO_CONFORMANCE=1 on RoutingManagement: conformance got through
  # 1 of 22 rows and logged "nothing was measured"; the report carried 13 pass / 5 fail
  # conformance checks anyway, all from the previous run's file.
  #
  # Two conditions now, either of which is disqualifying on its own:
  if [ "$LAST_VERDICT" = FAULT ]; then
    echo "      conformance did not complete — NOT slicing an older report in as its result."
  else
    CONF_TSV="$(ls -t "$ROOT"/docs/conformance/report-*.tsv 2>/dev/null | head -1)"
    if [ -z "$CONF_TSV" ]; then
      echo "      no docs/conformance/report-*.tsv to slice; the report will carry a fault row."
    elif [ ! "$CONF_TSV" -nt "$OUTDIR/.started" ]; then
      echo "      newest conformance report predates this run — NOT slicing it in."
      echo "      (${CONF_TSV#$ROOT/} is older than $STAMP; it measured a different run.)"
    else
      awk -F'\t' -v m="$MODULE" 'NR==1 || $1==m' "$CONF_TSV" > "$OUTDIR/conformance.tsv"
    fi
  fi
fi

# ── 2. Graph sweep: orphans and wiring shape ────────────────────────────────
# --tsv so the findings land structured in the report. Exit 2 = stale/empty catalog;
# the sweep refuses to report a clean shape from a graph it cannot trust.
run "graph sweep (orphans + wiring shape)" graph-sweep \
  "$OUTDIR/graph.tsv" gate 300 -- \
  "$(_tool graph-sweep.sh)" --module "$MODULE" --tsv

# ── 3. Coverage (optional rung): BRD leaves vs ledger ───────────────────────
# A DIFFERENT question from conformance — "does the requirement exist and is it claimed",
# not "does the model match the claim". Run when reachable; a fault row when not.
COV=""
# coverage-check.sh lives in the toolkit's bin/, not project-bin/, so _tool finds it
# via $MXTK_ROOT. It used to be looked up through one contributor's absolute clone
# path, which resolves on exactly one laptop.
cand="$(_tool coverage-check.sh)"
[ -x "$cand" ] && COV="$cand"
# The BRD is named by the ledger itself; guessing with `ls | head -1` picks another
# module's BRD and reports its leaves as this module's coverage.
BRD=""
if [ -f "$LEDGER" ]; then
  # ALL the BRDs the ledger names, not just the first — and the COUNT is reported, because
  # coverage-check.sh measures one BRD per run and a module with five of them was silently
  # having one fifth of its requirements measured and printed as the module's coverage
  # (t-wf-migration, 2026-09-02: five BRDs, F001 measured, F002-F005 never looked at, output
  # indistinguishable from full coverage). That is the exact shape of false green this repo's
  # own rule against unstated denominators exists to prevent.
  #
  # The first RESOLVABLE path wins rather than the first match: a ledger that mentions the
  # filename pattern in prose above its list hands `head -1` a string that is not a file, and
  # the instrument then reports "names no reachable BRD" over a ledger that names five.
  BRD_ALL=""
  while IFS= read -r cand; do
    [ -n "$cand" ] && [ -f "$ROOT/$cand" ] && BRD_ALL="$BRD_ALL$cand"$'\n'
  done <<EOF
$(grep -oE '[A-Za-z0-9_/.-]*\.brd\.json' "$LEDGER" 2>/dev/null | sort -u)
EOF
  BRD_N=$(printf '%s' "$BRD_ALL" | grep -c . || true)
  BRD_REL="$(printf '%s' "$BRD_ALL" | head -1)"
  [ -n "$BRD_REL" ] && BRD="$ROOT/$BRD_REL"
fi
if [ -z "$COV" ]; then
  fault_instrument "coverage (BRD leaves: UNCLAIMED/PHANTOM/DOUBLE)" coverage \
    "coverage-check.sh not reachable (neither bin/ nor the toolkit)" \
    "Requirement traceability for $MODULE is UNMEASURED, not clean."
elif [ ! -f "$LEDGER" ]; then
  fault_instrument "coverage (BRD leaves: UNCLAIMED/PHANTOM/DOUBLE)" coverage \
    "no coverage-ledger.md for $MODULE" \
    "Requirement traceability for $MODULE is UNMEASURED, not clean."
elif [ -z "$BRD" ]; then
  fault_instrument "coverage (BRD leaves: UNCLAIMED/PHANTOM/DOUBLE)" coverage \
    "the ledger names no reachable *.brd.json" \
    "Refusing to substitute another module's BRD — that would report its leaves as this module's."
else
  # MULTI-LEDGER MODE (added 2026-09-02, field-proven on t-wf-migration's five BRDs going
  # from "coverage · 1 of 5 BRDs" to all five clean). A module split one-ledger-per-BRD keeps
  # its files at architecture/modules/<Module>/coverage-ledger/<BRDID>.md — a DIRECTORY beside
  # where the single-file convention would put coverage-ledger.md, named after that same base.
  # If it exists, every BRD the ledger set names gets its own coverage-check.sh run, via
  # coverage-check-all.sh so this reuses the same `run()` verdict machinery (PASS/FINDING/FAULT
  # from a real exit code) every other rung here already goes through, rather than a bespoke
  # ad-hoc pass/fail path.
  LEDGER_DIR="$(dirname "$LEDGER")/coverage-ledger"
  if [ -d "$LEDGER_DIR" ]; then
    ALL="$(_tool coverage-check-all.sh)"
    BRD_GLOB="$(dirname "$BRD")/*.brd.json"
    run "coverage (BRD leaves: UNCLAIMED/PHANTOM/DOUBLE · all BRDs, one ledger each)" coverage \
      "$OUTDIR/coverage.txt" gate 300 -- \
      "$ALL" "$LEDGER_DIR" "$BRD_GLOB"
  else
    if [ "${BRD_N:-1}" -gt 1 ]; then
      printf '  \033[33m! coverage measures ONE BRD per run; this ledger names %s\033[0m\n' "$BRD_N"
      printf '    measuring %s — the other %s are NOT covered by this verdict.\n' \
        "$BRD_REL" "$((BRD_N - 1))"
      printf '    Run coverage-check.sh per BRD, or split the ledger one-per-BRD (see t-wf-migration for a worked example).\n'
    fi
    run "coverage (BRD leaves: UNCLAIMED/PHANTOM/DOUBLE${BRD_N:+ · 1 of $BRD_N BRDs})" coverage \
      "$OUTDIR/coverage.txt" gate 300 -- \
      "$COV" --summary "$BRD" "$LEDGER"
  fi
fi

# ── 4. Journeysfi

# ── 4. Journeys: NOT run here, and the report must say so ───────────────────
# Stated in the terminal as well as the report, because a reader who sees three clean
# model instruments and no mention of the app will supply the wrong conclusion.
printf '\n\033[1m── journeys (the running app)\033[0m\n'
c_warn "  ! NOT RUN IN THIS INVOCATION"; echo " — review answers a model question."
echo "      The report carries a journey \`fault\` row so it cannot render as covered."
echo "      For the app-side answer: bin/verify-module.sh $MODULE (needs the stack up)."
printf 'journeys\tFAULT\t2\t-\t(no journey run in this invocation)\n' >> "$SUMMARY"
note_instrument journey-runner fault 2 "" "" "no journey run in this invocation"

# ── 4b. The LOOK: also not run here, and the report must say so ─────────────
# Same reasoning as the journeys row directly above, for module-review.md stage 4 — the visual
# assessment of every page in the module. This script answers a model question; stage 4 is a
# judgement pass over rendered screens and no script performs it. Left unmentioned it renders as
# covered, which is precisely how an end-to-end run reports journeys, DB assertions and a monkey
# pass, goes green, and never looks at a page (measured 2026-08-20).
#
# Like the journeys row this does NOT increment FAULTED: it is a permanent property of this
# invocation, not a breakage, and gating on it would make every clean review exit 2.
printf '\n\033[1m── look (module-review.md §4 — the rendered pages)\033[0m\n'
c_warn "  ! NOT RUN IN THIS INVOCATION"; echo " — review answers a model question."
echo "      The report carries a \`look\` fault row so it cannot render as covered."
echo "      For the visual answer: review-agent, job 2 — every page in $MODULE assessed"
echo "      against wireframe, design system, or module-review.md §4d's unaided rubric."
printf 'look\tFAULT\t2\t-\t(no visual review in this invocation — module-review.md §4)\n' >> "$SUMMARY"
note_instrument ui-review fault 2 "" "" "no visual review in this invocation - module-review.md stage 4"

# ── 5. Verdict ──────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════"
column -t -s "$(printf '\t')" "$SUMMARY" 2>/dev/null | sed 's/^/  /' || cat "$SUMMARY"
echo "════════════════════════════════════════════════════════"
echo "  logs: ${OUTDIR#$ROOT/}"

if [ "$FAULTED" -gt 0 ]; then
  echo ""
  c_warn "  INCOMPLETE"; echo " — $FAULTED instrument(s) did not run, $FINDINGS with findings."
  echo "  This is NOT a pass with caveats. The unrun checks are absent, not green."
  exit 2
fi
if [ "$FINDINGS" -gt 0 ]; then
  echo ""; c_bad "  FINDINGS"; echo " — $FINDINGS instrument(s) reported. Every one ran; the model disagreed with the claim."
  exit 1
fi
echo ""; c_ok "  CLEAN"; echo " — every model instrument ran and found nothing."
echo "  Scope of that claim: ledger conformance, wiring shape, BRD coverage. It is NOT a"
echo "  claim about the running app — no journey ran, and nobody looked at a page"
echo "  (see the journeys and look fault rows in the report)."
exit 0
