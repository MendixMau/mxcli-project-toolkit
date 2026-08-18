#!/usr/bin/env bash
# PostToolUse — warn when the session's working context crosses a threshold.
#
# Why: cache-read cost is (context size x number of API calls). Measured across
# 21 sessions on this machine: 3.02B cache-read tokens over 10,434 calls, median
# context 227k, worst session 4,335 calls at median 371k. On a 1M-window model
# nothing forces a compaction, so context drifts upward and every later tool
# call re-reads the whole prefix. This is the nudge the window doesn't give you.
#
# Reads the true context size from the transcript's last usage record, so it
# reflects what was actually billed rather than an estimate.
#
# Warns once per threshold per session. Fail-open and cheap: only the tail of
# the transcript is parsed, never the whole file.
#
# Tunables: CLAUDE_CTX_WARN (default 300000), CLAUDE_CTX_HIGH (default 500000),
#           CLAUDE_CTX_URGENT (default 700000)
# Disable:  CLAUDE_CTX_WATCH=0

set -u

[ "${CLAUDE_CTX_WATCH:-1}" = "0" ] && exit 0

CKPT=${CLAUDE_CTX_CHECKPOINT:-200000}
WARN=${CLAUDE_CTX_WARN:-300000}
HIGH=${CLAUDE_CTX_HIGH:-500000}
URGENT=${CLAUDE_CTX_URGENT:-700000}
STATE_DIR="${TMPDIR:-/tmp}/claude-ctxwatch"

command -v jq      >/dev/null 2>&1 || exit 0
# Portability: a hook must never break the session, but it must not disable itself in silence
# either. `command -v python3` was the old guard — it succeeds on the Windows Store alias stub
# and fails on a machine whose Python 3 is called `python`, so on Windows this hook quietly
# stopped running and the context guard it provides was simply absent. resolve_py probes by
# executing. If there is genuinely no Python, say so ONCE per session and stand down.
PORTABLE_LIB="__TOOLKIT_ROOT__/bin/lib/portable.sh"
# shellcheck disable=SC1090
[ -f "$PORTABLE_LIB" ] && . "$PORTABLE_LIB"
PY="$(resolve_py 2>/dev/null)" || {
  _warned="${TMPDIR:-/tmp}/.claude-nopy-warned"
  [ -f "$_warned" ] || { printf '%s: no working Python 3 found — this hook is inactive.\n' "$(basename "$0")" >&2
                         printf '   Run <toolkit>/bin/doctor.sh to see why.\n' >&2; : > "$_warned"; }
  exit 0
}

input=$(cat)
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
session=$(printf '%s'  "$input" | jq -r '.session_id      // empty' 2>/dev/null)
[ -n "$transcript" ] && [ -f "$transcript" ] || exit 0
[ -n "$session" ] || session="unknown"

mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

# Throttle: parsing the transcript costs ~0.5s, and this fires on every tool
# call. Context does not grow fast enough to need checking more than once a
# minute, so skip if we checked recently.
throttle="$STATE_DIR/$session.last"
now=$(date +%s)
if [ -f "$throttle" ]; then
  last=$(cat "$throttle" 2>/dev/null || echo 0)
  case "$last" in ''|*[!0-9]*) last=0 ;; esac
  [ $(( now - last )) -ge "${CLAUDE_CTX_INTERVAL:-60}" ] || exit 0
fi
printf '%s' "$now" > "$throttle" 2>/dev/null

# Last usage record in the transcript = current context size.
#
# Scans backwards in growing chunks rather than `tail -c`: a single JSONL line
# here can be 600KB (an inlined screenshot), so a fixed byte tail routinely
# slices mid-line and finds no parseable record. Stops at the first usage
# record found, or at the cap.
ctx=$("$PY" - "$transcript" <<'PY' 2>/dev/null
import json, os, sys

path = sys.argv[1]
CAP = 8 << 20  # never read more than 8MB of tail

def newest_usage(chunk: bytes) -> int:
    best = 0
    # Drop the first (likely partial) line.
    for raw in chunk.split(b"\n")[1:]:
        if b'"usage"' not in raw:
            continue
        try:
            d = json.loads(raw)
        except Exception:
            continue
        u = (d.get("message") or {}).get("usage")
        if not isinstance(u, dict):
            continue
        n = ((u.get("input_tokens") or 0)
             + (u.get("cache_creation_input_tokens") or 0)
             + (u.get("cache_read_input_tokens") or 0))
        if n > 0:
            best = n
    return best

try:
    size = os.path.getsize(path)
    with open(path, "rb") as f:
        span = 1 << 18  # 256KB
        while span <= CAP:
            f.seek(max(0, size - span))
            found = newest_usage(f.read())
            if found or span >= size:
                print(found)
                break
            span <<= 2
        else:
            print(0)
except Exception:
    print(0)
PY
)

case "$ctx" in ''|*[!0-9]*) exit 0 ;; esac
[ "$ctx" -gt 0 ] || exit 0

# Pick the highest threshold crossed.
level=0
if   [ "$ctx" -ge "$URGENT" ]; then level=4
elif [ "$ctx" -ge "$HIGH"   ]; then level=3
elif [ "$ctx" -ge "$WARN"   ]; then level=2
elif [ "$ctx" -ge "$CKPT"   ]; then level=1
fi
[ "$level" -gt 0 ] || exit 0

# Warn once per threshold per session.
state="$STATE_DIR/$session"
prev=$(cat "$state" 2>/dev/null || echo 0)
case "$prev" in ''|*[!0-9]*) prev=0 ;; esac
[ "$level" -gt "$prev" ] || exit 0
printf '%s' "$level" > "$state" 2>/dev/null

k=$(( ctx / 1000 ))
# Every subsequent API call in this session re-reads this whole prefix.
cost_per_call=$("$PY" -c "print(f'{$ctx * 0.50 / 1_000_000:.2f}')" 2>/dev/null || echo "?")

# Has a checkpoint been written since the session got expensive?
stale_ckpt=1
if [ -f .claude/.last-checkpoint ]; then
  ts=$(cat .claude/.last-checkpoint 2>/dev/null || echo 0)
  case "$ts" in ''|*[!0-9]*) ts=0 ;; esac
  [ $(( now - ts )) -lt "${CLAUDE_CKPT_MAX_AGE:-3600}" ] && stale_ckpt=0
fi

case "$level" in
  1) msg="Context at ${k}k. At the next work boundary, checkpoint and /clear." ;;
  2) msg="Context at ${k}k. ~\$${cost_per_call} per tool call from here — checkpoint and /clear at the next boundary." ;;
  3) msg="Context at ${k}k — HIGH. ~\$${cost_per_call} per tool call. Finish the current step, checkpoint, /clear." ;;
  4) msg="Context at ${k}k — URGENT, nearing the 1M window. ~\$${cost_per_call} per tool call. Checkpoint and /clear now unless mid-edit." ;;
esac

# additionalContext reaches the model (systemMessage only reaches the user), so
# this is what actually triggers the checkpoint rather than just reporting cost.
if [ "$stale_ckpt" = "1" ]; then
  ctxmsg="Session context is ${k}k tokens and no checkpoint has been written recently. Every further tool call re-reads this whole prefix (~\$${cost_per_call} each). At the NEXT natural work boundary — a build-plan step done, a gate passed, a module finished — do this before continuing: run \`__CLAUDE_BIN__/checkpoint.sh --write\`, fill in its Narrative section (in flight / decisions / traps / do-not-lose), promote anything durable to PROJECT.md and anything reusable to a toolkit skill, commit, then tell the user it is safe to /clear. Do not interrupt an in-progress edit to do this."
else
  ctxmsg="Session context is ${k}k tokens (~\$${cost_per_call} per tool call). A checkpoint exists and is recent, so /clear is safe whenever the current step finishes — suggest it to the user at the next boundary."
fi

jq -n --arg m "$msg" --arg c "$ctxmsg" \
  '{systemMessage: $m,
    hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
exit 0
