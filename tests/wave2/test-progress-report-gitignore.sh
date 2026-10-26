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
# --- git worktree: .git is a FILE there, so a `-d .git` test never added the line -------------------------
git -C "$WORK/p" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
git -C "$WORK/p" worktree add -q "$WORK/wt" -b wt-branch >/dev/null 2>&1
[ -f "$WORK/wt/.git" ] && ok "worktree: .git is a file, as in a checked-out worktree" || bad "worktree: .git is a file"
WGI="$WORK/wt/.gitignore"
wcount() { grep -cE "$LINE" "$WGI" 2>/dev/null || true; }
wstrip() { [ -f "$WGI" ] && { sed -i.bak '/progress-report/d;/Machine-local progress/d' "$WGI"; rm -f "$WGI.bak"; }; return 0; }
mkdir -p "$WORK/wt/.claude"
bash "$ROOT/bin/doctor.sh" "$WORK/wt" >"$WORK/wdoctor.out" 2>&1
[ "$(wcount)" = 1 ] && ok "worktree doctor: adds the line" || bad "worktree doctor: adds the line"
bash "$ROOT/bin/doctor.sh" "$WORK/wt" >"$WORK/wdoctor2.out" 2>&1
[ "$(wcount)" = 1 ] && ok "worktree doctor: a second run does not add it twice" || bad "worktree doctor: not twice"
wstrip
touch "$WORK/wt/PROJECT.md"   # sync-project only manages a wired project; init output is untracked, so the worktree has none
bash "$ROOT/bin/sync-project.sh" "$WORK/wt" >"$WORK/wsync.out" 2>&1
[ "$(wcount)" = 1 ] && ok "worktree sync-project: adds the line" || bad "worktree sync-project: adds the line"
bash "$ROOT/bin/sync-project.sh" "$WORK/wt" >"$WORK/wsync2.out" 2>&1
[ "$(wcount)" = 1 ] && ok "worktree sync-project: a second run does not add it twice" || bad "worktree sync-project: not twice"

# --- tracked file: the line is not appended again, and the user is told to untrack it ----------------------
git -C "$WORK/p" worktree remove --force "$WORK/wt" >/dev/null 2>&1
strip
mkdir -p "$WORK/p/.claude"; echo cache > "$WORK/p/.claude/progress-report-sessions.txt"
git -C "$WORK/p" add -f .claude/progress-report-sessions.txt
HINT='git rm --cached .claude/progress-report-sessions.txt'
bash "$ROOT/bin/doctor.sh" "$WORK/p" >"$WORK/tdoctor.out" 2>&1
grep -qF "$HINT" "$WORK/tdoctor.out" && ok "tracked file, doctor: prints the git rm --cached hint" || bad "tracked file, doctor: hint"
bash "$ROOT/bin/doctor.sh" "$WORK/p" >"$WORK/tdoctor2.out" 2>&1
bash "$ROOT/bin/doctor.sh" "$WORK/p" >"$WORK/tdoctor3.out" 2>&1
[ "$(count)" = 1 ] && ok "tracked file, doctor: repeated runs append the line once" || bad "tracked file, doctor: once ($(count))"
strip
bash "$ROOT/bin/sync-project.sh" "$WORK/p" >"$WORK/tsync.out" 2>&1
bash "$ROOT/bin/sync-project.sh" "$WORK/p" >"$WORK/tsync2.out" 2>&1
bash "$ROOT/bin/sync-project.sh" "$WORK/p" >"$WORK/tsync3.out" 2>&1
[ "$(count)" = 1 ] && ok "tracked file, sync-project: repeated runs append the line once" || bad "tracked file, sync-project: once ($(count))"
grep -qF "$HINT" "$WORK/tsync3.out" && ok "tracked file, sync-project: prints the git rm --cached hint" || bad "tracked file, sync-project: hint"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
