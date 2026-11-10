#!/usr/bin/env bash
# test-doctor-portable.sh: #728 (a project ./mxcli built for another OS) and #711 (doctor's process-start
# timing must run the real `true` binary, not a hardcoded /bin/true that macOS lacks).
#
# usage: test-doctor-portable.sh /path/to/doctor.sh
#
# GOLDEN INPUT (captured, not hand-written; tests/wave2/fixtures/mxcli-binfmt/SOURCE.txt): the first 64
# bytes of a real Linux ELF (/bin/ls) and of two real macOS Mach-O executables (Go's debug/macho testdata,
# gcc output). The macOS side of this test is simulated on Linux with MXTK_PLATFORM=macos; a run on a
# real Mac is NOT done.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOCTOR="${1:?usage: $0 /path/to/doctor.sh}"
DOCTOR="$(cd "$(dirname "$DOCTOR")" && pwd)/$(basename "$DOCTOR")"
GOLD="$ROOT/tests/wave2/fixtures/mxcli-binfmt"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/doctor-portable.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
export MXTK_NO_GUIDE=1 MXTK_LEAKGUARD_DENYFILE="$WORK/deny" MXTK_DOCTOR_SKIP_DOCKER=1
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }
chk() { grep -q -- "$3" "$2" && ok "$1" || { bad "$1 (no '$3')"; sed -n 1,12p "$2" | sed 's/^/        /'; }; }

echo "doctor portability (#728, #711): $DOCTOR"
. "$ROOT/project-bin/_common.sh"

# --- mxtk_binfmt / mxtk_mxcli_wrong_format on the captured headers
[ "$(mxtk_binfmt "$GOLD/elf-x86_64-exec-header.bin")" = elf ] && ok "binfmt: ELF capture" || bad "binfmt: ELF capture"
[ "$(mxtk_binfmt "$GOLD/macho-amd64-exec-header.bin")" = macho ] && ok "binfmt: Mach-O capture" || bad "binfmt: Mach-O capture"
[ "$(mxtk_binfmt "$GOLD/macho-fat-header.bin")" = macho ] && ok "binfmt: fat Mach-O capture" || bad "binfmt: fat Mach-O capture"
printf '#!/bin/sh\nexit 0\n' > "$WORK/script"
[ "$(mxtk_binfmt "$WORK/script")" = other ] && ok "binfmt: shell script is other" || bad "binfmt: shell script"
[ "$(mxtk_mxcli_wrong_format "$GOLD/elf-x86_64-exec-header.bin" macos)" = elf ] && ok "macos host + ELF = wrong" || bad "macos host + ELF"
mxtk_mxcli_wrong_format "$GOLD/macho-amd64-exec-header.bin" macos && bad "macos host + Mach-O flagged" || ok "macos host + Mach-O = right"
[ "$(mxtk_mxcli_wrong_format "$GOLD/macho-fat-header.bin" linux)" = macho ] && ok "linux host + Mach-O = wrong" || bad "linux host + Mach-O"
mxtk_mxcli_wrong_format "$GOLD/elf-x86_64-exec-header.bin" linux && bad "linux host + ELF flagged" || ok "linux host + ELF = right"
mxtk_mxcli_wrong_format "$WORK/script" macos && bad "script flagged" || ok "script never flagged"

# --- doctor on a project whose ./mxcli is the wrong format (padded capture, executable)
mkproj() { # <dir> <header>
  mkdir -p "$1/mprcontents" "$1/.claude"; : > "$1/App.mpr"; : > "$1/mprcontents/x"
  { cat "$2"; head -c 4096 /dev/zero; } > "$1/mxcli"; chmod +x "$1/mxcli"
}
mkproj "$WORK/mac" "$GOLD/elf-x86_64-exec-header.bin"
MXTK_PLATFORM=macos bash "$DOCTOR" --quick "$WORK/mac" > "$WORK/mac.out" 2>&1
chk "macOS + Linux ./mxcli: FAIL names the cause" "$WORK/mac.out" "is a Linux program, but this computer runs macOS"
chk "macOS + Linux ./mxcli: remedy in plain words" "$WORK/mac.out" "mv mxcli mxcli.linux"
chk "macOS + Linux ./mxcli: offers --install" "$WORK/mac.out" "bin/doctor.sh --install"
grep -q "exit 126\|cannot run (exit" "$WORK/mac.out" && bad "old generic message still shown" || ok "no generic exit-126 message"
[ -x "$WORK/mac/mxcli" ] && ok "doctor did not move or delete the file" || bad "doctor touched mxcli"

mkproj "$WORK/lin" "$GOLD/macho-amd64-exec-header.bin"
MXTK_PLATFORM=linux bash "$DOCTOR" --quick "$WORK/lin" > "$WORK/lin.out" 2>&1
chk "Linux + Mach-O ./mxcli: FAIL names the cause" "$WORK/lin.out" "is a macOS program, but this computer runs Linux"

# --install: sets the foreign file aside before any fetch (no terminal, no --yes = nothing downloaded)
MXTK_PLATFORM=macos bash "$DOCTOR" --install "$WORK/mac" < /dev/null > "$WORK/inst.out" 2>&1
chk "--install: treats the foreign mxcli as missing" "$WORK/inst.out" "built for another OS; it will be kept as mxcli.elf"
[ -f "$WORK/mac/mxcli" ] && ok "--install without consent leaves the file in place" || bad "--install moved the file without consent"

# --install --yes with a fetch that fails (fake curl): the original is restored, and an existing
# set-aside file (mxcli.elf) is kept, never overwritten.
mkdir -p "$WORK/failbin"; printf '#!/bin/sh\nexit 22\n' > "$WORK/failbin/curl"; chmod +x "$WORK/failbin/curl"   # portability-ok: fixture fake
mkproj "$WORK/rst" "$GOLD/elf-x86_64-exec-header.bin"; cmp -s "$WORK/rst/mxcli" "$WORK/rst/mxcli" && cp "$WORK/rst/mxcli" "$WORK/rst.orig"
MXTK_PLATFORM=macos PATH="$WORK/failbin:$PATH" bash "$DOCTOR" --install --yes "$WORK/rst" < /dev/null > "$WORK/rst.out" 2>&1
cmp -s "$WORK/rst/mxcli" "$WORK/rst.orig" && ok "--install: failed fetch restores the original mxcli" || { bad "--install: original not restored after failed fetch"; sed -n 1,15p "$WORK/rst.out" | sed 's/^/        /'; }
[ -e "$WORK/rst/mxcli.elf" ] && bad "--install: set-aside file left behind after restore" || ok "--install: no stray mxcli.elf after restore"

mkproj "$WORK/keep" "$GOLD/elf-x86_64-exec-header.bin"; echo precious > "$WORK/keep/mxcli.elf"
MXTK_PLATFORM=macos PATH="$WORK/failbin:$PATH" bash "$DOCTOR" --install --yes "$WORK/keep" < /dev/null > "$WORK/keep.out" 2>&1
[ "$(cat "$WORK/keep/mxcli.elf" 2>/dev/null)" = precious ] && ok "--install: existing mxcli.elf kept, not overwritten" || bad "--install: existing mxcli.elf was overwritten"
cmp -s "$WORK/keep/mxcli" "$WORK/rst.orig" && ok "--install: original mxcli restored when mxcli.elf was taken" || bad "--install: original lost when mxcli.elf was taken"

# --- #711: the process-start timing runs the PATH `true` binary, 50 times in --bench
P="$WORK/proj"; mkdir -p "$P/mprcontents" "$P/.claude" "$WORK/bin" "$WORK/mxdir"
: > "$P/App.mpr"; : > "$P/mprcontents/x"; printf '#!/bin/sh\nexit 0\n' > "$P/mxcli"; chmod +x "$P/mxcli"
printf '#!/bin/sh\necho x >> "%s/true.count"\nexit 0\n' "$WORK" > "$WORK/bin/true"; chmod +x "$WORK/bin/true"
for t in git python3 node; do printf '#!/bin/sh\nexit 0\n' > "$WORK/bin/$t"; chmod +x "$WORK/bin/$t"; done   # portability-ok: fixture fakes the tools it probes
printf '#!/bin/sh\nexit 0\n' > "$WORK/mxdir/mxbuild"; printf '#!/bin/sh\nexit 3\n' > "$WORK/mxdir/mx"; chmod +x "$WORK/mxdir/mxbuild" "$WORK/mxdir/mx"
MXBUILD_PATH="$WORK/mxdir/mxbuild" PATH="$WORK/bin:/usr/bin:/bin" bash "$DOCTOR" --bench "$P" > "$WORK/bench.out" 2>&1
n="$(wc -l < "$WORK/true.count" 2>/dev/null | tr -d ' ')"
[ "${n:-0}" -ge 50 ] && ok "bench: the PATH true binary was started ${n} times (>= 50)" || bad "bench: PATH true started ${n:-0} times, expected >= 50"
grep -q 'No such file' "$WORK/bench.out" && bad "bench: stderr shows a failed exec" || ok "bench: no failed exec on stderr"
grep -n '/bin/true' "$DOCTOR" | grep -v '^[0-9]*:[[:space:]]*#' | grep -v 'for p in /usr/bin/true' && bad "doctor still has a bare /bin/true" || ok "doctor: no hardcoded /bin/true outside true_bin"

echo "pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
