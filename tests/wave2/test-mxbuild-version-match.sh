#!/usr/bin/env bash
# test-mxbuild-version-match.sh — project-bin/_common.sh's mxbuild version matching and the
# "refused, not clean" rule in mxtk_mxbuild_error_count.
#
#   usage: bash tests/wave2/test-mxbuild-version-match.sh project-bin/_common.sh
#
# Field origin (field project, Mendix 11.12.2, v1 single-file .mpr, 2026-09-26): find_mxbuild
# picked the NEWEST mxbuild (a Studio Pro 11.14.0 Beta). It refused the 11.12.2 model with exit
# 3, put the reason in the errors file's errors[] and left problems[] empty; the gate counted
# 0 Error problems and logged "pass · mxbuild clean" for 29 of 29 execs, one carrying a CE0066.
# The matching 11.12.2 mxbuild sat in the mxcli cache the whole time.
#
# Golden input, captured, not hand-written:
#   fixtures/mxbuild-version-mismatch.errors.json — the verbatim errors file of that refusal.
#   The _MetaData schema and row below — read off the real Marketplace.mpr on 2026-09-27:
#   columns (_ProductVersion, _BuildVersion, _SchemaHash, _DisableAutoMprV2Upgrade),
#   row ('11.12.2', '11.12.2', '{SHA256}…', 0).
#
# POSITIVE CONTROL: against _common.sh before this fix, cases 1-3 fail (no mxtk_model_version /
# mxtk_version_in_name, find_mxbuild returns the newest) and case 4a prints 0 instead of "?".
# Cases 4b-4d pass on both and are regression guards.
#
# Nothing here touches a real .mpr, a real mxcli or a real mxbuild.
set -u

COMMON="${1:?usage: $0 project-bin/_common.sh}"
COMMON="$(cd "$(dirname "$COMMON")" && pwd)/$(basename "$COMMON")"
HERE="$(cd "$(dirname "$0")" && pwd)"
GOLDEN="$HERE/fixtures/mxbuild-version-mismatch.errors.json"
T="$(mktemp -d "${TMPDIR:-/tmp}/mxtk-mxbuild-ver.XXXXXX")"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ok    $*"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL  $*"; }

# shellcheck disable=SC1091
. "$HERE/../../bin/lib/portable.sh"
PY="$(resolve_py)" && "$PY" -c 'import sqlite3' >/dev/null 2>&1 \
  || { echo "SKIP: no Python 3 with sqlite3"; exit 0; }

# ── Fixture project: a v1 single-file .mpr with the captured _MetaData shape ─
P="$T/proj"; mkdir -p "$P"
"$PY" - "$P/Fixture.mpr" <<'PYEOF'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute('CREATE TABLE _MetaData (_ProductVersion TEXT, _BuildVersion TEXT, _SchemaHash TEXT, _DisableAutoMprV2Upgrade INTEGER)')
c.execute("INSERT INTO _MetaData VALUES ('11.12.2', '11.12.2', '{SHA256}fixture', 0)")
c.commit()
PYEOF

# Stub java and a fake mxcli cache with two mxbuild versions. MODE selects the stub's output.
mkdir -p "$T/jdk/bin"; printf '#!/bin/sh\nexit 0\n' > "$T/jdk/bin/java"; chmod +x "$T/jdk/bin/java"
mk_mxbuild() {  # mk_mxbuild <dir>
  mkdir -p "$1/modeler"
  cat > "$1/modeler/mxbuild" <<MXB
#!/usr/bin/env bash
OUT=""
for a in "\$@"; do case "\$a" in --write-errors=*) OUT="\${a#--write-errors=}" ;; esac; done
case "\${MODE:-clean}" in
  refused)  cp "$GOLDEN" "\$OUT"; exit 3 ;;
  errors)   printf '{"errors":[],"problems":[{"severity":"Error","errorCode":"CE0066","message":"Entity access is out of date."},{"severity":"Error","errorCode":"CE0066","message":"Entity access is out of date."}]}' > "\$OUT"; exit 3 ;;
  empty)    : > "\$OUT"; exit 0 ;;
  clean)    printf '{"problems":[]}' > "\$OUT"; exit 0 ;;
esac
MXB
  chmod +x "$1/modeler/mxbuild"
}
H="$T/home"
mk_mxbuild "$H/.mxcli/mxbuild/11.14.0"
mk_mxbuild "$H/.mxcli/mxbuild/11.12.2"

run_in() {  # run_in <extra env, may be empty> <body>
  env -i PATH="$PATH" HOME="$H" PROJECT_ROOT="$P" JAVA_HOME="$T/jdk" ${1:+$1} \
    bash -c "set -u; source '$COMMON'; $2"
}

# ── 1: the model's version comes off _MetaData ───────────────────────────────
echo "== 1: mxtk_model_version reads _MetaData._ProductVersion =="
OUT=$(run_in "" 'mxtk_model_version' 2>&1)
[ "$OUT" = "11.12.2" ] && ok "model version = 11.12.2" || fail "model version -> '$OUT', expected 11.12.2"
printf 'not a model\n' > "$T/junk.mpr"
OUT=$(run_in "" "mxtk_model_version '$T/junk.mpr' && echo MATCHED || echo none" 2>&1)
[ "$OUT" = "none" ] && ok "[guard] a non-SQLite .mpr gives no version (falls back)" || fail "junk .mpr -> '$OUT'"

# ── 2: version-in-name matrix ────────────────────────────────────────────────
echo "== 2: mxtk_version_in_name =="
for pair in "11.12.2|11.12.2|yes" "11.12.2.83245|11.12.2|yes" \
            "Mendix Studio Pro 11.12.2.app|11.12.2|yes" "Mendix Studio Pro 11.14.0 Beta.app|11.14.0|yes" \
            "11.12.20|11.12.2|no" "11.14.0|11.12.2|no" "/x/11.12.2/y/11.14.0|11.12.2|no"; do
  n="${pair%%|*}"; rest="${pair#*|}"; v="${rest%%|*}"; want="${rest#*|}"
  got=$(run_in "" "mxtk_version_in_name '$n' '$v' && echo yes || echo no")
  [ "$got" = "$want" ] && ok "'$n' vs $v -> $got" || fail "'$n' vs $v -> $got, expected $want"
done

# ── 3: find_mxbuild prefers the model's version over the newest ──────────────
echo "== 3: find_mxbuild picks the matching mxbuild, not the newest =="
OUT=$(run_in "" 'find_mxbuild' 2>/dev/null)
case "$OUT" in
  */11.12.2/modeler/mxbuild) ok "picked 11.12.2 (model version) over 11.14.0 (newest)" ;;
  *) fail "picked '$OUT', expected the 11.12.2 cache entry" ;;
esac
OUT=$(run_in "MXBUILD_PATH=$H/.mxcli/mxbuild/11.14.0/modeler/mxbuild" 'find_mxbuild' 2>/dev/null)
case "$OUT" in */11.14.0/*) ok "[guard] MXBUILD_PATH still wins" ;; *) fail "MXBUILD_PATH ignored -> '$OUT'" ;; esac
mv "$H/.mxcli/mxbuild/11.12.2" "$T/parked-11.12.2"
OUT=$(run_in "" 'find_mxbuild' 2>/dev/null)
case "$OUT" in */11.14.0/*) ok "[guard] no match -> newest fallback" ;; *) fail "no-match fallback -> '$OUT'" ;; esac
ERR=$(run_in "MXTK_NO_INSTALL=1" "mxtk_ensure_mxbuild '$P/Fixture.mpr'" 2>&1 >/dev/null)
printf '%s' "$ERR" | grep -q "11.12.2" && printf '%s' "$ERR" | grep -qi "refuses" \
  && ok "mismatch fallback is announced on stderr, naming 11.12.2" \
  || fail "mismatch fallback was silent: '$ERR'"

# ── 4: a refusal is "?", never 0 ─────────────────────────────────────────────
echo "== 4: mxtk_mxbuild_error_count on mxbuild's exit + errors file =="
MXB="MXBUILD_PATH=$H/.mxcli/mxbuild/11.14.0/modeler/mxbuild"
# Called directly, not in $(...), so the MXTK_MXBUILD_* globals land in this shell.
OUT=$(run_in "$MXB MODE=refused" "mxtk_mxbuild_error_count '$P/Fixture.mpr' 30 > '$T/cnt' 2>/dev/null; rc=\$?; echo \"\$(cat '$T/cnt')|\$rc|\${MXTK_MXBUILD_EXIT:-unset}\"")
WHY=$(run_in "$MXB MODE=refused" "mxtk_mxbuild_error_count '$P/Fixture.mpr' 30 >/dev/null 2>&1; echo \"\${MXTK_MXBUILD_WHY:-}\"")
[ "${OUT%%|*}" = "?" ] && ok "4a: refused (exit 3, errors[], empty problems[]) -> '?'" \
                      || fail "4a: refused -> '${OUT%%|*}' (the false green: 0 read as clean)"
case "$WHY" in *"does not exactly match MxBuild version"*) ok "4a: MXTK_MXBUILD_WHY carries mxbuild's own reason" ;;
  *) fail "4a: MXTK_MXBUILD_WHY='$WHY'" ;; esac
OUT=$(run_in "$MXB MODE=errors" "mxtk_mxbuild_error_count '$P/Fixture.mpr' 30" 2>&1)
[ "$OUT" = "2" ] && ok "[guard] 4b: 2 x CE0066 with exit 3 -> 2" || fail "4b: -> '$OUT'"
OUT=$(run_in "$MXB MODE=empty" "mxtk_mxbuild_error_count '$P/Fixture.mpr' 30" 2>&1)
[ "$OUT" = "0" ] && ok "[guard] 4c: empty file + exit 0 -> 0" || fail "4c: -> '$OUT'"
OUT=$(run_in "$MXB MODE=clean" "mxtk_mxbuild_error_count '$P/Fixture.mpr' 30" 2>&1)
[ "$OUT" = "0" ] && ok "[guard] 4d: {\"problems\":[]} + exit 0 -> 0" || fail "4d: -> '$OUT'"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
