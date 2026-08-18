#!/usr/bin/env bash
# check-portability.sh — fail the build when a script reintroduces a macOS-only assumption.
#
# WHY THIS EXISTS. Portability regresses the moment someone authors a new script on a Mac, which
# is every time. The fixes in this repo will rot within weeks without a guard, and the guard has
# to be cheap enough to run on every commit.
#
# WHY THIS IS NOT AN mxcli .star LINT RULE. It was specified as one. It cannot be one: the
# Starlark API exposed to `mxcli lint` is entirely Mendix-model-scoped — entities(), microflows(),
# activities_for(), refs_to() over .mxcli/catalog.db — with no filesystem access of any kind
# (verified 2026-08-18 against .ai-context/skills/write-lint-rules.md and both rules in
# lint-rules/). A rule that reads shell scripts has nothing to read them with. So this is a shell
# script, run from tests/run-tests.sh and installable as a pre-commit hook, and it needs no
# per-project copy mechanism to reach anyone.
#
#   bin/check-portability.sh            # check the toolkit's own scripts
#   bin/check-portability.sh <dir>...   # check somewhere else
#
# Exit 0 clean, 1 violations found.
#
# NOT on the denylist, and deliberately:
#   date -r <file>   BSD and GNU both accept it, verified by running both. Banning it would
#                    hand the reader a false positive to suppress forever, and a denylist that
#                    cries wolf gets switched off — which is how the lint gate died last time.
#   xargs -0         supported by BSD and GNU xargs alike.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ "$#" -gt 0 ]; then TARGETS="$*"; else TARGETS="$ROOT/bin $ROOT/project-bin $ROOT/claude-hooks $ROOT/tests"; fi

VIOLATIONS=0
SCANNED=0

# Files allowed to name a macOS-only tool, because driving Studio Pro on macOS IS their job.
# A file is listed here by basename. Keep the list short and justify every addition.
is_exempt_macos_only() {
  case "$(basename "$1")" in
    save-sp.sh|restart-sp.sh|check-sp-health.sh|_common.sh|exec.sh|doctor.sh|check-portability.sh) return 0 ;;
    *) return 1 ;;
  esac
}
# Files allowed to contain the literal denied strings because they define or document the rule.
is_meta() {
  case "$(basename "$1")" in
    portable.sh|doctor.sh|check-portability.sh) return 0 ;;
    *) return 1 ;;
  esac
}

report() { printf '%s:%s: %s\n     %s\n' "$1" "$2" "$3" "$4"; VIOLATIONS=$((VIOLATIONS + 1)); }

# Strip comment lines and blank lines before matching, but keep original line numbers.
code_lines() { grep -n '' "$1" | grep -v ':[[:space:]]*#' ; }

while IFS= read -r f; do
  [ -f "$f" ] || continue
  SCANNED=$((SCANNED + 1))

  # 1. CRLF. Checked first: it makes every other finding moot.
  if ! tr -d '\r' < "$f" | cmp -s - "$f"; then
    report "$f" 1 "CRLF line endings" "bash fails on line 1. Ensure .gitattributes has *.sh text eol=lf."
  fi

  is_meta "$f" && continue

  while IFS= read -r hit; do
    ln="${hit%%:*}"; txt="${hit#*:}"

    case "$txt" in
      *python3*|*' python '*)
        report "$f" "$ln" "hard-coded Python name" \
          'Source bin/lib/portable.sh, call require_py, and use "$PY". A name on PATH is not an interpreter on Windows.' ;;
    esac

    case "$txt" in
      *'stat -f'*)
        # A GNU fallback may sit on the next physical line via a backslash continuation, so the
        # window is two lines, not one. Same-line only produced a false positive on graph-sweep.
        nxt="$(sed -n "$((ln + 1))p" "$f" 2>/dev/null)"
        case "$txt$nxt" in
          *'stat -c'*) : ;;  # BSD form with a GNU fallback within reach is fine
          *) report "$f" "$ln" "BSD-only stat -f with no GNU fallback" \
               'Use portable_file_size / portable_file_mtime_iso from bin/lib/portable.sh, or add || stat -c.' ;;
        esac ;;
    esac

    case "$txt" in
      *"sed -i ''"*)
        report "$f" "$ln" "BSD-only sed -i ''" \
          'GNU sed reads the next argument as the script. Write to a temp file and mv it.' ;;
    esac

    case "$txt" in
      *'readlink -f'*)
        report "$f" "$ln" "readlink -f is GNU-only (absent on macOS)" \
          'Use cd "$(dirname "$x")" && pwd.' ;;
    esac

    case "$txt" in
      *'grep -P'*|*'grep -qP'*|*'grep -oP'*)
        report "$f" "$ln" "grep -P is GNU-only" \
          'BSD grep has no -P and errors out — silently, if stderr is discarded. Use perl -CSD or POSIX ERE.' ;;
    esac

    is_exempt_macos_only "$f" && continue
    case "$txt" in
      *osascript*|*'open -a'*|*/Applications/*|*pgrep*)
        report "$f" "$ln" "macOS-only command or path" \
          'Guard it behind a uname check and say plainly what happens on other platforms.' ;;
    esac
  done <<EOF
$(code_lines "$f")
EOF
done <<EOF
$(find $TARGETS -name '*.sh' -type f 2>/dev/null | sort)
EOF

# A checker that inspected nothing must not report a pass. Found 2026-08-18 by a parallel
# session: bin/lint-gate.sh pointed at a nonexistent project, mxcli exited 0, and the gate
# reported a clean PASS over an empty set. This script had the identical hole — a bad path or
# an empty directory printed "clean" and exited 0. Same shape as the [].every() trace bug.
if [ "$SCANNED" -eq 0 ]; then
  printf 'check-portability: inspected ZERO files under: %s\n' "$TARGETS" >&2
  printf '  This is NOT a pass. Check the path, or that the directories still contain *.sh.\n' >&2
  exit 2
fi

if [ "$VIOLATIONS" -gt 0 ]; then
  printf '\ncheck-portability: %s violation(s).\n' "$VIOLATIONS"
  printf 'Each one is a script that runs here and fails on a colleague'"'"'s machine.\n'
  exit 1
fi
printf 'check-portability: clean — %s file(s) inspected under %s\n' "$SCANNED" "$TARGETS"
