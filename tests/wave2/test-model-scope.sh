#!/usr/bin/env bash
# test-model-scope.sh -- project-bin/model-scope.py (report / restore / check --staged).
#
# usage: bash tests/wave2/test-model-scope.sh [path-to-model-scope.py]
#
# Field (mendixlabs/mxcli#1596; mxcli v0.27.0, Mendix 10.24.18, MPR v2): one `alter entity ...
# rename attribute` rewrote 135 units in 20 modules that never referenced the attribute; the only
# change in each was the line breaks between bracketed conditions in XPath constraint strings.
#
#   G  the golden capture (fixtures/model-scope/golden-v0.27.0/, CAPTURE.md): a REAL mxcli v0.27.0
#      rename on a public model. Report: 1 real (the domain model), 2 noise in 2 modules [guard];
#      restore: the noise is byte-equal to before, the index matches, the real change stays.
#   A  the whitespace rule (literals, both quote kinds, escapes)
#   B  classification of the cases the capture lacks: whitespace inside a literal = real [guard],
#      XPath whitespace + another field = real [guard], key order = real, added / deleted = real,
#      a page data source's 'XPathConstraint', the module of a unit inside a folder
#   C  restore: second run writes nothing, --against REF, a model under app/, clean tree,
#      a checkout that stops part-way leaves the index matching [guard]
#   D  check --staged: exit codes, the restore command, MODEL_SCOPE_OK=1, no model yet
#
# B-D run on SYNTHETIC models (fixtures/model-scope/mkmodel.py), shaped like the capture.
# The ContentsHash check is the fixtures' own code (mkmodel.py hashes), never the subject's.
set -uo pipefail

TK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TK/project-bin/model-scope.py}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
FIX="$TK/tests/wave2/fixtures/model-scope"
. "$TK/bin/lib/portable.sh"; require_py; PYB="$PY"
WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/model-scope.XXXXXX")" && pwd -P)" || exit 2
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; return 0; }
echo "== subject: $SUBJECT"
# The subject imports mxpatch.py and mxunit_bson.py from its own directory.
[ -f "$(dirname "$SUBJECT")/mxpatch.py" ] || { echo "no mxpatch.py beside $SUBJECT"; exit 2; }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
gitq() { git -c user.email=t@t -c user.name=t "$@"; }
mkm() { "$PYB" -I "$FIX/mkmodel.py" "$@"; }
ms()  { ( cd "$R" && "$PYB" -I "$SUBJECT" "$@" ); }
mk()  { R="$WORK/$1"; shift; mkm init "$R" "$@"; }
chg() { ( cd "$R" && git status --porcelain -uall | grep -c 'mxunit' ); }
uf()  { "$PYB" -I -c "
import sys,uuid
ns=uuid.UUID('6f1c1c1e-0000-4000-8000-000000000001'); u=str(uuid.uuid5(ns,sys.argv[1]))
print('mprcontents/%s/%s/%s.mxunit'%(u[:2],u[2:4],u))" "$1"; }
sql2mpr() { "$PYB" -I -c "import sqlite3,sys;db=sqlite3.connect(sys.argv[2]);db.executescript(open(sys.argv[1]).read());db.commit()" "$1" "$2"; }

echo "== G: golden capture, real mxcli v0.27.0 rename"
GD="$FIX/golden-v0.27.0"; R="$WORK/g"; mkdir -p "$R"
cp -R "$GD/before/mprcontents" "$R/"; sql2mpr "$GD/before/TestApp.mpr.sql" "$R/TestApp.mpr"
( cd "$R" && git init -q . && gitq add -A && gitq commit -qm before )
cp -R "$GD/after/mprcontents" "$R/"; rm "$R/TestApp.mpr"; sql2mpr "$GD/after/TestApp.mpr.sql" "$R/TestApp.mpr"
MF_OWN=mprcontents/c2/e9/c2e900a8-6b87-4916-ae7b-49fed7f0a939.mxunit     # MyFirstModule.ACT_Item_Fetch
MF_OTHER=mprcontents/ce/32/ce321a44-1103-4ee9-875b-6d521bdd3178.mxunit   # Other.ACT_Thing_Fetch
DM=mprcontents/84/77/84776610-13b2-48cb-a265-d5e984d63129.mxunit         # MyFirstModule domain model
out="$(ms report -v)"
echo "$out" | grep -q 'vs HEAD: 3 unit file(s) changed, 1 real, 2 noise' && ok "captured rename: 1 real, 2 noise [guard]" || bad "golden counts" "$out"
echo "$out" | grep -q 'real changes by module: MyFirstModule 1' && ok "the real change is the renamed entity's module" || bad "golden module line" "$out"
echo "$out" | grep -qE "noise +M Other +$MF_OTHER" && ok "the unrelated module's microflow is noise" || bad "golden Other" "$out"
echo "$out" | grep -qE "real +M MyFirstModule +$DM .*Attributes/3/Name" && ok "the domain model's real change is the attribute Name" || bad "golden DM" "$out"
out="$(ms restore)"; rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q 'restored 2 noise unit(s) from HEAD' && ok "restore exits 0 and says what it restored" || bad "golden restore rc=$rc" "$out"
( cd "$R" && git diff --quiet HEAD -- "$MF_OWN" "$MF_OTHER" ) && ok "both noise units byte-equal to before" || bad "golden noise not restored"
( cd "$R" && git diff --quiet HEAD -- "$DM" ) && bad "golden: the real change was reverted" || ok "the real change is still there"
"$PYB" -I "$(dirname "$SUBJECT")/mxpatch.py" verify "$R/TestApp.mpr" 2>&1 | grep -q MISMATCH \
  && bad "golden: index out of step after restore" "$("$PYB" -I "$(dirname "$SUBJECT")/mxpatch.py" verify "$R/TestApp.mpr" 2>&1 | grep MISMATCH)" \
  || ok "no ContentsHash MISMATCH after restore (the capture's real fix hashes: golden-v0.27.0/fix-hashes-after-restore-v0.27.0.out)"

echo "== A: whitespace outside literals only"
cat > "$WORK/strip-check.py" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ms", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
f = m.strip_ws_outside_literals
cases = [
  ("[a = 'x y']\n[b = 1]\n",         "[a='x y'][b=1]"),
  ('[a = "x  y"] [b]',               '[a="x  y"][b]'),
  ("[n = 'it\\'s a b'] [c]",         "[n='it\\'s a b'][c]"),
  ("[a = '\n']",                     "[a='\n']"),
  ("[a = 'open  [b]",                "[a='open  [b]"),
  ("[a = \"it's\"] [b]",             "[a=\"it's\"][b]"),
]
bad = [(i, f(i), w) for i, w in cases if f(i) != w]
print("OK" if not bad else bad)
PY
out="$("$PYB" -I "$WORK/strip-check.py" "$SUBJECT")"
[ "$out" = OK ] && ok "strip: literals kept, escapes and nested quotes honoured" || bad "strip" "$out"

echo "== B: classification"
mk b2; mkm edit "$R" MfA1 literal
ms report | grep -q '1 real, 0 noise' && ok "whitespace inside a quoted literal is real [guard]" || bad "literal not real" "$(ms report)"
mk b3; mkm edit "$R" MfB2 wsfield
out="$(ms report -v)"
echo "$out" | grep -q '1 real, 0 noise' && echo "$out" | grep -q 'field changed: /Caption' && ok "XPath whitespace + another field = real [guard]" || bad "mixed not real" "$out"
mk b4; mkm edit "$R" MfB1 field
ms report | grep -q '1 real, 0 noise' && ok "another field alone = real" || bad "field not real"
mk b5; mkm edit "$R" MfB1 reorder
ms report | grep -q '1 real, 0 noise' && ok "key order change = real" || bad "reorder not real"
mk b6
mkm delete "$R" MfA2; mkm add "$R" MfNew ModuleB; mkm edit "$R" MfB1 ws; mkm edit "$R" MfB2 field; mkm edit "$R" PgA ws; mkm edit "$R" MfA1 ws
out="$(ms report -v)"
echo "$out" | grep -q '6 unit file(s) changed, 3 real, 3 noise' && ok "counts: 3 real (added, deleted, field), 3 noise" || bad "counts" "$out"
echo "$out" | grep -q 'real changes by module: ModuleB 2, ModuleA 1' && ok "real changes per module (added in B, deleted from A)" || bad "per-module line" "$out"
echo "$out" | grep -qE 'real +D ModuleA ' && ok "a deleted unit's module comes from the ref's .mpr" || bad "deleted module" "$out"
echo "$out" | grep -qE "noise +M ModuleA +$(uf PgA)" && ok "a page data source's 'XPathConstraint' counts" || bad "page key" "$out"
echo "$out" | grep -qE "noise +M ModuleA +$(uf MfA1)" && ok "a unit inside a folder resolves to its module" || bad "folder walk" "$out"
echo "$out" | grep -q 'noise: 3 unit(s) in 2 module(s)' && ok "noise line counts modules" || bad "noise line" "$out"

echo "== C: restore"
out="$(ms restore)"; rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q 'restored 3 noise unit(s)' && ok "restore exits 0" || bad "restore rc=$rc" "$out"
for n in MfB1 PgA MfA1; do
  ( cd "$R" && git diff --quiet HEAD -- "$(uf $n)" ) || { bad "$n not byte-equal to HEAD"; break; }
done && ok "noise files are byte-equal to HEAD"
[ "$(mkm hashes "$R")" = clean ] && ok "ContentsHash index matches the files" || bad "index not clean: $(mkm hashes "$R")"
( cd "$R" && git diff --quiet HEAD -- "$(uf MfB2)" ) && bad "the real change was reverted" || ok "the real change is still there"
( cd "$R" && test -e "$(uf MfNew)" ) && ok "the added unit is untouched" || bad "the added unit vanished"
st1="$(cd "$R" && git status --porcelain -uall; shasum "$R/App.mpr")"
out="$(ms restore)"; rc=$?
st2="$(cd "$R" && git status --porcelain -uall; shasum "$R/App.mpr")"
[ "$st1" = "$st2" ] && [ "$rc" -eq 0 ] && ok "second run writes nothing" || bad "second run changed things" "$out"

mk c2
mkm edit "$R" MfB1 field; ( cd "$R" && gitq add -A && gitq commit -qm second )
mkm edit "$R" MfB2 ws
out="$(ms report --against HEAD~1)"
echo "$out" | grep -q 'vs HEAD~1: 2 unit file(s) changed, 1 real, 1 noise' && ok "--against REF compares with that commit" || bad "--against" "$out"
ms restore --against HEAD~1 >/dev/null
( cd "$R" && git diff --quiet HEAD~1 -- "$(uf MfB2)" ) && ok "--against: noise restored from REF" || bad "--against restore"

mk c3 --sub app
mkm edit "$R" MfB1 ws; mkm edit "$R" MfB2 field
out="$(ms restore)"; rc=$?
echo "$out" | grep -q 'restored 1 noise unit(s)' && [ "$(chg)" -eq 1 ] && [ "$(mkm hashes "$R")" = clean ] \
  && ok "model under app/ (run from the project root)" || bad "two-tree rc=$rc" "$out"

mk c4
out="$(ms restore)"; rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q '0 unit file(s) changed' && ok "nothing changed: exit 0" || bad "clean tree" "$out"
out="$(ms report --against nosuchref 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "unknown ref: exit 2" || bad "bad ref rc=$rc" "$out"
# A checkout that stops part-way (one unit's directory not writable): the unit that did come
# back gets its ContentsHash row, the other stays as the write left it, and the index matches.
mk c9
mkm edit "$R" MfB1 ws; mkm edit "$R" PgA ws
LOCK="$R/$(dirname "$(uf PgA)")"; chmod 0555 "$LOCK"
out="$(ms restore 2>&1)"; rc=$?
chmod 0755 "$LOCK"
[ "$rc" -eq 2 ] && echo "$out" | grep -q 'stopped part-way' && [ "$(chg)" -eq 1 ] && [ "$(mkm hashes "$R")" = clean ] \
  && ok "partial restore: exit 2, restored unit re-indexed, index matches [guard]" || bad "partial restore rc=$rc chg=$(chg) $(mkm hashes "$R")" "$out"

echo "== D: check --staged"
mk d1
mkm edit "$R" MfB1 ws; ( cd "$R" && git add -A )
out="$(ms check --staged 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && ok "staged noise: exit 1 [guard]" || bad "staged noise rc=$rc" "$out"
echo "$out" | grep -q ' -I bin/model-scope.py restore' && echo "$out" | grep -q 'ModuleB' && ok "names the module and the restore command" || bad "message" "$out"
out="$(MODEL_SCOPE_OK=1 ms check --staged 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q 'MODEL_SCOPE_OK=1: committing' && ok "MODEL_SCOPE_OK=1 lets it through, out loud" || bad "override rc=$rc" "$out"
ms restore >/dev/null
ms check --staged >/dev/null 2>&1 && ok "after restore the staged index is clean (exit 0)" || bad "still refused after restore"
mk d2
mkm edit "$R" MfB2 field; ( cd "$R" && git add -A )
ms check --staged >/dev/null 2>&1 && ok "staged real change: exit 0" || bad "real change refused"
mk d3
mkm edit "$R" MfB1 ws    # not staged
ms check --staged >/dev/null 2>&1 && ok "noise only in the working tree: exit 0 (the index is what counts)" || bad "unstaged noise refused"
mkdir -p "$WORK/d4" && R="$WORK/d4" && ( cd "$R" && git init -q . && echo hi > f && git add f )
ms check --staged >/dev/null 2>&1 && ok "no model in the repo yet: exit 0" || bad "pre-model repo refused"
mk d5
mkm edit "$R" MfB1 ws; mkm edit "$R" MfA1 ws; mkm edit "$R" PgA ws; ( cd "$R" && git add -A )
out="$(ms check --staged 2>&1)"
echo "$out" | grep -q 'refused: 3 staged unit file' && ok "counts every staged noise unit" || bad "count" "$out"

echo ""
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
