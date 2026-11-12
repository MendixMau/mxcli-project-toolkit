#!/usr/bin/env bash
# upgrade-pipeline.sh: run every FIXED step of a Mendix upgrade with no model, stop at the first step that needs judgment.
#
# Usage: upgrade-pipeline.sh (--app-zip PATH | --app-dir DIR) --source FULL --target FULL [--target2 FULL] --work DIR
#                            [--from STEP] [--only STEP] [--dry-run]
#   --app-zip PATH   a project zip/mpk, unpacked into <run>/app and put under its own git ("original" commit)
#   --app-dir DIR    an unpacked project folder (own git is created when it has none)
#   --to FULL        instead of --target/--target2: the version ladder picks the route (9.x to 11 goes through 10.24;
#                    --via 10.24.x.y names that toolset, else the newest mxbuild-10.24.* in UPG_TOOLS) and writes <work>/ladder.json.
#   --source/--target/--target2  FULL versions (10.24.26.123458; 11.x may be 11.15.0). With --target2 the script runs
#                    rung 1 (source -> target), then calls itself for rung 2 (target -> target2) in <work>/rung2.
#   --work DIR       $WORK of steps/*.md (state/, logs/, evidence). Sources $WORK/env.sh or $RUN/env.sh (bin/cloud/setup.sh).
#   --from STEP      forget the done markers of STEP and every later step, then run from there
#   --only STEP      run just that step (even when done)
#   --dry-run        print the commands, run nothing
#   --cockpit        run no step: only regenerate $WORK/COCKPIT.html (needs just --work)
# Steps, in order: fetch triage baseline basewalk propose convert update build after afterwalk journeys heal diff gate
# heal (steps/heal.md): classifies every failing row, heals what belongs to the test (start noise, selection-gated buttons, a runner
# that did not run, outside calls via apimock, known harness log lines) and reruns only the affected journeys, at most 2 rounds.
# UPG_HEAL=0 turns it off (journeys then stops on a failure as before). Resume it with --from heal.
# Each finished step writes $WORK/state/<step>.done and is skipped on the next run. Logs: $WORK/logs/<step>.log.
# Judgment stops write $WORK/NEEDS-JUDGMENT.md. Exit codes:
#    0 gate PASS, nothing left for a person
#    2 usage / version-path error
#    3 missing tool or setup (run bin/cloud/setup.sh), or an mxcli of another version than the run's (bin/mxcli_pin.sh)
#    4 a fixed step failed unexpectedly (see the log named in the message)
#   10 mx check / mxbuild / quick start errors after convert+update: repair needed (steps/repair.md)
#   11 journeys INVALID or FAIL on the old app or the new one: fix the journey or write the todo (steps/journeys.md)
#   12 diff / gate REVIEW, FAIL or INVALID items need a comparison by a person (steps/gate.md). A FAIL is never a pass.
#   13 module plan missing, or a module kept / a data-bearing finding needs a decision (steps/upgrade.md)
#   14 the upgrade proposal awaits sign-off ($WORK/PROPOSAL.md section 6, steps/propose.md); also when a plan input changed
#      after the sign-off (the sign-off is cleared). Nothing in the app model has changed yet.
#   15 the owner paused the run on purpose (`Status: PAUSED <reason>` in PROPOSAL.md); NEEDS-JUDGMENT.md has the resume command
# Interview mode unattended (env UPG_INTERVIEW_MODE=unattended, or a line `Interview mode: unattended` in $WORK/interview-mode.txt):
# the propose step signs nothing, records ASSUMED (unattended) in DECISIONS.md, goes on, and every report says 'proposal not signed'.
# Decisions (bin/decisions.py): at the start of the run and of every step the pipeline applies $WORK/decisions.json (the page buttons
# and the chat share it); after every step, and when a step stops, it regenerates $WORK/COCKPIT.html (bin/cockpitpage.py).
# Hidden options for rung 2 (set by this script): --db NAME --old-mda PATH --seed-from DB
set -Eeuo pipefail

ARGS_ORIG=("$@")
SELF=$(readlink -f "${BASH_SOURCE[0]}")
TK="$(cd "$(dirname "$SELF")/../.." && pwd)"
APP_ZIP=""; APP_DIR_ARG=""; SOURCE=""; TARGET=""; TARGET2=""; WORK=""; TO=""; VIA=""
FROM=""; ONLY=""; DRY=0; COCKPIT=0; DB_ARG=""; OLD_MDA=""; SEED_FROM=""

STEPS=(fetch triage baseline basewalk propose convert update build after afterwalk journeys heal apidirect diff gate)
SMOKE_PW='Smoke-only-1!'
M2EE_PASS='m2ee-local-only'          # runapp.py's admin API password
PGC=mig-pg                           # runapp.py's Postgres container

usage_die() { echo "upgrade-pipeline.sh: $*" >&2; echo "usage: $0 (--app-zip PATH|--app-dir DIR) --source FULL --target FULL [--target2 FULL] --work DIR [--from STEP] [--only STEP] [--dry-run]" >&2; exit 2; }
die4() { echo "upgrade-pipeline.sh: $*" >&2; exit 4; }
on_err() { echo "upgrade-pipeline.sh: unexpected failure (exit $1) at line $2 in step '${STEP:-none}'; log: ${LOG:-none}" >&2; exit 4; }
trap 'on_err $? $LINENO' ERR

while [ $# -gt 0 ]; do
  case "$1" in
    --app-zip) APP_ZIP=${2:-}; shift 2 ;;
    --app-dir) APP_DIR_ARG=${2:-}; shift 2 ;;
    --source) SOURCE=${2:-}; shift 2 ;;
    --target) TARGET=${2:-}; shift 2 ;;
    --target2) TARGET2=${2:-}; shift 2 ;;
    --to) TO=${2:-}; shift 2 ;;
    --via) VIA=${2:-}; shift 2 ;;
    --work) WORK=${2:-}; shift 2 ;;
    --from) FROM=${2:-}; shift 2 ;;
    --only) ONLY=${2:-}; shift 2 ;;
    --db) DB_ARG=${2:-}; shift 2 ;;
    --old-mda) OLD_MDA=${2:-}; shift 2 ;;
    --seed-from) SEED_FROM=${2:-}; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --cockpit) COCKPIT=1; shift ;;
    -h|--help) sed -n 2,41p "$SELF"; exit 0 ;;
    *) usage_die "unknown argument: $1" ;;
  esac
done

[ -n "$WORK" ] || usage_die "--work is required"
if [ "$COCKPIT" = 1 ]; then   # step-free: regenerate the cockpit page and stop
  [ -d "$WORK" ] || usage_die "no such folder: $WORK"
  WORK=$(cd "$WORK" && pwd)
  exec python3 "$TK/bin/cockpitpage.py" --work "$WORK" --out "$WORK/COCKPIT.html"
fi
[ -n "$SOURCE" ] || usage_die "--source is required"
# --to: the version ladder. The pipeline picks the route from the start version: 9.x and 10.x below 10.24 go through 10.24
# (--via, else the newest mxbuild-10.24.* toolset in UPG_TOOLS) before 11; anything else is one rung.
if [ -n "$TO" ]; then
  [ -z "$TARGET$TARGET2" ] || usage_die "--to replaces --target and --target2: give one or the other"
  _sm=${SOURCE%%.*}; _sr=${SOURCE#*.}; _sn=${_sr%%.*}; _tm=${TO%%.*}
  if [ "$_tm" -ge 11 ] && { [ "$_sm" -le 9 ] || { [ "$_sm" -eq 10 ] && [ "$_sn" -lt 24 ]; }; }; then
    if [ -z "$VIA" ]; then
      VIA=$(ls -d "${UPG_TOOLS:-$(dirname "$WORK")/tools}"/mxbuild-10.24.* 2>/dev/null | sed 's#.*/mxbuild-##' | sort -t. -k3,3n -k4,4n | tail -1 || true)
      [ -n "$VIA" ] || usage_die "$SOURCE goes to $TO through 10.24: no mxbuild-10.24.* toolset found, give --via 10.24.x.y"
    fi
    TARGET=$VIA; TARGET2=$TO
  else
    TARGET=$TO
  fi
  echo "upgrade-pipeline.sh: version ladder $SOURCE -> $TARGET${TARGET2:+ -> $TARGET2}"
fi
[ -n "$TARGET" ] || usage_die "--target is required"
{ [ -n "$APP_ZIP" ] || [ -n "$APP_DIR_ARG" ]; } || usage_die "one of --app-zip / --app-dir is required"
{ [ -z "$APP_ZIP" ] || [ -z "$APP_DIR_ARG" ]; } || usage_die "--app-zip and --app-dir are exclusive"
[ -z "$APP_ZIP" ] || [ -f "$APP_ZIP" ] || usage_die "no such file: $APP_ZIP"
[ -z "$APP_DIR_ARG" ] || [ -d "$APP_DIR_ARG" ] || usage_die "no such folder: $APP_DIR_ARG"
for v in "$SOURCE" "$TARGET" ${TARGET2:+"$TARGET2"}; do
  [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || usage_die "'$v' is not a full version (10.24.26.123458)"
done
for s in "$FROM" "$ONLY"; do
  [ -z "$s" ] || [[ " ${STEPS[*]} " == *" $s "* ]] || usage_die "unknown step '$s' (steps: ${STEPS[*]})"
done

major() { echo "${1%%.*}"; }
minor() { local r=${1#*.}; echo "${r%%.*}"; }
# Version path rules (SKILL.md): 9 goes to 10, 10.x goes to 10.24 first, then to 11.
path_check() { # from to
  local fm tm
  fm=$(major "$1"); tm=$(major "$2")
  [ "$tm" -ge "$fm" ] || usage_die "target $2 is older than source $1"
  if [ "$fm" -le 9 ] && [ "$tm" -ge 11 ]; then usage_die "9.x goes to 10.24 first: use --target 10.24.x --target2 $2"; fi
  if [ "$fm" -eq 10 ] && [ "$tm" -ge 11 ] && [ "$(minor "$1")" -lt 24 ]; then
    usage_die "10.$(minor "$1") may not go to $2: take 10.24 first (--target 10.24.x --target2 $2)"; fi
}
path_check "$SOURCE" "$TARGET"
if [ -n "$TARGET2" ]; then
  [ "$(major "$TARGET2")" -ge 11 ] && [ "$(major "$TARGET")" -eq 10 ] && [ "$(minor "$TARGET")" -eq 24 ] ||
    usage_die "--target2 is the 11.x rung and --target must be 10.24.x"
fi

mkdir -p "$WORK"; WORK=$(cd "$WORK" && pwd)
mkdir -p "$WORK/state" "$WORK/logs"
# the route of this run, for the cockpit's version ladder (rung 2 keeps the one rung 1 wrote)
[ "$(basename "$WORK")" = rung2 ] || [ "$DRY" = 1 ] ||
  printf '{"route": ["%s", "%s"%s]}\n' "$SOURCE" "$TARGET" "${TARGET2:+, \"$TARGET2\"}" > "$WORK/ladder.json"

# ---- env.sh from bin/cloud/setup.sh: TK RUN MXCLI UPG_EXTRA UPG_UPDATE_CMD UPG_TOOLS ----
: "${RUN:=$(dirname "$WORK")}"
set +u
if [ -f "$WORK/env.sh" ]; then . "$WORK/env.sh"; elif [ -f "$RUN/env.sh" ]; then . "$RUN/env.sh"; fi
set -u
: "${RUN:=$(dirname "$WORK")}"
: "${UPG_TOOLS:=$RUN/tools}"
: "${MXCLI:=${UPG_MXCLI:-}}"
B="$TK/bin"
PORT_OFF=${PORT_OFF:-0}
APP_PORT=$((8080 + PORT_OFF)); ADMIN_PORT=$((8090 + PORT_OFF))
export TK RUN UPG_TOOLS
export UPG_ROOT="$RUN"
[ -z "${MXCLI:-}" ] || export UPG_MXCLI="$MXCLI"
export UPG_EXTRA="${UPG_EXTRA:-}"
export UPG_MXCLI_STATE="$WORK/state/mxcli-version"   # stepupdate.sh checks it too (bin/mxcli_pin.sh)
# two versions (--target2): every step of rung 1 belongs to the version of --target; rung 2 gets its own (set below), so one
# steps.jsonl and one COCKPIT.html cover 9 to 11 and gate 2 never rewrites the tests of gate 1 (steps.py UPG_PHASE)
[ -z "$TARGET2" ] || export UPG_PHASE=$(echo "$TARGET" | cut -d. -f1-3)
export UPG_STEPS_WORK="$WORK"   # steps.py trailer reads <work>/steps.jsonl: commits that fit a step carry Upgrade-Step (changelog.py -> steps.py done)
# F2 (Purchase Request 10.24, real run): mxrun.sh mounts only the run folder, so an --app-dir outside it was accepted and
# then failed at baseline with mxbuild's "Project file does not exist". Refuse it here, before any step runs.
if [ -n "$APP_DIR_ARG" ]; then
  _app=$(cd "$APP_DIR_ARG" && pwd -P); _run=$(mkdir -p "$RUN" && cd "$RUN" && pwd -P)
  case "$_app/" in "$_run"/*) ;; *)
    echo "upgrade-pipeline.sh: --app-dir $APP_DIR_ARG is outside the run folder $RUN; the containers only see the run folder. Move or copy the app under it (e.g. $RUN/app) and rerun." >&2
    exit 3 ;; esac
fi

APP=""; MPR=""
STEP=""; LOG="$WORK/logs/pipeline.log"
NJ_CODE=0; NJ_TMP="$WORK/state/nj.tmp"
APPS_UP=()

# ---- helpers ----
say() { printf '%s\n' "$*"; }
quoted() { printf ' %q' "$@"; }
x() { # run a command, append its output to the step log, return its exit code (never exits)
  if [ "$DRY" = 1 ]; then printf '+'; quoted "$@"; printf '\n'; return 0; fi
  { printf '+'; quoted "$@"; printf '\n'; } >> "$LOG"
  "$@" >> "$LOG" 2>&1
}
xo() { # xo FILE cmd...: like x, but the output goes to FILE (also logged by name)
  local out=$1; shift
  if [ "$DRY" = 1 ]; then printf '+'; quoted "$@"; printf ' > %q\n' "$out"; return 0; fi
  { printf '+'; quoted "$@"; printf ' > %q\n' "$out"; } >> "$LOG"
  "$@" > "$out" 2>&1
}
must() { local rc=0; x "$@" || rc=$?; [ "$rc" = 0 ] || die4 "step '$STEP': command failed (exit $rc): $*  (log: $LOG)"; }
note() { [ "$DRY" = 1 ] || printf '%s: %s\n' "$STEP" "$*" >> "$WORK/state/notes.txt"; }
need_tool() { # need_tool CMD  -> exit 3 when missing (dry-run: warn)
  command -v "$1" > /dev/null 2>&1 && return 0
  if [ "$DRY" = 1 ]; then say "WARN missing tool: $1"; return 0; fi
  echo "upgrade-pipeline.sh: missing tool '$1'. Run: bash $B/cloud/setup.sh --run-dir $RUN --source $SOURCE --target $TARGET${TARGET2:+ --target2 $TARGET2}" >&2
  exit 3
}
need_path() { # need_path PATH WHAT
  [ -e "$1" ] && return 0
  if [ "$DRY" = 1 ]; then say "WARN missing $2: $1"; return 0; fi
  echo "upgrade-pipeline.sh: missing $2: $1. Run: bash $B/cloud/setup.sh --run-dir $RUN --source $SOURCE --target $TARGET${TARGET2:+ --target2 $TARGET2}" >&2
  exit 3
}

# ---- judgment stops ----
nj_add() { # nj_add CODE "title" "text"
  [ "$NJ_CODE" != 0 ] || NJ_CODE=$1
  { printf '\n## %s (exit %s)\n\n%s\n' "$2" "$1" "$3"; } >> "$NJ_TMP"
}
nj_file() { # nj_file CODE "title" FILE [lines] [grep-pattern]: first lines of a file (optionally only lines matching)
  local body="(file not found: $3)"
  if [ -f "$3" ]; then
    if [ -n "${5:-}" ]; then body=$(grep -E "$5" "$3" | head -n "${4:-20}" || true); else body=$(head -n "${4:-20}" "$3" || true); fi
    body=$(printf 'file: %s\n\n```\n%s\n```' "$3" "$body")
  fi
  nj_add "$1" "$2" "$body"
}
rerun_cmd() { # the command that resumes at the current step: the run's own --from is dropped so the hint carries exactly one
  local a=() skip=0 v
  for v in ${ARGS_ORIG[@]+"${ARGS_ORIG[@]}"}; do
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    case "$v" in --from) skip=1; continue ;; --from=*) continue ;; esac
    a+=("$v")
  done
  printf '%s%s --from %s' "$SELF" "$(quoted ${a[@]+"${a[@]}"})" "$STEP"
}
nj_flush() { # write NEEDS-JUDGMENT.md and exit with the first recorded code
  [ "$NJ_CODE" != 0 ] || return 0
  {
    printf '# NEEDS JUDGMENT: step %s, exit %s\n\nrun folder: %s\nwork: %s\nsource %s -> target %s\n' "$STEP" "$NJ_CODE" "$RUN" "$WORK" "$SOURCE" "$TARGET"
    printf 'Rule: the items below are pending, not passed: a REGRESSION is fixed, the rest are decided in writing (allow/approved files named in steps/*.md), then rerun:\n\n'
    printf '    %s\n' "$(rerun_cmd)"
    cat "$NJ_TMP"
  } > "$WORK/NEEDS-JUDGMENT.md"
  cockpit_regen
  say "STOP    $STEP: needs judgment (exit $NJ_CODE), see $WORK/NEEDS-JUDGMENT.md"
  exit "$NJ_CODE"
}

# decisions.json (page + chat) -> the files the steps read; the cockpit page from the run's files. Neither can fail a step.
decisions_apply() {
  [ "$DRY" != 1 ] || return 0
  python3 "$B/decisions.py" apply --work "$WORK" >> "$WORK/logs/decisions.log" 2>&1 || true
}
cockpit_regen() {
  [ "$DRY" != 1 ] || return 0
  python3 "$B/cockpitpage.py" --work "$WORK" --out "$WORK/COCKPIT.html" >> "$WORK/logs/decisions.log" 2>&1 || true
  # rung 2 also refreshes the cockpit of rung 1, so the run keeps one page from start to end
  [ -z "${UPG_COCKPIT_OUT:-}" ] || [ ! -f "$WORK/COCKPIT.html" ] || cp "$WORK/COCKPIT.html" "$UPG_COCKPIT_OUT" 2>/dev/null || true
  # UPG_COCKPIT_HISTORY=1 keeps every version of the page (a demo video shows the cockpit filling up), next to the one cockpit
  if [ "${UPG_COCKPIT_HISTORY:-0}" = 1 ] && [ -f "$WORK/COCKPIT.html" ]; then
    local h; h=$(dirname "${UPG_COCKPIT_OUT:-$WORK/COCKPIT.html}")/cockpit-history; mkdir -p "$h"
    cp "$WORK/COCKPIT.html" "$h/$(date +%Y%m%d-%H%M%S)-$(basename "$(dirname "$WORK/x")").html" 2>/dev/null || true
  fi
}

# ---- Postgres / apps ----
db_exists() { # db_exists NAME
  [ "$DRY" = 1 ] && return 1
  [ -n "$(docker exec "$PGC" psql -U mendix -tAc "SELECT 1 FROM pg_database WHERE datname='$1'" 2> /dev/null || true)" ]
}
fresh_name() { # fresh_name BASE: a database name no earlier snapshot, walk or probe used (ledger) and that does not exist
  local n=$1 i=1
  while db_exists "$n" || { [ -f "$WORK/db-ledger.txt" ] && grep -q "^$n " "$WORK/db-ledger.txt"; }; do i=$((i + 1)); n="${1}_r$i"; done
  echo "$n"
}
copy_db() { must docker exec "$PGC" createdb -U mendix -T "$1" "$2"; }
mark_used() { must python3 "$B/snapshot.py" --ledger "$WORK/db-ledger.txt" --mark-used "$1" --use "$2"; }
psql_str() { echo "docker exec -i $PGC psql -U mendix -d $1"; }

# Where the walks and journeys sign in: env UPG_LOGIN_PATH, else the first line of $WORK/login-path.txt, else /login.html.
# An app whose login.html is an SSO redirect needs e.g. /login-with-mendixsso-button.html (seen on a 10.24 app).
login_path() { local p="${UPG_LOGIN_PATH:-}"; [ -n "$p" ] || p=$(head -n1 "$WORK/login-path.txt" 2> /dev/null || true); echo "${p:-/login.html}"; }
runenv() { # env words for runapp.py
  RUNENV=("WORKDIR=$WORK" "UPG_TOOLS=$UPG_TOOLS" "UPG_SESSION_TIMEOUT=30000" "PORT_OFF=$PORT_OFF")
  if [ -s "$WORK/env-values.json" ]; then RUNENV+=("CONST_OVERRIDES=$(cat "$WORK/env-values.json")"); fi
  # heal reruns: the apimock stand-in's and the NATS broker's constant overrides, merged under the person's env-values.json (theirs win)
  local src=()
  if [ -f "$WORK/state/heal-standin" ] && [ -s "$WORK/apimock/overrides.json" ]; then src+=("$WORK/apimock/overrides.json"); fi
  if { [ -f "$WORK/state/heal-nats" ] || nats_on; } && [ -s "$WORK/natsfixture/overrides.json" ]; then src+=("$WORK/natsfixture/overrides.json"); fi
  if [ "${#src[@]}" -gt 0 ]; then
    [ -s "$WORK/env-values.json" ] && src+=("$WORK/env-values.json")
    python3 -I -c '
import json, sys, os
ov = {}
for f in sys.argv[1:-1]:
    if os.path.isfile(f) and os.path.getsize(f):
        ov.update(json.load(open(f)))
json.dump(ov, open(sys.argv[-1], "w"), indent=1)' "${src[@]}" "$WORK/state/const-heal.json"
    RUNENV+=("CONST_OVERRIDES=$WORK/state/const-heal.json")
  fi
}
infra_rc() { # infra_rc RC NAME: runapp.py exit 3 is an environment fault (F21: a taken port), never a judgment
  [ "$1" != 3 ] || { echo "upgrade-pipeline.sh: $2 could not start: environment fault, see runapp INFRA line in $LOG" >&2; exit 3; }
}
app_up() { # app_up NAME MDA FULLVER DB  -> 0 started
  local rc=0
  runenv
  x env "${RUNENV[@]}" python3 "$B/runapp.py" start "$1" "$2" "$3" "$4" || rc=$?
  infra_rc "$rc" "$1"
  [ "$rc" != 0 ] || APPS_UP+=("$1")
  return "$rc"
}
app_down() {
  runenv
  x env "${RUNENV[@]}" python3 "$B/runapp.py" stop "$1" || true
  local keep=() a
  for a in "${APPS_UP[@]:-}"; do [ -z "$a" ] || [ "$a" = "$1" ] || keep+=("$a"); done
  APPS_UP=("${keep[@]:-}")
}
# ---- step timing ($WORK/state/timing.tsv) ----
# One row per ATTEMPT of a step: step, start (UTC), end (UTC), exit code. Appended, never rewritten: a resumed or re-run step
# gets a new row. bin/runlog.py reads it: machine time = the sum of the rows; person wait = the gap after a row that stopped
# for a person (exit 10 to 15, NEEDS-JUDGMENT.md) until the pipeline next ran. A failure to write a row never fails the run.
TIMING_STEP=""; TIMING_START=""
now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }
timing_open() { # timing_open STEP
  [ "$DRY" != 1 ] || return 0
  TIMING_STEP=$1; TIMING_START=$(now_utc)
}
timing_close() { # timing_close EXITCODE
  [ -n "$TIMING_STEP" ] || return 0
  local f="$WORK/state/timing.tsv" end
  end=$(now_utc)
  { [ -s "$f" ] || printf 'step\tstart_utc\tend_utc\texit\n' > "$f"; printf '%s\t%s\t%s\t%s\n' "$TIMING_STEP" "$TIMING_START" "$end" "$1" >> "$f"; } 2> /dev/null || true
  TIMING_STEP=""
}
cleanup() {
  local a rc=$?
  timing_close "$rc" || true   # the step that is stopping (exit 4, a judgment stop, an error) gets its row with its own exit code
  # run log (bin/runlog.py): a gate step that stops for judgment still leaves its row; the exit code stays the step's own
  if [ "${STEP:-}" = gate ] && [ "${DRY:-0}" != 1 ] && [ -z "${RUNLOG_DONE:-}" ]; then record_runlog || true; fi
  for a in "${APPS_UP[@]:-}"; do [ -z "$a" ] || { runenv; env "${RUNENV[@]}" python3 "$B/runapp.py" stop "$a" > /dev/null 2>&1 || true; }; done
}
trap cleanup EXIT

# BT-10: a full disk reads as an app defect ("An error occurred while creating the deployment package"). Check before the
# heavy steps (exit 3, environment fault) and name the cause when a build fails. Threshold: UPG_MIN_FREE_MB (default 2000).
disk_gate() { # disk_gate STEP: stop before a heavy step when the disk is nearly full
  [ "$DRY" = 1 ] && return 0
  local out rc=0
  out=$("$B/diskcheck.sh" --need-mb "${UPG_MIN_FREE_MB:-2000}" "$WORK") || rc=$?
  [ "$rc" = 0 ] || { echo "upgrade-pipeline.sh: step '$1': $out" >&2; exit 3; }
}
disk_cause() { # disk_cause [LOG]: after a failed build, a judgment item that names a full disk first (nothing when the disk is fine)
  [ "$DRY" = 1 ] && return 0
  local out rc=0
  out=$("$B/diskcheck.sh" --need-mb 300 --log "${1:-$LOG}" "$WORK") || rc=$?
  [ "$rc" = 0 ] || nj_add 10 "DISK FULL, not an app defect" "$out"
}

# ---- toolset / project helpers ----
mxw() { if [ "$(major "$1")" -le 9 ]; then echo "$B/mx9.sh"; else echo "$B/mx10.sh"; fi; }
heavy() { # heavy LABEL VER tool args...: a mx/mxbuild call under the heavy lock (steps/repair.md)
  local label=$1 ver=$2; shift 2
  "$B/heavy-lock.sh" "$label" "$(mxw "$ver")" "$ver" "$@"
}
mxcli_run() { if [ -n "${MXCLI:-}" ] && [ -x "$MXCLI" ]; then "$MXCLI" "$@"; else "$B/mxcli-container.sh" "$@"; fi; }
git_app() { git -C "$APP" -c user.name="upgrade-pipeline" -c user.email="upgrade-pipeline@localhost" "$@"; }
ensure_gitignore() {
  local f="$APP/.gitignore" l
  for l in '.claude/' '.mxcli/' '.stepupdate/' 'deployment/'; do
    grep -qxF "$l" "$f" 2> /dev/null || printf '%s\n' "$l" >> "$f"
  done
}
commit_app() { # commit_app "subject" KIND RULE: commit all changes in the app repo when there are any. Every toolkit commit
  # carries the trailers Changed-By: toolkit and Upgrade-Change: KIND RULE (trust.md section 3; bin/changelog.py reads them), and
  # Upgrade-Step: S-n when the step records know a step for that kind (steps.py trailer; UPG_STEPS_WORK is the work folder, exported below)
  [ "$DRY" = 1 ] && { say "+ git -C $APP commit -am '$1' (Upgrade-Change: $2 $3)"; return 0; }
  git_app add -A > /dev/null
  git_app diff --cached --quiet || git_app commit -q -m "$1" -m "$(printf 'Changed-By: toolkit\nUpgrade-Change: %s %s' "$2" "$3"; t=$(python3 "$B/steps.py" trailer --kind "$2" 2> /dev/null); [ -z "$t" ] || printf '\n%s' "$t")" >> "$LOG" 2>&1
}
resolve_app() {
  if [ -f "$WORK/state/app-dir" ]; then APP=$(cat "$WORK/state/app-dir")
  elif [ -n "$APP_DIR_ARG" ]; then APP=$(cd "$APP_DIR_ARG" && pwd)
  else APP="$RUN/app"; fi
  MPR=""
  if [ -d "$APP" ]; then
    local list=() f
    for f in "$APP"/*.mpr; do [ -e "$f" ] && list+=("$f"); done
    [ "${#list[@]}" -ne 1 ] || MPR=${list[0]}
    [ "${#list[@]}" -le 1 ] || die4 "more than one .mpr in $APP: ${list[*]}"
  fi
  [ -n "$MPR" ] || MPR="$APP/<app>.mpr"
}
project_version() { python3 "$B/mxversion.py" "$1" 2> /dev/null || true; }
open_errors() { # open_errors CHECKLOG -> number of errors
  local n
  n=$(grep -oE 'The app contains: *[0-9]+ errors' "$1" 2> /dev/null | grep -oE '[0-9]+' | head -n 1 || true)
  [ -n "$n" ] || n=$(grep -c '^\[error\]' "$1" 2> /dev/null || true)
  echo "${n:-0}"
}
roles_of_plan() { # roles_of_plan plan.json -> comma list of the non-guest roles of the smoke-walk plan
  python3 -I -c '
import json, sys
p = json.load(open(sys.argv[1]))
print(",".join(r["role"] for r in p.get("roles", []) if r.get("role") and r["role"] != p.get("guest_role")))' "$1"
}
write_users() { # write_users ROLES out.json: {"<Role>": {"user": "smoke_<role>", "pass": PW}}
  python3 -I -c '
import json, sys
roles, out, pw = sys.argv[1], sys.argv[2], sys.argv[3]
json.dump({r: {"user": "smoke_" + r.lower(), "pass": pw} for r in roles.split(",") if r}, open(out, "w"), indent=1)' "$1" "$2" "$SMOKE_PW"
}
user_args() { # user_args ROLES -> sets UARGS for smokewalk.js
  UARGS=(); local r
  IFS=',' read -ra _rl <<< "$1"
  for r in "${_rl[@]}"; do [ -z "$r" ] || UARGS+=(--user "$r=smoke_${r,,}:$SMOKE_PW"); done
}
mda_old() { if [ -n "$OLD_MDA" ]; then echo "$OLD_MDA"; else echo "$WORK/old-$SOURCE.mda"; fi; }
mda_new() { echo "$WORK/new-$TARGET.mda"; }

# DB names: <X> working, <X>_frozen never started.
if [ -n "$DB_ARG" ]; then X=$DB_ARG
else X="upg_$(basename "$RUN" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_\n' '_')"; fi
X_FROZEN="${X}_frozen"
[[ "$X" =~ ^[a-z0-9_]+$ ]] || usage_die "database name '$X' must be lower case letters, digits, underscore (use --db)"

preflight() {
  local t
  # BT-8: `--only propose` reads triage outputs only: no toolset, runtime or mxcli is needed, so none is demanded (a worker
  # who had deleted the 300 MB source runtime to make disk room could not regenerate PROPOSAL.md)
  local toolfree=0
  [ "$ONLY" != propose ] || toolfree=1
  for t in docker zsh git python3 node; do [ "$toolfree" = 1 ] && [ "$t" = docker ] && continue; need_tool "$t"; done
  [ -z "$APP_ZIP" ] || need_tool unzip
  if [ "$DRY" != 1 ] && [ "$toolfree" = 0 ]; then docker info > /dev/null 2>&1 || { echo "upgrade-pipeline.sh: docker daemon not running (setup.sh step docker)" >&2; exit 3; }; fi
  [ "$toolfree" = 0 ] || return 0
  need_path "$UPG_TOOLS/mxbuild-$SOURCE" "source mxbuild toolset"
  need_path "$UPG_TOOLS/mxbuild-$TARGET" "target mxbuild toolset"
  local v
  for v in "$SOURCE" "$TARGET" ${TARGET2:+"$TARGET2"}; do
    [ "$DRY" = 1 ] && continue
    ls -d "$UPG_TOOLS/runtime-$v" "$UPG_TOOLS/runtime-${v%.*}" > /dev/null 2>&1 || need_path "$UPG_TOOLS/runtime-$v" "runtime $v"
  done
  [ -z "$TARGET2" ] || need_path "$UPG_TOOLS/mxbuild-$TARGET2" "rung 2 mxbuild toolset"
  [ -n "${MXCLI:-}" ] && [ -x "${MXCLI:-}" ] || need_path "$UPG_TOOLS/mxcli-linux" "mxcli (MXCLI in env.sh, or tools/mxcli-linux)"
  [ -x "$B/heavy-lock.sh" ] || need_path "$B/heavy-lock.sh(+x)" "toolkit scripts"
}

# =====================================================================================================
# Steps
# =====================================================================================================

# fetch: unpack, put the project under git, record the original MPR. Script: unzip, git, mxversion.py
step_fetch() {
  if [ -n "$APP_ZIP" ]; then
    APP="$RUN/app"
    if [ -z "$(ls -A "$APP" 2> /dev/null || true)" ]; then
      must mkdir -p "$APP"
      # BT-9: a package may ship the build output deployment/ next to the .mpr (DOCGEN: 858 MB). mxbuild writes it again and
      # ensure_gitignore ignores it, so it is not unpacked; the zip itself is untouched. Only the folder beside the .mpr.
      local mprpath dpre=""
      mprpath=$(unzip -Z1 "$APP_ZIP" 2> /dev/null | grep -E '\.mpr$' | awk -F/ '{print NF, $0}' | sort -n | head -n 1 | cut -d' ' -f2- || true)
      case "$mprpath" in */*) dpre="${mprpath%/*}/" ;; esac
      if [ "$DRY" != 1 ] && unzip -Z1 "$APP_ZIP" 2> /dev/null | grep -q "^${dpre}deployment/."; then
        must unzip -q -o "$APP_ZIP" -d "$APP" -x "${dpre}deployment/*"
        note "fetch: the package ships a deployment/ folder (build output); not unpacked, mxbuild writes it again (BT-9)"
      else
        must unzip -q -o "$APP_ZIP" -d "$APP"
      fi
    fi
    # a zip with one top folder: the project is the folder that holds the .mpr
    if [ "$DRY" != 1 ] && ! ls "$APP"/*.mpr > /dev/null 2>&1; then
      local sub
      sub=$(find "$APP" -mindepth 2 -maxdepth 2 -name '*.mpr' -print -quit)
      sub=${sub%/*}
      [ -n "$sub" ] || die4 "no .mpr found in $APP_ZIP"
      APP=$sub
    fi
  else
    APP=$(cd "$APP_DIR_ARG" && pwd)
  fi
  [ "$DRY" = 1 ] || printf '%s\n' "$APP" > "$WORK/state/app-dir"
  resolve_app
  if [ "$DRY" != 1 ] && [ ! -d "$APP/.git" ]; then
    must git -C "$APP" init -q
    ensure_gitignore
    git_app add -A > /dev/null
    git_app commit -q -m "original" -m "$(printf 'Changed-By: toolkit\nUpgrade-Change: config run-start')" >> "$LOG" 2>&1
  elif [ "$DRY" != 1 ]; then
    ensure_gitignore
    if [ -n "$OLD_MDA" ]; then commit_app "rung start $SOURCE" config rung-start; fi
    [ -z "$(git_app status --porcelain)" ] || die4 "$APP has uncommitted changes: commit or discard them first (steps/baseline.md needs a clean tree)"
  else say "+ git init + commit original (when $APP has no .git)"; fi
  if [ "$DRY" != 1 ]; then
    local rev
    if [ -n "$OLD_MDA" ]; then rev=HEAD; else rev=$(git_app rev-list --max-parents=0 HEAD | tail -n 1); fi
    git_app show "$rev:$(basename "$MPR")" > "$WORK/original.mpr"
    local v
    v=$(project_version "$APP")
    if [[ "$v" != *"$SOURCE"* ]]; then
      echo "upgrade-pipeline.sh: the project is version '${v:-unknown}', not --source $SOURCE" >&2; exit 2
    fi
    if [ -n "$(find "$APP" -maxdepth 2 \( -name 'data-snapshot.zip' -o -name '*.script' \) -print -quit)" ]; then
      todo_hsql_replay
    fi
  fi
}

# TODO (no script exists): demo data inside the package (HSQLDB data-snapshot.zip) is NOT replayed into Postgres.
# The journals (T1) seeded synthetic rows with seed_pg.py instead. A person decides whether real data is needed.
todo_hsql_replay() {
  note "TODO todo_hsql_replay: the package carries HSQLDB demo data; it was NOT replayed into Postgres (no tool), the data baseline uses seed_pg.py rows"
  say "TODO    hsql data present, not replayed (see $WORK/state/notes.txt)"
}

# triage: versions, catalog, localedits, xmod, scanner, inventory, jarclash, impact map, release impact.
# Judgment: the module plan ($WORK/plan.txt, steps/triage.md item 3) has no script: exit 13 when absent.
step_triage() {
  local rc
  if [ "$DRY" = 1 ]; then say "+ mxversion.py app + toolsets > $WORK/versions.txt"; else
    { printf 'app: %s\n' "$(project_version "$MPR")"; printf 'toolset %s: %s\n' "$SOURCE" "$(project_version "$UPG_TOOLS/mxbuild-$SOURCE")"
      printf 'toolset %s: %s\n' "$TARGET" "$(project_version "$UPG_TOOLS/mxbuild-$TARGET")"; } > "$WORK/versions.txt"
  fi
  # BT-2: a module-only template (no navigation home page, no theme) has no baseline to freeze; say so now, not as "OLD app does not build"
  if [ "$DRY" != 1 ] && [ "${UPG_ALLOW_MODULE_ONLY:-}" != 1 ]; then
    rc=0; xo "$WORK/appshape.out" python3 "$B/appshape.py" "$APP" || rc=$?
    if [ "$rc" = 1 ]; then
      nj_add 13 "The source is a module, not an app: it needs a host app" "$(cat "$WORK/appshape.out")

No navigation profile of this project has a home page, so mxbuild stops it with 'Select a default home page' (and, when the layouts use design properties, 'Design property ... is not supported by your theme'): there is no running old app to freeze as the baseline, and no journey to compare. This is a template to import into an app, not an app.
Decide, in writing: (a) wrap it in a host app (an app with a home page, a theme and the module imported) and run the upgrade on that app; or (b) record the template as not upgradeable on its own and upgrade its modules inside the app that uses them. Then rerun. To go on anyway (the build will fail): UPG_ALLOW_MODULE_ONLY=1."
      nj_flush
    fi
  fi
  must mxcli_run -p "$MPR" -c "REFRESH CATALOG FULL"
  local le=() a
  if [ -f "$WORK/localedits.args" ]; then while IFS= read -r a; do [ -z "$a" ] || le+=("$a"); done < "$WORK/localedits.args"; fi
  rc=0; xo "$WORK/localedits.out" python3 "$B/localedits.py" "$APP" --md "$WORK/localedits.md" --json "$WORK/localedits.json" "${le[@]}" || rc=$?
  [ "$rc" -le 2 ] || die4 "localedits.py failed (exit $rc), see $WORK/localedits.out"
  [ "$rc" = 0 ] || note "localedits exit $rc (1 = RED local edits, 2 = some module UNKNOWN): never read as 'no edits'; stepupdate refuses edited modules and keeps them"
  # BT-6: a renamed or republished Marketplace module is outside every version plan; name it (playbooks/module-renames.tsv)
  rc=0; xo "$WORK/renamed.md" python3 "$B/renamed_modules.py" "$WORK/localedits.json" || rc=$?
  [ "$rc" != 1 ] || note "RENAMED modules in $WORK/renamed.md: not version updates, a decision item in the proposal"
  rc=0; xo "$WORK/xmod.txt" python3 "$B/idcheck.py" "$APP" --xmod || rc=$?
  # scanner (steps/triage.md item 6): optional, lives in the company brain checkout
  # the optional scanner: $EA, $UPG_SCANNER, or UPG_SCANNER= in the private ~/.config/upgrade-toolkit/local.env
  local EA="${EA:-${UPG_SCANNER:-$(sed -n 's/^UPG_SCANNER=//p' "$HOME/.config/upgrade-toolkit/local.env" 2>/dev/null)}}"
  if [ -f "$EA/scripts/scan.py" ]; then
    rc=0; (cd "$APP" && x python3 "$EA/scripts/scan.py" --project . --target "$TARGET" --from-version auto --data "$EA/data" --out "$WORK/findings.json") || rc=$?
    if [ "$rc" = 0 ]; then
      rc=0; xo "$WORK/scancover.out" python3 "$B/scancover.py" "$WORK/findings.json" || rc=$?
      [ "$rc" = 0 ] || note "scancover exit $rc: NO COVERAGE, scanner checked nothing for this rung: scanner rung INVALID, do the manual checks in $WORK/scancover.out"
    else note "scan.py failed (exit $rc): scanner rung INVALID"; fi
  else note "scanner not available at $EA: scanner rung INVALID"; fi
  if [ "$(major "$SOURCE")" -le 9 ]; then
    rc=0; xo "$WORK/javafinal.out" python3 "$B/javafinal.py" "$APP" --md "$WORK/javafinal.md" || rc=$?
    [ "$rc" != 1 ] || note "javafinal.py found assignments to Java action parameters: javac will fail at the build (by-hand fix, steps/repair.md row 10), see $WORK/javafinal.md"
  fi
  rc=0; xo "$WORK/test-inventory.out" python3 "$B/test_inventory.py" "$APP" --md "$WORK/test-inventory.md" --endpoints "$WORK/endpoints.txt" || rc=$?
  [ "$rc" = 0 ] || note "test_inventory.py exit $rc: no endpoints list (see $WORK/test-inventory.out)"
  rc=0; xo "$WORK/jarclash-before.out" python3 "$B/repair/jarclash.py" "$APP" --md "$WORK/jarclash-before.md" || rc=$?
  # impact map of the old app alone (always-on journey set, steps/journeys.md)
  must python3 "$B/impact_map.py" "$WORK/original.mpr" "$WORK/original.mpr" --out "$WORK/impact-base.json"
  # release impact (V31-RI): needs the module jumps, which come from the plan
  rc=0
  if [ -f "$WORK/module-jumps.txt" ]; then
    xo "$WORK/release-impact.out" python3 "$B/release_impact.py" --from "$SOURCE" --to "$TARGET" --plan "$WORK/module-jumps.txt" --out "$WORK/release-impact.md" || rc=$?
  else
    xo "$WORK/release-impact.out" python3 "$B/release_impact.py" --from "$SOURCE" --to "$TARGET" --out "$WORK/release-impact.md" || rc=$?
    note "no module-jumps.txt: release-impact.md holds Studio Pro rows only; module rows NOT generated"
  fi
  [ "$rc" = 0 ] || note "release_impact.py exit $rc (2 = a module is UNKNOWN to the brain: fill its row by hand), see $WORK/release-impact.out"
  # judgment: the plan
  if [ "$DRY" != 1 ] && [ ! -f "$WORK/plan.txt" ]; then
    nj_add 13 "Module plan missing: write $WORK/plan.txt" "No script picks module target versions (steps/triage.md item 3: newest version whose min Mendix fits the target, from the brain's modules-index.md and \`mxcli marketplace versions <content id>\`).
Write \`$WORK/plan.txt\`: one line per module, \`<content id> <version> <Module>\`, cross-module association targets (idcheck --xmod) LAST. An empty plan (comments only) is allowed and means no module updates.
Write \`$WORK/module-jumps.txt\`: \`<Module> <installed> -> <target>\` lines for the release-impact rows. Optional: \`$WORK/plan-pre.txt\` (updates BEFORE the convert, 10.x sources only), \`$WORK/localedits.args\` (one \`--cid Module=ID\` or \`--proxy Module=VER\` argument per line), \`$WORK/env-values.json\` (the environment's constants, same for old and new)."
    nj_file 13 "localedits result" "$WORK/localedits.md" 40
    nj_file 13 "cross-module association targets (update last)" "$WORK/xmod.txt" 20
    nj_flush
  fi
}

# baseline: build old, start on a fresh DB, seed, freeze, endpoint probe, snapshot, controls.
# Scripts: heavy-lock.sh + mx9/mx10.sh mxbuild, runapp.py, seed_pg.py, snapshot.py, diff.py
step_baseline() {
  local old rc=0 base probe keep line p code
  old=$(mda_old)
  if [ -z "$OLD_MDA" ] && [ ! -f "$old" ]; then
    disk_gate baseline
    x heavy build-old "$SOURCE" mxbuild --target=package -o "$old" "$MPR" || rc=$?
    if [ "$rc" != 0 ]; then
      disk_cause
      nj_file 10 "OLD app does not build (exit $rc)" "$LOG" 20 '^ERROR at|ERROR|error'
      nj_flush
    fi
    commit_app "build: regenerated stubs" config build-stubs
  fi
  if db_exists "$X_FROZEN"; then
    note "reusing existing frozen database $X_FROZEN"
  else
    if [ -n "$SEED_FROM" ]; then copy_db "$SEED_FROM" "$X"; fi
    app_up old "$old" "$SOURCE" "$X" || die4 "old app did not start on $X (log: $LOG, $WORK/logs/runtime-old.log)"
    app_down old
    if [ -z "$SEED_FROM" ]; then
      must python3 "$B/seed_pg.py" --psql "$(psql_str "$X")" --per-entity 5
      app_up old "$old" "$SOURCE" "$X" || die4 "old app did not start after the seed (log: $LOG)"
      app_down old
    fi
    copy_db "$X" "$X_FROZEN"
  fi
  # endpoint probe on its own copy (steps/triage.md item 8): drop listed paths that answer 404 on the old app
  if [ -s "$WORK/endpoints.txt" ] && [ ! -f "$WORK/endpoints.probed" ]; then
    probe=$(fresh_name "${X}_probe")
    copy_db "$X_FROZEN" "$probe"
    app_up oldprobe "$old" "$SOURCE" "$probe" || die4 "old app did not start for the endpoint probe (log: $LOG)"
    keep="$WORK/endpoints.new"; : > "$keep"
    if [ "$DRY" != 1 ]; then
      while IFS= read -r line; do
        p=$(printf '%s\n' "$line" | awk '{for(i=1;i<=NF;i++) if ($i ~ /^\//) {print $i; exit}}')
        [ -n "$p" ] || { printf '%s\n' "$line" >> "$keep"; continue; }
        code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$APP_PORT$p" || true)
        if [ "$code" = 404 ]; then note "endpoint $p dropped: 404 on the old app"; else printf '%s\n' "$line" >> "$keep"; fi
      done < "$WORK/endpoints.txt"
      cp "$WORK/endpoints.txt" "$WORK/endpoints.all.txt"; mv "$keep" "$WORK/endpoints.txt"; : > "$WORK/endpoints.probed"
    else say "+ curl each endpoint of $WORK/endpoints.txt on the old app, drop the 404s"; fi
    app_down oldprobe
    mark_used "$probe" probe
  fi
  base=$(fresh_name "${X}_base")
  copy_db "$X_FROZEN" "$base"
  app_up oldbase "$old" "$SOURCE" "$base" || die4 "old app did not start on $base (log: $LOG)"
  local ep_args=()
  [ ! -s "$WORK/endpoints.txt" ] || ep_args=(--endpoints "$WORK/endpoints.txt")
  rc=0
  x python3 "$B/snapshot.py" --label before --ledger "$WORK/db-ledger.txt" --psql "$(psql_str "$base")" \
    --app-url "http://localhost:$APP_PORT" "${ep_args[@]}" --log-cmd "docker logs ${UPG_NAME:-mig}-oldbase" \
    --admin-url "http://localhost:$ADMIN_PORT" --admin-pass "$M2EE_PASS" --out "$WORK/before.json" || rc=$?
  app_down oldbase
  [ "$rc" = 0 ] || die4 "snapshot before failed (exit $rc), log: $LOG"
  # controls (steps/baseline.md item 4)
  rc=0; x python3 "$B/diff.py" "$WORK/before.json" "$WORK/before.json" || rc=$?
  [ "$rc" = 0 ] || die4 "control failed: diff before vs before is not clean (exit $rc): the instrument is broken, log: $LOG"
  todo_mutant_control
}

# TODO (not automated): the mutant control needs a data-bearing table and column chosen from the schema and a value
# that fits the column length (T1, T2 both failed their first guess). It is reported as NOT RUN, never as passed.
todo_mutant_control() {
  note "TODO todo_mutant_control: mutant control NOT RUN (steps/baseline.md item 4); the tools' proof is 'make test' in controls/"
}

# basewalk: smoke users + smoke walk + always-on journeys on the OLD app, each on its own copy of the frozen DB.
# Scripts: smokewalk_gen.py, smoke_users.py, smokewalk.js, gen_journeys.py, run_journeys.py
step_basewalk() {
  local old roles rc=0 db
  old=$(mda_old)
  must python3 "$B/smokewalk_gen.py" "$APP" -o "$WORK/plan.json"
  roles=""; [ "$DRY" = 1 ] || roles=$(roles_of_plan "$WORK/plan.json")
  [ "$DRY" = 1 ] && roles="Role1,Role2"
  [ -n "$roles" ] || { nj_add 11 "No user roles in the smoke-walk plan" "plan.json has no non-guest role: nothing can log in. $WORK/plan.json"; nj_flush; }
  [ "$DRY" = 1 ] || write_users "$roles" "$WORK/users.json"
  user_args "$roles"
  # smoke walk
  db=$(fresh_name "${X}_smoke_walk")
  copy_db "$X_FROZEN" "$db"
  app_up oldwalk "$old" "$SOURCE" "$db" || die4 "old app did not start for the smoke walk (log: $LOG)"
  must python3 "$B/smoke_users.py" "$db" --roles "$roles" --apply
  rc=0; x node "$B/smokewalk.js" --plan "$WORK/plan.json" --url "http://localhost:$APP_PORT" "${UARGS[@]}" --login-path "$(login_path)" \
    --out "$WORK/smoke-before.json" --shots "$WORK/smoke-before-shots" || rc=$?
  app_down oldwalk
  mark_used "$db" walk
  [ "$rc" -le 1 ] || { nj_file 11 "Smoke walk on the OLD app is INVALID (exit $rc)" "$LOG" 30 'INVALID|FAIL|credential'; }
  [ "$rc" != 1 ] || note "smoke walk on the old app has FAIL steps (baseline defects, listed apart): $WORK/smoke-before.json"
  # always-on journeys
  # BT-4: baseline-evidence.txt (a NO-SIGNOUT line for an app with no sign-out UI) is read here as well as at the gate
  local create=() ev=()
  [ ! -f "$WORK/create-spec.json" ] || create=(--create "$WORK/create-spec.json")
  [ ! -f "$WORK/baseline-evidence.txt" ] || ev=(--baseline-evidence "$WORK/baseline-evidence.txt")
  # BT-12: a NO-CREATE / UNREACHABLE line is checked against the --actions inventory of the OLD model: write it here too
  if [ -f "$WORK/baseline-evidence.txt" ] && [ "$DRY" != 1 ] && [ -f "$WORK/original.mpr" ]; then
    { [ -s "$WORK/actions.json" ] && [ "$WORK/actions.json" -nt "$B/action_inventory.py" ]; } \
      || must python3 "$B/action_inventory.py" "$WORK/original.mpr" --out "$WORK/actions.json"
    ev+=(--actions "$WORK/actions.json")
  fi
  must python3 "$B/gen_journeys.py" "$WORK/impact-base.json" --out-dir "$WORK/journeys-base" --roles-with-users "$roles" --data-rung "${create[@]}"
  db=$(fresh_name "${X}_smoke_jbase")
  copy_db "$X_FROZEN" "$db"
  app_up oldj "$old" "$SOURCE" "$db" || die4 "old app did not start for the journeys (log: $LOG)"
  must python3 "$B/smoke_users.py" "$db" --roles "$roles" --apply
  rc=0; xo "$WORK/journeys-base.out" python3 "$B/run_journeys.py" "$WORK/journeys-base" --label before --port "$APP_PORT" --psql "$(psql_str "$db")" \
    --admin-port "$ADMIN_PORT" --admin-pass "$M2EE_PASS" --users "$WORK/users.json" --login-path "$(login_path)" --work "$WORK/e2e-base" --pause 50 ${ev[@]+"${ev[@]}"} || rc=$?
  app_down oldj
  mark_used "$db" journeys
  if [ "$rc" != 0 ]; then
    nj_file 11 "Always-on journeys are not all PASS on the OLD app (exit $rc): fix the journey, drop it, or write the todo" "$WORK/journeys-base.out" 40 'FAIL|INVALID|todo|skipped|INFO'
    nj_add 11 "Plan items" "plan: $WORK/journeys-base/plan.json (skipped, todo, not_browser). An MFA journey needs a user with an MFA type (users.json \`_mfa\`); this script cannot create one."
    nj_flush
  fi
}

# propose (trust spec section 2): nothing in the app model changes before a person signs $WORK/PROPOSAL.md.
# Scripts: action_inventory.py + apimock.py inventory on the original model (their output is a proposal input), proposal.py.
interview_unattended() {
  [ "${UPG_INTERVIEW_MODE:-}" = unattended ] || grep -qiE '^Interview mode:[[:space:]]*unattended' "$WORK/interview-mode.txt" 2> /dev/null
}
scope_run() { # journey_scope.py on the OLD model: sets SC=(--scope FILE) for gen_journeys.py, or SC=() when it cannot run
  SC=()
  [ -s "$WORK/actions.json" ] && [ -f "$WORK/original.mpr" ] || return 0
  local sa=(--out "$WORK/journey-scope.json" --md "$WORK/journey-scope.md") rc=0
  [ ! -s "$WORK/localedits.json" ] || sa+=(--localedits "$WORK/localedits.json")
  [ ! -s "$WORK/usage.json" ] || sa+=(--usage "$WORK/usage.json")   # optional: without it nothing is said about usage
  [ ! -s "$WORK/vendor-modules.txt" ] || sa+=(--vendor "$(tr '\n' ',' < "$WORK/vendor-modules.txt" | sed 's/,$//')")
  [ ! -d "$APP/javasource" ] || sa+=(--code-root "$APP")
  xo "$WORK/journey-scope.out" python3 "$B/journey_scope.py" "$WORK/actions.json" --model "$WORK/original.mpr" "${sa[@]}" || rc=$?
  if [ "$rc" = 0 ]; then
    SC=(--scope "$WORK/journey-scope.json")
    # why the reachable actions have no click path (read only; a failure only loses the cause text of the INVALID rows)
    if xo "$WORK/click-causes.out" python3 "$B/click_causes.py" "$WORK/actions.json" --model "$WORK/original.mpr" --scope "$WORK/journey-scope.json" \
         --out "$WORK/click-causes.json" --md "$WORK/click-causes.md"; then SC+=(--causes "$WORK/click-causes.json"); fi
  else note "journey_scope.py exit $rc: every action counts toward the journeys rung (see $WORK/journey-scope.out)"; fi
}
proposal_args() { # sets PA for proposal.py
  PA=(--work "$WORK" --source "$SOURCE" --target "$TARGET" --app "$APP")
  [ -z "$TARGET2" ] || PA+=(--target2 "$TARGET2")
  [ ! -f "$WORK/original.mpr" ] || PA+=(--original "$WORK/original.mpr")
  ! interview_unattended || PA+=(--unattended)
}
proposal_stop() { # proposal_stop RC: rc 14 / 15 end the run with NEEDS-JUDGMENT.md, anything else but 0 is a failed fixed step
  case "$1" in
    0) return 0 ;;
    14) nj_add 14 "Upgrade proposal awaits sign-off: read $WORK/PROPOSAL.md" "$(head -n 3 "$WORK/proposal.out" 2> /dev/null)
Nothing in the app model has changed. Read PROPOSAL.md, answer the section-3 items in chat (steps/decide.md; the P-n lines go to $WORK/DECISIONS.md), then a person writes one line in section 6:
\`Signed-off: <name> <yyyy-mm-dd>\` to go on, or \`Status: PAUSED <reason>\` to stop on purpose. An agent never writes that line. Then run the command at the top of this file."
       nj_file 14 "PROPOSAL.md (head)" "$WORK/PROPOSAL.md" 30 ;;
    15) nj_add 15 "Upgrade proposal PAUSED by the owner" "$(head -n 3 "$WORK/proposal.out" 2> /dev/null)
The run stopped on purpose; no step after propose has run. Resume: remove the \`Status: PAUSED\` line from $WORK/PROPOSAL.md section 6, write \`Signed-off: <name> <yyyy-mm-dd>\`, then
    $(rerun_cmd)" ;;
    *) die4 "proposal.py failed (exit $1), see $WORK/proposal.out" ;;
  esac
  nj_flush
}
step_propose() {
  local rc=0
  if [ "$DRY" = 1 ]; then
    say "+ action_inventory.py $WORK/original.mpr --out $WORK/actions.json; apimock.py inventory $WORK/original.mpr --json $WORK/apimock-inventory.json"
    say "+ proposal.py --work $WORK --source $SOURCE --target $TARGET (exit 14 unsigned, 15 PAUSED, 0 signed or unattended)"
    return 0
  fi
  if [ -f "$WORK/original.mpr" ]; then
    # the same file and the same freshness rule as the journeys step, so that step finds it done
    if [ ! -s "$WORK/actions.json" ] || [ ! "$WORK/actions.json" -nt "$B/action_inventory.py" ]; then
      rc=0; xo "$WORK/actions.out" python3 "$B/action_inventory.py" "$WORK/original.mpr" --out "$WORK/actions.json" || rc=$?
      [ "$rc" = 0 ] || note "action_inventory.py exit $rc: the proposal shows the action count as not measured (see $WORK/actions.out)"
    fi
    scope_run   # the triage line "journeys in scope: N reachable, M out of scope (...)" the proposal cites
    rc=0; xo "$WORK/apimock-inventory.out" python3 "$B/apimock.py" inventory "$WORK/original.mpr" --json "$WORK/apimock-inventory.json" || rc=$?
    [ "$rc" -le 3 ] || note "apimock.py inventory exit $rc: the proposal lists external systems as not measured (see $WORK/apimock-inventory.out)"
    # every version reviews its stand-ins again, as a step of its own; rung 2 compares with the inventory of rung 1
    if [ -s "$WORK/apimock-inventory.json" ]; then
      local prev=(); [ "$(basename "$WORK")" != rung2 ] || [ ! -s "$WORK/../apimock-inventory.json" ] || prev=(--previous "$WORK/../apimock-inventory.json")
      python3 "$B/steps.py" standins --work "$WORK" --inventory "$WORK/apimock-inventory.json" ${prev[@]+"${prev[@]}"} --by toolkit >> "$LOG" 2>&1 ||
        note "steps.py standins failed: the stand-ins of this version are not a step (see $LOG)"
    fi
  else
    note "no original.mpr: the proposal counts no modules, pages, microflows or actions"
  fi
  proposal_args
  rc=0; python3 "$B/proposal.py" "${PA[@]}" > "$WORK/proposal.out" 2>&1 || rc=$?
  cat "$WORK/proposal.out" >> "$LOG"
  if [ "$rc" = 0 ] && interview_unattended && [ "$(python3 "$B/proposal.py" --status --work "$WORK")" != signed ]; then
    note "proposal not signed: Interview mode unattended, ASSUMED (unattended) lines in $WORK/DECISIONS.md"
  fi
  proposal_stop "$rc"
}
# a plan input that changed after the sign-off clears it (proposal.py): every step after propose asks again
proposal_recheck() {
  local rc=0 keep=$STEP
  STEP=propose
  proposal_args
  python3 "$B/proposal.py" "${PA[@]}" > "$WORK/proposal.out" 2>&1 || rc=$?
  cat "$WORK/proposal.out" >> "$WORK/logs/propose.log"
  proposal_stop "$rc"
  STEP=$keep
}

# convert: mx convert in place with the TARGET toolset, convertcheck, commit. Scripts: heavy-lock.sh, mx10.sh, convertcheck.py, stepupdate.sh
step_convert() {
  local rc=0 cur
  cur=$(project_version "$APP")
  if [ "$DRY" != 1 ] && [[ "$cur" == *"$TARGET"* ]]; then note "project already at $TARGET, convert skipped"; return 0; fi
  # F13 (Purchase Request 10.24, real run): with only plan.txt, all eight updates ran after the convert and Mendix 11
  # refused every package (made before Studio Pro 10.21). A 10.x to 11 run states its pre-convert plan, even an empty one.
  if [ "$DRY" != 1 ] && [ "$(major "$SOURCE")" = 10 ] && [ "$(major "$TARGET")" -ge 11 ] && [ ! -e "$WORK/plan-pre.txt" ] \
     && [ -f "$WORK/plan.txt" ] && grep -qvE '^[[:space:]]*(#|$)' "$WORK/plan.txt"; then
    nj_add 13 "plan-pre.txt missing on a 10.x to 11 run" "Mendix 11 imports no package made before Studio Pro 10.21, so those updates must run before the convert. Split $WORK/plan.txt: lines whose package was made before 10.21 go to $WORK/plan-pre.txt (steps/triage.md, ORDER). Nothing to run before the convert: write $WORK/plan-pre.txt with only a comment."
    nj_flush
  fi
  if [ "$(major "$SOURCE")" -ge 10 ] && [ -s "$WORK/plan-pre.txt" ]; then
    run_stepupdate "$WORK/plan-pre.txt" "pre-convert"
    replay_edits pre
  fi
  disk_gate convert
  rc=0
  xo "$WORK/convert-$TARGET.log" env "UPG_ROOT=$RUN" "$B/heavy-lock.sh" convert "$B/mx10.sh" "$TARGET" mx convert --in-place "$APP" || rc=$?
  [ "$DRY" = 1 ] || note "mx convert exit $rc (never trusted, convertcheck decides)"
  rc=0; xo "$WORK/convertcheck.out" python3 "$B/convertcheck.py" "$WORK/convert-$TARGET.log" "$APP" --target "$TARGET" || rc=$?
  [ "$DRY" = 1 ] || cat "$WORK/convertcheck.out" >> "$LOG"
  [ "$rc" = 0 ] || die4 "NOT CONVERTED to $TARGET (convertcheck exit $rc): see $WORK/convertcheck.out and $WORK/convert-$TARGET.log. A 10.x below 10.24 must take the 10.24 rung first"
  commit_app "convert $TARGET" convert mx-convert
  rc=0; xo "$WORK/localedits-post-convert.out" python3 "$B/localedits.py" "$APP" --md "$WORK/localedits-post-convert.md" --json "$WORK/localedits-post-convert.json" || rc=$?
}

# one stepupdate batch, unattended. Exit 1 = modules kept (recorded), anything else = failure.
run_stepupdate() { # run_stepupdate PLAN label
  local plan=$1 rc=0 cmd="${UPG_UPDATE_CMD:-}"
  if [ "$DRY" != 1 ] && ! grep -qvE '^[[:space:]]*(#|$)' "$plan"; then note "$2 plan $plan has no module lines: no module updates"; return 0; fi
  [ -f "$WORK/approved.txt" ] || { [ "$DRY" = 1 ] || printf '# accepted step-idcheck findings: <pattern> # reason\n' > "$WORK/approved.txt"; }
  # an MPR name with a space broke the unquoted {mpr} in T1, T4, T8: quote it
  if [ -n "$cmd" ] && [[ "$cmd" != *"'{mpr}'"* ]] && [[ "$cmd" != *'"{mpr}"'* ]]; then cmd=${cmd//\{mpr\}/\'\{mpr\}\'}; fi
  local envs=("UPG_ROOT=$RUN")
  [ -z "$cmd" ] || envs+=("UPG_UPDATE_CMD=$cmd")
  # F1 (Purchase Request 10.24, real run): an edited module the judgment says to update anyway (and replay the edits) was
  # always KEPT, since --unattended keeps every refused module. $WORK/force-ui.txt names them, one per line.
  local fu=()
  if [ -f "$WORK/force-ui.txt" ]; then
    local mods; mods=$(grep -vE '^[[:space:]]*(#|$)' "$WORK/force-ui.txt" | awk '{print $1}' | paste -sd, -)
    [ -z "$mods" ] || fu=(--force-ui "$mods" --saved-edits "$WORK/saved-edits")
  fi
  # R-hook (pr-rerun): $WORK/accept-unsaved.txt names modules whose update may commit although the installed package cannot
  # prove their theme/JavaScript files unedited (stepupdate --accept-unsaved; NanoflowCommons 6.0.0 is not in the catalog)
  local au=()
  if [ -f "$WORK/accept-unsaved.txt" ]; then
    local amods; amods=$(grep -vE '^[[:space:]]*(#|$)' "$WORK/accept-unsaved.txt" | awk '{print $1}' | paste -sd, -)
    [ -z "$amods" ] || au=(--accept-unsaved "$amods")
  fi
  # F14: approved-step.txt holds step-only acceptances (a removal the replay restores): the step idcheck reads them,
  # the total idcheck (original vs final) never does, so a restore that did not happen still stops the run
  local apf="$WORK/approved.txt"
  if [ -f "$WORK/approved-step.txt" ]; then
    apf="$WORK/.approved-with-step.txt"
    [ "$DRY" = 1 ] || cat "$WORK/approved.txt" "$WORK/approved-step.txt" > "$apf"
  fi
  xo "$WORK/stepupdate-$2.out" env "${envs[@]}" bash "$B/stepupdate.sh" "$APP" "$plan" --approved "$apf" \
    --baseline "$WORK/original.mpr" --unattended ${fu[@]+"${fu[@]}"} ${au[@]+"${au[@]}"} || rc=$?
  [ "$DRY" = 1 ] || cat "$WORK/stepupdate-$2.out" >> "$LOG"
  if [ "$rc" -gt 1 ]; then die4 "stepupdate ($2) failed (exit $rc), output: $WORK/stepupdate-$2.out"; fi
  return 0
}

# replay: the local edits of a --force-ui module, run after the updates and committed one module at a time ("replay: <Module>"):
#   $WORK/replay/<Module>.mdl    model edits, run with mxcli exec (write it against the NEW version's definition: a
#                                "create or modify entity" drops every attribute it does not list)
#   $WORK/replay/<Module>.patch  file edits (theme SCSS, JavaScript), a diff against the OLD package with paths relative to
#                                the app folder, applied with git apply onto the NEW files: copying the old files back would
#                                undo the update. A patch that does not apply is a judgment stop, never a partial apply.
# A module that was kept (not updated) is not replayed: its edits are still there. The total idcheck that follows compares
# the result with the original, so a replay that misses a model edit stays visible.
replay_edits() { # replay_edits [pre]: pre = only modules the post-convert plan does not touch (their final version came
  # before the convert; F14: else the convert runs with MendixSSO's six associations gone); a replayed module is not redone
  [ -d "$WORK/replay" ] || return 0
  local f mod rc
  for f in "$WORK/replay"/*.mdl "$WORK/replay"/*.patch; do
    [ -f "$f" ] || continue
    mod=$(basename "$f"); mod=${mod%.*}
    if [ "${1:-}" = pre ] && grep -qE "^[0-9]+ [^ ]+ $mod\$" "$WORK/plan.txt" 2> /dev/null; then continue; fi
    if [ "$DRY" != 1 ] && git_app log --format=%s 2> /dev/null | grep -qxF "replay: $mod"; then note "replay $mod skipped: replayed already"; continue; fi
    if [ "$DRY" != 1 ] && grep -q "^$mod " "$APP/.stepupdate/kept.txt" 2> /dev/null; then note "replay $mod skipped: the module was kept, its edits are in place"; continue; fi
    rc=0
    case "$f" in
      *.mdl) xo "$WORK/replay-$mod.out" mxcli_run exec "$f" -p "$MPR" || rc=$?
             # F14 (Purchase Request 10.24, real run): MendixSSO 10.6.2 dropped the six associations PurchaseApprovals
             # owns into MendixSSOUser. Re-created by MDL they get new GUIDs (DROP + ADD column, the data is gone), so
             # replay/<Module>.guids names the elements whose ORIGINAL GUID goes back (restore_guid.py, one per line)
             if [ "$rc" = 0 ] && [ -f "$WORK/replay/$mod.guids" ]; then
               local el
               while read -r el; do
                 case "$el" in ''|'#'*) continue ;; esac
                 xo "$WORK/replay-$mod-guid-${el##*.}.out" python3 "$B/restore_guid.py" "$MPR" "$el" --from "$WORK/original.mpr" || { rc=$?; break; }
               done < "$WORK/replay/$mod.guids"
             fi ;;
      *.patch) # F15 (Purchase Request 10.24, real run): Atlas_Core 4.5.0 rewrote the line next to the edited one, so the
               # context no longer matched. Fallbacks, in order: already in place (reverse applies) = nothing to do; every
               # removed block found exactly once in its file = apply without context (patch_unique.py); else a stop
               if xo "$WORK/replay-$mod-patch.out" git -C "$APP" apply --check "$f"; then
                 xo "$WORK/replay-$mod-patch.out" git -C "$APP" apply "$f" || rc=$?
               elif git -C "$APP" apply --check --reverse "$f" > /dev/null 2>&1; then
                 note "replay $mod: the edit is already in place"
               elif xo "$WORK/replay-$mod-unique.out" python3 -I "$B/patch_unique.py" "$f" "$APP" &&
                    xo "$WORK/replay-$mod-patch.out" git -C "$APP" apply --check -C0 "$f"; then
                 xo "$WORK/replay-$mod-patch.out" git -C "$APP" apply -C0 "$f" || rc=$?
                 note "replay $mod: context changed, applied without context (each removed line unique in its file)"
               else rc=1; fi ;;
    esac
    [ "$rc" = 0 ] || { nj_file 13 "replay of $mod failed (exit $rc): $f" "$WORK/replay-$mod$([ "${f##*.}" = patch ] && echo -patch).out" 30; nj_flush; }
    commit_app "replay: $mod" replay "replay-$mod"
    note "replayed the local edits of $mod from $f"
  done
}

# mxcli v0.28.0 (#1502): `--save-edits` also writes the associations OTHER modules own that point into the updated module, as
# saved-edits/<Module>/association-<Owner>_<Name>.mdl (the update removes them with the entity). One that no replay/<Module>.mdl
# names is a lost association: noted here, and the total idcheck (original vs now) shows its removal.
assoc_unreplayed() {
  [ "$DRY" != 1 ] || return 0
  local f mod qn
  for f in "$WORK"/saved-edits/*/association-*.mdl; do
    [ -f "$f" ] || continue
    mod=$(basename "$(dirname "$f")"); mod=${mod%%.*}
    qn=$(grep -m1 -ioE 'association +[A-Za-z0-9_]+\.[A-Za-z0-9_]+' "$f" | awk '{print $2}')
    [ -n "$qn" ] || continue
    if [ ! -f "$WORK/replay/$mod.mdl" ] || ! grep -qF "$qn" "$WORK/replay/$mod.mdl"; then
      note "association $qn (owned by another module, removed by the $mod update) is saved in $f but no replay/$mod.mdl creates it: NOT replayed"
    fi
  done
}

# update: module updates with the post-convert plan; kept modules are recorded (SKILL stop rules), decided at the gate.
step_update() {
  [ -f "$WORK/plan.txt" ] || [ "$DRY" = 1 ] || { nj_add 13 "plan.txt missing" "$WORK/plan.txt does not exist"; nj_flush; }
  run_stepupdate "$WORK/plan.txt" post-convert
  replay_edits
  assoc_unreplayed
  if [ "$DRY" != 1 ]; then
    [ ! -s "$APP/.stepupdate/kept.txt" ] || cp "$APP/.stepupdate/kept.txt" "$WORK/kept.txt"
    local rc=0
    xo "$WORK/jarclash.out" python3 "$B/repair/jarclash.py" "$APP" --md "$WORK/jarclash.md" || rc=$?
    [ "$rc" = 0 ] || note "jarclash after the updates exit $rc: classes in two jars, see $WORK/jarclash.md (clashes listed in jarclash-before.md are older than the upgrade)"
  else
    x python3 "$B/repair/jarclash.py" "$APP" --md "$WORK/jarclash.md"
  fi
  local rc=0 ap=()
  [ ! -f "$WORK/approved.txt" ] || ap=(--approved "$WORK/approved.txt")
  xo "$WORK/idcheck-total.out" python3 "$B/idcheck.py" "$WORK/original.mpr" "$MPR" --md "$WORK/idcheck-total.md" "${ap[@]}" || rc=$?
  if [ "$rc" != 0 ]; then
    nj_file 13 "Total idcheck (original vs now) has open data-bearing findings (exit $rc)" "$WORK/idcheck-total.md" 30
    nj_flush
  fi
}

# build: mx check + the FIXED repair rows + mxbuild + stubs commit + quick start.
# Fixed rows (steps/repair.md): 0 JavaVersion (CE2513), 1 backslash paths, 2 sync-java-dependencies, 3 jardedupe, 5 update-widgets
# (CE0463), 6 design_props_guard (CE6087). Everything else (rows 4, 7-10 and own-document fixes) is a judgment stop (10).
CHECK_N=0
mxcheck() { # writes $WORK/check-N.log, sets CHECK_LOG
  CHECK_N=$((CHECK_N + 1)); CHECK_LOG="$WORK/check-$CHECK_N.log"
  if [ "$DRY" = 1 ]; then printf '+ %s check %s > %s\n' "$B/heavy-lock.sh check $(mxw "$TARGET") $TARGET mx" "$MPR" "$CHECK_LOG"; return 0; fi
  heavy check "$TARGET" mx check "$MPR" > "$CHECK_LOG" 2>&1 || true
}
has_code() { grep -q "\[$1\]" "$CHECK_LOG" 2> /dev/null; }
try_fix() { # try_fix "subject" RULE CODES cmd...: run a fixer, re-check, keep when checkdiff says not worse, else undo
  local subj=$1 rule=$2 codes=$3 prev rc=0; shift 3
  prev=$CHECK_LOG
  x "$@" || { note "fixer '$subj' failed (exit $?): left undone"; [ "$DRY" = 1 ] || { git_app checkout -q -- . ; git_app clean -fdq; }; return 0; }
  mxcheck
  [ "$DRY" = 1 ] && return 0
  python3 "$B/checkdiff.py" "$prev" "$CHECK_LOG" --fixed "$codes" >> "$LOG" 2>&1 || rc=$?
  if [ "$rc" = 0 ]; then commit_app "repair: $subj" repair "$rule"; say "        repair: $subj ($(open_errors "$prev") -> $(open_errors "$CHECK_LOG") errors)"
  else note "fix '$subj' made mx check WORSE (checkdiff exit $rc): undone"; git_app checkout -q -- . ; git_app clean -fdq; CHECK_LOG=$prev; fi
}
step_build() {
  local n=0 rc=0
  CHECK_N=0
  local f
  for f in "$WORK"/check-*.log; do if [ -e "$f" ]; then CHECK_N=$((CHECK_N + 1)); fi; done
  mxcheck
  # row 1: literal backslashes in file names (OQL package)
  if [ "$DRY" = 1 ] || [ -n "$(find "$APP" -maxdepth 1 -name '*\\*' -print -quit)" ]; then
    try_fix "backslash paths" repair-row-1 CE0463 python3 "$B/repair/backslash_paths.py" "$APP" --apply
  fi
  # row 0: Java 11 setting after a 9 -> 10 convert
  if [ "$(major "$SOURCE")" -le 9 ] && { [ "$DRY" = 1 ] || has_code CE2513; }; then
    try_fix "JavaVersion Java21" repair-row-0 CE2513 mxcli_run -p "$MPR" -c "alter settings model JavaVersion = 'Java21'"
  fi
  # rows 2 and 3: always, before the first build
  rc=0; xo "$WORK/logs/sync-java.log" heavy sync "$TARGET" mx sync-java-dependencies "$MPR" || rc=$?
  if [ "$rc" != 0 ]; then
    # T2-9, T6-2, T7-8, T8-14: Gradle behind the proxy; the failed sync still lists the deps: resolve them with host Maven
    local vrc=0; x bash "$B/cloud/vendorlib_mvn.sh" "$APP" "$WORK/logs/sync-java.log" --apply || vrc=$?
    if [ "$vrc" = 0 ]; then note "mx sync-java-dependencies failed (exit $rc); vendorlib filled by vendorlib_mvn.sh (host Maven)"
    else note "mx sync-java-dependencies failed (exit $rc), vendorlib_mvn.sh exit $vrc (3 = version range to pin), recorded NOT RUN; the build decides"; fi
  fi
  rc=0; x python3 "$B/repair/jardedupe.py" "$APP" || rc=$?
  x python3 "$B/repair/jardedupe.py" "$APP" --apply || true
  commit_app "repair: sync java dependencies, jardedupe" repair repair-row-2-3
  # row 4: missing or broken packages are noted (mx check reports what matters); DEPRECATED-11 builds clean but fails at
  # runtime on 11 (T7-29), so it stops here
  rc=0; xo "$WORK/missing_deps.txt" python3 "$B/repair/missing_deps.py" "$APP" --target "$TARGET" || rc=$?
  if [ "$DRY" != 1 ] && [ "$rc" = 1 ]; then
    note "missing_deps: $(grep -cE '^(MISSING|BROKEN)' "$WORK/missing_deps.txt" || true) missing or broken (see $WORK/missing_deps.txt)"
    if grep -q '^DEPRECATED-11' "$WORK/missing_deps.txt"; then
      nj_file 10 "Charts 3.x widgets on an 11 target: replace with Charts 6.x before the gate (T7-29)" "$WORK/missing_deps.txt" 30 '^DEPRECATED-11'
    fi
  fi
  # row 5, row 6
  if [ "$DRY" = 1 ] || has_code CE0463; then try_fix "update-widgets" repair-row-5 CE0463 heavy update-widgets "$TARGET" mx update-widgets "$MPR"; fi
  if [ "$DRY" = 1 ] || has_code CE6087; then
    try_fix "design properties" repair-row-6 CE6087 "$B/repair/design_props_guard.sh" "$APP" "$TARGET" --fixed CE6087 -- "$(mxw "$TARGET")" "$TARGET" mx rename-design-properties APP
  fi
  # all fixed rows done: where do we stand
  [ "$DRY" = 1 ] || { mxcheck; n=$(open_errors "$CHECK_LOG"); }
  # bounded loop (fix, recheck, again while it makes progress): a fixed row can expose the code of another one (L42), so the rows
  # whose code is still open run again, at most 2 more rounds, and the loop stops at the first round that lowers nothing
  if [ "$DRY" != 1 ] && [ "$n" != 0 ] && [ "${UPG_BUILD_ROUNDS:-2}" -gt 0 ]; then
    local brnd=0 bprev
    while [ "$brnd" -lt "${UPG_BUILD_ROUNDS:-2}" ] && [ "$n" != 0 ]; do
      brnd=$((brnd + 1)); bprev=$n
      if has_code CE0463; then try_fix "update-widgets (round $((brnd + 1)))" repair-row-5 CE0463 heavy update-widgets "$TARGET" mx update-widgets "$MPR"; fi
      if has_code CE6087; then try_fix "design properties (round $((brnd + 1)))" repair-row-6 CE6087 "$B/repair/design_props_guard.sh" "$APP" "$TARGET" --fixed CE6087 -- "$(mxw "$TARGET")" "$TARGET" mx rename-design-properties APP; fi
      mxcheck; n=$(open_errors "$CHECK_LOG")
      if [ "$n" -ge "$bprev" ]; then note "build loop round $((brnd + 1)): $bprev -> $n errors, no progress: stop"; break; fi
      note "build loop round $((brnd + 1)): $bprev -> $n errors"
    done
  fi
  if [ "$DRY" != 1 ] && [ "$n" != 0 ]; then
    nj_add 10 "mx check: $n errors after convert + updates + the fixed repair rows" "Summary file: $CHECK_LOG
Codes: $(grep -oE '^\[error\] *\[C[EW][0-9]+\]' "$CHECK_LOG" | grep -oE 'C[EW][0-9]+' | sort | uniq -c | sort -rn | head -n 15 | tr '\n' ';')
Work the list with steps/repair.md (rows 4, 7-10 and own-document fixes; one commit per fix; checkdiff.py after each)."
    nj_file 10 "First 20 error lines" "$CHECK_LOG" 20 '^\[error\]'
    nj_flush
  fi
  # mxbuild
  disk_gate build
  rc=0; xo "$WORK/build-$TARGET.log" heavy build "$TARGET" mxbuild --target=package -o "$(mda_new)" "$MPR" || rc=$?
  n=0; [ "$DRY" = 1 ] || n=$(grep -c '^ERROR at' "$WORK/build-$TARGET.log" 2> /dev/null || true)
  if [ "$DRY" != 1 ] && { [ "$rc" != 0 ] || [ "$n" != 0 ] || [ ! -f "$(mda_new)" ]; }; then
    disk_cause "$WORK/build-$TARGET.log"
    nj_add 10 "mxbuild failed (exit $rc, $n ERROR at lines)" "Summary file: $WORK/build-$TARGET.log (a 30 s theme-compile timeout is not a model error: retry when the machine is quiet; javac errors: javafinal.py, kept-module API removals)"
    nj_file 10 "First 20 error lines" "$WORK/build-$TARGET.log" 20 '^ERROR at|error:|ERROR'
    nj_flush
  fi
  commit_app "build: regenerated stubs" config build-stubs
  # quick start (mandatory before the gate)
  local q
  q=$(fresh_name "${X}_quick"); copy_db "$X_FROZEN" "$q"
  rc=0; runenv; x env "${RUNENV[@]}" python3 "$B/runapp.py" quick new "$(mda_new)" "$TARGET" "$q" || rc=$?
  mark_used "$q" quickstart
  infra_rc "$rc" quick
  if [ "$rc" != 0 ]; then
    nj_add 10 "QUICK START FAIL" "The new app does not start. Fix before the gate (after-startup contract, constants, missing jars). Start log: $WORK/logs/runtime-new.log"
    nj_file 10 "First 20 error lines" "$WORK/logs/runtime-new.log" 20 'ERROR|CRITICAL|Exception'
    nj_flush
  fi
}

# after: the new app on a fresh copy of the frozen DB, snapshot after. Scripts: runapp.py, snapshot.py
step_after() {
  local db rc=0
  db=$(fresh_name "${X}_after"); copy_db "$X_FROZEN" "$db"
  app_up newafter "$(mda_new)" "$TARGET" "$db" || { nj_file 10 "New app did not start on a copy of the frozen DB" "$WORK/logs/runtime-newafter.log" 20 'ERROR|CRITICAL|Exception'; nj_flush; }
  local ep_args=()
  [ ! -s "$WORK/endpoints.txt" ] || ep_args=(--endpoints "$WORK/endpoints.txt")
  x python3 "$B/snapshot.py" --label after --ledger "$WORK/db-ledger.txt" --psql "$(psql_str "$db")" \
    --app-url "http://localhost:$APP_PORT" "${ep_args[@]}" --log-cmd "docker logs ${UPG_NAME:-mig}-newafter" \
    --admin-url "http://localhost:$ADMIN_PORT" --admin-pass "$M2EE_PASS" --out "$WORK/after.json" || rc=$?
  app_down newafter
  [ "$rc" = 0 ] || die4 "snapshot after failed (exit $rc), log: $LOG"
}

# afterwalk: impact map, smoke walk of the NEW project against the baseline. Scripts: impact_map.py, smokewalk_gen.py, smoke_users.py, smokewalk.js
step_afterwalk() {
  local roles rc=0 db
  must python3 "$B/impact_map.py" "$WORK/original.mpr" "$MPR" --out "$WORK/impact.json" --md "$WORK/impact.md"
  must python3 "$B/smokewalk_gen.py" "$APP" -o "$WORK/plan-new.json"
  roles=""; [ "$DRY" = 1 ] || roles=$(roles_of_plan "$WORK/plan-new.json")
  [ "$DRY" = 1 ] && roles="Role1,Role2"
  user_args "$roles"
  db=$(fresh_name "${X}_smoke_new"); copy_db "$X_FROZEN" "$db"
  app_up newwalk "$(mda_new)" "$TARGET" "$db" || { nj_file 10 "New app did not start for the smoke walk" "$WORK/logs/runtime-newwalk.log" 20 'ERROR|CRITICAL|Exception'; nj_flush; }
  must python3 "$B/smoke_users.py" "$db" --roles "$roles" --apply
  x node "$B/smokewalk.js" --plan "$WORK/plan-new.json" --url "http://localhost:$APP_PORT" "${UARGS[@]}" --login-path "$(login_path)" \
    --compare "$WORK/smoke-before.json" --out "$WORK/smoke-after.json" --shots "$WORK/smoke-after-shots" || rc=$?
  app_down newwalk
  mark_used "$db" walk
  if [ "$rc" != 0 ]; then
    nj_file 12 "Smoke walk vs baseline (exit $rc: 1 = a PASS step regressed or broke, 2 = INVALID): a gate FAIL/INVALID, not a pass" "$LOG" 40 'REGRESS|FAIL|INVALID'
    nj_flush
  fi
}

# Each run_journeys call gets --psql for the database the app runs on (F7, Purchase Request 10.24: without it every data
# rung was INVALID "no --psql / UPG_PSQL", though the pipeline made that database itself).
# --data-rung: the journeys always get --psql (F7), so the own-row check (a create's ${RUN_ID} row exists) is asked
heal_on() { [ "${UPG_HEAL:-1}" != 0 ]; }
# journeys: impact-picked set on the old app (before-picked) and the new app (after, --compare). Scripts: gen_journeys.py, run_journeys.py
step_journeys() {
  local roles rc=0 db create=() old
  old=$(mda_old)
  roles=""; [ "$DRY" = 1 ] || roles=$(roles_of_plan "$WORK/plan-new.json")
  [ "$DRY" = 1 ] && roles="Role1,Role2"
  # PR-F36: a rerun writes journeys-*.out and e2e-*/ in place; keep the previous run's evidence first (pipe-30 -> 31)
  [ "$DRY" = 1 ] || must bash "$B/archive_journeys.sh" "$WORK"
  [ "$DRY" = 1 ] || rm -rf "$WORK/heal.json" "$WORK/heal-plan.json" "$WORK/heal-done.json" "$WORK/heal" "$WORK/e2e-heal-old" "$WORK/e2e-heal-new"   # a fresh run: nothing was healed yet
  [ -f "$WORK/users.json" ] || [ "$DRY" = 1 ] || write_users "$roles" "$WORK/users.json"
  [ ! -f "$WORK/create-spec.json" ] || create=(--create "$WORK/create-spec.json")
  # F22 (Purchase Request 10.24, real run): without the action inventory every journeys run was coverage INVALID
  # ("no actions.json") and the journeys covered the impact set only. The denominator is the OLD model's actions
  local act=() SC=()
  if [ "$DRY" != 1 ]; then
    # PR-F26: an actions.json older than action_inventory.py is written again (a rerun from journeys on a fixed toolkit
    # kept the old one: navigation list hops without their item)
    [ -s "$WORK/actions.json" ] && [ "$WORK/actions.json" -nt "$B/action_inventory.py" ] \
      || must python3 "$B/action_inventory.py" "$WORK/original.mpr" --out "$WORK/actions.json"
    act=(--actions "$WORK/actions.json")
    scope_run
  fi
  local si=()   # UPG_STANDIN=1: the whole journeys run on the stand-in APIs (apimock.py), on the old and the new app alike, with the journeys it makes possible
  if [ -n "${UPG_STANDIN:-}" ] && [ "$DRY" != 1 ]; then si=(--standin); heal_standin_start; fi
  must python3 "$B/gen_journeys.py" "$WORK/impact.json" ${act[@]+"${act[@]}"} --out-dir "$WORK/journeys" --roles-with-users "$roles" --users "$WORK/users.json" --data-rung "${create[@]}" ${si[@]+"${si[@]}"} ${SC[@]+"${SC[@]}"}
  # PR-F25: confirmed user processes (process_journeys.py) were never compiled by the pipeline, so a hand-confirmed
  # "submit a purchase request" never ran. Exit 3 is either a process INVALID (stops below) or no confirmed process
  if [ -f "$WORK/processes.md" ] && [ "${#act[@]}" -gt 0 ]; then
    rc=0; xo "$WORK/processes.out" python3 "$B/process_journeys.py" "$WORK/processes.md" --actions "$WORK/actions.json" --out-dir "$WORK/journeys" --users "$WORK/users.json" || rc=$?
    [ "$rc" = 0 ] || [ "$rc" = 3 ] || die4 "process_journeys exit $rc: $WORK/processes.out"
    # PR-F34: an INVALID confirmed process compiles to no legs at all, so the journeys ran for hours without it
    # (pipe-29). Stop before the apps start: the fix is a line in processes.md
    if grep -q '^INVALID' "$WORK/processes.out"; then
      nj_file 11 "A confirmed process is INVALID: fix processes.md (or set the process to status: dropped), then rerun --from journeys" "$WORK/processes.out" 20 '^INVALID'
      nj_flush
    fi
  fi
  fixtures_start
  db=$(fresh_name "${X}_smoke_jold"); copy_db "$X_FROZEN" "$db"; fixture_db "$db"
  app_up oldjp "$old" "$SOURCE" "$db" || die4 "old app did not start for before-picked (log: $LOG)"
  # PR-F32: each smoke user is its role's only holder, so a workflow that targets "all users with role X" picks it
  must python3 "$B/smoke_users.py" "$db" --roles "$roles" --sole-target --apply
  fixture_users_db "$db"
  rc=0; xo "$WORK/journeys-before-picked.out" python3 "$B/run_journeys.py" "$WORK/journeys" --label before-picked --port "$APP_PORT" --psql "$(psql_str "$db")" \
    --admin-port "$ADMIN_PORT" --admin-pass "$M2EE_PASS" --users "$WORK/users.json" --login-path "$(login_path)" --work "$WORK/e2e-before-picked" --pause 50 ${act[@]+"${act[@]}"} || rc=$?
  app_down oldjp
  mark_used "$db" journeys
  [ "$rc" = 0 ] || note "before-picked journeys on the old app exit $rc (baseline defects are listed apart): $WORK/journeys-before-picked.out"
  db=$(fresh_name "${X}_smoke_jnew"); copy_db "$X_FROZEN" "$db"; fixture_db "$db"
  app_up newjp "$(mda_new)" "$TARGET" "$db" || { nj_file 10 "New app did not start for the journeys" "$WORK/logs/runtime-newjp.log" 20 'ERROR|CRITICAL|Exception'; nj_flush; }
  # PR-F32: each smoke user is its role's only holder, so a workflow that targets "all users with role X" picks it
  must python3 "$B/smoke_users.py" "$db" --roles "$roles" --sole-target --apply
  fixture_users_db "$db"
  local sa=() ev=()
  [ ! -f "$WORK/shot-accept.txt" ] || sa=(--shot-accept "$WORK/shot-accept.txt")
  [ ! -f "$WORK/baseline-evidence.txt" ] || ev=(--baseline-evidence "$WORK/baseline-evidence.txt")   # BT-4: same file the gate reads
  rc=0; xo "$WORK/journeys-after.out" python3 "$B/run_journeys.py" "$WORK/journeys" --label after --port "$APP_PORT" --psql "$(psql_str "$db")" \
    --admin-port "$ADMIN_PORT" --admin-pass "$M2EE_PASS" --users "$WORK/users.json" --login-path "$(login_path)" --work "$WORK/e2e-after" --pause 50 ${act[@]+"${act[@]}"} \
    --compare "$WORK/e2e-before-picked" "${sa[@]}" ${ev[@]+"${ev[@]}"} || rc=$?
  app_down newjp
  mark_used "$db" journeys
  [ "${#si[@]}" = 0 ] || heal_standin_stop
  if [ "$rc" != 0 ] && heal_on; then
    # the heal step classifies every failing row next; the gate (diff step) still judges the journeys rung and stops on what is left
    note "journeys on the NEW app exit $rc: the heal step classifies the failing rows next (UPG_HEAL=0 stops here instead): $WORK/journeys-after.out"
  elif [ "$rc" != 0 ]; then
    local code=11
    # only SCREEN REVIEW lines and no FAIL/REGRESSION/INVALID journey: a comparison job (12), else a journey fix (11)
    if [ -f "$WORK/journeys-after.out" ] && grep -q 'SCREEN REVIEW' "$WORK/journeys-after.out" &&
       ! grep -E 'REGRESSION|NOT IN BASELINE|INVALID|\bFAIL\b' "$WORK/journeys-after.out" | grep -vq 'SCREEN REVIEW'; then code=12; fi
    nj_file "$code" "Journeys on the NEW app (exit $rc): REGRESSION/FAIL is a gate FAIL, INVALID blocks DONE, SCREEN REVIEW needs both images opened and a reason in shot-accept.txt" "$WORK/journeys-after.out" 60 'REGRESSION|NOT IN BASELINE|INVALID|FAIL|SCREEN|todo|skipped|journeys:'
    nj_add "$code" "Evidence" "summary: $WORK/e2e-after/after/summary.json ; plan: $WORK/journeys/plan.json ; screens: $WORK/e2e-after"
    nj_flush
  fi
}

# heal: classify every failing row, heal what belongs to the TEST, rerun only the affected checks (max 2 rounds, stops when a round
# changes nothing). steps/heal.md. Scripts: heal.py, apimock.py, gen_journeys.py --standin, run_journeys.py --only, seed_pg.py.
# Policy: the app is never edited here; a row that may be a real defect of the upgrade stays open (heal.py nj, exit 12 from diff).
nats_on() { [ -n "${UPG_NATS:-}${UPG_HEAL_NATS:-}" ]; }   # UPG_NATS=1: the journeys and heal steps run with the test broker (steps/heal.md, test fixtures)
fixtures_start() { # the test broker (stand-in broker and auth) and the browser's trust for its certificate, before a journeys or heal run
  nats_on || return 0
  [ "$DRY" != 1 ] || return 0
  must env APP="$APP" UPG_NAME="${UPG_NAME:-mig}" python3 "$B/natsfixture.py" up --work "$WORK"
  export UPG_BROWSER_SPKI; UPG_BROWSER_SPKI=$(python3 "$B/natsfixture.py" spki --work "$WORK") || die4 "natsfixture.py spki failed"
}
fixture_db() { # fixture_db DB: the same test-setup rows in a database copy of the old and the new app (never in the frozen baseline)
  [ "$DRY" != 1 ] || return 0
  if nats_on; then must env UPG_NAME="${UPG_NAME:-mig}" python3 "$B/natsfixture.py" seed --work "$WORK" --psql "$(psql_str "$1")"; fi
  [ ! -f "$WORK/test-setup.sql" ] || must python3 "$B/setup_sql.py" --psql "$(psql_str "$1")" --file "$WORK/test-setup.sql"
}
heal_drop() { local d; for d in "$@"; do x docker exec "$PGC" dropdb -U mendix --if-exists "$d" || true; done; }   # the heal copies are ~20 MB each and never read again
heal_twin() { # the restart control (steps/baseline.md item 4, PV-7): a second start of the OLD app on a fresh copy of the frozen DB
  if [ -f "$WORK/twin-old.md" ] && [ "$WORK/twin-old.md" -nt "$WORK/before.json" ]; then return 0; fi
  local db rc=0 ep_args=()
  db=$(fresh_name "${X}_restart"); copy_db "$X_FROZEN" "$db"
  app_up oldtwin "$(mda_old)" "$SOURCE" "$db" || die4 "old app did not start for the restart control (log: $LOG)"
  [ ! -s "$WORK/endpoints.txt" ] || ep_args=(--endpoints "$WORK/endpoints.txt")
  x python3 "$B/snapshot.py" --label restart --ledger "$WORK/db-ledger.txt" --psql "$(psql_str "$db")" \
    --app-url "http://localhost:$APP_PORT" ${ep_args[@]+"${ep_args[@]}"} --log-cmd "docker logs ${UPG_NAME:-mig}-oldtwin" \
    --admin-url "http://localhost:$ADMIN_PORT" --admin-pass "$M2EE_PASS" --out "$WORK/restart.json" || rc=$?
  app_down oldtwin
  mark_used "$db" restart
  heal_drop "$db"
  [ "$rc" = 0 ] || die4 "snapshot restart failed (exit $rc), log: $LOG"
  xo "$WORK/twin-old.out" python3 "$B/diff.py" "$WORK/before.json" "$WORK/restart.json" --md "$WORK/twin-old.md" || true
}
fixture_users_db() { # fixture_users_db DB: rows that point at the test users (a stored sign-in token), applied right after smoke_users.py made them
  [ "$DRY" != 1 ] || return 0
  [ ! -f "$WORK/test-setup-users.sql" ] || must python3 "$B/setup_sql.py" --psql "$(psql_str "$1")" --file "$WORK/test-setup-users.sql"
}
heal_standin_start() { # the same stand-in for the old and the new app (apimock.py), reachable from the containers
  local cls=()
  [ ! -f "$WORK/apimock-classify.txt" ] || cls=(--classify "$WORK/apimock-classify.txt")
  [ ! -d "$WORK/apimock-recorded" ] || cls+=(--recorded "$WORK/apimock-recorded")   # recorded bodies for the stand-in (apimock.py header)
  x python3 "$B/apimock.py" stop --state "$WORK/apimock" || true
  must python3 "$B/apimock.py" serve "$WORK/original.mpr" "$MPR" --state "$WORK/apimock" --public-host host.docker.internal --background ${cls[@]+"${cls[@]}"}
  : > "$WORK/state/heal-standin"
}
heal_standin_stop() { rm -f "$WORK/state/heal-standin"; x python3 "$B/apimock.py" stop --state "$WORK/apimock" || true; }
heal_gen() { # the journeys again, with --standin: an action whose only todo is an external call gets a journey
  local roles act=() create=() rc=0 SC=()
  roles=$(roles_of_plan "$WORK/plan-new.json")
  [ ! -s "$WORK/actions.json" ] || { act=(--actions "$WORK/actions.json"); scope_run; }
  [ ! -f "$WORK/create-spec.json" ] || create=(--create "$WORK/create-spec.json")
  must python3 "$B/gen_journeys.py" "$WORK/impact.json" ${act[@]+"${act[@]}"} --out-dir "$WORK/journeys" --roles-with-users "$roles" --users "$WORK/users.json" --data-rung ${create[@]+"${create[@]}"} --standin ${SC[@]+"${SC[@]}"}
  if [ -f "$WORK/processes.md" ] && [ "${#act[@]}" -gt 0 ]; then
    xo "$WORK/processes.out" python3 "$B/process_journeys.py" "$WORK/processes.md" --actions "$WORK/actions.json" --out-dir "$WORK/journeys" --users "$WORK/users.json" || rc=$?
  fi
}
heal_run_journeys() { # heal_run_journeys IDS_CSV BASE_DB: those journeys on the old app, then the new app (--compare), then merge
  local ids=$1 base=$2 roles db rc=0 act=() sa=() ev=()
  roles=$(roles_of_plan "$WORK/plan-new.json")
  [ ! -s "$WORK/actions.json" ] || act=(--actions "$WORK/actions.json")
  [ ! -f "$WORK/shot-accept.txt" ] || sa=(--shot-accept "$WORK/shot-accept.txt")
  [ ! -f "$WORK/baseline-evidence.txt" ] || ev=(--baseline-evidence "$WORK/baseline-evidence.txt")
  rm -rf "$WORK/e2e-heal-old" "$WORK/e2e-heal-new"
  db=$(fresh_name "${X}_smoke_jheal_old"); copy_db "$base" "$db"; fixture_db "$db"
  app_up healold "$(mda_old)" "$SOURCE" "$db" || die4 "old app did not start for the heal rerun (log: $LOG)"
  must python3 "$B/smoke_users.py" "$db" --roles "$roles" --sole-target --apply
  fixture_users_db "$db"
  rc=0; xo "$WORK/heal-journeys-old.out" python3 "$B/run_journeys.py" "$WORK/journeys" --label before-picked --only "$ids" --port "$APP_PORT" --psql "$(psql_str "$db")" \
    --admin-port "$ADMIN_PORT" --admin-pass "$M2EE_PASS" --users "$WORK/users.json" --login-path "$(login_path)" --work "$WORK/e2e-heal-old" --pause 50 ${act[@]+"${act[@]}"} || rc=$?
  app_down healold; mark_used "$db" heal; heal_drop "$db"
  db=$(fresh_name "${X}_smoke_jheal_new"); copy_db "$base" "$db"; fixture_db "$db"
  app_up healnew "$(mda_new)" "$TARGET" "$db" || { nj_file 10 "New app did not start for the heal rerun" "$WORK/logs/runtime-healnew.log" 20 'ERROR|CRITICAL|Exception'; nj_flush; }
  must python3 "$B/smoke_users.py" "$db" --roles "$roles" --sole-target --apply
  fixture_users_db "$db"
  rc=0; xo "$WORK/heal-journeys-new.out" python3 "$B/run_journeys.py" "$WORK/journeys" --label after --only "$ids" --port "$APP_PORT" --psql "$(psql_str "$db")" \
    --admin-port "$ADMIN_PORT" --admin-pass "$M2EE_PASS" --users "$WORK/users.json" --login-path "$(login_path)" --work "$WORK/e2e-heal-new" --pause 50 ${act[@]+"${act[@]}"} \
    --compare "$WORK/e2e-heal-old" ${sa[@]+"${sa[@]}"} ${ev[@]+"${ev[@]}"} || rc=$?
  app_down healnew; mark_used "$db" heal; heal_drop "$db"
  must python3 "$B/heal.py" merge --work "$WORK" --old "$WORK/e2e-heal-old" --new "$WORK/e2e-heal-new"
}
heal_nats() { # UPG_HEAL_NATS=1: a local NATS broker (natsfixture.py) for the old and the new app, then the journeys that failed at the NATS dialog again (steps/heal.md)
  local plan ids names sdb e sn=()
  plan=$(python3 "$B/heal.py" nats-plan --work "$WORK") || die4 "heal.py nats-plan failed"
  ids=$(python3 -I -c 'import json,sys; print(",".join(json.loads(sys.argv[1])["rerun"]))' "$plan")
  names=$(python3 -I -c 'import json,sys; print(" ".join(json.loads(sys.argv[1])["seedname"]))' "$plan")
  [ -z "${UPG_HEAL_NATS_IDS:-}" ] || ids=$UPG_HEAL_NATS_IDS   # a probe: a few journey ids (comma list) instead of the plan; the seedname values stay (a probe on the plain base reports a test-data error dialog as a regression)
  [ -n "$ids" ] || { note "heal nats: no journey to run again"; return 0; }
  say "heal nats: $(printf '%s' "$ids" | tr ',' '\n' | grep -c .) journey(s) on a base with the broker's connection data"
  must env APP="$APP" UPG_NAME="${UPG_NAME:-mig}" python3 "$B/natsfixture.py" up --work "$WORK"
  export UPG_BROWSER_SPKI; UPG_BROWSER_SPKI=$(python3 "$B/natsfixture.py" spki --work "$WORK") || die4 "natsfixture.py spki failed"   # the test browser trusts the broker's certificate key only
  : > "$WORK/state/heal-nats"
  sdb=$(fresh_name "${X}_smoke_jnats"); copy_db "$X_FROZEN" "$sdb"
  must env UPG_NAME="${UPG_NAME:-mig}" python3 "$B/natsfixture.py" seed --work "$WORK" --psql "$(psql_str "$sdb")"
  if [ -n "$names" ]; then   # the seedname rows need their valid names on this base too (same values on both sides)
    for e in $names; do sn+=(--value "$e"); done
    [ ! -f "$WORK/seedname-set.txt" ] || sn+=(--set-file "$WORK/seedname-set.txt")
    must python3 "$B/seedname_fix.py" --psql "$(psql_str "$sdb")" "${sn[@]}"
  fi
  mark_used "$sdb" heal-seed
  heal_standin_start
  heal_run_journeys "$ids" "$sdb"
  heal_standin_stop
  heal_drop "$sdb"
  unset UPG_BROWSER_SPKI
  rm -f "$WORK/state/heal-nats"   # the broker keeps running until `natsfixture.py down`: a second round and the evidence need it
  must python3 "$B/heal.py" finalize --work "$WORK"
  say "$(python3 "$B/heal.py" summary --work "$WORK")"
}
heal_reshoot() { # UPG_HEAL_RESHOOT=1: the healed and likely-real rows again, so the compared runs hold their own screenshots (steps/heal.md)
  local plan ids snids snames sdb e sn=()
  plan=$(python3 "$B/heal.py" reshoot-plan --work "$WORK") || die4 "heal.py reshoot-plan failed"
  ids=$(python3 -I -c 'import json,sys; print(",".join(json.loads(sys.argv[1])["rerun"]))' "$plan")
  snids=$(python3 -I -c 'import json,sys; print(",".join(json.loads(sys.argv[1])["seedname_ids"]))' "$plan")
  snames=$(python3 -I -c 'import json,sys; print(" ".join(json.loads(sys.argv[1])["seedname"]))' "$plan")
  say "heal reshoot: $(printf '%s' "$ids" | tr ',' '\n' | grep -c .) journey(s) on the plain base, $(printf '%s' "$snids" | tr ',' '\n' | grep -c .) on the seedname base"
  heal_standin_start
  if [ -n "$ids" ]; then heal_run_journeys "$ids" "$X_FROZEN"; fi
  if [ -n "$snids" ]; then
    sdb=$(fresh_name "${X}_smoke_jseeded"); copy_db "$X_FROZEN" "$sdb"
    for e in $snames; do sn+=(--value "$e"); done
    [ ! -f "$WORK/seedname-set.txt" ] || sn+=(--set-file "$WORK/seedname-set.txt")
    must python3 "$B/seedname_fix.py" --psql "$(psql_str "$sdb")" "${sn[@]}"
    mark_used "$sdb" heal-seed
    heal_run_journeys "$snids" "$sdb"
    heal_drop "$sdb"
  fi
  heal_standin_stop
  must python3 "$B/heal.py" finalize --work "$WORK"
  say "$(python3 "$B/heal.py" summary --work "$WORK")"
}
step_heal() {
  heal_on || { note "heal is off (UPG_HEAL=0): failing rows go to the gate unclassified"; return 0; }
  if [ "$DRY" = 1 ]; then say "+ heal: restart control of the old app, heal.py plan (at most 2 rounds), apimock stand-in, reruns of the affected journeys, heal.py finalize"; return 0; fi
  if [ -n "${UPG_HEAL_RESHOOT:-}" ]; then fixtures_start; heal_reshoot; return 0; fi
  if [ -n "${UPG_HEAL_NATS:-}" ]; then heal_nats; return 0; fi
  fixtures_start
  local rnd n ids base seeds sdb al=() la=() e
  [ -f "$WORK/e2e-after/after/summary.pre-heal.json" ] || rm -f "$WORK/heal.json" "$WORK/heal-plan.json" "$WORK/heal-done.json"   # nothing merged yet: a fresh start
  must python3 "$B/heal.py" grids --model "$WORK/original.mpr" --out "$WORK/heal-grids.json"
  [ ! -f "$WORK/allow.txt" ] || al=(--allow "$WORK/allow.txt")
  [ ! -f "$WORK/log-allow.txt" ] || la=(--log-allow "$WORK/log-allow.txt")
  xo "$WORK/heal-pre-diff.out" python3 "$B/diff.py" "$WORK/before.json" "$WORK/after.json" --md "$WORK/heal-pre-diff.md" ${al[@]+"${al[@]}"} ${la[@]+"${la[@]}"} || true
  heal_twin
  for rnd in 1 2; do
    xo "$WORK/heal-plan-$rnd.out" python3 "$B/heal.py" plan --work "$WORK" --round "$rnd" || die4 "heal.py plan failed (log: $WORK/heal-plan-$rnd.out)"
    n=$(sed -n 's/^CHANGED //p' "$WORK/heal-plan-$rnd.out"); n=${n:-0}
    ids=$(python3 -I -c 'import json,sys; print(",".join(json.load(open(sys.argv[1]))["rerun"]))' "$WORK/heal-plan.json")
    [ "$n" != 0 ] && [ -n "$ids" ] || { note "heal round $rnd changed nothing: stop"; break; }
    if [ -n "$(python3 -I -c 'import json,sys; print(",".join(json.load(open(sys.argv[1]))["standin"]))' "$WORK/heal-plan.json")" ]; then
      heal_standin_start; heal_gen
    fi
    must python3 "$B/heal.py" patch --work "$WORK"
    base="$X_FROZEN"
    seeds=$(python3 -I -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1]))["seed"]))' "$WORK/heal-plan.json")
    snames=$(python3 -I -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1])).get("seedname", [])))' "$WORK/heal-plan.json")
    if [ -n "$seeds$snames" ]; then   # the same rows go into the base of BOTH reruns (a seed on one side would be a difference of its own)
      sdb=$(fresh_name "${X}_smoke_jseeded"); copy_db "$X_FROZEN" "$sdb"
      if [ -n "$seeds" ]; then
        local so=(); for e in $seeds; do so+=(--per-entity-override "$e=3"); done
        must python3 "$B/seed_pg.py" --psql "$(psql_str "$sdb")" --per-entity 0 "${so[@]}"
      fi
      if [ -n "$snames" ]; then   # seeded junk used as an entity/member name: valid names, same on both sides (steps/heal.md, seedname)
        local sn=(); for e in $snames; do sn+=(--value "$e"); done
        [ ! -f "$WORK/seedname-set.txt" ] || sn+=(--set-file "$WORK/seedname-set.txt")
        must python3 "$B/seedname_fix.py" --psql "$(psql_str "$sdb")" "${sn[@]}"
      fi
      mark_used "$sdb" heal-seed; base="$sdb"
    fi
    heal_run_journeys "$ids" "$base"
    [ "$base" = "$X_FROZEN" ] || heal_drop "$base"
    heal_standin_stop
  done
  must python3 "$B/heal.py" finalize --work "$WORK"
  say "$(python3 "$B/heal.py" summary --work "$WORK")"
}

# diff: build log, identity, constants, data diff, start log, smoke screens, and the stored journeys results (PRC-8), all through gate.sh (smoke, release ran or run elsewhere)
# ---- apidirect: every consumed REST call tested directly, on the old and the new app (bin/apidirect.py, steps/apis.md) ----
# Why: the apis rung counted an outside endpoint as tested only when a browser journey happened to trigger it (16 of 170 in a
# field run). A throwaway COPY of the old and of the new app gets a test-only module (a wrapper microflow per REST-calling
# microflow, never committed); the runtime's client API runs each wrapper against the SAME stand-in, in three runs (ok, 500,
# malformed), and the requests sent and the results read are compared. UPG_APIDIRECT=0 turns the step off.
apidirect_on() { [ "${UPG_APIDIRECT:-1}" != 0 ] && [ -f "$WORK/original.mpr" ] && [ -f "$WORK/apimock/inventory.json" ]; }
apidirect_user() { # apidirect_user ROLE FIELD: the test user of a role from users.json
  python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2], {}).get(sys.argv[3], ""))' "$WORK/users.json" "$1" "$2" 2> /dev/null || true
}
apidirect_side() { # apidirect_side SIDE VER MDA: build the throwaway copy, run its wrappers, keep the results
  local side=$1 ver=$2 mda=$3 AD="$WORK/apidirect" db rc=0 role="${UPG_APIDIRECT_ROLE:-Administrator}" user pass base rec=()
  [ ! -f "$WORK/apidirect-recipes.json" ] || rec=(--recipes "$WORK/apidirect-recipes.json")   # inputs for calls whose inputs cannot be sampled (steps/apis.md)
  user=$(apidirect_user "$role" user); pass=$(apidirect_user "$role" pass)
  [ -n "$user" ] || { user="smoke_$(echo "$role" | tr 'A-Z ' 'a-z_')"; pass='Smoke-only-1!'; }
  xo "$AD/prepare-$side.out" python3 "$B/apidirect.py" prepare "$AD/calls-$side.json" --app "$AD/$side-src" --mxcli "${MXCLI:-$B/mxcli-container.sh}" --user-role "$role" ${rec[@]+"${rec[@]}"} || rc=$?
  [ "$rc" = 0 ] || { note "apidirect: the $side test module could not be prepared (exit $rc, $AD/prepare-$side.out)"; return 1; }
  rc=0; xo "$AD/build-$side.log" heavy "apid-build-$side" "$ver" mxbuild --target=package -o "$mda" "$AD/$side-src/$(basename "$MPR")" || rc=$?
  [ "$rc" = 0 ] || { note "apidirect: the $side test build failed (exit $rc, $AD/build-$side.log)"; return 1; }
  db=$(fresh_name "${X}_apid_$side"); copy_db "$X_FROZEN" "$db"; fixture_db "$db"
  app_up "apid$side" "$mda" "$ver" "$db" || { note "apidirect: the $side test app did not start"; heal_drop "$db"; return 1; }
  must python3 "$B/smoke_users.py" "$db" --roles "$role" --sole-target --apply
  fixture_users_db "$db"
  base=$(cat "$WORK/apimock/ready" 2> /dev/null | sed 's#//[^:/]*:#//localhost:#')
  rc=0; xo "$AD/drive-$side.out" python3 "$B/apidirect.py" drive "$AD/calls-$side.json" --side "$side" --app-url "http://localhost:$APP_PORT" \
    --standin "$base" --out "$AD/results-$side.jsonl" --user "$user" --password "$pass" --log-cmd "docker logs ${UPG_NAME:-mig}-apid$side" || rc=$?
  app_down "apid$side"; mark_used "$db" apidirect; heal_drop "$db"
  [ "$rc" = 0 ] || { note "apidirect: the $side run stopped (exit $rc, $AD/drive-$side.out)"; return 1; }
}
apidirect_run() {
  local AD="$WORK/apidirect" cls=() rev side rc=0
  mkdir -p "$AD"; rm -f "$AD"/results-*.jsonl "$AD"/direct.json "$AD"/direct.md
  [ ! -f "$WORK/apimock-classify.txt" ] || cls=(--classify "$WORK/apimock-classify.txt")
  [ ! -d "$WORK/apimock-recorded" ] || cls+=(--recorded "$WORK/apimock-recorded")
  must python3 "$B/apidirect.py" inventory "$WORK/original.mpr" --side old --out "$AD/calls-old.json" ${cls[@]+"${cls[@]}"}
  must python3 "$B/apidirect.py" inventory "$WORK/original.mpr" "$MPR" --side new --out "$AD/calls-new.json" ${cls[@]+"${cls[@]}"}
  rev=$(git_app log --format=%H --grep='^original$' | tail -1)
  [ -n "$rev" ] || { note "apidirect: no 'original' commit to take the old app from"; return 0; }
  for side in old new; do rm -rf "$AD/$side-src"; mkdir -p "$AD/$side-src"; done
  must bash -c "git -C '$APP' archive '$rev' | tar -x -C '$AD/old-src'"
  must rsync -a --exclude .git --exclude deployment --exclude theme-cache "$APP/" "$AD/new-src/"
  heal_standin_start
  rc=0
  apidirect_side old "$SOURCE" "$AD/ad-old.mda" || rc=1
  apidirect_side new "$TARGET" "$AD/ad-new.mda" || rc=1
  x python3 "$B/apidirect.py" split-log --state "$WORK/apimock" --out "$AD/standin/requests.jsonl"
  heal_standin_stop
  rm -rf "$AD/old-src" "$AD/new-src" "$AD"/ad-*.mda
  if [ "$rc" = 0 ]; then
    must python3 "$B/apidirect.py" compare --state "$AD"
  else
    note "apidirect: a side did not run: no direct results (the apis rung shows the journey evidence only)"
  fi
}
step_apidirect() {
  if [ "$DRY" = 1 ]; then say "+ apidirect.py inventory/prepare/drive/compare: every consumed REST call on a throwaway copy of the old and the new app"; return 0; fi
  apidirect_on || { note "apidirect is off (UPG_APIDIRECT=0, or no original.mpr / stand-in inventory)"; return 0; }
  apidirect_run
}
step_diff() {
  local rc=0 conf="$WORK/gate.conf" f k only="build,idcheck,const,data,logdiff,screens" bad
  local kv=("WORK=$WORK" "GATE_DIR=$WORK" "BUILD_LOG=$WORK/build-$TARGET.log" "OLD_MDA=$(mda_old)" "NEW_MDA=$(mda_new)")
  # GATE_DIR=$WORK: the evidence names stay as before and the screens rung finds $WORK/smoke-after-shots (afterwalk's)
  local allowf=allow.txt logallowf=log-allow.txt
  # the heal step's own lists (the person's file plus the rows the evidence accepted) replace the plain ones
  [ ! -f "$WORK/allow-effective.txt" ] || allowf=allow-effective.txt
  local notesf=gate-notes.txt; [ ! -f "$WORK/gate-notes-effective.txt" ] || notesf=gate-notes-effective.txt   # the person's notes plus the heal's behaviour-change lines
  [ ! -f "$WORK/log-allow-effective.txt" ] || logallowf=log-allow-effective.txt
  for f in APPROVED=approved.txt CONST_OVERRIDES=env-values.json CONST_ALLOW=const-allow.txt ALLOW=$allowf LOG_ALLOW=$logallowf SMOKE_SHOT_ACCEPT=shot-accept.txt GATE_NOTES=$notesf HEAL_JSON=heal.json; do
    k=${f%%=*}; [ ! -f "$WORK/${f#*=}" ] || kv+=("$k=$WORK/${f#*=}")
  done
  # L55: the smoke rung judges the stored smoke results (no app); L56 is GATE_NOTES above
  if [ -f "$WORK/smoke-after.json" ] && [ -f "$WORK/smoke-before.json" ]; then
    kv+=("SMOKE_BEFORE=$WORK/smoke-before.json" "SMOKE_REJUDGE=1"); only="$only,smoke"
  fi
  # the apis rung: the stand-in's own check of what was requested (apimock.py check)
  if [ -f "$WORK/apimock/inventory.json" ]; then kv+=("APIMOCK=$WORK/apimock"); only="$only,apis"; fi
  [ ! -f "$WORK/apidirect/direct.json" ] || kv+=("APIDIRECT=$WORK/apidirect")
  kv+=("BEFORE_JSON=$WORK/before.json" "AFTER_JSON=$WORK/after.json" "OLD_LOG=$WORK/logs/runtime-oldbase.log" "NEW_LOG=$WORK/logs/runtime-newafter.log" "SMOKE_BEFORE_SHOTS=$WORK/smoke-before-shots" "SMOKE_LOGIN_PATH=$(login_path)")
  # PRC-8: the journeys stage ran just before; judge its stored results again (gate.sh JOURNEYS_REJUDGE: no app, nothing
  # written) so the gate's Progress line counts the rung instead of "journeys: not measured yet" (Purchase Request run 4)
  if [ -f "$WORK/e2e-after/after/summary.json" ] && [ -d "$WORK/journeys" ] && [ -d "$WORK/e2e-before-picked" ]; then
    kv+=("JOURNEYS_DIR=$WORK/journeys" "JOURNEYS_BEFORE=$WORK/e2e-before-picked" "JOURNEYS_REJUDGE=1")
    [ ! -s "$WORK/actions.json" ] || kv+=("ACTIONS=$WORK/actions.json")
    [ ! -f "$WORK/shot-accept.txt" ] || kv+=("JOURNEY_SHOT_ACCEPT=$WORK/shot-accept.txt")
    [ ! -f "$WORK/baseline-evidence.txt" ] || kv+=("JOURNEY_EVIDENCE=$WORK/baseline-evidence.txt")
    only="$only,journeys"
  fi
  # PRC-4: the change ledger (gate.sh `Changes:` line) reads the app's git repo; the app is not always under $WORK/app
  # (Purchase Request run 4: the line never printed). Only a repo is named, like gate.sh's own $WORK/app default.
  [ ! -e "${APP:-/nonexistent}/.git" ] || kv+=("APP_REPO=$APP")
  if [ "$DRY" = 1 ]; then say "+ write $conf:"; printf '  %s\n' "${kv[@]}"; else printf '%s\n' "${kv[@]}" > "$conf"; fi
  local ga=(--config "$conf" --only "$only")
  [ "$DRY" != 1 ] || ga+=(--dry-run)
  xo "$WORK/gate.out" bash "$B/gate.sh" "${ga[@]}" || rc=$?
  [ "$DRY" != 1 ] || return 0
  # --only leaves smoke/journeys/release NOT RUN, which gate.sh counts as exit 2: judge the selected rungs' own rows
  bad=$(grep -E "^\| [0-9]+ \| (${only//,/|}) \| (FAIL|INVALID|NOT RUN) " "$WORK/gate-summary.md" 2> /dev/null || true)
  if [ "$rc" = 1 ] || [ -n "$bad" ] || { [ "$rc" != 0 ] && [ "$rc" != 2 ]; } || [ ! -f "$WORK/gate-summary.md" ]; then
    nj_file 12 "gate.sh: open FAIL / REVIEW / INVALID / NOT RUN (exit $rc: 1 = FAIL, 2 = INVALID or NOT RUN); accept in writing (allow files, steps/gate.md) or repair" "$WORK/gate-summary.md" 40 'FAIL|REVIEW|INVALID|NOT RUN'
  fi
  if [ -f "$WORK/heal.json" ]; then   # rows that may be a real defect of the upgrade stay open, with options and a recommendation
    python3 "$B/heal.py" finalize --work "$WORK" > /dev/null 2>&1 || true
    local hn; hn=$(python3 "$B/heal.py" nj --work "$WORK" 2> /dev/null || true)
    [ -z "$hn" ] || nj_add 12 "Heal: rows that may be real defects of the upgrade (no automatic fix)" "$hn"
  fi
  nj_flush
}

# gate: release impact, kept modules, written verdict. Scripts: release_impact.py --check
step_gate() {
  local rc=0
  if [ -s "$WORK/plan.txt" ] && grep -qvE '^[[:space:]]*(#|$)' "$WORK/plan.txt" && [ ! -f "$WORK/module-jumps.txt" ] && [ "$DRY" != 1 ]; then
    nj_add 12 "Release impact INVALID: module rows missing" "plan.txt has updates but $WORK/module-jumps.txt does not exist, so release-impact.md has no module rows (steps/triage.md item 10). Write module-jumps.txt, rerun triage, then fill every row."
  fi
  xo "$WORK/release-impact.check" python3 "$B/release_impact.py" --check "$WORK/release-impact.md" || rc=$?
  [ "$rc" = 0 ] || nj_file 12 "release_impact.py --check: open rows (exit $rc). Every row needs 'handled: <evidence>' or 'not relevant: <reason>' (INVALID until then)" "$WORK/release-impact.check" 30
  # NOT RUN items (mutant control, demo data replay) are never a pass: stop until a person ran them or wrote why not
  if [ "$DRY" != 1 ] && grep -q 'NOT RUN\|NOT replayed' "$WORK/state/notes.txt" 2> /dev/null && [ ! -f "$WORK/notrun-ack.txt" ]; then
    nj_file 12 "Gate items NOT RUN by the pipeline (steps/baseline.md item 4: the mutant control must FAIL)" "$WORK/state/notes.txt" 20 'NOT RUN|NOT replayed'
    nj_add 12 "Decision" "Run each item by hand and record the result, or write the reason it does not apply, in $WORK/notrun-ack.txt; then rerun --from gate."
  fi
  nj_flush
  # kept modules: complete except kept, unless a person acknowledged the list
  if [ "$DRY" != 1 ] && [ -s "$WORK/kept.txt" ] && [ ! -f "$WORK/kept-ack.txt" ]; then
    nj_file 13 "upgrade complete except kept modules (never reported as upgraded)" "$WORK/kept.txt" 40
    nj_add 13 "Decision" "Update them by hand (steps/upgrade.md, playbooks/edited-modules.md), or acknowledge the list: copy $WORK/kept.txt to $WORK/kept-ack.txt (then the verdict says 'complete except kept modules')."
    nj_flush
  fi
  write_summary
  record_runlog || true
}

write_summary() {
  [ "$DRY" != 1 ] || return 0
  {
    printf '# Pipeline result %s -> %s: gate PASS (fixed steps)\n\n' "$SOURCE" "$TARGET"
    printf 'No judgment stop remained. Evidence (all under %s):\n' "$WORK"
    printf -- '- build: check-*.log, build-%s.log, quick start log logs/runtime-new.log\n- gate: gate-summary.md (one row per rung)\n- identity: idcheck.md, idcheck-total.md\n- constants: constants.md\n- data: diff.md (before.json, after.json)\n- start log: logdiff.md\n- smoke walk: smoke-after.json, shotdiff-smoke.md\n- journeys: e2e-after/, journeys-after.out\n- release impact: release-impact.md (check clean)\n\n' "$TARGET"
    if [ -s "$WORK/kept.txt" ]; then printf 'upgrade complete except kept modules (acknowledged): see kept.txt\n\n'; fi
    case "$(python3 "$B/proposal.py" --status --work "$WORK" 2> /dev/null)" in
      signed|none) ;;
      *) printf 'proposal not signed: %s/PROPOSAL.md has no Signed-off line (unattended run); the verdict is not an owner-approved upgrade.\n\n' "$WORK" ;;
    esac
    printf 'Read impact.md before you sign the verdict (high constants read at startup, flows no longer called at startup).\n\n'
    printf '## Not run / notes (never read these as passed)\n'
    cat "$WORK/state/notes.txt" 2> /dev/null || true
  } > "$WORK/SUMMARY.md"
  say "PASS    gate $SOURCE -> $TARGET: $WORK/SUMMARY.md"
  record_grade
}

# report step (steps/report.md): print the completion grade and write the run row to the run-local $WORK/history-row.md (UPG_HISTORY
# chooses another file). Never the toolkit checkout: runs/HISTORY.md changes only through a toolkit PR. Information only: a failure
# here never changes the pipeline result.
record_grade() {
  [ -f "$WORK/gate-summary.md" ] || return 0
  local kept; kept=$(grep -cvE '^[[:space:]]*(#|$)' "$WORK/kept.txt" 2> /dev/null || true)
  python3 "$B/grade.py" "$WORK/gate-summary.md" --history "${UPG_HISTORY:-$WORK/history-row.md}" ${UPG_RUN_ID:+--run "$UPG_RUN_ID"} \
    --app "${UPG_APP_NAME:-unnamed app}" --path "$SOURCE > $TARGET" --kept "${kept:-0}" 2>&1 | sed 's/^/  /' || true
}

# run log (steps/report.md): append this run's row to FIELD-RUNS.md ($UPG_FIELD_RUNS, default the toolkit checkout) with
# bin/runlog.py. Never fails the run: the exit code and the gate verdict stay as they are. When runlog.py refuses (a run id
# already in the log, exit 3; a customer name, exit 4; no app code name, exit 2) the reason goes to the console, to the gate
# output (a `Run log:` line in gate-summary.md) and to NEEDS-JUDGMENT.md as an information section, and the run continues.
# App code name: UPG_APP_CODE (UPG_APP_NAME is the older spelling), else the one line in $WORK/state/app-code; type: UPG_APP_TYPE,
# else $WORK/state/app-type. UPG_RUN_ID sets the run id. The Time: line (step timing) is stamped into gate-summary.md first.
record_runlog() {
  RUNLOG_DONE=1
  [ -f "$WORK/gate-summary.md" ] || return 0
  local log="${UPG_FIELD_RUNS:-$TK/FIELD-RUNS.md}" out rc=0 app="${UPG_APP_CODE:-${UPG_APP_NAME:-}}" typ="${UPG_APP_TYPE:-}" why
  [ -n "$app" ] || app=$(head -n 1 "$WORK/state/app-code" 2> /dev/null || true)
  [ -n "$typ" ] || typ=$(head -n 1 "$WORK/state/app-type" 2> /dev/null || true)
  python3 -I "$B/runlog.py" --stamp-time --work "$WORK" > /dev/null 2>&1 || true
  out=$(python3 -I "$B/runlog.py" --work "$WORK" --log "$log" --require-app ${UPG_RUN_ID:+--run-id "$UPG_RUN_ID"} \
        ${app:+--app "$app"} ${typ:+--type "$typ"} 2>&1) || rc=$?
  if [ "$rc" = 0 ]; then
    echo "runlog: row added to $log. Commit FIELD-RUNS.md and CHANGES.md ($WORK/CHANGES.md) with explicit paths (git commit -- <paths>), then open a toolkit PR: the row is not in the toolkit until that PR is merged."
  else
    case "$rc" in
      3) why="the run id is already in the log (exit 3)" ;;
      4) why="the row holds a customer name (exit 4): set UPG_APP_CODE and UPG_APP_TYPE to code names" ;;
      2) why="runlog.py needs an app code name or a run id (exit 2): set UPG_APP_CODE (and UPG_APP_TYPE), or write it to $WORK/state/app-code" ;;
      *) why="" ;;
    esac
    why="${why:+$why: }$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-300)"
    echo "WARN    runlog: no row added (runlog.py exit $rc): $why"
    if [ "$DRY" != 1 ]; then
      { printf '\nRun log: no row added to FIELD-RUNS.md (runlog.py exit %s). %s\n' "$rc" "$why"; } >> "$WORK/gate-summary.md" 2> /dev/null || true
      [ -f "$WORK/NEEDS-JUDGMENT.md" ] || printf '# NEEDS JUDGMENT: information only, the run result is unchanged\n\nwork: %s\n' "$WORK" >> "$WORK/NEEDS-JUDGMENT.md" 2> /dev/null || true
      {
        printf '\n## Run log not added (information; the exit code and the verdict are unchanged)\n\nFIELD-RUNS.md has no row for this run: %s\nFix the cause and run: python3 -I %s/runlog.py --work %s --app <CODE> --type <TEXT>\nThen commit FIELD-RUNS.md through a toolkit PR.\n' "$why" "$B" "$WORK"
      } >> "$WORK/NEEDS-JUDGMENT.md" 2> /dev/null || true
    fi
  fi
  return 0
}

# =====================================================================================================
# Driver
# =====================================================================================================
# One mxcli version per run (bin/mxcli_pin.sh has the why): triage records it in $WORK/state/mxcli-version, every later
# step that uses mxcli compares it and REFUSES (exit 3, on stderr) when the binary is another version. --from fetch|triage
# (or --only triage) re-records on purpose. A run that predates the pin records on its first checked step, and says so.
mxcli_pin() { # mxcli_pin STEP
  [ "$DRY" != 1 ] || return 0
  case "$1" in fetch|propose) return 0 ;; esac
  local sf="$WORK/state/mxcli-version" rc=0 reset=0
  if [ "$1" = triage ] && { [ "$FROM" = triage ] || [ "$FROM" = fetch ] || [ "$ONLY" = triage ]; }; then reset=1; fi
  if [ ! -s "$sf" ] || [ "$reset" = 1 ]; then
    if [ ! -s "$sf" ] && [ "$1" != triage ]; then
      say "WARN    mxcli version: no pin from triage (a run older than the pin); recording it now, the steps before $1 are unchecked"
    fi
    bash "$B/mxcli_pin.sh" record "$sf" || rc=$?
  else
    bash "$B/mxcli_pin.sh" check "$sf" || rc=$?
  fi
  [ "$rc" = 0 ] || { echo "upgrade-pipeline.sh: step '$1' not run: mxcli version pin (exit $rc)" >&2; exit 3; }
  return 0
}

run_step() { # run_step NAME
  STEP=$1; LOG="$WORK/logs/$STEP.log"
  decisions_apply
  if [ "$DRY" != 1 ] && [ -f "$WORK/state/$STEP.done" ] && [ "$ONLY" != "$STEP" ]; then
    printf '%-10s %s\n' "$STEP" "skipped (done $(cat "$WORK/state/$STEP.done"))"; return 0
  fi
  mxcli_pin "$STEP"
  [ "$DRY" = 1 ] || : > "$NJ_TMP"
  NJ_CODE=0
  case " convert update build after afterwalk journeys heal apidirect diff gate " in
    *" $STEP "*) if [ "$DRY" != 1 ] && [ -f "$WORK/PROPOSAL.md" ]; then proposal_recheck; fi ;;
  esac
  printf '%-10s %s\n' "$STEP" "running (log: $LOG)"
  timing_open "$STEP"
  "step_$STEP"
  nj_flush
  timing_close 0 || true
  if [ "$DRY" != 1 ]; then date -u +%Y-%m-%dT%H:%M:%SZ > "$WORK/state/$STEP.done"; fi
  printf '%-10s %s\n' "$STEP" "done"
  cockpit_regen
}

main() {
  preflight
  resolve_app
  [ "$DRY" = 1 ] || rm -f "$WORK/NEEDS-JUDGMENT.md"
  decisions_apply   # resume: what was decided on the page or in chat while the run was stopped
  if [ -n "$FROM" ] && [ "$DRY" != 1 ]; then
    local s found=0
    for s in "${STEPS[@]}"; do [ "$s" != "$FROM" ] || found=1; [ "$found" = 0 ] || rm -f "$WORK/state/$s.done"; done
  fi
  local s
  for s in "${STEPS[@]}"; do
    [ -z "$ONLY" ] || [ "$s" = "$ONLY" ] || continue
    if [ "$s" != fetch ]; then resolve_app; fi
    run_step "$s"
  done
  [ -z "$ONLY" ] || exit 0
  # rung 2 (steps/upgrade.md rule: 10.24 first, then 11): the same pipeline, new app of rung 1 is the old app of rung 2
  if [ -n "$TARGET2" ]; then
    say "rung 2   $TARGET -> $TARGET2 in $WORK/rung2"
    local r2=("$SELF" --app-dir "$APP" --source "$TARGET" --target "$TARGET2" --work "$WORK/rung2"
              --old-mda "$(mda_new)" --seed-from "$X_FROZEN" --db "${X}_r2")
    [ "$DRY" != 1 ] || r2+=(--dry-run)
    if [ "$DRY" != 1 ]; then
      mkdir -p "$WORK/rung2/state"
      # one version per run: rung 2 inherits the pin of rung 1 (its triage then checks, not re-records)
      [ ! -s "$WORK/state/mxcli-version" ] || [ -s "$WORK/rung2/state/mxcli-version" ] || cp "$WORK/state/mxcli-version" "$WORK/rung2/state/mxcli-version"
      # one step file for both versions: rung 2 appends to the steps.jsonl of rung 1
      touch "$WORK/steps.jsonl"; [ -e "$WORK/rung2/steps.jsonl" ] || ln -s ../steps.jsonl "$WORK/rung2/steps.jsonl"
      for s in env-values.json create-spec.json localedits.args; do
        [ ! -f "$WORK/$s" ] || [ -f "$WORK/rung2/$s" ] || cp "$WORK/$s" "$WORK/rung2/$s"
      done
    fi
    exec env "RUN=$RUN" "UPG_PHASE=$(echo "$TARGET2" | cut -d. -f1-3)" "UPG_COCKPIT_OUT=$WORK/COCKPIT.html" "${r2[@]}"
  fi
  exit 0
}
main
