#!/usr/bin/env bash
# test-test-scratch.sh — project-bin/test-scratch.sh runs `mxcli test` on a copy, under locks.
#
# Usage: bash tests/wave2/test-test-scratch.sh [path-to-test-scratch.sh]
#
# WHY (#278, field run 2026-10-12): one `mxcli test` run unlocked in the live repo broke the
# running app (NoClassDefFoundError) with the .mpr unchanged; the fix that worked — scratch copy
# plus a lock on the fixed test ports — lived only in a private helper.
#
# Covers: the fake mxcli runs in the scratch dir with -p on the scratch .mpr, never the live one;
# the copy leaves out .mxcli (the live app's run --local record), .git and deployment; the port
# lock is held during the run and released after; a second run while the first holds the ports
# is refused; a dead holder's port lock is taken over; a live exec.sh on the project refuses the
# copy; --attach and -p are refused; mxcli's exit code is passed through; the copy is deleted;
# a bin/_common.sh older than the shared mxtest helpers stops with exit 2 and the sync remedy.
# Speed (feat/test-speed-one-boot): several test files run in ONE mxcli call; a file with
# `@cleanup none` and, with --per-file, every file gets its own; a flag value is never taken for a file;
# the warm copy keeps .mxcli + deployment between runs, is re-synced from the live model every time,
# never carries the live run record, and is dropped on --cold, a new mxcli, age, a leftover test
# injection; --no-cache is the old throwaway copy.
# No real mxcli: a stub records its cwd and argv.
set -uo pipefail
TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/project-bin/test-scratch.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
WORK="$(mktemp -d "${TMPDIR:-/tmp}/tscratch.XXXXXX")" || exit 2
WORK="$(cd "$WORK" && pwd -P)"
BG=""
trap 'for p in $BG; do kill -KILL "$p" 2>/dev/null; done; rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 — missing '$3' in: $(printf '%s' "$2" | tail -3)" ;; esac; }
echo "== subject: $SUBJECT"

P="$WORK/proj"; mkdir -p "$P/bin" "$P/mprcontents" "$P/.mxcli" "$P/deployment/run" "$P/tests" "$WORK/tmp"
printf 'model\n' > "$P/Fixture.mpr"; printf 'unit\n' > "$P/mprcontents/a.mxunit"
printf '{"pid": 1}\n' > "$P/.mxcli/run-local.json"; printf 'x\n' > "$P/deployment/run/big"
printf 'test\n' > "$P/tests/a.test.mdl"
cp "$TOOLKIT/project-bin/_common.sh" "$P/bin/"; cp "$SUBJECT" "$P/bin/test-scratch.sh"
cat > "$P/mxcli" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = "--version" ] && { echo "mxcli version ${STUB_VER:-stub-1}"; exit 0; }
echo "$*" >> "${REC}.calls"
{ echo "cwd=$(pwd -P)"; echo "args=$*"; ls -A; ls "${TMPDIR:-/tmp}" | grep -c mxtk-test-ports; } > "$REC"
sleep "${STUB_SLEEP:-0}"
echo "TESTRUNNER injected" >> Fixture.mpr      # what a real test run does to ITS model
exit "${STUB_RC:-0}"
STUB
chmod +x "$P/mxcli" "$P/bin/test-scratch.sh"
export TMPDIR="$WORK/tmp" MXTK_TEST_PORTS="$(( 30000 + RANDOM % 20000 )) $(( 30000 + RANDOM % 20000 ))"
run() { ( cd "$P" && REC="$WORK/rec.$1" ./bin/test-scratch.sh "${@:2}" ) 2>&1; }

echo "-- a scratch run"
OUT="$(run a --no-cache -- tests/a.test.mdl --local)"; RC=$?
[ "$RC" -eq 0 ] && ok "exit 0" || bad "exit $RC: $OUT"
R="$(cat "$WORK/rec.a" 2>/dev/null)"
case "$R" in *"cwd=$WORK/tmp/Fixture-test."*) ok "mxcli ran in the scratch copy" ;; *) bad "mxcli cwd: $(printf '%s' "$R" | head -1)" ;; esac
case "$R" in *"-p $WORK/tmp/Fixture-test."*"/Fixture.mpr"*) ok "-p points at the scratch .mpr" ;; *) bad "args: $(printf '%s' "$R" | sed -n 2p)" ;; esac
printf '%s' "$R" | grep -qx '.mxcli' && bad "the live run --local record was copied" || ok ".mxcli (live app record) not copied"
printf '%s' "$R" | grep -qx 'deployment' && bad "deployment/ was copied" || ok "deployment/ not copied"
[ "$(printf '%s' "$R" | tail -1)" = 1 ] && ok "port lock held during the run" || bad "no port lock during the run"
[ "$(cat "$P/Fixture.mpr")" = model ] && ok "live .mpr untouched" || bad "live .mpr was written"
grep -q 'mxtk-test-ports' <<<"$(ls "$WORK/tmp")" && bad "port lock left behind" || ok "port lock released"
grep -q 'Fixture-test' <<<"$(ls "$WORK/tmp")" && bad "scratch copy left behind" || ok "scratch copy deleted"
[ -f "$P/.mpr-snapshots/.exec.lock" ] && bad "exec lock left behind" || ok "exec lock released"

echo "-- exit code passes through"
OUT="$(STUB_RC=4 run b -- tests/a.test.mdl)"; RC=$?
[ "$RC" -eq 4 ] && ok "mxcli exit 4 → 4" || bad "exit $RC"

echo "-- second run while the first holds the ports"
( cd "$P" && STUB_SLEEP=4 REC="$WORK/rec.c" exec ./bin/test-scratch.sh -- tests/a.test.mdl ) >/dev/null 2>&1 &
H=$!; BG="$BG $H"
for i in $(seq 1 40); do [ -f "$WORK/rec.c" ] && break; sleep 0.1; done
OUT="$(run d -- tests/a.test.mdl)"; RC=$?
[ "$RC" -eq 3 ] && ok "refused (exit 3)" || bad "exit $RC"
has "names the holder" "$OUT" "held by PID $H"
[ -f "$WORK/rec.d" ] && bad "the refused run ran mxcli" || ok "the refused run ran nothing"
kill -KILL "$H" 2>/dev/null; wait "$H" 2>/dev/null

echo "-- dead holder's port lock is taken over (the SIGKILL above left it)"
grep -q 'mxtk-test-ports' <<<"$(ls "$WORK/tmp")" && ok "[setup] stale port lock present" || bad "[setup] no stale lock"
rm -f "$P/.mpr-snapshots/.exec.lock"
OUT="$(run e -- tests/a.test.mdl)"; RC=$?
[ "$RC" -eq 0 ] && has "taken over out loud" "$OUT" "taking it over" || bad "stale port lock blocked (exit $RC)"

echo "-- a live exec.sh on this project refuses the copy"
mkdir -p "$P/.mpr-snapshots"; bash -c 'exec -a "bash ./bin/exec.sh mdlsource/x.mdl" sleep 20' & E=$!; BG="$BG $E"
sleep 0.2; printf '%s %s x.mdl\n' "$E" "$(date +%s)" > "$P/.mpr-snapshots/.exec.lock"
OUT="$(run f -- tests/a.test.mdl)"; RC=$?
[ "$RC" -eq 3 ] && ok "refused (exit 3)" || bad "exit $RC"
[ -f "$WORK/rec.f" ] && bad "ran during a live exec" || ok "nothing copied or run"
kill -KILL "$E" 2>/dev/null; wait "$E" 2>/dev/null; rm -f "$P/.mpr-snapshots/.exec.lock"

echo "-- refusals"
OUT="$(run g -- tests/a.test.mdl --attach)"; RC=$?
[ "$RC" -eq 3 ] && has "--attach refused" "$OUT" "LIVE app" || bad "--attach exit $RC"
OUT="$(run h -- tests/a.test.mdl -p Other.mpr)"; RC=$?
[ "$RC" -eq 2 ] && ok "-p refused" || bad "-p exit $RC"

echo "-- a bin/_common.sh older than the shared mxtest helpers → exit 2 naming sync, nothing copied or run"
OC="$WORK/oldcommon"; mkdir -p "$OC/bin"; cp "$P/Fixture.mpr" "$P/mxcli" "$OC/"; cp "$P/bin/test-scratch.sh" "$OC/bin/"
sed '/^# mxcli run \/ test identity/,$d' "$TOOLKIT/project-bin/_common.sh" > "$OC/bin/_common.sh"
grep -q '^find_mpr()' "$OC/bin/_common.sh" && ! grep -q 'mxtest_left' "$OC/bin/_common.sh" \
  && ok "[setup] _common.sh without the mxtest helpers" || bad "[setup] could not strip only the mxtest helpers"
OUT="$( cd "$OC" && REC="$WORK/rec.oc" ./bin/test-scratch.sh -- tests/a.test.mdl 2>&1 )"; RC=$?
[ "$RC" -eq 2 ] && ok "exit 2" || bad "exit $RC: $(printf '%s' "$OUT" | tail -2)"
has "names the remedy" "$OUT" "sync-project.sh"
case "$OUT" in *"command not found"*) bad "died on command not found" ;; *) ok "no command-not-found" ;; esac
[ -f "$WORK/rec.oc" ] && bad "mxcli ran" || ok "nothing run"


echo "-- #304 review: a stale-lock takeover never removes a lock another run took meanwhile"
# Deterministic replay of the race: the functions are lifted from the subject, and holder_live
# is wrapped so that, while this run judges the dead holder, a second run completes its own
# takeover and writes a live lock. The old code then `mv -f`'d that live lock away and took
# the lock too — two holders. Taking over must re-read and leave a changed lock alone.
H="$WORK/harness.sh"; L="$WORK/race.lock"
awk '/^holder_live\(\) \{/ {p=1} /^release\(\) \{/ {p=0} p' "$SUBJECT" > "$H"
grep -q '^take_lock() {' "$H" && ok "[setup] lifted holder_live..take_lock from the subject" || bad "[setup] could not lift take_lock"
sleep 300 & LIVE=$!; BG="$BG $LIVE"
OUT="$( L="$L" LIVE="$LIVE" bash -c '
  . "$1"
  eval "orig_$(declare -f holder_live)"
  holder_live() {   # the dead holder is being judged: another run finishes ITS takeover now
    [ "$1" = 999999 ] && printf "%s %s %s\n" "$LIVE" "$(date +%s)" "test-scratch.sh" > "$L"
    [ "$1" = "$LIVE" ]
  }
  printf "999999 1 test-scratch.sh\n" > "$L"
  take_lock "$L" "race lock"; echo "rc=$?"
' _ "$H" 2>&1 )"
has "the second taker is refused (the live lock survives)" "$OUT" "rc=1"
[ "$(cut -d' ' -f1 "$L" 2>/dev/null)" = "$LIVE" ] && ok "the lock still names the live holder" || bad "the live holder's lock was replaced: $(cat "$L" 2>/dev/null)"
[ -e "$L.takeover" ] && bad "takeover marker left behind" || ok "takeover marker cleared"
echo "-- a takeover marker whose pid is dead (a takeover that died midway) is cleared"
printf '999999 1 test-scratch.sh\n' > "$L"; printf '999998 1\n' > "$L.takeover"
OUT="$( L="$L" bash -c '. "$1"; holder_live() { return 1; }; take_lock "$L" "race lock"; echo "rc=$?"' _ "$H" 2>&1 )"
has "taken after clearing the dead marker" "$OUT" "rc=0"
[ "$(cut -d' ' -f1 "$L" 2>/dev/null)" != 999999 ] && ok "the stale line is gone" || bad "stale line still there"
echo "-- #324 review: a FRESH empty takeover file (its creator between create and write) is not stale"
# find -mmin +0 counted a 0-2 s old file as old (GNU; BSD rounds up), so a takeover in progress was
# treated as dead and two contenders could both take over. +1 = empty for over a minute.
printf '999999 1 test-scratch.sh\n' > "$L"; : > "$L.takeover"
OUT="$( L="$L" bash -c '. "$1"; holder_live() { return 1; }; take_lock "$L" "race lock"; echo "rc=$?"' _ "$H" 2>&1 )"
has "not taken while a fresh empty takeover file exists" "$OUT" "rc=1"
[ -e "$L.takeover" ] && [ ! -s "$L.takeover" ] && ok "the fresh takeover file was left alone" || bad "the fresh takeover file was removed or replaced"
[ "$(cut -d' ' -f1 "$L" 2>/dev/null)" = 999999 ] && ok "the lock was not touched" || bad "the lock was taken over under a live takeover"
touch -t 200001010000 "$L.takeover"
OUT="$( L="$L" bash -c '. "$1"; holder_live() { return 1; }; take_lock "$L" "race lock"; echo "rc=$?"' _ "$H" 2>&1 )"
has "an empty takeover file over a minute old is stale → taken" "$OUT" "rc=0"
[ -e "$L.takeover" ] && bad "takeover file left behind" || ok "and no takeover file is left behind"
kill -KILL "$LIVE" 2>/dev/null; wait "$LIVE" 2>/dev/null

echo "-- speed: several files run in ONE mxcli call (one boot), flags go to it once, a flag VALUE is not a file"
rm -rf "$WORK/tmp"/Fixture-test*
printf '/**\n * @test one\n * @expect $A = 1\n */\n$A = 1;\n/\n' > "$P/tests/b.test.mdl"
printf '/**\n * @test two\n * @expect $A = 1\n */\n$A = 1;\n/\n' > "$P/tests/c.test.mdl"
printf '/**\n * @test keeps rows\n * @cleanup none\n * @expect $A = 1\n */\n$A = 1;\n/\n' > "$P/tests/leaky.test.mdl"
OUT="$(run s1 -- tests/a.test.mdl tests/b.test.mdl tests/c.test.mdl --local --db-type hsqldb --constant M.X=1)"; RC=$?
[ "$RC" -eq 0 ] && ok "exit 0" || bad "exit $RC: $OUT"
[ "$(wc -l < "$WORK/rec.s1.calls" | tr -d ' ')" = 1 ] && ok "3 files → 1 mxcli call" || bad "calls: $(cat "$WORK/rec.s1.calls")"
has "all three files in it" "$(cat "$WORK/rec.s1.calls")" "test tests/a.test.mdl tests/b.test.mdl tests/c.test.mdl --local --db-type hsqldb --constant M.X=1"
has "says 1 boot" "$OUT" "3 test files → 1 boot(s)"

echo "-- speed: a file with @cleanup none gets its own boot, after the shared one; flags reach both"
OUT="$(run s2 -- tests/a.test.mdl tests/leaky.test.mdl tests/b.test.mdl --local)"; RC=$?
[ "$(wc -l < "$WORK/rec.s2.calls" | tr -d ' ')" = 2 ] && ok "2 mxcli calls" || bad "calls: $(cat "$WORK/rec.s2.calls")"
has "shared boot first, without the leaky file" "$(sed -n 1p "$WORK/rec.s2.calls")" "test tests/a.test.mdl tests/b.test.mdl --local"
has "leaky file alone, same flags" "$(sed -n 2p "$WORK/rec.s2.calls")" "test tests/leaky.test.mdl --local"
has "says why" "$OUT" "tests/leaky.test.mdl has @cleanup none: its own boot"

echo "-- speed: --per-file (and MXTK_TEST_ONE_BOOT=0) opt out: one boot per file"
OUT="$(run s3 --per-file -- tests/a.test.mdl tests/b.test.mdl tests/c.test.mdl --local)"
[ "$(wc -l < "$WORK/rec.s3.calls" | tr -d ' ')" = 3 ] && ok "--per-file → 3 calls" || bad "calls: $(cat "$WORK/rec.s3.calls")"
OUT="$(MXTK_TEST_ONE_BOOT=0 run s4 -- tests/a.test.mdl tests/b.test.mdl --local)"
[ "$(wc -l < "$WORK/rec.s4.calls" | tr -d ' ')" = 2 ] && ok "MXTK_TEST_ONE_BOOT=0 → 2 calls" || bad "calls: $(cat "$WORK/rec.s4.calls")"

echo "-- speed: a directory is expanded to its test files, in sorted order; one file or none passes through as given"
OUT="$(run s5 -- tests --local)"
has "dir → files, leaky one separate" "$(cat "$WORK/rec.s5.calls")" "test tests/a.test.mdl tests/b.test.mdl tests/c.test.mdl --local"
[ "$(wc -l < "$WORK/rec.s5.calls" | tr -d ' ')" = 2 ] && ok "dir with a leaky file → 2 boots" || bad "calls: $(cat "$WORK/rec.s5.calls")"
OUT="$(run s6 -- tests/a.test.mdl --list)"
[ "$(cat "$WORK/rec.s6.calls")" = "test tests/a.test.mdl --list -p $(sed -n 's/^args=.* -p //p' "$WORK/rec.s6")" ] && ok "one file: unchanged call" || bad "$(cat "$WORK/rec.s6.calls")"

echo "-- speed: the exit code is the worst of the boots"
OUT="$(STUB_RC=3 run s7 -- tests/a.test.mdl tests/leaky.test.mdl)"; RC=$?
[ "$RC" -eq 3 ] && ok "boots 3,3 → 3" || bad "exit $RC"

echo "-- speed: the warm copy keeps .mxcli + deployment, re-syncs the model, never carries the live run record"
rm -rf "$WORK/tmp"/Fixture-test*
run w1 -- tests/a.test.mdl >/dev/null; C="$(ls -d "$WORK/tmp"/Fixture-test-cache.* 2>/dev/null | head -1)"
[ -d "$C" ] && ok "cold run leaves the copy for next time" || bad "no cache dir"
[ -f "$C/.mxcli/test-scratch.stamp" ] && ok "stamp written (mxcli version + created)" || bad "no stamp"
mkdir -p "$C/deployment/run"; echo idx > "$C/.mxcli/unit-index"; echo built > "$C/deployment/run/out"
echo '{"pid":2}' > "$C/.mxcli/run-state.json"; echo stray > "$C/stray.txt"
echo changed > "$P/tests/a.test.mdl"; rm -f "$P/tests/c.test.mdl"
OUT="$(run w2 -- tests/a.test.mdl)"
has "second run is warm" "$OUT" "warm copy"
[ -f "$C/.mxcli/unit-index" ] && [ -f "$C/deployment/run/out" ] && ok ".mxcli index and deployment build output kept" || bad "cache contents lost"
[ ! -e "$C/.mxcli/run-state.json" ] && ok "a run record in the copy is removed" || bad "run-state.json survived"
[ ! -e "$C/stray.txt" ] && [ ! -e "$C/tests/c.test.mdl" ] && ok "model re-synced: strays and deleted files gone" || bad "copy drifted from the live model"
[ "$(cat "$C/tests/a.test.mdl")" = changed ] && ok "edited test file arrives" || bad "stale test file"
printf 'test\n' > "$P/tests/a.test.mdl"
[ "$(cat "$P/Fixture.mpr")" = model ] && ok "live .mpr still untouched" || bad "live .mpr written"
printf '%s' "$(cat "$WORK/rec.w2")" | grep -qx '.mxcli' && ok "mxcli sees the copy's own .mxcli" || bad "no .mxcli in the copy"
[ -e "$P/.mxcli/test-scratch.stamp" ] && bad "stamp written into the live project" || ok "live project gets no stamp"

echo "-- speed: dropped and rebuilt cold on --cold, a new mxcli, age"
OUT="$(run w3 --cold -- tests/a.test.mdl)"
has "--cold says so" "$OUT" "dropping the warm copy (--cold)"
[ ! -e "$C/deployment/run/out" ] && ok "--cold: build output gone" || bad "--cold kept the cache"
mkdir -p "$C/deployment/run"; echo built > "$C/deployment/run/out"
OUT="$(STUB_VER=stub-2 run w4 -- tests/a.test.mdl)"
has "new mxcli says so" "$OUT" "mxcli changed"
[ ! -e "$C/deployment/run/out" ] && ok "new mxcli: build output gone" || bad "new mxcli kept the cache"
mkdir -p "$C/deployment/run"; echo built > "$C/deployment/run/out"; sed -i.bak 's/^created=.*/created=1000/' "$C/.mxcli/test-scratch.stamp"; rm -f "$C/.mxcli/test-scratch.stamp.bak"
OUT="$(STUB_VER=stub-2 run w5 -- tests/a.test.mdl)"
has "old copy says so" "$OUT" "older than 7 days"
[ ! -e "$C/deployment/run/out" ] && ok "age: build output gone" || bad "an old cache was kept"
mkdir -p "$C/deployment/run"; echo built > "$C/deployment/run/out"; rm -f "$C/.mxcli/test-scratch.stamp"
OUT="$(STUB_VER=stub-2 run w6 -- tests/a.test.mdl)"
has "a directory this script did not make is not trusted" "$OUT" "no stamp"
OUT="$(MXTK_TEST_COLD=1 STUB_VER=stub-2 run w7 -- tests/a.test.mdl)"
has "MXTK_TEST_COLD=1 = --cold" "$OUT" "dropping the warm copy (--cold)"

echo "-- speed: --no-cache is the old throwaway copy, and leaves no warm copy behind"
rm -rf "$WORK/tmp"/Fixture-test*
OUT="$(run n1 --no-cache -- tests/a.test.mdl)"
ls "$WORK/tmp" | grep -q 'Fixture-test' && bad "a copy was left behind" || ok "copy deleted, no cache made"
OUT="$(MXTK_TEST_CACHE=0 run n2 -- tests/a.test.mdl)"
ls "$WORK/tmp" | grep -q 'Fixture-test' && bad "MXTK_TEST_CACHE=0 left a copy" || ok "MXTK_TEST_CACHE=0 = --no-cache"

echo "-- #244: an after-startup left on an mxcli test injection is refused before anything is copied"
if command -v node >/dev/null 2>&1; then
  GU="$TOOLKIT/tests/wave2/fixtures/mxtest-guard/settings-unit.mxunit"
  SETAS="$TOOLKIT/tests/wave2/fixtures/mxtest-guard/set-after-startup.js"
  UNIT="$P/mprcontents/4e/70/4e70063d-53e1-477a-ab92-6b763330c293.mxunit"; mkdir -p "$(dirname "$UNIT")"
  node "$SETAS" "$GU" "$WORK/rt.mxunit" "" && cmp -s "$GU" "$WORK/rt.mxunit" \
    && ok "[setup] re-encoding the captured unit reproduces it byte for byte" || bad "[setup] the BSON re-encoder is not faithful"
  cp "$GU" "$UNIT"
  OUT="$(run i -- tests/a.test.mdl)"; RC=$?
  [ "$RC" -eq 0 ] && ok "captured settings unit (no after-startup) → runs" || bad "clean captured unit refused (exit $RC): $(printf '%s' "$OUT" | tail -3)"
  ( cd "$P" && git init -q && git add mprcontents && git -c user.email=t@t -c user.name=t commit -qm base ) >/dev/null 2>&1
  node "$SETAS" "$GU" "$UNIT" "Orders.ASU_Startup"
  ( cd "$P" && git -c user.email=t@t -c user.name=t commit -qam own ) >/dev/null 2>&1
  OUT="$(run j -- tests/a.test.mdl)"; RC=$?
  [ "$RC" -eq 0 ] && ok "a project's own after-startup → runs" || bad "own after-startup refused (exit $RC)"
  node "$SETAS" "$GU" "$UNIT" "MxTest.RegisterEndpoint"
  rm -rf "$WORK/tmp"/Fixture-test*
  OUT="$(run k -- tests/a.test.mdl)"; RC=$?
  [ "$RC" -eq 3 ] && ok "MxTest.RegisterEndpoint → refused (exit 3)" || bad "exit $RC: $(printf '%s' "$OUT" | tail -3)"
  has "names the leftover" "$OUT" "after-startup microflow is MxTest.RegisterEndpoint"
  has "names what HEAD has" "$OUT" "HEAD: Orders.ASU_Startup"
  has "prints the git repair" "$OUT" "git checkout -- 'mprcontents/4e/70/4e70063d-53e1-477a-ab92-6b763330c293.mxunit'"
  has "prints the MDL repair with HEAD's value" "$OUT" "alter settings runtime (AfterStartupMicroflow: 'Orders.ASU_Startup');"
  [ -f "$WORK/rec.k" ] && bad "mxcli ran on the injected model" || ok "mxcli not run"
  grep -q 'Fixture-test' <<<"$(ls "$WORK/tmp")" && bad "a copy was made" || ok "nothing copied"
  node "$SETAS" "$GU" "$UNIT" "MxTest.TestRunner"
  OUT="$(run l -- tests/a.test.mdl)"; RC=$?
  [ "$RC" -eq 3 ] && ok "MxTest.TestRunner → refused (exit 3)" || bad "TestRunner exit $RC"
  cp "$GU" "$UNIT"
  echo "-- #244: another unit that merely MENTIONS the setting (a doc string) does not switch the guard off"
  D1="$P/mprcontents/00/00/00000000-doc.mxunit"; D2="$P/mprcontents/ff/ff/ffffffff-doc.mxunit"; mkdir -p "$(dirname "$D1")" "$(dirname "$D2")"
  printf 'Documentation\0Set AfterStartupMicroflow to MxTest.Setup for tests\0' | tee "$D1" > "$D2"
  node "$SETAS" "$GU" "$UNIT" "MxTest.RegisterEndpoint"
  OUT="$(run n -- tests/a.test.mdl)"; RC=$?
  [ "$RC" -eq 3 ] && ok "doc-string units beside the injected settings unit → still refused" || bad "doc-string unit hid the injection (exit $RC)"
  echo "-- #244: MXTK_SKIP_MXTEST_GUARD=1 lets a run through, out loud"
  OUT="$(MXTK_SKIP_MXTEST_GUARD=1 run o -- tests/a.test.mdl)"; RC=$?
  [ "$RC" -eq 0 ] && has "skipped, and says so" "$OUT" "MXTK_SKIP_MXTEST_GUARD=1 — NOT checking" || bad "override exit $RC"
  rm -f "$D1" "$D2"
  echo "-- #244 on a v1 model (settings inside the .mpr itself), 2 MB of model after the setting"
  # Large on purpose: the reader stops at the first match, od then dies of SIGPIPE, and under the
  # script's pipefail that once discarded the answer — the guard silently did nothing on a real .mpr.
  V="$WORK/v1"; mkdir -p "$V/bin"; cp "$P/bin/"*.sh "$V/bin/"; cp "$P/mxcli" "$V/"
  node "$SETAS" "$GU" "$WORK/inj.mxunit" "MxTest.RegisterEndpoint"
  { printf 'SQLite format 3\0'; cat "$WORK/inj.mxunit"; head -c 2000000 /dev/zero; } > "$V/Fixture.mpr"
  OUT="$( cd "$V" && REC="$WORK/rec.m" ./bin/test-scratch.sh -- x.test.mdl 2>&1 )"; RC=$?
  [ "$RC" -eq 3 ] && has "large v1 .mpr → refused, git repair degrades to a placeholder" "$OUT" "HEAD: not readable" || bad "v1 exit $RC: $(printf '%s' "$OUT" | tail -3)"
  { printf 'SQLite format 3\0'; cat "$GU"; head -c 2000000 /dev/zero; } > "$V/Fixture.mpr"
  OUT="$( cd "$V" && REC="$WORK/rec.p" ./bin/test-scratch.sh -- x.test.mdl 2>&1 )"; RC=$?
  [ "$RC" -eq 0 ] && ok "large clean v1 .mpr → runs" || bad "clean v1 exit $RC: $(printf '%s' "$OUT" | tail -3)"
else
  echo "  [skip] node missing — the injected settings units are built from the capture with node"
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
