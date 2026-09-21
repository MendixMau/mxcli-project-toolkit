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
# DEFAULT FLIPPED 2026-09-16 (owner, verbatim). "too much approval clicking; start on auto, ask
# people in the toolkit attended or unattended, and let them switch" / "not all will have
# Claude". The ask-before-every-exec rule was a ritual, not a safety net: project-bin/exec.sh
# already snapshots first, mxbuild-validates after, auto-restores on failure, and writes a
# BUILD-LOG row — the record `ask` was protecting was already being kept either way. `ask`
# remains fully supported; nothing about it changed except that it is no longer what an unset
# project gets by default.
#
# THE MODES
#   ask   the agent asks before every ./mxcli exec, ./bin/exec.sh, mxcli test, mxcli docker
#         check, or --mcp write against the real .mpr — exactly as before this script existed.
#   auto  (the default) nothing blocks. The BUILD-LOG row project-bin/exec.sh already writes for
#         every exec is the safety net standing in for the question — see
#         interview-protocol.md's "Exec approval is a separate knob".
#
# RESOLUTION ORDER (first hit wins)
#   1. $CLAUDE_EXEC_APPROVAL              one command, one session
#   2. <project>/.mxtk/exec-approval      set by --set, survives the turn
#      <project>/.claude/.exec-approval   pre-2026-09-16 path, read only when the .mxtk one is
#                                         absent — never written by --set anymore, which removes
#                                         it once it writes the new path, so a project converges
#                                         onto the single new location the first time it's set
#   3. PROJECT.md `Exec approval:`        the project's stated default
#   4. default                            `auto`, unconditionally — no longer derived from
#                                         interview mode; attended and unattended both start
#                                         on auto, per the owner's request above
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

STATE_DIR="$PROJECT_DIR/.mxtk"
MODE_FILE="$STATE_DIR/exec-approval"
OLD_STATE_DIR="$PROJECT_DIR/.claude"
OLD_MODE_FILE="$OLD_STATE_DIR/.exec-approval"

# --- writers ---------------------------------------------------------------------------
case "$ACTION" in
  --set)
    NEW="${3:-}"
    is_valid "$NEW" || { echo "exec-approval: unknown mode '$NEW' (want: $VALID)" >&2; exit 2; }
    mkdir -p "$STATE_DIR" || exit 2
    printf '%s\n' "$NEW" > "$MODE_FILE" || exit 2
    rm -f "$OLD_MODE_FILE"
    echo "exec approval: $NEW  (session override, $MODE_FILE)"
    exit 0
    ;;
  --clear)
    rm -f "$MODE_FILE" "$OLD_MODE_FILE"
    echo "exec approval: session override cleared; falls back to PROJECT.md or default"
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

if [ -z "$MODE" ]; then
  # New path wins when present; the old .claude/.exec-approval path is read only as a
  # compatibility fallback for a project that hasn't been set (or synced) since 2026-09-16 —
  # --set always writes the new path and removes the old one, so this branch retires itself
  # the first time anyone sets this project's mode again.
  READ_FILE=""
  if [ -f "$MODE_FILE" ]; then
    READ_FILE="$MODE_FILE"
  elif [ -f "$OLD_MODE_FILE" ]; then
    READ_FILE="$OLD_MODE_FILE"
  fi
  if [ -n "$READ_FILE" ]; then
    FROM_FILE=$(tr -d '[:space:]' < "$READ_FILE" 2>/dev/null)
    if is_valid "$FROM_FILE"; then
      MODE="$FROM_FILE"; SOURCE="$READ_FILE"
    else
      echo "exec-approval: '$READ_FILE' holds '$FROM_FILE', not a mode; using ask" >&2
      MODE="ask"; SOURCE="fallback (bad $READ_FILE)"
    fi
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
  # No longer derived from interview mode (2026-09-16) — attended and unattended both start on
  # auto now; see the DEFAULT FLIPPED note above.
  MODE="auto"; SOURCE="default"
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
