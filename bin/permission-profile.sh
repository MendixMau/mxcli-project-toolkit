#!/bin/bash
# permission-profile.sh — resolve how much a project lets Claude Code run without a prompt.
#
# WHY (owner, 2026-10-06): "turn on allow everything, but based on the interview questions in
# intake, maybe with doctor.sh check what the setting is" / "focus mostly on allowing execs and
# those commands, and general work in the project folder. Outside the project folder limit more,
# unless people give it full access". exec-approval.sh decides whether the AGENT asks; this decides
# what bin/install-claude-permissions.sh writes, i.e. whether the HARNESS prompts.
#
# THE PROFILES
#   wrappers  only the toolkit's safe wrappers (bin/exec.sh, bin/*.sh, ./mxcli, mx) — the
#             pre-2026-10-06 allow-list, unchanged.
#   project   (the default) wrappers + edits anywhere inside the project folder + the everyday
#             project commands (node/npx playwright tests, npm install, docker compose, git
#             add/commit). Destructive git and sudo still prompt.
#   full      project + bare Bash/Edit/Read/WebFetch/WebSearch, written ONLY to the per-machine
#             .claude/settings.local.json — one person's opt-in, never committed.
# None of them can switch Claude Code into bypass or auto mode: a project settings file is not
# allowed to (https://code.claude.com/docs/en/permission-modes, fetched 2026-10-06). doctor.sh
# says how to get there from the user's own side.
#
# RESOLUTION ORDER (first hit wins), same shape as exec-approval.sh:
#   1. $MXTK_PERMISSION_PROFILE   2. <project>/.mxtk/permission-profile (--set)
#   3. PROJECT.md `Permission profile:`   4. default `project`
# An unrecognised value falls back to `wrappers` and says so on stderr — a typo must grant less.
#
# Usage: permission-profile.sh <project-dir> [--explain|--set wrappers|project|full|--clear]

set -u

PROJECT_DIR="${1:-}"
ACTION="${2:-}"

usage() {
  echo "usage: permission-profile.sh <project-dir> [--explain|--set wrappers|project|full|--clear]" >&2
  exit 2
}

[ -n "$PROJECT_DIR" ] || usage
[ -d "$PROJECT_DIR" ] || { echo "permission-profile: not a directory: $PROJECT_DIR" >&2; exit 2; }

VALID="wrappers project full"
is_valid() {
  case " $VALID " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

STATE_FILE="$PROJECT_DIR/.mxtk/permission-profile"

case "$ACTION" in
  --set)
    NEW="${3:-}"
    is_valid "$NEW" || { echo "permission-profile: unknown profile '$NEW' (want: $VALID)" >&2; exit 2; }
    mkdir -p "$PROJECT_DIR/.mxtk" || exit 2
    printf '%s\n' "$NEW" > "$STATE_FILE" || exit 2
    echo "permission profile: $NEW  ($STATE_FILE)"
    exit 0
    ;;
  --clear)
    rm -f "$STATE_FILE"
    echo "permission profile: override cleared; falls back to PROJECT.md or default"
    exit 0
    ;;
esac

PROFILE=""
SOURCE=""
_take() {  # _take <value> <source-label>
  if is_valid "$1"; then
    PROFILE="$1"; SOURCE="$2"
  else
    echo "permission-profile: $2 says '$1', not a profile; using wrappers" >&2
    PROFILE="wrappers"; SOURCE="fallback (bad $2)"
  fi
}

if [ -n "${MXTK_PERMISSION_PROFILE:-}" ]; then
  _take "$MXTK_PERMISSION_PROFILE" "\$MXTK_PERMISSION_PROFILE"
fi
if [ -z "$PROFILE" ] && [ -f "$STATE_FILE" ]; then
  _take "$(tr -d '[:space:]' < "$STATE_FILE" 2>/dev/null)" "$STATE_FILE"
fi
if [ -z "$PROFILE" ] && [ -f "$PROJECT_DIR/PROJECT.md" ]; then
  # First occurrence wins, case-insensitive — same convention as exec-approval.sh.
  FROM_MD=$(grep -iEm1 '^[[:space:]]*(-[[:space:]]*)?\**Permission profile\**[[:space:]]*:' "$PROJECT_DIR/PROJECT.md" 2>/dev/null \
            | sed -E 's/.*[Pp]rofile\**[[:space:]]*:[[:space:]]*//' \
            | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]*`')
  [ -n "$FROM_MD" ] && _take "$FROM_MD" "PROJECT.md"
fi
[ -n "$PROFILE" ] || { PROFILE="project"; SOURCE="default"; }

if [ "$ACTION" = "--explain" ]; then
  echo "profile: $PROFILE"
  echo "from: $SOURCE"
  case "$PROFILE" in
    wrappers) echo "effect: only the toolkit's wrappers (exec.sh, bin/*.sh, mxcli, mx) run unprompted." ;;
    project)  echo "effect: wrappers + edits inside the project folder + test/npm/docker/git-commit commands run unprompted." ;;
    full)     echo "effect: everything runs unprompted on this machine (settings.local.json), except the deny/ask rules." ;;
  esac
  exit 0
fi

[ -n "$ACTION" ] && usage

echo "$PROFILE"
