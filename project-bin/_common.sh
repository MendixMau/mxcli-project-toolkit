#!/usr/bin/env bash
# _common.sh — shared discovery for the project-local crash-net scripts.
#
# Sourced by exec.sh / snapshot-mpr.sh / restore-mpr.sh / restart-sp.sh /
# save-sp.sh. Not executable on its own.
#
# These scripts are installed INTO a project by bin/init-project.sh, so they
# cannot hardcode a project name, an .mpr filename, or a Studio Pro version —
# the copies they were promoted from hardcoded all three.
#
# Bash 3.2 compatible on purpose: `env bash` on stock macOS is 3.2.57. No
# mapfile, no readarray, no associative arrays, no ${var,,}.

# Resolve the project root. Three tiers, because these scripts run from two places.
#
#   1. $PROJECT_ROOT, if the caller set it — always wins.
#   2. The sourcing script's location (bin/ -> ..), when that parent IS a project.
#      This is the installed-copy case: <project>/bin/verify-module.sh.
#   3. The current directory's project root, found by walking up for an .mpr.
#
# Tier 3 is why this is not a one-liner any more. The toolkit's own copy of these
# scripts used to resolve tier 2 to the TOOLKIT, so running
#     ~/mxcli-project-toolkit/project-bin/verify-module.sh <Module>
# from inside a project pointed every instrument at the toolkit, which has no .mpr
# and no tests/e2e — and the run reported instrument faults rather than saying the
# obvious thing, that it was aimed at the wrong directory. Copying the script into
# every project was the workaround. Tier 3 removes the need for it: the shared
# toolkit copy now works from inside any wired project, no env var, no install.
_mxtk_resolve_root() {
  local self_parent d
  self_parent=$(cd "$(dirname "${BASH_SOURCE[2]:-${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}}")/.." 2>/dev/null && pwd)
  # tier 2: the script sits in a real project's bin/
  if [ -n "$self_parent" ] && ls "$self_parent"/*.mpr >/dev/null 2>&1; then
    printf '%s\n' "$self_parent"; return 0
  fi
  # tier 3: walk up from $PWD looking for the .mpr
  d=$(pwd)
  while [ "$d" != "/" ]; do
    if ls "$d"/*.mpr >/dev/null 2>&1; then printf '%s\n' "$d"; return 0; fi
    d=$(dirname "$d")
  done
  # nothing found: keep the old behaviour so the caller's own error is the one seen
  printf '%s\n' "${self_parent:-$(pwd)}"
}
PROJECT_ROOT="${PROJECT_ROOT:-$(_mxtk_resolve_root)}"

# ---------------------------------------------------------------------------
# find_mpr — echo the project's single .mpr, or fail loudly.
#
# Refuses to guess between two .mpr files: picking the wrong one means writing
# to, or restoring over, the wrong model. $MPR_FILE overrides.
# ---------------------------------------------------------------------------
find_mpr() {
  if [ -n "${MPR_FILE:-}" ]; then
    if [ ! -f "$PROJECT_ROOT/$MPR_FILE" ] && [ ! -f "$MPR_FILE" ]; then
      echo "ERROR: MPR_FILE='$MPR_FILE' does not exist" >&2
      return 1
    fi
    [ -f "$MPR_FILE" ] && { echo "$MPR_FILE"; return 0; }
    echo "$PROJECT_ROOT/$MPR_FILE"
    return 0
  fi

  local f count=0 found=""
  for f in "$PROJECT_ROOT"/*.mpr; do
    [ -e "$f" ] || continue
    count=$((count + 1))
    found="$f"
  done

  if [ "$count" -eq 0 ]; then
    echo "ERROR: no .mpr found in $PROJECT_ROOT" >&2
    return 1
  fi
  if [ "$count" -gt 1 ]; then
    echo "ERROR: $count .mpr files in $PROJECT_ROOT — refusing to guess which model to write." >&2
    for f in "$PROJECT_ROOT"/*.mpr; do [ -e "$f" ] && echo "  $(basename "$f")" >&2; done
    echo "Set MPR_FILE=<name>.mpr to choose." >&2
    return 1
  fi
  echo "$found"
}

# ---------------------------------------------------------------------------
# find_model_dir — echo the directory that holds the .mpr AND its mprcontents/.
#
# WHY THIS EXISTS (2026-08-31, field-found on a dashboard-publishing migration).
# A Mendix model is two things in ONE directory: `Project.mpr` and `mprcontents/`.
# On a single-tree checkout that directory happens to equal $PROJECT_ROOT, so every
# script here simply said $PROJECT_ROOT and was right by accident. On a two-tree
# checkout — repo at the root, `mxcli new` app under `app/` — it is not, and
# $PROJECT_ROOT points at a directory containing neither file.
#
# The failure was silent and total. snapshot-mpr.sh globbed `$PROJECT_ROOT/*.mpr`,
# matched nothing, copied nothing, printed "mpr snapshot ok", and pruned the older
# (equally empty) snapshots. exec.sh then ran twelve execs behind a crash-net that
# held zero bytes; the first gate failure tried to auto-restore, found a snapshot
# with no mprcontents/, and left the broken model on disk while reporting the
# restore path. The same wrong root also drove exec.sh's "PROJECT IS IN v1
# SINGLE-FILE FORMAT — Studio Pro WILL crash" warning, which fired after every
# successful exec on a perfectly healthy v2 model.
#
# Resolve from the .mpr itself (which honours MPR_FILE) instead of from the repo.
find_model_dir() {
  local mpr
  mpr=$(find_mpr) || return 1
  (cd "$(dirname "$mpr")" && pwd)
}

# ---------------------------------------------------------------------------
# mxtk_platform — "macos" | "windows" | "linux".
#
# WHY THIS EXISTS (2026-08-25). Everything below used to assume macOS: Studio Pro
# was looked for at /Applications/*.app and Java at /usr/libexec/java_home. Under
# Git Bash on Windows both lookups return nothing, so exec.sh's gate guard
# `[ -x "$MXBUILD" ] && [ -x "$JAVA_EXE" ]` was false on every run and the whole
# mxbuild block was skipped. The gate reported `skipped` — honestly, it was built
# "three states, not two" for exactly this reason — but nobody reads a skip as a
# problem, so every MDL exec on a Windows machine went unverified. That is the
# BSON-corruption class iterative-build-loop.md:243 says mxbuild is the ONLY
# reliable detector for. Found during a Windows training round.
#
# $OSTYPE is set by the shell; `uname -s` is the fallback for shells that do not
# export it. Git Bash reports MINGW64_NT-*, MSYS2 reports MSYS_NT-*.
# ---------------------------------------------------------------------------
mxtk_platform() {
  case "${OSTYPE:-}" in
    darwin*)            echo macos   ; return ;;
    msys*|cygwin*|win*) echo windows ; return ;;
  esac
  case "$(uname -s 2>/dev/null)" in
    Darwin)                    echo macos   ;;
    MINGW*|MSYS*|CYGWIN*|Windows*) echo windows ;;
    *)                         echo linux   ;;
  esac
}

# ---------------------------------------------------------------------------
# find_sp_app — newest installed Studio Pro root.
#
# Returns an .app bundle on macOS and a version directory on Windows; callers
# must go through find_mxbuild() rather than appending a path themselves, because
# the layout below the root differs per platform.
#
# Version-sorted, NOT lexically sorted: with 11.9.0 and 11.13.0 both installed,
# a plain `sort` picks 11.9.0 as "highest" because '9' > '1' at the third
# character. That silently builds against the wrong Mendix version. `sort -V`
# handles it; if this box has a sort without -V, we fall back and say so rather
# than quietly return a wrong answer. $MENDIX_APP overrides.
# ---------------------------------------------------------------------------
find_sp_app() {
  if [ -n "${MENDIX_APP:-}" ]; then echo "$MENDIX_APP"; return 0; fi
  local list="" root
  case "$(mxtk_platform)" in
    macos)
      list=$(ls -d /Applications/Mendix\ Studio\ Pro*.app 2>/dev/null) || true
      [ -z "$list" ] && { echo "ERROR: no 'Mendix Studio Pro *.app' in /Applications" >&2; return 1; }
      ;;
    windows)
      # Studio Pro installs as C:\Program Files\Mendix\<version>\ . Both Program
      # Files roots are checked, plus whatever Windows says they are — a machine
      # with a relocated install (D:\ is common on managed laptops, and the
      # training round's Git lived on D:) is not reachable by hardcoded /c.
      # NB: `PROGRAMFILES(X86)` cannot be expanded as ${...} — parentheses are not
      # legal in a bash identifier and it fails at RUNTIME with "bad substitution"
      # while passing `bash -n` cleanly. printenv is the only way to read it.
      for root in "${ProgramW6432:-}" "${PROGRAMFILES:-}" \
                  "$(printenv 'PROGRAMFILES(X86)' 2>/dev/null)" \
                  "/c/Program Files" "/c/Program Files (x86)" \
                  "/d/Program Files" "/d/Mendix" "/c/Mendix"; do
        [ -n "$root" ] || continue
        # Env vars arrive in Windows form (C:\Program Files); make them POSIX.
        case "$root" in
          [A-Za-z]:*) root="/$(printf '%s' "${root%%:*}" | tr '[:upper:]' '[:lower:]')${root#*:}"
                      root=$(printf '%s' "$root" | tr '\\' '/') ;;
        esac
        [ -d "$root/Mendix" ] && root="$root/Mendix"
        [ -d "$root" ] || continue
        list="$list$(ls -d "$root"/*/ 2>/dev/null)"
      done
      list=$(printf '%s\n' "$list" | sed 's:/*$::' | grep -v '^$') || true
      [ -z "$list" ] && {
        echo "ERROR: no Mendix Studio Pro install found under Program Files\\Mendix." >&2
        echo "       Set MENDIX_APP=<path to the version dir> or MXBUILD_PATH=<path to mxbuild.exe>." >&2
        return 1; }
      ;;
    *)
      echo "ERROR: Studio Pro does not run on this platform; set MXBUILD_PATH to skip discovery." >&2
      return 1
      ;;
  esac

  if printf '1.10\n1.9\n' | sort -V >/dev/null 2>&1; then
    printf '%s\n' "$list" | sort -V | tail -1
  else
    echo "WARNING: this sort has no -V; falling back to lexical order, which mis-ranks" >&2
    echo "         11.9 above 11.13. Set MENDIX_APP=<path> to be certain." >&2
    printf '%s\n' "$list" | sort | tail -1
  fi
}

# ---------------------------------------------------------------------------
# find_mxcli_cache — newest version dir in the mxcli download cache
# (~/.mxcli/mxbuild/<version>/), or fail.
#
# This is the SAME standalone toolchain the headless container build downloads:
# `./mxcli setup mxbuild -p <app>.mpr` fetches the mxbuild matching the model's
# Mendix version from the Mendix CDN and caches it here, shared across projects.
# It is how a machine WITHOUT Studio Pro (Linux, a container, a colleague's
# laptop mid-onboarding) still gets a working mxbuild gate — bin/doctor.sh
# --install runs the download. Version-sorted for the same 11.9-vs-11.13 reason
# as find_sp_app. $MXCLI_HOME overrides the cache root.
# ---------------------------------------------------------------------------
find_mxcli_cache() {
  local root="${MXCLI_HOME:-$HOME/.mxcli}/mxbuild" list
  [ -d "$root" ] || return 1
  list=$(ls -d "$root"/*/ 2>/dev/null | sed 's:/*$::' | grep -v '^$') || true
  [ -z "$list" ] && return 1
  if printf '1.10\n1.9\n' | sort -V >/dev/null 2>&1; then
    printf '%s\n' "$list" | sort -V | tail -1
  else
    printf '%s\n' "$list" | sort | tail -1
  fi
}

# find_mxbuild — the mxbuild binary: $MXBUILD_PATH override, then the chosen SP
# install, then the mxcli download cache (see find_mxcli_cache). The SP-derived
# path is still echoed when nothing is executable anywhere, so callers' error
# messages name the path that was expected rather than "<none>".
find_mxbuild() {
  if [ -n "${MXBUILD_PATH:-}" ]; then echo "$MXBUILD_PATH"; return 0; fi
  local app cand="" cache
  if app=$(find_sp_app 2>/dev/null); then
    case "$(mxtk_platform)" in
      windows) cand="$app/modeler/mxbuild.exe" ;;
      *)       cand="$app/Contents/modeler/mxbuild" ;;
    esac
    [ -x "$cand" ] && { echo "$cand"; return 0; }
  fi
  if cache=$(find_mxcli_cache); then
    local cmxb
    case "$(mxtk_platform)" in
      windows) cmxb="$cache/modeler/mxbuild.exe" ;;
      *)       cmxb="$cache/modeler/mxbuild" ;;
    esac
    [ -x "$cmxb" ] && { echo "$cmxb"; return 0; }
  fi
  [ -n "$cand" ] && { echo "$cand"; return 0; }
  return 1
}

# find_java — JAVA_HOME for the mxbuild invocation. $JAVA_HOME wins if already set.
#
# /usr/libexec/java_home is a macOS binary and does not exist anywhere else, so on
# Windows this used to leave JAVA_HOME empty and JAVA_EXE as the literal "/bin/java".
# Studio Pro ships its own JRE, which is the right one to use — it matches the
# mxbuild it is paired with — so that is tried before any system Java.
find_java() {
  if [ -n "${JAVA_HOME:-}" ] && [ -d "$JAVA_HOME" ]; then echo "$JAVA_HOME"; return 0; fi
  local app jh
  if [ "$(mxtk_platform)" = macos ] && [ -x /usr/libexec/java_home ]; then
    jh=$(/usr/libexec/java_home 2>/dev/null) && [ -n "$jh" ] && { echo "$jh"; return 0; }
  fi
  # Studio Pro's bundled JRE.
  if app=$(find_sp_app 2>/dev/null); then
    for jh in "$app/jre" "$app/Contents/jre" "$app/runtime/jre"; do
      [ -d "$jh" ] && { echo "$jh"; return 0; }
    done
  fi
  # A JRE/JDK shipped inside the mxcli download cache, next to its mxbuild.
  # Layout is probed rather than assumed (it has shifted between mxcli versions);
  # when none of these exist the system-Java fallback below still applies.
  local cache
  if cache=$(find_mxcli_cache 2>/dev/null); then
    for jh in "$cache/jre" "$cache/modeler/jre" "$cache/runtime/jre" "$cache/jdk"; do
      [ -d "$jh" ] && { echo "$jh"; return 0; }
    done
  fi
  # System Java, resolved from the java on PATH (two levels up from bin/java).
  local j
  j=$(command -v java 2>/dev/null) && [ -n "$j" ] && {
    jh=$(dirname "$(dirname "$j")"); [ -d "$jh" ] && { echo "$jh"; return 0; }; }
  return 1
}

# find_java_exe — the java binary itself, matching find_java's home.
find_java_exe() {
  local jh
  jh=$(find_java) || return 1
  case "$(mxtk_platform)" in
    windows) echo "$jh/bin/java.exe" ;;
    *)       echo "$jh/bin/java" ;;
  esac
}

# project_name — the .mpr basename without extension, for user-facing messages.
project_name() {
  local mpr
  mpr=$(find_mpr) || return 1
  basename "$mpr" .mpr
}

# --- Python 3 ------------------------------------------------------------------------------
# The project-side twin of bin/lib/portable.sh's require_py. It cannot simply source that file:
# portable.sh is toolkit-side and no installer copies it into a project, while these scripts
# run from <project>/bin/ on machines that may have no toolkit clone at all.
#
# Probe by EXECUTING, never `command -v`. On Windows `python3` usually resolves to the Microsoft
# Store App Execution Alias stub: `command -v` succeeds and the script then opens the Store
# instead of running. On a Mac without the Command Line Tools, /usr/bin/python3 is a prompt-only
# stub that does the same thing. A name on PATH is not an interpreter.
_py_is_store_stub() {
  case "$(command -v "$1" 2>/dev/null)" in
    *WindowsApps*|*windowsapps*) return 0 ;;
    *) return 1 ;;
  esac
}

# Echoes a working Python 3 and returns 0; echoes nothing and returns 1 when there is none.
# The non-fatal half, for the callers that must degrade rather than stop: exec.sh still writes
# and snapshots your changes when the mxbuild gate cannot read its results — it just has to say
# so instead of dying. $PYTHON overrides the search.
resolve_py() {
  _c=""
  for _c in "${PYTHON:-}" python3 python py; do  # portability-ok: this IS the interpreter probe
    [ -n "$_c" ] || continue
    _py_is_store_stub "$_c" && continue
    if "$_c" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then
      echo "$_c"; return 0
    fi
  done
  return 1
}

# Sets $PY to a working Python 3, or exits 2 with a message the reader can act on.
require_py() {
  PY="$(resolve_py)" || {
    echo "$(basename "${0:-script}"): Python 3 is required and was not found." >&2
    echo "  Tried, by running each one: python3, python, py." >&2
    echo "  macOS  : brew install python3    Linux: apt install python3" >&2
    echo "  Windows: python.org installer, tick 'Add python.exe to PATH'. A 'python3' that only" >&2
    echo "           opens the Microsoft Store is the alias stub — Settings > App execution aliases." >&2
    exit 2
  }
  export PY
}
