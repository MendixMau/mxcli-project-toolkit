#!/bin/bash
# exec-approval.sh — resolve whether an exec against the model has to ask first.
#
# WHY THIS EXISTS (user, 2026-09-15, verbatim). "I'm going a bit insane of claude keeping to
# asking me if they can run an exec mdl. Can we for unattended mode remove the check for exec,
# for attended keep it, but give the person the option to turn it off at any time?"
#
# DELIBERATELY A SEPARATE KNOB FROM interview-mode.sh, SAME SHAPE. interview-mode.sh's own
# header already says (2026-08-12): "auto build mode" already means "stop asking me before each
# mxcli exec" (RULE 1); interview mode is about REQUIREMENTS steering, a different axis, and
# sharing one switch would mean asking for build speed silently discards every requirement
# question. That separate knob was never built until now. This script is invoked as a
# subprocess for tier 4 below — never sourced — so a bug in one script can never corrupt the
# other's resolution.
#
# THE MODES
#   ask   the agent asks before every ./mxcli exec, ./bin/exec.sh, mxcli test, mxcli docker
#         check, or --mcp write against the real .mpr — exactly as before this script existed.
#   auto  nothing blocks. The BUILD-LOG row project-bin/exec.sh already writes for every exec
#         is the safety net standing in for the question — see interview-protocol.md's "Exec
#         approval is a separate knob".
#
# RESOLUTION ORDER (first hit wins)
#   1. $CLAUDE_EXEC_APPROVAL             one command, one session
#   2. <project>/.claude/.exec-approval  set by --set, survives the turn
#   3. PROJECT.md `Exec approval:`       the project's stated default
#   4. derived from interview mode       bin/interview-mode.sh <dir> says `auto` -> `auto`;
#                                        anything else (steering, assist, a fallback) -> `ask`
#
# A typo never resolves quieter. An unrecognised value anywhere falls back to `ask` and says so
# on stderr — the failure direction of a misspelling must be "asked too much", same rule as
# interview-mode.sh.
#
# Usage: exec-approval.sh <project-dir> [--explain|--set ask|auto|--clear]

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

PROJECT_DIR="${1:-}"
ACTION="${2:-}"

usage() {
  echo "usage: exec-approval.sh <project-dir> [--explain|--set ask|auto|--clear]" >&2
  exit 2
}

[ -n "$PROJECT_DIR" ] || usage
[ -d "$PROJECT_DIR" ] || { echo "exec-approval: not a directory: $PROJECT_DIR" >&2; exit 2; }

VALID="ask auto"
is_valid() {
  case " $VALID " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

STATE_DIR="$PROJECT_DIR/.claude"
MODE_FILE="$STATE_DIR/.exec-approval"

# --- writers ---------------------------------------------------------------------------
case "$ACTION" in
  --set)
    NEW="${3:-}"
    is_valid "$NEW" || { echo "exec-approval: unknown mode '$NEW' (want: $VALID)" >&2; exit 2; }
    mkdir -p "$STATE_DIR" || exit 2
    printf '%s\n' "$NEW" > "$MODE_FILE" || exit 2
    echo "exec approval: $NEW  (session override, $MODE_FILE)"
    exit 0
    ;;
  --clear)
    rm -f "$MODE_FILE"
    echo "exec approval: session override cleared; falls back to PROJECT.md or interview mode"
    exit 0
    ;;
esac

# --- resolve ---------------------------------------------------------------------------
MODE=""
SOURCE=""

if [ -n "${CLAUDE_EXEC_APPROVAL:-}" ]; then
  if is_valid "$CLAUDE_EXEC_APPROVAL"; then
    MODE="$CLAUDE_EXEC_APPROVAL"; SOURCE="\$CLAUDE_EXEC_APPROVAL"
  else
    echo "exec-approval: \$CLAUDE_EXEC_APPROVAL='$CLAUDE_EXEC_APPROVAL' is not a mode; using ask" >&2
    MODE="ask"; SOURCE="fallback (bad \$CLAUDE_EXEC_APPROVAL)"
  fi
fi

if [ -z "$MODE" ] && [ -f "$MODE_FILE" ]; then
  FROM_FILE=$(tr -d '[:space:]' < "$MODE_FILE" 2>/dev/null)
  if is_valid "$FROM_FILE"; then
    MODE="$FROM_FILE"; SOURCE="$MODE_FILE"
  else
    echo "exec-approval: '$MODE_FILE' holds '$FROM_FILE', not a mode; using ask" >&2
    MODE="ask"; SOURCE="fallback (bad $MODE_FILE)"
  fi
fi

if [ -z "$MODE" ] && [ -f "$PROJECT_DIR/PROJECT.md" ]; then
  # `Exec approval: auto` anywhere in PROJECT.md. Case-insensitive on the key and the value;
  # first occurrence wins so an appended log entry cannot silently retune the project — same
  # convention as interview-mode.sh's own PROJECT.md read.
  FROM_MD=$(grep -iEm1 '^[[:space:]]*(-[[:space:]]*)?\**Exec approval\**[[:space:]]*:' "$PROJECT_DIR/PROJECT.md" 2>/dev/null \
            | sed -E 's/.*[Aa]pproval\**[[:space:]]*:[[:space:]]*//' \
            | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]*`')
  if [ -n "$FROM_MD" ]; then
    if is_valid "$FROM_MD"; then
      MODE="$FROM_MD"; SOURCE="PROJECT.md"
    else
      echo "exec-approval: PROJECT.md says 'Exec approval: $FROM_MD', which is not a mode; using ask" >&2
      MODE="ask"; SOURCE="fallback (bad PROJECT.md value)"
    fi
  fi
fi

if [ -z "$MODE" ]; then
  IM_SCRIPT="$SCRIPT_DIR/interview-mode.sh"
  if [ -f "$IM_SCRIPT" ]; then
    IM="$(bash "$IM_SCRIPT" "$PROJECT_DIR" 2>/dev/null)"
    if [ "$IM" = "auto" ]; then
      MODE="auto"; SOURCE="derived from interview mode (auto)"
    else
      MODE="ask"; SOURCE="derived from interview mode (${IM:-unresolved})"
    fi
  else
    MODE="ask"; SOURCE="default (interview-mode.sh not found)"
  fi
fi

if [ "$ACTION" = "--explain" ]; then
  echo "mode: $MODE"
  echo "from: $SOURCE"
  case "$MODE" in
    ask)  echo "effect: the agent asks before every exec/test/docker-check/--mcp write, every time." ;;
    auto) echo "effect: those run without asking; the BUILD-LOG row is the record instead." ;;
  esac
  exit 0
fi

[ -n "$ACTION" ] && usage

echo "$MODE"
