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
  # tier 2: the script sits in a real project's bin/ (model at the root, or under app/ on a
  # two-tree checkout — the same one-level probe find_mpr makes)
  if [ -n "$self_parent" ] && { ls "$self_parent"/*.mpr >/dev/null 2>&1 || ls "$self_parent"/app/*.mpr >/dev/null 2>&1; }; then
    printf '%s\n' "$self_parent"; return 0
  fi
  # tier 3: walk up from $PWD looking for the .mpr (root or app/).
  # WHY app/ (2026-09-26, card-disbursement requirements-driven build): on a two-tree checkout
  # with no root .mpr, tiers 2 and 3 used to find nothing AT the project and kept climbing — and
  # the first stray .mpr in any ancestor directory became PROJECT_ROOT. A scratch copy under a
  # folder holding one unrelated .mpr pointed model-stamp.sh at that file and its hook passed.
  d=$(pwd)
  while [ "$d" != "/" ]; do
    if ls "$d"/*.mpr >/dev/null 2>&1 || ls "$d"/app/*.mpr >/dev/null 2>&1; then printf '%s\n' "$d"; return 0; fi
    d=$(dirname "$d")
  done
  # nothing found: keep the old behaviour so the caller's own error is the one seen
  printf '%s\n' "${self_parent:-$(pwd)}"
}
PROJECT_ROOT="${PROJECT_ROOT:-$(_mxtk_resolve_root)}"

# mxtk_posix_path — a Windows-form path (C:\Program Files\Mendix) as Git Bash addresses it
# (/c/Program Files/Mendix). Anything already POSIX passes through untouched. Used for every
# path that arrives from the environment or toolkit.env, because people copy paths out of
# Explorer, and `[ -d "C:\..." ]` is false in bash even when the folder exists.
mxtk_posix_path() {
  local p="$1"
  case "$p" in
    [A-Za-z]:*) p="/$(printf '%s' "${p%%:*}" | tr '[:upper:]' '[:lower:]')${p#*:}"
                p=$(printf '%s' "$p" | tr '\\' '/') ;;
  esac
  printf '%s\n' "$p"
}

# --- toolkit.env: where the tools live on THIS machine -------------------------------------
# Discovery below guesses (Program Files\Mendix, /Applications, JAVA_HOME, PATH). When the
# guess is wrong the fix used to be "export MENDIX_APP=... in every shell" — which nobody
# remembers between sessions, and which an agent's subshell never sees. So the same overrides
# can live in a file, KEY=VALUE, one per line, # comments:
#
#     <project>/.claude/toolkit.env     this project on this machine (doctor.sh appends it to .gitignore on its first run — commit that line)
#     ~/.mxcli-toolkit.env               every project on this machine
#
# Precedence: a variable already set in the environment wins; then the project file; then
# the user file. Windows paths may be pasted as-is (C:\Program Files\Mendix\11.11.0).
# Keys the toolkit reads: MENDIX_APP, MXBUILD_PATH, JAVA_HOME, MXCLI_VERSION, MXCLI_HOME,
# PYTHON. Unknown keys are exported too, harmlessly. bin/doctor.sh prints which files loaded.
# Field origin: a Windows onboarding (2026-09-08) with Studio Pro 10.24 + 11.8 + 11.11 side by
# side and a JDK that was not the JRE on PATH — four overrides, none of them discoverable.
MXTK_ENV_LOADED=""
mxtk_load_env() {
  local f line key val
  for f in "$PROJECT_ROOT/.claude/toolkit.env" "${HOME:-/nonexistent}/.mxcli-toolkit.env"; do
    [ -f "$f" ] || continue
    MXTK_ENV_LOADED="${MXTK_ENV_LOADED:+$MXTK_ENV_LOADED }$f"
    while IFS= read -r line || [ -n "$line" ]; do
      line=${line%$'\r'}
      case "$line" in ''|'#'*) continue ;; esac
      case "$line" in *=*) ;; *) continue ;; esac
      key=$(printf '%s' "${line%%=*}" | tr -d '[:space:]'); val=${line#*=}
      case "$key" in [A-Za-z_]*) ;; *) continue ;; esac
      case "$key" in *[!A-Za-z0-9_]*) continue ;; esac
      # export KEY=value and "KEY = value" both work; surrounding quotes are stripped.
      case "$val" in \"*\") val=${val#\"}; val=${val%\"} ;; \'*\') val=${val#\'}; val=${val%\'} ;; esac
      val=$(printf '%s' "$val" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
      val=$(mxtk_posix_path "$val")
      # Already set (by the shell, or by the project file on the previous pass) — keep it.
      eval "[ -n \"\${$key:-}\" ]" && continue
      export "$key=$val"
    done < "$f"
  done
}
mxtk_load_env

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
  # Two-tree checkout: repo at the root, the `mxcli new --output-dir ./app` app under app/.
  # cloud-dev-environment.md prescribes exactly that layout, and every script here refused it
  # with "no .mpr found" (field run, greenfield pilot, 2026-09-04). Same probe, one level down.
  if [ "$count" -eq 0 ] && [ -d "$PROJECT_ROOT/app" ]; then
    for f in "$PROJECT_ROOT"/app/*.mpr; do
      [ -e "$f" ] || continue
      count=$((count + 1))
      found="$f"
    done
  fi

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
# native_path — a path the NATIVE toolchain can open.
#
# Git Bash hands POSIX paths (/tmp/x, /c/Users/...) to native .exe arguments
# and converts them on the way out — but only for arguments. A path that is
# EMBEDDED in a string, such as `python -c "open('/tmp/x')"`, is not converted,
# and a native Windows Python (the only kind resolve_py finds on a stock
# machine) cannot open it: /tmp there means C:\tmp. Every err_* helper in
# exec.sh returned "?" this way on a real Windows 11 machine (2026-09-14), and
# a genuine CE0117 sailed through the mxbuild gate as "unverified" instead of
# fail + restore. Route any path that Python (or Node) will open through here.
# cygpath -m gives forward slashes (C:/Users/...), which bash, Python and Node
# all accept and which survives being quoted inside a -c string.
# ---------------------------------------------------------------------------
native_path() {
  case "$(mxtk_platform)" in
    windows) cygpath -m "$1" 2>/dev/null || printf '%s\n' "$1" ;;
    *)       printf '%s\n' "$1" ;;
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
  if [ -n "${MENDIX_APP:-}" ]; then mxtk_posix_path "$MENDIX_APP"; return 0; fi
  local list
  list=$(mxtk_sp_list) || return 1
  if printf '1.10\n1.9\n' | sort -V >/dev/null 2>&1; then
    printf '%s\n' "$list" | sort -V | tail -1
  else
    echo "WARNING: this sort has no -V; falling back to lexical order, which mis-ranks" >&2
    echo "         11.9 above 11.13. Set MENDIX_APP=<path> to be certain." >&2
    printf '%s\n' "$list" | sort | tail -1
  fi
}

# mxtk_sp_list — every installed Studio Pro root, one per line, unsorted (find_sp_app
# picks the newest; find_mxbuild first looks for the one matching the model's version).
mxtk_sp_list() {
  local list="" root seen=""
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
        root=$(mxtk_posix_path "$root")
        [ -d "$root/Mendix" ] && root="$root/Mendix"
        [ -d "$root" ] || continue
        # ProgramW6432, PROGRAMFILES and the literal /c/Program Files are usually the SAME
        # folder — list it once (2026-09-08 finding: a machine with both set scanned the
        # same install twice, which cost nothing correctness-wise here since the loop below
        # only admits real installs, but is wasted work worth skipping).
        case "$seen" in *"|$root|"*) continue ;; esac
        seen="$seen|$root|"
        # Two things went wrong here on a real Windows 11 machine (2026-09-14, Studio Pro
        # 9.24 + 10.24 + 11.12 side by side): (1) the roots were concatenated WITHOUT a
        # separator, so the last dir of one root and the first of the next fused into
        # ".../gradle-8.5//c/Program Files/Mendix/10.24.21.108016" — a path that does not
        # exist, reported by doctor as "mxbuild not found". (2) Program Files\Mendix also
        # holds "gradle-8.5" and "Version Selector", and `sort -V` ranks letters above
        # digits, so even with the separator the newest "version" was gradle-8.5. Only a
        # dir that actually carries modeler/mxbuild.exe is a Studio Pro install — that check
        # below is also what makes a trailing "only version-shaped dirs" regex filter
        # redundant, so none is applied here.
        for d in "$root"/*/; do
          [ -x "$d/modeler/mxbuild.exe" ] && list="$list$d"$'\n'
        done
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
  printf '%s\n' "$list"
}

# ---------------------------------------------------------------------------
# mxtk_is_elf <file> — true when the file is a Linux (ELF) binary. On Git Bash that is the
# one thing a project's ./mxcli can be that no chmod will ever fix.
mxtk_is_elf() { [ -f "$1" ] && [ "$(head -c 4 "$1" 2>/dev/null | tr -d '\177')" = "ELF" ]; }

# find_project_mxcli — the project's own mxcli binary, or fail.
#
# A project folder is shared between lanes (a Dev Container and Git Bash on the same disk),
# and each lane needs its own build of mxcli: the container's is a Linux ELF binary named
# `mxcli`, Windows' is `mxcli.exe`. Git Bash maps `mxcli` -> `mxcli.exe` transparently ONLY
# when no file called `mxcli` exists; once the container has put its binary there, every
# `./mxcli` and `[ -x mxcli ]` on the Windows side hits the ELF file instead and fails with
# exit 126 — and `chmod +x` appears to "revert", because MSYS derives the executable bit
# from the extension/header, not from mode bits. Real report, Windows, 2026-09-08.
# So on Windows, mxcli.exe is looked for first, explicitly.
find_project_mxcli() {
  local c
  if [ "$(mxtk_platform)" = windows ]; then
    for c in "$PROJECT_ROOT/mxcli.exe" "$PROJECT_ROOT/mxcli"; do
      [ -x "$c" ] && ! mxtk_is_elf "$c" && { echo "$c"; return 0; }
    done
    return 1
  fi
  c="$PROJECT_ROOT/mxcli"
  [ -x "$c" ] && { echo "$c"; return 0; }
  return 1
}

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

# ---------------------------------------------------------------------------
# mxtk_model_version [mpr] — the model's Mendix version (e.g. 11.12.2), read from the
# .mpr's own SQLite _MetaData._ProductVersion. v1 and v2 models both carry it (v2's .mpr
# is still the SQLite index). sqlite3 CLI if present (read-only), else Python's sqlite3.
# Prints nothing and returns 1 when it cannot tell — callers then fall back to "newest".
# Golden input: a field project's .mpr (v1, 152 MB) → _MetaData row
# ('11.12.2', '11.12.2', '{SHA256}…', 0), columns _ProductVersion, _BuildVersion,
# _SchemaHash, _DisableAutoMprV2Upgrade (captured 2026-09-27).
# ---------------------------------------------------------------------------
mxtk_model_version() {
  local mpr="${1:-}" v="" py
  [ -n "$mpr" ] || mpr="$(find_mpr 2>/dev/null)" || return 1
  [ -f "$mpr" ] || return 1
  if command -v sqlite3 >/dev/null 2>&1; then
    v=$(sqlite3 -readonly "$mpr" 'select _ProductVersion from _MetaData' 2>/dev/null | head -1 | tr -d '\r')
  fi
  if [ -z "$v" ]; then
    py="${PY:-$(resolve_py 2>/dev/null || true)}"
    [ -n "$py" ] && v=$("$py" -c "import sqlite3,sys,os,urllib.request as u
c=sqlite3.connect('file:'+u.pathname2url(os.path.abspath(sys.argv[1]))+'?mode=ro',uri=True)
print(c.execute('select _ProductVersion from _MetaData').fetchone()[0])" "$(native_path "$mpr")" 2>/dev/null | head -1 | tr -d '\r')
  fi
  case "$v" in
    [0-9]*.[0-9]*) printf '%s\n' "$v"; return 0 ;;
  esac
  return 1
}

# mxtk_version_in_name <dir-or-name> <version> — true when the LAST path component names
# <version> (compared on major.minor.patch). Matches "11.12.2", "11.12.2.83245",
# "Mendix Studio Pro 11.12.2.app", "Mendix Studio Pro 11.12.2 Beta.app"; never "11.12.20".
mxtk_version_in_name() {
  local base v3 re
  base=$(basename "$1")
  v3=$(printf '%s' "$2" | cut -d. -f1-3)
  [ -n "$v3" ] || return 1
  re=$(printf '%s' "$v3" | sed 's/\./\\./g')
  printf '%s\n' "$base" | grep -Eq "(^|[^0-9.])${re}(\.[0-9]+)?([^0-9.]|\.[^0-9]|\$)"
}

# mxtk_mxbuild_for_version <version> — an executable mxbuild whose install (Studio Pro
# root or mxcli cache dir) is named for <version>, or return 1. Studio Pro first, then
# the cache, same order as find_mxbuild's newest-first fallback.
mxtk_mxbuild_for_version() {
  local ver="$1" d c list cache_root
  [ -n "$ver" ] || return 1
  if [ -z "${MENDIX_APP:-}" ] && list=$(mxtk_sp_list 2>/dev/null); then
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      mxtk_version_in_name "$d" "$ver" || continue
      for c in "$d/Contents/modeler/mxbuild" "$d/modeler/mxbuild.exe"; do
        [ -x "$c" ] && { echo "$c"; return 0; }
      done
    done <<EOF_SP
$list
EOF_SP
  fi
  cache_root="${MXCLI_HOME:-$HOME/.mxcli}/mxbuild"
  for d in "$cache_root"/*/; do
    [ -d "$d" ] || continue
    d="${d%/}"
    mxtk_version_in_name "$d" "$ver" || continue
    for c in "$d/modeler/mxbuild" "$d/modeler/mxbuild.exe"; do
      [ -x "$c" ] && { echo "$c"; return 0; }
    done
  done
  return 1
}

# find_mxbuild — the mxbuild binary: $MXBUILD_PATH override, then the Studio Pro install
# or mxcli cache entry matching the MODEL'S version, then (no match) the newest SP install,
# then the newest mxcli download cache entry (see find_mxcli_cache). The SP-derived
# path is still echoed when nothing is executable anywhere, so callers' error
# messages name the path that was expected rather than "<none>".
#
# WHY VERSION FIRST (field project, 2026-09-26). mxbuild opens only a model of its own
# exact version. "Newest" picked a Studio Pro 11.14.0 Beta for an 11.12.2 model; that
# mxbuild exited 3 in two seconds with "Project version '11.12.2' does not exactly match
# MxBuild version '11.14.0'" in errors[] and an empty problems[] — and the gate read the
# empty problems[] as "0 errors, clean" for 29 of 29 execs, one of which shipped a CE0066.
# The matching 11.12.2 mxbuild sat in the mxcli cache the whole time. The no-match fallback
# is loud in mxtk_ensure_mxbuild (this function is always called with stderr discarded).
find_mxbuild() {
  if [ -n "${MXBUILD_PATH:-}" ]; then echo "$MXBUILD_PATH"; return 0; fi
  local ver m
  if ver=$(mxtk_model_version 2>/dev/null) && m=$(mxtk_mxbuild_for_version "$ver"); then
    echo "$m"; return 0
  fi
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
  # JDK 21 first on macOS: with JDK 25 as the default, the Mendix 11 deploy build's gradle
  # 8.5 fails ("Unsupported class file major version 69", mxbuild exit 3, empty problems[])
  # — field project 2026-09-26, Mendix 11.12.2. Platform-guarded: java_home is mac-only.
  if [ "$(mxtk_platform)" = macos ] && [ -x /usr/libexec/java_home ]; then
    jh=$(/usr/libexec/java_home -v 21 2>/dev/null || /usr/libexec/java_home 2>/dev/null) && [ -n "$jh" ] && { echo "$jh"; return 0; }
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

# ---------------------------------------------------------------------------
# mxtk_mxbuild_error_count — run mxbuild once, print its Error-severity count.
#
# Pulled out of project-bin/exec.sh, where this exact sequence (run mxbuild with
# --write-errors, read the result through native_path, treat an empty file + exit 0
# as a verified 0) was hand-written three times — the pre-flight baseline, the main
# gate, and the "whose error is it" restore-rebuild check — so that bin/doctor.sh's
# gate self-test can call the SAME code a real exec run trusts, not a second
# implementation that could quietly drift from it. Both layouts are covered because
# it takes an .mpr path, not a project directory: pass whatever find_mpr() returned
# (root or app/, per find_mpr's own two-tree probe).
#
# mxtk_mxbuild_error_count <mpr> <timeout-seconds> [errors-file]
#
# Resolves mxbuild/java via find_mxbuild/find_java/find_java_exe (so $MXBUILD_PATH,
# $MENDIX_APP and $JAVA_HOME overrides all apply here too) and runs
#     mxbuild --write-errors=<errors-file> --target=deploy <mpr>
# with output captured to a temp file, NEVER through `$(...)`: Studio Pro 11's
# mxbuild.exe starts modeler/tools/deno/*/deno.exe, which inherits stdout and keeps
# it open after mxbuild itself has exited — a command substitution then waits
# forever for EOF that never comes (field run, Windows 11, Studio Pro 11.12.4,
# 368cd2e). A file has no reader waiting on EOF: bash returns as soon as mxbuild
# itself exits. stdin is closed for the same reason — a console-attached child must
# not be able to wait on it.
#
# Bounded by <timeout-seconds>: no `timeout(1)` is assumed (macOS ships none) — the
# same background/poll/kill pattern as bin/doctor.sh's container_daemon_up. This is a
# genuine behaviour addition versus the exec.sh code it replaces, which had no bound
# at all; the default callers use is generous (300s) specifically so a real build is
# never cut short by it, only a truly stuck one.
#
# Sets on return (bash 3.2 has no namerefs, so these globals ARE the contract):
#   MXTK_MXBUILD_OUT    captured stdout+stderr from the mxbuild invocation
#   MXTK_MXBUILD_EXIT   mxbuild's own exit code, or 124 if it was killed for timing out
#   MXTK_MXBUILD_WHY    mxbuild's errors[] messages (why it did not check), or empty
#
# [errors-file], if given, is left on disk afterward (whatever mxbuild wrote, even
# nothing) for a caller that also wants err_codes/err_set/the raw JSON off the same
# run — e.g. exec.sh's failure-path detail dump. Omit it and a temp file is used and
# removed before this returns.
#
# Prints the integer Error-severity count on stdout, or "?" if it could not be
# determined. Empty errors file + exit 0 is 0, not "?": Studio Pro 11's mxbuild only
# writes --write-errors when the project already has errors, so an empty file after
# a clean exit is a verified-clean build (2026-09-14 field run), not a parse
# failure. A NON-ZERO exit with 0 Error problems is "?" too: mxbuild refused the model
# (version mismatch, JDK) without checking it — see the note at the end of the function.
# Returns 0 (count printed, 0 or more) · 1 (mxbuild ran, file unreadable —
# no Python 3, or the JSON did not parse) · 2 (mxbuild or java not found/executable,
# nothing was run) · 3 (timed out and was killed after <timeout-seconds>).
# ---------------------------------------------------------------------------
mxtk_mxbuild_error_count() {
  local _mpr="$1" _timeout="${2:-300}" _ef="${3:-}" _own_ef=0
  local _mb _jh _je _out _pid _waited=0 _exit=0 _py _count

  MXTK_MXBUILD_OUT=""; MXTK_MXBUILD_EXIT=""; MXTK_MXBUILD_WHY=""
  _mb="$(find_mxbuild 2>/dev/null || true)"
  _jh="$(find_java 2>/dev/null || true)"
  _je="$(find_java_exe 2>/dev/null || true)"
  if [ ! -x "$_mb" ] || [ ! -x "$_je" ]; then
    echo "?"; return 2
  fi

  if [ -z "$_ef" ]; then
    _ef=$(mktemp /tmp/mxbuild-errors.XXXXXX) || { echo "?"; return 2; }
    _own_ef=1
  fi
  _out=$(mktemp /tmp/mxbuild-out.XXXXXX) || { [ "$_own_ef" -eq 1 ] && rm -f "$_ef"; echo "?"; return 2; }

  "$_mb" --java-home="$_jh" --java-exe-path="$_je" \
         --write-errors="$_ef" --target=deploy "$_mpr" \
         > "$_out" 2>&1 < /dev/null &
  _pid=$!
  # _timeout 0 = unbounded: exec.sh's real gate passes 0 unless MXTK_GATE_TIMEOUT is set,
  # because a large model's deploy build legitimately runs past any fixed default, and a
  # timed-out gate reads as "non-zero exit, no errors file" = FAIL = auto-restore of work
  # that was fine. doctor's self-test is the one caller that wants a bound (300s default).
  while kill -0 "$_pid" 2>/dev/null; do
    if [ "$_timeout" -gt 0 ] && [ "$_waited" -ge "$_timeout" ]; then
      kill "$_pid" 2>/dev/null; wait "$_pid" 2>/dev/null
      MXTK_MXBUILD_OUT=$(cat "$_out" 2>/dev/null); rm -f "$_out"
      MXTK_MXBUILD_EXIT=124
      [ "$_own_ef" -eq 1 ] && rm -f "$_ef"
      echo "?"; return 3
    fi
    sleep 1; _waited=$((_waited + 1))
  done
  wait "$_pid" || _exit=$?
  MXTK_MXBUILD_OUT=$(cat "$_out" 2>/dev/null); rm -f "$_out"
  MXTK_MXBUILD_EXIT="$_exit"

  if [ ! -s "$_ef" ] && [ "$_exit" -eq 0 ]; then
    [ "$_own_ef" -eq 1 ] && rm -f "$_ef"
    echo 0; return 0
  fi

  _py="${PY:-$(resolve_py 2>/dev/null || true)}"
  if [ -z "$_py" ]; then
    [ "$_own_ef" -eq 1 ] && rm -f "$_ef"
    echo "?"; return 1
  fi
  _count=$("$_py" -c "import json;d=json.load(open('$(native_path "$_ef")'));print(len([x for x in d.get('problems',[]) if x.get('severity')=='Error']))" 2>/dev/null)
  MXTK_MXBUILD_WHY=$(mxtk_mxbuild_why "$_ef" "$_py")
  [ "$_own_ef" -eq 1 ] && rm -f "$_ef"
  if [ -z "$_count" ]; then echo "?"; return 1; fi
  # Non-zero exit and ZERO Error problems: mxbuild stopped BEFORE checking the model — a
  # version mismatch, a JDK/gradle failure — and put the reason in errors[], leaving
  # problems[] empty. That is "could not verify", never "0 errors". (An exit code and a
  # problem count are two facts; skills/tool-output-is-not-ground-truth.md.)
  if [ "$_count" = "0" ] && [ "$_exit" -ne 0 ]; then echo "?"; return 1; fi
  echo "$_count"; return 0
}

# mxtk_mxbuild_why <errors-file> [python] — mxbuild's own errors[] messages, joined and
# capped at 300 chars, or nothing. errors[] is where mxbuild says why it did NOT check the
# model; problems[] is only the model's findings. Verbatim errors[] captured on
# A field project (2026-09-26, mxbuild 11.14.0 vs an 11.12.2 model, exit 3):
#   {"errors":[{"message":"The MPR file located at …/Marketplace.mpr could not be opened:
#    Project version '11.12.2' does not exactly match MxBuild version '11.14.0'. Use loose
#    version check option for less strict version checking.","details":""}],"problems":[]}
mxtk_mxbuild_why() {
  local _py="${2:-${PY:-$(resolve_py 2>/dev/null || true)}}"
  [ -s "$1" ] && [ -n "$_py" ] || return 0
  "$_py" -c "import json;d=json.load(open('$(native_path "$1")'));print('; '.join((e.get('message','') if isinstance(e,dict) else str(e)) for e in d.get('errors',[]) or [])[:300])" 2>/dev/null || true
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

# ---------------------------------------------------------------------------
# mxtk_ensure_mxbuild <mpr> — make the mxbuild gate runnable, or say why not.
#
# Echoes an executable mxbuild path and returns 0. When find_mxbuild finds
# nothing runnable, it downloads the standalone toolchain through the project's
# own ./mxcli (`./mxcli setup mxbuild -p <app>.mpr` — the exact download
# bin/doctor.sh --install runs and the headless container build runs), then
# re-discovers. Returns 1 only when there is still nothing to run.
#
# WHY. Before this, a machine without Studio Pro and without a cached mxbuild
# got a one-line warning and an UNVERIFIED model write (2026-09-17: a cloud
# session applied nine scripts that way; one carried a CE0117 that only mxbuild
# can see, and it reached the Team Server). The remedy is one command that the
# toolkit already knows how to run — so run it, at the moment the gate needs
# it, instead of asking the reader to. MXTK_NO_INSTALL=1 turns the download off
# (offline CI), in which case this degrades to plain discovery.
# ---------------------------------------------------------------------------
mxtk_ensure_mxbuild() {
  local mpr="$1" found="" root mxcli ver="" mismatch=0
  found="$(find_mxbuild 2>/dev/null || true)"
  # A runnable mxbuild of the WRONG version is not a runnable gate: it refuses the model
  # (exit 3, "Project version 'X' does not exactly match MxBuild version 'Y'"). When the
  # model's version is readable and no install of it exists, download it like a missing
  # mxbuild; if that is not possible, keep the mismatched one but say so, loudly.
  ver="$(mxtk_model_version "$mpr" 2>/dev/null || true)"
  if [ -n "$ver" ] && [ -n "$found" ] && [ -x "$found" ]; then
    if [ -n "${MXBUILD_PATH:-}" ]; then
      case "$found" in
        *"$(printf '%s' "$ver" | cut -d. -f1-3)"*) ;;
        *) echo "  ⚠  MXBUILD_PATH=$found does not name this model's Mendix version ($ver) — if it is another version, mxbuild will refuse the model and the gate cannot verify it." >&2 ;;
      esac
      printf '%s\n' "$found"; return 0
    fi
    mxtk_mxbuild_for_version "$ver" >/dev/null 2>&1 || mismatch=1
  fi
  if [ -n "$found" ] && [ -x "$found" ] && [ "$mismatch" -eq 0 ]; then printf '%s\n' "$found"; return 0; fi
  if [ "$mismatch" -eq 1 ]; then
    echo "  ⚠  No mxbuild for this model's Mendix version ($ver) is installed; the only one found is $found." >&2
    echo "     mxbuild refuses a model of another version, so the gate would verify nothing with it." >&2
  fi
  [ "${MXTK_NO_INSTALL:-0}" = "1" ] && { [ -n "$found" ] && printf '%s\n' "$found"; return 1; }
  root="$(dirname "$mpr")"
  mxcli=""
  for mxcli in "${PROJECT_ROOT:-$root}/mxcli" "${PROJECT_ROOT:-$root}/mxcli.exe" "$root/mxcli" "$root/mxcli.exe"; do
    [ -x "$mxcli" ] && break
    mxcli=""
  done
  if [ -z "$mxcli" ]; then
    echo "  mxbuild not found and no project ./mxcli to download it with (bin/doctor.sh --install fetches both)." >&2
    [ -n "$found" ] && printf '%s\n' "$found"
    return 1
  fi
  echo "→ mxbuild not found — downloading the toolchain for this model's Mendix version" >&2
  echo "  ($mxcli setup mxbuild — the same download bin/doctor.sh --install runs; cached under ~/.mxcli/mxbuild/)" >&2
  if (cd "$root" && "$mxcli" setup mxbuild -p "$(basename "$mpr")" >&2); then
    found="$(find_mxbuild 2>/dev/null || true)"
    if [ -n "$found" ] && [ -x "$found" ]; then
      if [ -n "$ver" ] && ! mxtk_mxbuild_for_version "$ver" >/dev/null 2>&1; then
        echo "  ⚠  download finished but there is still no mxbuild for $ver — using $found; the gate will report the refusal as unverified." >&2
      fi
      printf '%s\n' "$found"; return 0
    fi
    echo "  download reported success but no runnable mxbuild was found afterwards (looked under ${MXCLI_HOME:-$HOME/.mxcli}/mxbuild/)." >&2
  else
    echo "  '$mxcli setup mxbuild' failed — a blocked network or proxy is the usual cause (the download comes from the Mendix CDN)." >&2
  fi
  [ -n "$found" ] && printf '%s\n' "$found"
  return 1
}

# ---------------------------------------------------------------------------
# find_toolkit_root — where the mxcli-project-toolkit clone is, for scripts
# that need bin/doctor.sh or project-bin/ from it. $MXTK_ROOT wins; else the
# `| Toolkit root | \`path\` |` row wire-agents.sh writes into CLAUDE.local.md.
# Echoes the directory and returns 0, or returns 1.
# ---------------------------------------------------------------------------
find_toolkit_root() {
  local c
  for c in "${MXTK_ROOT:-}" \
           "$(sed -nE 's/^\| *Toolkit root *\| *`([^`]+)`.*/\1/p' "${PROJECT_ROOT:-.}/CLAUDE.local.md" 2>/dev/null | head -1)"; do
    [ -n "$c" ] && [ -d "$c/project-bin" ] && { printf '%s\n' "$c"; return 0; }
  done
  return 1
}

# mxtk_sha256 — SHA-256 of stdin, whichever tool this machine has (sha256sum on
# Linux/Git Bash, shasum on macOS, openssl as the last resort).
mxtk_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1
  else openssl dgst -sha256 | sed 's/^.*= //'
  fi
}

# ---------------------------------------------------------------------------
# mxtk_proc_list — every process as "pid<TAB>ppid<TAB>args", one per line, from ONE snapshot;
# returns 1 when the platform gives no list (the caller must then warn and carry on, never block).
#
# WHY (#228). exec.sh's raw-exec guard used `pgrep -fl "mxcli exec"`: a substring search of
# every process on the machine, which also matched the caller's own `bash -c '... mxcli exec
# ...'` line, other projects' execs and greps, and which does not exist under Git Bash.
# This lists processes so the caller can compare argv exactly. macOS and Linux share
# `ps -A -o pid=,ppid=,args=`; Windows asks PowerShell (Git Bash's own ps shows MSYS pids only).
# ---------------------------------------------------------------------------
mxtk_proc_list() {
  case "$(mxtk_platform)" in
    windows)
      command -v powershell.exe >/dev/null 2>&1 || return 1
      powershell.exe -NoProfile -Command \
        "Get-CimInstance Win32_Process | ForEach-Object { \"\$(\$_.ProcessId)\`t\$(\$_.ParentProcessId)\`t\$(\$_.CommandLine)\" }" \
        2>/dev/null | tr -d '\r'
      ;;
    *)
      command -v ps >/dev/null 2>&1 || return 1
      ps -A -o pid=,ppid=,args= 2>/dev/null \
        | sed -E 's/^[[:space:]]*([0-9]+)[[:space:]]+([0-9]+)[[:space:]]+/\1	\2	/'
      ;;
  esac
}

# mxtk_raw_exec_on <model.mpr> — print "pid<TAB>args" for each process that is `mxcli exec`
# against that model and is NOT this shell, one of its ancestors, or one of its descendants
# (the $(...) subshells running this very check appear in ps under the caller's argv). Pids
# are compared exactly, so 123 never hides 1234. Exit 0 = list obtained (output may be empty),
# 1 = no process list available.
mxtk_raw_exec_on() {
  local mpr="$1" list
  list=$(mxtk_proc_list) || return 1
  [ -n "$list" ] || return 1
  printf '%s\n' "$list" | awk -F'\t' -v me="$$" -v mpr="$mpr" -v base="$(basename "$mpr")" '
    { pp[$1]=$2; args[$1]=$3 }
    END {
      skip[me]=1; down[me]=1
      for (p=me; p in pp && p > 1 && !(pp[p] in skip); p=pp[p]) skip[pp[p]]=1
      for (r=0; r<6; r++) for (k in pp) if (pp[k] in down) { down[k]=1; skip[k]=1 }
      for (k in pp) {
        if (k in skip) continue
        a=args[k]; m=split(a, w, /[[:space:]]+/)
        b=w[1]; gsub(/"/, "", b); sub(/.*[\/\\]/, "", b)
        if (b != "mxcli" && b != "mxcli.exe") continue
        hasexec=0; for (i=2;i<=m;i++) if (w[i]=="exec") hasexec=1
        if (!hasexec) continue
        if (index(a, mpr) || index(a, base)) print k "\t" a
      }
    }'
  return 0
}
