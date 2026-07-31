#!/usr/bin/env bash
# close-task.sh — show what writes are owed at a work boundary, and where each goes.
#
# THE POINT: knowledge produced by a finished task is only durable once it is a file.
# work-boundary.sh records boundary events to .claude/.pending-writes as they happen;
# this drains that ledger and prints the routing table so nothing has to be remembered.
#
# Full rationale: __TOOLKIT_ROOT__/skills/close-the-loop.md
#
# USAGE
#   close-task.sh            # show the ledger + routing table + unfiled carry-over
#   close-task.sh --done     # clear the ledger (run AFTER the writes are committed)
#   close-task.sh --add "…"  # manually record an owed write
#
# Exit 1 when writes are owed, 0 when clean — so it can gate a script.

set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT=$(pwd)
cd "$ROOT" || exit 1
LEDGER="$ROOT/.claude/.pending-writes"
CKPT="$ROOT/docs/progress/checkpoints.md"

mkdir -p "$ROOT/.claude" 2>/dev/null

case "${1:-}" in
  --done)
    n=0
    [ -f "$LEDGER" ] && { n=$(grep -c . "$LEDGER" 2>/dev/null); n=${n:-0}; }
    : > "$LEDGER"
    echo "Ledger cleared ($n entr$([ "$n" = 1 ] && echo y || echo ies))."
    exit 0
    ;;
  --add)
    shift
    [ -n "${1:-}" ] || { echo "usage: close-task.sh --add 'what happened'" >&2; exit 1; }
    printf '%s\t%s\n' "$(date '+%H:%M')" "$*" >> "$LEDGER"
    echo "Recorded."
    exit 0
    ;;
esac

owed=0

echo "## Close the loop — $(date '+%Y-%m-%d %H:%M')"
echo

# ---- the ledger --------------------------------------------------------
echo "### Owed writes (since last close)"
echo
if [ -s "$LEDGER" ]; then
  # Collapse duplicates but keep first-seen order and a count.
  awk -F'\t' '{k=$2; if(!(k in c)){order[++n]=k; first[k]=$1} c[k]++}
              END{for(i=1;i<=n;i++){k=order[i];
                    printf "- `%s` %s%s\n", first[k], k, (c[k]>1 ? " (x" c[k] ")" : "")}}' \
      "$LEDGER"
  owed=1
else
  echo "- (none recorded — either nothing happened, or work-boundary.sh is not wired)"
fi
echo

# ---- unfiled carry-over from the last checkpoint -----------------------
if [ -f "$CKPT" ]; then
  # Only look at the most recent checkpoint block.
  unfiled=$(awk '/^## Checkpoint —/{buf=""} {buf=buf $0 "\n"} END{printf "%s", buf}' "$CKPT" \
            | grep -iE '^\s*[-*].*UNFILED:' 2>/dev/null)
  if [ -n "$unfiled" ]; then
    echo "### UNFILED carry-over — route these or delete them"
    echo
    printf '%s\n' "$unfiled" | sed 's/^ *//'
    echo
    owed=1
  fi
fi

# ---- uncommitted work that implies a write -----------------------------
if git rev-parse --git-dir >/dev/null 2>&1; then
  mdl=$(git status --porcelain mdlsource 2>/dev/null | awk '{print $NF}' | head -6)
  if [ -n "$mdl" ]; then
    echo "### Uncommitted MDL — did each of these actually run?"
    echo "> A committed script is NOT an executed script. BUILD-LOG records execs, not commits."
    echo
    printf '%s\n' "$mdl" | sed 's/^/    - `/;s/$/`/'
    echo
  fi
fi

# ---- the routing table -------------------------------------------------
cat <<'TABLE'
### Where each thing goes — route by lifespan and audience, not topic

| What you have | Goes to |
|---|---|
| A script was executed against the .mpr | `docs/BUILD-LOG.md` (append-only, one entry per exec) |
| A build-plan step done / blocked / descoped | `architecture/build-plan.md` + the module plan |
| A decision that constrains future decisions | `PROJECT.md` (with the why) |
| A lesson true in a *different* project | `__TOOLKIT_ROOT__/skills/` |
| A confirmed reproducible tool defect | `bug-logs/mxcli-bugs.md` |
| How the user wants me to work / project context not in code | memory dir + one line in `MEMORY.md` |
| Where we are, what's next, what's unresolved | `docs/progress/checkpoints.md` |
| Genuinely unclear | checkpoint Narrative, prefixed `UNFILED:` — never a new folder |

Rules: verify before filing · one place only, link don't copy · a committed script is not
an executed script.

### Then
    checkpoint.sh --write     # and fill the Narrative  (append-only history)
    OVERWRITE docs/progress/RESUME.md   # <= 60 lines: where we are, next actions,
                                        #    do-not-lose, and which file to read for what.
                                        #    This is the ONLY file read after /clear.
    git commit
    close-task.sh --done      # empties the pending-writes file; PreCompact unblocks

Resume cost is the hidden half of the bill: whatever the next session reads to get oriented
rides in its context prefix and is re-read on every call. Measured 2026-07-31 — rediscovering
state from PROJECT.md + checkpoints.md + PROGRESS-LIVE + handoffs cost 100k up front and ~$10
in re-reads. RESUME.md exists to make that one small read. Keep it SHORT and overwrite it;
never append.
TABLE

exit "$owed"
