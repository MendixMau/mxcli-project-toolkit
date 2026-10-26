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
# Not fixtured: the Windows tasklist branch of pid_alive, the netstat branch of mxtk_port_holder and
# the PowerShell / `ps -o args=` branches of mxtk_pid_args (CI is Linux; Linux reads /proc).
# T8-T10 (#160): no handshake, ownership proven by the listener's command line running
# runtimelauncher.jar on this project's deployment dir (both layouts); a foreign one stays unverified.
# T11-T13 (#262 follow-up): this project's own booting runtime on its port is NOT READY (exit 1),
# never INSTRUMENT BLOCKED. T14 (#278): --track / --reap act on the project's own pid record only.
# T15-T16 (PR #319 review): spaced paths match whole, never as fragments (incl. the joined-line
# branch, forced); an unnamed holder is presumed ours only while the record is < BOOT_TIMEOUT old.
# T7 (#262): a port the run --local loop needs is held by a process that is not this project's
# loop (here the fake app itself, behind a dead handshake — Studio Pro's runtime in the field) →
# exit 4, "INSTRUMENT BLOCKED", the holder named with its pid, and it is still alive afterwards.
#
# T17-T19 (PR #568 review): the mxui.js fallback rejects an SPA catch-all (200 HTML on every path)
# and keeps a themed Mendix index; --local with a stubbed mxcli passes --serve-port and is proven by
# its handshake; --local with no mxcli names the missing mxcli.
#
# usage: test-stack-up-local.sh /path/to/test-stack-up.sh
# No pipefail: every assertion is `printf '%s' "$OUT" | grep -q …`, and grep -q exits on the first match —
# with pipefail the printf's SIGPIPE on a long $OUT then failed a passing assertion (seen on T2).
set -u

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
PIDS="$PIDS $!"; APP_PID=$!
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
BOOT=202101010000   # the handshake: newer than the model, older than any edit a case makes

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
  # Between the model (OLD) and now: a write and an edit in the same clock tick share an mtime,
  # so an edit made right after this line would not read as newer (35/50 on a probe here).
  touch -t "$BOOT" "$1/.mxcli/run-local.json"
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

echo "== T7 (#262): the run --local port is held by someone else -> instrument blocked, exit 4 =="
CAN_NAME=0; { command -v lsof >/dev/null 2>&1 || command -v ss >/dev/null 2>&1; } && CAN_NAME=1
P="$(mkproj t7 root)"; handshake "$P" "$DEAD_PID"
OUT="$(run "$P")"; RC=$?
[ "$RC" -eq 4 ] && ok "--check exits 4 (dead loop, its app port taken)" || bad "--check rc=$RC, want 4" "$OUT"
printf '%s' "$OUT" | grep -q "INSTRUMENT BLOCKED — :$APP (the run --local app port)" && ok "says instrument blocked, names :$APP" || bad "no blocked verdict" "$OUT"
if [ "$CAN_NAME" = 1 ]; then
  printf '%s' "$OUT" | grep -q "pid $APP_PID" && ok "names the holder's pid $APP_PID" || bad "holder pid not named" "$OUT"
else echo "  [skip] neither lsof nor ss: the holder is reported unnamed"; fi
kill -0 "$APP_PID" 2>/dev/null && ok "holder untouched" || bad "holder was killed"
P="$(mkproj t7b root)"; printf 'RUN_LOCAL_APP_PORT=%s\n' "$APP" >> "$P/.claude/loop/stack.conf"
OUT="$(cd "$P" && bash bin/test-stack-up.sh --no-docker 2>&1)"; RC=$?
[ "$RC" -eq 4 ] && printf '%s' "$OUT" | grep -q "INSTRUMENT BLOCKED" && ok "--no-docker, no record, RUN_LOCAL_APP_PORT taken: exit 4" || bad "--no-docker rc=$RC, want 4" "$OUT"
P="$(mkproj t7c root)"; handshake "$P" "$DEAD_PID"; sed -i.bak "s/^  \"appPort\": [0-9]*/  \"appPort\": 1/; s/^  \"adminPort\": [0-9]*/  \"adminPort\": 1/" "$P/.mxcli/run-local.json"
OUT="$(run "$P")"; RC=$?
[ "$RC" -eq 1 ] && ! printf '%s' "$OUT" | grep -q "INSTRUMENT BLOCKED" && ok "free run --local ports: plain NOT READY, exit 1" || bad "free ports rc=$RC, want 1" "$OUT"

# --- #160 and the #262 follow-up: the runtime's own command line ----------------------------
# srv.py <mx|boot> <www> <portfile> [args the script ignores] — a listener whose command line can
# carry `-jar …/runtimelauncher.jar <deployment dir>`, as the Mendix runtime's does (field capture,
# run --local on Linux, 2026-09-25: `java … -jar …/runtimelauncher.jar <project>/app/deployment`).
# mx serves the Mendix-marked login page; boot answers 503 (bound, not serving yet — a booting runtime).
cat > "$WORK/srv.py" <<'PY'
import functools, http.server, sys
mode, www, pf = sys.argv[1:4]
class Boot(http.server.BaseHTTPRequestHandler):
    def do_GET(self): self.send_response(503); self.end_headers()
    def log_message(self, *a): pass
H = functools.partial(http.server.SimpleHTTPRequestHandler, directory=www) if mode == "mx" else Boot
s = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
open(pf, "w").write(str(s.server_address[1]))
s.serve_forever()
PY
# srv <port var> <pid var> <mx|boot> [extra argv…]
SRVN=0
srv() {
  local pv="$1" iv="$2" mode="$3" pf; shift 3; SRVN=$((SRVN + 1)); pf="$WORK/srv$SRVN.port"
  "$PY" -I "$WORK/srv.py" "$mode" "$WORK/www" "$pf" "$@" >/dev/null 2>&1 &
  PIDS="$PIDS $!"; printf -v "$iv" '%s' "$!"
  for _ in $(seq 1 50); do [ -s "$pf" ] && break; sleep 0.1; done
  printf -v "$pv" '%s' "$(cat "$pf" 2>/dev/null)"
}
JAR=/opt/mendix/runtime/launcher/runtimelauncher.jar
if [ "$CAN_NAME" != 1 ]; then
  echo "  [skip] T8-T13: neither lsof nor ss — no listener pid, so no command line to read"
else
echo "== T8 (#160): no handshake; :X runs runtimelauncher.jar on THIS project's deployment dir -> verified =="
P="$(mkproj t8 root)"; mkdir -p "$P/deployment"
srv R8 R8PID mx -jar "$JAR" "$P/deployment"
# Another Mendix answers FIRST in the scan list — the old scan published it as ours-unverified.
printf 'APP_PORTS="%s %s"\n' "$APP" "$R8" >> "$P/.claude/loop/stack.conf"
OUT="$(run "$P")"; RC=$?
[ "$RC" -eq 0 ] && ok "--check exits 0" || bad "--check rc=$RC" "$OUT"
[ "$(envv "$P" APP_PORT)" = "$R8" ] && [ "$(envv "$P" APP_OWNERSHIP)" = verified ] && [ "$(envv "$P" APP_SOURCE)" = runtime ] \
  && ok "stack.env: APP_PORT=$R8 verified runtime (the foreign Mendix on :$APP skipped)" || bad "stack.env wrong" "$(cat "$P/.claude/loop/stack.env" 2>&1)"
printf '%s' "$OUT" | grep -q "runs this project's deployment dir" && ok "says why it is verified" || bad "no runtime verdict" "$OUT"
printf '%s' "$OUT" | grep -q "App freshness unknown" && ok "freshness unknown (this script did not build it)" || bad "freshness claimed" "$OUT"

echo "== T9 (#160): two-tree — runtimelauncher.jar on <root>/app/deployment -> verified =="
P="$(mkproj t9 app)"; mkdir -p "$P/app/deployment"
srv R9 R9PID mx -jar "$JAR" "$P/app/deployment/"
printf 'APP_PORTS="%s"\n' "$R9" >> "$P/.claude/loop/stack.conf"
OUT="$(run "$P")"; RC=$?
[ "$RC" -eq 0 ] && [ "$(envv "$P" APP_OWNERSHIP)" = verified ] && [ "$(envv "$P" APP_SOURCE)" = runtime ] \
  && ok "app/deployment recognised (trailing slash too)" || bad "two-tree runtime not verified (rc=$RC)" "$OUT"

echo "== T10 (#160): runtimelauncher.jar on ANOTHER checkout's deployment dir -> unverified, as before =="
P="$(mkproj t10 root)"; mkdir -p "$P/deployment" "$WORK/other/deployment"
srv R10 R10PID mx -jar "$JAR" "$WORK/other/deployment"
printf 'APP_PORTS="%s"\n' "$R10" >> "$P/.claude/loop/stack.conf"
OUT="$(run "$P")"; RC=$?
[ "$(envv "$P" APP_OWNERSHIP)" = unverified ] && [ "$(envv "$P" APP_SOURCE)" = scan ] \
  && ok "another project's runtime stays unverified" || bad "foreign runtime verified" "$(cat "$P/.claude/loop/stack.env" 2>&1)"

echo "== T11 (#262 follow-up): live record, its own child bound to the app port, booting -> NOT READY, exit 1 =="
P="$(mkproj t11 root)"
( "$PY" -I "$WORK/srv.py" boot "$WORK/www" "$WORK/t11.port" & wait ) >/dev/null 2>&1 &
LOOP11=$!; PIDS="$PIDS $LOOP11"
for _ in $(seq 1 50); do [ -s "$WORK/t11.port" ] && break; sleep 0.1; done
B11="$(cat "$WORK/t11.port")"; PIDS="$PIDS $(pgrep -P "$LOOP11" | tr '\n' ' ')"   # portability-ok: fixture teardown list, by parent pid
handshake "$P" "$LOOP11"
sed -i.bak "s/^  \"appPort\": [0-9]*/  \"appPort\": $B11/; s/^  \"adminPort\": [0-9]*/  \"adminPort\": 1/" "$P/.mxcli/run-local.json"
OUT="$(run "$P")"; RC=$?
[ "$RC" -eq 1 ] && ok "--check exits 1 (was 4)" || bad "--check rc=$RC, want 1" "$OUT"
printf '%s' "$OUT" | grep -q "INSTRUMENT BLOCKED" && bad "own booting runtime called a thief" "$OUT" || ok "not INSTRUMENT BLOCKED"
printf '%s' "$OUT" | grep -q "this project's own runtime holds :$B11" && ok "names its own runtime on :$B11" || bad "own holder not named" "$OUT"

echo "== T11b: live record, but ANOTHER checkout's runtime holds the app port -> still blocked, exit 4 =="
P="$(mkproj t11b root)"
srv F11 F11PID boot -jar "$JAR" "$WORK/other/deployment"
handshake "$P" "$LOOP11"
sed -i.bak "s/^  \"appPort\": [0-9]*/  \"appPort\": $F11/; s/^  \"adminPort\": [0-9]*/  \"adminPort\": 1/" "$P/.mxcli/run-local.json"
OUT="$(run "$P")"; RC=$?
[ "$RC" -eq 4 ] && printf '%s' "$OUT" | grep -q "INSTRUMENT BLOCKED — :$F11" && ok "foreign runtime still blocks (exit 4)" || bad "rc=$RC, want 4" "$OUT"

echo "== T12 (#262 follow-up): dead record, a booting runtime on THIS deployment dir holds the port -> exit 1 =="
P="$(mkproj t12 root)"; mkdir -p "$P/deployment"
srv B12 B12PID boot -jar "$JAR" "$P/deployment"
handshake "$P" "$DEAD_PID"
sed -i.bak "s/^  \"appPort\": [0-9]*/  \"appPort\": $B12/; s/^  \"adminPort\": [0-9]*/  \"adminPort\": 1/" "$P/.mxcli/run-local.json"
OUT="$(run "$P")"; RC=$?
[ "$RC" -eq 1 ] && ! printf '%s' "$OUT" | grep -q "INSTRUMENT BLOCKED" && ok "exit 1, not blocked" || bad "rc=$RC, want 1 and not blocked" "$OUT"

echo "== T13 (#262 follow-up): --no-docker, no record, Studio Pro booting THIS project on the port -> exit 1 =="
P="$(mkproj t13 root)"; mkdir -p "$P/deployment"
srv B13 B13PID boot -jar "$JAR" "$P/deployment"
printf 'RUN_LOCAL_APP_PORT=%s\nRUN_LOCAL_ADMIN_PORT=1\n' "$B13" >> "$P/.claude/loop/stack.conf"
OUT="$(cd "$P" && bash bin/test-stack-up.sh --no-docker 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q "own runtime holds its port" && ok "exit 1, says its own runtime is booting" || bad "rc=$RC, want 1" "$OUT"
kill -0 "$B13PID" 2>/dev/null && ok "own runtime untouched" || bad "own runtime killed"
fi

if [ "$CAN_NAME" = 1 ]; then
echo "== T15 (#319 review): a project path with a space — whole paths, never word-split fragments =="
mkdir -p "$WORK/sp ace"
P="$(mkproj "sp ace/t15" root)"; mkdir -p "$P/deployment" "$WORK/sp ace/other/deployment"
srv R15 R15PID mx -jar "$JAR" "$P/deployment"
srv F15 F15PID mx -jar "$JAR" "$WORK/sp ace/other/deployment"
printf 'APP_PORTS="%s"\n' "$R15" >> "$P/.claude/loop/stack.conf"
OUT="$(run "$P")"
[ "$(envv "$P" APP_OWNERSHIP)" = verified ] && [ "$(envv "$P" APP_SOURCE)" = runtime ] \
  && ok "own runtime under a spaced path verified" || bad "spaced own runtime not verified" "$OUT"
printf 'APP_PORTS="%s"\n' "$F15" >> "$P/.claude/loop/stack.conf"
OUT="$(run "$P")"
[ "$(envv "$P" APP_OWNERSHIP)" = unverified ] && ok "a foreign runtime under the same spaced prefix stays unverified" \
  || bad "foreign runtime under the spaced prefix verified" "$(cat "$P/.claude/loop/stack.env" 2>&1)"
# The joined-line branch (macOS ps / Windows CIM) has no argv boundaries; CI is Linux, so force it.
jl() { ( PROJECT_ROOT="$P"; . "$P/bin/_common.sh"; mxtk_platform() { echo macos; }; mxtk_pid_runs_deployment "$@" ); }
jl "$R15PID" "$P/deployment" && ok "joined line: own spaced deployment dir matches" || bad "joined line: own spaced dir missed"
jl "$F15PID" "$WORK/sp" && bad "joined line: fragment '$WORK/sp' matched a runtime under '$WORK/sp ace/'" || ok "joined line: a path fragment never matches"
jl "$F15PID" "$P/deployment" && bad "joined line: foreign runtime matched our dir" || ok "joined line: foreign runtime does not match"

echo "== T16 (#319 review): an unnamed holder is presumed ours only while the record is younger than BOOT_TIMEOUT =="
mkdir -p "$WORK/blind"
for t in lsof ss; do printf '#!/bin/sh\nexit 1\n' > "$WORK/blind/$t"; chmod +x "$WORK/blind/$t"; done
P="$(mkproj t16 root)"
srv B16 B16PID boot
handshake "$P" "$WATCH_PID"
sed -i.bak "s/^  \"appPort\": [0-9]*/  \"appPort\": $B16/; s/^  \"adminPort\": [0-9]*/  \"adminPort\": 1/" "$P/.mxcli/run-local.json"
touch "$P/.mxcli/run-local.json"
OUT="$(cd "$P" && PATH="$WORK/blind:$PATH" bash bin/test-stack-up.sh --check 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && ok "fresh record, unnamed holder: NOT READY (exit 1)" || bad "fresh record rc=$RC, want 1" "$OUT"
touch -t "$BOOT" "$P/.mxcli/run-local.json"
OUT="$(cd "$P" && PATH="$WORK/blind:$PATH" bash bin/test-stack-up.sh --check 2>&1)"; RC=$?
[ "$RC" -eq 4 ] && printf '%s' "$OUT" | grep -q "INSTRUMENT BLOCKED" && ok "record older than BOOT_TIMEOUT: blocked (exit 4), not 'booting' forever" || bad "stale record rc=$RC, want 4" "$OUT"
fi

echo "== T14 (#278): tracked test processes — only this project's own record, only stale ones =="
P="$(mkproj t14 root)"
( sleep 600 & wait ) & OLDRUN=$!; PIDS="$PIDS $OLDRUN"
sleep 0.2; OLDKID="$(pgrep -P "$OLDRUN" | head -1)"; PIDS="$PIDS $OLDKID"   # portability-ok: fixture, by parent pid
sleep 600 & YOUNG=$!; PIDS="$PIDS $YOUNG"
sleep 600 & REUSED=$!; PIDS="$PIDS $REUSED"
bash -c "exec -a 'node journey-runner.js' sleep 600" & DECOY14=$!; PIDS="$PIDS $DECOY14"
( cd "$P" && bash bin/test-stack-up.sh --track "$OLDRUN" journey-runner ) >/dev/null 2>&1 && ok "--track records a live pid" || bad "--track failed"
# Tracked under another time zone: --track and --reap must spell the start time alike (LC_ALL=C TZ=UTC0).
( cd "$P" && TZ=XYZ-14 LC_ALL=C bash bin/test-stack-up.sh --track "$YOUNG" monitor ) >/dev/null 2>&1
( cd "$P" && bash bin/test-stack-up.sh --track 1 init ) >/dev/null 2>&1; [ $? -eq 2 ] && ok "--track refuses pid 1" || bad "--track accepted pid 1"
( cd "$P" && bash bin/test-stack-up.sh --track 01 init ) >/dev/null 2>&1; [ $? -eq 2 ] && ok "--track refuses 01 (normalised, not string-compared)" || bad "--track accepted 01"
( cd "$P" && bash bin/test-stack-up.sh --track "$BASHPID" me ) >/dev/null 2>&1; [ $? -eq 2 ] && ok "--track refuses the calling shell" || bad "--track accepted the calling shell"
( cd "$P" && bash bin/test-stack-up.sh --track "$DEAD_PID" gone ) >/dev/null 2>&1 && bad "--track accepted a dead pid" || ok "--track refuses a dead pid"
BG="$P/.claude/loop/bg-pids.tsv"
# Age the first line; a REUSED pid: recorded start time differs from the running process's.
sed -i.bak "s/^$OLDRUN	[0-9]*	/$OLDRUN	1000000000	/" "$BG"
printf '%s\t1000000000\tThu Jan 1 00:00:00 1970\treused\n%s\t1000000000\tx\tdead\n' "$REUSED" "$DEAD_PID" >> "$BG"
OUT="$(run "$P")"
printf '%s' "$OUT" | grep -q "pid $OLDRUN — journey-runner" && ok "--check lists the stale own process" || bad "stale process not listed" "$OUT"
printf '%s' "$OUT" | grep -qE "pid ($YOUNG|$REUSED|$DECOY14) " && bad "listed a young/reused/untracked pid" "$OUT" || ok "young, reused and untracked pids not listed"
printf '%s' "$OUT" | grep -q -- "--reap" && ok "names the --reap command" || bad "no remedy named" "$OUT"
[ "$(wc -l < "$BG" | tr -d ' ')" = 4 ] && ok "--check left the record unchanged" || bad "--check wrote the record"
# A hand-edited line for pid 1, aged and with init's real start time: --reap must still never signal it.
printf '1\t1000000000\t%s\tinit\n' "$(LC_ALL=C TZ=UTC0 ps -o lstart= -p 1 2>/dev/null | sed 's/  */ /g; s/^ //; s/ $//')" >> "$BG"
OUT="$(cd "$P" && bash bin/test-stack-up.sh --reap 2>&1)"; RC=$?
printf '%s' "$OUT" | grep -q "stopped pid 1 " && bad "--reap signalled pid 1" "$OUT" || ok "--reap never signals a hand-edited pid-1 line"
sleep 0.5
[ "$RC" -eq 0 ] && ok "--reap exits 0" || bad "--reap rc=$RC" "$OUT"
kill -0 "$OLDRUN" 2>/dev/null && bad "stale tracked pid survived --reap" || ok "stale tracked pid stopped"
# The child is reparented once its parent dies; until init reaps it, kill -0 sees a zombie.
kid_alive() { kill -0 "$1" 2>/dev/null || return 1; [ "$(sed 's/.*) //' "/proc/$1/stat" 2>/dev/null | cut -d' ' -f1)" != Z ]; }
[ -n "$OLDKID" ] || bad "[setup] the tracked process had no child"
kid_alive "$OLDKID" && bad "its child survived" || ok "  and its child"
kill -0 "$YOUNG" 2>/dev/null && ok "young tracked pid untouched" || bad "young pid killed"
kill -0 "$REUSED" 2>/dev/null && ok "reused pid (start time mismatch) untouched" || bad "reused pid killed"
kill -0 "$DECOY14" 2>/dev/null && ok "untracked look-alike untouched" || bad "untracked process killed"
[ "$(cut -f1 "$BG" | tr '\n' ' ')" = "$YOUNG " ] && ok "record pruned to the live entry" || bad "record not pruned" "$(cat "$BG")"

# srv_any <portvar> <pidvar> <mode> <dir>: spa = every path answers 200 text/html (an Express/Vite
# catch-all); files = a plain static server over <dir>.
srv_any() {
  local pf="$WORK/$1.port"
  "$PY" -I - "$3" "$4" "$pf" >/dev/null 2>&1 <<'EOF2' &
import functools, http.server, sys
mode, root, pf = sys.argv[1:4]
class Spa(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        b = b'<!doctype html><html><head><title>Shop</title></head><body><div id="root"></div></body></html>'
        self.send_response(200); self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def log_message(self, *a): pass
H = Spa if mode == "spa" else functools.partial(http.server.SimpleHTTPRequestHandler, directory=root)
s = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
open(pf, "w").write(str(s.server_address[1]))
s.serve_forever()
EOF2
  PIDS="$PIDS $!"; printf -v "$2" '%s' "$!"
  for _ in $(seq 1 50); do [ -s "$pf" ] && break; sleep 0.1; done
  printf -v "$1" '%s' "$(cat "$pf" 2>/dev/null)"
}

echo "== T17 (PR #568 review): mxui.js fallback — an SPA catch-all is NOT Mendix; a themed Mendix index still is =="
srv_any SPA SPAPID spa "$WORK"
P="$(mkproj t17 root)"; printf 'APP_PORTS="%s"\n' "$SPA" >> "$P/.claude/loop/stack.conf"
OUT="$(run "$P")"; RC=$?
[ "$(envv "$P" APP_PORT)" != "$SPA" ] && ! printf '%s' "$OUT" | grep -q ":$SPA matched by scan" \
  && ok "SPA catch-all (200 text/html on every path) not identified as Mendix" || bad "SPA catch-all identified as Mendix (rc=$RC)" "$OUT"
mkdir -p "$WORK/themed/mxclientsystem/mxui"
printf '<html><head><title>Shop</title></head><body><div id="root"></div></body></html>\n' > "$WORK/themed/index.html"
printf '\n  (function(){window.mx=window.mx||{};})();\n' > "$WORK/themed/mxclientsystem/mxui/mxui.js"
srv_any THM THMPID files "$WORK/themed"
P="$(mkproj t17b root)"; printf 'APP_PORTS="%s"\n' "$THM" >> "$P/.claude/loop/stack.conf"
OUT="$(run "$P")"; RC=$?
[ "$(envv "$P" APP_PORT)" = "$THM" ] && [ "$(envv "$P" APP_OWNERSHIP)" = unverified ] \
  && ok "themed index.html + mxui.js served as JavaScript -> found (scan, unverified)" || bad "themed Mendix not found (rc=$RC)" "$OUT"

echo "== T18 (PR #568 review): --local, stubbed mxcli -> starts with --serve-port, found by its handshake =="
P="$(mkproj t18 root)"
cat > "$P/mxcli" <<EOF2
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$P/mxcli.args"
mpr=""; while [ \$# -gt 0 ]; do [ "\$1" = -p ] && { mpr="\$2"; shift; }; shift; done
d="\$(cd "\$(dirname "\$mpr")" && pwd)"; mkdir -p "\$d/.mxcli"
sed -e 's/^  "pid": [0-9]*/  "pid": $WATCH_PID/' -e 's/^  "appPort": [0-9]*/  "appPort": $APP/' \
    -e 's/^  "adminPass": "[^"]*"/  "adminPass": "$ADMIN_MARK"/' "$GOLDEN" > "\$d/.mxcli/run-local.json"
EOF2
chmod +x "$P/mxcli"
OUT="$( (cd "$P" && LOGDIR="$WORK" bash bin/test-stack-up.sh --local 2>&1) )"; RC=$?
ARGS="$(cat "$P/mxcli.args" 2>/dev/null)"
case "$ARGS" in "run --local --watch --detach -p "*"--serve-port 65"[4-9][0-9]*) ok "mxcli run --local --watch --detach … --serve-port given" ;; *) bad "mxcli not started as expected: '$ARGS'" "$OUT" ;; esac
printf '%s' "$OUT" | grep -q "App serving on :$APP .*ownership verified, run-local" && ok "app proven on :$APP via the run-local handshake" || bad "app not proven via handshake (rc=$RC)" "$OUT"
[ "$(envv "$P" APP_SOURCE)" = run-local ] && [ "$(envv "$P" APP_OWNERSHIP)" = verified ] && ok "stack.env: verified run-local" || bad "stack.env wrong" "$(cat "$P/.claude/loop/stack.env" 2>&1)"

echo "== T19 (PR #568 review): --local with no mxcli -> says no mxcli, not 'no Docker' =="
if command -v mxcli >/dev/null 2>&1; then
  echo "  [skip] T19: an mxcli is on PATH here"
else
  P="$(mkproj t19 root)"
  OUT="$( (cd "$P" && LOGDIR="$WORK" bash bin/test-stack-up.sh --local 2>&1) )"; RC=$?
  [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q "no mxcli found" && ! printf '%s' "$OUT" | grep -q "Docker/Podman" \
    && ok "exit $RC, names the missing mxcli" || bad "wrong no-mxcli message (rc=$RC)" "$OUT"
fi

echo
echo "stack-up-local: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
