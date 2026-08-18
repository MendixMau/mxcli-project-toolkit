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
#   2. NEVER writes to the .mpr. `mxcli docker build` reads the model and writes only build output.
#   3. Proves liveness with an actual HTTP response. "No error" is not "up".
#   4. Idempotent. If the app already answers, it does nothing and exits 0.
#   5. Starts an auxiliary service if it is down; NEVER stops one (another session may be using it).
#
# Usage:
#   bin/test-stack-up.sh --check     # report only, change nothing. Exit 0 iff required deps are up.
#   bin/test-stack-up.sh             # report, then bring up what is missing (may run a Docker build)
#   bin/test-stack-up.sh --no-docker # bring up auxiliaries only; never build. "SP is already running it".
#
# Exit codes: 0 = required stack is up · 1 = not up and could not fix · 2 = usage/env error
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
  "")          ;;
  *) echo "usage: $0 [--check|--no-docker]" >&2; exit 2 ;;
esac

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

# find_app_port emits "<port>|<ownership>" on stdout, NOT a bare port.
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
  # 1. Ownership: which port does THIS project's container publish?
  if owned="$(owned_app_port)" && [ -n "$owned" ]; then
    if mendix_at "$owned"; then echo "$owned|verified"; return 0; fi
    warn "our container publishes :$owned but it is not serving Mendix yet" >&2
    echo "$owned|verified"; return 1
  fi
  # 2. No container of ours is running (SP-hosted run, or docker unavailable). Fall back to the
  #    scan — but say so, because a hit here is UNVERIFIED ownership: it proves a Mendix answered,
  #    not that it is ours.
  for p in $APP_PORTS; do
    if mendix_at "$p"; then
      warn "no container owned by $ROOT/.docker is running; :$p matched by scan — ownership UNVERIFIED" >&2
      warn "  → recorded as APP_OWNERSHIP=unverified in stack.env. A test harness should REFUSE an" >&2
      warn "    unverified port unless ALLOW_UNVERIFIED_APP=1, because :$p may be another project." >&2
      echo "$p|unverified"; return 0
    fi
  done
  echo "|none"; return 1
}

# Single source of truth for the discovered ports. This script is the only thing that PROVES which
# port the app answers on; every consumer (the e2e config, the loop harness) reads the answer from
# here instead of hardcoding one. Before this file existed, Docker bound 8080, the specs hardcoded
# 8081 and a skill said 8080 — three "truths", and a spec pointed at a dead port reports the app as
# broken rather than as unreachable.
STACK_ENV="${STACK_ENV:-$ROOT/.claude/loop/stack.env}"
# publish_stack_env <port> <jaeger_ok> <ownership>
# APP_OWNERSHIP is not decoration: it is the difference between "this port is ours" and "a Mendix
# answered here". Consumers must be able to tell those apart from the file alone, because the stderr
# warning that distinguishes them is gone by the time anyone reads it.
publish_stack_env() {
  mkdir -p "$(dirname "$STACK_ENV")" 2>/dev/null || return 0
  {
    echo "# written by bin/test-stack-up.sh — $(date -u +%Y-%m-%dT%H:%M:%SZ). Do not edit."
    echo "APP_PORT=$1"
    echo "APP_OWNERSHIP=${3:-unknown}"
    [ -n "$MOCK_PORT" ] && echo "MOCK_PORT=$MOCK_PORT"
    [ "$2" -eq 0 ] && echo "JAEGER_PORT=$JAEGER_PORT" || echo "JAEGER_PORT="
  } > "$STACK_ENV"
}

echo "── Test stack: $PROJ ──────────────────────────────────"

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
APP_PORT="${APP_FIND%%|*}"
APP_OWNERSHIP="${APP_FIND##*|}"
if [ $APP_FOUND -eq 0 ]; then
  if [ "$APP_OWNERSHIP" = "verified" ]; then
    ok "App serving on :$APP_PORT (ownership verified — our container)"
  else
    warn "App serving on :$APP_PORT — ownership $APP_OWNERSHIP, this may be another project"
  fi
else
  bad "App not serving on any of: $APP_PORTS"
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
[ $APP_FOUND -eq 0 ] && publish_stack_env "$APP_PORT" "$JAEGER_OK" "$APP_OWNERSHIP"

if [ "$MODE" = "check" ]; then
  echo "────────────────────────────────────────────────────────"
  if [ $CTR_WARNED -eq 1 ]; then
    echo "APP UP, BUT REST-FED SPECS WILL BE INVALID — see the container warning above"
    exit 1
  fi
  if [ $APP_FOUND -eq 0 ] && [ $MOCK_OK -eq 0 ]; then
    echo "READY (app :$APP_PORT · jaeger $([ $JAEGER_OK -eq 0 ] && echo up || echo DOWN))"
    exit 0
  fi
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

# --- Bring up the app -------------------------------------------------------
if [ $APP_FOUND -ne 0 ]; then
  if [ "$MODE" = "nodocker" ]; then
    bad "App down and --no-docker given. Click Run Locally in Studio Pro, then re-run --check."
    exit 1
  fi
  if [ -z "$MXCLI" ]; then
    bad "App down and no mxcli found (neither ./mxcli nor on PATH) — cannot build."
    exit 2
  fi

  echo "→ App is down. Building and starting via Docker (reads the .mpr, never writes it)..."
  echo "  This can take several minutes on a cold build."

  # Do NOT pipe mxcli: reading $? through a pipe measures the pipe, not the command.
  # (this script runs without `set -e` on purpose — the boot-wait loop below relies on
  #  find_app_port returning non-zero repeatedly without killing the script)
  "$MXCLI" docker run -p "$MPR" >"$DOCKER_LOG" 2>&1
  DOCKER_RC=$?
  if [ $DOCKER_RC -ne 0 ]; then
    bad "mxcli docker run failed (rc=$DOCKER_RC) — see $DOCKER_LOG"
    tail -20 "$DOCKER_LOG"
    exit 1
  fi

  echo "→ Waiting for the app to answer (timeout ${BOOT_TIMEOUT}s)..."
  WAITED=0
  while [ $WAITED -lt "$BOOT_TIMEOUT" ]; do
    APP_FIND="$(find_app_port)" && { APP_FOUND=0; break; }
    sleep 3; WAITED=$((WAITED + 3))
    [ $((WAITED % 30)) -eq 0 ] && echo "  ...${WAITED}s"
  done
  APP_PORT="${APP_FIND%%|*}"
  APP_OWNERSHIP="${APP_FIND##*|}"

  if [ $APP_FOUND -eq 0 ]; then
    ok "App serving on :$APP_PORT after ${WAITED}s (ownership $APP_OWNERSHIP)"
  else
    bad "App still not answering after ${BOOT_TIMEOUT}s — see $DOCKER_LOG"
    "$MXCLI" docker status -p "$MPR" 2>&1 | tail -5
    exit 1
  fi
fi

echo "────────────────────────────────────────────────────────"
if [ $APP_FOUND -eq 0 ] && [ $MOCK_OK -eq 0 ]; then
  # re-publish: both the port AND the ownership can change across a Docker boot — before the boot no
  # container of ours was running (so any hit was an unverified scan); after it, one is.
  publish_stack_env "$APP_PORT" "$JAEGER_OK" "$APP_OWNERSHIP"
  echo "READY — ports published to ${STACK_ENV#$ROOT/}; the e2e config reads them automatically"
  echo "  app    :$APP_PORT  (ownership $APP_OWNERSHIP)"
  [ -n "$MOCK_PORT" ] && echo "  mock   :$MOCK_PORT"
  echo "  jaeger $([ $JAEGER_OK -eq 0 ] && echo ":$JAEGER_PORT" || echo 'DOWN — Trace assertions will not run')"
  exit 0
fi
echo "NOT READY"
exit 1
