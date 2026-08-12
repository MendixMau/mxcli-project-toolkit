#!/bin/bash
# interview-mode.sh — resolve how much the pipeline should involve the user.
#
# WHY THIS EXISTS. How much interviewing is right is a property of the app, not of the
# toolkit. A throwaway POC where every question is reversible wants none; a regulated
# conversion where a role-denial ships to production wants all of it. Hardcoding either
# into the Stop hook produces the two complaints already on record from the same user,
# a week apart: "the agent didn't interview, just continued" and "we want speed not blocking".
# Both are correct. The knob is the answer; the hook is just one of its readers.
#
# DELIBERATELY NOT THE SAME SWITCH AS `auto build mode`. That phrase already means
# "stop asking me before each mxcli exec" (RULE 1). It is about write approval, not about
# requirements. Sharing one switch would mean asking for build speed silently discards
# every requirement question — losing steering on an axis the user never mentioned.
# Decided 2026-08-12: separate knob.
#
# THE MODES
#   steering  every consequential question is put to the user. The default, and the
#             default on purpose: an unconfigured project is one whose risk appetite
#             nobody has stated yet.
#   assist    questions are batched at gates only; the low-consequence ones are assumed
#             and reported rather than asked.
#   auto      nothing blocks. Positions are taken and RECORDED — assumption, rejected
#             alternative, cost if wrong, and a consent stamp naming auto-mode rather
#             than a human. The recording is the entire safety net; see interview-protocol.md.
#
# RESOLUTION ORDER (first hit wins)
#   1. $CLAUDE_INTERVIEW_MODE          one command, one session
#   2. <project>/.claude/.interview-mode   set by --set, survives the turn
#   3. PROJECT.md `Interview mode:`    the project's stated default
#   4. steering
#
# A typo never resolves quieter. An unrecognised value anywhere falls back to steering and
# says so on stderr — the failure direction of a misspelling must be "asked too much".
#
# Usage: interview-mode.sh <project-dir> [--explain|--set MODE|--clear|--remote]

set -u

PROJECT_DIR="${1:-}"
ACTION="${2:-}"

usage() {
  echo "usage: interview-mode.sh <project-dir> [--explain|--set steering|assist|auto|--clear|--remote]" >&2
  exit 2
}

[ -n "$PROJECT_DIR" ] || usage
[ -d "$PROJECT_DIR" ] || { echo "interview-mode: not a directory: $PROJECT_DIR" >&2; exit 2; }

VALID="steering assist auto"
is_valid() {
  case " $VALID " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

STATE_DIR="$PROJECT_DIR/.claude"
MODE_FILE="$STATE_DIR/.interview-mode"
REMOTE_FILE="$STATE_DIR/.interview-remote"

# --- writers ---------------------------------------------------------------------------
case "$ACTION" in
  --set)
    NEW="${3:-}"
    is_valid "$NEW" || { echo "interview-mode: unknown mode '$NEW' (want: $VALID)" >&2; exit 2; }
    mkdir -p "$STATE_DIR" || exit 2
    printf '%s\n' "$NEW" > "$MODE_FILE" || exit 2
    echo "interview mode: $NEW  (session override, $MODE_FILE)"
    exit 0
    ;;
  --clear)
    rm -f "$MODE_FILE"
    echo "interview mode: session override cleared; falls back to PROJECT.md or steering"
    exit 0
    ;;
esac

# --- remote flag -----------------------------------------------------------------------
# Orthogonal to mode, not a fourth mode. Remote says "I am not at the keyboard, message me
# instead of parking the run" — it changes the CHANNEL, not how much gets decided for you.
REMOTE=0
[ -f "$REMOTE_FILE" ] && REMOTE=1
[ "${CLAUDE_INTERVIEW_REMOTE:-0}" = "1" ] && REMOTE=1

if [ "$ACTION" = "--remote" ]; then
  echo "$REMOTE"
  exit 0
fi

# --- resolve ---------------------------------------------------------------------------
MODE=""
SOURCE=""

if [ -n "${CLAUDE_INTERVIEW_MODE:-}" ]; then
  if is_valid "$CLAUDE_INTERVIEW_MODE"; then
    MODE="$CLAUDE_INTERVIEW_MODE"; SOURCE="\$CLAUDE_INTERVIEW_MODE"
  else
    echo "interview-mode: \$CLAUDE_INTERVIEW_MODE='$CLAUDE_INTERVIEW_MODE' is not a mode; using steering" >&2
    MODE="steering"; SOURCE="fallback (bad \$CLAUDE_INTERVIEW_MODE)"
  fi
fi

if [ -z "$MODE" ] && [ -f "$MODE_FILE" ]; then
  FROM_FILE=$(tr -d '[:space:]' < "$MODE_FILE" 2>/dev/null)
  if is_valid "$FROM_FILE"; then
    MODE="$FROM_FILE"; SOURCE="$MODE_FILE"
  else
    echo "interview-mode: '$MODE_FILE' holds '$FROM_FILE', not a mode; using steering" >&2
    MODE="steering"; SOURCE="fallback (bad $MODE_FILE)"
  fi
fi

if [ -z "$MODE" ] && [ -f "$PROJECT_DIR/PROJECT.md" ]; then
  # `Interview mode: assist` anywhere in PROJECT.md. Case-insensitive on the key and the
  # value; first occurrence wins so an appended log entry cannot silently retune the project.
  FROM_MD=$(grep -iEm1 '^[[:space:]]*(-[[:space:]]*)?\**Interview mode\**[[:space:]]*:' "$PROJECT_DIR/PROJECT.md" 2>/dev/null \
            | sed -E 's/.*[Mm]ode\**[[:space:]]*:[[:space:]]*//' \
            | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]*`')
  if [ -n "$FROM_MD" ]; then
    if is_valid "$FROM_MD"; then
      MODE="$FROM_MD"; SOURCE="PROJECT.md"
    else
      echo "interview-mode: PROJECT.md says 'Interview mode: $FROM_MD', which is not a mode; using steering" >&2
      MODE="steering"; SOURCE="fallback (bad PROJECT.md value)"
    fi
  fi
fi

if [ -z "$MODE" ]; then
  MODE="steering"; SOURCE="default (nothing set)"
fi

if [ "$ACTION" = "--explain" ]; then
  echo "mode:   $MODE"
  echo "from:   $SOURCE"
  echo "remote: $REMOTE"
  case "$MODE" in
    steering) echo "effect: every consequential question is put to you; the gate blocks until it is." ;;
    assist)   echo "effect: questions are batched at gates; low-consequence ones are assumed and reported." ;;
    auto)     echo "effect: nothing blocks. Positions are taken and recorded with an auto-mode consent stamp." ;;
  esac
  [ "$REMOTE" = "1" ] && echo "note:   remote is set — gates message you and continue instead of parking."
  exit 0
fi

[ -n "$ACTION" ] && usage

echo "$MODE"
