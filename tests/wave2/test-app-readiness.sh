#!/usr/bin/env bash
# test-app-readiness.sh — app-restart.sh's readiness probe has no false negatives, still fails a down
# app, names the part that is down, and restarts after a full build only an app the toolkit started.
#
# Usage: bash tests/wave2/test-app-readiness.sh [path-to-app-restart.sh]
#        (the _common.sh beside the subject is the one installed with it)
#
# WHY (#686, field run 2026-11): about 9 false "not proven up after 240s" from app-restart.sh while
# the app was serving; the agent re-proved each by hand at 2-4 min. The probe demanded Mendix words
# in login.html / index.html — Mendix 11's login.html has none (the login page served below is the
# shape of a Mendix 11.x deployment/web/login.html: no mxui / mx-name / "Mendix" / mxclientsystem),
# and a themed index.html need not either. And a full mxbuild into deployment/ leaves a running
# `run --local --watch` with no web client (/dist/index.js 404) until `mxcli run restart` (PR #700
# run-2 experiment, R22).
#
# The app is a node stand-in for `mxcli run --local` (no Mendix), as in test-app-restart.sh: it writes
# the run --local record from the CAPTURED handshake (fixtures/run-local/run-local.json) once it
# listens, serves index.html + the bundle, and answers on the admin port. Knobs (files in the
# project): .themed (an index.html with no Mendix words), .delay (seconds before it listens),
# .quiet (no log lines while it waits), .broken-<pid> (that process serves no bundle: the full-build
# case). Its `run restart` (mxcli's own, for a --detach run) stops the recorded pid and starts anew.
#
# Covers
#   R1 a themed index.html + a Mendix 11 login page → up (master: "does not serve a Mendix page")
#   R2 a boot slower than --timeout, its log still growing → waits on, up (master: not proven up)
#   R3 a boot that never comes up and writes nothing → fails at --timeout, naming the missing record
#   R4 a served page with the bundle 404 → fails without the boot extension, naming the client bundle
#   R5 --probe: up → 0; client gone → 1 naming the bundle; neither stops anything
#   R6 --if-client-gone, client served → 0, nothing stopped
#   R7 --if-client-gone, client gone, app NOT started by the toolkit → exit 6, the hint, nothing stopped
#   R8 --if-client-gone, client gone, toolkit-started (owner.pid), no run-state.json → restarted (exit 0)
#   R9 --if-client-gone, client gone, toolkit-started, a --detach run (run-state.json) → `mxcli run restart`
#   R10 a successful restart records the new pid as toolkit-started (owner.pid)
# Needs node and curl; skips (exit 0, says so) without them.
set -uo pipefail

TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/project-bin/app-restart.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
GOLDEN="$TOOLKIT/tests/wave2/fixtures/run-local/run-local.json"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 — missing '$3' in: $(printf '%s' "$2" | tail -4)" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 — unexpected '$3'" ;; *) ok "$1" ;; esac; }
echo "== subject: $SUBJECT"
command -v node >/dev/null 2>&1 && command -v curl >/dev/null 2>&1 || { echo "  [skip] node or curl missing"; echo "PASS=0 FAIL=0"; exit 0; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/appready.XXXXXX")" || exit 2
WORK="$(cd "$WORK" && pwd -P)"
KILL_LIST=""
cleanup() {
  for f in "$WORK"/*/.mxcli/run-local.json; do [ -f "$f" ] && KILL_LIST="$KILL_LIST $(sed -n 's/^  "pid": *\([0-9]*\).*/\1/p' "$f")"; done
  for p in $KILL_LIST; do kill -KILL "$p" 2>/dev/null; done   # test teardown only, by pid
  rm -rf "$WORK"
}
trap cleanup EXIT

mkapp() {  # $1 = project dir, $2 = port
  local P="$1"
  mkdir -p "$P/bin"
  printf 'not a real model\n' > "$P/Fixture.mpr"
  cp "$(dirname "$SUBJECT")/_common.sh" "$P/bin/"; cp "$SUBJECT" "$P/bin/app-restart.sh"
  echo "$2" > "$P/.fakeport"
  cat > "$P/mxcli" <<'JS'
#!/usr/bin/env node
const fs = require('fs'), http = require('http'), path = require('path'), cp = require('child_process');
const dir = process.cwd(), hs = path.join(dir, '.mxcli', 'run-local.json'), has = f => fs.existsSync(path.join(dir, f));
const port = parseInt(fs.readFileSync(path.join(dir, '.fakeport'), 'utf8'), 10);
const sleep = ms => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
const recPid = () => { try { return parseInt(/"pid": (\d+)/.exec(fs.readFileSync(hs, 'utf8'))[1], 10); } catch (e) { return 0; } };
if (process.argv[2] === 'run' && process.argv[3] === 'restart') {   // mxcli's own restart of a --detach run
  const old = recPid(); try { process.kill(old, 'SIGTERM'); } catch (e) {}
  for (let i = 0; i < 50 && fs.existsSync(hs); i++) sleep(100);
  const c = cp.spawn('./mxcli', ['run', '--local', '--watch', '--detach', '-p', 'Fixture.mpr'], { detached: true, stdio: 'ignore', env: process.env });
  c.unref(); fs.writeFileSync(path.join(dir, '.restarted-via-mxcli'), String(old));
  for (let i = 0; i < 100 && !(fs.existsSync(hs) && recPid() !== old); i++) sleep(100);
  process.exit(0);
}
const login = '<!DOCTYPE html><html><head><meta charset="utf-8" /><title>Login</title><link rel="stylesheet" href="theme.compiled.css?1"></head>' +
  '<body><div class="loginpage"><form id="loginForm" class="loginpage-form"><input id="usernameInput" class="form-control" type="text" /></form></div></body></html>';
const index = has('.themed')
  ? '<!DOCTYPE html><html lang="en"><head><title>Crew Roster</title></head><body><div id="root"></div><script src="dist/index.js?abc123" type="module"></script></body></html>'
  : '<html><head><title>Mendix</title><script src="dist/index.js?abc123"></script></head><body class="mxui"></body></html>';
const delay = has('.delay') ? parseInt(fs.readFileSync(path.join(dir, '.delay'), 'utf8'), 10) : 0;
const quiet = has('.quiet');
fs.writeFileSync(path.join(dir, '.fakepid'), String(process.pid));
if (has('.break-next')) fs.renameSync(path.join(dir, '.break-next'), path.join(dir, '.broken-' + process.pid));
let n = 0; const tick = setInterval(() => { if (!quiet) console.log('booting ' + (++n)); }, 1000);
const stop = () => { try { fs.unlinkSync(hs); } catch (e) {} process.exit(0); };
process.on('SIGTERM', stop); process.on('SIGINT', stop);
http.createServer((req, res) => { res.statusCode = 401; res.end('{"result":3}'); }).listen(port + 10, '127.0.0.1');
setTimeout(() => {
  clearInterval(tick);
  http.createServer((req, res) => {
    const u = req.url.split('?')[0];
    if (u === '/login.html') return res.end(login);
    if (u === '/index.html' || u === '/') return res.end(index);
    if (u === '/dist/index.js' && !has('.broken-' + process.pid)) { res.setHeader('Content-Type', 'text/javascript'); return res.end('/* bundle */'); }
    res.statusCode = 404; res.end('<html>not found</html>');
  }).listen(port, '127.0.0.1', () => {
    const g = fs.readFileSync(process.env.FAKE_GOLDEN, 'utf8')
      .replace(/^  "project": "[^"]*"/m, '  "project": ' + JSON.stringify(path.join(dir, 'Fixture.mpr')))
      .replace(/^  "pid": \d+/m, '  "pid": ' + process.pid)
      .replace(/^  "appPort": \d+/m, '  "appPort": ' + port)
      .replace(/^  "adminPort": \d+/m, '  "adminPort": ' + (port + 10))
      .replace(/^  "adminPass": "[^"]*"/m, '  "adminPass": "x"');
    fs.mkdirSync(path.dirname(hs), { recursive: true });
    fs.writeFileSync(hs, g);
    if (process.argv.includes('--detach')) fs.writeFileSync(path.join(dir, '.mxcli', 'run-state.json'), '{}');
  });
}, delay * 1000);
JS
  chmod +x "$P/mxcli" "$P/bin/app-restart.sh"
}
start_app() {  # $1 = project dir, $2 = extra flags; waits for the record
  rm -f "$1/.mxcli/run-local.json"
  ( cd "$1" && FAKE_GOLDEN="$GOLDEN" setsid nohup ./mxcli run --local --watch ${2:-} -p Fixture.mpr >"$1/first.log" 2>&1 </dev/null & )
  local i; for i in $(seq 1 100); do [ -f "$1/.mxcli/run-local.json" ] && return 0; sleep 0.2; done; return 1
}
hs_pid() { sed -n 's/^  "pid": *\([0-9]*\).*/\1/p' "$1/.mxcli/run-local.json" 2>/dev/null; }
alive() { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null || return 1; case "$(ps -o stat= -p "$1" 2>/dev/null)" in Z*) return 1 ;; esac; }
ar() { ( cd "$1" && shift && FAKE_GOLDEN="$GOLDEN" LOGDIR="$WORK" ./bin/app-restart.sh "$@" ) 2>&1; }
track() { KILL_LIST="$KILL_LIST $(hs_pid "$1")"; }

PORT=$(( 20000 + RANDOM % 20000 ))
P="$WORK/proj"; mkapp "$P" "$PORT"

echo "-- R1 a themed index.html and a Mendix 11 login page (no Mendix words anywhere) → up"
touch "$P/.themed"
start_app "$P" && ok "[setup] stand-in app up" || bad "[setup] stand-in app never wrote its record"
track "$P"
OUT="$(ar "$P" --timeout 12)"; RC=$?; track "$P"
[ "$RC" -eq 0 ] && ok "R1 restarted and proven up (exit 0)" || bad "R1 exit $RC: $(printf '%s' "$OUT" | tail -3)"
has "R1 proves the bundle the page loads" "$OUT" "dist/index.js?abc123 answers"
echo "-- R10 the restart recorded the new pid as toolkit-started"
[ "$(cat "$P/.claude/loop/app-restart/owner.pid" 2>/dev/null)" = "$(hs_pid "$P")" ] && ok "R10 owner.pid is the new recorded pid" \
  || bad "R10 owner.pid '$(cat "$P/.claude/loop/app-restart/owner.pid" 2>/dev/null)' vs record '$(hs_pid "$P")'"

echo "-- R2 a boot slower than --timeout whose log still grows → waits on, then up"
echo 7 > "$P/.delay"
T0=$(date +%s)
OUT="$(MXTK_RESTART_MAX=40 ar "$P" --timeout 3)"; RC=$?; track "$P"
[ "$RC" -eq 0 ] && ok "R2 proven up after the slow boot (exit 0)" || bad "R2 exit $RC: $(printf '%s' "$OUT" | tail -3)"
has "R2 says it kept waiting because the boot is still logging" "$OUT" "still booting"
rm -f "$P/.delay"

echo "-- R3 a boot that never comes up and writes nothing → fails at --timeout, naming what is missing"
echo 60 > "$P/.delay"; touch "$P/.quiet"
T0=$(date +%s)
OUT="$(MXTK_RESTART_MAX=40 ar "$P" --timeout 4)"; RC=$?; EL=$(( $(date +%s) - T0 ))
[ "$RC" -eq 1 ] && ok "R3 exit 1" || bad "R3 exit $RC"
has "R3 names the part that is down" "$OUT" "down: no new run --local record"
[ "$EL" -lt 12 ] && ok "R3 bounded: gave up after ${EL}s (--timeout 4), not extended toward the 40 s cap" || bad "R3 waited ${EL}s for a boot that logged nothing"
# The silent app never wrote a record: stop it by the pid it wrote at start (teardown, by pid).
kill -KILL "$(cat "$P/.fakepid" 2>/dev/null)" 2>/dev/null
rm -f "$P/.delay" "$P/.quiet"
start_app "$P" && track "$P" || bad "[setup] app did not come back after R3"

echo "-- R4 the page is served but the bundle is 404 → fails, naming the bundle, no boot extension"
touch "$P/.break-next"   # the restarted process serves its pages but no bundle
T0=$(date +%s)
OUT="$(MXTK_RESTART_MAX=60 MXTK_RESTART_QUIET=30 ar "$P" --timeout 5)"; RC=$?; EL=$(( $(date +%s) - T0 )); track "$P"
[ "$RC" -eq 1 ] && ok "R4 exit 1" || bad "R4 exit $RC: $(printf '%s' "$OUT" | tail -3)"
has "R4 names the client bundle and its HTTP code" "$OUT" "down: client bundle http://127.0.0.1:$PORT/dist/index.js?abc123 → HTTP 404"
has "R4 keeps the blank-page line" "$OUT" "Page bundle not served"
hasnt "R4 does not wait on as if booting" "$OUT" "still booting"
[ "$EL" -lt 25 ] && ok "R4 gave up at the timeout (${EL}s)" || bad "R4 waited ${EL}s for a client that a wait cannot bring back"

echo "-- R5 --probe"
BR="$(hs_pid "$P")"
OUT="$(ar "$P" --probe)"; RC=$?
[ "$RC" -eq 1 ] && ok "R5 client gone → exit 1" || bad "R5 exit $RC: $OUT"
has "R5 names the bundle" "$OUT" "client bundle"
has "R5 and the runtime state from the admin port" "$OUT" ":$PORT is not serving"
[ "$(hs_pid "$P")" = "$BR" ] && alive "$BR" && ok "R5 nothing stopped" || bad "R5 the app changed"
rm -f "$P/.broken-$BR"
OUT="$(ar "$P" --probe)"; RC=$?
[ "$RC" -eq 0 ] && ok "R5 serving → exit 0" || bad "R5 exit $RC: $OUT"
has "R5 says so" "$OUT" "serving on :$PORT"

echo "-- R6 --if-client-gone, client still served → nothing"
OUT="$(ar "$P" --if-client-gone)"; RC=$?
[ "$RC" -eq 0 ] && ok "R6 exit 0" || bad "R6 exit $RC: $OUT"
has "R6 says no restart" "$OUT" "still served"
[ "$(hs_pid "$P")" = "$BR" ] && alive "$BR" && ok "R6 nothing stopped" || bad "R6 the app changed"

echo "-- R7 --if-client-gone, client gone, app not started by the toolkit → hint, exit 6, nothing stopped"
echo 999999 > "$P/.claude/loop/app-restart/owner.pid"; touch "$P/.broken-$BR"
OUT="$(ar "$P" --if-client-gone)"; RC=$?
[ "$RC" -eq 6 ] && ok "R7 exit 6" || bad "R7 exit $RC: $OUT"
has "R7 prints the one-line restart hint" "$OUT" "mxcli run restart -p Fixture.mpr"
has "R7 says why it does not restart" "$OUT" "not started by the toolkit"
[ "$(hs_pid "$P")" = "$BR" ] && alive "$BR" && ok "R7 nothing stopped" || bad "R7 an app the toolkit did not start was stopped"

echo "-- R8 --if-client-gone, client gone, toolkit-started, no run-state.json → restarted"
echo "$BR" > "$P/.claude/loop/app-restart/owner.pid"
OUT="$(ar "$P" --if-client-gone --timeout 20)"; RC=$?; track "$P"
[ "$RC" -eq 0 ] && ok "R8 exit 0" || bad "R8 exit $RC: $(printf '%s' "$OUT" | tail -3)"
has "R8 says it restarts because the toolkit started it" "$OUT" "restarts it now"
NEW="$(hs_pid "$P")"
[ -n "$NEW" ] && [ "$NEW" != "$BR" ] && ok "R8 a new app process ($NEW)" || bad "R8 no new process"
alive "$BR" && bad "R8 old pid still alive" || ok "R8 old pid stopped"

echo "-- R9 --if-client-gone, client gone, toolkit-started --detach run → mxcli run restart"
OLD="$(hs_pid "$P")"; kill -TERM "$OLD" 2>/dev/null; sleep 0.5
start_app "$P" --detach && track "$P" || bad "[setup] --detach app did not start"
DP="$(hs_pid "$P")"; echo "$DP" > "$P/.claude/loop/app-restart/owner.pid"; touch "$P/.broken-$DP"
[ -f "$P/.mxcli/run-state.json" ] && ok "[setup] run-state.json present" || bad "[setup] no run-state.json"
OUT="$(ar "$P" --if-client-gone --timeout 20)"; RC=$?; track "$P"
[ "$RC" -eq 0 ] && ok "R9 exit 0" || bad "R9 exit $RC: $(printf '%s' "$OUT" | tail -3)"
[ -f "$P/.restarted-via-mxcli" ] && ok "R9 restarted through mxcli run restart" || bad "R9 mxcli run restart not used"
has "R9 says so" "$OUT" "mxcli run restart -p Fixture.mpr"
N9="$(hs_pid "$P")"; [ -n "$N9" ] && [ "$N9" != "$DP" ] && ok "R9 a new app process" || bad "R9 no new process"
[ "$(cat "$P/.claude/loop/app-restart/owner.pid" 2>/dev/null)" = "$N9" ] && ok "R9 the new pid stays toolkit-started" || bad "R9 owner.pid not updated"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
