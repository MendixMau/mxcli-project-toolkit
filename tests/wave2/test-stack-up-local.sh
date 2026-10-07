#!/usr/bin/env bash
# Fixtures for test-stack-up.sh recognising a live `mxcli run --local` as THIS project's app.
#
# mxcli (v0.24+) writes <dir of -p>/.mxcli/run-local.json when the app is ready and removes it on
# exit. Before this change the script never read it: a run --local app was found by port scan,
# published as APP_OWNERSHIP=unverified, and the e2e harness refused it unless the operator set
# ALLOW_UNVERIFIED_APP=1. Field run 2026-10-07, existing app: same app, same port, now `verified`.
#
# The handshake is fixtures/run-local/run-local.json — a real capture from that field run, every
# value replaced (project path, pid, ports, passwords, constants), byte layout kept. Each case
# rewrites only pid/appPort/adminPass. The "app" is a python http.server serving a login page with
# a Mendix marker; the "mxcli" is `sleep` with its argv[0] set, so `ps` shows the command line the
# script reads --watch from. docker/podman are stubbed out so no real container can answer.
# Not fixtured: the Windows tasklist branch of pid_alive (CI is Linux).
#
# usage: test-stack-up-local.sh /path/to/test-stack-up.sh
set -uo pipefail

SRC="${1:?usage: test-stack-up-local.sh /path/to/test-stack-up.sh}"
case "$SRC" in /*) ;; *) SRC="$PWD/$SRC" ;; esac
GOLDEN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/run-local/run-local.json"
[ -f "$SRC" ] && [ -f "$(dirname "$SRC")/_common.sh" ] && [ -f "$GOLDEN" ] \
  || { echo "FIXTURE ERROR: need $SRC, its _common.sh, and $GOLDEN"; exit 2; }
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin/lib/portable.sh"
require_py
command -v curl >/dev/null 2>&1 || { echo "FIXTURE ERROR: needs curl"; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/stackup-local.XXXXXX")"
PIDS=""
cleanup() { for p in $PIDS; do kill "$p" 2>/dev/null; done; rm -rf "$WORK"; }
trap cleanup EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/  FAIL-detail: /'; }

# --- no container runtime: only our fake app can answer ----------------------------------
mkdir -p "$WORK/stubs"
for t in docker podman; do printf '#!/bin/sh\nexit 1\n' > "$WORK/stubs/$t"; chmod +x "$WORK/stubs/$t"; done
export PATH="$WORK/stubs:$PATH"
unset PROJECT_ROOT MPR_FILE STACK_ENV STACK_CONF SERVED_FILE

# --- the fake app -------------------------------------------------------------------------
mkdir -p "$WORK/www"
printf '<html><script src="mxclientsystem/mxui/mxui.js"></script></html>\n' > "$WORK/www/login.html"
"$PY" -I - "$WORK/www" "$WORK/port" >/dev/null 2>&1 <<'EOF' &
import functools, http.server, sys
H = functools.partial(http.server.SimpleHTTPRequestHandler, directory=sys.argv[1])
s = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
open(sys.argv[2], "w").write(str(s.server_address[1]))
s.serve_forever()
EOF
PIDS="$PIDS $!"
for _ in $(seq 1 50); do [ -s "$WORK/port" ] && break; sleep 0.1; done
APP="$(cat "$WORK/port" 2>/dev/null)"
[ -n "$APP" ] && curl -s --max-time 4 "http://localhost:$APP/login.html" | grep -q mxui \
  || { echo "FIXTURE ERROR: fake app did not come up"; exit 2; }

# A process whose command line reads like mxcli's: fake_mxcli <var> <args after "mxcli">.
fake_mxcli() {
  bash -c "exec -a 'mxcli $2' sleep 600" >/dev/null 2>&1 &
  PIDS="$PIDS $!"; printf -v "$1" '%s' "$!"
}
fake_mxcli WATCH_PID 'run --local --watch -p Fixture.mpr'
fake_mxcli PLAIN_PID 'run --local -p Fixture.mpr'
sleep 0.3   # let exec -a replace bash, so ps shows the mxcli command line
sleep 0 & DEAD_PID=$!; wait "$DEAD_PID" 2>/dev/null

ADMIN_MARK="fixture-admin-marker-7c1"   # stands in for the adminPass value
OLD=202001010000

# mkproj <name> <root|app|symlink> -> echoes the project root
mkproj() {
  local p="$WORK/$1" m
  mkdir -p "$p/bin" "$p/.claude/loop"
  cp "$SRC" "$p/bin/test-stack-up.sh"; cp "$(dirname "$SRC")/_common.sh" "$p/bin/"
  # Nothing scanned or traced may answer: the run --local handshake is the only way in.
  printf 'APP_PORTS="1"\nJAEGER_PORT="1"\n' > "$p/.claude/loop/stack.conf"
  case "$2" in
    root)    m="$p" ;;
    app)     m="$p/app" ;;
    symlink) m="$p/app"; ln -s app/Fixture.mpr "$p/Fixture.mpr" ;;
  esac
  mkdir -p "$m/mprcontents"; printf 'mpr' > "$m/Fixture.mpr"; printf 'u' > "$m/mprcontents/a.mxunit"
  touch -t "$OLD" "$m/Fixture.mpr" "$m/mprcontents/a.mxunit"
  echo "$p"
}
# handshake <dir> <pid> -> the golden, pointed at our fake app, written into <dir>/.mxcli/
handshake() {
  mkdir -p "$1/.mxcli"
  sed -e "s/^  \"pid\": [0-9]*/  \"pid\": $2/" \
      -e "s/^  \"appPort\": [0-9]*/  \"appPort\": $APP/" \
      -e "s/^  \"adminPass\": \"[^\"]*\"/  \"adminPass\": \"$ADMIN_MARK\"/" "$GOLDEN" > "$1/.mxcli/run-local.json"
}
run() { (cd "$1" && bash bin/test-stack-up.sh --check 2>&1); }
envv() { sed -n "s/^$2=//p" "$1/.claude/loop/stack.env" 2>/dev/null; }

echo "== T0: the golden is what the script's reader expects =="
grep -q '^  "pid": 4242,$' "$GOLDEN" && grep -q '^  "appPort": 8180,$' "$GOLDEN" \
  && ok "golden carries pid/appPort at MarshalIndent's two-space top level" || bad "golden shape changed"
grep -q "$ADMIN_MARK" "$GOLDEN" && bad "golden carries the test secret" || ok "golden carries no live secret"

echo "== T1: live --watch loop, model unchanged -> verified, run-local, fresh =="
P="$(mkproj t1 root)"; handshake "$P" "$WATCH_PID"
OUT="$(run "$P")"; RC=$?
[ "$RC" -eq 0 ] && ok "--check exits 0" || bad "--check rc=$RC" "$OUT"
printf '%s' "$OUT" | grep -q "ownership verified — this project's mxcli run --local" && ok "reported as this project's run --local" || bad "not reported as run --local" "$OUT"
printf '%s' "$OUT" | grep -q "App serves the current model" && ok "fresh" || bad "not fresh" "$OUT"
[ "$(envv "$P" APP_PORT)" = "$APP" ] && [ "$(envv "$P" APP_OWNERSHIP)" = verified ] && [ "$(envv "$P" APP_SOURCE)" = run-local ] \
  && ok "stack.env: APP_PORT=$APP APP_OWNERSHIP=verified APP_SOURCE=run-local" || bad "stack.env wrong" "$(cat "$P/.claude/loop/stack.env" 2>&1)"
grep -rq "$ADMIN_MARK" "$P/.claude" && bad "adminPass leaked into .claude/" || ok "adminPass not copied anywhere under .claude/"
printf '%s' "$OUT" | grep -q "$ADMIN_MARK" && bad "adminPass printed" || ok "adminPass not printed"

echo "== T2: dead pid -> the handshake is ignored =="
P="$(mkproj t2 root)"; handshake "$P" "$DEAD_PID"
OUT="$(run "$P")"; RC=$?
[ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q "App not serving" && ok "not trusted: app reported not serving" || bad "dead-pid handshake trusted (rc=$RC)" "$OUT"
[ "$(envv "$P" APP_SOURCE)" = run-local ] && bad "stack.env says run-local for a dead loop" || ok "stack.env not claimed for a dead loop"

echo "== T3: model edited, loop without --watch -> stale, exit 1 =="
P="$(mkproj t3 root)"; handshake "$P" "$PLAIN_PID"; touch "$P/Fixture.mpr"
OUT="$(run "$P")"; RC=$?
[ "$RC" -eq 1 ] && ok "--check exits 1" || bad "--check rc=$RC" "$OUT"
printf '%s' "$OUT" | grep -q "APP UP BUT STALE — restart mxcli run --local with --watch" && ok "says restart with --watch" || bad "no stale verdict" "$OUT"

echo "== T4: model edited, loop WITH --watch -> watch applies it, ready =="
P="$(mkproj t4 root)"; handshake "$P" "$WATCH_PID"; touch "$P/mprcontents/a.mxunit"
OUT="$(run "$P")"; RC=$?
[ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q "run --local --watch applies it" && ok "watch state, exit 0" || bad "watch not recognised (rc=$RC)" "$OUT"

echo "== T5: two-tree (app/), handshake beside app/Fixture.mpr =="
P="$(mkproj t5 app)"; handshake "$P/app" "$PLAIN_PID"
OUT="$(run "$P")"; RC=$?
[ "$RC" -eq 0 ] && [ "$(envv "$P" APP_SOURCE)" = run-local ] && ok "found under app/" || bad "two-tree handshake missed (rc=$RC)" "$OUT"
touch "$P/app/mprcontents/a.mxunit"
OUT="$(run "$P")"; RC=$?
[ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q "APP UP BUT STALE" && ok "an app/mprcontents edit reads stale" || bad "app/ edit not seen (rc=$RC)" "$OUT"

echo "== T6: two-tree with a root symlink, run as -p Fixture.mpr from the root =="
P="$(mkproj t6 symlink)"; handshake "$P" "$PLAIN_PID"
OUT="$(run "$P")"; RC=$?
[ "$RC" -eq 0 ] && [ "$(envv "$P" APP_SOURCE)" = run-local ] && ok "found beside the symlink" || bad "symlinked handshake missed (rc=$RC)" "$OUT"
touch "$P/app/mprcontents/a.mxunit"
OUT="$(run "$P")"; RC=$?
[ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q "APP UP BUT STALE" && ok "edit behind the symlink reads stale" || bad "edit behind symlink not seen (rc=$RC)" "$OUT"

echo
echo "stack-up-local: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
