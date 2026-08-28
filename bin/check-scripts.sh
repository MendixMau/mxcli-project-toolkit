#!/usr/bin/env bash
# check-scripts.sh — prove the toolkit's own scripts actually LOAD on this machine.
#
# WHY THIS EXISTS. F-042 (2026-08-28) and the CRLF training-round incidents share a shape:
# a script that is broken *here* — wrong line endings, a bashism this bash doesn't have, a
# syntax error that only ships because nobody executed the file — is discovered mid-stage,
# where it reads as "the toolkit is broken". This runs every shipped script through its own
# interpreter's parse step AT SETUP TIME, so "does not run on this machine" is discovered
# before any stage depends on it.
#
# WHAT IT PROVES, AND WHAT IT DOES NOT. `bash -n` and `node --check` prove the interpreter
# accepts the file: syntax, line endings, parse-level bashisms. They execute nothing, so they
# prove nothing about assumptions (see CLAUDE.md "Shipping an instrument — field-proof before
# merge" — that gate is the merge-time answer; this is the install-time floor beneath it).
# Environment prerequisites (python, mxbuild, java) are doctor.sh's sections, not this.
#
# Scope: the toolkit's shipped sets, plus — with a project dir — that project's INSTALLED
# COPIES (bin/, tests/e2e/), which drift independently and can be CRLF-mangled by any Windows
# editor after install. Pipelines are excluded: they are npm packages with their own installs.
#
#   bin/check-scripts.sh                  # the toolkit's own scripts
#   bin/check-scripts.sh <project-dir>    # also that project's installed copies
#
# Exit: 0 everything checked loads · 1 node missing so JS went unchecked (named, not silent)
#       · 2 at least one script does not load, or a set matched zero files (absence is never
#         a pass — an empty glob means the probe looked in the wrong place)

set -uo pipefail

TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="${1:-}"

FAIL=0
SH_OK=0; SH_N=0
JS_OK=0; JS_N=0
NODE_OK=1
command -v node >/dev/null 2>&1 || NODE_OK=0

check_sh() { # check_sh LABEL GLOB...
  local label="$1"; shift
  local f n=0
  for f in "$@"; do
    [ -f "$f" ] || continue
    n=$((n + 1)); SH_N=$((SH_N + 1))
    if OUT="$(bash -n "$f" 2>&1)"; then
      SH_OK=$((SH_OK + 1))
    else
      FAIL=$((FAIL + 1))
      printf '  FAIL  %s does not parse under this bash:\n' "$f"
      printf '%s\n' "$OUT" | head -3 | sed 's/^/        /'
      if ! tr -d '\r' < "$f" | cmp -s - "$f"; then
        printf '        (file carries CRLF line endings — see doctor.sh "Line endings" for the fix)\n'
      fi
    fi
  done
  if [ "$n" -eq 0 ]; then
    FAIL=$((FAIL + 1))
    printf '  FAIL  %s matched no files — this is not a pass, the probe looked in the wrong place\n' "$label"
  fi
}

check_js() { # check_js LABEL GLOB...
  local label="$1"; shift
  local f n=0
  for f in "$@"; do
    [ -f "$f" ] || continue
    n=$((n + 1))
    [ "$NODE_OK" -eq 1 ] || continue
    JS_N=$((JS_N + 1))
    if OUT="$(node --check "$f" 2>&1)"; then
      JS_OK=$((JS_OK + 1))
    else
      FAIL=$((FAIL + 1))
      printf '  FAIL  %s does not parse under this node:\n' "$f"
      printf '%s\n' "$OUT" | head -3 | sed 's/^/        /'
    fi
  done
  # Zero JS files is a real state only for a project with no e2e engine installed yet; the
  # toolkit sets below always have files, so the empty-glob guard applies to them alike.
  if [ "$n" -eq 0 ]; then
    FAIL=$((FAIL + 1))
    printf '  FAIL  %s matched no files — this is not a pass, the probe looked in the wrong place\n' "$label"
  fi
}

check_sh "toolkit bin/*.sh"          "$TOOLKIT_ROOT"/bin/*.sh
check_sh "toolkit bin/lib/*.sh"      "$TOOLKIT_ROOT"/bin/lib/*.sh
check_sh "toolkit project-bin/*.sh"  "$TOOLKIT_ROOT"/project-bin/*.sh
check_js "toolkit project-bin/*.js"  "$TOOLKIT_ROOT"/project-bin/*.js
check_js "toolkit project-tests/e2e/*.js" "$TOOLKIT_ROOT"/project-tests/e2e/*.js

if [ -n "$PROJECT_DIR" ]; then
  if [ ! -d "$PROJECT_DIR" ]; then
    printf '  FAIL  %s is not a directory\n' "$PROJECT_DIR"
    FAIL=$((FAIL + 1))
  else
    # The installed copies. bin/ exists on every wired project; tests/e2e/ only after
    # install-tests.sh — its absence is install-manifest's finding, not a parse failure,
    # so probe it only when present.
    check_sh "project bin/*.sh" "$PROJECT_DIR"/bin/*.sh
    if [ -d "$PROJECT_DIR/tests/e2e" ]; then
      check_js "project tests/e2e/*.js" "$PROJECT_DIR"/tests/e2e/*.js
    fi
  fi
fi

printf '  %d/%d shell script(s) parse under this bash' "$SH_OK" "$SH_N"
if [ "$NODE_OK" -eq 1 ]; then
  printf ', %d/%d Node instrument(s) parse under this node.\n' "$JS_OK" "$JS_N"
else
  printf '. Node instruments UNCHECKED — node is not installed (see doctor.sh).\n'
fi

if [ "$FAIL" -gt 0 ]; then
  printf '  %d script(s) will not run on this machine. Fix before any stage depends on them.\n' "$FAIL"
  exit 2
fi
[ "$NODE_OK" -eq 1 ] || exit 1
exit 0
