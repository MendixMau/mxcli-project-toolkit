#!/usr/bin/env bash
# test-doctor-mxcli-arch.sh — doctor.sh --install must choose the mxcli asset from the real
# hardware. Git Bash on Windows 11 ARM64 runs emulated, so `uname -m` says x86_64 there; the
# `uname -s` suffix (...-ARM64) and PROCESSOR_ARCHITEW6432 / PROCESSOR_ARCHITECTURE tell the truth.
#
#   usage: bash tests/wave2/test-doctor-mxcli-arch.sh bin/doctor.sh
#
# A fake `uname` on PATH plays each machine; no stdin terminal and no --yes, so doctor prints the
# plan (with the asset URL) and downloads nothing.
set -u
DOCTOR="${1:?usage: $0 bin/doctor.sh}"
DOCTOR="$(cd "$(dirname "$DOCTOR")" && pwd)/$(basename "$DOCTOR")"
T="$(mktemp -d "${TMPDIR:-/tmp}/mxtk-doctor-arch.XXXXXX")"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ok    $*"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL  $*"; }

mkdir -p "$T/bin" "$T/proj"
cat > "$T/bin/uname" <<'EOS'
#!/usr/bin/env bash
case "${1:-}" in
  -s) echo "$FAKE_UNAME_S" ;;
  -m) echo "$FAKE_UNAME_M" ;;
  *)  echo "$FAKE_UNAME_S" ;;
esac
EOS
chmod +x "$T/bin/uname"

# case <label> <uname -s> <uname -m> <PROCESSOR_ARCHITEW6432> <PROCESSOR_ARCHITECTURE> <expected asset>
run_case() {
  local label="$1" us="$2" um="$3" w64="$4" pa="$5" want="$6" out="$T/out.$RANDOM"
  FAKE_UNAME_S="$us" FAKE_UNAME_M="$um" PROCESSOR_ARCHITEW6432="$w64" PROCESSOR_ARCHITECTURE="$pa" \
    MXCLI_VERSION= PATH="$T/bin:$PATH" bash "$DOCTOR" --install "$T/proj" < /dev/null > "$out" 2>&1
  if grep -F -- "/$want" "$out" > /dev/null; then ok "$label -> $want"; else
    fail "$label -> expected $want"; grep -E "from https|mxcli-(darwin|linux|windows)" "$out" | head -3; fi
}

echo "doctor mxcli arch — $DOCTOR"
run_case "gitbash ARM64 suffix, uname -m x86_64" "MINGW64_NT-10.0-26200-ARM64" x86_64 "" "" mxcli-windows-arm64.exe
run_case "gitbash PROCESSOR_ARCHITEW6432=ARM64" "MINGW64_NT-10.0-26200" x86_64 ARM64 AMD64 mxcli-windows-arm64.exe
run_case "gitbash PROCESSOR_ARCHITECTURE=ARM64" "MINGW64_NT-10.0-26200" aarch64 "" ARM64 mxcli-windows-arm64.exe
run_case "gitbash plain x86_64" "MINGW64_NT-10.0-26200" x86_64 "" AMD64 mxcli-windows-amd64.exe
run_case "gitbash plain x86_64, no PROCESSOR vars" "MINGW64_NT-10.0-26200" x86_64 "" "" mxcli-windows-amd64.exe
run_case "macOS arm64" Darwin arm64 "" "" mxcli-darwin-arm64
run_case "macOS x86_64" Darwin x86_64 "" "" mxcli-darwin-amd64
run_case "macOS ignores PROCESSOR_ARCHITECTURE=ARM64 vars" Darwin x86_64 ARM64 ARM64 mxcli-darwin-amd64
run_case "linux x86_64" Linux x86_64 "" "" mxcli-linux-amd64
run_case "linux aarch64" Linux aarch64 "" "" mxcli-linux-arm64

echo "pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
