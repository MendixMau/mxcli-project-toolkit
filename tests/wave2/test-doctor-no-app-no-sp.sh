#!/usr/bin/env bash
# test-doctor-no-app-no-sp.sh — doctor.sh --install on a machine that cannot get a native mxbuild.
#
#   usage: bash tests/wave2/test-doctor-no-app-no-sp.sh bin/doctor.sh
#
# Field run 2026-11-16 (Windows 11, Git Bash, no Studio Pro, no Docker, an EMPTY project folder):
# doctor printed four FAILs from the missing .mpr and its advice ("No Studio Pro needed for the
# gate: --install downloads the standalone toolchain") led to `mxcli new`, which downloaded 373 MB
# of a Linux mxbuild that could never run there. The Mendix CDN publishes Linux mxbuild only.
#
# A fake `uname` plays each OS; a stub ./mxcli logs every call, so "setup mxbuild" being invoked
# (or not) is observed, not inferred. HOME points at an empty dir so no real cache is found.
set -u
DOCTOR="${1:?usage: $0 bin/doctor.sh}"
DOCTOR="$(cd "$(dirname "$DOCTOR")" && pwd)/$(basename "$DOCTOR")"
T="$(mktemp -d "${TMPDIR:-/tmp}/mxtk-doctor-noapp.XXXXXX")"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ok    $*"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL  $*"; }

mkdir -p "$T/bin" "$T/home" "$T/nosp"   # nosp: MENDIX_APP aims discovery at an empty folder, so a real Studio Pro on the test host is never found
cat > "$T/bin/uname" <<'EOS'
#!/usr/bin/env bash
case "${1:-}" in
  -m) echo x86_64 ;;
  *)  echo "$FAKE_UNAME_S" ;;
esac
EOS
chmod +x "$T/bin/uname"

# A project folder with a stub mxcli (both spellings, so Git Bash's .exe preference finds one).
mkproj() {
  local d="$T/$1"; mkdir -p "$d"
  cat > "$d/mxcli" <<EOS
#!/usr/bin/env bash
echo "\$*" >> "$d/.calls"
case "\${1:-}" in --version|version) echo "mxcli version v0.32.0" ;; setup) exit 1 ;; esac
exit 0
EOS
  chmod +x "$d/mxcli"; cp "$d/mxcli" "$d/mxcli.exe"
  [ "${2:-}" = mpr ] && : > "$d/App.mpr"
  echo "$d"
}

plat() { case "$1" in Darwin) echo macos ;; MINGW*) echo windows ;; *) echo linux ;; esac; }
run() { # run <uname -s> <project> -> output file
  local out="$T/out.$RANDOM"
  # MXTK_PLATFORM: _common.sh reads $OSTYPE first, which the fake uname cannot change.
  MXTK_PLATFORM="$(plat "$1")" FAKE_UNAME_S="$1" HOME="$T/home" MXCLI_VERSION= MENDIX_APP="$T/nosp" MXBUILD_PATH= ProgramW6432= PROGRAMFILES= \
    PATH="$T/bin:$PATH" bash "$DOCTOR" --install --yes "$2" < /dev/null > "$out" 2>&1
  echo "$out"
}
has()    { grep -qF -- "$2" "$1"; }
called() { grep -q '^setup mxbuild' "$1/.calls" 2>/dev/null; }

echo "doctor --install, no app / no native mxbuild — $DOCTOR"

# 1. Windows, empty folder: say "create the app first", plan no 800 MB download, call no setup.
P="$(mkproj win-empty)"; O="$(run MINGW64_NT-10.0-26200 "$P")"
has "$O" "there is no Mendix app here yet" && ok "win empty: says there is no app yet" || fail "win empty: no 'no app yet' line"
has "$O" "Studio Pro > New app > Blank" && ok "win empty: names the Studio Pro step" || fail "win empty: no Studio Pro step"
has "$O" "BEFORE 'mxcli init'" && ok "win empty: says new before init" || fail "win empty: no new-before-init order"
has "$O" "mxbuild toolchain (~800 MB" && fail "win empty: still plans the 800 MB download" || ok "win empty: no 800 MB download planned"
called "$P" && fail "win empty: ran mxcli setup mxbuild" || ok "win empty: did not run mxcli setup mxbuild"

# 2. Windows, app present, no Studio Pro: say the CDN is Linux-only; still no setup call.
P="$(mkproj win-app mpr)"; O="$(run MINGW64_NT-10.0-26200 "$P")"
has "$O" "the Mendix CDN publishes Linux mxbuild only" && ok "win app: says CDN is Linux-only" || fail "win app: no Linux-only line"
has "$O" "Dev Container" && ok "win app: offers the Dev Container" || fail "win app: no Dev Container way out"
has "$O" "No Studio Pro needed for the gate" && fail "win app: still claims no Studio Pro needed" || ok "win app: no false 'no Studio Pro needed'"
called "$P" && fail "win app: ran mxcli setup mxbuild" || ok "win app: did not run mxcli setup mxbuild"

# 3. macOS, app present, no Studio Pro: same as Windows.
P="$(mkproj mac-app mpr)"; O="$(run Darwin "$P")"
has "$O" "the Mendix CDN publishes Linux mxbuild only" && ok "mac app: says CDN is Linux-only" || fail "mac app: no Linux-only line"
called "$P" && fail "mac app: ran mxcli setup mxbuild" || ok "mac app: did not run mxcli setup mxbuild"

# 4. Linux, app present: the download path is unchanged.
P="$(mkproj linux-app mpr)"; O="$(run Linux "$P")"
called "$P" && ok "linux app: still runs mxcli setup mxbuild" || fail "linux app: setup mxbuild no longer runs"

# 5. The project-section help text no longer says 'mxcli init' makes a .mpr.
P="$(mkproj win-help)"; O="$(run MINGW64_NT-10.0-26200 "$P")"
has "$O" "gets its .mpr from 'mxcli init'" && fail "help: still says mxcli init makes the .mpr" || ok "help: mxcli init no longer named as the .mpr source"

# 7. Studio Pro IS installed (macOS and Windows layouts): nothing changes — no download, no new
#    FAIL, the old "nothing to download" line. Guards against the fix firing on a healthy machine.
mkstub() { mkdir -p "$(dirname "$1")"; printf '#!/usr/bin/env bash\necho "MxBuild stub"\nexit 0\n' > "$1"; chmod +x "$1"; }
mkstub "$T/spmac/Contents/modeler/mxbuild"; mkstub "$T/spwin/modeler/mxbuild.exe"
for c in "Darwin:$T/spmac:mac" "MINGW64_NT-10.0-26200:$T/spwin:win"; do
  us="${c%%:*}"; rest="${c#*:}"; sp="${rest%:*}"; lbl="${rest##*:}"
  P="$(mkproj "$lbl-sp" mpr)"; O="$T/out.$lbl-sp"
  MXTK_PLATFORM="$(plat "$us")" FAKE_UNAME_S="$us" HOME="$T/home" MXCLI_VERSION= MENDIX_APP="$sp" MXBUILD_PATH= \
    PATH="$T/bin:$PATH" bash "$DOCTOR" --install --yes "$P" < /dev/null > "$O" 2>&1
  has "$O" "nothing to download" && ok "$lbl with Studio Pro: nothing to download" || fail "$lbl with Studio Pro: expected 'nothing to download'"
  has "$O" "publishes Linux mxbuild only" && fail "$lbl with Studio Pro: Linux-only FAIL fired" || ok "$lbl with Studio Pro: no Linux-only FAIL"
  called "$P" && fail "$lbl with Studio Pro: ran setup mxbuild" || ok "$lbl with Studio Pro: no setup mxbuild"
done

# 6. No Claude Code on the machine: the Claude-only section says "skipped", not WARN.
P="$(mkproj noclaude mpr)"; O="$T/out.noclaude"
MXTK_PLATFORM=linux HOME="$T/home" MENDIX_APP="$T/nosp" PATH="$T/bin:/usr/bin:/bin" FAKE_UNAME_S=Linux \
  bash "$DOCTOR" "$P" < /dev/null > "$O" 2>&1
sed -n '/Claude Code permissions/,/Property sets/p' "$O" > "$O.claude"
has "$O.claude" "skipped — Claude Code is not installed" && ok "no claude: section skipped" || fail "no claude: section not skipped"
grep -q 'WARN' "$O.claude" && fail "no claude: section still WARNs" || ok "no claude: no WARN from the Claude-only section"

echo "--- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
