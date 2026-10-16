#!/usr/bin/env bash
# test-progress-report-gitignore.sh: the progress report's session cache (.claude/progress-report-sessions.txt)
# holds absolute session-log paths (user name, session ids), so it is machine-local: init-project.sh writes the
# .gitignore line for a new project, bin/doctor.sh and bin/sync-project.sh add it to a project that lacks it, and
# none of them adds it twice. Usage: bash tests/wave2/test-progress-report-gitignore.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/pr-gitignore.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
export MXTK_NO_GUIDE=1 MXTK_LEAKGUARD_DENYFILE="$WORK/deny"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }
LINE='^/\.claude/progress-report-sessions\.txt$'
count() { grep -cE "$LINE" "$WORK/p/.gitignore"; }
strip() { sed -i.bak '/progress-report/d;/Machine-local progress/d' "$WORK/p/.gitignore"; rm -f "$WORK/p/.gitignore.bak"; }
mkdir "$WORK/p"; git -C "$WORK/p" init -q
bash "$ROOT/bin/init-project.sh" "$WORK/p" </dev/null >"$WORK/init.out" 2>&1
[ "$(count)" = 1 ] && ok "init: a new project ignores the session cache" || bad "init: a new project ignores the session cache"
git -C "$WORK/p" check-ignore -q .claude/progress-report-sessions.txt && ok "init: git agrees the cache is ignored" || bad "init: git agrees"
strip
bash "$ROOT/bin/doctor.sh" "$WORK/p" >"$WORK/doctor.out" 2>&1
[ "$(count)" = 1 ] && ok "doctor: adds the line to a project that lacks it" || bad "doctor: adds the line"
bash "$ROOT/bin/doctor.sh" "$WORK/p" >"$WORK/doctor2.out" 2>&1
[ "$(count)" = 1 ] && ok "doctor: a second run does not add it twice" || bad "doctor: not twice"
strip
bash "$ROOT/bin/sync-project.sh" "$WORK/p" >"$WORK/sync.out" 2>&1
[ "$(count)" = 1 ] && ok "sync-project: adds the line to a synced project" || bad "sync-project: adds the line"
bash "$ROOT/bin/sync-project.sh" "$WORK/p" >"$WORK/sync2.out" 2>&1
[ "$(count)" = 1 ] && ok "sync-project: a second run does not add it twice" || bad "sync-project: not twice"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
