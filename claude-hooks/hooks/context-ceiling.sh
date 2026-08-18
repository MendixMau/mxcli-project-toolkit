#!/usr/bin/env bash
# PreToolUse — a hard context ceiling. Blocks context-ADDING tools above the limit.
#
# WHY THIS EXISTS: Sonnet 4.6's 200k window was a cost governor disguised as a
# limitation — it made runaway context physically impossible. Measured on this machine:
# across 2,416 Sonnet 4.6 calls the largest context ever reached was 166k, and 0% went
# over 200k. On a 1M window, 70% of calls went over 200k and 89% of cache-read spend
# came from context that could not have existed before. The window stopped budgeting;
# nothing replaced it. This is the replacement.
#
# THE RULE: above the ceiling the session becomes WRITE-ONLY until a checkpoint is
# written. Reading adds context; writing drains it to disk. That asymmetry is what
# keeps the escape route open — you can always finish filing, you just can't take on
# anything new.
#
# Blocked above the ceiling : Read, Grep, Glob, WebFetch, WebSearch, Agent, most Bash
# Always allowed            : Write, Edit, NotebookEdit, TodoWrite/Task*, and the Bash
#                             commands that checkpoint, inspect git, and commit
#
# After a checkpoint you get a grace window (default 15 min) to keep working, then the
# ceiling re-applies. It does not brick the session, it re-asks. Only /clear actually
# lowers context, and no hook can call /clear — that stays with the user.
#
# Tunables: CLAUDE_CTX_CEILING (default 400000), CLAUDE_CTX_GRACE (seconds, default 900)
# Disable:  CLAUDE_CTX_CEILING=0

set -u

CEILING=${CLAUDE_CTX_CEILING:-400000}
[ "$CEILING" = "0" ] && exit 0
GRACE=${CLAUDE_CTX_GRACE:-900}

command -v jq >/dev/null 2>&1 || exit 0
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
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)

# --- 1. Is this tool one that adds context? -----------------------------
case "$tool" in
  Write|Edit|NotebookEdit|TodoWrite|TaskCreate|TaskUpdate|TaskGet|TaskList)
      exit 0 ;;   # writing is how you get out of here
  Read|Grep|Glob|WebFetch|WebSearch|Agent|Task|Bash) ;;
  *)  exit 0 ;;   # unknown / cheap tools: fail open
esac

# Bash is mixed: the escape route runs through it. Allow the commands that file,
# inspect, and commit; block the ones that pull new material into context.
if [ "$tool" = "Bash" ]; then
  cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
  case "$cmd" in
    *checkpoint.sh*|*close-task.sh*|*gate-check.sh*|*check-root-clean.sh*) exit 0 ;;
    git\ commit*|git\ add*|git\ status*|git\ diff\ --stat*|git\ push*)     exit 0 ;;
    *) ;;
  esac
fi

# --- 2. Measure context (cached; PreToolUse fires constantly) -----------
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
session=$(printf   '%s' "$input" | jq -r '.session_id      // empty' 2>/dev/null)
[ -n "$transcript" ] && [ -f "$transcript" ] || exit 0
[ -n "$session" ] || session="unknown"

STATE_DIR="${TMPDIR:-/tmp}/claude-ctxwatch"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
cache="$STATE_DIR/$session.ceil"
now=$(date +%s)

ctx=""
if [ -f "$cache" ]; then
  read -r cts cval < "$cache" 2>/dev/null
  case "${cts:-x}${cval:-x}" in *[!0-9]*) cts=0; cval=0 ;; esac
  # Context only grows, so a slightly stale reading fails open, never shut.
  [ $(( now - ${cts:-0} )) -lt 30 ] && ctx=${cval:-0}
fi

if [ -z "$ctx" ]; then
  ctx=$("$PY" - "$transcript" <<'PY' 2>/dev/null
import json, os, sys
path = sys.argv[1]; CAP = 8 << 20
def newest(chunk):
    best = 0
    for raw in chunk.split(b"\n")[1:]:
        if b'"usage"' not in raw: continue
        try: d = json.loads(raw)
        except Exception: continue
        u = (d.get("message") or {}).get("usage")
        if not isinstance(u, dict): continue
        n = ((u.get("input_tokens") or 0) + (u.get("cache_creation_input_tokens") or 0)
             + (u.get("cache_read_input_tokens") or 0))
        if n > 0: best = n
    return best
try:
    size = os.path.getsize(path)
    with open(path, "rb") as f:
        span = 1 << 18
        while span <= CAP:
            f.seek(max(0, size - span))
            found = newest(f.read())
            if found or span >= size:
                print(found); break
            span <<= 2
        else: print(0)
except Exception: print(0)
PY
)
  case "$ctx" in ''|*[!0-9]*) ctx=0 ;; esac
  printf '%s %s' "$now" "$ctx" > "$cache" 2>/dev/null
fi

[ "$ctx" -ge "$CEILING" ] || exit 0

# --- 3. Fresh checkpoint buys a grace window ----------------------------
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] && cd "$cwd" 2>/dev/null
root=$(git rev-parse --show-toplevel 2>/dev/null) || root=$(pwd)

age=999999
if [ -f "$root/.claude/.last-checkpoint" ]; then
  ts=$(cat "$root/.claude/.last-checkpoint" 2>/dev/null || echo 0)
  case "$ts" in ''|*[!0-9]*) ts=0 ;; esac
  [ "$ts" -gt 0 ] && age=$(( now - ts ))
fi
[ "$age" -le "$GRACE" ] && exit 0

k=$(( ctx / 1000 ))
kc=$(( CEILING / 1000 ))
owed=0
[ -s "$root/.claude/.pending-writes" ] && { owed=$(grep -c . "$root/.claude/.pending-writes" 2>/dev/null); owed=${owed:-0}; }

cat >&2 <<MSG
Context ceiling reached: ${k}k tokens, limit ${kc}k. \`$tool\` is blocked.

Every call from here re-reads the whole ${k}k prefix. Measured on this machine, 89% of
cache-read spend came from context above 200k — this is that, happening now.

The session is WRITE-ONLY until a checkpoint exists. Write/Edit still work, as do
checkpoint.sh, close-task.sh, gate-check.sh, and git. Do this, do not work around it:

  1. __CLAUDE_BIN__/close-task.sh        ($owed write(s) owed)
     Route each item with the table it prints. File nothing unverified.
  2. __CLAUDE_BIN__/checkpoint.sh --write
     Fill the Narrative: in flight / decisions / traps / do-not-lose.
  3. Commit, then close-task.sh --done
  4. Tell the user to /clear — you cannot do it, and it is the only thing that
     actually lowers context. /compact is second best.

A checkpoint buys ${GRACE}s of grace, then this returns. Only /clear resets it.

Override: CLAUDE_CTX_CEILING=0   Raise it: CLAUDE_CTX_CEILING=600000
MSG
exit 2
