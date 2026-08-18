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
#   bin/doctor.sh                 # probe the machine
#   bin/doctor.sh <project-dir>   # also probe a specific project's wiring
#
# Exit: 0 = ready. 1 = warnings only, the toolkit will mostly work. 2 = something required is
# missing and a pipeline stage will fail.

set -u

TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="${1:-}"

FAIL=0
WARN=0

ok()   { printf '  ok    %s\n' "$*"; }
warn() { printf '  WARN  %s\n' "$*"; WARN=$((WARN + 1)); }
bad()  { printf '  FAIL  %s\n' "$*"; FAIL=$((FAIL + 1)); }
note() { printf '        %s\n' "$*"; }
head_() { printf '\n%s\n' "$*"; }

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
for f in "$TOOLKIT_ROOT"/bin/*.sh "$TOOLKIT_ROOT"/bin/lib/*.sh "$TOOLKIT_ROOT"/project-bin/*.sh \
         "$TOOLKIT_ROOT"/claude-hooks/hooks/*.sh "$TOOLKIT_ROOT"/claude-hooks/bin/*.sh; do
  [ -f "$f" ] || continue
  # Strip CR and compare with the original: any difference means the file carries CRs.
  if ! tr -d '\r' < "$f" | cmp -s - "$f"; then
    CRLF_HITS=$((CRLF_HITS + 1))
    [ -n "$CRLF_FIRST" ] || CRLF_FIRST="$f"
  fi
done

if [ "$CRLF_HITS" -gt 0 ]; then
  bad "$CRLF_HITS script(s) have Windows line endings (CRLF). They will not run."
  note "first one: $CRLF_FIRST"
  note "Every one fails on its first line with: \$'\\r': command not found"
  note "Fix, from the toolkit root:"
  note "  git config core.autocrlf false"
  note "  git rm --cached -r . && git reset --hard"
  note "The .gitattributes in this repo prevents it happening again on a fresh clone."
else
  ok "shell scripts are LF, as required"
fi

AUTOCRLF="$(git -C "$TOOLKIT_ROOT" config --get core.autocrlf 2>/dev/null || echo unset)"
case "$AUTOCRLF" in
  true) warn "git core.autocrlf=true. .gitattributes overrides it for *.sh, but set it false." ;;
  *)    ok "git core.autocrlf=$AUTOCRLF" ;;
esac

# --- command line tools ---------------------------------------------------------------------

head_ "Command line tools"

for c in git sed grep awk find sort tr cut; do
  command -v "$c" >/dev/null 2>&1 && ok "$c" || bad "$c is missing — it is used by nearly every script"
done

command -v sqlite3 >/dev/null 2>&1 && ok "sqlite3" || {
  warn "sqlite3 is missing. project-bin/graph-sweep.sh reads the mxcli catalog with it."
  note "macOS: preinstalled. Linux: apt install sqlite3. Windows: winget install SQLite.SQLite"; }

command -v shellcheck >/dev/null 2>&1 && ok "shellcheck (optional, for editing toolkit scripts)" \
  || note "shellcheck not installed — only needed if you edit toolkit scripts"

# --- studio pro -------------------------------------------------------------------------

head_ "Studio Pro automation"

case "$PLATFORM" in
  macos)
    if ls -d /Applications/Mendix\ Studio\ Pro*.app >/dev/null 2>&1; then
      ok "found: $(ls -d /Applications/Mendix\ Studio\ Pro*.app | tr '\n' ' ')"
    else
      warn "no 'Mendix Studio Pro *.app' in /Applications — project-bin/restart-sp.sh cannot run"
    fi
    ;;
  gitbash|wsl|linux|unknown)
    warn "The Studio Pro scripts (save-sp.sh, restart-sp.sh, and the SP handling in exec.sh)"
    note "are macOS-only: they are built on osascript, lsof and 'open -a', and Studio Pro is"
    note "discovered by looking in /Applications. There is no Windows port yet."
    note "Everything else in the toolkit works here. Drive Studio Pro by hand on this platform."
    ;;
esac

# --- project ------------------------------------------------------------------------------

if [ -n "$PROJECT_DIR" ]; then
  head_ "Project: $PROJECT_DIR"
  if [ ! -d "$PROJECT_DIR" ]; then
    bad "not a directory"
  else
    [ -f "$PROJECT_DIR/CLAUDE.local.md" ] && ok "CLAUDE.local.md (toolkit wiring) present" \
      || warn "no CLAUDE.local.md — run bin/init-project.sh '$PROJECT_DIR'"
    MPR="$(ls "$PROJECT_DIR"/*.mpr 2>/dev/null | head -1)"
    [ -n "$MPR" ] && ok "model: $(basename "$MPR")" || warn "no .mpr found in the project root"
    if [ -x "$PROJECT_DIR/mxcli" ]; then ok "mxcli present and executable"
    elif [ -f "$PROJECT_DIR/mxcli" ]; then bad "mxcli is present but not executable — chmod +x mxcli"
    else warn "no mxcli in the project root"; fi
  fi
fi

# --- verdict ---------------------------------------------------------------------------------

head_ "Verdict"
if [ "$FAIL" -gt 0 ]; then
  printf '  %s problem(s) that will break a pipeline stage, %s warning(s).\n' "$FAIL" "$WARN"
  printf '  Fix the FAIL lines above before running anything else.\n'
  exit 2
elif [ "$WARN" -gt 0 ]; then
  printf '  Ready, with %s warning(s). Read them — each one names something that will not work.\n' "$WARN"
  exit 1
else
  printf '  Ready.\n'
  exit 0
fi
