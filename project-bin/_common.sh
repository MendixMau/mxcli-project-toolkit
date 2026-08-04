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

# Resolve the project root from the sourcing script's location (bin/ -> ..).
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")/.." && pwd)}"

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
# find_sp_app — newest installed Studio Pro .app bundle.
#
# Version-sorted, NOT lexically sorted: with 11.9.0 and 11.13.0 both installed,
# a plain `sort` picks 11.9.0 as "highest" because '9' > '1' at the third
# character. That silently builds against the wrong Mendix version. `sort -V`
# handles it; if this box has a sort without -V, we fall back and say so rather
# than quietly return a wrong answer. $MENDIX_APP overrides.
# ---------------------------------------------------------------------------
find_sp_app() {
  if [ -n "${MENDIX_APP:-}" ]; then echo "$MENDIX_APP"; return 0; fi
  local list
  list=$(ls -d /Applications/Mendix\ Studio\ Pro*.app 2>/dev/null) || true
  [ -z "$list" ] && { echo "ERROR: no 'Mendix Studio Pro *.app' in /Applications" >&2; return 1; }

  if printf '1.10\n1.9\n' | sort -V >/dev/null 2>&1; then
    printf '%s\n' "$list" | sort -V | tail -1
  else
    echo "WARNING: this sort has no -V; falling back to lexical order, which mis-ranks" >&2
    echo "         11.9 above 11.13. Set MENDIX_APP=<path> to be certain." >&2
    printf '%s\n' "$list" | sort | tail -1
  fi
}

# find_mxbuild — the mxbuild binary inside the chosen SP app. $MXBUILD_PATH overrides.
find_mxbuild() {
  if [ -n "${MXBUILD_PATH:-}" ]; then echo "$MXBUILD_PATH"; return 0; fi
  local app
  app=$(find_sp_app) || return 1
  echo "$app/Contents/modeler/mxbuild"
}

# project_name — the .mpr basename without extension, for user-facing messages.
project_name() {
  local mpr
  mpr=$(find_mpr) || return 1
  basename "$mpr" .mpr
}
