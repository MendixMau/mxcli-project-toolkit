#!/usr/bin/env bash
# Fixture for exec.sh's per-step seconds and its --subjects advisory mode (2026-10-16).
#
# usage: bash tests/wave2/test-exec-step-times.sh [/path/to/exec.sh]
#
# WHY. A BUILD-LOG row carried only the run total, so nobody could say where an exec's time
# went (a five-app lab project: 28-41 s per exec, split unknown). exec.sh now marks each step
# and prints "steps: guards Ns check Ns snapshot Ns baseline Ns exec Ns gate Ns lint Ns" in
# the summary and in the BUILD-LOG detail. --subjects lists the elements a script writes, one
# per line, for bin/affected-tests.sh.
#
# Golden input is captured, never written: --subjects reads the toolkit's own shipped MDL and
# fixtures/affected-tests/shop.mdl (exec'd to build that fixture's model). The run case reuses
# test-exec-hash-verify.sh's stub project; its mxcli replays the verbatim v0.26.0
# `mxcli fix hashes` / `fix --help` captures (fixtures/mxpatch/, fixtures/property-sets/).
#
# Positive control: against master's exec.sh 5 pass, 5 fail. The --subjects listings and the
# steps line and cell fail; the guards (exit codes, writes nothing, elapsed) pass.
set -uo pipefail

TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
EXEC_SH="${1:-$TOOLKIT/project-bin/exec.sh}"
case "$EXEC_SH" in /*) ;; *) EXEC_SH="$PWD/$EXEC_SH" ;; esac
WORK="$(mktemp -d "${TMPDIR:-/tmp}/exec-st.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
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

echo "== a run prints and logs the step seconds =="
FX="$TOOLKIT/tests/wave2/fixtures/mxpatch"; PSFX="$TOOLKIT/tests/wave2/fixtures/property-sets"
P="$WORK/proj"; mkdir -p "$P/bin" "$P/mprcontents/84/77" "$WORK/jdk/bin"
printf 'not a real model\n' > "$P/Fixture.mpr"
printf 'bson\n' > "$P/mprcontents/84/77/84776610-13b2-48cb-a265-d5e984d63129.mxunit"
cp "$TOOLKIT/project-bin/_common.sh" "$TOOLKIT/project-bin/restore-mpr.sh" "$P/bin/"
cp "$EXEC_SH" "$P/bin/exec.sh"; chmod +x "$P/bin/"*.sh
cat > "$P/bin/snapshot-mpr.sh" <<'SNAP'
#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."
D=".mpr-snapshots/$(date +%Y%m%d-%H%M%S)-$$-$RANDOM"
mkdir -p "$D"; cp Fixture.mpr "$D/Fixture.mpr"; cp -r mprcontents "$D/mprcontents"
echo "Snapshot saved: $D"
SNAP
chmod +x "$P/bin/snapshot-mpr.sh"
printf '#!/usr/bin/env bash\necho "written by the patch" >> "$1"\n' > "$P/patch.sh"
cat > "$P/mxcli" <<'MXCLI'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "fix --help") cat "$PSFX/fix-help-v0.26.0.txt"; exit 0 ;;
  "fix hashes") cat "$FX/verify-clean-v0.26.0.out"; cat "$FX/verify-clean-v0.26.0.err" >&2; exit "$(cat "$FX/verify-clean-v0.26.0.exit")" ;;
esac
exit 0
MXCLI
cat > "$WORK/mxbuild" <<'MXB'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in --write-errors=*) printf '{"problems":[]}' > "${a#--write-errors=}" ;; esac; done
exit 0
MXB
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/jdk/bin/java"
chmod +x "$P/mxcli" "$WORK/mxbuild" "$WORK/jdk/bin/java"
( cd "$P" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm fixture ) >/dev/null 2>&1
export FX PSFX
mkdir -p "$WORK/tmp"
( cd "$P" && TMPDIR="$WORK/tmp" SKIP_BASELINE=1 SP_RESTART=0 MXTK_NO_INSTALL=1 \
    MXBUILD_PATH="$WORK/mxbuild" JAVA_HOME="$WORK/jdk" ./bin/exec.sh --patch patch.sh ) > "$WORK/out" 2>&1; RC=$?
[ "$RC" -eq 0 ] && ok "run exit 0" || bad "run rc=$RC" "$(tail -20 "$WORK/out")"
STEPS="$(grep '^  steps: ' "$WORK/out")"
printf '%s\n' "$STEPS" | grep -qE '^  steps: guards [0-9]+s check [0-9]+s snapshot [0-9]+s baseline [0-9]+s exec [0-9]+s gate [0-9]+s lint [0-9]+s' \
  && ok "summary: steps line in pipeline order" || bad "summary steps" "$(grep -n 'elapsed\|steps' "$WORK/out")"
grep -q '^  elapsed: ' "$WORK/out" && ok "elapsed total still printed" || bad "no elapsed line"
ROW="$(tail -1 "$P/docs/BUILD-LOG.md" 2>/dev/null)"
printf '%s\n' "$ROW" | grep -qE '✅ applied .* · steps: guards [0-9]+s check [0-9]+s .*gate [0-9]+s lint [0-9]+s' \
  && ok "BUILD-LOG detail carries the steps cell" || bad "BUILD-LOG steps" "$ROW"

echo; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
