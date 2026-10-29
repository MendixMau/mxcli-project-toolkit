#!/usr/bin/env bash
# Fixture for the opt-in check-only gate (`Gate mode: check`, #584/#585).
#
# usage: test-exec-gate-kind.sh /path/to/exec.sh
#
# The mx check outputs under fixtures/mx-check/ are verbatim captures (mx 11.13.0, a real
# purchase-requests model, clean and with one attribute dropped → 6 × CE1613). The fake `mx`
# below only replays them; the parsing under test is _common.sh's.
#   K1  mx check JSON → mxbuild problems[] shape (6 Error problems, CE1613, module/document/element)
#   K2  mxtk_mx_check_error_count on the CE1613 capture: 6, file in mxbuild shape
#   K3  on the clean capture: 0
#   K4  mx writes no JSON: "?" with the reason, never 0
#   K5  mxtk_gate_mxbuild with MXTK_GATE_KIND=check runs mx, not mxbuild
#   K6  gate_kind_decide: default full; check mode → full until a full build is recorded, then
#       check; full again after MXTK_CHECK_MAX (10) checks, on a Java change, on a real drop with
#       Java actions, on --patch
#   K7  model-stamp kind: a check stamp passes `check` but not `check --full`; no kind line = full
#   K8  pre-push hook: full build only when the stamp says mx check; refuses on errors
set -uo pipefail
EXEC="${1:?usage: test-exec-gate-kind.sh /path/to/exec.sh}"
TK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FX="$TK/tests/wave2/fixtures/mx-check"
. "$TK/bin/lib/portable.sh"
require_py
WORK="$(mktemp -d "${TMPDIR:-/tmp}/gate-kind.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }

# A fake toolchain dir: mxbuild (records that it ran) and mx (replays $MX_REPLAY, exits $MX_RC).
T="$WORK/modeler"; mkdir -p "$T"
cat > "$T/mxbuild" <<EOF
#!/bin/sh
touch "$WORK/mxbuild-ran"; exit 0
EOF
cat > "$T/mx" <<'EOF'
#!/bin/sh
# mx check <mpr> -j <out>
out=""; while [ $# -gt 0 ]; do [ "$1" = "-j" ] && { shift; out="$1"; }; shift; done
[ -n "${MX_REPLAY:-}" ] && [ -n "$out" ] && cp "$MX_REPLAY" "$out"
echo "Checking app for errors..."; exit "${MX_RC:-0}"
EOF
chmod +x "$T/mxbuild" "$T/mx"
P="$WORK/proj"; mkdir -p "$P/.claude/loop"; printf 'mpr' > "$P/App.mpr"
export MXBUILD_PATH="$T/mxbuild"

cm() { ( . "$TK/project-bin/_common.sh"; "$@" ) 2>&1; }

echo "K1 conversion"
cm mxtk_mx_check_to_mxbuild "$FX/mx-check-11.13.0-CE1613.json" "$WORK/conv.json" >/dev/null
out=$("$PY" -c "import json;d=json.load(open('$WORK/conv.json'));p=d['problems'];l=p[0]['locations'][0]
print(len(p),{x['severity'] for x in p},{x['errorCode'] for x in p},l['module'],sorted(l))")
[ "$out" = "6 {'Error'} {'CE1613'} Approval ['document', 'element', 'module']" ] \
  && ok "K1: 6 Error problems, CE1613, locations module/document/element" || bad "K1" "$out"

echo "K2 error count, CE1613 capture"
out=$(MX_REPLAY="$FX/mx-check-11.13.0-CE1613.json" MX_RC=1 cm mxtk_mx_check_error_count "$P/App.mpr" 30 "$WORK/ef2.json")
n=$("$PY" -c "import json;print(len(json.load(open('$WORK/ef2.json'))['problems']))" 2>&1)
[ "$out" = "6" ] && [ "$n" = "6" ] && ok "K2: 6 errors, errors file in mxbuild shape" || bad "K2" "count=$out file=$n"

echo "K3 error count, clean capture"
out=$(MX_REPLAY="$FX/mx-check-11.13.0-clean.json" MX_RC=0 cm mxtk_mx_check_error_count "$P/App.mpr" 30 "$WORK/ef3.json")
[ "$out" = "0" ] && ok "K3: clean → 0" || bad "K3" "$out"

echo "K4 no JSON written"
out2=$(MX_REPLAY="" MX_RC=3 cm mxtk_mx_check_error_count "$P/App.mpr" 30)
[ "$out2" = "?" ] && ok "K4: no JSON → ?, not 0" || bad "K4" "$out2"
( . "$TK/project-bin/_common.sh"; MX_REPLAY="" MX_RC=3 mxtk_mx_check_error_count "$P/App.mpr" 30 >/dev/null
  case "$MXTK_MXBUILD_WHY" in *"no readable JSON (exit 3)"*) exit 0 ;; *) echo "$MXTK_MXBUILD_WHY"; exit 1 ;; esac ) \
  && ok "K4: the reason names the exit code" || bad "K4 reason"

echo "K5 gate dispatch"
rm -f "$WORK/mxbuild-ran"
( . "$TK/project-bin/_common.sh"; MXTK_GATE_KIND=check MX_REPLAY="$FX/mx-check-11.13.0-CE1613.json" MX_RC=1 \
    mxtk_gate_mxbuild "$P/App.mpr" 30 "$WORK/ef5.json" )
[ ! -e "$WORK/mxbuild-ran" ] && [ -s "$WORK/ef5.json" ] && ok "K5: check kind ran mx, not mxbuild" || bad "K5"

echo "K6 gate_kind_decide"
fn="$WORK/gk.sh"
sed -n '/^_GK_STATE=/,/^}/p' "$EXEC" > "$fn"
grep -q '^gate_kind_decide() {' "$fn" || bad "K6: gate_kind_decide not found in $EXEC"
( cd "$P" && git init -q && git config user.email tester && git config user.name t \
  && mkdir -p javasource/Mod/actions && echo 'class A {}' > javasource/Mod/actions/A.java \
  && git add -A && git commit -qm init ) >/dev/null 2>&1
printf 'create entity Mod.E (Name: String);\n' > "$WORK/add.mdl"
printf 'alter entity Mod.E drop attribute Name;\n' > "$WORK/drop.mdl"
decide() {  # $1 script, $2 patch mode → "<kind>|<why>"
  ( cd "$P" && . "$TK/project-bin/_common.sh" && PROJECT_ROOT="$P" SCRIPT="$1" PATCH_MODE="${2:-0}" MXBUILD="$T/mxbuild" \
    && . "$fn" && gate_kind_decide && echo "$GATE_KIND|$GATE_KIND_WHY" ) 2>&1
}
rm -f "$P/.claude/loop/gate-kind.state"
out=$(decide "$WORK/add.mdl"); case "$out" in "full|no full build recorded yet") ok "K6a: no Gate mode line → check mode (first exec builds full)" ;; *) bad "K6a" "$out" ;; esac
printf '# P\n\nGate mode: full\n' > "$P/PROJECT.md"
out=$(decide "$WORK/add.mdl"); [ "$out" = "full|" ] && ok "K6a2: Gate mode: full → full build, silent" || bad "K6a2" "$out"
printf '# P\n\nGate mode: check\n' > "$P/PROJECT.md"
out=$(decide "$WORK/add.mdl"); case "$out" in "full|no full build recorded yet") ok "K6b: check mode, no state → full" ;; *) bad "K6b" "$out" ;; esac
JFP=$( cd "$P" && . "$TK/project-bin/_common.sh" && PROJECT_ROOT="$P" SCRIPT=/dev/null PATCH_MODE=0 MXBUILD="$T/mxbuild" && . "$fn" && gate_kind_decide && _gk_java_fp )
printf 'checks 1\njava %s\n' "$JFP" > "$P/.claude/loop/gate-kind.state"
out=$(decide "$WORK/add.mdl"); case "$out" in check\|*) ok "K6c: state recorded → check ($out)" ;; *) bad "K6c" "$out" ;; esac
out=$(decide "$WORK/drop.mdl"); case "$out" in "full|the project has Java actions"*) ok "K6d: drop with Java actions → full" ;; *) bad "K6d" "$out" ;; esac
printf 'drop microflow if exists Mod.ACT_X;\ncreate microflow Mod.ACT_X () begin end;\n' > "$WORK/recreate.mdl"
out=$(decide "$WORK/recreate.mdl"); case "$out" in check\|*) ok "K6k: drop … if exists (re-create idiom) stays check" ;; *) bad "K6k" "$out" ;; esac
out=$(decide "$WORK/add.mdl" 1); case "$out" in "full|--patch"*) ok "K6e: --patch → full" ;; *) bad "K6e" "$out" ;; esac
printf 'checks 4\njava %s\n' "$JFP" > "$P/.claude/loop/gate-kind.state"
out=$(decide "$WORK/add.mdl"); case "$out" in check\|*) ok "K6f: 4 checks in a row → still check (no every-5th rule)" ;; *) bad "K6f" "$out" ;; esac
printf 'checks 10\njava %s\n' "$JFP" > "$P/.claude/loop/gate-kind.state"
out=$(decide "$WORK/add.mdl"); case "$out" in "full|backstop: 10"*) ok "K6f2: 10 check-only passes in a row → full (backstop)" ;; *) bad "K6f2" "$out" ;; esac
printf 'checks 1\njava %s\n' "$JFP" > "$P/.claude/loop/gate-kind.state"
echo 'class A { int x; }' > "$P/javasource/Mod/actions/A.java"
out=$(decide "$WORK/add.mdl"); case "$out" in "full|Java/JavaScript"*) ok "K6g: Java edited since the last full build → full" ;; *) bad "K6g" "$out" ;; esac
( cd "$P" && git checkout -q -- javasource )
mkdir -p "$P/javasource/Mod/proxies"; echo 'class E {}' > "$P/javasource/Mod/proxies/E.java"
out=$(decide "$WORK/add.mdl"); case "$out" in check\|*) ok "K6j: a regenerated proxy is not a Java change" ;; *) bad "K6j" "$out" ;; esac
rm -rf "$P/javasource/Mod/proxies"
out=$(MXTK_GATE_MODE=full decide "$WORK/add.mdl"); [ "$out" = "full|" ] && ok "K6h: MXTK_GATE_MODE=full overrides PROJECT.md" || bad "K6h" "$out"
mv "$T/mx" "$T/mx.off"
out=$(decide "$WORK/add.mdl"); case "$out" in "full|no mx tool"*) ok "K6i: no mx beside mxbuild → full" ;; *) bad "K6i" "$out" ;; esac
mv "$T/mx.off" "$T/mx"

echo "K7 stamp kind"
S="$WORK/stamp"; mkdir -p "$S/bin" "$S/.claude"; cp "$TK/project-bin/model-stamp.sh" "$TK/project-bin/_common.sh" "$S/bin/"
( cd "$S" && git init -q && git config user.email tester && git config user.name t && printf 'm' > App.mpr \
  && mkdir mprcontents && echo u > mprcontents/u && git add -A && git commit -qm i ) >/dev/null 2>&1
st() { ( cd "$S" && PROJECT_ROOT="$S" "$@" ) >/dev/null 2>&1; }
st env MXTK_STAMP_KIND=check MXTK_STAMP_ERRORS=0 bash bin/model-stamp.sh write pass "exec.sh x (mx check)"
st bash bin/model-stamp.sh check -q && ok "K7a: a check stamp passes the plain check (commits allowed)" || bad "K7a"
st bash bin/model-stamp.sh check -q --full && bad "K7b: check stamp passed --full" || ok "K7b: a check stamp fails --full"
st env MXTK_STAMP_ERRORS=0 bash bin/model-stamp.sh write pass "verify-model.sh"
st bash bin/model-stamp.sh check -q --full && ok "K7c: a full stamp passes --full" || bad "K7c"
sed -i.bak '/^kind: /d' "$S/.claude/.model-verified" 2>/dev/null; rm -f "$S/.claude/.model-verified.bak"
st bash bin/model-stamp.sh check -q --full && ok "K7d: a stamp with no kind line (older) counts as full" || bad "K7d"

echo "K8 pre-push hook"
cp "$TK/project-bin/install-project-hooks.sh" "$S/bin/"
printf '#!/usr/bin/env bash\necho ran > .claude/full-ran; exit "${FAKE_VM_RC:-0}"\n' > "$S/bin/verify-model.sh"; chmod +x "$S/bin/"*.sh
st bash bin/install-project-hooks.sh
PPH="$S/.git/hooks/pre-push"
[ -x "$PPH" ] && ok "K8a: pre-push hook installed" || bad "K8a"
pp() { ( cd "$S" && echo "refs/heads/m 0 refs/heads/m 0" | "$@" "$PPH" origin x ) >/dev/null 2>&1; }
rm -f "$S/.claude/full-ran"; pp env; rc=$?
[ "$rc" = 0 ] && [ ! -e "$S/.claude/full-ran" ] && ok "K8b: no gate-kind state → no-op" || bad "K8b" "rc=$rc"
mkdir -p "$S/.claude/loop"; echo "checks 1" > "$S/.claude/loop/gate-kind.state"
st env MXTK_STAMP_KIND=check MXTK_STAMP_ERRORS=0 bash bin/model-stamp.sh write pass "exec.sh x (mx check)"
rm -f "$S/.claude/full-ran"; pp env; rc=$?
[ "$rc" = 0 ] && [ -e "$S/.claude/full-ran" ] && ok "K8c: check-only stamp → full build runs, push goes on" || bad "K8c" "rc=$rc"
rm -f "$S/.claude/full-ran"; pp env FAKE_VM_RC=1; rc=$?
[ "$rc" = 1 ] && ok "K8d: full build fails → push refused" || bad "K8d" "rc=$rc"
pp env FAKE_VM_RC=1 MODEL_UNVERIFIED_OK=1; [ $? = 0 ] && ok "K8e: MODEL_UNVERIFIED_OK=1 pushes anyway" || bad "K8e"
st env MXTK_STAMP_ERRORS=0 bash bin/model-stamp.sh write pass "verify-model.sh"
rm -f "$S/.claude/full-ran"; pp env FAKE_VM_RC=1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$S/.claude/full-ran" ] && ok "K8f: full stamp → no build" || bad "K8f" "rc=$rc"

echo
echo "gate-kind: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
