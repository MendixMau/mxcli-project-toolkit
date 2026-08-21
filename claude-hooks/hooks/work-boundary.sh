#!/usr/bin/env bash
# PostToolUse / Bash — record work-boundary events so owed writes survive being forgotten.
#
# THE POINT: context-watch.sh triggers on token count, which is a proxy for "a lot has
# happened", not for "something finished". The events that actually owe a written record
# are execs, gates, and commits — and those are observable. This appends them to
# .claude/.pending-writes, so the obligation lives on disk rather than in working memory.
#
# The ledger is drained by close-task.sh --done, and precompact-guard.sh refuses to
# compact while it is non-empty.
#
# Rationale: __TOOLKIT_ROOT__/skills/close-the-loop.md
#
# Tunables: CLAUDE_BOUNDARY_NUDGE_EVERY (default 4)
# Disable:  CLAUDE_WORK_BOUNDARY=0

set -u

[ "${CLAUDE_WORK_BOUNDARY:-1}" = "0" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$cmd" ] || exit 0

# Never record the bookkeeping tools themselves — that would be a loop.
case "$cmd" in
  *close-task.sh*|*checkpoint.sh*|*work-boundary.sh*|*precompact-guard.sh*) exit 0 ;;
esac

# Classification is substring matching, so a command that merely *mentions* an exec —
# grepping for one, echoing one into a test harness, writing one into a script — would
# be recorded as if it ran. Caught in testing: piping a JSON payload containing
# "mxcli exec" into this very hook logged a phantom exec. Skip commands that are
# plainly talking about the thing rather than doing it.
case "$cmd" in
  echo*|printf*|cat\ *|grep*|rg\ *|*'| '*grep*|*'<<'*|*--help*|*--dry-run*) exit 0 ;;
esac

# Classify. Each pattern names the write it owes, in the words close-task.sh will print.
what=""
case "$cmd" in
  *"mxcli exec"*|*"bin/exec.sh"*|*"mxcli -p"*" -c "*)
      what="mxcli exec ran → owes a docs/BUILD-LOG.md entry (what it did · exec · mxbuild · SP after)" ;;
  *--mcp*)
      what="MCP write session → owes a docs/BUILD-LOG.md entry; note it was MCP, not CLI" ;;
  *gate-check.sh*)
      what="gate-check ran → owes a build-plan position update (and PROJECT.md if it was a gate decision)" ;;
  *"docker check"*|*"/mx check"*|*"modeler/mx"*)
      what="mxbuild/mx check ran → owes the result on the BUILD-LOG entry for the script it validated" ;;
  *"git commit"*)
      what="commit made → work boundary; checkpoint if the task is closed" ;;
  *check-root-clean.sh*)
      what="root-clean check ran → stage may be closable; confirm artifacts are in their folders" ;;
  *verify-module.sh*)
      what="verify-module.sh ran → owes a finding-disposition.md pass (route findings via close-the-loop.md to docs/improvement-register.md, name what didn't run)" ;;
  *review-module.sh*)
      what="review-module.sh ran → owes a finding-disposition.md pass (route findings via close-the-loop.md to docs/improvement-register.md, name what didn't run)" ;;
  *journey-runner.js*)
      what="journey-runner.js ran → owes a finding-disposition.md pass (route findings via close-the-loop.md to docs/improvement-register.md, name what didn't run)" ;;
  *design-audit.js*)
      what="design-audit.js ran → owes a finding-disposition.md pass (route findings via close-the-loop.md to docs/improvement-register.md, name what didn't run)" ;;
esac
[ -n "$what" ] || exit 0

# Resolve the project root the same way close-task.sh does.
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] && cd "$cwd" 2>/dev/null
root=$(git rev-parse --show-toplevel 2>/dev/null) || root=$(pwd)
mkdir -p "$root/.claude" 2>/dev/null || exit 0
ledger="$root/.claude/.pending-writes"

# Don't let a repeated command inflate the ledger past its last entry.
last=$(tail -1 "$ledger" 2>/dev/null | cut -f2-)
[ "$last" = "$what" ] && exit 0

printf '%s\t%s\n' "$(date '+%H:%M')" "$what" >> "$ledger" 2>/dev/null || exit 0

# Nudge the model, not just the user: additionalContext is the half that reaches it.
n=$(grep -c . "$ledger" 2>/dev/null); n=${n:-0}
every=${CLAUDE_BOUNDARY_NUDGE_EVERY:-4}
[ "$n" -eq 1 ] || [ $(( n % every )) -eq 0 ] || exit 0

if [ "$n" -eq 1 ]; then
  msg="Work-boundary ledger opened: 1 write owed."
else
  msg="Work-boundary ledger: $n writes owed. Close the loop at the next boundary."
fi

ctx="A work boundary just occurred and $n write(s) are now owed on disk (.claude/.pending-writes): ${what}. Do NOT interrupt an in-progress edit for this. But at the next natural stopping point — the current step verified, the topic about to change, or before any compaction — run \`__CLAUDE_BIN__/close-task.sh\`, route each owed item using the table it prints (route by lifespan and audience: transferable lesson -> toolkit skill; decision-with-why -> PROJECT.md; exec -> docs/BUILD-LOG.md; plan movement -> architecture/build-plan.md; how-we-work -> memory; unclear -> checkpoint Narrative prefixed UNFILED:, never a new folder), then \`checkpoint.sh --write\`, commit, and \`close-task.sh --done\`. File nothing you have not verified."

jq -n --arg m "$msg" --arg c "$ctx" \
  '{systemMessage: $m,
    hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
exit 0
