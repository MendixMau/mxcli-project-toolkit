#!/usr/bin/env bash
# doctor.sh — probe this machine once and say, in plain language, what the toolkit needs and
# what is missing. Run this before anything else, on any platform.
#
# WHY THIS EXISTS. The toolkit is handed to people who cannot debug a shell script. Every
# environment assumption it makes was previously discovered halfway through a pipeline stage,
# where it reads as "the toolkit is broken" rather than "my machine is missing something".
# One command, run first, moves every one of those discoveries to the front.
#
# This script deliberately depends on almost nothing: POSIX shell plus coreutils. It must be
# able to report "you have no Python" while itself having no Python. Do not add a dependency
# here without checking it against that rule.
#
#   bin/doctor.sh                           # probe the machine
#   bin/doctor.sh <project-dir>             # also probe a specific project's wiring
#   bin/doctor.sh --install <project-dir>   # and, if tools are missing, offer to download
#                                           # them locally: a missing ./mxcli from the
#                                           # mendixlabs/mxcli GitHub releases, then the
#                                           # mxbuild toolchain via `./mxcli setup mxbuild`
#                                           # (same download the headless container build
#                                           # uses; cached at ~/.mxcli/mxbuild/).
#   bin/doctor.sh --install --yes <dir>     # skip the confirmation (unattended/agent runs)
#   bin/doctor.sh --no-docker [<project-dir>] # skip the container-runtime probe (or
#                                           # MXTK_DOCTOR_SKIP_DOCKER=1). The probe is bounded
#                                           # anyway: MXTK_DOCKER_PROBE_SECS (default 8) — a
#                                           # stopped Docker Desktop can make 'docker info' sit
#                                           # silent for minutes, which read as "the setup
#                                           # hangs" (field report, 2026-09-09). The probe finds
#                                           # docker OR podman, whichever is present;
#                                           # MXTK_CONTAINER_RUNTIME=<name> forces one.
#   bin/doctor.sh --quick [<project-dir>]   # ~2 s: platform, mxcli/mxbuild/java EXECUTE, spawn
#                                           # speed, path hygiene, model layout. Skips the
#                                           # once-per-machine sections (python, CRLF, script
#                                           # parse, node, docker, gate self-test). exec.sh runs
#                                           # this itself when the receipt is stale — doctor
#                                           # used to run once and never again, so a machine
#                                           # that drifted mid-project (new binary, wrong-arch
#                                           # mxbuild, a Defender policy) read as "the toolkit
#                                           # is broken".
#   bin/doctor.sh --gate-selftest [<dir>]   # force the gate self-test section to run even
#                                           # under --quick, or on its own. See its own header
#                                           # (search "Gate self-test") for what it proves and
#                                           # why: mxbuild/java being PRESENT does not mean the
#                                           # mxbuild gate can actually SEE an error.
#
# --install never downloads silently: it prints the plan first — what, from where, how big,
# why, and the detected OS/arch — then asks [y/N] at a terminal, or requires --yes when there
# is no terminal to ask on. $MXCLI_VERSION=vX.Y.Z pins the mxcli release; default is latest.
#
# --install is the one deliberate exception to the no-dependency rule: it needs network access
# (and curl or wget), runs only when asked, and a failed or declined download degrades to the
# same report you would have had without it.
#
# Exit: 0 = ready. 1 = warnings only, the toolkit will mostly work. 2 = something required is
# missing and a pipeline stage will fail.

set -u

TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR=""
INSTALL=0
ASSUME_YES=0
QUICK=0
GATE_SELFTEST=0
NO_DOCKER="${MXTK_DOCTOR_SKIP_DOCKER:-0}"
DOCKER_PROBE_SECS="${MXTK_DOCKER_PROBE_SECS:-8}"
for _arg in "$@"; do
  case "$_arg" in
    --install) INSTALL=1 ;;
    --yes|-y)  ASSUME_YES=1 ;;
    --quick)   QUICK=1 ;;
    --gate-selftest) GATE_SELFTEST=1 ;;
    --no-docker) NO_DOCKER=1 ;;
    *)         PROJECT_DIR="$_arg" ;;
  esac
done

FAIL=0
WARN=0

ok()   { printf '  ok    %s\n' "$*"; }
warn() { printf '  WARN  %s\n' "$*"; WARN=$((WARN + 1)); }
bad()  { printf '  FAIL  %s\n' "$*"; FAIL=$((FAIL + 1)); }
note() { printf '        %s\n' "$*"; }
head_() { printf '\n%s\n' "$*"; }

# probe_runs <binary> — does this binary actually EXECUTE on this machine?
#
# Not the same question as "does --version exit 0". Field report (2026-08-31, macOS, latest
# Studio Pro): its mxbuild dropped --version, so the flag exits non-zero while the binary is
# perfectly healthy — and this script's old probe read that as "mxbuild cannot run" on exactly
# the machine of the person we told to run doctor first. The probe the section needs is
# execute-level: try --version, and when the flag (not the binary) is what failed, try --help.
# Exit 126/127 is the binary itself failing (wrong platform / not found) — no retry can fix
# that. Both flags failing with other codes is also reported broken, with the output shown.
# On success: PROBE_OUT holds the first probe's output, PROBE_HOW names the flag that worked.
# (Show PROBE_OUT via probe_line — real mxbuild's --help opens with a blank-lined ASCII
# banner, so a naive head -1 prints nothing.)
# Every probe runs the binary with its output on a FILE, never inside `$(...)`. Studio Pro
# 11's mxbuild.exe (11.12.4, Windows, 2026-09-14) starts modeler/tools/deno/win-x64/deno.exe,
# which inherits stdout and outlives mxbuild — on --version and --help as much as on a real
# build. A command substitution waits for EOF on the pipe, deno never closes it, and doctor
# sat in "Build toolchain" for over ten minutes on the one machine it was meant to diagnose
# (it finished the instant the stray deno was killed). Writing to a file has no reader
# waiting on EOF, so bash returns when mxbuild itself exits. stdin is closed so a console-
# attached child cannot wait on that either. probe_capture <var> <cmd...> sets <var> to the
# combined output and returns the command's exit status.
PROBE_OUT=""
PROBE_HOW=""
probe_line() { printf '%s\n' "$PROBE_OUT" | grep -v '^[[:space:]]*$' | head -1; }
probe_capture() {
  _pc_var="$1"; shift
  _pc_file=$(mktemp "${TMPDIR:-/tmp}/doctor-probe.XXXXXX")
  _pc_exit=0
  "$@" > "$_pc_file" 2>&1 < /dev/null || _pc_exit=$?
  eval "$_pc_var=\$(cat \"\$_pc_file\")"
  rm -f "$_pc_file"
  return "$_pc_exit"
}
probe_runs() {
  PROBE_OUT=""; PROBE_HOW=""
  _pr_exit=0
  # --quick: the question is only "does it START" (exit 126/127 is the wrong-platform binary,
  # and that answer arrives in milliseconds). A healthy mxbuild spends ~5-9 s in .NET start-up
  # per flag, which made "quick" take 14 s; bound it and read a timeout as "started".
  if [ "$QUICK" = 1 ] && command -v timeout >/dev/null 2>&1; then
    probe_capture PROBE_OUT timeout 2 "$1" --help || _pr_exit=$?
    case "$_pr_exit" in
      0|124) PROBE_HOW="started (quick probe, 2 s bound)"; [ -n "$PROBE_OUT" ] || PROBE_OUT="(started)"; return 0 ;;
      126|127) return "$_pr_exit" ;;
    esac
    _pr_exit=0
  fi
  probe_capture PROBE_OUT "$1" --version || _pr_exit=$?
  if [ "$_pr_exit" -eq 0 ]; then PROBE_HOW="--version"; return 0; fi
  case "$_pr_exit" in 126|127) return "$_pr_exit" ;; esac
  if probe_capture _pr_out2 "$1" --help; then
    PROBE_OUT="$_pr_out2"; PROBE_HOW="--help; this build has no --version"
    return 0
  fi
  return "$_pr_exit"
}

# --- platform -------------------------------------------------------------------------------

head_ "Platform"

UNAME="$(uname -s 2>/dev/null || echo unknown)"
case "$UNAME" in
  Darwin)             PLATFORM=macos ;;
  Linux)              PLATFORM=linux ;;
  MINGW*|MSYS*|CYGWIN*) PLATFORM=gitbash ;;
  *)                  PLATFORM=unknown ;;
esac
ok "$UNAME  (treating this as: $PLATFORM)"

# WSL reports Linux. It matters, because a WSL shell cannot see Windows applications the way
# Git Bash can — Studio Pro automation is reached differently, or not at all.
if [ "$PLATFORM" = linux ] && grep -qi microsoft /proc/version 2>/dev/null; then
  PLATFORM=wsl
  warn "This is WSL, not native Linux."
  note "WSL is a separate Linux filesystem and process space. Scripts that drive Studio Pro"
  note "or reach a locally running app on the Windows side need the Windows host, not this one."
  note "If you are on Windows, prefer Git Bash for toolkit scripts until this is settled."
fi

ok "shell: ${BASH_VERSION:-not bash}"
case "${BASH_VERSION:-0}" in
  3.*) note "bash 3.2 (the macOS system bash). Scripts here are written for it; nothing to do." ;;
esac

# --- environment lane -------------------------------------------------------------------------
# Where this session runs decides the write modes available (CONVERSION-RUNBOOK.md → "Where you
# run this"). It is DETECTED, never asked: the agent records the answer in PROJECT.md and moves on.
#   cloud        Claude Code on the web/mobile: CLAUDE_CODE_REMOTE=true. Ephemeral — push at
#                every gate. Headless lane: CLI write mode only, mxcli run --local(--hub) to see it.
#   devcontainer VS Code devcontainer / Codespaces / any Docker container on Linux. Same headless
#                lane as cloud, on your own disk.
#   local        macOS or Windows with Studio Pro reachable: all three write modes.
#   local-linux  native Linux, no container markers: headless lane, nothing ephemeral.

head_ "Environment lane (detected)"

if [ "${CLAUDE_CODE_REMOTE:-}" = "true" ]; then
  ENV_LANE=cloud
elif [ -n "${REMOTE_CONTAINERS:-}${CODESPACES:-}${DEVCONTAINER:-}" ] || [ -f /.dockerenv ]; then
  ENV_LANE=devcontainer
else
  case "$PLATFORM" in
    macos|gitbash|wsl) ENV_LANE=local ;;
    *)                 ENV_LANE=local-linux ;;
  esac
fi
ok "$ENV_LANE"
case "$ENV_LANE" in
  cloud)
    note "Ephemeral container: the git remote is the workspace — commit and push at every gate."
    note "Headless: CLI write mode (exec.sh + mxbuild gate); see the app with mxcli run --local --hub."
    note "mxcli run --local CONSOLIDATES a split-model .mpr (CRITICAL, bug-logs): snapshot first, git status after."
    note "Setup order for a new project: skills/cloud-dev-environment.md." ;;
  devcontainer|local-linux)
    note "Headless lane: CLI write mode (exec.sh + mxbuild gate); mxcli run --local to see the app."
    note "Nothing is ephemeral here. Studio Pro modes (--mcp) are not available HERE — open the same"
    note ".mpr from a Mac terminal / Git Bash when you need them; lanes mix, one .mpr writer at a time." ;;
  local)
    note "Studio Pro lane: all three write modes (CLI, --mcp, hand-rolled MCP) when SP is installed." ;;
esac
note "Agents: record this once in PROJECT.md as 'Environment: $ENV_LANE' — do not ask the user."

if [ "$QUICK" != 1 ]; then
# --- python ---------------------------------------------------------------------------------

head_ "Python 3"

# shellcheck disable=SC1091
. "$TOOLKIT_ROOT/bin/lib/portable.sh"

if PY_FOUND="$(resolve_py)"; then
  ok "$PY_FOUND -> $($PY_FOUND -c 'import sys,platform; print(sys.executable or "?", platform.python_version())' 2>/dev/null)"
else
  bad "No working Python 3 found. Tried, by running each: python3, python, py."
  note "macOS  : brew install python3"
  note "Linux  : apt install python3   (or your distro's equivalent)"
  note "Windows: install from python.org and tick 'Add python.exe to PATH'."
  # The py launcher can default to Python 2 while a perfectly good Python 3 sits behind -3.
  if py -3 -c 'import sys; sys.exit(0)' >/dev/null 2>&1; then
    note "NOTE: 'py -3' works on this machine but 'py' does not default to it. The scripts need"
    note "a single-word command, so set one: py -3 -m ensurepip, or reinstall with PATH ticked."
  fi
fi

# The Store alias stub is worth naming even when a real interpreter was found later on PATH:
# it is the thing that will confuse the reader when they type python3 themselves.
for c in python3 python; do
  case "$(command -v "$c" 2>/dev/null)" in
    *WindowsApps*|*windowsapps*)
      warn "'$c' on your PATH is the Microsoft Store alias stub, not an interpreter."
      note "The toolkit skips it. You should still turn it off:"
      note "Settings > Apps > Advanced app settings > App execution aliases."
      ;;
  esac
done

# --- line endings ------------------------------------------------------------------------

head_ "Line endings"

# The highest-value check in this file. If git checked these scripts out with CRLF, bash fails
# on line 1 of every one of them with a message ($'\r': command not found) that names nothing
# a reader can act on. It happens before any other check in this script would ever run.
CRLF_HITS=0
CRLF_FIRST=""
CRLF_SEEN=0
for f in "$TOOLKIT_ROOT"/bin/*.sh "$TOOLKIT_ROOT"/bin/lib/*.sh "$TOOLKIT_ROOT"/project-bin/*.sh \
         "$TOOLKIT_ROOT"/claude-hooks/hooks/*.sh "$TOOLKIT_ROOT"/claude-hooks/bin/*.sh; do
  [ -f "$f" ] || continue
  CRLF_SEEN=$((CRLF_SEEN + 1))
  # Strip CR and compare with the original: any difference means the file carries CRs.
  if ! tr -d '\r' < "$f" | cmp -s - "$f"; then
    CRLF_HITS=$((CRLF_HITS + 1))
    [ -n "$CRLF_FIRST" ] || CRLF_FIRST="$f"
  fi
done

# Zero scripts found is not "all your scripts are fine" — it means the probe looked in the
# wrong place and would report LF over an empty set. Say so instead.
if [ "$CRLF_SEEN" -eq 0 ]; then
  bad "found no shell scripts under $TOOLKIT_ROOT to check — this is not a pass"
  note "Either the toolkit path is wrong, or the clone is incomplete — re-clone the toolkit."
elif [ "$CRLF_HITS" -gt 0 ]; then
  bad "$CRLF_HITS script(s) have Windows line endings (CRLF). They will not run."
  note "first one: $CRLF_FIRST"
  note "Every one fails on its first line with: \$'\\r': command not found"
  note "Fix, from the toolkit root:"
  note "  git config core.autocrlf false"
  note "  git rm --cached -r . && git reset --hard"
  note "The .gitattributes in this repo prevents it happening again on a fresh clone."
else
  ok "shell scripts are LF, as required ($CRLF_SEEN checked)"
fi

AUTOCRLF="$(git -C "$TOOLKIT_ROOT" config --get core.autocrlf 2>/dev/null || echo unset)"
case "$AUTOCRLF" in
  true) warn "git core.autocrlf=true. .gitattributes overrides it for *.sh, but set it false." ;;
  *)    ok "git core.autocrlf=$AUTOCRLF" ;;
esac

# --- the toolkit's own scripts --------------------------------------------------------------

head_ "Do the toolkit's own scripts load here?"

# CRLF above catches one way a script cannot run; this catches the rest of the parse-level
# class (a bashism this bash rejects, a syntax error that shipped, a mangled installed copy)
# by running every shipped script through its interpreter's parse step. check-scripts.sh is
# standalone so sync-project.sh can run the same probe after every refresh.
if [ -x "$TOOLKIT_ROOT/bin/check-scripts.sh" ]; then
  CS_EXIT=0
  "$TOOLKIT_ROOT/bin/check-scripts.sh" ${PROJECT_DIR:+"$PROJECT_DIR"} || CS_EXIT=$?
  case "$CS_EXIT" in
    0) ok "every shipped script parses under this machine's bash and node" ;;
    1) warn "shell scripts parse; Node instruments unchecked (no node — see the Node section)" ;;
    *) bad "script(s) that will not run on this machine — see the FAIL lines above" ;;
  esac
else
  bad "bin/check-scripts.sh is missing — the clone is incomplete or predates it"
  note "git pull inside the toolkit clone restores it (or re-clone the toolkit)."
fi

fi

# --- command line tools ---------------------------------------------------------------------

head_ "Command line tools"

CORE_MISSING=0
for c in git sed grep awk find sort tr cut; do
  command -v "$c" >/dev/null 2>&1 && ok "$c" || { bad "$c is missing — it is used by nearly every script"; CORE_MISSING=$((CORE_MISSING + 1)); }
done
if [ "$CORE_MISSING" -gt 0 ]; then
  note "These all arrive together: Windows — install Git for Windows and use its Git Bash;"
  note "macOS — xcode-select --install; Linux — apt install git (coreutils ships with the distro)."
fi

command -v sqlite3 >/dev/null 2>&1 && ok "sqlite3" || {
  warn "sqlite3 is missing. project-bin/graph-sweep.sh reads the mxcli catalog with it."
  note "macOS: preinstalled. Linux: apt install sqlite3. Windows: winget install SQLite.SQLite"; }

command -v shellcheck >/dev/null 2>&1 && ok "shellcheck (optional, for editing toolkit scripts)" \
  || note "shellcheck not installed — only needed if you edit toolkit scripts"

if [ "$QUICK" != 1 ]; then
# --- studio pro -------------------------------------------------------------------------

head_ "Studio Pro automation"

case "$PLATFORM" in
  macos)
    if ls -d /Applications/Mendix\ Studio\ Pro*.app >/dev/null 2>&1; then
      ok "found: $(ls -d /Applications/Mendix\ Studio\ Pro*.app | tr '\n' ' ')"
    else
      warn "no 'Mendix Studio Pro *.app' in /Applications — project-bin/restart-sp.sh cannot run"
      note "Install Studio Pro (Mendix Marketplace) if you want SP automation; everything"
      note "else works without it — the mxbuild gate can run on the downloaded toolchain."
    fi
    ;;
  gitbash|wsl|linux|unknown)
    # Informational only. Nobody needs these scripts to use the toolkit — Studio Pro is
    # opened and saved by hand at the points where they would run — so on the platforms
    # they do not exist for, this is not a warning. (It was one; a Windows onboarding
    # counted it among "6 warnings" and asked what to do about it. Nothing.)
    note "save-sp.sh / restart-sp.sh (macOS conveniences) are not on this platform — you open"
    note "and save Studio Pro yourself at those points. Nothing else depends on them."
    ;;
esac

fi

# --- build toolchain -----------------------------------------------------------------------

head_ "Build toolchain (mxbuild model verification)"

# WHY THIS SECTION EXISTS. exec.sh verifies every model write with mxbuild. When mxbuild or
# its Java cannot be resolved, the gate does not fail — it reports `skipped` and the exec goes
# through UNVERIFIED. Real incident (Windows training round, 2026-08): machines where mxbuild
# could not run went whole exercises without a single consistency error being captured,
# because nobody reads a skip as a problem. This section answers, before any work starts,
# the one question that decided that: will the mxbuild gate actually run on this machine?
#
# Discovery is deliberately the SAME code exec.sh uses (project-bin/_common.sh), so a green
# line here predicts the gate's behaviour instead of approximating it.

# _common.sh resolves PROJECT_ROOT by walking up from $PWD when unset; pin it first so
# sourcing it from an arbitrary directory stays inert. (It also redefines resolve_py with its
# project-side twin — harmless, the Python probe above already ran.)
PROJECT_ROOT="${PROJECT_DIR:-$TOOLKIT_ROOT}"
# shellcheck disable=SC1091
. "$TOOLKIT_ROOT/project-bin/_common.sh"

SP_APP="$(find_sp_app 2>/dev/null || true)"
MXBUILD="$(find_mxbuild 2>/dev/null || true)"
JAVA_HOME_FOUND="$(find_java 2>/dev/null || true)"
JAVA_EXE="$(find_java_exe 2>/dev/null || true)"

# toolkit.env — the human-editable answer to "doctor guessed the wrong Studio Pro / Java".
# _common.sh already loaded it (project file, then ~/.mxcli-toolkit.env; a variable set in
# the shell wins over both). Say what was read, so a stale value is findable.
if [ -n "${MXTK_ENV_LOADED:-}" ]; then
  ok "toolkit.env loaded: $MXTK_ENV_LOADED"
else
  note "No toolkit.env — discovery guesses below. To pin tool locations for this machine, create"
  note "  ${PROJECT_DIR:-<project>}/.claude/toolkit.env  (this project)  or  ~/.mxcli-toolkit.env  (every project)"
  note "  with lines like:  MENDIX_APP=C:\\Program Files\\Mendix\\11.11.0    JAVA_HOME=C:\\Software\\Java\\jdk-21"
  note "  (Windows paths can be pasted as-is; MXBUILD_PATH, MXCLI_VERSION and PYTHON work too.)"
fi

# --install: when no runnable mxbuild was discovered, download the standalone toolchain
# through the project's own mxcli — `./mxcli setup mxbuild -p <app>.mpr`, the exact download
# the headless container build runs, cached at ~/.mxcli/mxbuild/<version>/ and shared across
# projects. find_mxbuild/find_java (project-bin/_common.sh) discover that cache, so after a
# successful download the exec.sh mxbuild gate runs from it too — no Studio Pro required.
# This happens BEFORE the reporting below, so the report describes the machine as it now is.

# The setup step itself, shared by the had-mxcli and just-fetched-mxcli paths. Re-runs the
# toolchain discovery on success — the cache did not exist the first time around.
install_toolchain() {
  INSTALL_MPR="$(ls "$PROJECT_DIR"/*.mpr 2>/dev/null | head -1)"
  if [ -z "$INSTALL_MPR" ]; then
    bad "--install: no .mpr in $PROJECT_DIR — setup mxbuild needs the model to pick a version."
    return
  fi
  note "downloading the mxbuild toolchain (mxcli setup mxbuild — same as the container build)..."
  if (cd "$PROJECT_DIR" && "$PMXCLI" setup mxbuild -p "$(basename "$INSTALL_MPR")"); then
    SP_APP="$(find_sp_app 2>/dev/null || true)"
    MXBUILD="$(find_mxbuild 2>/dev/null || true)"
    JAVA_HOME_FOUND="$(find_java 2>/dev/null || true)"
    JAVA_EXE="$(find_java_exe 2>/dev/null || true)"
    ok "toolchain downloaded to ~/.mxcli/mxbuild/ (shared cache, reused by every project)"
  else
    bad "'mxcli setup mxbuild' failed — see its output above."
    note "A blocked network/proxy is the usual cause; the download comes from the Mendix CDN."
  fi
}

if [ "$INSTALL" -eq 1 ]; then
  # What is actually missing? --install covers two tools: the project's ./mxcli (which every
  # MDL session needs anyway) and the mxbuild toolchain (which the gate needs).
  NEED_TOOLCHAIN=1
  if [ -n "$MXBUILD" ] && [ -x "$MXBUILD" ] && probe_runs "$MXBUILD"; then NEED_TOOLCHAIN=0; fi
  NEED_MXCLI=0
  PMXCLI="$(find_project_mxcli 2>/dev/null || true)"
  if [ -n "$PROJECT_DIR" ] && [ -z "$PMXCLI" ]; then
    NEED_MXCLI=1
  fi

  if [ "$NEED_TOOLCHAIN" -eq 0 ] && [ "$NEED_MXCLI" -eq 0 ]; then
    ok "--install: nothing to download — a runnable mxbuild and the project mxcli are in place"
  elif [ -z "$PROJECT_DIR" ]; then
    bad "--install needs a project directory: bin/doctor.sh --install <project-dir>"
    note "The download runs through that project's own ./mxcli, which reads the model's"
    note "Mendix version and fetches the matching toolchain."
  elif [ "$NEED_MXCLI" -eq 1 ] && [ "$PLATFORM" = gitbash ] && mxtk_is_elf "$PROJECT_DIR/mxcli"; then
    # Not a permissions problem, and chmod cannot fix it (Git Bash derives the executable bit
    # from the extension/header, so `chmod +x` looks like it "reverts"). The file is the Linux
    # build the Dev Container uses on this same folder. Windows needs mxcli.exe beside it.
    note "--install: $PROJECT_DIR/mxcli is the Linux build (the Dev Container's) — fine, leave it."
    note "Git Bash needs mxcli.exe next to it; fetching that now, the two coexist."
    NEED_MXCLI=1; PMXCLI=""
  elif [ -f "$PROJECT_DIR/mxcli" ] && [ ! -x "$PROJECT_DIR/mxcli" ] && [ "$PLATFORM" != gitbash ]; then
    bad "--install: mxcli in $PROJECT_DIR is present but not executable — chmod +x mxcli, re-run."
  else
    # The release assets follow one naming scheme (verified against the published releases,
    # 2026-08-31): mxcli-{darwin|linux}-{amd64|arm64}, mxcli-windows-amd64.exe. Windows gets
    # the .exe name so Git Bash's transparent foo -> foo.exe mapping serves the project
    # convention ./mxcli unchanged. $MXCLI_VERSION pins a release tag (e.g. v0.16.0) for
    # teams that standardise; default is latest.
    MXCLI_ARCH="$(uname -m 2>/dev/null || echo unknown)"
    case "$MXCLI_ARCH" in
      x86_64|amd64) MXCLI_ARCH=amd64 ;;
      arm64|aarch64) MXCLI_ARCH=arm64 ;;
    esac
    case "$PLATFORM-$MXCLI_ARCH" in
      macos-amd64)   MXCLI_ASSET="mxcli-darwin-amd64";      MXCLI_DEST="mxcli" ;;
      macos-arm64)   MXCLI_ASSET="mxcli-darwin-arm64";      MXCLI_DEST="mxcli" ;;
      linux-amd64|wsl-amd64) MXCLI_ASSET="mxcli-linux-amd64"; MXCLI_DEST="mxcli" ;;
      linux-arm64|wsl-arm64) MXCLI_ASSET="mxcli-linux-arm64"; MXCLI_DEST="mxcli" ;;
      gitbash-amd64) MXCLI_ASSET="mxcli-windows-amd64.exe"; MXCLI_DEST="mxcli.exe" ;;
      *)             MXCLI_ASSET=""; MXCLI_DEST="" ;;
    esac
    if [ -n "${MXCLI_VERSION:-}" ]; then
      MXCLI_URL="https://github.com/mendixlabs/mxcli/releases/download/$MXCLI_VERSION/${MXCLI_ASSET:-<asset>}"
    else
      MXCLI_URL="https://github.com/mendixlabs/mxcli/releases/latest/download/${MXCLI_ASSET:-<asset>}"
    fi
    if command -v curl >/dev/null 2>&1; then MXCLI_FETCH="curl -fsSL -o"
    elif command -v wget >/dev/null 2>&1; then MXCLI_FETCH="wget -q -O"
    else MXCLI_FETCH=""; fi

    if [ "$NEED_MXCLI" -eq 1 ] && { [ -z "$MXCLI_ASSET" ] || [ -z "$MXCLI_FETCH" ]; }; then
      bad "--install: no mxcli in $PROJECT_DIR and cannot auto-fetch one here"
      [ -z "$MXCLI_ASSET" ] && note "(no published mxcli build detected for $PLATFORM/$MXCLI_ARCH — if that"
      [ -z "$MXCLI_ASSET" ] && note " detection is wrong, pick your asset at github.com/mendixlabs/mxcli/releases)"
      [ -z "$MXCLI_FETCH" ] && note "(neither curl nor wget on this machine)"
      note "Download it yourself into the project root, then re-run:"
      note "  $MXCLI_URL"
      note "  chmod +x mxcli"
    else
      # ---- the plan, before anything is downloaded ------------------------------------
      # Downloading executables onto someone's machine is not a silent act: say what, from
      # where, how big, why, and what was detected — then get a yes. A wrong OS/arch guess,
      # a metered connection, or a company policy against fetching binaries are all things
      # only the human in front of the machine can judge.
      note ""
      note "--install plan — this machine is missing tools the toolkit needs, and doctor can"
      note "download them now. Nothing has been downloaded yet. The plan:"
      _STEP=0
      if [ "$NEED_MXCLI" -eq 1 ]; then
        _STEP=$((_STEP + 1))
        note "  $_STEP. mxcli (~90 MB) -> $PROJECT_DIR/$MXCLI_DEST"
        note "     the MDL CLI every session here uses; from $MXCLI_URL"
        [ -z "${MXCLI_VERSION:-}" ] && note "     (latest release — set MXCLI_VERSION=vX.Y.Z to pin the team's version)"
      fi
      if [ "$NEED_TOOLCHAIN" -eq 1 ]; then
        _STEP=$((_STEP + 1))
        note "  $_STEP. mxbuild toolchain (~800 MB, one-time) -> ~/.mxcli/mxbuild/<version>/"
        note "     verifies every model write (the exec.sh gate); from cdn.mendix.com, exact"
        note "     version read from the project's .mpr — the same download the container build uses."
        if [ "$NEED_MXCLI" -eq 0 ] && [ -n "$PMXCLI" ]; then
          _PLAN_MPR="$(ls "$PROJECT_DIR"/*.mpr 2>/dev/null | head -1)"
          [ -n "$_PLAN_MPR" ] && (cd "$PROJECT_DIR" && "$PMXCLI" setup mxbuild -p "$(basename "$_PLAN_MPR")" --dry-run 2>/dev/null) \
            | grep -E 'Version:|URL:' | while IFS= read -r l; do note "     $l"; done
        fi
      fi
      note "  Detected machine: $PLATFORM/$MXCLI_ARCH — if that looks wrong, answer no and use the"
      note "  URLs above by hand (a wrong-platform binary downloads fine and then cannot run)."
      note "  If your company restricts downloading executables, route these same URLs through"
      note "  your approved channel instead."
      # ---- consent --------------------------------------------------------------------
      CONSENT=0
      if [ "$ASSUME_YES" -eq 1 ]; then
        note "  (--yes given: proceeding)"
        CONSENT=1
      elif [ -t 0 ]; then
        printf '        Proceed with the download(s)? [y/N] '
        IFS= read -r _REPLY || _REPLY=""
        case "$_REPLY" in y|Y|yes|Yes|YES) CONSENT=1 ;; *) CONSENT=0 ;; esac
      else
        warn "--install: no terminal to ask on and no --yes — nothing downloaded."
        note "An unattended run needs the explicit flag: bin/doctor.sh --install --yes $PROJECT_DIR"
      fi

      if [ "$CONSENT" -eq 0 ]; then
        [ "$ASSUME_YES" -eq 0 ] && [ -t 0 ] && note "Understood — nothing downloaded. The URLs above work by hand too."
      else
        MXCLI_READY=1
        if [ "$NEED_MXCLI" -eq 1 ]; then
          note "fetching $MXCLI_ASSET from the mxcli releases..."
          if $MXCLI_FETCH "$PROJECT_DIR/$MXCLI_DEST" "$MXCLI_URL" && chmod +x "$PROJECT_DIR/$MXCLI_DEST" \
             && probe_runs "$PROJECT_DIR/$MXCLI_DEST"; then
            ok "mxcli fetched into the project root: $(probe_line)"
            PMXCLI="$PROJECT_DIR/$MXCLI_DEST"
          else
            rm -f "$PROJECT_DIR/$MXCLI_DEST" 2>/dev/null
            MXCLI_READY=0
            bad "--install: fetching mxcli failed (network/proxy, or the binary would not run here)."
            note "Download it yourself into the project root, then re-run:  $MXCLI_URL"
          fi
        fi
        if [ "$NEED_TOOLCHAIN" -eq 1 ] && [ "$MXCLI_READY" -eq 1 ]; then
          install_toolchain
        fi
      fi
    fi
  fi
fi

GATE_OK=1

# Studio Pro install (the root mxbuild and the bundled JRE are discovered under).
if [ -n "$SP_APP" ]; then
  ok "Studio Pro install: $SP_APP"
elif [ "$PLATFORM" = linux ]; then
  warn "no Studio Pro install (none exists for Linux)."
  note "A standalone mxbuild works instead: bin/doctor.sh --install <project-dir> downloads"
  note "one to ~/.mxcli (the container build's toolchain), or set MXBUILD_PATH=/path/to/mxbuild."
else
  # Severity depends on whether the standalone toolchain covers for it below.
  if [ -n "$MXBUILD" ] && [ -x "$MXBUILD" ]; then
    warn "no Studio Pro install found — running on the downloaded toolchain instead (fine for"
    note "the mxbuild gate; you still need Studio Pro to open the model yourself)."
  else
    bad "no Studio Pro install found — mxbuild and its bundled Java live inside it."
    note "Two ways out:"
    note "  1. No Studio Pro needed for the gate: bin/doctor.sh --install <project-dir>"
    note "     downloads the standalone toolchain (same one the headless container build uses)."
    note "  2. Install Mendix Studio Pro, or point past the discovery:"
    note "     MENDIX_APP=<install root>   (macOS: /Applications/Mendix Studio Pro X.Y.Z.app,"
    note "                                  Windows: C:/Program Files/Mendix/X.Y.Z)"
    note "     MXBUILD_PATH=<mxbuild binary>   JAVA_HOME=<jdk/jre root>"
  fi
fi

# mxbuild: present, executable, AND RUNS. Presence alone has lied before — a wrong-platform
# binary sits at the right path, exits 126 on invocation, and a careless reading of "0 errors
# reported" becomes a false green. Execute it and read the exit code (probe_runs above — a
# failed --version alone is NOT "cannot run").
if [ -n "$MXBUILD" ] && [ -x "$MXBUILD" ]; then
  MXB_EXIT=0
  probe_runs "$MXBUILD" || MXB_EXIT=$?
  if [ "$MXB_EXIT" -eq 0 ]; then
    ok "mxbuild runs ($PROBE_HOW): $(probe_line)"
    note "at: $MXBUILD"
  else
    GATE_OK=0
    bad "mxbuild exists but cannot run (exit $MXB_EXIT): $MXBUILD"
    printf '%s\n' "$PROBE_OUT" | grep -v '^[[:space:]]*$' | head -3 | while IFS= read -r l; do note "  $l"; done
    note "Exit 126 usually means a binary built for another platform/architecture."
  fi
else
  GATE_OK=0
  if [ "$PLATFORM" = linux ]; then
    warn "mxbuild not found/executable: ${MXBUILD:-<none>}"
  else
    bad "mxbuild not found/executable: ${MXBUILD:-<none>}"
  fi
  note "Have Studio Pro? Point at it: MENDIX_APP=<its version folder> in toolkit.env (see above)."
  note "No Studio Pro: bin/doctor.sh --install <project-dir> downloads a standalone mxbuild,"
  note "like the container build. MXBUILD_PATH=<path to mxbuild> also works."
fi

# Java: mxbuild is invoked with an explicit --java-exe-path; if none resolves, the gate skips.
if [ -n "$JAVA_EXE" ] && [ -x "$JAVA_EXE" ]; then
  # -version writes to stderr, and wrappers can prepend noise (JAVA_TOOL_OPTIONS pickup
  # lines); take the line that actually names a version, not merely the first.
  JV="$("$JAVA_EXE" -version 2>&1 | grep -i 'version' | head -1)" || JV=""
  if [ -n "$JV" ]; then
    ok "java runs: $JV  ($JAVA_EXE)"
    # mxbuild compiles the model's Java actions, which takes javac — a JRE has none. Studio
    # Pro's bundled runtime is a JRE that mxbuild is paired with, so only flag a system Java.
    case "$JAVA_HOME_FOUND" in
      "${SP_APP:-<none>}"/*) ;;
      *) if [ ! -x "$(dirname "$JAVA_EXE")/javac" ] && [ ! -x "$(dirname "$JAVA_EXE")/javac.exe" ]; then
           note "this Java is a JRE (no javac). Java actions in the model need a JDK to compile:"
           note "set JAVA_HOME=<a JDK 21 folder> in toolkit.env if a build complains about javac."
         fi ;;
    esac
  else
    GATE_OK=0
    bad "java exists but produced no version output: $JAVA_EXE"
  fi
else
  GATE_OK=0
  if [ "$PLATFORM" = linux ] && [ -z "$SP_APP" ]; then
    warn "java not found (looked for JAVA_HOME, Studio Pro's bundled JRE, then PATH)."
    note "The downloaded mxbuild toolchain needs a system Java: apt install openjdk-21-jre"
    note "(or your distro's equivalent), or set JAVA_HOME=<jdk/jre root>."
  else
    bad "java not found/executable: ${JAVA_EXE:-<none>}"
    note "Studio Pro ships its own JRE and that is the preferred one; if discovery missed it,"
    note "set JAVA_HOME=<jdk/jre root> explicitly. No Studio Pro? Install a JDK/JRE 21:"
    note "macOS: brew install --cask temurin@21   Windows: winget install EclipseAdoptium.Temurin.21.JRE"
  fi
fi

if [ "$GATE_OK" -eq 1 ] && [ -n "$MXBUILD" ] && [ -x "$MXBUILD" ]; then
  ok "exec.sh mxbuild gate WILL RUN on this machine — model writes get verified."
else
  # Same fact, platform-matched severity: on Linux there is no Studio Pro to install, so a
  # skipping gate is expected (WARN) unless the user provides a standalone mxbuild. On the
  # platforms Studio Pro runs on, a skipping gate is the training-round failure itself.
  if [ "$PLATFORM" = linux ] && [ -z "$SP_APP" ] && [ -z "${MXBUILD_PATH:-}" ]; then
    warn "exec.sh mxbuild gate WILL BE SKIPPED on this machine."
  else
    bad "the mxbuild gate would be skipped on this machine — sort out the mxbuild/java lines"
    note "above before the first model write, so every write gets verified."
  fi
  note "Why it matters: without mxbuild, MDL execs report gate=skipped and consistency errors"
  note "go uncaught until Studio Pro opens the model. Usually one of these fixes it:"
  note "  - Studio Pro is installed: put its folder in toolkit.env, e.g."
  note "      MENDIX_APP=C:\\Program Files\\Mendix\\11.11.0   (pick the version your .mpr uses)"
  note "  - No Studio Pro here: bin/doctor.sh --install <project-dir> downloads a standalone"
  note "    mxbuild (the same one the container build uses)."
fi

if [ "$QUICK" != 1 ]; then
# --- node -----------------------------------------------------------------------------------

head_ "Node.js (pipelines, page fidelity, e2e)"

NODE_V="$(node --version 2>/dev/null)" || NODE_V=""
if [ -n "$NODE_V" ]; then
  ok "node $NODE_V"
else
  warn "node is missing. Needed by the extraction pipelines (npm install per pipeline),"
  note "project-bin/page-fidelity.js, and Playwright e2e (project-bin/test-stack-up.sh)."
  note "Not needed for a pure MDL-writing session. To install: an LTS from nodejs.org,"
  note "or brew install node / winget install OpenJS.NodeJS.LTS / apt install nodejs npm."
fi
note "e2e additionally needs a Playwright browser in the project: npx playwright install chromium"

# --- self-verification (container runtime) ---------------------------------------------------

head_ "Self-verification stack (container runtime — recommended)"

# With a container runtime, the loop closes without a human: after a build the agent runs a
# Linux build of the app, brings up Postgres + the app (project-bin/test-stack-up.sh), drives
# it with Playwright, screenshots the pages, and verifies its own work — nobody has to open
# Studio Pro to find out whether a page renders. Without one the mxbuild gate still verifies
# the MODEL, but nothing verifies the RUNNING APP unless a human does. Recommended, never
# required — hence WARN, not FAIL.
#
# DOCKER *OR* PODMAN. This section used to advertise Podman in its advice text while every
# probe ran `docker` only — so a machine running Podman without the docker shim was told
# "docker is not installed", and on a team that cannot licence Docker Desktop that reads as
# "go install software you are not allowed to have". (Field data point: a colleague's
# machine-ready status carried "Docker not installed" as a known issue; they may well have had
# Podman all along.) Detection order: docker first when present — including when it IS a Podman
# shim, which is transparent and correct — then podman.
CONTAINER_RUNTIME="${MXTK_CONTAINER_RUNTIME:-}"
if [ -z "$CONTAINER_RUNTIME" ]; then
  if command -v docker >/dev/null 2>&1; then CONTAINER_RUNTIME=docker
  elif command -v podman >/dev/null 2>&1; then CONTAINER_RUNTIME=podman
  fi
fi
# What to call it in the report. Docker has a daemon; podman normally does not, so "podman
# daemon" would be wrong — the label carries that difference, and the runtime is NAMED in the
# output so a user can tell which one doctor actually found.
case "$CONTAINER_RUNTIME" in
  docker)
    RUNTIME_LABEL="docker daemon"
    RUNTIME_PROBING="the docker daemon"
    RUNTIME_DOWN="docker is installed but the docker daemon is not responding." ;;
  *)
    RUNTIME_LABEL="$CONTAINER_RUNTIME"
    RUNTIME_PROBING="$CONTAINER_RUNTIME"
    RUNTIME_DOWN="$CONTAINER_RUNTIME is installed but not responding." ;;
esac

# container_daemon_up — `<runtime> info`, bounded. When Docker Desktop is installed but not
# running, the CLI can sit on its socket/named pipe with no output for minutes (macOS and Git
# Bash both reported, 2026-09-09) — and since init-project.sh runs doctor last, the whole
# scaffold read as hung. A stopped `podman machine` stalls the same way, so podman goes through
# the same bound. No `timeout` on stock macOS, so: background the probe, poll once a second,
# kill it at the bound. Returns 0 up · 1 down (answered quickly) · 2 no answer within the bound.
container_daemon_up() {
  "$CONTAINER_RUNTIME" info >/dev/null 2>&1 &
  _dd_pid=$!
  _dd_waited=0
  while kill -0 "$_dd_pid" 2>/dev/null; do
    if [ "$_dd_waited" -ge "$DOCKER_PROBE_SECS" ]; then
      kill "$_dd_pid" 2>/dev/null; wait "$_dd_pid" 2>/dev/null
      return 2
    fi
    sleep 1; _dd_waited=$((_dd_waited + 1))
  done
  wait "$_dd_pid"
}

# container_start_hint — the one command that starts this runtime on this platform, or the
# closest thing to it. Printed instead of "start Docker", which sent people to look for a
# button — and a Podman user must never be sent to look for Docker Desktop at all.
container_start_hint() {
  if [ "$CONTAINER_RUNTIME" = podman ]; then
    case "$PLATFORM" in
      macos|gitbash)
        note "  podman machine start    # the VM podman runs containers in; ~15-60 s"
        note "  (podman machine init first, if this machine has never had one)" ;;
      linux|wsl)
        note "  systemctl --user start podman.socket   # rootless; or sudo systemctl start podman.socket"
        note "  (rootless podman often needs no service at all — check 'podman info' by hand)" ;;
      *) note "  start the podman machine/service, then re-run this script" ;;
    esac
  else
    case "$PLATFORM" in
      macos)
        if [ -d /Applications/Docker.app ]; then note "  open -a Docker          # Docker Desktop; the daemon needs ~30-90 s after launch"
        elif command -v colima >/dev/null 2>&1; then note "  colima start"
        else note "  open -a Docker (Docker Desktop) or colima start — whichever is installed"; fi ;;
      gitbash)
        note '  start "" "C:\Program Files\Docker\Docker\Docker Desktop.exe"   # then wait ~30-90 s'
        note "  (or Rancher Desktop / Podman Desktop from the Start menu)" ;;
      linux|wsl)
        note "  sudo systemctl start docker     # or, on WSL, start Docker Desktop on the Windows side" ;;
      *) note "  start Docker Desktop / the docker service, then re-run this script" ;;
    esac
  fi
  note "Then re-run: bin/doctor.sh${PROJECT_DIR:+ $PROJECT_DIR}   (this section is skipped by --quick)"
}

if [ "$NO_DOCKER" = 1 ]; then
  note "docker probe skipped (--no-docker / MXTK_DOCTOR_SKIP_DOCKER=1). Self-verification stack not checked."
elif [ -n "$CONTAINER_RUNTIME" ]; then
  note "probing $RUNTIME_PROBING (bounded: ${DOCKER_PROBE_SECS} s — a stopped runtime can otherwise hang here)..."
  DOCKER_STATE=0
  container_daemon_up || DOCKER_STATE=$?
  case "$DOCKER_STATE" in
    0)
      ok "$RUNTIME_LABEL responding — mxcli docker check + test-stack-up.sh (app up, e2e, screenshots) available" ;;
    2)
      warn "$CONTAINER_RUNTIME is installed but '$CONTAINER_RUNTIME info' gave no answer within ${DOCKER_PROBE_SECS} s — treated as not running."
      note "That silent wait is what makes a setup look hung. Raise the bound with"
      note "MXTK_DOCKER_PROBE_SECS=30 if it is merely slow to answer here. To start it:"
      container_start_hint ;;
    *)
      warn "$RUNTIME_DOWN"
      note "Until it runs: no app container, no throwaway Postgres, no agent-driven e2e/screenshots."
      note "To start it:"
      container_start_hint ;;
  esac
  # --install is the "do it for me" mode: on macOS with Docker Desktop present, launch it.
  # Never elsewhere — Windows launch paths vary and Linux needs sudo. Podman is left alone:
  # `podman machine start` on a machine that has never run `podman machine init` is not a safe
  # guess to make on someone's behalf.
  if [ "$DOCKER_STATE" != 0 ] && [ "$INSTALL" = 1 ] && [ "$CONTAINER_RUNTIME" = docker ] && [ "$PLATFORM" = macos ] && [ -d /Applications/Docker.app ]; then
    if open -a Docker 2>/dev/null; then
      note "--install: launched Docker Desktop (open -a Docker). Give it ~30-90 s, then re-run doctor."
    fi
  fi
else
  warn "no container runtime found — neither docker nor podman. One is recommended for new builders."
  note "It is what lets the agent verify its own build: 'mxcli docker check' (deep model+build"
  note "verification) and project-bin/test-stack-up.sh (Postgres + the app up, Playwright e2e,"
  note "page screenshots) both need it. Without it, only mxbuild verifies the model and a human"
  note "must open Studio Pro to see whether anything actually renders."
  note "No-container fallback for just running the app: 'mxcli run --local' against a native"
  note "PostgreSQL (host:PORT)."
  note "Docker Desktop needs a paid licence at larger companies, and is NOT required: Podman is"
  note "the licence-free option (docker-CLI compatible; doctor probes it directly, so no docker"
  note "shim is needed). Rancher Desktop and colima (macOS) are the other common substitutes."
fi

fi

# --- spawn speed (git bash) -----------------------------------------------------------------

# gate-check.sh + the obligation check fork over a thousand subprocesses per run. On a healthy
# machine a fork is ~1-3 ms and the run takes seconds; observed on a managed Windows laptop:
# 152 ms per fork, which turns the same run into a 5-15 minute "hang" (see the header of
# bin/lib/obligation-check.sh). Measure it once here so slow reads as "this machine", not
# "the toolkit is broken".
# In --quick mode measure on every platform: a corporate endpoint agent on macOS, or an
# overloaded container, shows the same symptom, and the number is what makes "slow" actionable.
if [ "$PLATFORM" = gitbash ] || [ "$QUICK" = 1 ]; then
  head_ "Process spawn speed"
  T0="$(date +%s%N 2>/dev/null || echo x)"
  case "$T0" in
    *[!0-9]*) note "cannot measure spawn speed (no nanosecond clock in this date)" ;;
    *)
      i=0
      while [ "$i" -lt 25 ]; do _="$(true)"; i=$((i + 1)); done
      T1="$(date +%s%N)"
      MS_PER_FORK=$(( (T1 - T0) / 25 / 1000000 ))
      if [ "$MS_PER_FORK" -le 40 ]; then
        ok "~${MS_PER_FORK} ms per subprocess — gate-check will run in normal time"
      else
        warn "~${MS_PER_FORK} ms per subprocess — gate-check.sh will feel HUNG (minutes, not seconds)."
        note "The usual causes, in order:"
        note "  - Windows Defender real-time scanning every process start. Ask IT to exclude"
        note "    the Git Bash install directory and this repo's folder."
        note "  - The repo living under OneDrive/Dropbox (every file touch syncs)."
        note "  - Corporate endpoint agents hooking process creation."
      fi
      ;;
  esac
fi

# --- path hygiene ---------------------------------------------------------------------------

for p in "$TOOLKIT_ROOT" "${PROJECT_DIR:+$PROJECT_DIR}"; do
  [ -n "$p" ] || continue
  case "$p" in
    *OneDrive*|*onedrive*)
      head_ "Path hygiene"
      warn "$p is under OneDrive. Sync fights every model write and slows every script;"
      note "move the folder outside OneDrive." ;;
  esac
  case "$p" in
    *" "*)
      warn "path contains a space: $p"
      note "Most toolkit scripts quote correctly, but tooling invoked underneath (npm, java"
      note "launchers) has a long history of not doing so. A space-free path avoids the class." ;;
  esac
done

# --- project ------------------------------------------------------------------------------

if [ -n "$PROJECT_DIR" ]; then
  head_ "Project: $PROJECT_DIR"
  if [ ! -d "$PROJECT_DIR" ]; then
    bad "not a directory"
  else
    [ -f "$PROJECT_DIR/CLAUDE.local.md" ] && ok "CLAUDE.local.md (toolkit wiring) present" \
      || warn "no CLAUDE.local.md — run bin/init-project.sh '$PROJECT_DIR'"
    MPR="$(ls "$PROJECT_DIR"/*.mpr 2>/dev/null | head -1)"
    # Two-tree checkout (cloud-dev-environment.md: `mxcli new --output-dir ./app`) — the app
    # lives under app/. Reported "no .mpr found" on a healthy pilot, 2026-09-04.
    [ -n "$MPR" ] || MPR="$(ls "$PROJECT_DIR"/app/*.mpr 2>/dev/null | head -1)"
    [ -n "$MPR" ] && ok "model: ${MPR#$PROJECT_DIR/}" || {
      warn "no .mpr found in the project root"
      note "If the model lives elsewhere, point doctor at the folder that contains it;"
      note "a brand-new project gets its .mpr from 'mxcli init' or a Studio Pro export."; }
    PMXCLI_PROBE="$(find_project_mxcli 2>/dev/null || true)"
    if [ -n "$PMXCLI_PROBE" ]; then
      # Present is not enough — a wrong-platform binary is present, executable, and exits 126.
      MXCLI_EXIT=0
      probe_runs "$PMXCLI_PROBE" || MXCLI_EXIT=$?
      if [ "$MXCLI_EXIT" -eq 0 ]; then
        ok "mxcli runs ($PROBE_HOW): $(probe_line)"
        note "at: $PMXCLI_PROBE"
      else
        bad "mxcli exists but cannot run (exit $MXCLI_EXIT): $PMXCLI_PROBE"
        printf '%s\n' "$PROBE_OUT" | grep -v '^[[:space:]]*$' | head -3 | while IFS= read -r l; do note "  $l"; done
        note "Exit 126 usually means a binary built for another platform/architecture —"
        note "re-download the mxcli build for this OS."
      fi
    elif [ "$PLATFORM" = gitbash ] && mxtk_is_elf "$PROJECT_DIR/mxcli"; then
      warn "the project's mxcli is the Linux build (the Dev Container's) — Git Bash needs mxcli.exe beside it."
      note "Not a permissions problem: chmod cannot make a Linux binary run here, which is why it"
      note "looked like it 'reverted'. Leave the file for the container and add the Windows build:"
      note "  bin/doctor.sh --install $PROJECT_DIR      (fetches mxcli.exe; the two coexist)"
      note "  or copy the mxcli.exe you already have on PATH into the project root."
    elif [ -f "$PROJECT_DIR/mxcli" ]; then bad "mxcli is present but not executable — chmod +x mxcli"
    else
      warn "no mxcli in the project root"
      note "bin/doctor.sh --install $PROJECT_DIR fetches the right build for this OS/arch"
      note "(from github.com/mendixlabs/mxcli/releases) and then the mxbuild toolchain with it."
    fi
  fi
fi

# --- gate self-test ---------------------------------------------------------------------------
#
# WHY THIS SECTION EXISTS. exec.sh's mxbuild gate has, in the field, silently reported "?" and
# applied real errors with exit 0 — a wrong-architecture mxbuild once reported 0 errors for
# several commits before anyone noticed (merge desk, after Marco Keijsers' #59 and the July
# wrong-arch mxbuild incident). Every section above this one answers "is mxbuild present and
# does it run" — none of them answers "if the model actually had an error, would the gate SEE
# it". This one does: it runs the exact function exec.sh's gate and pre-flight baseline both
# trust (mxtk_mxbuild_error_count, project-bin/_common.sh — the mandatory chain step producing
# every count this section reads) against a SCRATCH COPY of the real project model, first
# clean, then with a deliberately-broken microflow injected via the project's own mxcli, and
# requires the count to go from a real 0 to a real >=1. A gate that cannot tell those two states
# apart is worse than no gate at all: it reports green on a broken build.
#
# The project's own .mpr/mprcontents are never touched — this runs entirely inside a scratch
# directory, removed on every exit path via a RETURN trap (bash), not just the happy path.
#
# THE SCRATCH COPY IS THE WHOLE MODEL DIRECTORY, NOT JUST .mpr + mprcontents/. Two field
# reports (an Atlas project on Mendix 11.14.0 with mxcli v0.23.0, Windows 11; and a project
# with a custom theme on Mendix 11.12.4, macOS) both saw this self-test FAIL with a dirty
# baseline — 1000+ `Could not find widget ...` / design-property errors, every one of them
# from Atlas_Web_Content page templates or the custom theme — while the real gate (exec.sh /
# verify-model.sh, which run mxbuild --target=deploy IN PLACE against the project as it sits
# on disk) passed with 0 errors on the identical model. A --target=deploy build resolves
# widget/theme/design-property references out of theme/, resources/, widgets/ and javasource/
# sitting BESIDE the .mpr; a copy of only .mpr + mprcontents/ cannot see any of them, so it
# fails on resources that were never actually broken. Options weighed and why they lost:
#   A. mxbuild --target=check (skip resource resolution). No evidence this target exists —
#      grepped bin/, project-bin/, skills/, bug-logs/: every real gate in this toolkit runs
#      --target=deploy, and nothing here has ever invoked --target=check.
#   B. A sibling .mpr copied into the project's OWN directory. Unsafe, not chosen: MPR v2
#      stores its content in mprcontents/ beside the .mpr, so a second .mpr dropped next to
#      the real one collides with the project's own mprcontents/ — this would risk corrupting
#      the very model it is meant to leave untouched.
#   (Symlinks into the project tree instead of copying were also considered and rejected:
#   Git Bash on Windows silently COPIES through a symlink instead of linking it, unless
#   MSYS=winsymlinks is set on that machine — nothing here can assume it is.)
#   C. Copy the whole project tree. Chosen, scoped down: copy the directory that holds the
#   .mpr (dirname "$MPR" — the project root on a single-tree checkout, app/ on a two-tree one,
#   CLAUDE.md "Shipping an instrument" rule 2), minus .git/, deployment/, node_modules/ and
#   .mpr-snapshots/ — none of which mxbuild reads, and the last of which can itself hold
#   several full mprcontents/ copies. The model's real basename is preserved automatically,
#   because every sibling is copied as-is (a renamed .mpr makes mxbuild bail before it writes
#   an error file at all — reported 2026-09-22, the basename fix below). This measures nothing
#   it cannot afford: the copied size is printed (du -sh) so a user sees the cost before the
#   next run, not after.
#
# Skipped under --quick (two extra mxbuild runs); force it with `bin/doctor.sh --gate-selftest
# [project-dir]`, which also works stood alone without waiting through the rest of doctor.
# Bounded by DOCTOR_GATE_TIMEOUT (default 300s) via mxtk_mxbuild_error_count. exec.sh's own
# gate is unbounded by default (MXTK_GATE_TIMEOUT) — a slow real build must never be mistaken
# for a failed one and restored; only this throwaway copy gets a clock.

GATE_SELFTEST_LINE=""

if [ "$QUICK" != 1 ] || [ "$GATE_SELFTEST" = 1 ]; then

head_ "Gate self-test (can the mxbuild gate actually see an error?)"

gate_selftest() {
  local scratch scratch_mpr t0 t1 elapsed mdl model_dir base_count bad_count rc timeout_s
  local copy_excl copy_ok entry entry_name x copy_size
  timeout_s="${DOCTOR_GATE_TIMEOUT:-300}"
  t0=$(date +%s)

  if [ -z "$PROJECT_DIR" ] || [ -z "${MPR:-}" ]; then
    note "NOT RUN — no project / no .mpr given (pass a project dir to doctor.sh to enable this)"
    GATE_SELFTEST_LINE="not-run (no project/.mpr)"
    return 0
  fi
  if [ ! -x "$MXBUILD" ] || [ ! -x "$JAVA_EXE" ]; then
    note "NOT RUN — mxbuild/java not resolved (see 'Build toolchain' above)"
    GATE_SELFTEST_LINE="not-run (no mxbuild)"
    return 0
  fi
  if [ -z "${PMXCLI_PROBE:-}" ]; then
    note "NOT RUN — no project mxcli resolved (see 'Project' above)"
    GATE_SELFTEST_LINE="not-run (no mxcli)"
    return 0
  fi

  scratch="$(mktemp -d /tmp/doctor-gate-selftest.XXXXXX)" || {
    bad "gate self-test: could not create a scratch directory"
    GATE_SELFTEST_LINE="fail (no scratch dir)"
    return 0
  }
  trap 'rm -rf "$scratch" 2>/dev/null' RETURN

  # Copy the WHOLE model directory — .mpr, mprcontents/, theme/, resources/, widgets/,
  # javasource/, everything a --target=deploy build reads off disk beside the .mpr — minus
  # what it never reads. See the section header above ("THE SCRATCH COPY IS THE WHOLE MODEL
  # DIRECTORY") for the two field reports this fixes and the options it was weighed against.
  # The model's REAL basename is preserved automatically because every sibling, the .mpr
  # included, is copied as itself: mprcontents/ carries an internal record of the .mpr's own
  # name, and a renamed copy makes mxbuild bail BEFORE it writes any error file at all — which
  # this self-test would then report as "gate cannot read mxbuild's error file", a false FAIL
  # on a healthy gate (reported 2026-09-22 by Yvann).
  model_dir="$(dirname "$MPR")"
  copy_excl=".git deployment node_modules .mpr-snapshots"
  copy_ok=1
  for entry in "$model_dir"/* "$model_dir"/.[!.]*; do
    [ -e "$entry" ] || continue
    entry_name="$(basename "$entry")"
    for x in $copy_excl; do
      [ "$entry_name" = "$x" ] && continue 2
    done
    cp -R "$entry" "$scratch/" 2>/dev/null || copy_ok=0
  done
  scratch_mpr="$scratch/$(basename "$MPR")"
  if [ "$copy_ok" -ne 1 ] || [ ! -e "$scratch_mpr" ]; then
    bad "gate self-test: could not copy the model directory into the scratch dir"
    GATE_SELFTEST_LINE="fail (copy failed)"
    return 0
  fi
  copy_size="$(du -sh "$scratch" 2>/dev/null | awk '{print $1}')"
  note "copied ${copy_size:-?} of project resources into the scratch dir (excluding .git, deployment/, node_modules/, .mpr-snapshots/)"

  # (a) Baseline: the gate must resolve SOME integer off this model, clean or not — "?" here
  # means the gate cannot read mxbuild's own output, which is the original F-042-class defect.
  base_count=$(mxtk_mxbuild_error_count "$scratch_mpr" "$timeout_s")
  rc=$?
  if [ "$rc" -eq 3 ]; then
    bad "gate self-test: mxbuild did not return within ${timeout_s}s (baseline run)"
    GATE_SELFTEST_LINE="fail (timeout)"
    return 0
  fi
  if [ "$base_count" = "?" ]; then
    bad "gate self-test: gate cannot read mxbuild's error file (baseline run) — a real error would go unseen"
    GATE_SELFTEST_LINE="fail (unreadable error file)"
    return 0
  fi
  ok "baseline: gate read $base_count error(s) off the scratch copy"

  # A dirty baseline makes the known-bad control meaningless: if the untouched copy already
  # reports errors, a self-test that later sees a HIGHER (but still nonzero) count on the
  # deliberately-broken copy proves nothing — the delta could be noise, not the injected error.
  if [ "$base_count" -ne 0 ] 2>/dev/null; then
    bad "gate self-test: baseline copy already reports $base_count error(s) — dirty model, the known-bad control cannot prove anything against it"
    GATE_SELFTEST_LINE="fail (dirty baseline: $base_count)"
    return 0
  fi

  # (b) Known-bad control: inject a deliberate type mismatch (CE0117 shape — assigning a String
  # literal to an Integer) via the project's OWN mxcli, throwaway module/microflow name, quoted
  # identifiers per this toolkit's MDL convention, and require the gate to see >=1 error. Zero
  # here means the gate is blind: it would report a genuinely broken model as clean.
  mdl="$scratch/gate-selftest.mdl"
  cat > "$mdl" <<'MDL'
CREATE MODULE "DrGateSelftest";
CREATE MICROFLOW "DrGateSelftest"."MF_GateSelftest" ()
BEGIN
  DECLARE $Bad Integer = 0;
  SET $Bad = 'not-a-number';
END;
MDL
  # If mxcli refuses the injection (syntax rejected by a newer grammar, model locked, ...),
  # the copy is still clean and a 0 below would be a FALSE "blind" verdict — say NOT RUN.
  if ! "$PMXCLI_PROBE" exec "$mdl" -p "$scratch_mpr" >"$scratch/inject.out" 2>&1; then
    warn "gate self-test: NOT RUN — the project's mxcli refused the known-bad injection:"
    sed 's/^/      /' "$scratch/inject.out" | head -5
    GATE_SELFTEST_LINE="not-run (injection refused)"
    return 0
  fi

  bad_count=$(mxtk_mxbuild_error_count "$scratch_mpr" "$timeout_s")
  rc=$?
  if [ "$rc" -eq 3 ]; then
    bad "gate self-test: mxbuild did not return within ${timeout_s}s (known-bad run)"
    GATE_SELFTEST_LINE="fail (timeout)"
    return 0
  fi
  if [ "$bad_count" = "?" ]; then
    bad "gate self-test: gate cannot read mxbuild's error file (known-bad run) — a real error would go unseen"
    GATE_SELFTEST_LINE="fail (unreadable error file)"
    return 0
  fi
  if [ "$bad_count" -eq 0 ] 2>/dev/null; then
    bad "gate self-test: gate is blind — a known-bad model (CE0117 type mismatch) reports clean"
    GATE_SELFTEST_LINE="fail (blind)"
    return 0
  fi
  # The count must have actually MOVED off the (already-verified-zero) baseline — a gate that
  # reports the same constant nonzero count on both the clean and the deliberately-broken copy
  # would pass an `-eq 0` check by luck while never having read the injected error at all.
  if [ "$bad_count" -le "$base_count" ] 2>/dev/null; then
    bad "gate self-test: gate is blind — known-bad copy reports $bad_count error(s), no higher than the $base_count baseline"
    GATE_SELFTEST_LINE="fail (blind: bad=$bad_count base=$base_count)"
    return 0
  fi

  t1=$(date +%s); elapsed=$(( t1 - t0 ))
  ok "known-bad control: gate read $bad_count error(s) off the deliberately-broken copy (${elapsed}s)"
  GATE_SELFTEST_LINE="pass (baseline=$base_count known-bad=$bad_count ${elapsed}s)"
  return 0
}

gate_selftest

fi

# --- verdict ---------------------------------------------------------------------------------

head_ "Verdict"

# Leave a dated receipt in the project so gate-check can tell "doctor ran and passed" from
# "nobody ever ran doctor here". Informational only — nothing gates on it, because a machine
# check must never turn into a stage verdict.
if [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ]; then
  if [ "$FAIL" -gt 0 ]; then RECEIPT_VERDICT=fail
  elif [ "$WARN" -gt 0 ]; then RECEIPT_VERDICT=warn
  else RECEIPT_VERDICT=ok; fi
  mkdir -p "$PROJECT_DIR/.claude" 2>/dev/null || true
  # Line 2 is the environment fingerprint: mxcli version, mxbuild path, arch. exec.sh re-runs
  # `doctor.sh --quick` when it changes or the receipt is over a day old (warn-only).
  FP_MXCLI="$( [ -x "$PROJECT_DIR/mxcli" ] && "$PROJECT_DIR/mxcli" --version 2>/dev/null | head -1 || echo none)"
  { printf '%s %s fail=%s warn=%s%s\n' "$(date '+%Y-%m-%d %H:%M')" "$RECEIPT_VERDICT" "$FAIL" "$WARN" "$( [ "$QUICK" = 1 ] && echo ' quick')"
    printf 'fingerprint: %s | %s | %s\n' "$FP_MXCLI" "${MXBUILD:-no-mxbuild}" "$(uname -sm)"
    [ -n "$GATE_SELFTEST_LINE" ] && printf 'gate-selftest: %s\n' "$GATE_SELFTEST_LINE"
  } > "$PROJECT_DIR/.claude/.doctor-receipt" 2>/dev/null || true
  # The receipt is MACHINE-LOCAL by design (like .guide-shown): committing one machine's
  # receipt would satisfy gate-check's doctor-ran probe on every other machine. Since this
  # script creates the file, it also keeps it out of git — otherwise every wired project
  # trips clean-tree hooks on an untracked file doctor itself wrote (field case: a stop
  # hook demanding it be committed, 2026-09-02).
  if [ -d "$PROJECT_DIR/.git" ] && ! git -C "$PROJECT_DIR" check-ignore -q .claude/.doctor-receipt 2>/dev/null; then
    printf '\n# Machine-local toolkit marker (doctor.sh preflight receipt)\n/.claude/.doctor-receipt\n' \
      >> "$PROJECT_DIR/.gitignore" 2>/dev/null || true
    note "(added /.claude/.doctor-receipt to the project's .gitignore — the receipt is machine-local)"
  fi
  # toolkit.env holds this machine's paths — never something to commit.
  if [ -d "$PROJECT_DIR/.git" ] && ! git -C "$PROJECT_DIR" check-ignore -q .claude/toolkit.env 2>/dev/null; then
    printf '\n# Machine-local tool locations (bin/doctor.sh / project-bin/_common.sh)\n/.claude/toolkit.env\n' \
      >> "$PROJECT_DIR/.gitignore" 2>/dev/null || true
    note "(added /.claude/toolkit.env to the project's .gitignore — it holds this machine's paths)"
  fi
fi

if [ "$FAIL" -gt 0 ]; then
  printf '  %s thing(s) to sort out before the first model write (FAIL lines), %s note(s) worth reading (WARN).\n' "$FAIL" "$WARN"
  printf '  Analysis and planning stages run fine meanwhile; each FAIL line says what fixes it.\n'
  exit 2
elif [ "$WARN" -gt 0 ]; then
  printf '  Ready. %s warning(s) above — read each one: some are optional, a missing .mpr or CLAUDE.local.md is not.\n' "$WARN"
  exit 1
else
  printf '  Ready.\n'
  exit 0
fi
