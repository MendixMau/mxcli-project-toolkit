#!/usr/bin/env bash
# Fixture for exec.sh's per-step seconds (2026-10-16).
#
# usage: bash tests/wave2/test-exec-step-times.sh [/path/to/exec.sh]
#
# WHY. A BUILD-LOG row carried only the run total, so nobody could say where an exec's time
# went (a five-app lab project: 28-41 s per exec, split unknown). exec.sh now marks each step
# and prints "steps: guards Ns check Ns snapshot Ns baseline Ns exec Ns gate Ns lint Ns" in
# the summary and in the BUILD-LOG detail. The gate mark is taken right after the mxbuild run,
# so a run whose gate FAILS (and is rolled back) logs its gate seconds as well: those are the
# costliest runs, about 20% of execs in the lab, and the first version lost exactly them.
#
# The run case reuses test-exec-hash-verify.sh's stub project; its mxcli replays the verbatim
# v0.26.0 `mxcli fix hashes` / `fix --help` captures (fixtures/mxpatch/, fixtures/property-sets/).
# The mxbuild stub reports one Error problem when the model file contains BREAK.
#
# Positive control: against master's exec.sh the steps line and both BUILD-LOG cells fail; the
# exit-code and elapsed guards pass.
set -uo pipefail

TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
EXEC_SH="${1:-$TOOLKIT/project-bin/exec.sh}"
case "$EXEC_SH" in /*) ;; *) EXEC_SH="$PWD/$EXEC_SH" ;; esac
WORK="$(mktemp -d "${TMPDIR:-/tmp}/exec-st.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; return 0; }
echo "== subject: $EXEC_SH"

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
BAD=0
for a in "$@"; do case "$a" in *.mpr) grep -q BREAK "$a" 2>/dev/null && BAD=1 ;; esac; done
for a in "$@"; do case "$a" in --write-errors=*)
  if [ "$BAD" = 1 ]; then printf '{"problems":[{"severity":"Error","errorCode":"CE0117","message":"type mismatch"}]}' > "${a#--write-errors=}"
  else printf '{"problems":[]}' > "${a#--write-errors=}"; fi ;; esac; done
[ "$BAD" = 1 ] && exit 1
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

echo "== a run whose gate FAILS still logs the gate seconds =="
printf '#!/usr/bin/env bash\necho BREAK >> "$1"\n' > "$P/break.sh"; chmod +x "$P/break.sh"
( cd "$P" && git add -A && git -c user.email=t@t -c user.name=t commit -qm after-first ) >/dev/null 2>&1
( cd "$P" && TMPDIR="$WORK/tmp" SKIP_BASELINE=1 SP_RESTART=0 MXTK_NO_INSTALL=1 \
    MXBUILD_PATH="$WORK/mxbuild" JAVA_HOME="$WORK/jdk" ./bin/exec.sh --patch break.sh ) > "$WORK/out2" 2>&1; RC2=$?
[ "$RC2" -ne 0 ] && ok "failing run exits non-zero" || bad "failing run exited 0" "$(tail -20 "$WORK/out2")"
ROW2="$(tail -1 "$P/docs/BUILD-LOG.md" 2>/dev/null)"
printf '%s\n' "$ROW2" | grep -qE 'gate failed|rolled back|not verified|unverified|blocked' \
  && ok "the last BUILD-LOG row is the failed one" || bad "last row is not a failure row" "$ROW2"
printf '%s\n' "$ROW2" | grep -qE 'steps: guards [0-9]+s check [0-9]+s snapshot [0-9]+s baseline [0-9]+s exec [0-9]+s gate [0-9]+s' \
  && ok "failed row carries steps including gate" || bad "failed row lacks gate seconds" "$ROW2"

echo; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
