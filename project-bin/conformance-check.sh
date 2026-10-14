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
# A row with no baseline line yet (a module built after the baseline was written) is baselined
# on first sight and said so; `--module` scopes a baseline rewrite to that module's rows.
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
# Ledger path shapes, all read:
#   architecture/modules/<Module>/coverage-ledger/*.md  one ledger per BRD (coverage-check-all.sh's
#                                                       form); EVERY file is measured, one report
#                                                       per BRD, and the coverage-ledger.md beside
#                                                       the directory is treated as its index
#   architecture/modules/<Module>/coverage-ledger.md    canonical (per-module)
#   architecture/modules/<Module>-coverage-ledger.md    flat module layout
#   architecture/coverage-ledger.md                     single-BRD project
#
# Usage:
#   bin/conformance-check.sh [--module <Name>] [--update-baseline] [--quiet]
#   LEDGER_FILE=<file-or-dir> bin/conformance-check.sh [--module <Name>] ...
#
#   LEDGER_FILE   overrides discovery: one ledger file, or a directory whose *.md files are all
#                 measured (one per BRD). Relative to the project root. A path that is neither is
#                 a FAULT, never a silent fall-back to another ledger.
#
# Exit: 0 clean or baseline written · 1 regression · 2 instrument fault (refuses to guess)
#       3 NOT MEASURED (no ledger, but a spec exists) · 4 NOT APPLICABLE (no spec at all)

set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
cd "$PROJECT_ROOT" || exit 2

MPR="$(find_mpr)" || exit 2
MXCLI="$(find_project_mxcli 2>/dev/null || echo ./mxcli)"
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
    -h|--help)         sed -n '2,52p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -x "$MXCLI" ] || { echo "FAULT: $MXCLI not found or not executable" >&2; exit 2; }
[ -f "$MPR" ]   || { echo "FAULT: $MPR not found" >&2; exit 2; }
mkdir -p "$OUTDIR"

# --- find the ledger(s) ------------------------------------------------------------------
# Three path shapes are in the wild and all three are legitimate. The canonical one is the
# per-module directory; the flat one exists because real projects lay architecture/modules/ out
# flat (PROJECT-A: `Approval-brief.md`, `ProductNumbers.md`, no subdirectories at all); the
# project-level one is sanctioned by skills/coverage-ledger.md's own header for a single-BRD
# project. Globbing only the canonical shape is why a project with ledgers in the flat shape
# would still be told it had none.
#
# LEDGER_COUNT is tracked separately rather than read back as ${#LEDGERS[@]}: under `set -u`,
# bash 3.2 (stock macOS) treats an EMPTY array as unset and aborts on that expansion — which is
# precisely the case this block exists to handle gracefully.
#
# PER-BRD DIRECTORIES (fixed 2026-10-13, field report 2026-10-11): a
# module that splits its ledger one-per-BRD keeps the rows in <Module>/coverage-ledger/<BRD>.md
# and turns <Module>/coverage-ledger.md into an index. This script only ever read the index, so
# every such module ended in "FAULT: 0 measurable rows extracted from 1 ledger(s)." — while the
# operator's LEDGER_FILE workaround on ONE per-BRD file measured 128 rows (66 measured, 66 OK).
# coverage-preflight.sh already read the directory first (2026-09-26); this is the same rule:
# the directory wins over the index beside it, and every file in it is measured.
LEDGERS=()
LEDGER_COUNT=0
add_ledger() { LEDGERS[$LEDGER_COUNT]="$1"; LEDGER_COUNT=$((LEDGER_COUNT+1)); }
has_md()     { [ -d "$1" ] && ls "$1"/*.md >/dev/null 2>&1; }
add_dir()    { local f; for f in "$1"/*.md; do [ -f "$f" ] && add_ledger "$f"; done; }
if [ -n "${LEDGER_FILE:-}" ]; then
  if has_md "$LEDGER_FILE"; then add_dir "$LEDGER_FILE"
  elif [ -f "$LEDGER_FILE" ]; then add_ledger "$LEDGER_FILE"
  else
    echo "FAULT: LEDGER_FILE=$LEDGER_FILE is neither a ledger file nor a directory of *.md ledgers" >&2
    echo "       (resolved against $PROJECT_ROOT). Refusing to fall back to another ledger." >&2
    exit 2
  fi
elif [ -n "$MODULE" ]; then
  if has_md "architecture/modules/$MODULE/coverage-ledger"; then
    add_dir "architecture/modules/$MODULE/coverage-ledger"
  else
    for c in "architecture/modules/$MODULE/coverage-ledger.md" \
             "architecture/modules/$MODULE-coverage-ledger.md" \
             "architecture/coverage-ledger.md"; do
      [ -f "$c" ] && { add_ledger "$c"; break; }
    done
  fi
else
  for d in architecture/modules/*/coverage-ledger; do
    has_md "$d" && add_dir "$d"
  done
  for c in architecture/modules/*/coverage-ledger.md \
           architecture/modules/*-coverage-ledger.md \
           architecture/coverage-ledger.md; do
    [ -f "$c" ] || continue
    has_md "${c%.md}" && continue          # the index of a per-BRD directory measured above
    add_ledger "$c"
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
# A per-BRD file <Module>/coverage-ledger/<BRD>.md belongs to <Module> and carries a BRD label;
# every other shape has no BRD label ("-": read splits on tabs, so an empty field would shift).
ledger_module() {
  local ledger="$1" base parent
  base="$(basename "$ledger")"
  parent="$(basename "$(dirname "$ledger")")"
  case "$base" in
    *-coverage-ledger.md) printf '%s\n' "${base%-coverage-ledger.md}"; return ;;
  esac
  case "$parent" in
    architecture)    printf '%s\n' "${MODULE:-project}"; return ;;
    coverage-ledger) printf '%s\n' "$(basename "$(dirname "$(dirname "$ledger")")")"; return ;;
    *)               printf '%s\n' "$parent"; return ;;
  esac
}
ledger_brd() {
  case "$(basename "$(dirname "$1")")" in
    coverage-ledger) printf '%s\n' "$(basename "$1" .md)" ;;
    *)               printf '%s\n' "-" ;;
  esac
}

# Rows are keyed (module, pointer) in the baseline. A JSON pointer is relative to ITS BRD, so two
# per-BRD ledgers of one module both have `/microflows/0`; their pointer key carries the BRD id.
extract() {
  local ledger="$1" mod brd
  mod="$(ledger_module "$ledger")"
  brd="$(ledger_brd "$ledger")"
  awk -F'|' -v mod="$mod" -v brd="$brd" -v file="$ledger" '
    NF==9 && $2 ~ /^ *`\// {
      total++
      ptr=$2; acc=$7; st=$8
      gsub(/^ +| +$/, "", ptr); gsub(/^ +| +$/, "", st)
      if (brd != "-") ptr = brd ":" ptr
      if (match(acc, /`(SHOW|DESCRIBE)[^`]*`/)) {
        cmd = substr(acc, RSTART+1, RLENGTH-2)
        print "ROW\t" mod "\t" brd "\t" ptr "\t" st "\t" cmd
      } else {
        print "PROSE\t" mod "\t" brd "\t" ptr "\t" st "\t"
      }
    }
    END { if (!total) print "NOTABLE\t" file }
  ' "$ledger"
}

ROWS="$(for l in "${LEDGERS[@]}"; do [ -f "$l" ] && extract "$l"; done)"

MEASURABLE=$(printf '%s\n' "$ROWS" | grep -c '^ROW' || true)
PROSE=$(printf '%s\n' "$ROWS" | grep -c '^PROSE' || true)
NOTABLE="$(printf '%s\n' "$ROWS" | awk -F'\t' '$1=="NOTABLE"{print $2}')"

# A ledger file with no ledger table is, in practice, an index: the coverage-ledger.md a module
# keeps beside its per-BRD directory, or one that points at another module's per-BRD file.
# Say where its rows are rather than "0 measurable rows", which reads as a broken instrument.
explain_index() {
  local f="$1" dir links
  dir="${f%.md}"
  echo "       $f has no ledger table rows — it is an index, not a ledger." >&2
  if has_md "$dir"; then
    echo "       Its rows are in $dir/:" >&2
    for l in "$dir"/*.md; do echo "         $l" >&2; done
    echo "       Unset LEDGER_FILE (the directory is found by itself) or set LEDGER_FILE=$dir" >&2
    return
  fi
  links="$(grep -oE '\]\([^)#]+\.md\)' "$f" 2>/dev/null | sed -E 's/^\]\(//; s/\)$//' | sort -u)"
  if [ -n "$links" ]; then
    echo "       It links to these ledgers (relative to $(dirname "$f")/) — rows are in them:" >&2
    printf '%s\n' "$links" | sed 's/^/         /' >&2
    echo "       Measure them with LEDGER_FILE=<that file or its directory>." >&2
  fi
}

# Non-vacuous guard: an instrument that measured nothing must not report "all clean".
if [ "$MEASURABLE" -eq 0 ]; then
  NNOTABLE=$(printf '%s' "$NOTABLE" | grep -c . || true)
  if [ "$NNOTABLE" -gt 0 ] && [ "$NNOTABLE" -eq "$LEDGER_COUNT" ]; then
    echo "FAULT: nothing to measure — the ledger read is an index, not a ledger table." >&2
    while IFS= read -r f; do [ -n "$f" ] && explain_index "$f"; done <<< "$NOTABLE"
    echo "       Refusing to report a clean run over zero measurements." >&2
    exit 2
  fi
  echo "FAULT: 0 measurable rows extracted from $LEDGER_COUNT ledger(s)." >&2
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
  # THE WATCHDOG POLLS INSTEAD OF SLEEPING ONCE (fixed 2026-09-02, found on a workflow-migration project).
  # It used to be `( sleep "$TIMEOUT_S"; kill -9 "$pid" )`, cancelled afterwards with
  # `kill "$killer"; wait "$killer"`. That cancellation does not work: a bash subshell blocked
  # inside `sleep` does not act on SIGTERM until the sleep RETURNS, so `wait "$killer"` sat for
  # the whole timeout window on EVERY probe -- whatever the command did, however fast.
  #
  # Field measurement (a workflow-migration project, 61-row ledger, 30 measurable rows): each mxcli DESCRIBE
  # took 0.144s and each probe took 24s with TIMEOUT_S=25. Conformance needed ~12 minutes to do
  # ~5 seconds of work and was killed by every reasonable outer timeout before it printed a
  # verdict. The instrument looked hung; it was only ever waiting on its own guard. Nobody had
  # noticed because a ledger with few measurable rows finishes anyway -- the cost scales with
  # exactly the thing a good ledger has more of.
  #
  # Polling in 1s steps fixes both halves: the watchdog exits by itself within a second of the
  # command finishing (nothing to cancel, no orphaned `sleep` left behind), and it still kills a
  # genuinely stuck command at the deadline. `kill -0` is a liveness test, not a signal. SIGKILL
  # on the cancel path because, unlike SIGTERM, it cannot be deferred.
  ( i=0
    while [ "$i" -lt "$TIMEOUT_S" ]; do
      sleep 1; i=$((i+1))
      kill -0 "$pid" 2>/dev/null || exit 0
    done
    kill -9 "$pid" 2>/dev/null ) & killer=$!
  wait "$pid" 2>/dev/null; rc=$?
  kill -9 "$killer" 2>/dev/null; wait "$killer" 2>/dev/null
  cat "$tmp"; rm -f "$tmp"
  return $rc
}

# PRESENT = mxcli exited 0, produced output, and the output is not an empty result set.
probe() {
  local cmd="$1" out rc
  if ! runnable "$cmd"; then echo "UNRUNNABLE"; return; fi
  # mxcli v0.25.0 reads -c as mdl 1, which refuses the one-element summaries outright:
  # "Parse error: line 1: `show entity` is not in mdl 1: write `describe entity` for the
  # definition, …" (verbatim, v0.25.0). Ledgers written for v0.24 carry `SHOW ENTITY M.X`, so
  # every such row would turn UNRUNNABLE on upgrade and read as a regression. DESCRIBE answers
  # the same presence question on both versions (rc 0 found, "Error: entity not found: M.X"
  # rc 1 missing), so ask that instead. Only these two forms were removed; other SHOWs still run.
  cmd="$(printf '%s' "$cmd" | sed -E 's/^[Ss][Hh][Oo][Ww]( +([Ee][Nn][Tt][Ii][Tt][Yy]|[Aa][Ss][Ss][Oo][Cc][Ii][Aa][Tt][Ii][Oo][Nn]) )/DESCRIBE\1/')"
  out="$(run_guarded "$cmd")"; rc=$?
  if [ $rc -ge 128 ]; then echo "TIMEOUT"; return; fi
  # A probe mxcli cannot run says nothing about the model, so it is UNRUNNABLE, never ABSENT.
  # Scored as ABSENT it was a false OK on every not-built row with a malformed probe: on a
  # card-disbursement requirements-driven build `DESCRIBE DEMOUSER ops1` read ABSENT/OK while
  # `DESCRIBE DEMO USER 'ops1'` read PRESENT on the same model. Both strings are verbatim
  # mxcli v0.24.0 output (rc 1): "Parse error: line 1:64 extraneous input '.' …" and
  # "Error: no describable document named "DEMOUSER" found in the project; specify the type
  # explicitly, …". A genuine miss stays ABSENT: "Error: constant not found: Nope.X".
  case "$out" in
    *"Parse error:"*|*"no describable document named"*) echo "UNRUNNABLE"; return ;;
  esac
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
while IFS=$'\t' read -r kind mod brd ptr status cmd; do
  [ "$kind" = "ROW" ] || continue
  n=$((n+1))
  [ "$QUIET" -eq 1 ] || printf '\r  measuring %d/%d ' "$n" "$MEASURABLE" >&2
  observed="$(probe "$cmd")"
  case "$observed" in
    UNRUNNABLE) verdict="UNRUNNABLE" ;;   # prose, or a command mxcli refused to parse/resolve
    TIMEOUT)    verdict="TIMEOUT" ;;      # never treated as a pass
    *)
      case "$status:$observed" in
        built:PRESENT|partial:PRESENT|not-built:ABSENT|accepted:PRESENT) verdict="OK" ;;
        built:ABSENT|partial:ABSENT|accepted:ABSENT)                     verdict="STALE" ;;
        not-built:PRESENT)                                               verdict="UNDERSTATED" ;;
        *)                                                               verdict="UNKNOWN-STATUS" ;;
      esac ;;
  esac
  RESULTS+="$mod	$ptr	$status	$observed	$verdict	$cmd	$brd"$'\n'
done 3<<< "$ROWS" <&3
[ "$QUIET" -eq 1 ] || printf '\r%*s\r' 30 '' >&2

RESULTS="$(printf '%s' "$RESULTS" | sed '/^$/d' | sort)"

# --- baseline / regression --------------------------------------------------------------
KEYED="$(printf '%s\n' "$RESULTS" | awk -F'\t' '{print $1"\t"$2"\t"$5}')"

# `--module` measures one module, so it may rewrite only that module's rows. Writing $KEYED
# whole dropped every other module's baseline, and their regressions went unmeasured with
# nothing said (card-disbursement build, 2026-09-26: `--update-baseline --module MockServices`
# dropped the 127 Disbursement rows).
#
# A rewrite that LOOSENS needs a person (#348): a row OK in the old baseline and not OK in the
# new one is a regression being accepted, so it is written only against a matching row in
# .claude/baseline-approvals.tsv (bin/baseline-approve.sh conformance, run by the user). So does
# re-creating a deleted baseline, or any write over one that moved outside this script. A
# first baseline, a rewrite that loosens nothing and first-sight seeding need nothing; every
# write is recorded (bin/baseline-lock.sh) so gate-check can tell a hand edit from ours.
LOCK="$(dirname "${BASH_SOURCE[0]}")/baseline-lock.sh"
[ -f "$LOCK" ] || LOCK=""
PRIOR=""; [ -n "$LOCK" ] && PRIOR="$(bash "$LOCK" verify "$PROJECT_ROOT" conformance | cut -f1)"
# lock_write <new-file> <basis> — move <new-file> over the baseline, or refuse (exit 2)
lock_write() {
  local new="$1" basis="$2" why="" loose sha
  if [ -f "$BASELINE" ]; then
    loose="$(awk -F'\t' 'NR==FNR { if ($3=="OK") ok[$1"\t"$2]=1; next }
                         (($1"\t"$2) in ok) && $3!="OK" {n++} END {print n+0}' "$BASELINE" "$new")"
    [ "$loose" -gt 0 ] && why="accepts $loose regression(s) (rows OK in the baseline, not OK now)"
  fi
  [ "$PRIOR" = GONE ] && why="${why:+$why; }re-creates a baseline that was deleted"
  [ "$PRIOR" = FAIL ] && why="${why:+$why; }follows a baseline that moved without approval"
  [ "$PRIOR" = MANUAL ] && why="${why:+$why; }follows a baseline with no verifiable record"
  if [ -z "$why" ]; then
    mv "$new" "$BASELINE"
    if [ -n "$LOCK" ]; then bash "$LOCK" record "$PROJECT_ROOT" conformance "$basis"
    else echo "  note: bin/baseline-lock.sh not installed — this baseline write is unrecorded (sync-project.sh)" >&2; fi
    return 0
  fi
  if [ -z "$LOCK" ]; then
    echo "REFUSED — this baseline write $why and needs a person's approval, but bin/baseline-lock.sh is not installed (run the toolkit's bin/sync-project.sh)." >&2
    rm -f "$new"; exit 2
  fi
  sha="$(bash "$LOCK" sha "$new")"
  if bash "$LOCK" approved "$PROJECT_ROOT" conformance "$sha"; then
    mv "$new" "$BASELINE"
    bash "$LOCK" record "$PROJECT_ROOT" conformance approved
    echo "  human approval found for this exact baseline (sha $(printf '%s' "$sha" | cut -c1-12))"
    return 0
  fi
  echo "REFUSED — this baseline write $why." >&2
  [ -f "$BASELINE" ] && awk -F'\t' 'NR==FNR { if ($3=="OK") ok[$1"\t"$2]=1; next }
       (($1"\t"$2) in ok) && $3!="OK" {print "    " $1 "  " $2 "  OK -> " $3}' "$BASELINE" "$new" | head -20 >&2
  bash "$LOCK" propose "$PROJECT_ROOT" conformance "$new" "conformance: $why${MODULE:+ (module $MODULE)}"
  rm -f "$new"; exit 2
}
if [ "$UPDATE_BASELINE" -eq 1 ] || [ ! -f "$BASELINE" ]; then
  if [ -n "$MODULE" ] && [ -f "$BASELINE" ]; then
    { awk -F'\t' -v m="$MODULE" '$1!=m' "$BASELINE"; printf '%s\n' "$KEYED"; } \
      | sed '/^$/d' | sort > "$BASELINE.tmp"
  else
    printf '%s\n' "$KEYED" > "$BASELINE.tmp"
  fi
  if [ -f "$BASELINE" ]; then lock_write "$BASELINE.tmp" tighten; else lock_write "$BASELINE.tmp" first; fi
  WROTE_BASELINE=1
else
  WROTE_BASELINE=0
fi

# A row the baseline has never seen (a module built after the first run wrote it) used to be
# compared with "" — never a regression, forever, with nothing said. Its first measurement is
# its baseline, exactly as the first run's were; the count is printed below.
REGRESSIONS=""
SEEDED=""
if [ "$WROTE_BASELINE" -eq 0 ]; then
  while IFS=$'\t' read -r mod ptr verdict; do
    [ -n "$mod" ] || continue
    was="$(awk -F'\t' -v m="$mod" -v p="$ptr" '$1==m && $2==p {print $3; exit}' "$BASELINE")"
    if [ -z "$was" ]; then
      SEEDED+="$mod	$ptr	$verdict"$'\n'
    elif [ "$was" = "OK" ] && [ "$verdict" != "OK" ]; then
      REGRESSIONS+="$mod	$ptr	was OK, now $verdict"$'\n'
    fi
  done <<< "$KEYED"
  # Seeding adds rows the baseline never had; it is recorded, never laundered over a hand edit.
  if [ -n "$SEEDED" ] && { [ "$PRIOR" = FAIL ] || [ "$PRIOR" = MANUAL ]; }; then
    echo "  note: $(printf '%s' "$SEEDED" | grep -c .) row(s) not seeded — the baseline is $PRIOR in gate-check; the user runs bin/baseline-approve.sh conformance --current" >&2
    SEEDED=""
  elif [ -n "$SEEDED" ]; then
    { cat "$BASELINE"; printf '%s' "$SEEDED"; } | sed '/^$/d' | sort > "$BASELINE.tmp" \
      && lock_write "$BASELINE.tmp" seed
  fi
fi
NSEED=$(printf '%s' "$SEEDED" | grep -c . || true)

# --- report ------------------------------------------------------------------------------
STAMP="$(date +%Y-%m-%d)"
# One report per BRD for per-BRD ledgers (report-<date>-<BRD>.tsv), so measuring several BRDs
# does not leave only the last one on disk; rows from every other shape keep report-<date>.tsv.
REPORTS=""
# while-read, not `for b in $(…)`: a BRD file name with a space must stay one BRD.
while IFS= read -r b; do
  [ -n "$b" ] || continue
  if [ "$b" = "-" ]; then REPORT="$OUTDIR/report-$STAMP.tsv"; else REPORT="$OUTDIR/report-$STAMP-$b.tsv"; fi
  { printf 'module\tpointer\tstored\tobserved\tverdict\tcommand\n'
    printf '%s\n' "$RESULTS" | awk -F'\t' -v b="$b" 'BEGIN{OFS="\t"} $7==b {print $1,$2,$3,$4,$5,$6}'
  } > "$REPORT"
  REPORTS+="$REPORT"$'\n'
done <<< "$(printf '%s\n' "$RESULTS" | awk -F'\t' 'NF{print $7}' | sort -u)"

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
[ "$UNRUN" -gt 0 ] && echo "  UNRUNNABLE             $UNRUN   (backticked prose, or a probe mxcli rejects — fix the probe; see the report)"
[ "$TMO" -gt 0 ]   && echo "  TIMEOUT                $TMO   (>${TIMEOUT_S}s — never counted as a pass)"
[ "$UNK" -gt 0 ]   && echo "  UNKNOWN-STATUS         $UNK"
while IFS= read -r r; do [ -n "$r" ] && echo "  report                 $r"; done <<< "$REPORTS"
if [ -n "$NOTABLE" ]; then
  while IFS= read -r f; do [ -n "$f" ] && echo "  no table (index?)      $f"; done <<< "$NOTABLE"
fi
[ "$NSEED" -gt 0 ] && echo "  newly baselined        $NSEED   (no baseline row yet — regressions measured from the next run)"

if [ "$STALE" -gt 0 ] || [ "$UNDER" -gt 0 ]; then
  echo
  echo "  mismatches:"
  printf '%s\n' "$RESULTS" | awk -F'\t' '$5!="OK" {printf "    %-24s %-28s %-11s -> %-7s %s\n", $1, $2, $3, $4, $5}'
fi

if [ "$WROTE_BASELINE" -eq 1 ]; then
  echo
  if [ -n "$MODULE" ]; then
    echo "  baseline rows for $MODULE rewritten in $BASELINE ($MEASURABLE rows; other modules' rows kept)."
  else
    echo "  baseline written to $BASELINE ($MEASURABLE rows). Regressions are measured from here."
  fi
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
