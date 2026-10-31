#!/usr/bin/env bash
# Fixture for doctor.sh's "advise latest, respect pins" check (mxcli v0.29 compat, 2026-10-30):
# the normal doctor run compares the project's mxcli with the latest release and ADVISES —
# a WARN with the upgrade path when behind, a plain note when MXCLI_VERSION pins it, one quiet
# note when the latest cannot be read. Never a FAIL, never a download.
#
# usage: bash tests/wave2/test-doctor-mxcli-latest.sh [/path/to/bin/doctor.sh]
#
# Golden input: the stub mxcli prints the captured `mxcli --version` of the real release
# binaries (fixtures/property-sets/version-v0.2{4,8,9}.0.txt). MXTK_MXCLI_LATEST stands in for
# the network answer, so no request leaves the machine; the offline case points curl at
# nothing via MXTK_MXCLI_LATEST unset + a PATH without curl.
# Positive control: against master's doctor.sh (no advice) 4 pass, 8 fail — only D, G, H and
# A's "never a FAIL" pass, as they assert an absence.
set -uo pipefail
TK="$(cd "$(dirname "$0")/../.." && pwd)"
DOCTOR="${1:-$TK/bin/doctor.sh}"
case "$DOCTOR" in /*) ;; *) DOCTOR="$PWD/$DOCTOR" ;; esac
FIX="$TK/tests/wave2/fixtures/property-sets"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/doctor-latest.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
export MXTK_NO_GUIDE=1 MXTK_DOCTOR_SKIP_DOCKER=1 MXTK_LEAKGUARD_DENYFILE="$WORK/deny"
unset MXCLI_VERSION MXTK_NO_LATEST_CHECK
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; return 0; }

P="$WORK/proj"; mkdir -p "$P"; : > "$P/App.mpr"
cat > "$P/mxcli" <<STUB
#!/usr/bin/env bash
case "\${1:-}" in --version|version) cat "$FIX/version-\$(cat "$P/.ver").txt" ;; esac
exit 0
STUB
chmod +x "$P/mxcli"
run() { echo "$1" > "$P/.ver"; shift; ( cd "$WORK" && env "$@" bash "$DOCTOR" "$P" ) > "$WORK/out" 2>&1; }
out() { grep -E "mxcli|latest|MXCLI_VERSION|upgrade|what's new" "$WORK/out" | head -12; }

echo "== A: behind, not pinned: WARN, release link, upgrade path, how to pin =="
run v0.28.0 MXTK_MXCLI_LATEST=v0.29.0
grep -q "WARN  mxcli v0.28.0 is behind the latest release v0.29.0 (advice only" "$WORK/out" && ok "WARN names both versions" || bad "A: no WARN" "$(out)"
grep -q "releases/tag/v0.29.0" "$WORK/out" && ok "links the release notes" || bad "A: no link" "$(out)"
grep -q "bin/doctor.sh --install $P" "$WORK/out" && ok "names the upgrade command" || bad "A: no upgrade command" "$(out)"
grep -q "set MXCLI_VERSION=v0.28.0" "$WORK/out" && ok "says how to stay deliberately" || bad "A: no pin hint" "$(out)"
grep -qE "FAIL .*(latest|behind)" "$WORK/out" && bad "A: advice became a FAIL" "$(out)" || ok "never a FAIL"

echo "== B: behind, pinned by MXCLI_VERSION: a note, no WARN =="
run v0.28.0 MXTK_MXCLI_LATEST=v0.29.0 MXCLI_VERSION=v0.28.0
grep -q "mxcli pinned by MXCLI_VERSION=v0.28.0; latest is v0.29.0" "$WORK/out" && ! grep -q "WARN  mxcli v0.28.0 is behind" "$WORK/out" \
  && ok "pin respected: noted, not nagged" || bad "B" "$(out)"

echo "== C: on the latest: ok line =="
run v0.29.0 MXTK_MXCLI_LATEST=v0.29.0
grep -q "ok    mxcli v0.29.0 is the latest release" "$WORK/out" && ok "ok line" || bad "C" "$(out)"

echo "== D: newer than 'latest' (a pre-release build): not called behind =="
run v0.29.0 MXTK_MXCLI_LATEST=v0.28.0
grep -q "is behind" "$WORK/out" && bad "D: called behind" "$(out)" || ok "not behind"

echo "== E: below the toolkit's floor (v0.24.0): the floor is named =="
run v0.24.0 MXTK_MXCLI_LATEST=v0.29.0
grep -q "checked against v0.28.0 and later; v0.24.0 output may not parse" "$WORK/out" && ok "floor note" || bad "E" "$(out)"

echo "== F: latest unknown (no curl, no MXTK_MXCLI_LATEST): one quiet note =="
NOCURL="$WORK/nocurl"; mkdir -p "$NOCURL"
for t in bash sh env cat grep sed awk head tail tr cut sort uniq wc date uname mktemp rm mkdir dirname basename find ls printf readlink pwd chmod touch cp mv tee od id ps sleep kill git timeout stat file; do
  _p="$(command -v "$t" 2>/dev/null)" && ln -sf "$_p" "$NOCURL/$t"
done
. "$TK/bin/lib/portable.sh"; require_py >/dev/null 2>&1 && _p="$(command -v "$PY" 2>/dev/null)" && ln -sf "$_p" "$NOCURL/$(basename "$_p")"
run v0.28.0 PATH="$NOCURL"
grep -q "latest mxcli release: not checked (offline, or no curl) — installed v0.28.0" "$WORK/out" && ! grep -q "is behind" "$WORK/out" \
  && ok "offline: one note, no WARN" || bad "F" "$(out)"

echo "== G: MXTK_NO_LATEST_CHECK=1 skips it [guard] =="
run v0.28.0 MXTK_MXCLI_LATEST=v0.29.0 MXTK_NO_LATEST_CHECK=1
grep -qE "latest release|is behind" "$WORK/out" && bad "G: ran anyway" "$(out)" || ok "skipped"

echo "== H: --quick never makes the request [guard] =="
echo v0.28.0 > "$P/.ver"; ( cd "$WORK" && MXTK_MXCLI_LATEST=v0.29.0 bash "$DOCTOR" --quick "$P" ) > "$WORK/out" 2>&1
grep -qE "latest release|is behind" "$WORK/out" && bad "H: --quick ran it" "$(out)" || ok "--quick: not run"

echo ""
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
