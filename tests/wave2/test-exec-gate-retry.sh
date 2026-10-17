#!/usr/bin/env bash
# test-exec-gate-retry.sh - exec.sh's gate when mxbuild collides with a live watcher, or fails
# for a reason that is not the model.
#
# usage: bash tests/wave2/test-exec-gate-retry.sh [path-to-exec.sh]
#
# Field (a migration project, 12 modules, 2026-10-16/17): the gate's mxbuild and a live
# `mxcli run --local --watch` on the same project both write deployment/. 17 of 27 failed gates
# were "gate could not run" (mxbuild exit 1, no CE code, no errors file); 0 of 22 in watcher-free
# copies. Now: the project's watcher is paused (SIGSTOP/SIGCONT) while the gate runs, and an exit
# 1 or 3 with no CE code and no errors file is retried once.
#
#   A  infra exit once, then clean: retried, write kept, "retry after infra exit" in output + row
#   B  infra exit twice: the #424 rollback still applies to the final failure (model identical)
#   C  a real CE error list (exit 1): NOT retried, normal gate-failed rollback [guard]
#   D  a live watcher of this project is stopped while mxbuild runs and running again after;
#      a sibling `<proj>-copy` watcher and a nested .claude/worktrees/x watcher are NOT stopped
#   E  exec.sh SIGKILLed mid-gate leaves the watcher stopped; the next exec.sh resumes it
#
# Synthetic only: throwaway git repo, stub mxcli, stub mxbuild, stub java. Nothing real runs.
set -uo pipefail

TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/project-bin/exec.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/exec-retry.XXXXXX")" && pwd -P)" || exit 2
WPID=""; XPIDS=""
trap 'for _w in $WPID $XPIDS; do pkill -KILL -P "$_w" 2>/dev/null; kill -KILL "$_w" 2>/dev/null; done; rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL - $1${2:+: $2}"; }
echo "== subject: $SUBJECT"

P="$WORK/proj"
mkdir -p "$P/bin" "$P/mprcontents" "$P/mdlsource" "$WORK/jdk/bin"
printf 'not a real model\n' > "$P/Fixture.mpr"
printf 'bson\n' > "$P/mprcontents/a.mxunit"
printf 'CREATE MODULE "Nope";\n' > "$P/mdlsource/test.mdl"
cp "$TOOLKIT/project-bin/_common.sh" "$TOOLKIT/project-bin/restore-mpr.sh" "$P/bin/"
cp "$SUBJECT" "$P/bin/exec.sh"
cat > "$P/bin/snapshot-mpr.sh" <<'SNAP'
#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."
D=".mpr-snapshots/$(date +%Y%m%d-%H%M%S)-$$-$RANDOM"
mkdir -p "$D"; cp Fixture.mpr "$D/"; cp -r mprcontents "$D/"
echo "Snapshot saved: $D"
SNAP
# The write: `mxcli exec` appends to the model, as a real script would.
cat > "$P/mxcli" <<'MXCLI'
#!/usr/bin/env bash
D="$(cd "$(dirname "$0")" && pwd)"
case "${1:-}" in
  check) exit 0 ;;
  run) sleep 120; exit 0 ;;
  exec) echo "written by the script" >> "$D/Fixture.mpr"; echo "x" >> "$D/mprcontents/a.mxunit"; echo "fake mxcli exec"; exit 0 ;;
esac
exit 0
MXCLI
chmod +x "$P/bin/"*.sh "$P/mxcli"
# mxbuild: MXB_MODES per call number, comma list: ok | infra (exit 1, no CE code, no errors file) | err (a CE0001 error list)
# MXB_WATCH_PID: record that process's state (ps stat) at the start of every call
# MXB_OTHER_PIDS: the same for more pids, as `<pid> <stat>` lines in MXB_OTHERS
# hang (mode): record the pid in MXB_HANGPID and sleep, so the test can SIGKILL exec.sh mid-gate
cat > "$WORK/mxbuild" <<'MXB'
#!/usr/bin/env bash
n=$(( $(cat "$MXB_N" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$MXB_N"
mode="$(printf '%s\n' "$MXB_MODES" | tr ',' '\n' | sed -n "${n}p")"; mode="${mode:-ok}"
[ -n "${MXB_WATCH_PID:-}" ] && ps -o stat= -p "$MXB_WATCH_PID" >> "$MXB_STATES"
for q in ${MXB_OTHER_PIDS:-}; do echo "$q $(ps -o stat= -p "$q")" >> "$MXB_OTHERS"; done
err=""; for a in "$@"; do case "$a" in --write-errors=*) err="${a#--write-errors=}" ;; esac; done
case "$mode" in
  ok)    [ -n "$err" ] && printf '{"problems":[]}' > "$err"; exit 0 ;;
  hang)  echo $$ > "$MXB_HANGPID"; exec sleep 60 ;;
  infra) echo "Directory not empty : deployment/web" >&2; exit 1 ;;
  err)   [ -n "$err" ] && printf '{"problems":[{"severity":"Error","code":"CE0001","message":"boom","element":{"document":"M.X"}}]}' > "$err"; exit 1 ;;
esac
MXB
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/jdk/bin/java"
chmod +x "$WORK/mxbuild" "$WORK/jdk/bin/java"
( cd "$P" && git init -q . && printf '.mpr-snapshots/\ndocs/\n.claude/\n' > .gitignore && git add -A \
  && git -c user.email=t@t -c user.name=t commit -qm fixture ) >/dev/null 2>&1

LOG="$P/docs/BUILD-LOG.md"
sum() { cat "$P/Fixture.mpr" "$P/mprcontents/a.mxunit" | cksum; }
BEFORE="$(sum)"   # the committed model; run() resets to it
# run <label> <modes> - resets the model, runs the default path, prints the exit code
run() {
  [ -n "${NORESET:-}" ] || ( cd "$P" && git checkout -q -- Fixture.mpr mprcontents && rm -rf .mpr-snapshots docs \
    && { find .claude -mindepth 1 -maxdepth 1 ! -name worktrees -exec rm -rf {} + 2>/dev/null; true; } ) >/dev/null 2>&1
  rm -f "$WORK/n"; mkdir -p "$WORK/tmp"
  ( cd "$P" && TMPDIR="$WORK/tmp" SP_RESTART=0 MXTK_NO_INSTALL=1 MXB_N="$WORK/n" MXB_MODES="$2" \
      MXBUILD_PATH="$WORK/mxbuild" JAVA_HOME="$WORK/jdk" ./bin/exec.sh mdlsource/test.mdl ) >"$WORK/out.$1" 2>&1
  echo $?
}
lastrow() { tail -1 "$LOG" 2>/dev/null; }
kept() { grep -q 'written by the script' "$P/Fixture.mpr"; }

echo "== A: infra exit once, then clean: retried, kept =="
RC=$(run A ok,infra,ok)
[ "$RC" -eq 0 ] && kept && ok "exit 0, write kept" || bad "A rc=$RC" "$(tail -8 "$WORK/out.A")"
[ "$(cat "$WORK/n")" -eq 3 ] && ok "mxbuild ran 3 times (baseline, gate, retry)" || bad "A: mxbuild calls" "$(cat "$WORK/n")"
grep -q 'retry after infra exit' "$WORK/out.A" && ok "says retry after infra exit" || bad "A: no retry message" "$(tail -10 "$WORK/out.A")"
lastrow | grep -q 'retry after infra exit' && lastrow | grep -q 'applied' && ok "applied row carries the retry note" || bad "A: row" "$(lastrow)"

echo "== B: infra exit twice: the #424 rollback applies to the final failure =="
RC=$(run B ok,infra,infra)
[ "$(cat "$WORK/n")" -eq 3 ] && ok "retried exactly once" || bad "B: mxbuild calls" "$(cat "$WORK/n")"
kept && bad "B: the write was KEPT after the final failure" || ok "write rolled back"
[ "$(sum)" = "$BEFORE" ] && ok "model identical to before the exec" || bad "B: model differs from before"
lastrow | grep -q 'gate could not run.*script rolled back' && lastrow | grep -q 'retry after infra exit' \
  && ok "row says rolled back, with the retry note" || bad "B: row" "$(lastrow)"

echo "== C: a real CE error list: no retry [guard] =="
RC=$(run C ok,err)
[ "$(cat "$WORK/n")" -eq 3 ] && ok "no retry: baseline, gate, whose-error rebuild only" || bad "C: mxbuild calls" "$(cat "$WORK/n")"
grep -q 'retry after infra exit' "$WORK/out.C" && bad "C: retried a model error" || ok "no retry message"
lastrow | grep -q 'gate failed' && ok "gate failed row" || bad "C: row" "$(lastrow)"

echo "== D: a live watcher of this project is paused during mxbuild =="
( cd "$P" && exec ./mxcli run --local --watch -p Fixture.mpr ) >/dev/null 2>&1 &
WPID=$!
# a sibling copy (absolute -p) and a nested lane worktree (relative -p, matched by cwd): not this project's
mkdir -p "$WORK/proj-copy" "$P/.claude/worktrees/x"
( cd "$WORK/proj-copy" && exec "$P/mxcli" run --local --watch -p "$WORK/proj-copy/Fixture.mpr" ) >/dev/null 2>&1 &
SPID=$!
( cd "$P/.claude/worktrees/x" && exec "$P/mxcli" run --local --watch -p Fixture.mpr ) >/dev/null 2>&1 &
NPID=$!
XPIDS="$SPID $NPID"
sleep 1
MXB_STATES="$WORK/states"; : > "$MXB_STATES"
MXB_OTHERS="$WORK/others"; : > "$MXB_OTHERS"
export MXB_WATCH_PID="$WPID" MXB_STATES MXB_OTHER_PIDS="$SPID $NPID" MXB_OTHERS
RC=$(run D ok,ok)
unset MXB_WATCH_PID MXB_OTHER_PIDS
[ "$RC" -eq 0 ] && kept && ok "exit 0, write kept" || bad "D rc=$RC" "$(tail -8 "$WORK/out.D")"
[ "$(wc -l < "$MXB_STATES" | tr -d ' ')" -eq 2 ] && ! grep -qv 'T' "$MXB_STATES" && ok "watcher stopped (T) during both mxbuild runs" || bad "D: states" "$(cat "$MXB_STATES")"
case "$(ps -o stat= -p "$WPID" 2>/dev/null)" in T*) bad "D: watcher still stopped after exec" ;; "") bad "D: watcher is gone" ;; *) ok "watcher running again after exec" ;; esac
[ "$(wc -l < "$MXB_OTHERS" | tr -d ' ')" -eq 4 ] && ! grep -q ' T' "$MXB_OTHERS" \
  && ok "sibling <proj>-copy and nested .claude/worktrees/x watchers never stopped" || bad "D: other projects' watchers" "$(cat "$MXB_OTHERS")"
[ ! -e "$P/.mpr-snapshots/.watcher-paused" ] && ok "pause record cleared after a normal exit" || bad "D: .watcher-paused left behind"

echo "== E: exec.sh SIGKILLed mid-gate: the next exec.sh resumes the watcher =="
export MXB_HANGPID="$WORK/hangpid"; rm -f "$MXB_HANGPID"
( cd "$P" && git checkout -q -- Fixture.mpr mprcontents && rm -rf .mpr-snapshots docs ) >/dev/null 2>&1
rm -f "$WORK/n"
( cd "$P" && exec env TMPDIR="$WORK/tmp" SP_RESTART=0 MXTK_NO_INSTALL=1 MXB_N="$WORK/n" MXB_MODES="hang" \
    MXBUILD_PATH="$WORK/mxbuild" JAVA_HOME="$WORK/jdk" ./bin/exec.sh mdlsource/test.mdl ) >"$WORK/out.E1" 2>&1 &
KPID=$!
i=0; while [ ! -s "$MXB_HANGPID" ] && [ "$i" -lt 100 ]; do sleep 0.2; i=$((i+1)); done
case "$(ps -o stat= -p "$WPID" 2>/dev/null)" in T*) ok "watcher stopped while the gate runs" ;; *) bad "E: watcher not stopped mid-gate" ;; esac
grep -q "^$KPID $WPID" "$P/.mpr-snapshots/.watcher-paused" 2>/dev/null && ok "pause record names exec pid and watcher pid" || bad "E: record" "$(cat "$P/.mpr-snapshots/.watcher-paused" 2>/dev/null)"
kill -KILL "$KPID" 2>/dev/null; wait "$KPID" 2>/dev/null
kill -KILL "$(cat "$MXB_HANGPID")" 2>/dev/null
case "$(ps -o stat= -p "$WPID" 2>/dev/null)" in T*) ok "after SIGKILL the watcher is left stopped (no trap ran)" ;; *) bad "E: watcher not left stopped" ;; esac
( cd "$P" && ./bin/restore-mpr.sh ) >"$WORK/out.E2" 2>&1 && ok "restore-mpr.sh (no argument) ignores the dot file" || bad "E: restore-mpr.sh" "$(tail -3 "$WORK/out.E2")"
export MXB_HANGPID=/dev/null
RC=$(NORESET=1 run E ok,ok)
[ "$RC" -eq 0 ] && ok "next exec.sh ran clean" || bad "E rc=$RC" "$(tail -8 "$WORK/out.E")"
grep -q 'resumed 1 watcher' "$WORK/out.E" && ok "prints one line about the resumed leftover" || bad "E: no resume line" "$(head -12 "$WORK/out.E")"
case "$(ps -o stat= -p "$WPID" 2>/dev/null)" in T*) bad "E: watcher still stopped" ;; "") bad "E: watcher is gone" ;; *) ok "watcher running again" ;; esac
[ ! -e "$P/.mpr-snapshots/.watcher-paused" ] && ok "record cleared" || bad "E: record left behind"

echo ""
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
