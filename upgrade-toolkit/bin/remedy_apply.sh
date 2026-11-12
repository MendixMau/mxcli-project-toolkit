#!/bin/bash
# remedy_apply.sh: apply one option of a remedy card on its own branch, check, build, gate again, record the result (RT-10,
# BACKLOG #86, RM-3).
#
# Why: remedy.py printed the next AUTO-TRY option as a command line, and no script applied it. In the notification
# service remedy trial (r1 and r2) every rung needed the same hand steps: a branch per option, the recipe, a widget
# refresh, mx check 0, a build to a labelled mda with a disk check, a gate folder seeded from the original gate (the
# --only merge had nothing to keep), a by-eye look at the screens, the release rows, the tried line, the remedy.py rerun,
# and the cleanup of the mda and the trial databases. A git revert of a binary MPR step commit conflicted (RT-1), so an
# option lives on its own branch and a FAIL abandons that branch: the gate branch is never rewritten.
#
#   remedy_apply.sh --config FILE [KEY=VALUE ...] <card key> <option> [--base BRANCH] [--apply CMD] [--human]
#                   [--from check|build|gate] [--dry-run]
#   remedy_apply.sh --config FILE [KEY=VALUE ...] --finish <card key> <option> PASS|FAIL [--eye SHOT] [--note TEXT]
#
# <card key> and <option> as remedy.py prints them (the card key of a generic card holds its subject:
# generic-kept-unproven:GenAICommons). The option is read from WORK/remediation.json (remedy.py --json, the default
# output): its mode, apply text and regate rungs.
#
# Config: KEY=VALUE lines (# comments; relative paths are relative to the config file); KEY=VALUE arguments win.
#   APP          the app clone (a git work tree; the .mpr is the only *.mpr in it)                       required
#   WORK         the run's work folder ($W): remediation.json, remedy-tried.txt                           required
#   GATE_CONF    the original gate.conf (gate.sh --config)                                    required with regate rungs
#   GATE_SEED    the original gate folder whose gate-summary.md seeds the trial's gate folder
#                (default: the folder of the gate summary remediation.json names)
#   CHECK_CMD    mx check of the app; {MPR} {APP} are replaced                                            required
#   BUILD_CMD    the build to an mda; {MPR} {MDA} {APP} are replaced; its output must say BUILD SUCCEEDED  required
#   WIDGETS_CMD  the widget refresh after the recipe (mx update-widgets {MPR} on MPR v1, mxcli-container.sh fix widgets
#                on MPR v2); a change is committed as "remedy: widgets refresh"                           optional
#   CLEANUP_CMD  run after the result is recorded: drop the trial databases; {LABEL} is replaced           optional
#   MIN_FREE_GB  free disk the build needs (default 12)
#   RETRIES      tries of a command that crashes with rc 139 (a segfault of the MPR v2 tools; default 3)
#   APPLY_DIR    where the recipes live (default WORK/remedy-apply): <card key with : as _>.<option>.sh, run in APP with
#                APP MPR WORK CARD OPTION BRANCH BASE in the environment; --apply CMD replaces it
#   REMEDY_ARGS  extra arguments for the remedy.py rerun, run in WORK (--kept-file, --release, --table ...); --work WORK and
#                --gate <GATE_SEED>/gate-summary.md are always given
#
# Phases:
#   apply  the app must be clean; branch remedy-<card>-<option> from BASE (default: the branch checked out; --base stacks
#          an option on an earlier one, as dw3 B on top of C); snapshot widgets/*.mpk; run the recipe; commit what it
#          left; report every widget mpk the recipe moved (RT-2); WIDGETS_CMD, committed when it changes something.
#          No recipe, a failing recipe, or no change: the branch is dropped, nothing recorded, exit 2 (a broken recipe
#          is not a verdict on the option).
#   check  CHECK_CMD: rc 0 and no error line, else FAIL.
#   build  disk check, then BUILD_CMD to WORK/remedy-<card>-<option>.mda; no BUILD SUCCEEDED is FAIL.
#   gate   gate.sh --config GATE_CONF --only <regate rungs without eye> --seed-from GATE_SEED with LABEL, GATE_DIR,
#          BUILD_LOG and NEW_MDA of this trial (NEW_MDA is exported, so PRE hooks read it). A FAIL rung is FAIL.
#          An INVALID or NOT RUN rung (other than release) is not judged: exit 4, branch kept, rerun with --from gate
#          (RT-11: a smoke walk hit the time limit and went INVALID).
#   pause  for a person: the regate names eye (a visual symptom, RT-6: shotdiff passed a doubled text at 4.8 percent and
#          smoke passed in-widget error alerts), or the release rung is not PASS (rows only a person closes).
#          WORK/remedy-todo-<card>-<option>.md lists the shots and the rows and the --finish commands; exit 5.
#   record the line `<card> <option> PASS|FAIL <evidence> [eye=<shot>] # branch ...` in WORK/remedy-tried.txt.
#          PASS: the app stays on the option's branch. FAIL: the app goes back to BASE; the branch stays as evidence
#          (abandoned, never merged). Then the mda is deleted, CLEANUP_CMD runs, and remedy.py runs again.
# --finish records a paused option: PASS needs --eye <shot path> when the regate names eye (the shot that was looked at).
#
# Exit: 0 = PASS recorded, 1 = FAIL recorded (branch abandoned), 2 = input or tool error (nothing recorded),
#       4 = not judged (a regate rung INVALID or NOT RUN; branch kept), 5 = paused for a person (TODO written).
# Env: UPG_REMEDY_BIN (where gate.sh and remedy.py are; default this folder), UPG_PYTHON (default python3).
set -u
here=$(cd "$(dirname "$0")" && pwd)
B=${UPG_REMEDY_BIN:-$here}; PY=${UPG_PYTHON:-python3}
die() { echo "remedy_apply: $*" >&2; exit 2; }
KEYS=" APP WORK GATE_CONF GATE_SEED CHECK_CMD BUILD_CMD WIDGETS_CMD CLEANUP_CMD MIN_FREE_GB RETRIES APPLY_DIR REMEDY_ARGS "
PATHKEYS=" APP WORK GATE_CONF GATE_SEED APPLY_DIR "
for k in $KEYS; do eval "V_$k="; done
setkey() {
  case "$KEYS" in *" $1 "*) ;; *) die "unknown key '$1' (known:$KEYS)";; esac
  local v=$2
  if [ -n "$3" ] && [ -n "$v" ]; then case "$PATHKEYS" in *" $1 "*) case $v in /*) ;; *) v=$3/$v;; esac;; esac; fi
  eval "V_$1=\$v"
}

config=""; dry=0; human=0; base=""; apply_cmd=""; from=""; finish=0; verdict=""; eye=""; note=""; POS=(); ARGKV=()
while [ $# -gt 0 ]; do
  case "$1" in
    --config) [ $# -ge 2 ] || die "--config needs a file"; config=$2; shift 2;;
    --dry-run) dry=1; shift;;
    --human) human=1; shift;;
    --base) [ $# -ge 2 ] || die "--base needs a branch"; base=$2; shift 2;;
    --apply) [ $# -ge 2 ] || die "--apply needs a command"; apply_cmd=$2; shift 2;;
    --from) [ $# -ge 2 ] || die "--from needs check, build or gate"; from=$2; shift 2
            case $from in check|build|gate) ;; *) die "--from $from: check, build or gate";; esac;;
    --finish) finish=1; shift;;
    --eye) [ $# -ge 2 ] || die "--eye needs a shot path"; eye=$2; shift 2;;
    --note) [ $# -ge 2 ] || die "--note needs a text"; note=$2; shift 2;;
    -h|--help) awk 'NR>1{if(!/^#/)exit; print}' "$0"; exit 0;;
    [A-Z]*=*) ARGKV+=("$1"); shift;;
    -*) die "unknown option '$1' (see --help)";;
    *) POS+=("$1"); shift;;
  esac
done
if [ -n "$config" ]; then
  [ -f "$config" ] || die "config file not found: $config"
  cdir=$(cd "$(dirname "$config")" && pwd)
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue;; *=*) ;; *) die "$config: not KEY=VALUE: $line";; esac
    setkey "${line%%=*}" "${line#*=}" "$cdir"
  done < "$config"
fi
for kv in ${ARGKV[@]+"${ARGKV[@]}"}; do setkey "${kv%%=*}" "${kv#*=}" "$PWD"; done
if [ $finish = 1 ]; then
  [ ${#POS[@]} = 3 ] || die "--finish <card key> <option> PASS|FAIL"
  verdict=${POS[2]}; case $verdict in PASS|FAIL) ;; *) die "--finish: verdict '$verdict' is not PASS or FAIL";; esac
else
  [ ${#POS[@]} = 2 ] || die "give <card key> <option> (see --help)"
fi
CARD=${POS[0]}; OPT=${POS[1]}
[ -n "$V_APP" ] && [ -d "$V_APP" ] || die "APP: no app folder (${V_APP:-unset})"
git -C "$V_APP" rev-parse --git-dir >/dev/null 2>&1 || die "APP $V_APP is not a git work tree"
[ -n "$V_WORK" ] && [ -d "$V_WORK" ] || die "WORK: no work folder (${V_WORK:-unset})"
W=$(cd "$V_WORK" && pwd); V_APP=$(cd "$V_APP" && pwd); JSON=$W/remediation.json; TRIED=$W/remedy-tried.txt
[ -f "$JSON" ] || die "no $JSON: run remedy.py --work $W first"
MPRS=("$V_APP"/*.mpr); [ ${#MPRS[@]} = 1 ] && [ -f "${MPRS[0]}" ] || die "APP $V_APP: want exactly one .mpr"
MPR=${MPRS[0]}
MINFREE=${V_MIN_FREE_GB:-12}; RETRIES=${V_RETRIES:-3}; APPLY_DIR=${V_APPLY_DIR:-$W/remedy-apply}

# the option from remediation.json: mode, regate, apply text, the gate summary it came from
info=$("$PY" - "$JSON" "$CARD" "$OPT" <<'EOF'
import json, shlex, sys
d = json.load(open(sys.argv[1]))
c = next((c for c in d.get("cards", []) if c["id"] == sys.argv[2]), None)
if not c:
    print("ERR=" + shlex.quote(f"no card {sys.argv[2]} in {sys.argv[1]} (cards: {', '.join(x['id'] for x in d.get('cards', []))})")); sys.exit()
o = next((o for o in c["options"] if o["option"] == sys.argv[3]), None)
if not o:
    print("ERR=" + shlex.quote(f"card {sys.argv[2]} has no option {sys.argv[3]} (options: {', '.join(x['option'] for x in c['options'])})")); sys.exit()
rg = [x.strip() for x in o.get("regate", "").split(",") if x.strip() and x.strip() != "-"]
for k, v in (("MODE", o["mode"]), ("WHY", o.get("why_human", "")), ("APPLY_TEXT", o.get("apply", "")),
             ("RUNGS", ",".join(x for x in rg if x != "eye")), ("EYE", "1" if "eye" in rg else "0"),
             ("STATUS", c.get("status", "")), ("GATE_SUMMARY", d.get("gate") or ""), ("DISPROVEN", o.get("disproven", ""))):
    print(f"{k}={shlex.quote(v)}")
EOF
) || die "could not read $JSON"
ERR=""; eval "$info"; [ -z "$ERR" ] || die "$ERR"
SEED=${V_GATE_SEED:-$( [ -n "$GATE_SUMMARY" ] && dirname "$GATE_SUMMARY")}
case $SEED in ''|/*) ;; *) SEED=$W/$SEED;; esac
[ -z "$SEED" ] || [ -d "$SEED" ] || { [ -d "$(dirname "$JSON")/$SEED" ] && SEED=$(dirname "$JSON")/$SEED; }
slug=$(printf '%s' "$CARD" | tr -c 'A-Za-z0-9._-' '-'); optl=$(printf '%s' "$OPT" | tr 'A-Z' 'a-z')
BR=remedy-$slug-$optl; LABEL=-remedy-$slug-$optl; GDIR=$W/gate$LABEL; MDA=$W/remedy-$slug-$optl.mda
LOG=$W/remedy-apply-$slug-$optl.log; STATE=$W/remedy-apply-$slug-$optl.state; TODO=$W/remedy-todo-$slug-$optl.md
BUILD_LOG=$W/remedy-build-$slug-$optl.log; CHECK_LOG=$W/remedy-check-$slug-$optl.log
RECIPE=${apply_cmd:-$APPLY_DIR/$(printf '%s' "$CARD" | tr ':' '_').$OPT.sh}
cur=$(git -C "$V_APP" symbolic-ref --short -q HEAD || echo "")

sub() { local s=$1; s=${s//\{MPR\}/$(printf %q "$MPR")}; s=${s//\{MDA\}/$(printf %q "$MDA")}; s=${s//\{APP\}/$(printf %q "$V_APP")}; s=${s//\{LABEL\}/$LABEL}; printf '%s' "$s"; }
run_retry() { # run_retry OUTFILE CMD: bash -c CMD, retried on rc 139 (RETRIES tries)
  local out=$1 cmd=$2 i rc=0
  for i in $(seq 1 "$RETRIES"); do
    (cd "$V_APP" && bash -c "$cmd") > "$out" 2>&1; rc=$?
    [ $rc = 139 ] || break
    echo "remedy_apply: rc 139 (crash) on try $i: retry" | tee -a "$LOG" >&2
  done
  return $rc
}
gitc() { git -C "$V_APP" "$@"; }
commit_all() { # commit_all MESSAGE: commit whatever is changed, quietly; prints the new short hash or nothing
  [ -z "$(gitc status --porcelain)" ] && return 0
  gitc add -A && gitc commit -q -m "$1" >/dev/null && gitc rev-parse --short HEAD
}
abandon() { # back to BASE, the branch dropped when it holds nothing worth keeping ($1 = drop)
  gitc checkout -q -f "$BASE" 2>/dev/null
  [ "${1:-}" = drop ] && gitc branch -q -D "$BR" 2>/dev/null
  rm -f "$STATE"
}
record() { # record PASS|FAIL EVIDENCE NOTE
  local v=$1 ev=$2 nt=$3 commits line
  commits=$(gitc log --format=%h "$BASE..$BR" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
  line="$CARD $OPT $v $ev # branch $BR on $BASE (${commits:-no commits})"
  [ $v = FAIL ] && line="$line, abandoned"
  [ -n "$nt" ] && line="$line; $nt"
  printf '%s\n' "$line" >> "$TRIED"
  echo "remedy_apply: recorded in $TRIED: $line"
  if [ $v = FAIL ]; then gitc checkout -q -f "$BASE" && echo "remedy_apply: app back on $BASE; $BR kept as evidence, never merged"
  else echo "remedy_apply: app stays on $BR (the option's fix)"; fi
  rm -f "$MDA" "$STATE"
  [ -z "$V_CLEANUP_CMD" ] || { (cd "$W" && bash -c "$(sub "$V_CLEANUP_CMD")") >> "$LOG" 2>&1 || echo "remedy_apply: WARN CLEANUP_CMD failed (see $LOG)" >&2; }
  local gs=""; [ -n "$SEED" ] && [ -f "$SEED/gate-summary.md" ] && gs="--gate $SEED/gate-summary.md"
  echo "remedy_apply: remedy.py again:"
  # shellcheck disable=SC2086
  (cd "$W" && "$PY" "$B/remedy.py" --work "$W" $gs $V_REMEDY_ARGS 2>&1) | sed 's/^/  /' | head -40
  rm -f "$TODO"
  [ $v = PASS ] && exit 0 || exit 1
}
already=$( [ -f "$TRIED" ] && grep -E "^$(printf '%s' "$CARD" | sed 's/[.[\*^$]/\\&/g') $OPT (PASS|FAIL) " "$TRIED" | head -1)

# --- finish a paused option ------------------------------------------------------------------------------------------
if [ $finish = 1 ]; then
  [ -f "$STATE" ] || die "no paused trial for $CARD $OPT ($STATE missing): run it first"
  # shellcheck disable=SC1090
  . "$STATE"
  [ -z "$already" ] || die "already recorded: $already"
  if [ $verdict = PASS ]; then
    [ "$EYE" = 0 ] || [ -n "$eye" ] || die "PASS of $CARD $OPT needs --eye <shot path>: its regate names eye (a by-eye screens verdict, RT-6)"
    [ -z "$eye" ] || [ -f "$eye" ] || die "--eye $eye: no such shot"
    record PASS "$GDIR/gate-summary.md${eye:+ eye=$eye}" "finished by a person${note:+: $note}"
  fi
  record FAIL "$GDIR/gate-summary.md${eye:+ eye=$eye}" "finished by a person${note:+: $note}"
fi

# --- preflight -------------------------------------------------------------------------------------------------------
[ -z "$already" ] || die "already tried: $already (remedy.py moves to the next option)"
if [ "$MODE" != AUTO-TRY ] && [ $human = 0 ]; then
  die "$CARD $OPT is HUMAN${WHY:+ ($WHY)}${DISPROVEN:+; DISPROVEN: $DISPROVEN}: a person chooses it; pass --human when they did"
fi
[ -n "$V_CHECK_CMD" ] || die "CHECK_CMD is not set"
[ -n "$V_BUILD_CMD" ] || die "BUILD_CMD is not set"
if [ -n "$RUNGS" ]; then
  [ -n "$V_GATE_CONF" ] && [ -f "$V_GATE_CONF" ] || die "GATE_CONF: no gate config (${V_GATE_CONF:-unset}); the regate rungs are $RUNGS"
  [ -n "$SEED" ] && [ -f "$SEED/gate-summary.md" ] || die "GATE_SEED: no gate-summary.md in '${SEED:-unset}' (the original gate folder seeds the trial's)"
fi
if [ -n "$from" ]; then
  [ -f "$STATE" ] || die "--from $from: no trial state $STATE (run without --from first)"
  # shellcheck disable=SC1090
  . "$STATE"
  gitc rev-parse -q --verify "refs/heads/$BR" >/dev/null || die "--from $from: no branch $BR"
else
  BASE=${base:-$cur}
  [ -n "$BASE" ] || die "the app is on a detached HEAD: give --base BRANCH"
  gitc rev-parse -q --verify "refs/heads/$BASE" >/dev/null || die "--base $BASE: no such branch"
  ! gitc rev-parse -q --verify "refs/heads/$BR" >/dev/null || die "branch $BR exists already (an earlier trial): --from check|build|gate resumes it, or delete it"
fi
GATE_CMD=(bash "$B/gate.sh" --config "$V_GATE_CONF" --only "$RUNGS" --seed-from "$SEED" "LABEL=$LABEL" "GATE_DIR=$GDIR")
GATE_CMD+=("BUILD_LOG=$BUILD_LOG" "NEW_MDA=$MDA")
if [ $dry = 1 ]; then
  echo "remedy_apply: dry run, nothing changed"
  echo "  card $CARD option $OPT ($MODE${STATUS:+, card $STATUS}); recipe: $RECIPE $( [ -n "$apply_cmd" ] || [ -f "$RECIPE" ] || echo "(MISSING)")"
  echo "  branch $BR from ${BASE}; check: $(sub "$V_CHECK_CMD"); build: $(sub "$V_BUILD_CMD")"
  [ -n "$RUNGS" ] && echo "  gate: NEW_MDA=$MDA ${GATE_CMD[*]}" || echo "  gate: no regate rungs"
  [ "$EYE" = 1 ] && echo "  pause: a by-eye look at the screens (regate names eye)"
  case ",$RUNGS," in *,release,*) echo "  pause when the release rung is not PASS (rows to close)";; esac
  exit 0
fi
echo "== $(date -u +%Y-%m-%dT%H:%MZ) $CARD $OPT" >> "$LOG"
save_state() { printf 'BASE=%q\nBR=%q\nEYE=%q\nGDIR=%q\nMDA=%q\n' "$BASE" "$BR" "$EYE" "$GDIR" "$MDA" > "$STATE"; }

# --- apply -----------------------------------------------------------------------------------------------------------
if [ -z "$from" ]; then
  [ -z "$(gitc status --porcelain)" ] || die "the app has uncommitted changes: commit or stash them first ($V_APP)"
  if [ -z "$apply_cmd" ] && [ ! -f "$RECIPE" ]; then
    die "no recipe for $CARD $OPT: write it as $RECIPE (run in the app folder; the row says: ${APPLY_TEXT:-nothing})"
  fi
  gitc checkout -q -b "$BR" "$BASE" || die "could not create branch $BR from $BASE"
  save_state
  snap=$(cd "$V_APP" && for f in widgets/*.mpk; do [ -f "$f" ] && printf '%s %s\n' "$(cksum < "$f" | tr -s ' ' '-')" "$f"; done)
  echo "remedy_apply: $CARD $OPT on branch $BR (from $BASE): recipe $RECIPE"
  if [ -n "$apply_cmd" ]; then rcmd=$apply_cmd; else rcmd="bash $(printf %q "$RECIPE")"; fi
  (cd "$V_APP" && APP=$V_APP MPR=$MPR WORK=$W CARD=$CARD OPTION=$OPT BRANCH=$BR BASE=$BASE bash -c "$rcmd") >> "$LOG" 2>&1
  rc=$?
  if [ $rc != 0 ]; then
    abandon drop
    die "the recipe failed (rc $rc, see $LOG): not a verdict on the option; fix the recipe (a git revert of an MPR step commit conflicts: RT-1)"
  fi
  h=$(commit_all "remedy: $CARD $OPT")
  if [ "$(gitc rev-list --count "$BASE..$BR")" = 0 ]; then abandon drop; die "the recipe changed nothing in $V_APP"; fi
  now=$(cd "$V_APP" && for f in widgets/*.mpk; do [ -f "$f" ] && printf '%s %s\n' "$(cksum < "$f" | tr -s ' ' '-')" "$f"; done)
  moved=$("$PY" - "$snap" "$now" <<'EOF'
import sys
a = dict(reversed(l.split(" ", 1)) for l in sys.argv[1].splitlines() if l.strip())
b = dict(reversed(l.split(" ", 1)) for l in sys.argv[2].splitlines() if l.strip())
for f in sorted(set(a) | set(b)):
    if f not in b: print(f"widget mpk removed: {f}")
    elif f not in a: print(f"widget mpk added: {f}")
    elif a[f] != b[f]: print(f"widget mpk changed: {f}")
EOF
)
  [ -z "$moved" ] || { echo "$moved" | sed 's/^/remedy_apply: /'; echo "$moved" >> "$LOG"; echo "remedy_apply: check that each moved widget mpk belongs to the option (a downgrade leaves the newer mpks, RT-2)"; }
  if [ -n "$V_WIDGETS_CMD" ]; then
    run_retry "$W/remedy-widgets-$slug-$optl.log" "$(sub "$V_WIDGETS_CMD")"; rc=$?
    [ $rc = 0 ] || { echo "remedy_apply: WIDGETS_CMD rc $rc (see $W/remedy-widgets-$slug-$optl.log); branch kept, rerun with --from check after a fix" >&2; exit 2; }
    h2=$(commit_all "remedy: widgets refresh ($CARD $OPT)"); [ -z "$h2" ] || echo "remedy_apply: widgets refresh committed $h2"
  fi
else
  gitc checkout -q "$BR" || die "could not check out $BR"
fi

# --- check -----------------------------------------------------------------------------------------------------------
if [ -z "$from" ] || [ "$from" = check ]; then
  run_retry "$CHECK_LOG" "$(sub "$V_CHECK_CMD")"; rc=$?
  nerr=$(grep -Eci '\[error\]|^error' "$CHECK_LOG")
  grep -Eqi '(^| )[1-9][0-9]* errors?' "$CHECK_LOG" && nerr=$((nerr + 1))
  if [ $rc != 0 ] || [ "${nerr:-0}" != 0 ]; then
    echo "remedy_apply: mx check rc $rc, error lines $nerr: FAIL"
    record FAIL "$CHECK_LOG" "mx check not clean (rc $rc, $nerr error lines)"
  fi
  echo "remedy_apply: mx check clean"
fi

# --- build -----------------------------------------------------------------------------------------------------------
if [ -z "$from" ] || [ "$from" != gate ]; then
  free=$(df -Pk "$W" | awk 'NR==2{print int($4/1048576)}')
  [ "${free:-0}" -ge "$MINFREE" ] || { echo "remedy_apply: ${free} GB free under $W, MIN_FREE_GB is $MINFREE: stop (branch kept, --from build)" >&2; exit 2; }
  run_retry "$BUILD_LOG" "$(sub "$V_BUILD_CMD")"; rc=$?
  if ! grep -q "BUILD SUCCEEDED" "$BUILD_LOG"; then
    echo "remedy_apply: build rc $rc, no BUILD SUCCEEDED: FAIL"
    record FAIL "$BUILD_LOG" "build failed (rc $rc)"
  fi
  echo "remedy_apply: built $MDA"
fi

# --- gate --------------------------------------------------------------------------------------------------------------
pause=""
if [ -n "$RUNGS" ]; then
  echo "remedy_apply: NEW_MDA=$MDA ${GATE_CMD[*]}"
  NEW_MDA=$MDA "${GATE_CMD[@]}" >> "$LOG" 2>&1; grc=$?
  S=$GDIR/gate-summary.md
  [ -f "$S" ] || { echo "remedy_apply: gate.sh rc $grc wrote no $S (see $LOG): not judged; --from gate" >&2; exit 4; }
  fails=""; notj=""
  for r in $(echo "$RUNGS" | tr ',' ' '); do
    v=$(grep -E "^\| [0-9]+ \| $r \| " "$S" | head -1 | awk -F' \\| ' '{print $3}')
    echo "remedy_apply: rung $r ${v:-missing}"
    case "$v" in
      PASS|'PASS*'|EXCEPT) ;;
      FAIL) fails="$fails $r";;
      *) if [ "$r" = release ]; then pause="$pause release"; else notj="$notj $r(${v:-missing})"; fi;;
    esac
  done
  [ -z "$fails" ] || record FAIL "$S" "regate FAIL:$fails"
  [ -z "$notj" ] || { echo "remedy_apply: not judged:$notj; fix the instrument and rerun with --from gate (branch $BR kept, nothing recorded)"; exit 4; }
fi
[ "$EYE" = 1 ] && pause="eye$pause"
pause=${pause# }
if [ -z "$pause" ]; then record PASS "${S:-$BUILD_LOG}" "regate PASS: ${RUNGS:-build only}"; fi

# --- pause for a person -----------------------------------------------------------------------------------------------
{
  echo "# Remedy trial paused: $CARD option $OPT"
  echo
  echo "Branch \`$BR\` (from \`$BASE\`), gate folder \`$GDIR\`. The automatic rungs ($RUNGS) did not FAIL. A person decides:"
  echo
  if [ "$EYE" = 1 ]; then
    echo "## By eye (RT-6: shotdiff and smoke pass this symptom)"
    echo
    echo "Open the after shots next to the before shots and look at the symptom of the card on every page it names:"
    bs=$(sed -n 's/^SMOKE_BEFORE_SHOTS=//p' "${V_GATE_CONF:-/dev/null}" 2>/dev/null | head -1)
    [ -n "$bs" ] && echo "- before: \`$bs\`"
    find "$GDIR" -name '*.png' 2>/dev/null | sort | head -60 | sed 's/^/- after: `/; s/$/`/'
    echo
  fi
  case " $pause " in *" release "*)
    echo "## Release rows"; echo
    echo "The release rung is not PASS: close the rows this option handles (release_impact.py --check), or say why they stay open."
    echo; grep -E "^\| [0-9]+ \| release \| " "$GDIR/gate-summary.md" 2>/dev/null; echo;;
  esac
  echo "## Then record it"
  echo
  echo "    bash $here/remedy_apply.sh --config ${config:-<remedy.conf>} --finish $CARD $OPT PASS$( [ "$EYE" = 1 ] && echo ' --eye <the shot you looked at>') [--note TEXT]"
  echo "    bash $here/remedy_apply.sh --config ${config:-<remedy.conf>} --finish $CARD $OPT FAIL --note 'what you saw'"
} > "$TODO"
echo "remedy_apply: PAUSED for a person ($pause): $TODO"
exit 5
