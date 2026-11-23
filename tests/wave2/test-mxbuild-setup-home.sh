#!/usr/bin/env bash
# test-mxbuild-setup-home.sh — mxtk_ensure_mxbuild finds the mxbuild that `mxcli setup mxbuild` just
# fetched, also when MXCLI_HOME points somewhere else.
#
#   usage: bash tests/wave2/test-mxbuild-setup-home.sh project-bin/_common.sh
#
# Field (real-mxcli run, mxcli v0.32.0-374, Mendix 11.8.0, 2026-11-20): the toolkit reads the mxbuild
# cache at ${MXCLI_HOME:-~/.mxcli}, but mxcli itself always uses ~/.mxcli (os.UserHomeDir, in
# cmd/mxcli/docker/download.go). With MXCLI_HOME set, exec.sh's auto-download printed
# "MxBuild ready: /root/.mxcli/mxbuild/11.8.0/modeler/mxbuild", then "download reported success but
# no runnable mxbuild was found afterwards", and refused the exec.
#
# Golden input, captured verbatim: fixtures/mxbuild-setup/setup-mxbuild-cached-v0.32.0.out is the
# stdout+stderr of `./mxcli setup mxbuild -p ProbeApp.mpr` from that run. The stub mxcli replays it
# with "/root" replaced by this test's HOME (the only edit, so the path it names exists here) and
# creates that mxbuild, as the real command does.
#
#   A  MXCLI_HOME elsewhere: the reported mxbuild is used, rc 0, a note names MXCLI_HOME   (fails on master)
#   B  MXCLI_HOME unset: the same mxbuild, rc 0                                          (guard)
#   C  setup reports an mxbuild of another version: not used, rc 1                         (guard)
#   D  setup fails: rc 1, the "failed" line                                                (guard)
#
# Nothing here touches a real .mpr, a real mxcli or a real mxbuild.
set -u

COMMON="${1:?usage: $0 project-bin/_common.sh}"
COMMON="$(cd "$(dirname "$COMMON")" && pwd)/$(basename "$COMMON")"
HERE="$(cd "$(dirname "$0")" && pwd)"
GOLDEN="$HERE/fixtures/mxbuild-setup/setup-mxbuild-cached-v0.32.0.out"
T="$(mktemp -d "${TMPDIR:-/tmp}/mxtk-mxb-setup.XXXXXX")"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ok    $*"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL  $*"; }

# shellcheck disable=SC1091
. "$HERE/../../bin/lib/portable.sh"
PY="$(resolve_py)" && "$PY" -c 'import sqlite3' >/dev/null 2>&1 \
  || { echo "SKIP: no Python 3 with sqlite3"; exit 0; }

P="$T/proj"; mkdir -p "$P"
"$PY" - "$P/ProbeApp.mpr" <<'PYEOF'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute('CREATE TABLE _MetaData (_ProductVersion TEXT, _BuildVersion TEXT, _SchemaHash TEXT, _DisableAutoMprV2Upgrade INTEGER)')
c.execute("INSERT INTO _MetaData VALUES ('11.8.0', '11.8.0', '{SHA256}fixture', 0)")
c.commit()
PYEOF
H="$T/home"; mkdir -p "$H" "$T/elsewhere"
# Stub project mxcli. SETUP_VER: the version the replayed capture names (default 11.8.0). SETUP_RC: exit code.
cat > "$P/mxcli" <<MXCLI
#!/usr/bin/env bash
[ "\$1 \$2" = "setup mxbuild" ] || exit 0
v="\${SETUP_VER:-11.8.0}"
[ "\${SETUP_RC:-0}" = 0 ] || { echo "Error: download failed: dial tcp: lookup cdn.mendix.com"; exit 1; }
mkdir -p "\$HOME/.mxcli/mxbuild/\$v/modeler"
printf '#!/bin/sh\nexit 0\n' > "\$HOME/.mxcli/mxbuild/\$v/modeler/mxbuild"; chmod +x "\$HOME/.mxcli/mxbuild/\$v/modeler/mxbuild"
sed -e "s#/root#\$HOME#g" -e "s#11\\.8\\.0#\$v#g" "$GOLDEN"
MXCLI
chmod +x "$P/mxcli"

run() {  # run <extra env...> -> OUT (stdout), ERR, RC
  rm -rf "$H/.mxcli"
  env -i PATH="$PATH" HOME="$H" PROJECT_ROOT="$P" TMPDIR="$T" "$@" \
    bash -c "set -u; source '$COMMON'; mxtk_ensure_mxbuild '$P/ProbeApp.mpr'" >"$T/out" 2>"$T/err"
  RC=$?; OUT="$(cat "$T/out")"; ERR="$(cat "$T/err")"
}
WANT="$H/.mxcli/mxbuild/11.8.0/modeler/mxbuild"

echo "== A: MXCLI_HOME elsewhere =="
run MXCLI_HOME="$T/elsewhere"
[ "$RC" = 0 ] && [ "$OUT" = "$WANT" ] && ok "A: rc 0, the mxbuild mxcli reported" || fail "A: rc=$RC out='$OUT' err: $(tail -2 "$T/err")"
case "$ERR" in *"MXCLI_HOME=$T/elsewhere"*) ok "A: note names MXCLI_HOME" ;; *) fail "A: no MXCLI_HOME note" ;; esac
case "$ERR" in *"MxBuild ready: $WANT"*) ok "A: mxcli's own output still on stderr" ;; *) fail "A: setup output not shown" ;; esac

echo "== B: MXCLI_HOME unset =="
run
[ "$RC" = 0 ] && [ "$OUT" = "$WANT" ] && ok "B: rc 0, same mxbuild" || fail "B: rc=$RC out='$OUT'"
case "$ERR" in *"note: mxcli caches"*) fail "B: MXCLI_HOME note without MXCLI_HOME" ;; *) ok "B: no note" ;; esac

echo "== C: setup reports another version =="
run MXCLI_HOME="$T/elsewhere" SETUP_VER=11.9.0
[ "$RC" = 1 ] && ok "C: rc 1, a wrong-version mxbuild is not the gate" || fail "C: rc=$RC out='$OUT'"

echo "== D: setup fails =="
run MXCLI_HOME="$T/elsewhere" SETUP_RC=1
[ "$RC" = 1 ] && case "$ERR" in *"setup mxbuild' failed"*) true ;; *) false ;; esac \
  && ok "D: rc 1, failure named" || fail "D: rc=$RC err: $(tail -2 "$T/err")"

echo ""
echo "== $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
