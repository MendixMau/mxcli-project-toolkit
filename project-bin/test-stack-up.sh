#!/usr/bin/env bash
# test-stack-up.sh — bring the test stack up, and PROVE it is up.
#
# WHY THIS EXISTS. It is the precondition step for any e2e run, and the crash-net scripts cannot do
# the job: every exit path of restart-sp.sh ends with "click Run Locally in Studio Pro", which blocks
# every test run on a human. This script brings the stack up unattended and — the part that matters —
# proves the thing that answered is THIS project's application.
#
# DESIGN RULES, all deliberate:
#   1. NEVER touches Studio Pro. No force-quit, no kill. It detects SP and reports; that is all.
#      restart-sp.sh owns crash recovery and warns that unsaved work is lost. This must be safe to
#      run while someone else is working in SP.
#   2. Never writes model CONTENT. Measured (field run 2026-10-07, existing app): a `mxcli docker
#      run` / `docker build` runs `mx update-widgets` first, which rewrites widget definitions in the
#      .mpr — git showed it modified after a build that failed. That is a widget-definition refresh,
#      not a change anyone authored, but it IS a write: commit or snapshot before a build, and never
#      run one while Studio Pro has the model open.
#   3. Proves liveness with an actual HTTP response. "No error" is not "up".
#   4. Idempotent, but never STALE. If the app already answers and was built from the current model,
#      it does nothing and exits 0. If the model changed since this script last built it, an app
#      that answers is serving the OLD model — every test then measures yesterday's build and a
#      fixed bug "still fails". So it hot-reloads (`mxcli docker reload`: build + reload_model,
#      no container restart) and falls back to a restart only if the reload fails. See WARM LOOP.
#   5. Starts an auxiliary service if it is down; NEVER stops one (another session may be using it).
#
# Usage:
#   bin/test-stack-up.sh --check     # report only, change nothing. Exit 0 iff required deps are up.
#   bin/test-stack-up.sh             # report, then bring up what is missing (may run a Docker build)
#   bin/test-stack-up.sh --no-docker # bring up auxiliaries only; never build. "SP is already running it".
#   bin/test-stack-up.sh --restart   # skip the hot reload; rebuild and restart the container (old path)
#   bin/test-stack-up.sh --track <pid> [label]  # record a background test process THIS project started
#   bin/test-stack-up.sh --reap      # stop recorded processes older than MXTK_STALE_HOURS; nothing else
#
# WARM LOOP. After a model change the old loop was: exec.sh gate (mxbuild) -> `docker run` (mx check +
# mxbuild again) -> container restart -> boot wait. Now: the app's model is recorded in
# .claude/loop/served-model (the model-stamp fingerprint at the moment this script built it); when
# the current fingerprint differs, `mxcli docker reload` rebuilds and swaps the model into the
# running runtime instead of restarting it, and passes --skip-check when model-stamp says the
# current model already passed an mxbuild (the exec.sh gate) — that check was the duplicate.
# Entity/association changes need a DB sync that reload_model may not do; if the reload fails or the
# app stops answering, it falls back to the restart. MXTK_WARM_RELOAD=off keeps the old idempotent
# no-op. Measured (field run 2026-10-07, existing app, cloud container, one page change):
#   docker run --wait, cold                         190 s
#   restart (docker run --wait over a running app)  179 s
#   docker reload, with the duplicate check         140 s
#   docker reload --skip-check                       93 s  (reload_model itself 0.6 s; the build is the rest)
#   mxcli run --local --watch, page change           ~18 s from exec to applied (security/nav change: ~60 s restart)
# So the fastest loop is not this script: keep `mxcli run --local --watch` running beside the
# session and let it apply each exec (skills/ui-loop.md). This script is the Docker path and the
# proof-of-ownership step. `docker reload --css` is NOT a theme loop: it copies the theme without
# compiling SCSS, so a main.scss edit does not show.
#
# RUN --LOCAL IS RECOGNISED, NOT REPLACED. `mxcli run --local` (v0.24+) publishes
# <mpr dir>/.mxcli/run-local.json while it serves — pid and app port, written when the app is ready,
# removed on exit. A live pid in OUR project's directory plus a Mendix answer on its port is the same
# kind of claim as the compose label: it cannot be true of two projects at once. So that app is
# ownership `verified` (APP_SOURCE=run-local), where it used to scan as `unverified` and the e2e
# config refused it — the recommended fast loop was the one the harness would not test. This script
# never restarts or reloads it (it did not start it): `--watch` applies each change itself, and
# without --watch a model newer than the handshake is reported stale with the restart to run. Only
# pid and appPort are read; the file also holds the admin password and boot config, never copied.
#
# Exit codes: 0 = required stack is up · 1 = not up and could not fix · 2 = usage/env error ·
#             4 = instrument blocked: the port `mxcli run --local` needs is held by another process
#                 (named with its pid, never stopped) — record it as blocked, not as a test failure
#
# PORT HELD BEFORE RUN --LOCAL (#262, field run 2026-10-10). Studio Pro had started its own runtime on
# the app/admin ports a run --local restart needed. mxcli failed with "Authentication failed" (the
# admin API answering was Studio Pro's), and the journeys then ran against Studio Pro's runtime: run
# INVALID. Wherever this script would tell you to start `mxcli run --local`, it first checks that
# loop's app and admin port — from a leftover run-local.json, else RUN_LOCAL_APP_PORT /
# RUN_LOCAL_ADMIN_PORT (stack.conf), else mxcli's defaults 8080 / app port + 10 — and exits 4
# naming the holder (lsof / ss; netstat on Windows) instead of advising a start that cannot work.
#
# RUNTIME PROOF WITHOUT A HANDSHAKE (#160, field run 2026-09-25, requirements-driven build). An app
# with no run-local.json — Studio Pro's Run Locally, or a run --local older than the handshake — was
# found by scan and published APP_OWNERSHIP=unverified, so every journey run needed APP_PORT
# asserted by hand. The proof was there all along: the runtime's command line runs
# `runtimelauncher.jar <project>/app/deployment`, and a deployment directory belongs to one checkout.
# So a scanned Mendix port whose listener (lsof / ss / netstat) runs runtimelauncher.jar on THIS
# project's deployment dir (<root>/deployment, <root>/app/deployment, or beside the real .mpr) is
# `verified` with APP_SOURCE=runtime. Freshness stays `unknown` — this script did not build it.
# Command line: /proc on Linux, `ps -o args=` on macOS, PowerShell CIM on Git Bash (_common.sh's
# mxtk_pid_runs_deployment). Unreadable → `unverified`, exactly as before.
#
# OWN PROCESS ON THE PORT IS NOT A THIEF (follow-up to #262). The port check above must not name
# this project's own runtime: while it boots it binds its ports before it serves a page, and the
# check said "INSTRUMENT BLOCKED" (exit 4) about it. A holder is ours — reported NOT READY, exit 1
# — when it is the live recorded run --local pid or a descendant of it, or when its command line
# runs this project's deployment dir (that includes Studio Pro running THIS project). Anything else
# still blocks.
#
# STALE TEST PROCESSES (#278, field run 2026-10-12). A night of retries left journey-runner and
# monitor shells running for hours; a later run then hit the trial licence's session cap and was
# INVALID. Every run of this script lists the recorded processes older than MXTK_STALE_HOURS
# (default 4) and prints the one command that stops them; --reap does it. It acts ONLY on
# .claude/loop/bg-pids.tsv — lines `<pid> TAB <epoch> TAB <ps lstart> TAB <label>` written by
# `--track <pid> [label]` for a process this project started — never on a process found by name
# or pattern, so another project's runner is out of reach by construction. A pid whose start time
# no longer matches its line was reused by an unrelated process and is dropped, never signalled.
# Not on Git Bash: its ps cannot show a Windows process's start time, so nothing is reaped there.
#
# PROJECT CONFIGURATION — no project name, port or service path is hardcoded here. Put anything
# project-specific in <project>/.claude/loop/stack.conf, which this script sources if present:
#
#   APP_PORTS="8080 8081"                                # fallback scan list; ownership beats it
#   JAEGER_PORT=16686                                    # OTel collector UI (optional)
#   MOCK_HEALTH_URL="http://localhost:3001/api/health"   # set to enable the mock rung
#   MOCK_PORT=3001
#   MOCK_DIR="source/mock-api"                           # dir containing server.js
#   MOCK_START="node server.js"                          # command run inside MOCK_DIR
#   BOOT_TIMEOUT=240
#   MXTK_STALE_HOURS=4                                   # age at which a tracked process is stale
#
# With no MOCK_HEALTH_URL the mock rung is reported as "not configured" and does not gate — most
# projects have no mock, and a rung that fails for everyone gets switched off, taking the real
# rungs with it.

set -uo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
cd "$PROJECT_ROOT" || { echo "cannot cd to project root" >&2; exit 2; }
ROOT="$PROJECT_ROOT"

MPR="$(find_mpr)" || exit 2
PROJ="$(project_name)" || PROJ="app"

STACK_CONF="${STACK_CONF:-$ROOT/.claude/loop/stack.conf}"
# shellcheck disable=SC1090
[ -f "$STACK_CONF" ] && . "$STACK_CONF"

APP_PORTS="${APP_PORTS:-8080 8081 8084}"
JAEGER_PORT="${JAEGER_PORT:-16686}"
MOCK_HEALTH_URL="${MOCK_HEALTH_URL:-}"
MOCK_PORT="${MOCK_PORT:-}"
MOCK_DIR="${MOCK_DIR:-}"
MOCK_START="${MOCK_START:-node server.js}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-240}"
LOGDIR="${LOGDIR:-${TMPDIR:-/tmp}}"
MOCK_LOG="$LOGDIR/${PROJ}-mock.log"
DOCKER_LOG="$LOGDIR/${PROJ}-docker-run.log"

# mxcli lives in the project root on a wired project, but may be on PATH instead.
if [ -x "$ROOT/mxcli" ]; then MXCLI="$ROOT/mxcli"
elif command -v mxcli >/dev/null 2>&1; then MXCLI="mxcli"
else MXCLI=""; fi

MODE="up"
case "${1:-}" in
  --check)     MODE="check" ;;
  --no-docker) MODE="nodocker" ;;
  --restart)   MODE="restart" ;;
  --reap)      MODE="reap" ;;
  --track)     MODE="track" ;;
  "")          ;;
  *) echo "usage: $0 [--check|--no-docker|--restart|--reap|--track <pid> [label]]" >&2; exit 2 ;;
esac

# Helpers moved to _common.sh (#160). A project whose bin/_common.sh predates them stops here with
# the remedy instead of dying mid-run on "command not found".
command -v mxtk_pid_runs_deployment >/dev/null 2>&1 || {
  echo "test-stack-up: bin/_common.sh is older than this script (no mxtk_pid_runs_deployment)." >&2
  echo "  → <toolkit>/bin/sync-project.sh $ROOT --only-bin _common.sh --upgrade-bin _common.sh   (installs just that file; backs up a hand-edited copy first)" >&2; exit 2; }

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }

# HTTP liveness. Returns 0 only on a real status line — a served response, not a guess.
# 4xx counts as "serving" (a login redirect or 403 still proves something answers).
http_up() {
  local url="$1" code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 "$url" 2>/dev/null)"
  [ -n "$code" ] && [ "$code" != "000" ]
}

# Identify a MENDIX app, not merely "something is listening".
#
# CONFIRMED FALSE GREEN: an unrelated Node/Express process was bound to the expected port and this
# script reported "✓ App serving". http_up() accepts any 4xx as "serving" — deliberate, a login
# redirect or 403 is a real Mendix response — but Express answers /login.html with a 404, also 4xx.
# A spec pointed at that port then hangs forever waiting for a login form that will never render,
# and the symptom reads as "the app is broken".
#
# So: require a served login page (2xx/3xx) that actually contains Mendix markers. 4xx no longer
# qualifies for identification — if the runtime is up but redirecting, /index.html carries the same
# markers.
mendix_at() {
  local p="$1" body code path
  for path in /login.html /index.html; do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 "http://localhost:$p$path" 2>/dev/null)"
    case "$code" in 2??|3??) ;; *) continue ;; esac
    body="$(curl -s --max-time 4 "http://localhost:$p$path" 2>/dev/null | head -c 20000)"
    case "$body" in
      *mxui*|*mx-name*|*"Mendix"*|*mxclientsystem*) return 0 ;;
    esac
  done
  return 1
}

# Ask Docker which port OUR container publishes, instead of scanning a guessed list.
#
# CONFIRMED FALSE GREEN, and sharper than the Express one above, because the thing answering IS
# Mendix. `mxcli docker init` writes its compose file into `<project>/.docker/`, so Compose derives
# the project name from that directory — "docker" — identically for EVERY mxcli project on the
# machine. Six projects collided on one workstation. Measured: project A started `docker-mendix-1`
# on :8080 at 02:52; at 02:56 project B's stack RECREATED that same container on :8082 and A's
# containers ceased to exist, with one shared `docker_postgres-data` volume underneath both.
#
# mendix_at() cannot see that. It asks "is this Mendix?" and B is Mendix: 200, real login page, all
# four markers. A journey run then measures a DIFFERENT APPLICATION and produces a page of plausible
# findings. Worse, a guessed port list will not contain B's port, so the script would report "app
# not serving" while an app was plainly serving.
#
# The container's compose label carries the directory it was started from. That is the only identity
# claim in the system that cannot be true of two projects at once. (Pinning COMPOSE_PROJECT_NAME in
# .docker/.env is what PREVENTS the collision; this function is the instrument that DETECTS one when
# the pin is missing.)
owned_app_port() {
  local want="$ROOT/.docker" name dir port
  command -v docker >/dev/null 2>&1 || return 1
  while IFS='|' read -r name dir port; do
    [ "$dir" = "$want" ] || continue
    [ -n "$port" ] || continue
    echo "$port"; return 0
  done <<EOF
$(docker ps --filter 'label=com.docker.compose.service=mendix' \
     --format '{{.Names}}' 2>/dev/null | while read -r n; do
       [ -n "$n" ] || continue
       printf '%s|%s|%s\n' "$n" \
         "$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' "$n" 2>/dev/null)" \
         "$(docker inspect -f '{{with index .NetworkSettings.Ports "8080/tcp"}}{{(index . 0).HostPort}}{{end}}' "$n" 2>/dev/null)"
     done)
EOF
  return 1
}

# find_app_port emits "<port>|<ownership>|<source>" on stdout, NOT a bare port.
#
# It is called in a command substitution, so it runs in a subshell and cannot set a variable in the
# parent — the ownership verdict has to travel on stdout with the port or it is lost.
#
# MEASURED, and the reason ownership is carried at all: a published stack.env held APP_PORT=8080 for
# a day. :8080 was another project's Mendix container, answering 200 with a real login page. The scan
# branch below HAD warned "ownership UNVERIFIED" to stderr, exited 0 anyway, and publish_stack_env
# wrote the port as bare fact. A warning that leaves no trace in the artifact is not a guard: the
# next run reads a plausible number and tests the wrong app, and every assertion it makes is about
# someone else's software.
find_app_port() {
  local p owned
  # 0. A live `mxcli run --local` of this project (its handshake names the port).
  if owned="$(local_loop_port)" && mendix_at "$owned"; then echo "$owned|verified|run-local"; return 0; fi
  # 1. Ownership: which port does THIS project's container publish?
  if owned="$(owned_app_port)" && [ -n "$owned" ]; then
    if mendix_at "$owned"; then echo "$owned|verified|docker"; return 0; fi
    warn "our container publishes :$owned but it is not serving Mendix yet" >&2
    echo "$owned|verified|docker"; return 1
  fi
  # 2. No container of ours is running (SP-hosted run, or docker unavailable). Scan — and first
  #    look for a port whose listener runs THIS project's deployment dir (see RUNTIME PROOF).
  local hits="" h
  for p in $APP_PORTS; do
    mendix_at "$p" || continue
    hits="$hits $p"
    h="$(mxtk_port_holder "$p")" || continue
    [ "${h%%|*}" = "?" ] && continue
    if mxtk_pid_runs_deployment "${h%%|*}" "${DEPLOY_DIRS[@]}"; then echo "$p|verified|runtime"; return 0; fi
  done
  # 3. Otherwise a hit is UNVERIFIED ownership: it proves a Mendix answered, not that it is ours.
  for p in $hits; do
    warn "no container owned by $ROOT/.docker is running; :$p matched by scan — ownership UNVERIFIED" >&2
    warn "  → recorded as APP_OWNERSHIP=unverified in stack.env. A test harness should REFUSE an" >&2
    warn "    unverified port unless ALLOW_UNVERIFIED_APP=1, because :$p may be another project." >&2
    echo "$p|unverified|scan"; return 0
  done
  echo "|none|none"; return 1
}

# A live `mxcli run --local` serving THIS project: echoes its app port. See RUN --LOCAL above.
# Fields are read at MarshalIndent's two-space top level, so a key inside bootConfig cannot match.
MPR_DIR="$(cd "$(dirname "$MPR")" && pwd)"
# A two-tree checkout may carry a root symlink to app/X.mpr. mprcontents/ sits beside the real
# file, and mxcli writes the handshake beside whichever path -p was given — so look in both.
MODEL_DIR="$MPR_DIR"
if [ -L "$MPR" ]; then
  _t="$(readlink "$MPR")"
  case "$_t" in /*) ;; *) _t="$MPR_DIR/$_t" ;; esac
  MODEL_DIR="$(cd "$(dirname "$_t")" 2>/dev/null && pwd -P)" || MODEL_DIR="$MPR_DIR"
fi
# Where this project's runtime is deployed, on either layout. An ARRAY, never a space-joined string:
# word-split, "/work/a b/proj/deployment" became the fragment "/work/a", which matched any
# runtime under "/work/a b/…" on the joined-command-line branch — a foreign checkout read as ours.
DEPLOY_DIRS=("$ROOT/deployment" "$ROOT/app/deployment" "$MPR_DIR/deployment" "$MODEL_DIR/deployment")
LOCAL_HS="$MPR_DIR/.mxcli/run-local.json"
pick_local_hs() {
  local d
  for d in "$MPR_DIR" "$MODEL_DIR"; do
    [ -f "$d/.mxcli/run-local.json" ] && { LOCAL_HS="$d/.mxcli/run-local.json"; return 0; }
  done
  return 1
}
pick_local_hs || true
hs_field() { sed -n "s/^  \"$1\": *\([0-9][0-9]*\).*/\1/p" "$LOCAL_HS" 2>/dev/null | head -1; }
pid_alive() {
  [ -n "$1" ] || return 1
  case "$(mxtk_platform)" in
    # mxcli.exe records a Windows pid; Git Bash's kill only knows MSYS pids.
    windows) grep -q " $1 " <<<"$(tasklist //FI "PID eq $1" //NH 2>/dev/null)" ;;
    *)       kill -0 "$1" 2>/dev/null ;;
  esac
}
# The ports a `mxcli run --local` of this project will want: "<app> <admin>".
run_local_ports() {
  local a="" m=""
  if pick_local_hs; then a="$(hs_field appPort)"; m="$(sed -n 's/^  "adminPort": *\([0-9][0-9]*\).*/\1/p' "$LOCAL_HS" 2>/dev/null | head -1)"; fi
  a="${RUN_LOCAL_APP_PORT:-${a:-8080}}"
  m="${RUN_LOCAL_ADMIN_PORT:-${m:-$((a + 10))}}"
  echo "$a $m"
}
# own_holder "<pid>|<name>" — is this port holder this project's own process? Yes when it is the
# live recorded run --local pid or under it (the runtime mxcli started), or when its command line
# runs this project's deployment dir (a newer run --local still booting, Studio Pro running THIS
# project). With a live record and a holder that cannot be placed — unnamed (a root-owned process
# is "?" to a non-root lsof), or Windows where Git Bash shows no parent pids — it is presumed ours
# only while the record is younger than BOOT_TIMEOUT: a boot has that long to answer. Past it the
# presumption ends and the holder blocks (exit 4) — otherwise a real stranger would read "booting"
# forever, which is #262's failure again.
own_holder() {
  local hp="${1%%|*}" lp=""
  pick_local_hs && lp="$(hs_field pid)" && pid_alive "$lp" || lp=""
  [ "$hp" != "?" ] && mxtk_pid_runs_deployment "$hp" "${DEPLOY_DIRS[@]}" && return 0
  # A runtime whose command line names ANOTHER deployment dir is foreign, whatever else is true.
  [ "$hp" != "?" ] && case "$(mxtk_pid_args "$hp" 2>/dev/null)" in *runtimelauncher.jar*) return 1 ;; esac
  [ -n "$lp" ] || return 1
  mxtk_pid_in_tree "$hp" "$lp" && return 0
  if [ "$hp" = "?" ] || [ "$(mxtk_platform)" = windows ]; then
    [ -n "$(find "$LOCAL_HS" -mmin -$(( (BOOT_TIMEOUT + 59) / 60 )) 2>/dev/null)" ] && return 0
  fi
  return 1
}
# Exit 4 if a run --local of this project could not bind its ports. Never stops the holder.
# Returns 3 (and sets OWN_HOLDING) when a port is held by this project's own process — it is
# booting or not serving a page yet: NOT READY, never blocked.
OWN_HOLDING=""
check_run_local_ports() {
  local p h kind=app
  OWN_HOLDING=""
  for p in $(run_local_ports); do
    if h="$(mxtk_port_holder "$p")"; then
      if own_holder "$h"; then
        [ -n "$OWN_HOLDING" ] || OWN_HOLDING=":$p (the run --local $kind port) — $(mxtk_holder_text "$h")"
        kind=admin; continue
      fi
      bad "INSTRUMENT BLOCKED — :$p (the run --local $kind port) is held by $(mxtk_holder_text "$h")"
      echo "  Not touching it. \`mxcli run --local\` here would collide: it reports 'Authentication failed'"
      echo "  against the other runtime's admin API, and a journey would test that runtime instead."
      echo "  → Stop that process yourself (Studio Pro: stop its run), or start on free ports:"
      echo "    ./mxcli run --local --watch -p $(basename "$MPR") --app-port <free> --admin-port <free>"
      echo "  Record the run as INSTRUMENT BLOCKED, not as a failure. Then re-run with --check."
      exit 4
    fi
    kind=admin
  done
  if [ -n "$OWN_HOLDING" ]; then
    warn "this project's own runtime holds $OWN_HOLDING"
    warn "  → it is booting, or up without serving a page yet. Not blocked: wait, then re-run --check."
    return 3
  fi
  return 0
}
local_loop_port() {
  local pid port
  pick_local_hs || return 1
  pid="$(hs_field pid)"; port="$(hs_field appPort)"
  [ -n "$port" ] && pid_alive "$pid" || return 1
  echo "$port"
}
# yes | no | unknown — was the loop started with --watch? Read from its command line where ps can
# show one; Windows processes do not expose it to Git Bash.
local_loop_watch() {
  local pid args
  pid="$(hs_field pid)"
  args="$(ps -o args= -p "$pid" 2>/dev/null)" || { echo unknown; return; }
  [ -n "$args" ] || { echo unknown; return; }
  case "$args" in *--watch*) echo yes ;; *) echo no ;; esac
}
# Did the model change since the loop booted? The handshake is written when the app is ready, so
# its mtime is the boot's model; any .mpr or mprcontents file newer than it is a later edit.
local_model_changed() {
  [ -n "$(find "$MODEL_DIR" -maxdepth 1 -name '*.mpr' -newer "$LOCAL_HS" 2>/dev/null | head -1)" ] && return 0
  [ -d "$MODEL_DIR/mprcontents" ] && [ -n "$(find "$MODEL_DIR/mprcontents" -type f -newer "$LOCAL_HS" 2>/dev/null | head -1)" ]
}

# Single source of truth for the discovered ports. This script is the only thing that PROVES which
# port the app answers on; every consumer (the e2e config, the loop harness) reads the answer from
# here instead of hardcoding one. Before this file existed, Docker bound 8080, the specs hardcoded
# 8081 and a skill said 8080 — three "truths", and a spec pointed at a dead port reports the app as
# broken rather than as unreachable.
STACK_ENV="${STACK_ENV:-$ROOT/.claude/loop/stack.env}"
# publish_stack_env <port> <jaeger_ok> <ownership> <source>
# APP_OWNERSHIP is not decoration: it is the difference between "this port is ours" and "a Mendix
# answered here". Consumers must be able to tell those apart from the file alone, because the stderr
# warning that distinguishes them is gone by the time anyone reads it.
publish_stack_env() {
  mkdir -p "$(dirname "$STACK_ENV")" 2>/dev/null || return 0
  {
    echo "# written by bin/test-stack-up.sh — $(date -u +%Y-%m-%dT%H:%M:%SZ). Do not edit."
    echo "APP_PORT=$1"
    echo "APP_OWNERSHIP=${3:-unknown}"
    echo "APP_SOURCE=${4:-unknown}"
    [ -n "$MOCK_PORT" ] && echo "MOCK_PORT=$MOCK_PORT"
    [ "$2" -eq 0 ] && echo "JAEGER_PORT=$JAEGER_PORT" || echo "JAEGER_PORT="
  } > "$STACK_ENV"
}

# --- Served model: which model state is the running app built from? ----------
# Written ONLY by this script, right after it built the app, so it names the model the build read
# (after mx update-widgets, which can rewrite the .mpr — fingerprint before the build would be
# stale the moment the build finished). An app started any other way (Studio Pro, a manual
# `docker run`) has no record: freshness UNKNOWN, reported, never guessed.
SERVED_FILE="${SERVED_FILE:-$ROOT/.claude/loop/served-model}"
STAMP_SH="$(dirname "${BASH_SOURCE[0]}")/model-stamp.sh"
model_fp() { [ -f "$STAMP_SH" ] && bash "$STAMP_SH" fingerprint 2>/dev/null; }
record_served() {
  local fp; fp="$(model_fp)" || fp=""
  [ -n "$fp" ] || return 0
  mkdir -p "$(dirname "$SERVED_FILE")" 2>/dev/null && printf '%s\n' "$fp" > "$SERVED_FILE"
}
# Echoes fresh | stale | unknown.
served_state() {
  local want have
  # Proven by its command line, not built by this script: no record of what model it booted.
  [ "${APP_SOURCE:-}" = "runtime" ] && { echo unknown; return; }
  # run --local: mxcli rebuilt nothing for us to record; the handshake's mtime is the boot.
  if [ "${APP_SOURCE:-}" = "run-local" ]; then
    pick_local_hs || true
    if ! local_model_changed; then echo fresh
    else case "$(local_loop_watch)" in yes) echo watch ;; no) echo stale ;; *) echo changed ;; esac; fi
    return
  fi
  have="$(head -1 "$SERVED_FILE" 2>/dev/null)"
  want="$(model_fp)" || want=""
  if [ -z "$have" ] || [ -z "$want" ]; then echo unknown
  elif [ "$have" = "$want" ]; then echo fresh
  else echo stale; fi
}

# After `docker run --wait` returned: prove over HTTP that OUR app answers (design rule 3). mxcli's
# wait reads the runtime log, so this normally passes on the first probe. Sets APP_* in this shell.
prove_app() {
  local waited=0
  while :; do
    APP_FIND="$(find_app_port)" && break
    [ $waited -ge 30 ] && break
    sleep 3; waited=$((waited + 3))
  done
  IFS='|' read -r APP_PORT APP_OWNERSHIP APP_SOURCE <<<"$APP_FIND"
  mendix_at "$APP_PORT"
}

# --- Tracked background test processes (#278) — see STALE TEST PROCESSES above -----------------
BG_PIDS="${BG_PIDS:-$ROOT/.claude/loop/bg-pids.tsv}"
STALE_HOURS="${MXTK_STALE_HOURS:-4}"
case "$STALE_HOURS" in ''|*[!0-9]*) echo "MXTK_STALE_HOURS takes whole hours" >&2; exit 2 ;; esac
# Fixed locale and zone, so a --track in one shell and a --reap in another spell the start time alike.
pid_lstart() { LC_ALL=C TZ=UTC0 ps -o lstart= -p "$1" 2>/dev/null | sed 's/  */ /g; s/^ //; s/ $//'; }
# bg_scan — prints "<state>|<pid>|<age h>|<label>" per record line: live | stale | gone (dead, or the
# pid now belongs to a process that started at another time).
bg_scan() {
  local pid ep ls lab now
  [ -f "$BG_PIDS" ] || return 0
  now="$(date +%s)"
  while IFS='	' read -r pid ep ls lab; do
    case "$pid" in ''|*[!0-9]*) continue ;; esac
    [ "$((10#$pid))" -gt 1 ] || { echo "gone|$pid|0|$lab"; continue; }   # init / own group: never a target
    case "$ep" in ''|*[!0-9]*) ep="$now" ;; esac
    if ! kill -0 "$pid" 2>/dev/null || [ "$(pid_lstart "$pid")" != "$ls" ]; then
      echo "gone|$pid|0|$lab"
    elif [ $(( (now - ep) / 3600 )) -ge "$STALE_HOURS" ]; then
      echo "stale|$pid|$(( (now - ep) / 3600 ))|$lab"
    else echo "live|$pid|$(( (now - ep) / 3600 ))|$lab"; fi
  done < "$BG_PIDS"
}
# bg_prune — keep only the lines whose process still runs with its recorded start time.
bg_prune() {
  local keep pid
  [ -f "$BG_PIDS" ] || return 0
  keep="$(bg_scan | awk -F'|' '$1 != "gone" { print $2 }')"
  : > "$BG_PIDS.tmp" || return 0
  while IFS= read -r line; do
    pid="${line%%	*}"
    case " $(echo $keep) " in *" $pid "*) printf '%s\n' "$line" >> "$BG_PIDS.tmp" ;; esac
  done < "$BG_PIDS"
  mv "$BG_PIDS.tmp" "$BG_PIDS"
}
if [ "$MODE" = "track" ]; then
  T_PID="${2:-}"; T_LABEL="${3:-process}"
  case "$T_PID" in ''|*[!0-9]*) echo "usage: $0 --track <pid> [label]" >&2; exit 2 ;; esac
  T_PID=$((10#$T_PID))   # "01" / "001" must not slip past the refusal below as strings
  # Never pid 1, this script, or the shell that called it: --reap would later stop the caller itself.
  case "$T_PID" in 0|1|"$$"|"$PPID") echo "test-stack-up: refusing to track pid $T_PID (init, this script, or the calling shell) — pass the background process's pid (\$! after starting it)" >&2; exit 2 ;; esac
  [ "$(mxtk_platform)" = windows ] && { echo "test-stack-up: --track is not supported on Git Bash (no process start time to check a reused pid against); nothing recorded"; exit 0; }
  T_LS="$(pid_lstart "$T_PID")"
  [ -n "$T_LS" ] || { echo "test-stack-up: pid $T_PID is not running — nothing recorded" >&2; exit 1; }
  mkdir -p "$(dirname "$BG_PIDS")" || exit 2
  printf '%s\t%s\t%s\t%s\n' "$T_PID" "$(date +%s)" "$T_LS" "$(printf '%s' "$T_LABEL" | tr '\t\n' '  ')" >> "$BG_PIDS"
  echo "tracked pid $T_PID ($T_LABEL) in ${BG_PIDS#$ROOT/}"
  exit 0
fi
# bg_report — list the stale ones and the command that stops them. Read-only.
bg_report() {
  local st pid age lab n=0
  while IFS='|' read -r st pid age lab; do
    [ "$st" = stale ] || continue
    [ $n -eq 0 ] && warn "test processes THIS project started are still running after ${STALE_HOURS}h+ (${BG_PIDS#$ROOT/}):"
    warn "  pid $pid — $lab — ${age}h"; n=$((n + 1))
  done <<EOF_BG
$(bg_scan)
EOF_BG
  [ $n -gt 0 ] && warn "  → hung runs hold login sessions (licence session cap → INVALID runs). Stop them: $0 --reap"
  return 0
}
if [ "$MODE" = "reap" ]; then
  [ "$(mxtk_platform)" = windows ] && { echo "test-stack-up: --reap is not supported on Git Bash; stop the processes yourself"; exit 0; }
  REAPED=0
  while IFS='|' read -r st pid age lab; do
    [ "$st" = stale ] || continue
    # A hand-edited line can say anything: pid 0 or 1 is never signalled (kill 0 = our own group).
    [ "$((10#$pid))" -gt 1 ] || { warn "pid $pid in ${BG_PIDS#$ROOT/} — never signalled"; continue; }
    # Re-checked at the moment of the kill: the scan above may be seconds old.
    _ls="$(awk -F'\t' -v p="$pid" '$1 == p { print $3; exit }' "$BG_PIDS")"
    [ -n "$_ls" ] && [ "$(pid_lstart "$pid")" = "$_ls" ] || { warn "pid $pid changed since the scan — not touched"; continue; }
    KIDS="$(pgrep -P "$pid" 2>/dev/null | tr '\n' ' ' || true)"   # portability-ok: pgrep -P (by parent pid of a recorded pid); Windows returned above
    kill -TERM "$pid" $KIDS 2>/dev/null || true
    for _ in 1 2 3 4 5; do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
    for k in "$pid" $KIDS; do kill -0 "$k" 2>/dev/null && kill -KILL "$k" 2>/dev/null; done
    ok "stopped pid $pid — $lab — ${age}h old${KIDS:+ (and its children $KIDS)}"; REAPED=$((REAPED + 1))
  done <<EOF_BG
$(bg_scan)
EOF_BG
  bg_prune
  echo "reaped $REAPED stale tracked process(es); live and untracked processes untouched"
  exit 0
fi

echo "── Test stack: $PROJ ──────────────────────────────────"
bg_report
[ "$MODE" != "check" ] && bg_prune

# --- Studio Pro: report only, never act -------------------------------------
# Matched on the process list rather than with pgrep: pgrep is macOS/BSD-and-Linux only, and the
# case-sensitive form silently reports "closed" because the executable is lowercase 'studiopro'
# — which then gates every downstream decision on a false negative.
SP_HITS="$(ps axo comm= 2>/dev/null | grep -i 'studiopro' | head -3)"
if [ -n "$SP_HITS" ]; then
  warn "Studio Pro is OPEN — not touching it. If it is running the app, that is fine."
else
  ok "Studio Pro not running"
fi

# --- .mpr cleanliness: report only ------------------------------------------
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  MPR_STATUS="$(git -C "$ROOT" status --porcelain -- "$MPR" 2>/dev/null)"
  if [ -n "$MPR_STATUS" ]; then
    warn "$(basename "$MPR") has uncommitted changes — a Docker build will build THAT state, not HEAD"
  fi
fi

# --- App --------------------------------------------------------------------
APP_FIND="$(find_app_port)"
APP_FOUND=$?
IFS='|' read -r APP_PORT APP_OWNERSHIP APP_SOURCE <<<"$APP_FIND"
if [ $APP_FOUND -eq 0 ]; then
  if [ "$APP_SOURCE" = "run-local" ]; then
    ok "App serving on :$APP_PORT (ownership verified — this project's mxcli run --local)"
  elif [ "$APP_SOURCE" = "runtime" ]; then
    ok "App serving on :$APP_PORT (ownership verified — its runtime runs this project's deployment dir)"
  elif [ "$APP_OWNERSHIP" = "verified" ]; then
    ok "App serving on :$APP_PORT (ownership verified — our container)"
  else
    warn "App serving on :$APP_PORT — ownership $APP_OWNERSHIP, this may be another project"
  fi
else
  bad "App not serving on any of: $APP_PORTS"
fi
SERVED="none"
if [ $APP_FOUND -eq 0 ]; then
  SERVED="$(served_state)"
  case "$SERVED" in
    fresh)   ok "App serves the current model" ;;
    stale)   warn "App serves an OLDER model — the model changed since it was built; tests would measure the old build"
             [ "$APP_SOURCE" = "run-local" ] && warn "  → run --local was started without --watch: stop it and start ./mxcli run --local --watch -p $(basename "$MPR")" ;;
    watch)   ok "Model changed since boot — run --local --watch applies it (~20s a page change, ~60s security/navigation)" ;;
    changed) warn "Model changed since run --local booted; cannot see whether it runs with --watch. Without --watch it serves the old model" ;;
    unknown) warn "App freshness unknown — not built by this script (Studio Pro / manual run); it may serve an old model" ;;
  esac
fi

# --- Jaeger (needed only for Trace assertions) ------------------------------
JAEGER_OK=1
if http_up "http://localhost:$JAEGER_PORT/api/services"; then
  ok "Jaeger on :$JAEGER_PORT"; JAEGER_OK=0
else
  warn "Jaeger DOWN on :$JAEGER_PORT — Trace assertions unavailable (UI+Data still fine)"
fi

# --- Auxiliary mock API (only if this project declared one) -----------------
MOCK_OK=1
MOCK_REQUIRED=0
if [ -n "$MOCK_HEALTH_URL" ]; then
  MOCK_REQUIRED=1
  if http_up "$MOCK_HEALTH_URL"; then
    ok "Mock API answering ($MOCK_HEALTH_URL)"; MOCK_OK=0
  else
    bad "Mock API DOWN ($MOCK_HEALTH_URL)"
  fi
else
  ok "No mock API configured (set MOCK_HEALTH_URL in ${STACK_CONF#$ROOT/} if this project has one)"
  MOCK_OK=0
fi

# --- Container-reachability: the trap that looks like a feature bug ---------
# Inside a container, `localhost` is the CONTAINER. A microflow that hardcodes
# 'http://localhost:<port>/...' cannot reach a host service from a dockerised app — every REST-fed
# spec then renders an empty grid and captures ZERO spans, which reads as "the page is broken".
# Confirmed: container->localhost:3001 = 000, container->host.docker.internal:3001 = 200.
# Runs in --check too: this is exactly what you need to know BEFORE deciding to test.
CTR_WARNED=0
CONTAINER="$(docker ps --filter 'label=com.docker.compose.service=mendix' --format '{{.Names}}' 2>/dev/null | head -1)"
if [ -n "$CONTAINER" ] && [ $MOCK_REQUIRED -eq 1 ] && [ $MOCK_OK -eq 0 ]; then
  FROM_CTR="$(docker exec "$CONTAINER" sh -c \
    "curl -s -o /dev/null -w '%{http_code}' --max-time 4 '$MOCK_HEALTH_URL'" 2>/dev/null)"
  if [ "$FROM_CTR" = "000" ] || [ -z "$FROM_CTR" ]; then
    CTR_WARNED=1
    warn "Dockerised app CANNOT reach the host service (localhost inside the container = the container)"
    warn "  → REST-fed specs will render empty grids and capture ZERO spans."
    warn "  → That is an INVALID RUN, not a feature failure. Do not debug the page."
    warn "  → Use Studio Pro's Run Locally for those specs, or parameterise the URLs (a model write)."
  else
    ok "Container can reach the host service (HTTP $FROM_CTR)"
  fi
fi

# Publish as soon as the port is MEASURED, not only when the whole stack is READY. A down mock makes
# REST-fed specs invalid; it does not change which port the app answers on, and the non-REST specs
# still need to know it.
[ $APP_FOUND -eq 0 ] && publish_stack_env "$APP_PORT" "$JAEGER_OK" "$APP_OWNERSHIP" "$APP_SOURCE"

if [ "$MODE" = "check" ]; then
  echo "────────────────────────────────────────────────────────"
  if [ $CTR_WARNED -eq 1 ]; then
    echo "APP UP, BUT REST-FED SPECS WILL BE INVALID — see the container warning above"
    exit 1
  fi
  if [ "$SERVED" = "stale" ] && [ "$APP_SOURCE" = "run-local" ]; then
    echo "APP UP BUT STALE — restart mxcli run --local with --watch (this script does not restart a loop it did not start)"
    exit 1
  fi
  if [ "$SERVED" = "stale" ] && [ "$APP_OWNERSHIP" = "verified" ]; then
    echo "APP UP BUT STALE — re-run without --check to hot-reload the current model"
    exit 1
  fi
  if [ $APP_FOUND -eq 0 ] && [ $MOCK_OK -eq 0 ]; then
    echo "READY (app :$APP_PORT · jaeger $([ $JAEGER_OK -eq 0 ] && echo up || echo DOWN))"
    exit 0
  fi
  # A leftover run-local record means this project runs as run --local: name a port thief now.
  [ $APP_FOUND -ne 0 ] && pick_local_hs && check_run_local_ports
  echo "NOT READY — re-run without --check to bring it up"
  exit 1
fi

# --- Bring up the mock (safe: start only, never stop) -----------------------
if [ $MOCK_REQUIRED -eq 1 ] && [ $MOCK_OK -ne 0 ]; then
  if [ -n "$MOCK_DIR" ] && [ -d "$ROOT/$MOCK_DIR" ]; then
    echo "→ Starting mock API ($MOCK_START in $MOCK_DIR)..."
    ( cd "$ROOT/$MOCK_DIR" && nohup $MOCK_START >"$MOCK_LOG" 2>&1 & )
    for _ in $(seq 1 20); do
      sleep 0.5
      if http_up "$MOCK_HEALTH_URL"; then MOCK_OK=0; break; fi
    done
    if [ $MOCK_OK -eq 0 ]; then ok "Mock API up"
    else bad "Mock API failed to start — see $MOCK_LOG"; fi
  else
    bad "MOCK_HEALTH_URL is set but MOCK_DIR is missing or not a directory: ${MOCK_DIR:-<unset>}"
  fi
fi

# --- Warm loop: refresh a running app instead of restarting it --------------
# Only for OUR container (ownership verified, source docker): a reload swaps the model in a runtime,
# and doing that to an unverified port could be another project's app or a Studio Pro run. A
# run --local loop is never reloaded from here — --watch does that, inside the process that owns it.
if [ $APP_FOUND -eq 0 ] && [ "$APP_SOURCE" = "docker" ] && [ -n "$MXCLI" ] \
   && [ "${MXTK_WARM_RELOAD:-on}" != "off" ] && [ "$MODE" != "nodocker" ] \
   && { [ "$SERVED" != "fresh" ] || [ "$MODE" = "restart" ]; }; then
  T0=$(date +%s)
  RELOADED=1
  if [ "$MODE" != "restart" ]; then
    # --skip-check only when this exact model already passed an mxbuild (exec.sh's gate or
    # verify-model.sh). Otherwise the check is the only build-error report before the build.
    SKIP=""
    if [ -f "$STAMP_SH" ] && bash "$STAMP_SH" check -q >/dev/null 2>&1; then SKIP="--skip-check"; fi
    echo "→ Model changed since the app was built — hot-reloading (build + reload_model${SKIP:+, check skipped: model already gate-verified})..."
    "$MXCLI" docker reload -p "$MPR" $SKIP >"$DOCKER_LOG" 2>&1
    RELOADED=$?
    if [ $RELOADED -eq 0 ]; then
      # reload_model returned; prove the app still answers before trusting it.
      for _ in $(seq 1 20); do
        APP_FIND="$(find_app_port)" && break
        sleep 1
      done
      if mendix_at "${APP_FIND%%|*}"; then
        record_served
        ok "Hot reload done in $(( $(date +%s) - T0 ))s — app serves the current model"
        SERVED=fresh
      else
        warn "reload_model returned but the app stopped answering — falling back to a restart"
        RELOADED=1
      fi
    else
      warn "docker reload failed (rc=$RELOADED) — falling back to a restart. Log: $DOCKER_LOG"
      tail -5 "$DOCKER_LOG" | sed 's/^/    /'
    fi
  fi
  if [ $RELOADED -ne 0 ]; then
    echo "→ Rebuilding and restarting the container..."
    "$MXCLI" docker run -p "$MPR" --wait --wait-timeout "$BOOT_TIMEOUT" >"$DOCKER_LOG" 2>&1
    if [ $? -ne 0 ]; then
      bad "mxcli docker run failed — see $DOCKER_LOG"; tail -20 "$DOCKER_LOG"; exit 1
    fi
    # Proved here, not by falling into "Bring up the app" below: that block runs `docker run`
    # again, and did — every restart built and booted the app twice.
    if prove_app; then
      record_served; SERVED=fresh
      ok "Restarted in $(( $(date +%s) - T0 ))s — app serves the current model"
    else
      bad "mxcli reported the runtime started, but no Mendix answers over HTTP — see $DOCKER_LOG"; exit 1
    fi
  fi
fi

# --- Bring up the app -------------------------------------------------------
if [ $APP_FOUND -ne 0 ]; then
  if [ "$MODE" = "nodocker" ]; then
    check_run_local_ports || { bad "App not serving yet — this project's own runtime holds its port. Re-run --check when it answers."; exit 1; }
    bad "App down and --no-docker given. Click Run Locally in Studio Pro (or, with no Studio Pro, ./mxcli run --local --watch), then re-run --check."
    exit 1
  fi
  # No reachable Docker (or Podman) daemon: say so and name the Docker-free route, instead of letting
  # `mxcli docker run` fail with a daemon error the agent then reports as "cannot start Docker".
  # A cloud container ships the docker CLI with no daemon; that is normal, not a blocker.
  # Bounded: a stopped Docker Desktop can leave `docker info` silent for minutes.
  _RT=docker; command -v docker >/dev/null 2>&1 || _RT=podman
  if ! command -v "$_RT" >/dev/null 2>&1; then _DK=1; else
    "$_RT" info >/dev/null 2>&1 & _dk_pid=$!; _dk_w=0; _DK=
    while kill -0 "$_dk_pid" 2>/dev/null; do
      [ "$_dk_w" -ge 15 ] && { kill "$_dk_pid" 2>/dev/null; _DK=2; break; }
      sleep 1; _dk_w=$((_dk_w + 1))
    done
    [ -n "$_DK" ] || { wait "$_dk_pid"; _DK=$?; }
  fi
  if [ "$_DK" != 0 ]; then
    check_run_local_ports || { bad "App not serving yet — this project's own runtime holds its port. Re-run --check when it answers."; exit 1; }
    bad "App down and no Docker/Podman reachable, so this script cannot build the app container."
    echo "  Normal in a cloud container, and fine on a desktop without one. Run the app without it:"
    echo "    Studio Pro: Run Locally.  No Studio Pro:"
    echo "    ./mxcli run --local --watch -p $(basename "$MPR")   # flags: skills/cloud-dev-environment.md"
    echo "  This script then sees it as yours (verified) and --watch keeps it current."
    echo "  Snapshot first — mxcli run --local consolidates a split-model .mpr. Then re-run with --check."
    exit 1
  fi
  if [ -z "$MXCLI" ]; then
    bad "App down and no mxcli found (neither ./mxcli nor on PATH) — cannot build."
    exit 2
  fi

  echo "→ App is down. Building and starting via Docker (reads the .mpr, never writes it)..."
  echo "  This can take several minutes on a cold build."

  # Do NOT pipe mxcli: reading $? through a pipe measures the pipe, not the command.
  # --wait: mxcli follows the runtime log until it reports started, so the boot wait is mxcli's.
  # The loop below is the HTTP proof (design rule 3) and normally passes on its first probe.
  "$MXCLI" docker run -p "$MPR" --wait --wait-timeout "$BOOT_TIMEOUT" >"$DOCKER_LOG" 2>&1
  DOCKER_RC=$?
  if [ $DOCKER_RC -ne 0 ]; then
    bad "mxcli docker run failed (rc=$DOCKER_RC) — see $DOCKER_LOG"
    tail -20 "$DOCKER_LOG"
    exit 1
  fi

  if prove_app; then
    APP_FOUND=0
    record_served
    ok "App serving on :$APP_PORT (ownership $APP_OWNERSHIP)"
  else
    bad "mxcli reported the runtime started, but no Mendix answers over HTTP — see $DOCKER_LOG"
    "$MXCLI" docker status -p "$MPR" 2>&1 | tail -5
    exit 1
  fi
fi

echo "────────────────────────────────────────────────────────"
if [ "$APP_SOURCE" = "run-local" ] && [ "$SERVED" = "stale" ]; then
  echo "NOT READY — the run --local app serves an older model; restart it with --watch"
  exit 1
fi
if [ $APP_FOUND -eq 0 ] && [ $MOCK_OK -eq 0 ]; then
  # re-publish: both the port AND the ownership can change across a Docker boot — before the boot no
  # container of ours was running (so any hit was an unverified scan); after it, one is.
  publish_stack_env "$APP_PORT" "$JAEGER_OK" "$APP_OWNERSHIP" "$APP_SOURCE"
  echo "READY — ports published to ${STACK_ENV#$ROOT/}; the e2e config reads them automatically"
  echo "  app    :$APP_PORT  (ownership $APP_OWNERSHIP, $APP_SOURCE)"
  [ -n "$MOCK_PORT" ] && echo "  mock   :$MOCK_PORT"
  echo "  jaeger $([ $JAEGER_OK -eq 0 ] && echo ":$JAEGER_PORT" || echo 'DOWN — Trace assertions will not run')"
  exit 0
fi
echo "NOT READY"
exit 1
