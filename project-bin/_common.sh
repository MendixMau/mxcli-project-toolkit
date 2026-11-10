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
#   3. The current directory's project root, found by walking up for an .mpr (at the root,
#      under app/, or under apps/<X>/) and never past the first project folder (#420).
#
# Tier 3 is why this is not a one-liner any more. The toolkit's own copy of these
# scripts used to resolve tier 2 to the TOOLKIT, so running
#     ~/mxcli-project-toolkit/project-bin/verify-module.sh <Module>
# from inside a project pointed every instrument at the toolkit, which has no .mpr
# and no tests/e2e — and the run reported instrument faults rather than saying the
# obvious thing, that it was aimed at the wrong directory. Copying the script into
# every project was the workaround. Tier 3 removes the need for it: the shared
# toolkit copy now works from inside any wired project, no env var, no install.
#
# Where a model may sit under a project root — the three layouts, probed one level each, the
# same probe find_mpr makes: <root>/*.mpr (single tree), <root>/app/*.mpr (two-tree), and
# <root>/apps/<X>/*.mpr (multi-app folder, one app per subfolder).
_mxtk_has_model() {
  ls "$1"/*.mpr >/dev/null 2>&1 || ls "$1"/app/*.mpr >/dev/null 2>&1 || ls "$1"/apps/*/*.mpr >/dev/null 2>&1
}
# A folder that is a project whether or not a model was found in it: it holds an installed
# bin/_common.sh (init-project.sh installs one into every project), or a .claude/ beside a
# PROJECT.md (the wired-project pair init-project.sh writes). A bare .claude/ is NOT enough:
# Claude Code creates one in whatever folder it runs in (a stray /tmp/.claude stopped the walk
# in testing), and $HOME's is the user config. The toolkit's own copy lives in project-bin/
# and the toolkit has no PROJECT.md, so the toolkit is not a project folder.
_mxtk_is_project_dir() {
  [ -f "$1/bin/_common.sh" ] && return 0
  [ -d "$1/.claude" ] && [ -f "$1/PROJECT.md" ] && [ "$1" != "${HOME:-/nonexistent}" ]
}
# mxtk_walk_root <dir> — walk up from <dir>; print the first folder that holds a model (any of
# the three layouts) or is a project folder, whichever comes first. rc 1 when neither is found
# below /. The marker stop is what keeps the walk inside the project (#420): a multi-app folder
# (apps/<X>/X.mpr) failed the root/app probe, the walk climbed on, and the first ancestor with
# ANY .mpr became PROJECT_ROOT, so look-ledger rows landed in another folder's ledger.
# A stop at an app folder (<p>/app or <p>/apps/<X>, any letter case) whose project folder <p>
# is marked returns <p> (#489): the installed copy (tier 2) already resolves <p> from there, and
# two answers for one cwd split the ledgers. An unmarked app folder is still returned as itself,
# and so is an app folder that is a project folder of its own (its own install, or .claude/
# beside PROJECT.md): a project nested at apps/<X>/ or app/ keeps its own root.
mxtk_walk_root() {
  local d="$1" p
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    if _mxtk_has_model "$d" || _mxtk_is_project_dir "$d"; then
      if ! _mxtk_is_project_dir "$d"; then
        p="${d%/*}"
        case "$d" in
          */[Aa][Pp][Pp])  [ -n "$p" ] && _mxtk_is_project_dir "$p" && d="$p" ;;
          */[Aa][Pp][Pp][Ss]/*)
            case "$p" in */[Aa][Pp][Pp][Ss]) p="${p%/*}"; [ -n "$p" ] && _mxtk_is_project_dir "$p" && d="$p" ;; esac ;;
        esac
      fi
      printf '%s\n' "$d"; return 0
    fi
    p="${d%/*}"; [ "$p" != "$d" ] || break   # dirname without a process
    d="$p"
  done
  return 1
}
_mxtk_resolve_root() {
  local self_parent _src _sd
  _src="${BASH_SOURCE[2]:-${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}}"
  _sd="${_src%/*}"; [ "$_sd" != "$_src" ] || _sd=.
  self_parent=$(cd "$_sd/.." 2>/dev/null && pwd)
  # tier 2: the script sits in a real project's bin/ (a model in any of the three layouts)
  if [ -n "$self_parent" ] && _mxtk_has_model "$self_parent"; then
    printf '%s\n' "$self_parent"; return 0
  fi
  # tier 3: walk up from $PWD (mxtk_walk_root).
  # WHY app/ (2026-09-26, card-disbursement requirements-driven build): on a two-tree checkout
  # with no root .mpr, tiers 2 and 3 used to find nothing AT the project and kept climbing — and
  # the first stray .mpr in any ancestor directory became PROJECT_ROOT. A scratch copy under a
  # folder holding one unrelated .mpr pointed model-stamp.sh at that file and its hook passed.
  # WHY apps/*/ and the project-folder stop (#420): the same climb, for a multi-app folder.
  mxtk_walk_root "$(pwd)" && return 0
  # nothing found: keep the old behaviour so the caller's own error is the one seen
  printf '%s\n' "${self_parent:-$(pwd)}"
}
PROJECT_ROOT="${PROJECT_ROOT:-$(_mxtk_resolve_root)}"
# Multi-app folder, MPR_FILE unset, the session inside one app's folder: pick that app HERE,
# at source time, and export it (#489 review). Since #489 the root from apps/<X>/ is the
# project, and a pick made later inside find_mpr did not survive exec.sh's cd "$PROJECT_ROOT"
# or reach its children (snapshot-mpr.sh refused and set -e aborted the run mid-way). Only
# when the root holds no *.mpr and no app/*.mpr, and exactly one apps/<X>/*.mpr sits in a
# folder holding $PWD. Globs and builtins only. Outside any one app nothing is picked, so
# find_mpr still refuses and names MPR_FILE.
# An auto-pick is marked MXTK_MPR_PICKED (both exported). A child that inherits it while its own
# cwd sits inside a DIFFERENT apps/<X>/ re-derives; at the project root it keeps the pick (that
# is exec.sh's cd, the case this exists for). A pick inherited from ANOTHER project is dropped.
# A MPR_FILE the user set is never touched.
if [ -n "${MXTK_MPR_PICKED:-}" ] && [ "${MPR_FILE:-}" = "$MXTK_MPR_PICKED" ]; then
  case "$MPR_FILE" in "$PROJECT_ROOT"/*) ;; *) unset MPR_FILE MXTK_MPR_PICKED ;; esac
  case "$PWD/" in
    "${MPR_FILE%/*}"/*) ;;
    "$PROJECT_ROOT"/apps/?*/*) unset MPR_FILE MXTK_MPR_PICKED ;;
  esac
fi
if [ -z "${MPR_FILE:-}" ] && [ -d "$PROJECT_ROOT/apps" ]; then
  _mxtk_n=0; _mxtk_pick=""
  for _mxtk_f in "$PROJECT_ROOT"/*.mpr "$PROJECT_ROOT"/app/*.mpr; do [ -e "$_mxtk_f" ] && _mxtk_n=2; done
  if [ "$_mxtk_n" -eq 0 ]; then
    for _mxtk_f in "$PROJECT_ROOT"/apps/*/*.mpr; do
      [ -e "$_mxtk_f" ] || continue
      case "$PWD/" in "${_mxtk_f%/*}"/*) _mxtk_n=$((_mxtk_n + 1)); _mxtk_pick="$_mxtk_f" ;; esac
    done
  fi
  if [ "$_mxtk_n" -eq 1 ]; then MPR_FILE="$_mxtk_pick"; MXTK_MPR_PICKED="$_mxtk_pick"; export MPR_FILE MXTK_MPR_PICKED; fi
  unset _mxtk_n _mxtk_pick _mxtk_f
fi

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
      # Drop a leading `export ` before squeezing whitespace, or the key reads as exportKEY.
      key=${line%%=*}; key=${key#"${key%%[![:space:]]*}"}
      case "$key" in export[[:space:]]*) key=${key#export} ;; esac
      key=$(printf '%s' "$key" | tr -d '[:space:]'); val=${line#*=}
      case "$key" in [A-Za-z_]*) ;; *) continue ;; esac
      case "$key" in *[!A-Za-z0-9_]*) continue ;; esac
      # export KEY=value and "KEY = value" both work; surrounding quotes are stripped.
      # Trim first, so `KEY = "value"` still has its quotes at the edges when they are stripped.
      val=$(printf '%s' "$val" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
      case "$val" in \"*\") val=${val#\"}; val=${val%\"} ;; \'*\') val=${val#\'}; val=${val%\'} ;; esac
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
# True when exec.sh's exported model path (MXTK_MPR_MEMO) was resolved for THIS project root and
# MPR_FILE and still exists: a single model was found there, so the layout probes can be skipped.
_mxtk_mpr_memo_ok() {
  [ -n "${MXTK_MPR_MEMO:-}" ] && [ "${MXTK_MPR_MEMO_KEY:-}" = "$PROJECT_ROOT|${MPR_FILE:-}" ] && [ -f "$MXTK_MPR_MEMO" ]
}
find_mpr() {
  # Run-scope memo: exec.sh resolves the model once and exports it, keyed on the project root
  # and MPR_FILE, so the scripts it starts (and its own later calls) skip the glob probes.
  if _mxtk_mpr_memo_ok; then printf '%s\n' "$MXTK_MPR_MEMO"; return 0; fi
  if [ -n "${MPR_FILE:-}" ]; then
    if [ ! -f "$PROJECT_ROOT/$MPR_FILE" ] && [ ! -f "$MPR_FILE" ]; then
      echo "ERROR: MPR_FILE='$MPR_FILE' does not exist" >&2
      return 1
    fi
    # Always an absolute path (#489 review): a caller that later does `cd "$PROJECT_ROOT"`
    # (exec.sh) would otherwise resolve a cwd-relative MPR_FILE against the wrong folder.
    if [ -f "$MPR_FILE" ]; then
      case "$MPR_FILE" in /*|[A-Za-z]:*) echo "$MPR_FILE" ;; *) echo "$(pwd)/$MPR_FILE" ;; esac
      return 0
    fi
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
  # Multi-app folder: one app per apps/<X>/ (#420). The root resolver accepts this layout, so
  # the model lookup must too; with more than one app it refuses to guess, like any other pair.
  local multi=0
  if [ "$count" -eq 0 ] && [ -d "$PROJECT_ROOT/apps" ]; then
    for f in "$PROJECT_ROOT"/apps/*/*.mpr; do
      [ -e "$f" ] || continue
      count=$((count + 1)); multi=1
      found="$f"
    done
  fi

  if [ "$count" -eq 0 ]; then
    echo "ERROR: no .mpr found in $PROJECT_ROOT" >&2
    return 1
  fi
  # (A session inside one app's folder never gets here: _common.sh exported MPR_FILE for
  # that app at source time, #489 review.)
  if [ "$count" -gt 1 ]; then
    echo "ERROR: $count .mpr files in $PROJECT_ROOT — refusing to guess which model to write." >&2
    for f in "$PROJECT_ROOT"/*.mpr; do [ -e "$f" ] && echo "  $(basename "$f")" >&2; done
    if [ "$multi" = 1 ]; then
      for f in "$PROJECT_ROOT"/apps/*/*.mpr; do [ -e "$f" ] && echo "  ${f#"$PROJECT_ROOT"/}" >&2; done
      echo "Set MPR_FILE=apps/<X>/<X>.mpr (relative to $PROJECT_ROOT) to choose." >&2
    else
      echo "Set MPR_FILE=<name>.mpr to choose." >&2
    fi
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
  # exec.sh exports the answer it already computed (MXTK_MODEL_DIR_MEMO) for the same model.
  if _mxtk_mpr_memo_ok && [ -n "${MXTK_MODEL_DIR_MEMO:-}" ] && [ -d "$MXTK_MODEL_DIR_MEMO" ]; then
    printf '%s\n' "$MXTK_MODEL_DIR_MEMO"; return 0
  fi
  mpr=$(find_mpr) || return 1
  local d="${mpr%/*}"; [ "$d" != "$mpr" ] || d=.; [ -n "$d" ] || d=/
  (cd "$d" && pwd)
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
  case "${MXTK_PLATFORM:-$(mxtk_platform)}" in
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
  case "${MXTK_PLATFORM:-$(mxtk_platform)}" in
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

# mxtk_binfmt <file> — what kind of executable the first bytes say it is: elf | macho | pe |
# other. Magic numbers only (no `file`, which Git Bash may lack); od exists everywhere.
# macho = feedface/feedfacf (+ byte-swapped) and cafebabe (fat/universal). A Java .class also
# starts cafebabe but is never a project ./mxcli, so the overlap is harmless here.
mxtk_binfmt() {
  local h
  [ -f "$1" ] || { echo other; return 0; }
  h="$(head -c 4 "$1" 2>/dev/null | od -An -tx1 | tr -d ' \n')"
  case "$h" in
    7f454c46)                                         echo elf   ;;
    feedface|feedfacf|cefaedfe|cffaedfe|cafebabe)     echo macho ;;
    4d5a*)                                            echo pe    ;;
    *)                                                echo other ;;
  esac
}

# mxtk_mxcli_wrong_format <file> [platform] — prints the foreign format (elf|macho) and returns 0
# when <file> is an executable built for another OS than the host; returns 1 otherwise (right
# format, a script, unreadable). macOS runs only Mach-O and Linux only ELF; Windows is handled by
# mxtk_is_elf above. Field report #728: `mxcli new` on macOS left a Linux ./mxcli in the app.
mxtk_mxcli_wrong_format() {
  local f; f="$(mxtk_binfmt "$1")"
  case "${2:-${MXTK_PLATFORM:-$(mxtk_platform)}}:$f" in
    macos:elf)   echo elf;   return 0 ;;
    linux:macho) echo macho; return 0 ;;
  esac
  return 1
}

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
  if [ "${MXTK_PLATFORM:-$(mxtk_platform)}" = windows ]; then
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
# mxtk_sqlite_ro_uri <path> — print a read-only SQLite URI for <path>: absolute, URI-escaped,
# ending in ?mode=ro. Hand it to Python as sqlite3.connect(uri, uri=True).
# Escaping is the point: a plain "file:%s?mode=ro" cuts the path at a '#' or '?' in any folder
# name ("a #2", "b?c"), drops mode=ro with it, and SQLite then CREATES an empty file at the
# truncated path (a zero-byte "a " beside the model folder) and opens that instead.
# Uses $PY when set, else resolve_py. Returns 1 when there is no Python. The caller decides
# whether to pass the path through native_path first; this does no platform conversion.
# ---------------------------------------------------------------------------
mxtk_sqlite_ro_uri() {
  local py="${PY:-${MXTK_PY_MEMO:-$(resolve_py 2>/dev/null || true)}}"
  [ -n "$py" ] || return 1
  "$py" -c "import os,sys,urllib.request as u
print('file:'+u.pathname2url(os.path.abspath(sys.argv[1]))+'?mode=ro')" "$1" | tr -d '\r'
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
  # Memo: exec.sh exports MXTK_MODEL_VERSION once per run, so the many find_mxbuild calls
  # in one exec (and the scripts it starts) do not each spawn sqlite3/python (#584: a
  # process start costs 58-94 ms on a Defender-scanned Windows machine).
  # Also for the run's own model path: exec.sh passes it explicitly (mxtk_ensure_mxbuild, the
  # gate), and without this each of those calls started sqlite3 | head | tr again.
  if [ -n "${MXTK_MODEL_VERSION:-}" ] && { [ -z "$mpr" ] || [ "$mpr" = "${MXTK_MPR_MEMO:-}" ]; }; then printf '%s\n' "$MXTK_MODEL_VERSION"; return 0; fi
  [ -n "$mpr" ] || mpr="$(find_mpr 2>/dev/null)" || return 1
  [ -f "$mpr" ] || return 1
  if command -v sqlite3 >/dev/null 2>&1; then
    v=$(sqlite3 -readonly "$mpr" 'select _ProductVersion from _MetaData' 2>/dev/null) || true
    v="${v%%$'\n'*}"; v="${v//$'\r'/}"   # head -1 | tr -d '\r' without two more processes
  fi
  if [ -z "$v" ]; then
    py="${PY:-${MXTK_PY_MEMO:-$(resolve_py 2>/dev/null || true)}}"
    # One Python start, not two: the read-only URI (what mxtk_sqlite_ro_uri prints) is built
    # in the same interpreter that opens it. On Windows there is usually no sqlite3 CLI, so
    # this is the path, and a Python start costs more than any other process there.
    if [ -n "$py" ]; then
      v=$("$py" -c "import sqlite3,sys,os,urllib.request as u
c=sqlite3.connect('file:'+u.pathname2url(os.path.abspath(sys.argv[1]))+'?mode=ro',uri=True)
print(c.execute('select _ProductVersion from _MetaData').fetchone()[0])" "$(native_path "$mpr")" 2>/dev/null) || true
      v="${v%%$'\n'*}"; v="${v//$'\r'/}"
    fi
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
  # In-shell (was basename + cut + sed + grep: four process starts per installed Studio Pro).
  local base="$1" v3 re a b c _rest
  while [ "${base%/}" != "$base" ] && [ -n "${base%/}" ]; do base="${base%/}"; done
  base="${base##*/}"
  IFS=. read -r a b c _rest <<< "$2"
  v3="$a${b:+.$b}${c:+.$c}"
  [ -n "$v3" ] || return 1
  re="(^|[^0-9.])${v3//./\\.}(\\.[0-9]+)?([^0-9.]|\\.[^0-9]|\$)"
  [[ $base =~ $re ]]
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
  # Per-run memo exec.sh exports (#584) — its own name, so the explicit-override semantics of
  # MXBUILD_PATH (no version match, mxtk_ensure_mxbuild's warning) never reach child scripts.
  if [ -n "${MXTK_MXBUILD_MEMO:-}" ] && [ -x "$MXTK_MXBUILD_MEMO" ]; then echo "$MXTK_MXBUILD_MEMO"; return 0; fi
  local ver m
  if ver=$(mxtk_model_version 2>/dev/null) && m=$(mxtk_mxbuild_for_version "$ver"); then
    echo "$m"; return 0
  fi
  local app cand="" cache
  if app=$(find_sp_app 2>/dev/null); then
    case "${MXTK_PLATFORM:-$(mxtk_platform)}" in
      windows) cand="$app/modeler/mxbuild.exe" ;;
      *)       cand="$app/Contents/modeler/mxbuild" ;;
    esac
    [ -x "$cand" ] && { echo "$cand"; return 0; }
  fi
  if cache=$(find_mxcli_cache); then
    local cmxb
    case "${MXTK_PLATFORM:-$(mxtk_platform)}" in
      windows) cmxb="$cache/modeler/mxbuild.exe" ;;
      *)       cmxb="$cache/modeler/mxbuild" ;;
    esac
    [ -x "$cmxb" ] && { echo "$cmxb"; return 0; }
  fi
  [ -n "$cand" ] && { echo "$cand"; return 0; }
  return 1
}

# _mxtk_java_want — the JDK major the model's Mendix version needs: 25 for 11.14 and above,
# else 21 (also when the version cannot be read).
_mxtk_java_want() {
  local mver mmaj mmin want=21
  if mver=$(mxtk_model_version 2>/dev/null); then
    mmaj="${mver%%.*}"; mmin="${mver#*.}"; mmin="${mmin%%.*}"
    if [ "$mmaj" -gt 11 ] 2>/dev/null || { [ "$mmaj" -eq 11 ] && [ "$mmin" -ge 14 ]; } 2>/dev/null; then want=25; fi
  fi
  echo "$want"
}

# find_java_note — prints ONE line when find_java had to use a JDK other than the one the
# model needs (macOS, JAVA_HOME unset, wanted JDK not installed); prints nothing otherwise.
# find_java runs in a $(...) whose stderr every caller discards, so the warning has to be a
# separate call the caller prints:
#   _n="$(find_java_note || true)"; [ -n "$_n" ] && echo "WARN: $_n" >&2
find_java_note() {
  [ -n "${JAVA_HOME:-}" ] && [ -d "$JAVA_HOME" ] && return 0
  local jhbin="${MXTK_JAVA_HOME_BIN:-/usr/libexec/java_home}" want used
  [ "${MXTK_PLATFORM:-$(mxtk_platform)}" = macos ] && [ -x "$jhbin" ] || return 0
  want=$(_mxtk_java_want)
  "$jhbin" -F -v "$want" >/dev/null 2>&1 && return 0
  used=$(find_java 2>/dev/null) || used="none found"
  echo "wanted JDK $want (for this model's Mendix version) is not installed, using $used; mxbuild may fail with a Java version error. Install JDK $want or set JAVA_HOME in toolkit.env."
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
  # macOS: the JDK that matches the model. Studio Pro 11.13 and below build with JDK 21 (with
  # JDK 25 as the default, the deploy build's gradle 8.5 fails: "Unsupported class file major
  # version 69", mxbuild exit 3, empty problems[] — field project 2026-09-26, Mendix 11.12.2);
  # 11.14 and above need JDK 25 (Gradle 9.1+; "release version 25 not supported" on JDK 21 —
  # field report, Mendix 11.15; docs.mendix.com/refguide/system-requirements). The model's
  # version is read from the .mpr; unreadable → want 21 as before.
  # Plain `java_home -v N` NEVER fails on macOS: when N is not installed it prints the default
  # JDK and exits 0. Only `-F -v N` fails, so detection uses -F. A missing wanted JDK still
  # falls back to the default (nothing new blocks), and find_java_note says so, because every
  # caller discards find_java's stderr. Platform-guarded: java_home is mac-only.
  # MXTK_JAVA_HOME_BIN overrides the binary (tests).
  local jhbin="${MXTK_JAVA_HOME_BIN:-/usr/libexec/java_home}" want
  if [ "${MXTK_PLATFORM:-$(mxtk_platform)}" = macos ] && [ -x "$jhbin" ]; then
    want=$(_mxtk_java_want)
    jh=$("$jhbin" -F -v "$want" 2>/dev/null) && [ -n "$jh" ] && { echo "$jh"; return 0; }
    jh=$("$jhbin" 2>/dev/null) && [ -n "$jh" ] && { echo "$jh"; return 0; }
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
  case "${MXTK_PLATFORM:-$(mxtk_platform)}" in
    windows) echo "$jh/bin/java.exe" ;;
    *)       echo "$jh/bin/java" ;;
  esac
}

# ---------------------------------------------------------------------------
# Watcher pause and infra retry around the exec gate's mxbuild.
#
# Field (a migration project, 12 modules, 2026-10-16/17): the gate's mxbuild and a live
# `mxcli run --local --watch` on the SAME project both write deployment/. One of the two dies
# part-way ("Directory not empty: .../deployment/web", mxbuild exit 1 or 3, no errors file):
# 17 of 27 failed gates, against 0 of 22 gates run in watcher-free copies of the same project.
#
# Chosen fix: pause the watcher for the length of the gate (SIGSTOP, then SIGCONT). mxbuild
# has no option that moves the deploy target's output out of <project>/deployment, so a
# separate output dir is not available; a pause needs no mxbuild support and no change to the
# watcher. Only the watcher process itself is stopped. Its runtime keeps serving, and a rebuild
# the watcher already started before the pause can still collide, which is what the retry below
# is for. exec.sh resumes the watcher in its EXIT trap too, so an interrupted run does not leave
# it stopped. A SIGKILL runs no trap, so the paused pids are also written to
# .mpr-snapshots/.watcher-paused; the next exec.sh resumes them once it holds the lock. The file
# is a dot FILE: the `*/` snapshot globs in restore-mpr.sh and snapshot-mpr.sh never match it.
# ---------------------------------------------------------------------------
MXTK_PAUSED_PIDS=""
MXTK_PAUSED_FILE=""
MXTK_GATE_RETRY_NOTE=""
MXTK_GATE_FIRST_OUT=""
MXTK_GATE_FIRST_EXIT=""
MXTK_GATE_INFRA_PERSISTENT=""   # errors[] text that already failed a build AND its retry this run

# mxtk_watcher_pids <project-root> - pids of `mxcli run --local --watch` that belong to this
# project. Exact match only: the watcher's project dir (the directory of its -p argument,
# resolved against its cwd, or its cwd when it has no -p) must equal the root after pwd -P. A
# substring test also hit a sibling `<App>-copy` and a nested `.claude/worktrees/x` watcher.
mxtk_watcher_pids() {
  local _root _pid _cmd _cwd _p _dir
  _root="$(cd "$1" 2>/dev/null && pwd -P)" || return 0
  for _pid in $(pgrep -f 'run --local' 2>/dev/null || true); do  # portability-ok: pgrep -f ships with Linux procps and macOS; Windows has no watcher to pause here
    [ "$_pid" = "$$" ] && continue
    _cmd="$(ps -o command= -p "$_pid" 2>/dev/null)" || continue
    case "$_cmd" in *mxcli*"run --local"*--watch*) ;; *) continue ;; esac
    _cwd="$(readlink "/proc/$_pid/cwd" 2>/dev/null || lsof -a -p "$_pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')"
    [ -n "$_cwd" ] && _cwd="$(cd "$_cwd" 2>/dev/null && pwd -P)"
    _p=""
    case "$_cmd" in
      *" -p "*) _p="${_cmd#* -p }" ;;
      *" --project "*) _p="${_cmd#* --project }" ;;
    esac
    if [ -n "$_p" ]; then
      case "$_p" in /*) ;; *) [ -n "$_cwd" ] || continue; _p="$_cwd/$_p" ;; esac
      # ps drops the quotes, so "-p /x/App copy/App.mpr" must not read as /x/App: keep the
      # longest run of words that exists on disk (it also drops any flags after the path).
      while [ ! -e "$_p" ]; do case "$_p" in *" "*) _p="${_p% *}" ;; *) continue 2 ;; esac; done
      if [ -d "$_p" ]; then _dir="$_p"; else _dir="$(dirname "$_p")"; fi
      _dir="$(cd "$_dir" 2>/dev/null && pwd -P)" || continue
    else
      _dir="$_cwd"
    fi
    [ -n "$_dir" ] && [ "$_dir" = "$_root" ] && echo "$_pid"
  done
  return 0
}

# mxtk_pause_watchers <project-root> - SIGSTOP every watcher of this project, remember the pids
# (in memory, and in <root>/.mpr-snapshots/.watcher-paused for a SIGKILL of this process).
mxtk_pause_watchers() {
  local _pid _cands
  MXTK_PAUSED_PIDS=""
  MXTK_PAUSED_FILE="$1/.mpr-snapshots/.watcher-paused"
  _cands="$(mxtk_watcher_pids "$1" | tr '\n' ' ')"
  [ -n "$_cands" ] || return 0
  # Record before stopping: a SIGKILL between kill -STOP and the record would leave a stopped
  # watcher nobody resumes. Resuming a pid that was never stopped is harmless.
  { mkdir -p "$1/.mpr-snapshots" && echo "$$ $_cands" > "$MXTK_PAUSED_FILE"; } 2>/dev/null || true
  for _pid in $_cands; do
    if kill -STOP "$_pid" 2>/dev/null; then
      MXTK_PAUSED_PIDS="$MXTK_PAUSED_PIDS $_pid"
      echo "  → paused the run --local --watch watcher (pid $_pid) for the gate; it resumes right after" >&2
    fi
  done
  if [ -n "$MXTK_PAUSED_PIDS" ]; then
    { mkdir -p "$1/.mpr-snapshots" && echo "$$$MXTK_PAUSED_PIDS" > "$MXTK_PAUSED_FILE"; } 2>/dev/null || true
  fi
  return 0
}

# mxtk_resume_watchers - SIGCONT whatever mxtk_pause_watchers stopped. Safe to call twice.
mxtk_resume_watchers() {
  local _pid
  for _pid in $MXTK_PAUSED_PIDS; do kill -CONT "$_pid" 2>/dev/null || true; done
  [ -n "$MXTK_PAUSED_FILE" ] && rm -f "$MXTK_PAUSED_FILE"
  MXTK_PAUSED_PIDS=""
  return 0
}

# mxtk_resume_leftover <project-root> - call once the exec lock is held. A watcher left stopped
# by an exec.sh that was SIGKILLed (its record is still on disk) is resumed when its pid still
# exists and is still a watcher of this project; the record is then cleared.
mxtk_resume_leftover() {
  local _f="$1/.mpr-snapshots/.watcher-paused" _rec _pid _live _n=0
  [ -f "$_f" ] || return 0
  _rec="$(head -1 "$_f" 2>/dev/null || true)"
  _live="$(mxtk_watcher_pids "$1")"
  for _pid in ${_rec#* }; do
    case "$_pid" in ''|*[!0-9]*) continue ;; esac
    if grep -Fxq -- "$_pid" <<<"$_live" && kill -CONT "$_pid" 2>/dev/null; then _n=$((_n+1)); fi
  done
  rm -f "$_f"
  [ "$_n" -gt 0 ] && echo "  → resumed $_n watcher(s) left stopped by an exec.sh that was killed during the gate"
  return 0
}

# mxtk_mxbuild_infra_only <errors-file> - true when mxbuild's errors file reports no Error
# problem and every errors[] message is a generic deploy-stage failure, never a reason about the
# model. Verbatim messages from a field build (#448, 2026-10-16, Mendix 11.15, exit 3, problems[]
# empty), each of which passed on the next build with no model change:
#   "Compilation of the app bundle failed."  ·  "An error occurred while compiling Theme files"
#   "An error occurred while cleaning excluded jar files & copying files."
#   "An error occurred while compiling Java actions"
# A version mismatch ("The MPR file located at ... could not be opened: Project version ...")
# matches neither form, so it is still never retried. No Python 3: false (no retry, as before).
mxtk_mxbuild_infra_only() {
  local _py="${PY:-${MXTK_PY_MEMO:-$(resolve_py 2>/dev/null || true)}}"
  [ -s "$1" ] && [ -n "$_py" ] || return 1
  "$_py" -c '
import json, re, sys
d = json.load(open(sys.argv[1]))
if any(isinstance(p, dict) and p.get("severity") == "Error" for p in d.get("problems") or []): sys.exit(1)
m = [(e.get("message", "") if isinstance(e, dict) else str(e)).strip() for e in d.get("errors") or []]
ok = re.compile(r"^(Compilation of the app bundle failed\.?|An error occurred while [^:]*)$")
sys.exit(0 if m and all(ok.match(x) and not re.search(r"CE[0-9]{4}", x) for x in m) else 1)
' "$(native_path "$1")" 2>/dev/null
}

# _mxtk_slurp <var> <file> — what `var=$(cat file)` does (whole file, trailing newlines
# stripped), without the subshell and the cat process. Empty when the file is unreadable.
_mxtk_slurp() {
  local _s=""
  IFS= read -r -d '' _s < "$2" 2>/dev/null || true
  while [ "${_s%$'\n'}" != "$_s" ]; do _s="${_s%$'\n'}"; done
  printf -v "$1" '%s' "$_s"
}

# mxtk_build_tree <mpr> — where the toolkit's full build runs. Sets MXTK_BUILD_MPR to the .mpr
# inside <project>/.mxtk/build/model/, a synced copy of the model directory (bin/build-tree.py: one
# Python start, incremental), and MXTK_BUILD_PLACE=copy; or, when that cannot be done, to <mpr>
# itself with MXTK_BUILD_PLACE=in-place and MXTK_BUILD_NOTE saying why.
# WHY (#686): mxbuild writes <app dir>/deployment/ whatever --target or --output says (measured on
# mxbuild 11.13.0: the deploy AND the package target both rewrote deployment/web/dist), and a
# running `mxcli run --local --watch` serves deployment/web — every toolkit full build left it with
# no web client (/dist/index.js 404) until a restart. deployment/ is now only for what mxcli run
# builds. The errors file, the error count and its CE codes come from the same model bytes; the
# stamp and fingerprints are taken from the real model by their own callers. Cost: one Python
# start per build plus a copy of the model directory and one deployment/ under .mxtk/build/ on disk
# (bin/doctor.sh --cleanup removes it). MXTK_GATE_IN_PLACE=1 builds in place, as before.
mxtk_build_tree() {
  local _r="${PROJECT_ROOT:-$(dirname "$1")}" _o _py
  MXTK_BUILD_MPR="$1"; MXTK_BUILD_PLACE=in-place; MXTK_BUILD_NOTE=""; MXTK_BUILD_SRC=""; MXTK_BUILD_DST=""
  MXTK_BUILD_SRC_N=""; MXTK_BUILD_DST_N=""
  [ "${MXTK_GATE_IN_PLACE:-0}" = 1 ] && { MXTK_BUILD_NOTE="MXTK_GATE_IN_PLACE=1"; return 0; }
  [ -f "$_r/bin/build-tree.py" ] || { MXTK_BUILD_NOTE="bin/build-tree.py not installed (sync-project.sh)"; return 0; }
  _py="${PY:-${MXTK_PY_MEMO:-$(resolve_py 2>/dev/null || true)}}"
  [ -n "$_py" ] || { MXTK_BUILD_NOTE="no Python 3"; return 0; }
  mxtk_build_lock_take "$_r" || { MXTK_BUILD_NOTE="$MXTK_BUILD_LOCK_NOTE"; return 0; }
  if _o="$("$_py" -I "$(native_path "$_r/bin/build-tree.py")" "$(native_path "$1")" "$(native_path "$_r/.mxtk/build/model")" 2>&1)"; then
    MXTK_BUILD_MPR="${_o##*$'\n'}"; MXTK_BUILD_MPR="${MXTK_BUILD_MPR%$'\r'}"
    MXTK_BUILD_SRC="${_o%$'\n'*}"; MXTK_BUILD_SRC="${MXTK_BUILD_SRC##*$'\n'}"; MXTK_BUILD_SRC="${MXTK_BUILD_SRC%$'\r'}"
    # Python prints native paths: C:\... on Windows, which is also how mxbuild.exe names files in
    # its output there. Keep that form for the rewrite (mxtk_build_tree_unmap), use the POSIX one here.
    MXTK_BUILD_SRC_N="$MXTK_BUILD_SRC"; MXTK_BUILD_DST_N="${MXTK_BUILD_MPR%[\\/]*}"
    case "$MXTK_BUILD_MPR" in [A-Za-z]:*) MXTK_BUILD_MPR="$(mxtk_posix_path "$MXTK_BUILD_MPR")" ;; esac
    case "$MXTK_BUILD_SRC" in [A-Za-z]:*) MXTK_BUILD_SRC="$(mxtk_posix_path "$MXTK_BUILD_SRC")" ;; esac
    if [ -f "$MXTK_BUILD_MPR" ]; then
      MXTK_BUILD_PLACE=copy; MXTK_BUILD_DST="${MXTK_BUILD_MPR%/*}"
      return 0
    fi
    MXTK_BUILD_SRC=""; MXTK_BUILD_SRC_N=""; MXTK_BUILD_DST_N=""
    MXTK_BUILD_MPR="$1"
  fi
  MXTK_BUILD_NOTE="the copy failed: ${_o##*$'\n'}"
}
# Stale-lock takeover, shared by exec.sh's .exec.lock and the full-build copy's .build.lock.
# Taking over is serialised through a second O_EXCL file, <lock>.takeover; under it the lock is
# re-read and removed ONLY if it still holds exactly the stale line judged by the caller, so the
# compare-then-rm cannot hit a fresh lock (independent review of #304: 12 contenders gave up to 3
# holders with a plain check-then-rm; the #721 review reproduced 4 on the first .build.lock).
# A takeover file left by a holder killed inside those microseconds is stale once its pid is dead
# or it is older than 10 s (an empty one once it is over a minute old, review of #324); it is
# moved aside and put back with `ln` (never clobbers) if what was moved is not the one judged stale.
mxtk_lock_takeover() {  # $1 = lock file, $2 = the stale lock line; 0 iff it was removed (or already gone)
  local _lk="$1" _stale="$2" _tk _mine _t _tpid _tsince _tstale _now
  _tk="$_lk.takeover"; _mine="$$ ${EPOCHSECONDS:-$(date +%s)}"
  if ! ( set -o noclobber; printf '%s\n' "$_mine" > "$_tk" ) 2>/dev/null; then
    _t="$(head -1 "$_tk" 2>/dev/null || true)"; _tpid="${_t%% *}"; _tsince="${_t#* }"
    case "$_tsince" in ''|*[!0-9]*) _tsince=0 ;; esac
    _tstale=0
    if [ -n "$_t" ]; then
      { ! kill -0 "$_tpid" 2>/dev/null || [ $(( ${EPOCHSECONDS:-$(date +%s)} - _tsince )) -gt 10 ]; } && _tstale=1
    elif [ -n "$(find "$_tk" -mmin +1 2>/dev/null)" ]; then
      _tstale=1   # empty for over a minute: its creator died between the create and the write
    fi
    if [ "$_tstale" = 1 ]; then
      if mv "$_tk" "$_tk.stale.$$" 2>/dev/null; then
        # Remove what was moved ONLY if it is what was judged stale; anything else is someone's
        # live takeover file: put it back (ln never clobbers), and if that fails leave it be.
        # Same body as test-scratch.sh's take_over() — keep the two in step (PR #322).
        if [ "$(head -1 "$_tk.stale.$$" 2>/dev/null || true)" = "$_t" ]; then rm -f "$_tk.stale.$$"
        else ln "$_tk.stale.$$" "$_tk" 2>/dev/null && rm -f "$_tk.stale.$$"; fi
      fi
    fi
    return 1
  fi
  _now="$(head -1 "$_lk" 2>/dev/null || true)"
  [ "$_now" = "$_stale" ] && rm -f "$_lk"
  [ "$(head -1 "$_tk" 2>/dev/null || true)" = "$_mine" ] && rm -f "$_tk"   # only our own takeover file
  return 0
}
# mxtk_lock_live <pid> <who> — 0 iff the pid is alive, not a zombie, and (where ps can show it) its
# command line names <who>, the script that wrote the lock; otherwise the pid was reused.
mxtk_lock_live() {
  local a
  case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$1" 2>/dev/null || return 1
  case "$(sed 's/.*) //' "/proc/$1/stat" 2>/dev/null | cut -d' ' -f1)" in Z) return 1 ;; esac
  [ -n "${2:-}" ] || return 0
  a="$(ps -o args= -p "$1" 2>/dev/null || true)"
  case "$a" in ""|*"$2"*) return 0 ;; esac
  return 1
}

# One full build at a time in the copy (#686 review). The exec gate and a pre-push or module-close
# verify-model.sh can build at the same moment, and two syncs + two mxbuilds in one folder would
# corrupt each other's output. Lock: <root>/.mpr-snapshots/.build.lock, "<pid> <epoch> <who>",
# taken with noclobber (O_EXCL, no process start) — the same shape as exec.sh's .exec.lock. A
# held lock is waited on (2 s polls, MXTK_BUILD_LOCK_WAIT, default 900 s: a build takes minutes);
# a lock whose pid is gone is stale and taken over; still held after the wait → this build runs
# in place, said out loud (correct verdict; only the watch client may need a restart). Taken in
# mxtk_build_tree, released after the build: by mxtk_gate_mxbuild (unless MXTK_BUILD_LOCK_KEEP=1 —
# exec.sh, which removes it with its own lock on exit), and by verify-model.sh.
MXTK_BUILD_LOCK=""; MXTK_BUILD_LOCK_NOTE=""
mxtk_build_lock_take() {  # $1 = project root. 0 = ours (taken now or already), 1 = not taken
  local f="$1/.mpr-snapshots/.build.lock" held hp waited=0 max="${MXTK_BUILD_LOCK_WAIT:-900}" told=0
  MXTK_BUILD_LOCK_NOTE=""
  [ -d "$1/.mpr-snapshots" ] || mkdir -p "$1/.mpr-snapshots" 2>/dev/null
  while :; do
    if ( set -o noclobber; printf '%s %s %s\n' "$$" "${EPOCHSECONDS:-$(date +%s)}" "${0##*/}" > "$f" ) 2>/dev/null; then
      MXTK_BUILD_LOCK="$f"; return 0
    fi
    held=""; read -r held < "$f" 2>/dev/null || true; hp="${held%% *}"
    [ "$hp" = "$$" ] && { MXTK_BUILD_LOCK="$f"; return 0; }
    if [ -z "$held" ]; then sleep 1; waited=$((waited + 1)); [ "$waited" -lt "$max" ] && continue; fi   # being written
    if [ -n "$held" ] && ! mxtk_lock_live "$hp" "${held#* * }"; then
      # Stale (dead, zombie, or pid reused): the shared O_EXCL takeover, then try again.
      mxtk_lock_takeover "$f" "$held" || { sleep 1; waited=$((waited + 1)); }
      continue
    fi
    if [ "$waited" -ge "$max" ]; then
      MXTK_BUILD_LOCK_NOTE="another full build (pid ${hp:-?}) held .mxtk/build/ for ${waited}s"; return 1
    fi
    [ "$told" = 1 ] || { echo "  … another full build (pid ${hp:-?}: ${held#* * }) is using .mxtk/build/ — waiting for it" >&2; told=1; }
    sleep 2; waited=$((waited + 2))
  done
}
mxtk_build_lock_release() {  # removes the lock only while it is ours
  local own=""
  [ -n "$MXTK_BUILD_LOCK" ] && [ -f "$MXTK_BUILD_LOCK" ] || return 0
  read -r own < "$MXTK_BUILD_LOCK" 2>/dev/null || true
  [ "${own%% *}" = "$$" ] && rm -f "$MXTK_BUILD_LOCK"
  MXTK_BUILD_LOCK=""; return 0
}

# mxtk_build_tree_paths — a Java compile error printed from the copy names the copy's file; point it
# back at the real one, so nobody edits .mxtk/build/. Pure bash, no process.
mxtk_build_tree_paths() { mxtk_build_tree_unmap MXTK_MXBUILD_OUT; }
# mxtk_build_tree_unmap <variable name> — rewrite the copy's paths in that variable to the real
# model folder's: the POSIX form, the native C:\... form mxbuild.exe prints on Git Bash, and that
# form with forward slashes. The pattern is quoted, so a [ * ? in the project path is literal
# (#721 review). Bash builtins only; printf -v is bash 3.1+.
mxtk_build_tree_unmap() {
  [ "${MXTK_BUILD_PLACE:-}" = copy ] && [ -n "$MXTK_BUILD_DST" ] || return 0
  local _v _f _t
  eval "_v=\${$1-}"
  _v="${_v//"$MXTK_BUILD_DST"/$MXTK_BUILD_SRC}"
  if [ -n "$MXTK_BUILD_DST_N" ] && [ "$MXTK_BUILD_DST_N" != "$MXTK_BUILD_DST" ]; then
    _v="${_v//"$MXTK_BUILD_DST_N"/$MXTK_BUILD_SRC_N}"
    _f="${MXTK_BUILD_DST_N//\\//}"; _t="${MXTK_BUILD_SRC_N//\\//}"
    _v="${_v//"$_f"/$_t}"
  fi
  printf -v "$1" '%s' "$_v"
}

# mxtk_gate_mxbuild <mpr> <timeout-seconds> <errors-file> - the exec gate's way to run
# mxbuild: mxtk_mxbuild_error_count with this project's watcher paused around it, and ONE
# retry when mxbuild exits 1 or 3 and left no sign of a model problem (no CE code in its
# output, nothing in the errors file). That shape is an infrastructure failure, not a verdict
# on the model; a real model error always names a CE code. An errors file with content (for
# example a version mismatch in errors[]) is deterministic and is not retried, with one
# exception (#448): a file whose only content is a generic deploy-stage message is the same
# infra shape (mxtk_mxbuild_infra_only, above). The retry check runs only after exit 1 or 3,
# so a clean build never pays for it.
# Prints nothing on stdout (callers discard the count); sets the same MXTK_MXBUILD_* globals as
# mxtk_mxbuild_error_count, plus MXTK_GATE_RETRY_NOTE ("retry after infra exit" or empty); after a
# retry MXTK_GATE_FIRST_OUT / MXTK_GATE_FIRST_EXIT hold the FIRST attempt's output and exit code
# (the MXTK_MXBUILD_* globals describe the final attempt only).
# Returns mxtk_mxbuild_error_count's code for the final attempt.
mxtk_gate_mxbuild() {
  local _mpr="$1" _timeout="${2:-0}" _ef="$3" _rc=0
  MXTK_GATE_RETRY_NOTE=""; MXTK_GATE_FIRST_OUT=""; MXTK_GATE_FIRST_EXIT=""
  # MXTK_GATE_KIND=check (set by exec.sh's gate-kind decision): `mx check` instead of a
  # deploy build. No infra retry: mx check has no deploy stage to collide on.
  if [ "${MXTK_GATE_KIND:-full}" = "check" ]; then
    mxtk_mx_check_error_count "$_mpr" "$_timeout" "$_ef" >/dev/null || _rc=$?
    return "$_rc"
  fi
  mxtk_pause_watchers "${PROJECT_ROOT:-$(dirname "$_mpr")}"
  mxtk_build_tree "$_mpr"; _mpr="$MXTK_BUILD_MPR"   # a copy: deployment/ is the running app's (#686)
  mxtk_mxbuild_error_count "$_mpr" "$_timeout" "$_ef" >/dev/null || _rc=$?
  mxtk_build_tree_paths
  case "${MXTK_MXBUILD_EXIT:-}" in
    1|3)
      # A deploy-stage message that already survived one retry in this run (the baseline's)
      # is persistent, not a collision: building a 4th time would only cost time.
      if [ -n "$MXTK_GATE_INFRA_PERSISTENT" ] && [ "${MXTK_MXBUILD_WHY:-}" = "$MXTK_GATE_INFRA_PERSISTENT" ]; then
        echo "  ⚠ no retry: mxbuild failed with the same deploy-stage message on the earlier build and its retry (${MXTK_MXBUILD_WHY})" >&2
      elif ! grep -Eq -- 'CE[0-9]{4}' <<<"${MXTK_MXBUILD_OUT:-}" \
         && { [ ! -s "$_ef" ] || mxtk_mxbuild_infra_only "$_ef"; }; then
        echo "  ⚠ retry after infra exit: mxbuild exited $MXTK_MXBUILD_EXIT with no CE code and no model problem${MXTK_MXBUILD_WHY:+ ($MXTK_MXBUILD_WHY)}; building once more" >&2
        MXTK_GATE_RETRY_NOTE="retry after infra exit"
        MXTK_GATE_FIRST_OUT="${MXTK_MXBUILD_OUT:-}"; MXTK_GATE_FIRST_EXIT="$MXTK_MXBUILD_EXIT"
        : > "$_ef"
        _rc=0
        mxtk_mxbuild_error_count "$_mpr" "$_timeout" "$_ef" >/dev/null || _rc=$?
        mxtk_build_tree_paths
        # Same deploy-stage failure twice: remember its text, so a later build in this run
        # (the gate after the baseline) does not retry it again (#494 review).
        case "${MXTK_MXBUILD_EXIT:-}" in
          1|3) [ -n "${MXTK_MXBUILD_WHY:-}" ] && mxtk_mxbuild_infra_only "$_ef" \
                 && MXTK_GATE_INFRA_PERSISTENT="$MXTK_MXBUILD_WHY" ;;
        esac
      fi ;;
  esac
  [ "${MXTK_BUILD_LOCK_KEEP:-0}" = 1 ] || mxtk_build_lock_release   # exec.sh releases it with its own lock
  mxtk_resume_watchers
  return "$_rc"
}

# ---------------------------------------------------------------------------
# Reaping the deno helper a toolkit-started mxbuild leaves behind (#708).
#
# WHY. mxbuild (and `mx`, and mxcli's `docker check`/`docker build`, which run mxbuild) starts
# modeler/tools/deno/<platform>/deno (WebExtensionsRunner), ~290 MB, that outlives it with
# parent PID 1 and never exits. Field, 2026-11-06 (pipeline-mode experiment for #700, 16 GB
# container): 47 of them held 13 GB, and every later build was OOM-killed. doctor --cleanup lists
# them, but nothing called it, so each exec, module close, doctor probe and fixture added one.
#
# HOW (process group, never a name match on the whole machine). mxtk_reap_launch_begin turns on
# bash job control (`set -m`) for the ONE `cmd &` that follows, so that cmd leads a new process
# group whose id is its own pid; mxtk_reap_launch_end turns it back off. Everything the cmd starts
# inherits that group, deno included, and keeps it after mxbuild exits and deno is re-parented to
# PID 1. mxtk_reap_group <pid>, called once the cmd has exited, stops only processes that are BOTH
# in that group AND named deno / deno.exe. A deno the toolkit did not start (Studio Pro's, another
# session's, a user's `deno run`) is in another group and is never touched; no `pkill`, no pattern
# over the process table. A group id is not reused while any member lives, so the group still names
# this invocation's children when it is read. `set -m` in a non-interactive bash neither moves the
# shell into another group nor takes the terminal (checked under a pty and in a pipeline).
# Field run (2026-11-09, Linux x86-64, real mxbuild 11.13.0 on a copy of a 197 MB test app, while
# another experiment's mxbuild ran on the same machine): through mxtk_gate_mxbuild, mxbuild pid
# 22279 / pgid 22279 started deno pid 25497 / ppid 22279 / pgid 22279, still alive 19 s in; the call
# reaped 1 and no deno of that group was left. Through mxtk_reaped: mxbuild 23436 / pgid 23436, deno
# 27070 / pgid 23436, gone afterwards, while two orphaned denos of the other experiment (pgid 11043
# and 21660, ppid 1) were left running, untouched.
# Cost: when the group is already empty (the common case: nothing stray) the check is the `kill -0`
# builtin, no process start; one `ps` only when something of the group is still alive.
# Platforms: Linux and macOS (bash 3.2 has `set -m`; no `setsid` needed). Git Bash: skipped —
# mxbuild.exe and deno.exe are native Windows processes outside MSYS process groups, so group
# membership cannot be read reliably there; doctor --cleanup (wmic) stays the path on Windows.
# MXTK_NO_REAP=1 turns all of this off (the old behaviour).
MXTK_REAPED_N=0
_MXTK_REAP_ON=0
_MXTK_REAP_HADM=0
mxtk_reap_launch_begin() {
  _MXTK_REAP_ON=0; _MXTK_REAP_HADM=0
  [ "${MXTK_NO_REAP:-0}" = 1 ] && return 0
  case "${OSTYPE:-}" in msys*|cygwin*|win*) return 0 ;; esac
  case $- in *m*) _MXTK_REAP_HADM=1 ;; esac
  set -m 2>/dev/null || true
  case $- in *m*) _MXTK_REAP_ON=1 ;; esac
  return 0
}
mxtk_reap_launch_end() {
  [ "$_MXTK_REAP_HADM" = 1 ] || set +m 2>/dev/null || true
  return 0
}
# mxtk_reap_group <pid> — stop the deno processes still in <pid>'s process group. Sets MXTK_REAPED_N.
mxtk_reap_group() {
  local _g="$1" _p _pg _c _kill=""
  MXTK_REAPED_N=0
  [ "$_MXTK_REAP_ON" = 1 ] && [ -n "$_g" ] || return 0
  kill -0 -- "-$_g" 2>/dev/null || return 0
  while read -r _p _pg _c; do
    [ "$_pg" = "$_g" ] && [ "$_p" != "$_g" ] || continue
    case "${_c##*/}" in deno|deno.exe) _kill="$_kill $_p"; MXTK_REAPED_N=$((MXTK_REAPED_N + 1)) ;; esac
  done <<EOT
$(ps -A -o pid=,pgid=,comm= 2>/dev/null)
EOT
  # shellcheck disable=SC2086
  [ -z "$_kill" ] || kill $_kill 2>/dev/null || true
  return 0
}
# mxtk_reaped <cmd...> — run cmd in the foreground (the caller's redirections apply; give it
# `< /dev/null`), then reap its deno. Returns cmd's exit code.
# Signals. In its own group, cmd no longer receives the terminal's Ctrl-C. So the wait runs in a
# ( ... ) subshell that stays in the caller's (foreground) group: on INT/TERM that subshell stops
# cmd's group and ends (130/143), while the caller gets the same Ctrl-C and runs its own trap or
# default action, exactly as before. The INT/TERM trap is set only inside that subshell: the
# caller's traps are never read, reset or re-raised (bash 3.2 has no BASHPID, and `trap -p` in a
# subshell shows the parent's traps, so save/restore/re-raise could not be done right there).
# A TERM sent to the caller's pid alone reaches the caller only, as it did before this helper.
# NOT reaped (#708 review): a command that starts mxbuild in a NEW process group of its own.
# mxcli does (field run, 2026-11-09, this machine: an `mxcli run --local` pid 21500 / pgid 21500
# had its mxbuild at pid 21600 / pgid 21600, and that mxbuild's deno at pgid 21600). So for
# `mxcli docker check/build/reload` the deno sits in mxbuild's group, not mxcli's, and this stops
# nothing; bin/doctor.sh --cleanup is the fallback there. Direct mxbuild / mx calls are reaped.
mxtk_reaped() {
  local _rc=0
  mxtk_reap_launch_begin
  if [ "$_MXTK_REAP_ON" != 1 ]; then mxtk_reap_launch_end; "$@" || _rc=$?; return "$_rc"; fi
  mxtk_reap_launch_end
  (
    _r=0
    mxtk_reap_launch_begin
    "$@" &
    _p=$!
    mxtk_reap_launch_end
    trap 'kill -TERM -- "-$_p" 2>/dev/null; exit 130' INT
    trap 'kill -TERM -- "-$_p" 2>/dev/null; exit 143' TERM
    wait "$_p" || _r=$?
    mxtk_reap_group "$_p"
    exit "$_r"
  ) || _rc=$?
  return "$_rc"
}

# mxtk_deno_orphans — the mxbuild helpers (a deno under modeler/tools/deno) whose parent is not a
# live mxbuild / mx / dotnet / Studio Pro: sets MXTK_ORPHAN_N and MXTK_ORPHAN_KB (resident memory).
# Same parent rule as bin/doctor.sh's mh_leftovers, without its 10-minute age floor: at an OOM, every
# orphan counts. Linux/macOS only (0 0 on Git Bash, where doctor --cleanup reads wmic instead).
mxtk_deno_orphans() {
  MXTK_ORPHAN_N=0; MXTK_ORPHAN_KB=0
  case "${OSTYPE:-}" in msys*|cygwin*|win*) return 0 ;; esac
  set -- $(ps -A -o pid=,ppid=,rss=,args= 2>/dev/null | awk '
    { pid = $1; pp[pid] = $2; rss[pid] = $3; a = $0; sub(/^ *[0-9]+ +[0-9]+ +[0-9]+ +/, "", a); args[pid] = a; ord[++n] = pid }
    END { c = 0; kb = 0
      for (i = 1; i <= n; i++) { p = ord[i]
        if (args[p] !~ /modeler\/tools\/deno\/[^ ]*deno(\.exe)?( |$)/) continue
        q = pp[p]
        if (q in args) { g = args[q]; sub(/ .*/, "", g); sub(/.*\//, "", g)
          if (g ~ /^(mxbuild|mx|mxutil|dotnet|MxBuild)(\.exe)?$/ || args[q] ~ /[Ss]tudio/) continue }
        c++; kb += rss[p] }
      print c, kb }')
  MXTK_ORPHAN_N="${1:-0}"; MXTK_ORPHAN_KB="${2:-0}"
}

# mxtk_mxbuild_oom_note <exit> [output] — when an mxbuild run was killed for lack of memory (exit
# 137, or an out-of-memory message in its output), print the plain cause and set MXTK_MXBUILD_OOM
# to it; returns 1 (and leaves it empty) otherwise. The count is what --cleanup can free.
MXTK_MXBUILD_OOM=""
mxtk_mxbuild_oom_note() {
  local _gb
  MXTK_MXBUILD_OOM=""
  [ "${1:-0}" != 0 ] || return 1
  if [ "$1" != 137 ]; then
    case "${2:-}" in *OutOfMemory*|*"out of memory"*|*"Out of memory"*|*"Cannot allocate memory"*|*"OOM-kill"*|*"oom-kill"*) ;; *) return 1 ;; esac
  fi
  mxtk_deno_orphans
  _gb="$(( MXTK_ORPHAN_KB / 1048576 )).$(( MXTK_ORPHAN_KB * 10 / 1048576 % 10 ))"
  MXTK_MXBUILD_OOM="build killed for lack of memory: $MXTK_ORPHAN_N orphaned deno processes hold $_gb GB — run bin/doctor.sh --cleanup"
  echo "  ✗ $MXTK_MXBUILD_OOM" >&2
  return 0
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
  # The overrides find_mxbuild / find_java answer first are read directly: exec.sh exports
  # MXBUILD_PATH for the run, and a set JAVA_HOME is what find_java returns, so the common
  # case starts no subshell (three before, each with its own probes behind it).
  if [ -n "${MXBUILD_PATH:-}" ]; then _mb="$MXBUILD_PATH"; else _mb="$(find_mxbuild 2>/dev/null || true)"; fi
  if [ -n "${JAVA_HOME:-}" ] && [ -d "$JAVA_HOME" ]; then
    _jh="$JAVA_HOME"
    case "${MXTK_PLATFORM:-$(mxtk_platform)}" in windows) _je="$_jh/bin/java.exe" ;; *) _je="$_jh/bin/java" ;; esac
  else
    _jh="$(find_java 2>/dev/null || true)"
    _je="$(find_java_exe 2>/dev/null || true)"
  fi
  if [ ! -x "$_mb" ] || [ ! -x "$_je" ]; then
    echo "?"; return 2
  fi

  if [ -z "$_ef" ]; then
    _ef=$(mktemp /tmp/mxbuild-errors.XXXXXX) || { echo "?"; return 2; }
    _own_ef=1
  fi
  _out=$(mktemp /tmp/mxbuild-out.XXXXXX) || { [ "$_own_ef" -eq 1 ] && rm -f "$_ef"; echo "?"; return 2; }

  mxtk_reap_launch_begin
  "$_mb" --java-home="$_jh" --java-exe-path="$_je" \
         --write-errors="$_ef" --target=deploy "$_mpr" \
         > "$_out" 2>&1 < /dev/null &
  _pid=$!
  mxtk_reap_launch_end   # its deno is reaped by group below (#708)
  # _timeout 0 = unbounded: exec.sh's real gate passes 0 unless MXTK_GATE_TIMEOUT is set,
  # because a large model's deploy build legitimately runs past any fixed default, and a
  # timed-out gate reads as "non-zero exit, no errors file" = FAIL = auto-restore of work
  # that was fine. doctor's self-test is the one caller that wants a bound (300s default).
  # Unbounded (the exec gate's default): nothing to poll for, so `wait` — a poll loop started a
  # `sleep 1` process per second of build (10 on a warm Linux build, 150+ on a cold Windows one).
  if [ "$_timeout" -gt 0 ]; then
    while kill -0 "$_pid" 2>/dev/null; do
      if [ "$_waited" -ge "$_timeout" ]; then
        kill "$_pid" 2>/dev/null; wait "$_pid" 2>/dev/null; mxtk_reap_group "$_pid"
        _mxtk_slurp MXTK_MXBUILD_OUT "$_out"; rm -f "$_out"
        MXTK_MXBUILD_EXIT=124
        [ "$_own_ef" -eq 1 ] && rm -f "$_ef"
        echo "?"; return 3
      fi
      sleep 1; _waited=$((_waited + 1))
    done
  fi
  wait "$_pid" || _exit=$?
  mxtk_reap_group "$_pid"
  _mxtk_slurp MXTK_MXBUILD_OUT "$_out"; rm -f "$_out"
  MXTK_MXBUILD_EXIT="$_exit"
  mxtk_mxbuild_oom_note "$_exit" "$MXTK_MXBUILD_OUT" || true

  if [ ! -s "$_ef" ] && [ "$_exit" -eq 0 ]; then
    [ "$_own_ef" -eq 1 ] && rm -f "$_ef"
    echo 0; return 0
  fi

  _py="${PY:-${MXTK_PY_MEMO:-$(resolve_py 2>/dev/null || true)}}"
  if [ -z "$_py" ]; then
    [ "$_own_ef" -eq 1 ] && rm -f "$_ef"
    echo "?"; return 1
  fi
  _count=$("$_py" -c "import json;d=json.load(open('$(native_path "$_ef")'));print(len([x for x in d.get('problems',[]) if x.get('severity')=='Error']))" 2>/dev/null)
  MXTK_MXBUILD_WHY=$(mxtk_mxbuild_why "$_ef" "$_py")
  [ -z "$MXTK_MXBUILD_WHY" ] && MXTK_MXBUILD_WHY="$MXTK_MXBUILD_OOM"   # BUILD-LOG names the cause (#708)
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
# capped at 300 chars, or nothing. A message whose details carry a compiler "error: ..." line
# gets that line appended: "An error occurred while compiling Java actions" alone does not say
# "release version 25 not supported" (JDK 21 on an 11.15 model, #576). errors[] is where mxbuild says why it did NOT check the
# model; problems[] is only the model's findings. Verbatim errors[] captured on
# A field project (2026-09-26, mxbuild 11.14.0 vs an 11.12.2 model, exit 3):
#   {"errors":[{"message":"The MPR file located at …/Marketplace.mpr could not be opened:
#    Project version '11.12.2' does not exactly match MxBuild version '11.14.0'. Use loose
#    version check option for less strict version checking.","details":""}],"problems":[]}
mxtk_mxbuild_why() {
  local _py="${2:-${PY:-${MXTK_PY_MEMO:-$(resolve_py 2>/dev/null || true)}}}"
  [ -s "$1" ] && [ -n "$_py" ] || return 0
  "$_py" -c "import json,re
d=json.load(open('$(native_path "$1")'))
def one(e):
  if not isinstance(e,dict): return str(e)
  m=re.search(r'error: ([^\\n]+)',e.get('details','') or '')
  return e.get('message','')+(' ('+m.group(1).strip()+')' if m else '')
print('; '.join(one(e) for e in d.get('errors',[]) or [])[:300])" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Check-only gate (opt-in: `Gate mode: check` in PROJECT.md; exec.sh decides per exec).
#
# `mx check` ships next to mxbuild and runs the same model consistency checks (CE codes) in
# ~12 s where a deploy build takes 18-165 s, because it skips the Java compile and the deploy
# packaging. What it cannot see is exactly that: Java compile errors, including a model change
# that breaks a generated proxy a Java action uses. exec.sh therefore still runs the full build
# when those can change (mxtk_gate_kind_decide in exec.sh) — this is the cheap path only.
# WHY (#584/#585, Windows field reports): mxbuild was the largest single cost per exec there.
#
# mxtk_java_fp <project-root> — content fingerprint of the files only a full build compiles
# (javasource/ javascriptsource/ theme/ userlib/ widgets/). Content, not git state: committing an
# unchanged file must not read as a change. javasource/*/proxies/ is excluded: mxbuild regenerates
# it from the model on every full build. exec.sh (gate kind) and verify-model.sh record it.
mxtk_java_fp() {
  ( cd "$1" 2>/dev/null || exit 0
    # File ARGUMENTS, not --stdin-paths: git resolves stdin paths from the repository top, so in a
    # model folder below it (app/ on a two-tree checkout, apps/<X>/) the cwd-relative names failed
    # to open and every fingerprint hashed the same (PR #700 review). Arguments are cwd-relative.
    # Same names and hashes as before on a single-tree checkout, and no extra process (#687 budget).
    _l="$(git ls-files -co --exclude-standard -- javasource javascriptsource theme userlib widgets 2>/dev/null \
          | grep -v '^javasource/[^/]*/proxies/' || true)"
    { printf '%s\n' "$_l"
      if [ -n "$_l" ]; then ( set -f; IFS='
'; git hash-object -- $_l ) 2>/dev/null; fi; } \
      | cksum | { read -r _ck _; printf '%s\n' "$_ck"; } )
}

# mxtk_model_java_fp [project root] — mxtk_java_fp of the MODEL's folder, where javasource/,
# javascriptsource/, theme/, userlib/ and widgets/ sit beside the .mpr (app/ on a two-tree checkout).
# The one fingerprint exec.sh (gate kind), verify-model.sh and the pre-push hook record and compare:
# fingerprinting the project root on a two-tree checkout saw no Java at all, and a hook that used the
# model dir against a root-recorded value read every push as a Java change (PR #700 review).
mxtk_model_java_fp() {
  local r="${1:-$PROJECT_ROOT}" d
  d="$(PROJECT_ROOT="$r" find_model_dir 2>/dev/null)" || d=""
  mxtk_java_fp "${d:-$r}"
}

# mxtk_find_mx — the `mx` tool beside the resolved mxbuild (same version by construction).
mxtk_find_mx() {
  local _mb _d _c
  _mb="${MXBUILD_PATH:-$(find_mxbuild 2>/dev/null || true)}"
  [ -n "$_mb" ] || return 1
  _d="${_mb%/*}"; [ "$_d" != "$_mb" ] || _d=.
  for _c in "$_d/mx" "$_d/mx.exe"; do [ -x "$_c" ] && { echo "$_c"; return 0; }; done
  return 1
}

# mxtk_mx_check_to_mxbuild <mx-check.json> <out.json> [python] — rewrite `mx check -j` output
# into the mxbuild --write-errors shape exec.sh's err_set/err_report/err_codes read:
#   {"errors":[...],"problems":[{"severity":"Error","errorCode","message","locations":[{module,document,element}]}]}
# Golden input: tests/wave2/fixtures/mx-check/mx-check-11.13.0-CE1613.json (captured, mx 11.13.0).
mxtk_mx_check_to_mxbuild() {
  local _py="${3:-${PY:-${MXTK_PY_MEMO:-$(resolve_py 2>/dev/null || true)}}}"
  [ -n "$_py" ] || return 1
  "$_py" -c "import json,sys
d=json.load(open(sys.argv[1]))
def loc(l): return {'module':l.get('module-name',''),'document':l.get('document-name',''),'element':l.get('element-name','')}
probs=[{'severity':'Error','errorCode':e.get('code',''),'message':e.get('message',''),
        'locations':[loc(l) for l in e.get('locations') or []]} for e in d.get('errors') or []]
json.dump({'errors':[],'problems':probs,'source':'mx check'},open(sys.argv[2],'w'))
print(len(probs))" "$(native_path "$1")" "$(native_path "$2")" 2>/dev/null
}

# mxtk_mx_check_error_count <mpr> <timeout-seconds> [errors-file] — mxtk_mxbuild_error_count's
# contract (same globals, same return codes, same printed count), backed by `mx check -j`.
# The errors file it leaves is in mxbuild's shape (mxtk_mx_check_to_mxbuild), so every reader
# downstream is unchanged. A run that produced no JSON is "?" with the output tail in
# MXTK_MXBUILD_WHY — never 0.
mxtk_mx_check_error_count() {
  local _mpr="$1" _timeout="${2:-300}" _ef="${3:-}" _own_ef=0
  local _mx _out _js _pid _waited=0 _exit=0 _count
  MXTK_MXBUILD_OUT=""; MXTK_MXBUILD_EXIT=""; MXTK_MXBUILD_WHY=""
  _mx="$(mxtk_find_mx)" || { echo "?"; return 2; }
  if [ -z "$_ef" ]; then _ef=$(mktemp /tmp/mxcheck-errors.XXXXXX) || { echo "?"; return 2; }; _own_ef=1; fi
  _out=$(mktemp /tmp/mxcheck-out.XXXXXX) || { echo "?"; return 2; }
  _js=$(mktemp /tmp/mxcheck-json.XXXXXX) || { rm -f "$_out"; echo "?"; return 2; }
  rm -f "$_js"   # mx writes the file itself; an empty pre-existing one would read as "no output"
  mxtk_reap_launch_begin
  "$_mx" check "$_mpr" -j "$(native_path "$_js")" > "$_out" 2>&1 < /dev/null &
  _pid=$!
  mxtk_reap_launch_end
  if [ "$_timeout" -gt 0 ]; then   # unbounded: `wait`, no per-second sleep process
    while kill -0 "$_pid" 2>/dev/null; do
      if [ "$_waited" -ge "$_timeout" ]; then
        kill "$_pid" 2>/dev/null; wait "$_pid" 2>/dev/null; mxtk_reap_group "$_pid"
        _mxtk_slurp MXTK_MXBUILD_OUT "$_out"; rm -f "$_out" "$_js"
        MXTK_MXBUILD_EXIT=124; [ "$_own_ef" -eq 1 ] && rm -f "$_ef"
        echo "?"; return 3
      fi
      sleep 1; _waited=$((_waited + 1))
    done
  fi
  wait "$_pid" || _exit=$?
  mxtk_reap_group "$_pid"
  _mxtk_slurp MXTK_MXBUILD_OUT "$_out"; rm -f "$_out"
  MXTK_MXBUILD_EXIT="$_exit"
  mxtk_mxbuild_oom_note "$_exit" "$MXTK_MXBUILD_OUT" || true
  if [ -s "$_js" ]; then _count=$(mxtk_mx_check_to_mxbuild "$_js" "$_ef"); fi
  rm -f "$_js"
  [ "$_own_ef" -eq 1 ] && rm -f "$_ef"
  case "${_count:-}" in
    ''|*[!0-9]*)
      MXTK_MXBUILD_WHY="${MXTK_MXBUILD_OOM:+$MXTK_MXBUILD_OOM; }mx check wrote no readable JSON (exit $_exit): $(printf '%s' "$MXTK_MXBUILD_OUT" | tail -3 | tr '\n' ' ' | cut -c1-240)"
      echo "?"; return 1 ;;
  esac
  # exit 1 with errors is the normal "model has errors" answer; any other non-zero exit
  # with 0 errors means mx did not check the model.
  if [ "$_count" = "0" ] && [ "$_exit" -ne 0 ]; then
    MXTK_MXBUILD_WHY="mx check exited $_exit with no errors listed: $(printf '%s' "$MXTK_MXBUILD_OUT" | tail -3 | tr '\n' ' ' | cut -c1-240)"
    echo "?"; return 1
  fi
  echo "$_count"; return 0
}

# project_name — the .mpr basename without extension, for user-facing messages.
project_name() {
  local mpr
  mpr=$(find_mpr) || return 1
  basename "$mpr" .mpr
}

# --- Pipeline mode (#686) ------------------------------------------------------------------
# PROJECT.md `Pipeline mode: high-speed | balanced | high-quality`. No line, or a value not
# recognised, = balanced. Env MXTK_PIPELINE_MODE wins. Read by exec.sh (per-row lane), the pre-push
# hook (install-project-hooks.sh) and module-close.sh; the table is iterative-build-loop.md
# § "Pipeline mode". $1 = project root (default $PROJECT_ROOT).
mxtk_pipeline_mode() {
  # Bash builtins only (no sed/tr): exec.sh calls this on every run, and tests/wave2/
  # test-exec-process-budget.sh counts the processes one exec starts (#687).
  local v="${MXTK_PIPELINE_MODE:-}" f="${1:-$PROJECT_ROOT}/PROJECT.md" l re='^[*_ >-]*[Pp]ipeline mode:[*_ `]*([A-Za-z-]*)'
  if [ -z "$v" ] && [ -r "$f" ]; then
    while IFS= read -r l || [ -n "$l" ]; do
      if [[ $l =~ $re ]]; then v="${BASH_REMATCH[1]}"; break; fi
    done < "$f"
  fi
  case "$v" in
    [Hh][Ii][Gg][Hh]-[Ss][Pp][Ee][Ee][Dd]) echo high-speed ;;
    [Hh][Ii][Gg][Hh]-[Qq][Uu][Aa][Ll][Ii][Tt][Yy]) echo high-quality ;;
    *) echo balanced ;;
  esac
}
# Printed wherever the toolkit runs a full build (exec.sh's full gate, module-close.sh, the pre-push
# hook): a full build replaces the bundle a running `mxcli run --local --watch` serves, and the client
# 404s on /dist/index.js until a restart (PR #700 run-2 experiment). Advice only.
MXTK_WATCH_NOTE="full build done: if the app runs with --watch, run \`mxcli run restart\` before the next LOOK"
# Module-close polish loop, "<fidelity %> <max rounds>": 75 3 | 85 3 | 90 5 by mode (high-speed
# 3 rounds, not 2: in every arm of the PR #700 run-2 experiment one round went to undoing a regression); a PROJECT.md
# line `UI polish: <N>% / <R> rounds` overrides either number.
mxtk_ui_polish() {
  local r="${1:-$PROJECT_ROOT}" pt pr pol x
  case "$(mxtk_pipeline_mode "$r")" in high-speed) pt=75; pr=3 ;; high-quality) pt=90; pr=5 ;; *) pt=85; pr=3 ;; esac
  pol="$(grep -m1 -iE '^[*_ -]*UI polish:' "$r/PROJECT.md" 2>/dev/null)"
  x="$(printf '%s' "$pol" | sed -n 's/[^0-9]*\([0-9][0-9]*\)[ ]*%.*/\1/p')"; [ -n "$x" ] && pt=$x
  x="$(printf '%s' "$pol" | sed -n 's/.*[^0-9]\([0-9][0-9]*\)[ ]*round.*/\1/p')"; [ -n "$x" ] && pr=$x
  echo "$pt $pr"
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
  # Run-scope memo (exec.sh exports it): the probe below STARTS Python, which is the single
  # costliest process start on Windows, and lint-gate / metrics-ledger / row-groups each did it.
  if [ -n "${MXTK_PY_MEMO:-}" ]; then echo "$MXTK_PY_MEMO"; return 0; fi
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
    echo "  mxbuild not found and no project ./mxcli to download it with (bin/doctor.sh --install --yes fetches both)." >&2
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

# ---------------------------------------------------------------------------
# mxtk_resolve_ledger <root> <module> — the ONE coverage-ledger lookup for a module. Echoes
# the first that exists and returns 0, or returns 1:
#   1. <root>/architecture/modules/<M>/coverage-ledger/    per-BRD directory (holds >=1 *.md;
#                                                           wins over the index file beside it)
#   2. <root>/architecture/modules/<M>/coverage-ledger.md  canonical per-module file
#   3. <root>/architecture/modules/<M>-coverage-ledger.md  flat module layout
#   4. <root>/architecture/coverage-ledger.md              single-BRD project file
# An empty <module> tries only 4. An empty <root> echoes paths relative to the current dir.
# Explicit overrides (LEDGER_FILE, a positional ledger) stay with each caller: their failure
# semantics differ (conformance-check refuses to fall back, verify-module passes a hint).
# Used by conformance-check.sh, coverage-preflight.sh, review-module.sh and verify-module.sh.
# Why one helper (#673): those four each carried their own copy of this chain, and the copies
# drifted — review-module knew 2 of the 4 forms, verify-module 3 — so a project with a valid
# single-BRD ledger passed conformance and coverage run alone and FAULTed both rungs of the
# module review. Duplicated discovery logic drifts and the fix does not travel (the same lesson
# as bin/lib/discover-brds.sh's header, and CLAUDE.md "Writing in this toolkit — generic first").
# ---------------------------------------------------------------------------
mxtk_resolve_ledger() {
  local p="${1:+$1/}" m="${2:-}" c
  if [ -n "$m" ]; then
    c="${p}architecture/modules/$m/coverage-ledger"
    [ -d "$c" ] && ls "$c"/*.md >/dev/null 2>&1 && { printf '%s\n' "$c"; return 0; }
    for c in "${p}architecture/modules/$m/coverage-ledger.md" \
             "${p}architecture/modules/$m-coverage-ledger.md"; do
      [ -f "$c" ] && { printf '%s\n' "$c"; return 0; }
    done
  fi
  c="${p}architecture/coverage-ledger.md"
  [ -f "$c" ] && { printf '%s\n' "$c"; return 0; }
  return 1
}

# mxtk_sha256 — SHA-256 of stdin, whichever tool this machine has (sha256sum on
# Linux/Git Bash, shasum on macOS, openssl as the last resort).
mxtk_sha256() {
  local _h _
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | { read -r _h _; printf '%s\n' "$_h"; }
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 | { read -r _h _; printf '%s\n' "$_h"; }
  else openssl dgst -sha256 | sed 's/^.*= //'
  fi
}

# ---------------------------------------------------------------------------
# Process identity — who holds a port, whose process it is. Shared by test-stack-up.sh and
# app-restart.sh (moved here from both, #160; they had carried identical copies since #262).
# All read-only: nothing below stops, signals or starts a process.
# ---------------------------------------------------------------------------

# mxtk_port_holder <port> — who LISTENs on it: prints "<pid>|<process name>" and returns 0, or
# returns 1 when the port is free. "?|an unidentified process" when something accepts connections
# but no tool here can name it (lsof without root cannot see another user's sockets).
# Per platform: lsof (macOS, Linux), then ss (Linux without lsof), netstat -ano + tasklist (Windows).
mxtk_port_holder() {
  local p="$1" out pid="" name=""
  case "${MXTK_PLATFORM:-$(mxtk_platform)}" in
    windows)
      pid="$(netstat -ano 2>/dev/null | tr -d '\r' | awk -v p=":$p" '$1=="TCP" && $4=="LISTENING" && substr($2, length($2)-length(p)+1)==p { print $5; exit }')"
      [ -n "$pid" ] && name="$(tasklist //FI "PID eq $pid" //FO CSV //NH 2>/dev/null | tr -d '\r' | head -1 | cut -d'"' -f2)" ;;
    *)
      if command -v lsof >/dev/null 2>&1; then
        out="$(lsof -nP -iTCP:"$p" -sTCP:LISTEN -Fpc 2>/dev/null)"
        pid="$(printf '%s\n' "$out" | sed -n 's/^p//p' | head -1)"
        name="$(printf '%s\n' "$out" | sed -n 's/^c//p' | head -1)"
      fi
      if [ -z "$pid" ] && command -v ss >/dev/null 2>&1; then
        out="$(ss -ltnpH "sport = :$p" 2>/dev/null | head -1)"
        pid="$(printf '%s' "$out" | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p')"
        name="$(printf '%s' "$out" | sed -n 's/.*users:(("\([^"]*\)".*/\1/p')"
      fi ;;
  esac
  if [ -n "$pid" ]; then printf '%s|%s\n' "$pid" "${name:-unknown}"; return 0; fi
  if (exec 3<>"/dev/tcp/127.0.0.1/$p") 2>/dev/null; then printf '?|an unidentified process\n'; return 0; fi
  return 1
}

# mxtk_holder_text "<pid>|<name>" — "studiopro pid 4711" plus its parent where ps can show one,
# because a runtime Studio Pro started shows up as plain "java"; the parent names the owner.
mxtk_holder_text() {
  local pid="${1%%|*}" name="${1#*|}" pp pn
  [ "$pid" = "?" ] && { printf '%s (pid unknown — no lsof/ss/netstat could name it)\n' "$name"; return; }
  printf '%s pid %s' "$name" "$pid"
  if [ "$(mxtk_platform)" != windows ]; then
    pp="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
    pn="$(ps -o comm= -p "${pp:-0}" 2>/dev/null | sed 's#.*/##')"
    [ -n "$pp" ] && [ "$pp" != 1 ] && [ -n "$pn" ] && printf ' (parent: %s pid %s)' "$pn" "$pp"
  fi
  printf '\n'
}

# mxtk_app_probe <app port> [admin port] — is a run --local app serving its client? One pass, no wait.
# 0 = up: <app port> serves /index.html (2xx/3xx) AND the client bundle that page loads (dist/*.js or
# mxui.js; /dist/index.js when the page names neither — a themed index.html) answers 2xx with a body
# that is not HTML (an SPA catch-all answers every path with its index page).
# 1 = not up. MXTK_PROBE_DOWN names the part that is down, in words a reader can act on; the admin
# API (127.0.0.1:<admin port>, where mxcli always binds it) only sharpens that message — it is never
# required, so a wrong admin port can not turn a serving app into "down".
# Sets MXTK_PROBE_BUNDLE (the bundle URL tried, with its HTTP code when it failed).
# WHY (#686: 9 false "not proven up after 240s" in one field run while the app served, each
# re-proved by hand at 2-4 min). app-restart.sh required Mendix words in login.html / index.html.
# Mendix 11's login.html carries none (checked on a Mendix 11 deployment/web), and a themed
# index.html need not either, so a serving app could read "does not serve a Mendix page" for the
# whole wait. The record's pid and port already say whose app it is (ports are ownership-checked
# before the start); the bundle answering as JavaScript says the client is there. 127.0.0.1, not
# localhost: mxcli binds the app (and always the admin API) to 127.0.0.1 by default.
mxtk_app_probe() {
  local p="$1" a="${2:-}" h="http://127.0.0.1" code src first adm=""
  MXTK_PROBE_DOWN=""; MXTK_PROBE_BUNDLE=""
  if [ -n "$a" ]; then
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 -X POST -H 'Content-Type: application/json' \
      -d '{"action":"runtime_status","params":{}}' "$h:$a/" 2>/dev/null)"
    case "$code" in ''|000) adm="the runtime's admin API :$a does not answer either — the runtime is not up" ;;
                    *) adm="the runtime's admin API :$a answers — the runtime is up, its app is not (yet)" ;; esac
  fi
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 "$h:$p/index.html" 2>/dev/null)"
  case "$code" in
    2??|3??) ;;
    *) MXTK_PROBE_DOWN="app port :$p does not serve index.html (HTTP ${code:-none})${adm:+; $adm}"; return 1 ;;
  esac
  src="$(curl -s --max-time 4 "$h:$p/index.html" 2>/dev/null | head -c 50000 \
        | grep -oE 'src="[^"]*(dist/[^"]*\.js|mxui\.js)[^"]*"' | head -1 | sed 's/^src="//; s/"$//')"
  [ -n "$src" ] || src="/dist/index.js"
  case "$src" in http*) ;; /*) src="$h:$p$src" ;; *) src="$h:$p/$src" ;; esac
  MXTK_PROBE_BUNDLE="$src"
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 6 "$src" 2>/dev/null)"
  case "$code" in
    2??) first="$(curl -s --max-time 6 "$src" 2>/dev/null | head -c 512 | tr -d ' \t\r\n' | cut -c1)"
         [ "$first" != "<" ] && return 0
         MXTK_PROBE_BUNDLE="$src → HTML, not JavaScript"
         MXTK_PROBE_DOWN="client bundle $src answers with an HTML page, not JavaScript — no Mendix client is served"; return 1 ;;
  esac
  MXTK_PROBE_BUNDLE="$src → HTTP ${code:-none}"
  MXTK_PROBE_DOWN="client bundle $src → HTTP ${code:-none}: the runtime serves pages but no web client (after a full build into deployment/, a run --local --watch app serves none until it is restarted)"
  return 1
}

# mxtk_pid_in_tree <pid> <root pid> — 0 when <pid> is <root pid> or a descendant of it (walked up
# by parent pid, at most 10 levels). Git Bash's ps shows no parent of a Windows pid: returns 1 there
# unless the two pids are equal, so a caller must treat "not in tree" on Windows as "unknown".
mxtk_pid_in_tree() {
  local p="$1" root="$2" i=0
  [ -n "$p" ] && [ -n "$root" ] || return 1
  while [ -n "$p" ] && [ "$p" != 0 ] && [ "$p" != 1 ] && [ "$i" -lt 10 ]; do
    [ "$p" = "$root" ] && return 0
    p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"; i=$((i + 1))
  done
  return 1
}

# mxtk_pid_args <pid> — the process's command line. Linux: argv one per line from /proc (exact, a
# space inside an argument survives). macOS: `ps -o args=`, ONE line (arguments joined by spaces).
# Windows (Git Bash): Win32_Process.CommandLine via PowerShell, one line — Git Bash's ps cannot
# show a Windows process's arguments. Returns 1 when nothing could be read.
mxtk_pid_args() {
  local pid="$1" out=""
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  case "${MXTK_PLATFORM:-$(mxtk_platform)}" in
    linux)
      if [ -r "/proc/$pid/cmdline" ]; then out="$(tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null)"
      else out="$(ps -o args= -p "$pid" 2>/dev/null)"; fi ;;
    macos) out="$(ps -o args= -p "$pid" 2>/dev/null)" ;;
    windows)
      command -v powershell.exe >/dev/null 2>&1 \
        && out="$(powershell.exe -NoProfile -NonInteractive -Command "(Get-CimInstance Win32_Process -Filter 'ProcessId=$pid').CommandLine" 2>/dev/null | tr -d '\r')" ;;
  esac
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

# mxtk_pid_runs_deployment <pid> <deployment dir>... — 0 when <pid> is a Mendix runtime started on
# one of the named deployment directories: its command line runs runtimelauncher.jar and the
# argument after the jar resolves to one of them. That is how both `mxcli run --local` and Studio
# Pro's Run Locally start the runtime (field capture, run --local, Linux, 2026-09-25:
# `java … -jar …/runtimelauncher.jar <project>/app/deployment`). A deployment directory belongs to
# exactly one project checkout, so this is an ownership claim, not a "looks like Mendix" guess.
# Linux compares exact argv after resolving symlinks (and a relative argument against the process's
# cwd); macOS and Windows have only the joined line, so the directory is matched as text in both
# its logical and physical spellings (Windows: drive form, case-insensitive). Unreadable → 1.
mxtk_pid_runs_deployment() {
  local pid="$1" args line next="" arg="" cwd d cand want
  shift
  args="$(mxtk_pid_args "$pid")" || return 1
  case "$args" in *runtimelauncher.jar*) ;; *) return 1 ;; esac
  if [ "$(mxtk_platform)" = linux ] && [ -r "/proc/$pid/cmdline" ]; then
    while IFS= read -r line; do
      [ -n "$next" ] && { arg="$line"; break; }
      case "$line" in *runtimelauncher.jar) next=1 ;; esac
    done <<EOF_ARGS
$args
EOF_ARGS
    [ -n "$arg" ] || return 1
    case "$arg" in /*) ;; *) cwd="$(readlink "/proc/$pid/cwd" 2>/dev/null)" || return 1; arg="$cwd/$arg" ;; esac
    arg="$(cd "$arg" 2>/dev/null && pwd -P)" || return 1
    for d in "$@"; do
      want="$(cd "$d" 2>/dev/null && pwd -P)" || continue
      [ "$arg" = "$want" ] && return 0
    done
    return 1
  fi
  # One joined line: arguments are not delimited, so a directory is matched WHOLE — followed by the
  # end of the line, a lone slash, or a space and a flag (" -"). A space and anything else could be
  # the rest of a longer, spaced path: "/work/a" must not match "…runtimelauncher.jar /work/a b/x"
  # (a foreign checkout read as ours, PR #319 review). Each <dir> arrives as ONE argument.
  line="$(printf '%s' "$args" | head -1 | tr -d '"')"
  [ "${MXTK_PLATFORM:-$(mxtk_platform)}" = windows ] && line="$(printf '%s' "$line" | tr '\\' '/' | tr '[:upper:]' '[:lower:]')"
  for d in "$@"; do
    for cand in "${d%/}" "$(cd "$d" 2>/dev/null && pwd -P)"; do
      [ -n "$cand" ] || continue
      [ "${MXTK_PLATFORM:-$(mxtk_platform)}" = windows ] && cand="$(native_path "$cand" | tr '\\' '/' | tr '[:upper:]' '[:lower:]')"
      case "$line" in
        *"runtimelauncher.jar $cand"|*"runtimelauncher.jar $cand/"|*"runtimelauncher.jar $cand -"*|*"runtimelauncher.jar $cand/ -"*) return 0 ;;
      esac
    done
  done
  return 1
}

# ---------------------------------------------------------------------------
# mxcli run / test identity — shared by app-restart.sh and test-scratch.sh (one copy each until
# 2026-10-14; they had drifted only in a branch test-scratch never took). A caller whose installed
# _common.sh predates this section stops with the sync remedy (`command -v mxtest_left`).
# ---------------------------------------------------------------------------

# mxtk_pid_is_mxcli_run <pid> — 0 when the process IS an `mxcli run` (#304 review). A SIGKILLed
# mxcli leaves its run --local record behind and the OS hands its pid to an unrelated process;
# `kill -0` cannot tell the difference. Linux with /proc: argv one per line (mxtk_pid_args), so
# `run` must be a whole argument after one naming mxcli. macOS (and Linux without /proc): the
# joined `ps -o args=` line, " run " as a word after mxcli. Windows: the image name is mxcli.exe
# (tasklist — Git Bash's ps cannot show a Windows process's arguments, and PowerShell per call is
# slow). Unreadable → 1.
mxtk_pid_is_mxcli_run() {
  local a="" nl='
'
  if [ "${MXTK_PLATFORM:-$(mxtk_platform)}" = windows ]; then
    a="$(tasklist //FI "PID eq $1" //FO CSV //NH 2>/dev/null | tr -d '\r' | head -1 | cut -d'"' -f2)"
    case "$(printf '%s' "$a" | tr '[:upper:]' '[:lower:]')" in mxcli.exe|mxcli) return 0 ;; esac
    return 1
  fi
  a="$(mxtk_pid_args "$1")" || return 1
  if [ "$(mxtk_platform)" = linux ] && [ -r "/proc/$1/cmdline" ]; then
    case "$nl$a$nl" in *mxcli*"${nl}run${nl}"*) return 0 ;; esac
    return 1
  fi
  case " $a " in *mxcli*" run "*) return 0 ;; esac
  return 1
}

# ── After-startup left on an mxcli test injection (#244, BUG-157) ───────────
# `mxcli test` and `mxcli run --test-endpoint` point the model's after-startup microflow at
# MxTest.RegisterEndpoint (MxTest.TestRunner for a plain test run) and chain the original; only a
# clean exit puts it back. A run stopped by a signal leaves it, and the next injection then chains
# RegisterEndpoint to itself: StackOverflowError in the after-startup, the runtime never starts.
# Read straight from the model bytes — no mxcli, no running app: the setting is the BSON string
# element 0x02 "AfterStartupMicroflow" 0x00 of the project-settings unit (mprcontents/**/*.mxunit;
# inside the .mpr itself on a v1 model). Layout checked against real settings units (mxcli's own
# test models). A unit or .mpr without the bytes "MxTest." anywhere is not scanned at all (an 8 MB
# v1 .mpr costs a grep, not an 8 s od). MXTK_SKIP_MXTEST_GUARD=1 skips the check, out loud.
mxtest_after_startup() (  # $1 = file, or - for stdin. Prints the value ('' = none); 1 = no such element
  # A subshell with pipefail OFF: awk exits at the first match and od then dies of SIGPIPE; under
  # the caller's pipefail that 141 would hide the answer and switch the guard off on a large .mpr.
  set +o pipefail
  { if [ "$1" = - ]; then od -An -v -tx1; else od -An -v -tx1 "$1"; fi; } 2>/dev/null | awk '
    BEGIN { for (i = 0; i < 256; i++) hv[sprintf("%02x", i)] = i
            for (i = 32; i < 127; i++) { c = sprintf("%c", i); ch[sprintf("%02x", i)] = c; hx[c] = sprintf("%02x", i) }
            s = "AfterStartupMicroflow"; T = length(s) + 2; t[1] = "02"; t[T] = "00"
            for (i = 1; i <= length(s); i++) t[i + 1] = hx[substr(s, i, 1)]
            k = 0; st = 0; found = 0 }
    { for (f = 1; f <= NF; f++) { b = $f
        if (st == 0) { if (b == t[k + 1]) k++; else k = (b == t[1]) ? 1 : 0
                       if (k == T) { st = 1; L = 0; m = 1; n = 0; v = "" } }
        else if (st == 1) { L += hv[b] * m; m *= 256
                            if (++n == 4) { if (L < 1 || L > 1024) { st = 0; k = 0 } else if (L == 1) { found = 1; exit } else { st = 2; n = 0 } } }
        else { if (++n < L) v = v ((b in ch) ? ch[b] : "?"); else { found = 1; exit } } } }
    END { if (!found) exit 1; print v }'
)
MXTEST_LEFT=""; MXTEST_UNIT=""; MXTEST_HEAD=""
mxtest_left() {  # $1 = model dir, $2 = .mpr. 0 = after-startup is an mxcli test injection (sets MXTEST_*)
  local unit val cands
  MXTEST_LEFT=""; MXTEST_UNIT=""; MXTEST_HEAD=""
  if [ "${MXTK_SKIP_MXTEST_GUARD:-0}" = 1 ]; then
    echo "  ! MXTK_SKIP_MXTEST_GUARD=1 — NOT checking for a leftover mxcli test after-startup (#244). If the app" >&2
    echo "    then dies with StackOverflowError in MxTest.RegisterEndpoint, that is what this check was for." >&2
    return 1
  fi
  if [ -d "$1/mprcontents" ]; then
    cands="$(LC_ALL=C grep -rla --include='*.mxunit' 'AfterStartupMicroflow' "$1/mprcontents" 2>/dev/null)"
  else cands="$2"; fi
  # Every unit holding the text, not the first: a doc string elsewhere can mention the setting by
  # name. Only the BSON element counts, and only a unit that contains "MxTest." can hold the value.
  while IFS= read -r unit; do
    [ -n "$unit" ] && [ -f "$unit" ] || continue
    LC_ALL=C grep -qa 'MxTest\.' "$unit" 2>/dev/null || continue
    val="$(mxtest_after_startup "$unit")" || continue
    case "$val" in MxTest.RegisterEndpoint|MxTest.TestRunner) ;; *) continue ;; esac
    MXTEST_LEFT="$val"; MXTEST_UNIT="$unit"
    case "$unit" in *.mxunit)   # what HEAD has, so the repair can name it; "?" = not tracked / no git
      MXTEST_HEAD="$(git -C "$(dirname "$unit")" show "HEAD:./$(basename "$unit")" 2>/dev/null | mxtest_after_startup -)" || MXTEST_HEAD="?" ;;
    *) MXTEST_HEAD="?" ;; esac
    return 0
  done <<CANDS
$cands
CANDS
  return 1
}
mxtest_refusal() {  # $1 = tool name. Prints the refusal and the repair to stderr. test-scratch gets the
  # test-a-copy advice; any other caller (app-restart) the stop-the-live-app advice.
  local was="$MXTEST_HEAD" rel="${MXTEST_UNIT#"$PROJECT_ROOT"/}"
  echo "✗ $1: this model's after-startup microflow is $MXTEST_LEFT — left behind by an mxcli test or" >&2
  echo "  run --test-endpoint that did not exit cleanly (stopped by a signal or killed; BUG-157)," >&2
  echo "  or held right now by a live run --test-endpoint of this project." >&2
  echo "  Starting on it recurses (the next injection chains $MXTEST_LEFT to itself: StackOverflowError)," >&2
  echo "  or fails the build with CE1613 if the MxTest module is already gone. Either way the app never starts." >&2
  echo "  set in: $rel" >&2
  case "$was" in '?') was="<your own after-startup microflow, or '' for none>"
                      echo "  HEAD: not readable (no git, or the unit is untracked)" >&2 ;;
                 '')  echo "  HEAD: no after-startup microflow" >&2 ;;
                 *)   echo "  HEAD: $was" >&2 ;; esac
  if [ "$1" = test-scratch ]; then
    echo "  → If this project's app runs with --test-endpoint right now (skills/cloud-dev-environment.md), the" >&2
    echo "    live model is fine as it is — test a copy whose settings unit comes from HEAD instead (#244's" >&2
    echo "    workaround): git worktree add <dir> HEAD, copy the units under test into it, run mxcli test there" >&2
    echo "    on free ports. Or stop the live app with Ctrl+C in its own terminal (a clean stop restores it)." >&2
  else
    echo "  → If this project's app is running with --test-endpoint right now, this is its live injection:" >&2
    echo "    stop it with Ctrl+C in its own terminal (a clean stop restores the setting), then retry." >&2
  fi
  echo "  → Otherwise restore it, then retry:" >&2
  echo "      git checkout -- '$rel'      (then git status: the run may have left an MxTest module too)" >&2
  echo "    or through ./bin/exec.sh (an ALTER SETTINGS — say so in chat; it is what mxcli's own cleanup runs):" >&2
  echo "      mdl 1;" >&2
  echo "      alter settings runtime (AfterStartupMicroflow: '$was');" >&2
  echo "    or Studio Pro: App Settings → Runtime → After startup." >&2
  echo "  A false refusal? MXTK_SKIP_MXTEST_GUARD=1 skips this check (and says so)." >&2
}
