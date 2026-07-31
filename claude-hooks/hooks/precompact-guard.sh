#!/usr/bin/env bash
# PreCompact — warn (once) when compaction would summarize away unwritten state.
#
# THE POINT: compaction is a lossy write you cannot audit. If decisions, in-flight work,
# or traps exist only in the transcript, they may not survive it. This surfaces that
# risk at the moment it matters.
#
# IT DOES NOT HARD-BLOCK. An earlier version did, and it was wrong twice over: it
# recognised only `checkpoint.sh`'s stamp file as valid evidence — so it blocked a
# session that had correctly written a handoff doc, a scope status, and 18 BRDs — and
# it offered no way through except an env var you cannot set mid-session. A guard that
# punishes correct work and cannot be dismissed is a bug, not a safeguard.
#
# So: it interrupts AT MOST ONCE per session. Press /compact again and it passes.
# The one interruption is the whole value; anything more is obstruction.
#
# Evidence that state is on disk — ANY of these counts:
#   - .claude/.last-checkpoint stamped recently (checkpoint.sh --write)
#   - a commit in the last MAX_AGE
#   - a recently modified doc: docs/handoffs/, docs/progress/, BUILD-LOG.md, PROJECT.md
#
# Tunables: CLAUDE_CKPT_MAX_AGE (seconds, default 3600)
# Disable:  CLAUDE_PRECOMPACT_GUARD=0

set -uo pipefail

[ "${CLAUDE_PRECOMPACT_GUARD:-1}" = "0" ] && exit 0

MAX_AGE=${CLAUDE_CKPT_MAX_AGE:-3600}
input=$(cat 2>/dev/null || true)

cwd=""; session=""
if command -v jq >/dev/null 2>&1; then
  cwd=$(printf     '%s' "$input" | jq -r '.cwd        // empty' 2>/dev/null)
  session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
fi
[ -n "$cwd" ] && cd "$cwd" 2>/dev/null
root=$(git rev-parse --show-toplevel 2>/dev/null) || root=$(pwd)
now=$(date +%s)

# --- evidence that this session already wrote its state -----------------
have_evidence=0

stamp="$root/.claude/.last-checkpoint"
if [ -f "$stamp" ]; then
  ts=$(cat "$stamp" 2>/dev/null || echo 0)
  case "$ts" in ''|*[!0-9]*) ts=0 ;; esac
  [ "$ts" -gt 0 ] && [ $(( now - ts )) -le "$MAX_AGE" ] && have_evidence=1
fi

if [ "$have_evidence" = "0" ] && git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
  last_commit=$(git -C "$root" log -1 --format=%ct 2>/dev/null || echo 0)
  case "$last_commit" in ''|*[!0-9]*) last_commit=0 ;; esac
  [ "$last_commit" -gt 0 ] && [ $(( now - last_commit )) -le "$MAX_AGE" ] && have_evidence=1
fi

# A recently-touched progress/handoff doc is state written by hand — equally valid.
if [ "$have_evidence" = "0" ]; then
  recent=$(find "$root/docs" "$root/PROJECT.md" -maxdepth 2 \
             \( -name '*.md' \) -newermt "-${MAX_AGE} seconds" 2>/dev/null | head -1)
  [ -n "$recent" ] && have_evidence=1
fi

owed=0
ledger="$root/.claude/.pending-writes"
[ -s "$ledger" ] && { owed=$(grep -c . "$ledger" 2>/dev/null); owed=${owed:-0}; }

if [ "$have_evidence" = "1" ] && [ "$owed" -eq 0 ]; then
  echo "State is on disk and nothing is owed — compaction is safe." >&2
  exit 0
fi

# --- interrupt at most once per session ---------------------------------
STATE_DIR="${TMPDIR:-/tmp}/claude-ctxwatch"
mkdir -p "$STATE_DIR" 2>/dev/null
[ -n "$session" ] || session="unknown"
seen="$STATE_DIR/$session.precompact"

if [ -f "$seen" ]; then
  echo "Proceeding with compaction (already warned once this session)." >&2
  exit 0
fi
: > "$seen" 2>/dev/null

extra=""
[ "$owed" -gt 0 ] && extra="
$owed write(s) are recorded as owed in .claude/.pending-writes — see close-task.sh."

cat >&2 <<MSG
Heads up before compacting — I found no sign that this session's state was written
to disk in the last $(( MAX_AGE / 60 )) minutes (no checkpoint stamp, no recent commit, no recently
modified doc under docs/ or PROJECT.md).$extra

If decisions, in-flight work, or traps exist only in this conversation, compaction
may summarize them away and you cannot audit what was dropped.

If you already wrote your state somewhere I did not look, ignore this.
Otherwise, worth doing first:
  __CLAUDE_BIN__/close-task.sh      # what is owed, and where it goes
  __CLAUDE_BIN__/checkpoint.sh --write

**Run /compact again and it will go through** — this warns once per session, not twice.
Prefer /clear over /compact once state is on disk: it lands lower and leaves reviewable
text instead of a summary.

Silence it entirely: CLAUDE_PRECOMPACT_GUARD=0
MSG
exit 2
