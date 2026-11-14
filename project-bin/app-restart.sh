#!/usr/bin/env bash
# app-restart.sh — restart THIS project's `mxcli run --local` app, and only that one.
#
#   ./bin/app-restart.sh                  restart, return when the port answers and a page bundle serves
#   ./bin/app-restart.sh --dry-run        say what would be stopped and how it would be started; touch nothing
#   ./bin/app-restart.sh --cmd '<start>'  start command to use instead of the one read from the process
#   ./bin/app-restart.sh --timeout <s>    readiness bound (default 240, MXTK_RESTART_TIMEOUT); a boot
#                                         still writing its log past it gets more, up to MXTK_RESTART_MAX (600)
#   ./bin/app-restart.sh --probe          is the recorded app serving? one pass, names the part that is down
#   ./bin/app-restart.sh --if-client-gone after a full build: restart only when the web client is gone AND
#                                         the toolkit started this app; otherwise say so (exit 6)
#
# Exit: 0 up and serving (--probe: up; --if-client-gone: nothing to do, or restarted) ·
#       1 restarted but not proven up (timeout, no bundle) — --probe: not serving · 2 usage ·
#       3 refused — nothing was stopped (no record, record belongs elsewhere, start command unknown,
#         the model's after-startup left on an mxcli test injection — #244) ·
#       4 instrument blocked — the app or admin port is held by a process this script did not record
#         (named, with its pid; never stopped). A run summary records it as blocked, not as FAIL.
#       5 stopped, not started — stopping a `run --test-endpoint` app left its after-startup on
#         MxTest.RegisterEndpoint, and a start would recurse (#244; the repair is printed).
#       6 --if-client-gone: the web client is gone but this app was not started by the toolkit —
#         nothing stopped; the one-line restart hint is printed.
#
# WHY (#289 item 1, field run 2026-10-12). A 20-task UX-fix run over three apps, one lane per app:
# implementers were told never to start or stop apps, because a broad kill in one lane had once
# killed another lane's app. So every restart `run --local --watch` needed (it misses a class of
# model changes — skills/ui-loop.md § "What watch picks up") went through the lead: 24 implementer
# restart-resumes, 41.6M tokens, each resume re-reading a 100-215k context. What the lead did that
# never hit another lane: kill only the one app's process id, wait for the port. This script is
# that, safe for the implementer to call itself.
#
# THE ONE RULE: it stops only the process `mxcli run --local` recorded for THIS project, never
# anything found by name or pattern. The record is <mpr dir>/.mxcli/run-local.json (mxcli v0.24+
# writes it when the app is ready, removes it on exit — the same file bin/test-stack-up.sh reads
# for ownership; see its RUN --LOCAL header). Refuses (exit 3) when:
#   - there is no record → nothing to stop; it never falls back to pgrep/pkill;
#   - the record's "project" is not this project's .mpr → a copied project carries the ORIGINAL's
#     record, and following it would stop someone else's app;
#   - the start command cannot be recovered (below) and --cmd was not given.
# Besides the recorded pid it stops that pid's own child processes, listed BY PARENT PID before
# the stop (`pgrep -P`) — the runtime mxcli started — so an orphaned runtime cannot keep the port.
# On Windows, `taskkill /PID <pid> /T` — the same tree, by pid.
#
# HOW IT RESTARTS "THE SAME WAY": the argv and working directory of the recorded process —
# /proc/<pid>/cmdline + cwd on Linux (exact), `ps -o args=` + lsof cwd on macOS only when nothing is remembered
# (whitespace-split, refused if a path holds a space, never written to start.cmd — #737). Windows processes do not expose their command line to
# Git Bash, so there --cmd is needed the first time. Every successful restart remembers the
# command in .claude/loop/app-restart/start.cmd (self-gitignored, machine-local), so the next one
# — or one after the app died — needs no --cmd. It must be an `mxcli run --local` command; this
# script starts nothing else. Values after password/secret/token/key flags, and of any Name=value whose Name holds one, are masked on screen.
#
# READY means: a new record with a live pid, its port serving index.html, and the JS bundle that
# index.html references (dist/index.js or mxui.js; /dist/index.js for a themed page that names
# neither) answering 2xx with JavaScript — an app serving a blank page because the bundle is missing
# is not up (contrib note 5e, 2026-08-29). The probe is mxtk_app_probe in _common.sh; its header has
# why it no longer looks for Mendix words in the page (#686: 9 false "not proven up" in one run).
# The wait backs off (1, 2, 4, 8 s) and is bounded: --timeout, extended only while the app port is
# still silent AND a start log is still growing (a cold boot with a web-client build can pass 240 s),
# never past MXTK_RESTART_MAX. A failure names the part that is down: no record, the runtime (its
# admin API silent), the app port, or the client bundle.
#
# OWNERSHIP (#686). A successful start here, or test-stack-up.sh's local lane, writes the new pid to
# .claude/loop/app-restart/owner.pid. --if-client-gone restarts only an app whose recorded pid is that
# one — the toolkit started it — via `mxcli run restart` when mxcli's .mxcli/run-state.json (a
# --detach run) is there, else the restart below. Any other app gets the hint, never a stop.
#
# PORTS HELD BY SOMEONE ELSE (#262, field run 2026-10-10): Studio Pro had started its own runtime on
# the same app/admin ports seconds before a restart. `mxcli run --local` then failed with
# "Authentication failed" — the admin API answering was the other runtime's — which reads as a
# credential problem, and the next journey ran against Studio Pro's runtime: no OQL, run INVALID,
# four more runs NOT RUN. So before stopping anything, and again before starting, the app port and
# the admin port (record's adminPort, else app port + 10) must be free or held by the recorded
# process tree; otherwise it exits 4 naming the holder (lsof / ss / netstat) and kills nothing.
#
# LEFTOVER TEST INJECTION (#244, BUG-157): `mxcli test` / `run --test-endpoint` stopped by a signal
# leave the after-startup on MxTest.RegisterEndpoint, and the next start recurses (StackOverflowError)
# or fails at CE1613. It is read from the model bytes (no mxcli) before anything is stopped — refused,
# exit 3, unless the recorded app is a live --test-endpoint run, which holds it legitimately — and
# again after the stop, before the start (exit 5). The repair is printed; this script never writes it.
#
# Never touches Studio Pro, the model, Docker, or another port. Docker stack: bin/test-stack-up.sh
# --restart (scoped to this project's container). Bash 3.2 / Git Bash / macOS / Linux.
set -uo pipefail

. "$(dirname "$0")/_common.sh"

DRY=0; CMD_OVERRIDE="${MXTK_APP_START_CMD:-}"; TIMEOUT="${MXTK_RESTART_TIMEOUT:-240}"; MODE=restart
MAXWAIT="${MXTK_RESTART_MAX:-600}"; QUIET="${MXTK_RESTART_QUIET:-20}"
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --probe)   MODE=probe ;;
    --if-client-gone) MODE=client ;;
    --cmd)     shift; CMD_OVERRIDE="${1:-}" ;;
    --timeout) shift; TIMEOUT="${1:-}" ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "usage: $0 [--dry-run] [--probe] [--if-client-gone] [--cmd '<start command>'] [--timeout <seconds>]" >&2; exit 2 ;;
  esac
  shift
done
case "$TIMEOUT" in ''|*[!0-9]*) echo "app-restart: --timeout takes whole seconds" >&2; exit 2 ;; esac
case "$MAXWAIT$QUIET" in *[!0-9]*) MAXWAIT=600; QUIET=20 ;; esac
[ "$MAXWAIT" -lt "$TIMEOUT" ] && MAXWAIT="$TIMEOUT"

refuse() { echo "✗ app-restart: $1" >&2; shift; for l in "$@"; do echo "  $l" >&2; done; echo "  Nothing was stopped." >&2; exit 3; }

MPR="$(find_mpr)" || exit 2
_real() { (cd "$(dirname "$1")" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "$(basename "$1")"); }
MPR_DIR="$(cd "$(dirname "$MPR")" && pwd)"
MPR_REAL="$(_real "$MPR")"
MPR_TARGET="$MPR_REAL"
MODEL_DIR="$MPR_DIR"
if [ -L "$MPR" ]; then   # two-tree checkout: a root symlink to app/X.mpr; mxcli writes beside -p
  _t="$(readlink "$MPR")"; case "$_t" in /*) ;; *) _t="$MPR_DIR/$_t" ;; esac
  MPR_TARGET="$(_real "$_t")"; MODEL_DIR="$(dirname "$MPR_TARGET")"
fi
HS=""
for _d in "$MPR_DIR" "$MODEL_DIR"; do [ -f "$_d/.mxcli/run-local.json" ] && { HS="$_d/.mxcli/run-local.json"; break; }; done

hs_num()  { sed -n "s/^  \"$1\": *\([0-9][0-9]*\).*/\1/p" "$2" 2>/dev/null | head -1; }
hs_str()  { sed -n "s/^  \"$1\": *\"\(.*\)\",\{0,1\} *$/\1/p" "$2" 2>/dev/null | head -1 | sed 's/\\\\/\\/g'; }
pid_alive() {
  [ -n "${1:-}" ] || return 1
  case "$(mxtk_platform)" in
    windows) grep -q " $1 " <<<"$(tasklist //FI "PID eq $1" //NH 2>/dev/null)" ;;   # mxcli.exe records a Windows pid
    *)       kill -0 "$1" 2>/dev/null || return 1
             # a zombie answers kill -0 until something reaps it; on Linux /proc says Z
             case "$(sed 's/.*) //' "/proc/$1/stat" 2>/dev/null | cut -d' ' -f1)" in Z) return 1 ;; esac ;;
  esac
}
port_answers() { local c; c="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://localhost:$1/" 2>/dev/null)"; [ -n "$c" ] && [ "$c" != "000" ]; }
mask_has_secret() {  # pure bash glob: does $1 hold a secret word? (no fork)
  case "$1" in
    *[Pp][Aa][Ss][Ss]*|*[Pp][Ww][Dd]*|*[Ss][Ee][Cc][Rr][Ee][Tt]*|*[Tt][Oo][Kk][Ee][Nn]*|*[Kk][Ee][Yy]*|*[Cc][Rr][Ee][Dd][Ee][Nn][Tt][Ii][Aa][Ll]*) return 0 ;;
  esac
  return 1
}
mask() {  # print argv joined, with the value after any password/secret/token/key flag masked
  # Display only (TK-003): the executed ARGV is never touched. Each argument is masked on its own,
  # BEFORE it is quoted for display, so a quoted secret with spaces is hidden whole. Passes:
  # (0) the argument after a secret-named flag is a secret, whole; (1) the argument IS `Name=value`
  # with a secret Name: everything after `=` is masked, spaces included (the argv form of
  # `--constant "Mod.ApiKey=two words"`); (2) inside a shell string (`--cmd '...'`) a quoted
  # `"Name=value with spaces"` / `'Name=...'`; (3) a secret-named FLAG masks its value, as
  # `--db-password v`, `--db-password=v`, `--db-password "two words"`; (4) ANY `Name=value` whose Name
  # holds a secret word masks the value, quoted or not. Known over-mask, kept: the word match is a
  # substring, so `Monkey` (Key), `Turkey` (Key) and `Bypass` (Pass) mask too. Display only, harmless.
  local _w='([Pp][Aa][Ss][Ss]|[Pp][Ww][Dd]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Tt][Oo][Kk][Ee][Nn]|[Kk][Ee][Yy]|[Cc][Rr][Ee][Dd][Ee][Nn][Tt][Ii][Aa][Ll])'
  local _v="\"[^\"]*\"|'[^']*'|[^ ]+"
  # Speed: the sed forks only run for an argument that holds a secret word (a bash glob decides),
  # so a typical argv costs no fork at all. The argument after `-c` is a shell string: pass (1) is
  # skipped for it, so `bash -c 'DB_PASSWORD=x ./mxcli run ...'` keeps the whole command visible.
  local a out="" prev_secret=0 prev_c=0 p1
  for a in "$@"; do
    p1='s/^$//'
    if [ "$prev_secret" = 1 ]; then a="****"; prev_secret=0; prev_c=0
    else
      if [ "$prev_c" = 1 ]; then prev_c=0
      else
        p1="s/^([A-Za-z0-9_.-]*${_w}[A-Za-z0-9_.-]*)=.*$/\\1=****/"
        case "$a" in
          -c) prev_c=1 ;;
          -*" "*|-*=*) ;;                                              # flag=value or a shell string: sed below
          -*[!-A-Za-z_]*) ;;
          -*) mask_has_secret "$a" && prev_secret=1 ;;
        esac
      fi
      if mask_has_secret "$a"; then
        a="$(printf '%s' "$a" | sed -E \
          -e "$p1" \
          -e "s/\"([A-Za-z0-9_.-]*${_w}[A-Za-z0-9_.-]*)=[^\"]*\"/\"\\1=****\"/g" \
          -e "s/'([A-Za-z0-9_.-]*${_w}[A-Za-z0-9_.-]*)=[^']*'/'\\1=****'/g" \
          -e "s/(-[-A-Za-z_]*${_w}[-A-Za-z_]*)(=| +)(${_v})/\\1\\3****/g" \
          -e "s/([A-Za-z0-9_.-]*${_w}[A-Za-z0-9_.-]*)=(${_v})/\\1=****/g")"
      fi
    fi
    case "$a" in *" "*) a="'$a'" ;; esac
    out="$out $a"
  done
  printf '%s\n' "${out# }"
}

# Port and process helpers (mxtk_port_holder, mxtk_holder_text, mxtk_pid_in_tree) live in
# _common.sh, shared with test-stack-up.sh. A project whose bin/_common.sh predates them stops here
# with the remedy, instead of dying mid-restart on "command not found".
command -v mxtk_port_holder >/dev/null 2>&1 && command -v mxtk_app_probe >/dev/null 2>&1 || {
  echo "app-restart: bin/_common.sh is older than this script (no mxtk_port_holder / mxtk_app_probe)." >&2
  echo "  → <toolkit>/bin/sync-project.sh $PROJECT_ROOT --only-bin _common.sh --upgrade-bin _common.sh   (installs just that file; backs up a hand-edited copy first)" >&2; exit 2; }
# blocked <port> "<pid>|<name>" <when> — exit 4, the holder named, nothing of it touched.
blocked() {
  echo "✗ app-restart: instrument blocked — port :$1 is held by $(mxtk_holder_text "$2"), not this project's run --local." >&2
  echo "  $3. This script never stops a process it did not record, so it is not touching that one." >&2
  echo "  Starting now would collide: mxcli reports 'Authentication failed' against the other runtime's admin API." >&2
  echo "  → Stop that process yourself (Studio Pro: stop its run), or start on free ports:" >&2
  echo "    ./bin/app-restart.sh --cmd './mxcli run --local --watch -p $(basename "$MPR") --app-port <free> --admin-port <free>'" >&2
  echo "  Record this run as INSTRUMENT BLOCKED, not as a test failure." >&2
  exit 4
}
# ── After-startup left on an mxcli test injection (#244, BUG-157) ───────────
# The reader (mxtest_after_startup / mxtest_left / mxtest_refusal) and the pid check
# (mxtk_pid_is_mxcli_run) live in _common.sh, shared with test-scratch.sh. Same stop as above for a
# _common.sh that predates them.
command -v mxtest_left >/dev/null 2>&1 && command -v mxtk_pid_is_mxcli_run >/dev/null 2>&1 || {
  echo "app-restart: bin/_common.sh is older than this script (no mxtest_left / mxtk_pid_is_mxcli_run)." >&2
  echo "  → <toolkit>/bin/sync-project.sh $PROJECT_ROOT --only-bin _common.sh --upgrade-bin _common.sh   (installs just that file; backs up a hand-edited copy first)" >&2; exit 2; }
# in_our_tree <pid> — the recorded pid itself, or a descendant of it (the runtime mxcli started).
in_our_tree() { [ "$ALIVE" = 1 ] && mxtk_pid_in_tree "$1" "$PID"; }

# ── Readiness wait (READY in the header) ────────────────────────────────────
# _logsz — total bytes of the logs a booting app writes: our start log, and mxcli's own run.log /
# runtime.log beside the model. Growth between two probes is the only "still booting" signal used.
_logsz() {
  local f n t=0
  for f in "$LOG" "$MPR_DIR/.mxcli/run.log" "$MPR_DIR/.mxcli/runtime.log" "$MODEL_DIR/.mxcli/run.log" "$MODEL_DIR/.mxcli/runtime.log"; do
    [ -f "$f" ] || continue
    n="$(wc -c < "$f" 2>/dev/null | tr -d ' ')"; t=$((t + ${n:-0}))
  done
  echo "$t"
}
mark_owned() {  # $1 = pid the toolkit just started — read by --if-client-gone
  mkdir -p "$REC_DIR" 2>/dev/null && { [ -f "$REC_DIR/.gitignore" ] || printf '*\n' > "$REC_DIR/.gitignore"; } \
    && printf '%s\n' "$1" > "$REC_DIR/owner.pid" 2>/dev/null || true
}
wait_ready() {  # exits: 0 up, 1 not proven up
  local t0 now el cap sz lsz lchg w=1 h np told=0
  t0=$(date +%s); lchg=0; cap="$TIMEOUT"; lsz="$(_logsz)"   # only growth from here counts as progress
  while :; do
    NEWPORT=""; NEWADMIN=""; NEWPID=""
    for _d in "$MPR_DIR" "$MODEL_DIR"; do
      h="$_d/.mxcli/run-local.json"
      [ -f "$h" ] || continue
      np="$(hs_num pid "$h")"
      if pid_alive "$np"; then NEWPID="$np"; NEWPORT="$(hs_num appPort "$h")"; NEWADMIN="$(hs_num adminPort "$h")"; break; fi
    done
    if [ -n "$NEWPORT" ] && mxtk_app_probe "$NEWPORT" "$NEWADMIN"; then
      [ "$NEWPORT" != "$PORT" ] && echo "  ! the app came back on :$NEWPORT (was :$PORT)"
      mark_owned "$NEWPID"
      echo "✓ app-restart: serving on :$NEWPORT after $(( $(date +%s) - t0 ))s — bundle $MXTK_PROBE_BUNDLE answers"
      exit 0
    fi
    [ -n "$NEWPORT" ] || MXTK_PROBE_DOWN="no new run --local record with a live pid yet (mxcli writes it once the app is up)"
    now=$(date +%s); el=$((now - t0))
    sz="$(_logsz)"; [ "$sz" != "$lsz" ] && { lsz="$sz"; lchg=$now; }
    if [ "$el" -ge "$cap" ]; then
      # Still booting: nothing serves on the app port yet, and a log moved within QUIET seconds.
      # A served page with a missing bundle is not "booting" — that is the full-build case, and waiting
      # does not fix it.
      case "$MXTK_PROBE_DOWN" in
        "no new run --local record"*|"app port :"*)
          if [ "$cap" -lt "$MAXWAIT" ] && [ $((now - lchg)) -lt "$QUIET" ]; then
            cap=$((cap + QUIET)); [ "$cap" -gt "$MAXWAIT" ] && cap="$MAXWAIT"
            [ "$told" = 1 ] || echo "  … still booting at ${el}s (its log is still growing) — waiting up to ${MAXWAIT}s"
            told=1
          else break; fi ;;
        *) break ;;
      esac
    fi
    [ $((el + w)) -gt "$cap" ] && w=$((cap - el)); [ "$w" -lt 1 ] && w=1
    sleep "$w"; w=$((w * 2)); [ "$w" -gt 8 ] && w=8
  done
  echo "✗ app-restart: not proven up after ${el}s — down: $MXTK_PROBE_DOWN" >&2
  case "$MXTK_PROBE_DOWN" in
    "client bundle"*) echo "  Page bundle not served: $MXTK_PROBE_BUNDLE — a blank page, not an app (see $LOG)" >&2 ;;
    *) echo "  See $LOG" >&2 ;;
  esac
  exit 1
}

# ── 1. The record ───────────────────────────────────────────────────────────
[ -n "$HS" ] || refuse "no run --local record for this project (.mxcli/run-local.json beside $(basename "$MPR"))." \
  "This app was not started with \`mxcli run --local\` (v0.24+), or it is not running. This script never" \
  "stops a process found by name or pattern, so there is nothing it may stop." \
  "→ Start it:   ./mxcli run --local --watch -p $(basename "$MPR")" \
  "→ Docker app: ./bin/test-stack-up.sh --restart"
PID="$(hs_num pid "$HS")"; PORT="$(hs_num appPort "$HS")"; HS_PROJECT="$(hs_str project "$HS")"
[ -n "$PORT" ] || refuse "the record $HS names no appPort — cannot tell which app it is."
[ -n "$HS_PROJECT" ] || refuse "the record $HS names no project — cannot prove it is this project's app." \
  "Stop the app yourself and start it again; do not let a script guess."
case "$HS_PROJECT" in [A-Za-z]:*) HS_PROJECT="$(mxtk_posix_path "$HS_PROJECT")" ;; esac
HS_REAL="$(_real "$HS_PROJECT")"
if [ "$HS_REAL" != "$MPR_REAL" ] && [ "$HS_REAL" != "$MPR_TARGET" ] \
   && [ "$(printf '%s' "$HS_REAL" | tr '[:upper:]' '[:lower:]')" != "$(printf '%s' "$MPR_TARGET" | tr '[:upper:]' '[:lower:]')" ]; then
  refuse "the run --local record here belongs to another project:" \
    "record:  $HS_PROJECT" "this:    $MPR_TARGET" \
    "A copied project carries the original's record; stopping its pid would stop someone else's app."
fi
# The recorded pid must still BE an mxcli run (#304 review). A SIGKILLed mxcli leaves its record
# behind, and the OS hands its pid to an unrelated process; `kill -0` cannot tell the difference,
# and the start-command check below cannot either when --cmd / MXTK_APP_START_CMD supplies the
# command — so without this a stale record plus a reused pid sent TERM/KILL to that process and
# its children. Checked on the pid itself, whichever way the start command is learned: its
# command line names mxcli and `run` (mxtk_pid_is_mxcli_run in _common.sh); on Windows the
# image name is mxcli.exe. Anything else is treated as not running: never stopped, and if it
# holds one of the ports the port check below names it and stops.
ALIVE=0
if pid_alive "$PID"; then
  if mxtk_pid_is_mxcli_run "$PID"; then ALIVE=1
  else echo "  ! recorded pid $PID is alive but is not an mxcli run (the pid was reused after the app died) — treating the app as not running; that process is not touched"; fi
fi
REC_ADMIN="$(hs_num adminPort "$HS")"   # the probe uses only a recorded admin port, never a guess
ADMIN_PORT="$REC_ADMIN"; [ -n "$ADMIN_PORT" ] || ADMIN_PORT=$((PORT + 10))
REC_DIR="$PROJECT_ROOT/.claude/loop/app-restart"; REC="$REC_DIR/start.cmd"
LOG="${LOGDIR:-${TMPDIR:-/tmp}}/$(basename "$MPR" .mpr)-run-local.log"

# ── 1b. --probe / --if-client-gone: look before touching anything ───────────
if [ "$MODE" = probe ]; then
  [ "$ALIVE" = 1 ] || { echo "✗ app-restart --probe: the recorded app (pid $PID) is not running — start it: ./bin/app-restart.sh"; exit 1; }
  if mxtk_app_probe "$PORT" "$REC_ADMIN"; then
    echo "✓ app-restart --probe: serving on :$PORT (pid $PID) — bundle $MXTK_PROBE_BUNDLE answers"; exit 0
  fi
  echo "✗ app-restart --probe: :$PORT is not serving — down: $MXTK_PROBE_DOWN"; exit 1
fi
if [ "$MODE" = client ]; then
  [ "$ALIVE" = 1 ] || { echo "→ app-restart: no running app recorded for this project — nothing to restart after the build"; exit 0; }
  if mxtk_app_probe "$PORT" "$REC_ADMIN"; then
    echo "✓ app-restart: the web client is still served on :$PORT after the build — no restart"; exit 0
  fi
  _own=""; [ -f "$REC_DIR/owner.pid" ] && read -r _own < "$REC_DIR/owner.pid"
  if [ "$_own" != "$PID" ]; then
    echo "→ app-restart: after the full build :$PORT is not serving — $MXTK_PROBE_DOWN"
    echo "  This app (pid $PID) was not started by the toolkit, so it is not restarted here."
    echo "  → run \`mxcli run restart -p $(basename "$MPR")\` (or ./bin/app-restart.sh) before the next LOOK"
    exit 6
  fi
  echo "→ app-restart: after the full build :$PORT is not serving ($MXTK_PROBE_DOWN)."
  echo "  The toolkit started this app (pid $PID), so it restarts it now."
  _rs=""; for _d in "$MPR_DIR" "$MODEL_DIR"; do [ -f "$_d/.mxcli/run-state.json" ] && { _rs=1; break; }; done
  _mx="$(find_project_mxcli 2>/dev/null || command -v mxcli 2>/dev/null || true)"
  if [ -n "$_rs" ] && [ -n "$_mx" ]; then
    echo "  mxcli run restart -p $(basename "$MPR")   (a --detach run: mxcli restarts it with its own arguments)"
    "$_mx" run restart -p "$MPR" >>"$LOG" 2>&1 </dev/null || echo "  ! mxcli run restart exited $? — see $LOG; checking the app anyway"
    wait_ready
  fi
  # No run-state.json (not a --detach run) or no mxcli here: the recorded-pid restart below.
fi

# ── 2. How it was started ───────────────────────────────────────────────────
ARGV=(); START_CWD=""; HOW=""; PS_DERIVED=0
if [ -n "$CMD_OVERRIDE" ]; then
  ARGV=(bash -c "$CMD_OVERRIDE"); START_CWD="$PROJECT_ROOT"; HOW="--cmd"
elif [ "$ALIVE" = 1 ] && [ -r "/proc/$PID/cmdline" ]; then
  while IFS= read -r -d '' _a; do ARGV+=("$_a"); done < "/proc/$PID/cmdline"
  START_CWD="$(readlink "/proc/$PID/cwd" 2>/dev/null || true)"; HOW="/proc/$PID/cmdline"
elif [ "$ALIVE" = 1 ] && [ "$(mxtk_platform)" = macos ] && [ ! -f "$REC" ]; then
  # Last resort, only with nothing remembered (#737: this used to run BEFORE start.cmd and then
  # overwrote a good start.cmd). `ps` joins argv with spaces, so it is lossy: refuse when a path
  # we know of holds whitespace, and never write what it returned to start.cmd.
  for _p in "$PROJECT_ROOT" "$MPR"; do
    case "$_p" in *[[:space:]]*) refuse "this app's start command cannot be read back exactly on macOS: a path holds a space ($_p)." \
      "→ Pass it once: ./bin/app-restart.sh --cmd './mxcli run --local --watch -p \"<project>.mpr\"'" \
      "  (the exact command you started it with; it is remembered for the next restart)" ;; esac
  done
  # shellcheck disable=SC2207
  ARGV=($(ps -o args= -p "$PID" 2>/dev/null)); PS_DERIVED=1
  START_CWD="$(lsof -a -p "$PID" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)"
  case "$START_CWD" in *[[:space:]]*) refuse "this app's working directory holds a space ($START_CWD); \`ps\` cannot give its start command back exactly." \
    "→ Pass it once: ./bin/app-restart.sh --cmd '<the exact start command>'" ;; esac
  HOW="ps -o args= (whitespace-split, never remembered — pass --cmd if an argument held a space)"
fi
if [ ${#ARGV[@]} -eq 0 ] && [ -f "$REC" ]; then
  START_CWD="$(head -1 "$REC")"
  while IFS= read -r _a; do ARGV+=("$_a"); done < <(sed '1d' "$REC")
  HOW="remembered from the last restart ($REC)"
  # A start.cmd written by the pre-#737 macOS code holds the argv split at spaces: its first element
  # is then a path that does not exist. Say so instead of letting nohup fail 240 s later.
  case "${ARGV[0]:-}" in */*) [ -x "${ARGV[0]}" ] || [ -x "${START_CWD:-.}/${ARGV[0]}" ] || refuse "the remembered start command in $REC is not runnable: ${ARGV[0]} does not exist (an older version split it at a space)." \
    "→ Pass it once: ./bin/app-restart.sh --cmd '<the exact start command>' (this replaces the remembered one)" ;; esac
fi
[ -d "${START_CWD:-/nonexistent}" ] || START_CWD="$PROJECT_ROOT"
if [ ${#ARGV[@]} -eq 0 ]; then
  refuse "cannot recover how this app was started (pid $PID$([ "$ALIVE" = 1 ] || echo ', not running'); $(mxtk_platform) does not expose it)." \
    "→ Pass it once: ./bin/app-restart.sh --cmd './mxcli run --local --watch -p $(basename "$MPR")'" \
    "  (the exact command you started it with; it is remembered for the next restart)"
fi
case " ${ARGV[*]} " in
  *" run "*"--local"*) ;;
  *) refuse "the recorded process is not an \`mxcli run --local\` ($(mask "${ARGV[@]}"))." \
       "This script restarts only that; it will not start anything else." ;;
esac


# ── 2a. The model must not carry a leftover mxcli test injection (#244) ─────
# A live `run --test-endpoint` legitimately holds the injection while it runs; its stop is supposed
# to restore it, which 3b re-checks before anything starts. In every other case the start would
# recurse in the after-startup, so refuse before stopping anything.
LIVE_ENDPOINT=0
if [ "$ALIVE" = 1 ]; then case " ${ARGV[*]} " in *" --test-endpoint "*|*" --test-endpoint="*) LIVE_ENDPOINT=1 ;; esac; fi
if mxtest_left "$MODEL_DIR" "$MPR_TARGET" && [ "$LIVE_ENDPOINT" = 0 ]; then
  mxtest_refusal "app-restart"
  echo "  Nothing was stopped." >&2
  exit 3
fi

echo "→ app-restart: $(basename "$MPR") on :$PORT"
if [ "$ALIVE" = 1 ]; then echo "  stop:  pid $PID (from $HS) and its own child processes"
else echo "  stop:  nothing — recorded pid $PID is not running"; fi
echo "  start: $(mask "${ARGV[@]}")"
echo "         in $START_CWD   [$HOW]"
echo "  ports: app :$PORT, admin :$ADMIN_PORT"

# ── 2b. Ports: free, or held by the recorded tree — never by someone else ───
# Checked before anything is stopped, so a collision costs nothing. When the recorded app is alive
# and the holder cannot be placed in its tree (no name, or Windows where Git Bash shows no parent
# pids), it is left to the post-stop check below, which is exact: after our tree is gone, whatever
# still holds the port is not ours.
for _p in "$PORT" "$ADMIN_PORT"; do
  _h="$(mxtk_port_holder "$_p")" || continue
  if [ "$ALIVE" = 1 ]; then
    case "${_h%%|*}" in '?') continue ;; esac
    [ "$(mxtk_platform)" = windows ] && continue
    in_our_tree "${_h%%|*}" && continue
  fi
  blocked "$_p" "$_h" "Nothing was stopped"
done
[ "$DRY" = 1 ] && { echo "  (dry run — nothing stopped or started)"; exit 0; }

# ── 3. Stop exactly that process tree ───────────────────────────────────────
if [ "$ALIVE" = 1 ]; then
  if [ "$(mxtk_platform)" = windows ]; then
    taskkill //PID "$PID" //T //F >/dev/null 2>&1 || true
  else
    KIDS="$(pgrep -P "$PID" 2>/dev/null | tr '\n' ' ' || true)"   # portability-ok: pgrep -P (by parent pid) ships with Linux procps and macOS; Windows takes taskkill above
    kill -TERM "$PID" 2>/dev/null || true
    for _i in $(seq 1 30); do pid_alive "$PID" || break; sleep 1; done
    pid_alive "$PID" && { echo "  pid $PID ignored TERM for 30s — KILL"; kill -KILL "$PID" 2>/dev/null || true; }
    for _k in $KIDS; do kill -TERM "$_k" 2>/dev/null || true; done
    sleep 1
    for _k in $KIDS; do kill -0 "$_k" 2>/dev/null && kill -KILL "$_k" 2>/dev/null || true; done
  fi
  echo "  ✓ stopped pid $PID"
fi
_busy=""
for _i in $(seq 1 30); do
  _busy=""
  for _p in "$PORT" "$ADMIN_PORT"; do mxtk_port_holder "$_p" >/dev/null && { _busy="$_p"; break; }; done
  [ -z "$_busy" ] && ! port_answers "$PORT" && break
  sleep 1
done
if [ -n "$_busy" ]; then
  blocked "$_busy" "$(mxtk_port_holder "$_busy" || echo '?|an unidentified process')" "The recorded app was stopped; nothing was started"
elif port_answers "$PORT"; then
  blocked "$PORT" "?|an unidentified process" "The recorded app was stopped; nothing was started"
fi


# ── 3b. Did the stop leave the test injection behind? (#244) ───────────────
# A `run --test-endpoint` stopped by a signal can skip its restore; starting it again would chain
# MxTest.RegisterEndpoint to itself. The app is down now — say so plainly, and start nothing.
if mxtest_left "$MODEL_DIR" "$MPR_TARGET"; then
  mxtest_refusal "app-restart"
  echo "  The recorded app was stopped; nothing was started (exit 5)." >&2
  exit 5
fi

# ── 4. Start it the same way, detached, and remember how ────────────────────
rm -f "$HS" 2>/dev/null || true   # a SIGKILLed mxcli leaves its record behind; the new one must be new
if command -v setsid >/dev/null 2>&1; then
  ( cd "$START_CWD" && exec setsid nohup "${ARGV[@]}" >>"$LOG" 2>&1 </dev/null ) &
else
  ( cd "$START_CWD" && exec nohup "${ARGV[@]}" >>"$LOG" 2>&1 </dev/null ) &
fi
disown 2>/dev/null || true
echo "  ✓ started (log: $LOG)"
if [ "$HOW" != "remembered from the last restart ($REC)" ] && [ "$PS_DERIVED" != 1 ]; then
  mkdir -p "$REC_DIR" && { [ -f "$REC_DIR/.gitignore" ] || printf '*\n' > "$REC_DIR/.gitignore"; }
  { printf '%s\n' "$START_CWD"; printf '%s\n' "${ARGV[@]}"; } > "$REC" 2>/dev/null || true
fi

# ── 5. Ready = new record, live pid, its port serving, bundle 2xx (wait_ready above) ─
wait_ready
