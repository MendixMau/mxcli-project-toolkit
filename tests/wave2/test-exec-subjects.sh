#!/usr/bin/env bash
# Fixture for exec.sh's --subjects advisory mode (2026-10-16).
#
# usage: bash tests/wave2/test-exec-subjects.sh [/path/to/exec.sh]
#
# --subjects lists the elements a script writes, one "<kind>\t<Module.Name>\tline N" row each,
# for project-bin/affected-tests.sh. It writes nothing and needs no .mpr.
#
# Golden input is captured, never written: it reads the toolkit's own shipped MDL and
# fixtures/affected-tests/shop.mdl (the MDL that was exec'd to build that fixture's model).
#
# Positive control: against master's exec.sh the listings fail (it has no --subjects and treats
# the flag as a script name); the guards that nothing is written pass.
set -uo pipefail

TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
EXEC_SH="${1:-$TOOLKIT/project-bin/exec.sh}"
case "$EXEC_SH" in /*) ;; *) EXEC_SH="$PWD/$EXEC_SH" ;; esac
WORK="$(mktemp -d "${TMPDIR:-/tmp}/exec-subj.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; return 0; }
echo "== subject: $EXEC_SH"

echo "== --subjects: real MDL =="
mkdir -p "$WORK/empty"
subj() { (cd "$WORK/empty" && bash "$EXEC_SH" --subjects "$1" 2>&1); }
SHOP="$(subj "$TOOLKIT/tests/wave2/fixtures/affected-tests/shop.mdl")"
EXP="module	Shop	line 2
entity	Shop.Order	line 3
microflow	Shop.SUB_Order_Total	line 7
microflow	Shop.VAL_Order	line 11
microflow	Shop.ACT_Order_Submit	line 16
page	Shop.Order_Edit	line 24
microflow	Shop.ACT_Order_New	line 33
page	Shop.Order_Overview	line 38"
[ "$SHOP" = "$EXP" ] && ok "shop.mdl: module, entity, 4 microflows, 2 pages, each with its line" || bad "shop.mdl" "$SHOP"
case "$SHOP" in *SUB_Order_Total*SUB_Order_Total*) bad "a CALL MICROFLOW inside a body was listed as a subject" ;; *) ok "calls inside bodies are not subjects" ;; esac
G="$(subj "$TOOLKIT/examples/stylegallery/mdlsource/gallery/90-gallery-home.mdl")"
printf '%s\n' "$G" | grep -q '^page	StyleGallery.Gallery_Home	' && printf '%s\n' "$G" | grep -q '^access	StyleGallery.Gallery_Home	' \
  && ok "CREATE PAGE + GRANT VIEW ON PAGE: page and access (gallery 90-gallery-home)" || bad "gallery" "$G"
A="$(subj "$TOOLKIT/tests/wave2/fixtures/page-fidelity-mocks/bind-contract-alter.mdl")"
printf '%s\n' "$A" | grep -q '^page	Demo.Catalog	line 2$' && ok "ALTER PAGE (bind-contract-alter)" || bad "alter" "$A"
[ -z "$(ls -A "$WORK/empty")" ] && ok "--subjects wrote nothing and needed no .mpr" || bad "wrote into cwd"
(cd "$WORK/empty" && bash "$EXEC_SH" --subjects "$WORK/no-such.mdl" >/dev/null 2>&1); rc=$?
[ "$rc" = 2 ] && ok "missing script exits 2" || bad "missing script exited $rc"

echo; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
