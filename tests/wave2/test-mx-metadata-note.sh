#!/usr/bin/env bash
# Fixture for the Studio Pro revision note (project-bin/mx-metadata-note.py) and the post-commit /
# post-rewrite hooks + notes push refspec project-bin/install-project-hooks.sh installs.
# 2026-10-12: every CLI commit on a field project showed "Model changes 0" in Studio Pro History,
# because the hand-written note carried "ModelChanges":[].
#
# Golden input is captured, not written: fixtures/mx-metadata-note/ holds four real .mxunit files
# (MyFirstModule's module, MyFirstLogic microflow, domain model, module security -- Mendix template
# content, no app data), their verbatim Unit-table rows and the real .mpr schema, all from a
# Mendix 11.15.0 model. The test assembles them into throwaway git repos (single-tree AND two-tree)
# and asserts the note Studio Pro would read. The field run against real Studio Pro is cited in the
# script header, not repeated here.
#
# usage: bash tests/wave2/test-mx-metadata-note.sh      (no argument; subjects are the project-bin files)
# Every repo here sets HEAD to main explicitly, so the result does not depend on init.defaultBranch;
# run it under both:  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=init.defaultBranch GIT_CONFIG_VALUE_0=master
set -uo pipefail
TK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FX="$TK/tests/wave2/fixtures/mx-metadata-note"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mx-metadata-note.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }
. "$TK/bin/lib/portable.sh"; require_py

MOD=16747dc6-b6b7-42ae-aabf-255dca2aeeaf; MF=4a8475b3-14cb-4100-8963-58f2fd3a0be8
DM=84776610-13b2-48cb-a265-d5e984d63129; MS=3f64baa2-b85c-4999-9a3c-3cc38382eb54
PL=0f0f0f0f-1111-4222-8333-444444444444   # a project-level unit: real ModuleSecurity bytes, placed under the root
export MODEL_UNVERIFIED_OK=1               # the pre-commit gate is test-model-stamp.sh's subject, not this one's
export GIT_TERMINAL_PROMPT=0
# Hermetic git: no global/system config (a push.default or push.negotiate there would change what
# "the same push as a no-hooks clone" means). GIT_CONFIG_COUNT from the caller still applies.
: > "$WORK/gitconfig"; export GIT_CONFIG_GLOBAL="$WORK/gitconfig" GIT_CONFIG_NOSYSTEM=1
unset MXTK_TS_REMOTES
TSURL=https://git.api.mendix.com/00000000-0000-0000-0000-000000000000.git
# A Team Server remote that is really a local bare repo: url.<bare>.insteadOf keeps the configured
# URL on git.api.mendix.com (what the installer detects) while every fetch/push goes local.
bare()   { git init -q --bare "$1" && git -C "$1" symbolic-ref HEAD refs/heads/main; }
tsremote() { git config "url.$1.insteadOf" "$TSURL"; git remote add teamserver "$TSURL"; }
nmd()    { "$PY" ./bin/mx-metadata-note.py "$@"; }   # resolve_py's interpreter, never the shebang

# mkmodel <model-dir> <unit>... : write <model-dir>/App.mpr (real schema + captured rows) and the units
mkmodel() {
  local d="$1"; shift
  "$PY" - "$FX" "$d" "$@" <<'PY'
import os, sqlite3, sys, shutil
fx, d, units = sys.argv[1], sys.argv[2], sys.argv[3:]
rows = {}
for line in open(f"{fx}/unit-rows.tsv"):
    if line.startswith("#"): continue
    u, c, n = line.rstrip("\n").split("\t"); rows[u] = (c, n)
def blob(g):
    b = bytes.fromhex(g.replace("-", "")); return b[3::-1] + b[5:3:-1] + b[7:5:-1] + b[8:]
root = "4d827743a25b514b800e658754fc369b"
pl = "0f0f0f0f-1111-4222-8333-444444444444"
mpr = f"{d}/App.mpr"
if os.path.exists(mpr): os.unlink(mpr)
db = sqlite3.connect(mpr); db.executescript(open(f"{fx}/schema.sql").read())
db.execute("insert into _MetaData values (2,'11.15.0','11.15.0','')")
cdir = f"{d}/mprcontents"; shutil.rmtree(cdir, ignore_errors=True)
for u in units:
    src = "3f64baa2-b85c-4999-9a3c-3cc38382eb54" if u == pl else u
    key = blob(u).hex()
    c, n = (root, "ProjectSecurity") if u == pl else rows[key]
    db.execute("insert into Unit (UnitID, ContainerID, ContainmentName) values (?,?,?)", (blob(u), bytes.fromhex(c), n))
    os.makedirs(f"{cdir}/{u[:2]}/{u[2:4]}", exist_ok=True)
    shutil.copy(f"{fx}/{src}.mxunit", f"{cdir}/{u[:2]}/{u[2:4]}/{u}.mxunit")
db.commit(); db.close()
PY
}
note()   { git notes --ref=mx_metadata show "${1:-HEAD}" 2>/dev/null; }
field()  { "$PY" -c "import json,sys;n=json.load(sys.stdin);print(json.dumps(sorted((c['Status'],c['UnitType'],c['UnitName'],c['Module']) for c in n['ModelChanges'])))"; }
newrepo() {
  local r="$1"; mkdir -p "$r/bin"; cd "$r" && git init -q . && git symbolic-ref HEAD refs/heads/main && git config user.email t@t && git config user.name t
  cp "$TK/project-bin/_common.sh" "$TK/project-bin/model-stamp.sh" "$TK/project-bin/install-project-hooks.sh" "$TK/project-bin/mx-metadata-note.py" bin/
  echo readme > README.md; git add -A >/dev/null; git commit -qm init
}

echo "T0 install never adds push config; it removes only the exact pair an earlier revision wrote"
TS="$WORK/ts.git"; bare "$TS"
P="$WORK/single"; newrepo "$P"; tsremote "$TS"
PROJECT_ROOT="$P" ./bin/install-project-hooks.sh --check >/dev/null 2>&1 && bad "--check passed with no hooks" || ok "--check fails before install"
PROJECT_ROOT="$P" ./bin/install-project-hooks.sh >/dev/null 2>&1
[ -x .git/hooks/post-commit ] && [ -x .git/hooks/post-rewrite ] && ok "post-commit + post-rewrite installed" || bad "hooks missing"
[ -z "$(git config --get-all remote.teamserver.push)" ] && ok "no remote.teamserver.push written" || bad "push config written" "$(git config --get-all remote.teamserver.push)"
PROJECT_ROOT="$P" ./bin/install-project-hooks.sh --check >/dev/null 2>&1 && ok "--check passes without any push refspec" || bad "--check" "$(PROJECT_ROOT="$P" ./bin/install-project-hooks.sh --check 2>&1)"
git config --add remote.teamserver.push HEAD; git config --add remote.teamserver.push refs/notes/mx_metadata:refs/notes/mx_metadata
out="$(PROJECT_ROOT="$P" ./bin/install-project-hooks.sh --check 2>&1)"; rc=$?
[ $rc -ne 0 ] && printf '%s\n' "$out" | grep -q 'earlier toolkit revision' && ok "--check flags the earlier revision's HEAD + notes pair" || bad "--check silent on leftover pair (rc $rc)" "$out"
PROJECT_ROOT="$P" ./bin/install-project-hooks.sh >/dev/null 2>&1
[ -z "$(git config --get-all remote.teamserver.push)" ] && ok "install removes that exact pair" || bad "leftover pair kept" "$(git config --get-all remote.teamserver.push)"
git config --add remote.teamserver.push refs/heads/main:refs/heads/main
PROJECT_ROOT="$P" ./bin/install-project-hooks.sh >/dev/null 2>&1
[ "$(git config --get-all remote.teamserver.push)" = "refs/heads/main:refs/heads/main" ] && ok "a user's own push refspec is untouched" || bad "user refspec changed" "$(git config --get-all remote.teamserver.push)"
git config --add remote.teamserver.push refs/notes/mx_metadata:refs/notes/mx_metadata
out="$(PROJECT_ROOT="$P" ./bin/install-project-hooks.sh 2>&1)"
[ "$(git config --get-all remote.teamserver.push | wc -l | tr -d ' ')" = 2 ] && echo "$out" | grep -q 'left alone' \
  && ok "notes refspec beside a user's entries: not provably ours, left alone with a note" || bad "foreign notes refspec" "$(git config --get-all remote.teamserver.push)"
git config --unset-all remote.teamserver.push

echo "T1 a model commit gets a note with real names, types and module"
mkmodel "$P" $MOD $MF $DM $MS
git add -A >/dev/null; git commit -qm "add MyFirstModule" 2>/dev/null
got="$(note | field)"
exp='[["Added", "DomainModels$DomainModel", "", "MyFirstModule"], ["Added", "Microflows$Microflow", "MyFirstLogic", "MyFirstModule"], ["Added", "Projects$ModuleImpl", "MyFirstModule", "MyFirstModule"], ["Added", "Security$ModuleSecurity", "", "MyFirstModule"]]'
[ "$got" = "$exp" ] && ok "4 Added entries, Studio Pro's shape" || bad "ModelChanges" "got $got"
note | grep -q '"ModelerVersion":"11.15.0"' && ok "ModelerVersion read from the commit's .mpr" || bad "version" "$(note)"

echo "T2 modified and deleted units; deleted ones are named from the parent commit"
"$PY" - "$P/mprcontents/${MF:0:2}/${MF:2:2}/$MF.mxunit" <<'PY'
import sys; p=sys.argv[1]; b=open(p,'rb').read(); assert b'client' in b; open(p,'wb').write(b.replace(b'client', b'CLIENT', 1))
PY
git add -A >/dev/null; git commit -qm "edit microflow" 2>/dev/null
[ "$(note | field)" = '[["Modified", "Microflows$Microflow", "MyFirstLogic", "MyFirstModule"]]' ] && ok "Modified microflow" || bad "modified" "$(note)"
mkmodel "$P" $MOD $DM $MS; git add -A >/dev/null; git commit -qm "drop microflow" 2>/dev/null
[ "$(note | field)" = '[["Deleted", "Microflows$Microflow", "MyFirstLogic", "MyFirstModule"]]' ] && ok "Deleted microflow, still named" || bad "deleted" "$(note)"

echo "T3 project-level unit: empty UnitName and Module, as Studio Pro writes them"
mkmodel "$P" $MOD $DM $MS $PL; git add -A >/dev/null; git commit -qm "project unit" 2>/dev/null
[ "$(note | field)" = '[["Added", "Security$ModuleSecurity", "", ""]]' ] && ok "project-level entry" || bad "project-level" "$(note)"

echo "T4 a commit that touches no model file gets no note"
echo more >> README.md; git commit -qam docs 2>/dev/null
note >/dev/null && bad "docs commit got a note" "$(note)" || ok "no note on a docs commit"

echo "T5 amend: post-rewrite notes the new commit; an existing note keeps its other keys"
git notes --ref=mx_metadata add -f -m '{"BranchName":"x","ModelerVersion":"9.9.9","ModelChanges":[],"RelatedStories":[],"Extra":1}' HEAD~1 2>/dev/null
nmd write HEAD~1 >/dev/null
note HEAD~1 | grep -q '"ModelerVersion":"9.9.9".*"Extra":1' && note HEAD~1 | grep -q 0f0f0f0f && ok "existing keys kept, ModelChanges filled" || bad "keys" "$(note HEAD~1)"
mkmodel "$P" $MOD $DM $MS; git add -A >/dev/null; git commit -q --amend -m "docs + drop project unit" 2>/dev/null
[ "$(note | field)" = '[["Deleted", "Security$ModuleSecurity", "", ""]]' ] && ok "amended commit noted" || bad "amend" "$(note)"

echo "T6 git push is untouched: same outcome as a clone with no hooks; notes never ride along"
[ -z "$(git config --get-all remote.teamserver.push)" ] && ok "no push config after model commits" || bad "push config appeared" "$(git config --get-all remote.teamserver.push)"
git push -q teamserver main >/dev/null 2>&1 && [ "$(git -C "$TS" rev-parse refs/heads/main)" = "$(git rev-parse HEAD)" ] && ok "git push teamserver main pushes the branch" || bad "branch push" "$(git push teamserver main 2>&1)"
git -C "$TS" rev-parse -q --verify refs/notes/mx_metadata >/dev/null && bad "git push carried the notes" || ok "git push did not carry the notes (sync publishes them)"
git push -q teamserver main:refs/heads/remotefeat >/dev/null 2>&1
CTL="$WORK/control"; git clone -q "$TS" "$CTL"; git -C "$CTL" config user.email t@t; git -C "$CTL" config user.name t
pushcase() {   # pushcase <repo> <remote> : the differently-named-upstream push, then a detached-HEAD push
  ( cd "$1" && git fetch -q "$2" && git checkout -q -b feature "$2/remotefeat" && git commit -q --allow-empty -m f 2>/dev/null
    git push -q "$2" >/dev/null 2>&1; a=$?
    git checkout -q --detach && git push -q "$2" >/dev/null 2>&1; b=$?
    git checkout -q main; echo "$a $b" )
}
got="$(pushcase "$P" teamserver)"; ctl="$(pushcase "$CTL" origin)"
[ "$got" = "$ctl" ] && ok "same push exit codes as a no-hooks clone ($got)" || bad "push differs from a no-hooks clone" "hooks: $got  control: $ctl"
case "$got" in 0\ *) bad "upstream named remotefeat: push should be refused (push.default=simple)" ;; *) ok "branch tracking a differently named upstream is refused, as under simple" ;; esac
git -C "$TS" rev-parse -q --verify refs/heads/feature >/dev/null && bad "a new 'feature' branch appeared on the remote" || ok "no stray same-named branch created on the remote"

echo "T6a sync publishes the notes; a remote with no notes ref yet is not an error"
out="$(nmd sync teamserver 2>&1)"; rc=$?
[ $rc -eq 0 ] && [ "$(git -C "$TS" rev-parse refs/notes/mx_metadata 2>/dev/null)" = "$(git rev-parse refs/notes/mx_metadata)" ] \
  && ok "sync to a remote with no notes ref: exit 0, notes published" || bad "sync to empty remote (rc $rc)" "$out"
nmd sync teamserver >/dev/null 2>&1 && ok "second sync is a clean no-op" || bad "second sync failed" "$(nmd sync teamserver 2>&1)"
printf '#!/bin/sh\n[ -f "$GIT_DIR/rejected-once" ] && exit 0\ntouch "$GIT_DIR/rejected-once"; echo "remote moved" >&2; exit 1\n' > "$TS/hooks/pre-receive"; chmod +x "$TS/hooks/pre-receive"
git notes --ref=mx_metadata add -f -m '{"ModelerVersion":"11.15.0","ModelChanges":[],"From":"retry"}' HEAD 2>/dev/null
out="$(nmd sync teamserver 2>&1)"; rc=$?
[ $rc -eq 0 ] && echo "$out" | grep -q 'once more' && [ "$(git -C "$TS" rev-parse refs/notes/mx_metadata)" = "$(git rev-parse refs/notes/mx_metadata)" ] \
  && ok "a rejected notes push is retried once after re-sync, then lands" || bad "retry (rc $rc)" "$out"
printf '#!/bin/sh\necho "remote moved" >&2; exit 1\n' > "$TS/hooks/pre-receive"
git notes --ref=mx_metadata add -f -m '{"ModelerVersion":"11.15.0","ModelChanges":[],"From":"retry2"}' HEAD 2>/dev/null
out="$(nmd sync teamserver 2>&1)"; rc=$?
[ $rc -ne 0 ] && echo "$out" | grep -q 'rejected twice' && ok "rejected again: exit $rc with a clear report" || bad "double rejection (rc $rc)" "$out"
rm -f "$TS/hooks/pre-receive"; nmd sync teamserver >/dev/null 2>&1

echo "T6b a fresh clone with no local notes: install fetches the remote's notes (non-forced), no push config"
F="$WORK/fresh"; git clone -q "$TS" "$F" && cd "$F" && git config user.email t@t && git config user.name t
git remote remove origin; tsremote "$TS"; git fetch -q teamserver; git branch -q -u teamserver/main
mkdir -p bin; cp "$TK/project-bin/_common.sh" "$TK/project-bin/model-stamp.sh" "$TK/project-bin/install-project-hooks.sh" "$TK/project-bin/mx-metadata-note.py" bin/
git rev-parse -q --verify refs/notes/mx_metadata >/dev/null && bad "precondition: clone already has notes" || true
PROJECT_ROOT="$F" ./bin/install-project-hooks.sh >/dev/null 2>&1
[ "$(git rev-parse -q --verify refs/notes/mx_metadata)" = "$(git -C "$TS" rev-parse refs/notes/mx_metadata)" ] && ok "install fetched the remote's notes" || bad "notes not fetched"
[ -z "$(git config --get-all remote.teamserver.push)" ] && ok "and wrote no push config" || bad "push config" "$(git config --get-all remote.teamserver.push)"
cd "$P"

echo "T7 backfill: notes a history that had none; a second run changes nothing"
git update-ref -d refs/notes/mx_metadata
out="$(nmd backfill)"
echo "$out" | tail -1 | grep -q "updated 5 notes" && ok "backfill wrote 5 notes (5 model commits)" || bad "backfill" "$out"
nmd backfill | tail -1 | grep -q "updated 0 notes" && ok "second backfill is a no-op" || bad "not idempotent"

echo "T7b backfill never overwrites a note that already lists changes (Studio Pro's); --force does"
git notes --ref=mx_metadata add -f -m '{"ModelerVersion":"11.15.0","ModelChanges":[{"Status":"Modified","UnitName":"FromStudioPro"}],"From":"sp"}' HEAD~2 2>/dev/null
nmd backfill | tail -1 | grep -q "updated 0 notes" && note HEAD~2 | grep -q FromStudioPro && ok "Studio Pro's non-empty note left alone" || bad "SP note overwritten" "$(note HEAD~2)"
nmd write HEAD~2 >/dev/null; note HEAD~2 | grep -q FromStudioPro && ok "write leaves it alone too" || bad "write overwrote" "$(note HEAD~2)"
nmd backfill --force | tail -1 | grep -q "updated 1 notes" && ! note HEAD~2 | grep -q FromStudioPro && note HEAD~2 | grep -q '"From":"sp"' \
  && ok "--force recomputes it, other keys kept" || bad "--force" "$(note HEAD~2)"

echo "T8 two-tree layout (app/App.mpr + root symlink)"
T="$WORK/twotree"; newrepo "$T"; PROJECT_ROOT="$T" ./bin/install-project-hooks.sh >/dev/null 2>&1
mkdir -p app; mkmodel "$T/app" $MOD $MF; ln -s app/App.mpr App.mpr
git add -A >/dev/null; git commit -qm "two-tree model" 2>/dev/null
[ "$(note | field)" = '[["Added", "Microflows$Microflow", "MyFirstLogic", "MyFirstModule"], ["Added", "Projects$ModuleImpl", "MyFirstModule", "MyFirstModule"]]' ] && ok "two-tree note" || bad "two-tree" "$(note)"

echo "T9 sync: another clone noted other commits; merge, then a fast-forward push"
B="$WORK/remote.git"; bare "$B"
cd "$P" && git remote add origin "$B" && git push -q origin HEAD:refs/heads/main refs/notes/mx_metadata:refs/notes/mx_metadata
C="$WORK/clone"; git clone -q "$B" "$C" && cd "$C" && git config user.email t@t && git config user.name t
git fetch -q origin refs/notes/mx_metadata:refs/notes/mx_metadata
git notes --ref=mx_metadata add -f -m '{"ModelerVersion":"11.15.0","ModelChanges":[{"Status":"Modified"}],"From":"them"}' HEAD~3 2>/dev/null   # changed only there
git notes --ref=mx_metadata add -f -m '{"ModelerVersion":"11.15.0","ModelChanges":[],"From":"them"}' HEAD~2 2>/dev/null                        # changed on BOTH sides
git notes --ref=mx_metadata add -f -m '{"ModelerVersion":"11.15.0","ModelChanges":[{"Status":"Added"}],"From":"them-sp"}' HEAD~1 2>/dev/null   # BOTH sides, theirs lists changes
git push -q origin refs/notes/mx_metadata:refs/notes/mx_metadata 2>/dev/null
cd "$P" && git notes --ref=mx_metadata add -f -m '{"ModelerVersion":"11.15.0","ModelChanges":[],"From":"us"}' HEAD~2 2>/dev/null
git notes --ref=mx_metadata add -f -m '{"ModelerVersion":"11.15.0","ModelChanges":[{"Status":"Modified"}],"From":"us"}' HEAD~1 2>/dev/null
mkmodel "$P" $MOD $MF $DM $MS && git add -A >/dev/null && git commit -qm "re-add" 2>/dev/null
if git push -q origin refs/notes/mx_metadata:refs/notes/mx_metadata 2>/dev/null; then bad "diverged notes pushed without a merge"
else ok "plain notes push rejected when the remote moved"; fi
nmd sync origin >/dev/null 2>&1 && ok "sync merged and pushed" || bad "sync failed" "$(nmd sync origin 2>&1)"
[ "$(git ls-remote origin refs/notes/mx_metadata | cut -f1)" = "$(git rev-parse refs/notes/mx_metadata)" ] && ok "remote notes == local" || bad "remote differs"
git notes --ref=mx_metadata show HEAD~4 2>/dev/null | grep -q '"From":"them"' && ok "a note changed only on the remote keeps the remote's change" || bad "remote-only change lost" "$(git notes --ref=mx_metadata show HEAD~4)"
git notes --ref=mx_metadata show HEAD~3 2>/dev/null | grep -q '"From":"us"' && ok "a note changed on both sides, theirs empty: ours wins" || bad "ours lost the conflict" "$(git notes --ref=mx_metadata show HEAD~3)"
git notes --ref=mx_metadata show HEAD~2 2>/dev/null | grep -q '"From":"them-sp"' && ok "a note changed on both sides, theirs lists changes: theirs kept, never pushed over" || bad "colleague's non-empty note overwritten" "$(git notes --ref=mx_metadata show HEAD~2)"

echo; echo "mx-metadata-note: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
