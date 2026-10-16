#!/usr/bin/env bash
# test-app-restart.sh — project-bin/app-restart.sh stops only the recorded app and proves it is back.
#
# Usage: bash tests/wave2/test-app-restart.sh [path-to-app-restart.sh]
#
# WHY (#289 item 1, field run 2026-10-12): 24 implementer restart-resumes cost 41.6M tokens because
# only the lead was allowed to restart an app — a broad kill in one lane had once killed another
# lane's app. The helper is only safe to hand to an implementer if it can never do that.
#
# The app is a stand-in for `mxcli run --local` (node, no Mendix): it writes the run --local record
# from the CAPTURED handshake (fixtures/run-local/run-local.json, real field capture) with its own
# pid, port and project, serves a Mendix-marked login page, an index.html that loads
# dist/index.js, and the bundle; it starts one child (the "runtime"); on TERM it removes the record
# like mxcli does. A decoy whose command line also says "mxcli run --local" runs throughout: it must
# survive every case, because the helper may never kill by pattern.
#
# Covers: no record → refuse (exit 3); a record copied from another project → refuse, its pid
# untouched; --dry-run touches nothing; a real restart (old pid + its child gone, new record
# live, port + bundle proven, command remembered, self-gitignored); bundle missing → exit 1 with
# the blank-page message; dead pid + remembered command → start only; dead pid, nothing
# remembered → refuse naming --cmd; secrets masked; no pattern-kill anywhere in the source.
# #262: a stranger on the admin port while our app runs → exit 4 before anything is stopped, the
# stranger named by pid and alive; our app dead and a stranger on the app port → exit 4, nothing
# started. (The stranger is a bare TCP listener, as a runtime's admin port is to curl.)
# #160: the port/tree helpers moved to _common.sh; an older _common.sh stops with exit 2 + the
# sync remedy (this is the case where it would otherwise die on "command not found"); so does one older
# than the mxtest/pid helpers that moved there from this script and test-scratch.sh.
# #304 review: a stale record whose pid was reused by an unrelated process, restarted with --cmd →
# that process survives (the pid is checked to be an mxcli run itself). #244: the settings unit is
# the CAPTURED one (fixtures/mxtest-guard, from mxcli's own test model), re-encoded with the
# after-startup under test: a plain app + leftover injection → exit 3, app untouched; a live
# --test-endpoint app whose stop does not restore → exit 5, nothing started; one whose stop restores
# → restarted.
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

echo "-- source never kills by pattern"
if grep -nE '\b(pkill|killall)\b|pgrep +-[a-zA-Z]*f' "$SUBJECT" | grep -v '^[0-9]*: *#' | grep -q .; then   # portability-ok: a grep FOR pgrep, not a call
  bad "pattern kill in the source: $(grep -nE '\b(pkill|killall)\b|pgrep +-[a-zA-Z]*f' "$SUBJECT" | grep -v '^[0-9]*: *#' | head -2)"   # portability-ok: same
else ok "no pkill / killall / pgrep -f outside comments"; fi   # portability-ok: message text

command -v node >/dev/null 2>&1 && command -v curl >/dev/null 2>&1 || { echo "  [skip] node or curl missing"; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]; exit; }
[ -f "$GOLDEN" ] || { bad "golden handshake missing: $GOLDEN"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/apprestart.XXXXXX")" || exit 2
WORK="$(cd "$WORK" && pwd -P)"
KILL_LIST=""
cleanup() {
  for f in "$WORK"/*/.mxcli/run-local.json; do [ -f "$f" ] && KILL_LIST="$KILL_LIST $(sed -n 's/^  "pid": *\([0-9]*\).*/\1/p' "$f")"; done
  for p in $KILL_LIST; do pkill -KILL -P "$p" 2>/dev/null; kill -KILL "$p" 2>/dev/null; done   # test teardown only, by pid
  rm -rf "$WORK"
}
trap cleanup EXIT

mkapp() {  # $1 = project dir, $2 = port
  local P="$1"
  mkdir -p "$P/bin"
  printf 'not a real model\n' > "$P/Fixture.mpr"
  cp "$TOOLKIT/project-bin/_common.sh" "$P/bin/"; cp "$SUBJECT" "$P/bin/app-restart.sh"
  echo "$2" > "$P/.fakeport"
  cat > "$P/mxcli" <<'JS'
#!/usr/bin/env node
// Stand-in for `mxcli run --local`: record, serve, child, clean exit on TERM.
const fs = require('fs'), http = require('http'), path = require('path'), cp = require('child_process');
const dir = process.cwd(), hs = path.join(dir, '.mxcli', 'run-local.json');
const port = parseInt(fs.readFileSync(path.join(dir, '.fakeport'), 'utf8'), 10);
fs.writeFileSync(path.join(dir, '.fakeargv'), process.argv.slice(2).join('\n') + '\n');   // what the launch really passed
const child = cp.spawn('sleep', ['300'], { stdio: 'ignore' });
fs.writeFileSync(path.join(dir, '.fakechild'), String(child.pid));
http.createServer((req, res) => {
  const u = req.url.split('?')[0];
  if (u === '/login.html' || u === '/index.html' || u === '/')
    return res.end('<html><head><title>Mendix</title><script src="dist/index.js?abc123"></script></head><body class="mxui"></body></html>');
  if (u === '/dist/index.js' && !fs.existsSync(path.join(dir, '.nobundle'))) return res.end('/* bundle */');
  res.statusCode = 404; res.end('nope');
}).listen(port, '127.0.0.1', () => {
  const g = fs.readFileSync(process.env.FAKE_GOLDEN, 'utf8')
    .replace(/^  "project": "[^"]*"/m, '  "project": ' + JSON.stringify(path.join(dir, 'Fixture.mpr')))
    .replace(/^  "pid": \d+/m, '  "pid": ' + process.pid)
    .replace(/^  "appPort": \d+/m, '  "appPort": ' + port)
    .replace(/^  "adminPort": \d+/m, '  "adminPort": ' + (port + 10))
    .replace(/^  "adminPass": "[^"]*"/m, '  "adminPass": "x"');
  fs.mkdirSync(path.dirname(hs), { recursive: true });
  setTimeout(() => fs.writeFileSync(hs, g), 300);   // written when "ready", as mxcli does
});
// .restore_on_stop (two lines: source, target) stands in for run --test-endpoint's clean-exit restore.
const stop = () => { try { const r = fs.readFileSync(path.join(dir, '.restore_on_stop'), 'utf8').trim().split('\n'); fs.copyFileSync(r[0], r[1]); } catch (e) {}
  try { fs.unlinkSync(hs); } catch (e) {} try { child.kill('SIGTERM'); } catch (e) {} process.exit(0); };
process.on('SIGTERM', stop); process.on('SIGINT', stop);
JS
  chmod +x "$P/mxcli" "$P/bin/app-restart.sh"
}
start_app() {  # $1 = project dir, $2 = extra run flags (optional); waits for the record
  ( cd "$1" && FAKE_GOLDEN="$GOLDEN" setsid nohup ./mxcli run --local --watch ${2:-} -p Fixture.mpr >"$1/first.log" 2>&1 </dev/null & )
  local i; for i in $(seq 1 50); do [ -f "$1/.mxcli/run-local.json" ] && return 0; sleep 0.2; done; return 1
}
hs_pid() { sed -n 's/^  "pid": *\([0-9]*\).*/\1/p' "$1/.mxcli/run-local.json" 2>/dev/null; }
# Zombie-aware: a stopped child nobody has reaped yet still answers kill -0 (3/10 flakes on "was not stopped").
alive() { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null || return 1; case "$(ps -o stat= -p "$1" 2>/dev/null)" in Z*) return 1 ;; esac; }
restart() { ( cd "$1" && shift && FAKE_GOLDEN="$GOLDEN" LOGDIR="$WORK" ./bin/app-restart.sh "$@" ) 2>&1; }

PORT=$(( 20000 + RANDOM % 20000 ))
P="$WORK/proj"; mkapp "$P" "$PORT"
# The decoy: same words on its command line, different project. Must never be touched.
bash -c 'exec -a "mxcli run --local --watch -p /elsewhere/Other.mpr" sleep 300' & DECOY=$!; KILL_LIST="$KILL_LIST $DECOY"

echo "-- no record → refuse, nothing stopped"
OUT="$(restart "$P")"; RC=$?
[ "$RC" -eq 3 ] && ok "exit 3" || bad "exit $RC: $OUT"
has "says it never kills by name or pattern" "$OUT" "never"
alive "$DECOY" && ok "decoy untouched" || bad "decoy killed"

start_app "$P" && ok "[setup] stand-in app wrote its record" || bad "[setup] stand-in app never became ready"
OLD="$(hs_pid "$P")"; OLDKID="$(cat "$P/.fakechild" 2>/dev/null)"; KILL_LIST="$KILL_LIST $OLD $OLDKID"

echo "-- a record copied from another project → refuse, its pid untouched"
C="$WORK/copy"; mkapp "$C" "$PORT"; mkdir -p "$C/.mxcli"; cp "$P/.mxcli/run-local.json" "$C/.mxcli/"
OUT="$(restart "$C")"; RC=$?
[ "$RC" -eq 3 ] && ok "exit 3" || bad "exit $RC"
has "names the other project" "$OUT" "belongs to another project"
alive "$OLD" && ok "the original's app is still running" || bad "the copy's restart killed the original's app"
rm -f "$C/.mxcli/run-local.json"

echo "-- --dry-run touches nothing"
OUT="$(restart "$P" --dry-run)"; RC=$?
[ "$RC" -eq 0 ] && ok "exit 0" || bad "exit $RC: $OUT"
has "names the recorded pid" "$OUT" "pid $OLD"
has "names the start command it read" "$OUT" "run --local --watch -p Fixture.mpr"
alive "$OLD" && ok "app still running" || bad "dry run stopped the app"

echo "-- restart"
OUT="$(restart "$P" --timeout 30)"; RC=$?
[ "$RC" -eq 0 ] && ok "exit 0" || bad "exit $RC: $(printf '%s' "$OUT" | tail -4)"
has "proves the bundle" "$OUT" "dist/index.js?abc123 answers"
sleep 0.5
alive "$OLD" && bad "old pid $OLD still alive" || ok "old pid stopped"
alive "$OLDKID" && bad "old child $OLDKID still alive" || ok "its child (the runtime) stopped"
NEW="$(hs_pid "$P")"; KILL_LIST="$KILL_LIST $NEW $(cat "$P/.fakechild" 2>/dev/null)"
[ -n "$NEW" ] && [ "$NEW" != "$OLD" ] && alive "$NEW" && ok "new record, live pid $NEW" || bad "no new live record (pid '$NEW')"
alive "$DECOY" && ok "decoy untouched" || bad "decoy killed"
[ -f "$P/.claude/loop/app-restart/start.cmd" ] && ok "start command remembered" || bad "start command not remembered"
[ "$(cat "$P/.claude/loop/app-restart/.gitignore" 2>/dev/null)" = "*" ] && ok "  and self-gitignored" || bad "record dir not self-gitignored"

echo "-- bundle missing → not up (blank page)"
touch "$P/.nobundle"
OUT="$(restart "$P" --timeout 6)"; RC=$?
[ "$RC" -eq 1 ] && ok "exit 1" || bad "exit $RC"
has "says the bundle is not served" "$OUT" "Page bundle not served"
rm -f "$P/.nobundle"
KILL_LIST="$KILL_LIST $(hs_pid "$P") $(cat "$P/.fakechild" 2>/dev/null)"

echo "-- dead pid + remembered command → start only"
D="$(hs_pid "$P")"; DK="$(cat "$P/.fakechild" 2>/dev/null)"
kill -KILL "$D" "$DK" 2>/dev/null; sleep 0.5
[ -f "$P/.mxcli/run-local.json" ] && ok "[setup] SIGKILL left a stale record" || bad "[setup] no stale record"
OUT="$(restart "$P" --timeout 30)"; RC=$?
[ "$RC" -eq 0 ] && ok "exit 0" || bad "exit $RC: $(printf '%s' "$OUT" | tail -4)"
has "says there was nothing to stop" "$OUT" "nothing — recorded pid $D is not running"
has "uses the remembered command" "$OUT" "remembered from the last restart"
KILL_LIST="$KILL_LIST $(hs_pid "$P") $(cat "$P/.fakechild" 2>/dev/null)"

echo "-- #304 review: a stale record whose pid now belongs to another process → that process is never stopped"
# A SIGKILLed mxcli leaves its record; the OS reuses the pid. With --cmd the start command no longer
# comes from the pid, so only a check on the pid itself can tell. The old code sent it TERM.
R="$WORK/reused"; RPORT=$(( PORT + 200 )); mkapp "$R" "$RPORT"
sleep 300 & REUSED=$!; KILL_LIST="$KILL_LIST $REUSED"
mkdir -p "$R/.mxcli"
sed -e "s|^  \"project\": \"[^\"]*\"|  \"project\": $(printf '%s' "$R/Fixture.mpr" | sed 's/[&|]/\\&/g; s/.*/"&"/')|" \
    -e "s/^  \"pid\": [0-9]*/  \"pid\": $REUSED/" -e "s/^  \"appPort\": [0-9]*/  \"appPort\": $RPORT/" \
    -e "s/^  \"adminPort\": [0-9]*/  \"adminPort\": $(( RPORT + 10 ))/" "$GOLDEN" > "$R/.mxcli/run-local.json"
OUT="$(restart "$R" --timeout 30 --cmd './mxcli run --local --watch -p Fixture.mpr')"; RC=$?
alive "$REUSED" && ok "the process holding the reused pid is untouched" || bad "the reused pid $REUSED was killed"
has "says the pid is not an mxcli run" "$OUT" "is not an mxcli run"
[ "$RC" -eq 0 ] && ok "the app is started (exit 0)" || bad "exit $RC: $(printf '%s' "$OUT" | tail -3)"
KILL_LIST="$KILL_LIST $(hs_pid "$R") $(cat "$R/.fakechild" 2>/dev/null)"

echo "-- #244: an after-startup left on an mxcli test injection"
GU="$TOOLKIT/tests/wave2/fixtures/mxtest-guard/settings-unit.mxunit"
SETAS="$TOOLKIT/tests/wave2/fixtures/mxtest-guard/set-after-startup.js"
UNIT="$P/mprcontents/4e/70/4e70063d-53e1-477a-ab92-6b763330c293.mxunit"; mkdir -p "$(dirname "$UNIT")"
cp "$GU" "$UNIT"; cp "$GU" "$P/.clean.mxunit"
CUR="$(hs_pid "$P")"
node "$SETAS" "$GU" "$UNIT" "MxTest.RegisterEndpoint"
OUT="$(restart "$P" --timeout 10)"; RC=$?
[ "$RC" -eq 3 ] && ok "plain run --local app + leftover injection → refused (exit 3)" || bad "exit $RC: $(printf '%s' "$OUT" | tail -3)"
has "names the leftover" "$OUT" "after-startup microflow is MxTest.RegisterEndpoint"
has "prints the MDL repair" "$OUT" "alter settings runtime (AfterStartupMicroflow:"
has "says nothing was stopped" "$OUT" "Nothing was stopped"
alive "$CUR" && ok "the app was left running" || bad "the app was stopped"
OUT="$(MXTK_SKIP_MXTEST_GUARD=1 restart "$P" --dry-run)"; RC=$?
[ "$RC" -eq 0 ] && has "MXTK_SKIP_MXTEST_GUARD=1 lets it through, out loud" "$OUT" "NOT checking" || bad "override exit $RC"
cp "$GU" "$UNIT"

echo "-- #244: a live --test-endpoint app holds the injection legitimately; a stop that does not restore it → exit 5"
OUT="$(restart "$P" --timeout 30 --cmd './mxcli run --local --watch --test-endpoint -p Fixture.mpr')"; RC=$?
[ "$RC" -eq 0 ] && ok "[setup] app restarted with --test-endpoint" || bad "[setup] exit $RC: $(printf '%s' "$OUT" | tail -3)"
CUR="$(hs_pid "$P")"; KILL_LIST="$KILL_LIST $CUR $(cat "$P/.fakechild" 2>/dev/null)"
node "$SETAS" "$GU" "$UNIT" "MxTest.RegisterEndpoint"     # what run --test-endpoint writes while it runs
OUT="$(restart "$P" --timeout 10)"; RC=$?
[ "$RC" -eq 5 ] && ok "exit 5" || bad "exit $RC: $(printf '%s' "$OUT" | tail -3)"
has "says it stopped and started nothing" "$OUT" "The recorded app was stopped; nothing was started"
hasnt "starts nothing" "$OUT" "started (log:"
alive "$CUR" && bad "the app was not stopped" || ok "the --test-endpoint app was stopped"
echo "-- #244: repaired and started by hand (the stop removed the record); a stop that restores restarts normally"
cp "$GU" "$UNIT"
start_app "$P" --test-endpoint && ok "[setup] --test-endpoint app started again" || bad "[setup] app never became ready"
KILL_LIST="$KILL_LIST $(hs_pid "$P") $(cat "$P/.fakechild" 2>/dev/null)"
node "$SETAS" "$GU" "$UNIT" "MxTest.RegisterEndpoint"; printf '%s\n%s\n' "$P/.clean.mxunit" "$UNIT" > "$P/.restore_on_stop"
OUT="$(restart "$P" --timeout 30)"; RC=$?
[ "$RC" -eq 0 ] && ok "a stop that restores → restarted (exit 0)" || bad "exit $RC: $(printf '%s' "$OUT" | tail -3)"
rm -f "$P/.restore_on_stop"; cp "$GU" "$UNIT"
KILL_LIST="$KILL_LIST $(hs_pid "$P") $(cat "$P/.fakechild" 2>/dev/null)"

# A process this script did not start, listening on $1 — the Studio Pro runtime of #262.
stranger() {
  node -e "require('net').createServer(()=>{}).listen($1,'127.0.0.1')" & STR=$!; KILL_LIST="$KILL_LIST $STR"
  local i; for i in $(seq 1 50); do alive "$STR" && (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null && return 0; sleep 0.1; done; return 1
}
CAN_NAME=0; { command -v lsof >/dev/null 2>&1 || command -v ss >/dev/null 2>&1; } && CAN_NAME=1

echo "-- #262: a stranger holds the admin port while our app runs → exit 4, nothing stopped"
CUR="$(hs_pid "$P")"; CURKID="$(cat "$P/.fakechild" 2>/dev/null)"
if [ "$CAN_NAME" = 1 ]; then
  stranger $((PORT + 10)) && ok "[setup] stranger listening on :$((PORT + 10))" || bad "[setup] stranger never listened"
  OUT="$(restart "$P" --timeout 10)"; RC=$?
  [ "$RC" -eq 4 ] && ok "exit 4" || bad "exit $RC: $(printf '%s' "$OUT" | tail -4)"
  has "says instrument blocked" "$OUT" "instrument blocked"
  has "names the holder's pid" "$OUT" "pid $STR"
  has "says nothing was stopped" "$OUT" "Nothing was stopped"
  alive "$CUR" && ok "our app still running" || bad "our app was stopped although the start could never succeed"
  alive "$STR" && ok "stranger untouched" || bad "stranger killed"
  kill -KILL "$STR" 2>/dev/null; wait "$STR" 2>/dev/null
else
  echo "  [skip] neither lsof nor ss — a holder beside a live app cannot be told from the app's own runtime"
fi

echo "-- #262: our app died and a stranger took the app port → exit 4, nothing started"
CUR="$(hs_pid "$P")"; CURKID="$(cat "$P/.fakechild" 2>/dev/null)"
kill -KILL "$CUR" "$CURKID" 2>/dev/null; sleep 0.5
stranger "$PORT" && ok "[setup] stranger listening on :$PORT" || bad "[setup] stranger never listened"
OUT="$(restart "$P" --timeout 10)"; RC=$?
[ "$RC" -eq 4 ] && ok "exit 4" || bad "exit $RC: $(printf '%s' "$OUT" | tail -4)"
has "says instrument blocked" "$OUT" "instrument blocked — port :$PORT"
[ "$CAN_NAME" = 1 ] && has "names the holder's pid" "$OUT" "pid $STR"
hasnt "starts nothing" "$OUT" "started (log:"
alive "$STR" && ok "stranger untouched" || bad "stranger killed"
NEWP="$(hs_pid "$P")"; [ "$NEWP" = "$CUR" ] && ok "no new record written" || { bad "the record changed: an app was started or the record removed (pid '$NEWP')"; KILL_LIST="$KILL_LIST $NEWP"; }
kill -KILL "$STR" 2>/dev/null; wait "$STR" 2>/dev/null

echo "-- dead pid, nothing remembered, no --cmd → refuse naming --cmd"
D="$(hs_pid "$P")"; kill -KILL "$D" "$(cat "$P/.fakechild" 2>/dev/null)" 2>/dev/null; sleep 0.5
rm -rf "$P/.claude/loop/app-restart"
OUT="$(restart "$P")"; RC=$?
[ "$RC" -eq 3 ] && ok "exit 3" || bad "exit $RC"
has "points at --cmd" "$OUT" "--cmd"

echo "-- secrets masked"
OUT="$(restart "$P" --dry-run --cmd './mxcli run --local --db-password hunter2 -p Fixture.mpr')"
hasnt "a password value never reaches the screen" "$OUT" "hunter2"
OUT="$(restart "$P" --dry-run --cmd './mxcli run --local --constant Mod.HubApiPassword=s3cretA --constant Mod.Api_Token=tokB --db-password hunter3 --db-password=hunter4 --constant Mod.Port=8080 -p Fixture.mpr')"
hasnt "--constant Name=value with a Password name is masked" "$OUT" "s3cretA"
hasnt "a Token-named constant is masked" "$OUT" "tokB"
hasnt "--db-password <value> and --db-password=<value> are masked" "$OUT" "hunter3"
hasnt "the = form is masked" "$OUT" "hunter4"
has "a non-secret constant stays readable" "$OUT" "Mod.Port=8080"
echo "-- secrets masked: quoted values with spaces, wider word list (follow-up to #403)"
OUT="$(restart "$P" --dry-run --cmd './mxcli run --local --constant "Mod.ApiKey=two words" --db-password '"'"'zqx pw9'"'"' --constant Mod.Pwd=pwdv --constant Mod.Credential=credv --constant Mod.Passphrase=ppv --constant Mod.ClientSecret=csv -p Fixture.mpr')"
hasnt "a double-quoted Name=value with spaces is masked whole (first word)" "$OUT" "two"
hasnt "a double-quoted Name=value with spaces is masked whole (tail)" "$OUT" "words"
hasnt "--db-password 'two words' is masked whole (first word)" "$OUT" "zqx"
hasnt "--db-password 'two words' is masked whole (tail)" "$OUT" "pw9"
hasnt "a Pwd-named constant is masked" "$OUT" "pwdv"
hasnt "a Credential-named constant is masked" "$OUT" "credv"
hasnt "a Passphrase-named constant is masked" "$OUT" "ppv"
hasnt "a ClientSecret-named constant is masked" "$OUT" "csv"
has "the rest of the command stays readable" "$OUT" "-p Fixture.mpr"
has "a Name is kept, only the value masked" "$OUT" "Mod.ApiKey="
# Known over-mask, pinned so it does not get worse unnoticed: a substring match on Key.
OUT="$(restart "$P" --dry-run --cmd './mxcli run --local --constant Mod.Monkey=1 --constant Mod.Port=8080 -p Fixture.mpr')"
hasnt "known over-mask: Monkey matches Key" "$OUT" "Mod.Monkey=1"
has "a name with no secret word stays readable" "$OUT" "Mod.Port=8080"
echo "-- the masked display never changes the executed command (real launch path)"
CUR="$(hs_pid "$P")"; KILL_LIST="$KILL_LIST $CUR $(cat "$P/.fakechild" 2>/dev/null)"
OUT="$(restart "$P" --timeout 30 --cmd './mxcli run --local --constant "Mod.ApiKey=two words" --db-password '"'"'zqx pw9'"'"' --constant Mod.Pwd=pwdv -p Fixture.mpr')"; RC=$?
KILL_LIST="$KILL_LIST $(hs_pid "$P") $(cat "$P/.fakechild" 2>/dev/null)"
[ "$RC" -eq 0 ] && ok "the restart with secrets in --cmd succeeded" || bad "exit $RC: $(printf '%s' "$OUT" | tail -4)"
EXPECT_ARGV="$(printf '%s\n' run --local --constant 'Mod.ApiKey=two words' --db-password 'zqx pw9' --constant Mod.Pwd=pwdv -p Fixture.mpr)"
[ "$(cat "$P/.fakeargv" 2>/dev/null)" = "$EXPECT_ARGV" ] && ok "the started app received the raw argv, byte-identical" || bad "started app argv differs: $(cat "$P/.fakeargv" 2>/dev/null)"
hasnt "the printed output hides the spaced secret" "$OUT" "words"
hasnt "the printed output hides the --db-password value" "$OUT" "zqx"
case "$(cat "$P/.claude/loop/app-restart/start.cmd" 2>/dev/null)" in *"Mod.ApiKey=two words"*zqx\ pw9*) ok "start.cmd remembers the raw secrets" ;; *) bad "start.cmd lost the raw command" ;; esac
echo "-- env assignment at the start of a --cmd string keeps the whole command visible"
OUT="$(restart "$P" --dry-run --cmd 'DB_PASSWORD=envsecret ./mxcli run --local --watch -p Fixture.mpr')"
hasnt "the env secret is masked" "$OUT" "envsecret"
has "the whole command stays visible, quoted" "$OUT" "bash -c 'DB_PASSWORD=**** ./mxcli run --local --watch -p Fixture.mpr'"
OUT="$(restart "$P" --dry-run --cmd 'DB_PASSWORD=envsecret echo hi')"
hasnt "[refuse path] the env secret is masked" "$OUT" "envsecret"
has "[refuse path] the whole command stays visible" "$OUT" "bash -c 'DB_PASSWORD=**** echo hi'"
OUT="$(restart "$P" --dry-run --cmd 'echo "Mod.ApiKey=two words"')"
hasnt "[refuse path] a non-mxcli command masks a spaced secret too" "$OUT" "words"
alive "$DECOY" && ok "decoy survived the whole run" || bad "decoy killed"

echo "-- #160: a bin/_common.sh older than the moved helpers → exit 2 naming sync, nothing stopped"
O="$WORK/oldcommon"; mkapp "$O" "$PORT"
sed '/^# Process identity — who holds a port/,$d' "$TOOLKIT/project-bin/_common.sh" > "$O/bin/_common.sh"
grep -q mxtk_port_holder "$O/bin/_common.sh" && bad "[setup] could not strip the helpers" || ok "[setup] _common.sh without the shared helpers"
OUT="$(restart "$O" --dry-run)"; RC=$?
[ "$RC" -eq 2 ] && ok "exit 2" || bad "exit $RC: $(printf '%s' "$OUT" | tail -2)"
has "names the remedy" "$OUT" "sync-project.sh"
hasnt "no command-not-found mid-run" "$OUT" "command not found"

echo "-- a bin/_common.sh older than the shared mxtest/pid helpers → exit 2 naming sync, nothing stopped"
O2="$WORK/oldcommon2"; mkapp "$O2" "$PORT"
sed '/^# mxcli run \/ test identity/,$d' "$TOOLKIT/project-bin/_common.sh" > "$O2/bin/_common.sh"
grep -q mxtk_port_holder "$O2/bin/_common.sh" && ! grep -q 'mxtest_left\|mxtk_pid_is_mxcli_run' "$O2/bin/_common.sh" \
  && ok "[setup] _common.sh with the port helpers, without the mxtest/pid helpers" || bad "[setup] could not strip only the mxtest/pid helpers"
OUT="$(restart "$O2" --dry-run)"; RC=$?
[ "$RC" -eq 2 ] && ok "exit 2" || bad "exit $RC: $(printf '%s' "$OUT" | tail -2)"
has "names what is missing" "$OUT" "no mxtest_left"
has "names the remedy" "$OUT" "sync-project.sh"
hasnt "no command-not-found mid-run" "$OUT" "command not found"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
