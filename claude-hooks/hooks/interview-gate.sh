#!/bin/bash
# interview-gate.sh — Stop hook. Refuses to let a session end its turn while questions the
# pipeline generated have never been put to the user.
#
# WHY A HOOK. Every softer mechanism has already been tried and observed to fail:
#   - the runbook says to interview at every gate -> sessions read it and continued anyway;
#   - gate-check.sh blocks on unraised questions -> only if the agent chooses to run it;
#   - the agent stubs say raising is mandatory -> stubs are advice.
# Reported by the user, twice, on a live run: "after each gate, the agent didn't interview,
# didn't open a html for me to review, just continued." An instruction an agent may decline
# to follow is not a gate. This is the layer that cannot be declined.
#
# WHAT IT DOES. On Stop, if the project has open questions in a blocking state, it emits
# decision:block with the batch and the report path. Claude then has to raise them before it
# can finish the turn.
#
# WHAT IT DELIBERATELY DOES NOT DO.
#   - It never blocks twice in a row for the same question set. A hook that re-blocks on the
#     agent's next attempt to stop would trap the session in a loop it cannot exit, including
#     the turn in which it is asking the very questions. State is kept in
#     <project>/.claude/.interview-gate-last.
#   - It stays silent when stop_hook_active is set, for the same reason.
#   - It stays silent when there is no toolkit, no jq, or nothing was examined. A hook that
#     fires on projects that are not running this pipeline is noise, and noise gets uninstalled.

[ "${CLAUDE_INTERVIEW_GATE:-1}" = "0" ] && exit 0

INPUT=$(cat)

STOP_ACTIVE=$(printf '%s' "$INPUT" | python3 -c '
import json,sys
try: print(json.load(sys.stdin).get("stop_hook_active", False))
except Exception: print("True")
' 2>/dev/null)
[ "$STOP_ACTIVE" = "True" ] && exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
TOOLKIT="__TOOLKIT_ROOT__"
OQ="$TOOLKIT/bin/open-questions.sh"
QR="$TOOLKIT/bin/questions-report.sh"
IM="$TOOLKIT/bin/interview-mode.sh"

[ -x "$OQ" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# How much this project wants to be involved. See bin/interview-mode.sh — the mode is a
# property of the app, not of this hook, and `auto` is a legitimate answer. A hook that
# blocks regardless of mode is the "we want speed not blocking" complaint in script form.
MODE="steering"
[ -x "$IM" ] && MODE=$("$IM" "$PROJECT_DIR" 2>/dev/null || echo steering)
REMOTE=0
[ -x "$IM" ] && REMOTE=$("$IM" "$PROJECT_DIR" --remote 2>/dev/null || echo 0)

# auto: never block. The questions still get collected and the report still gets written —
# what changes is that the run keeps moving and the recording carries the weight. Blocking
# here would make the mode a lie.
[ "$MODE" = "auto" ] && AUTO=1 || AUTO=0

JSON=$("$OQ" "$PROJECT_DIR" --json 2>/dev/null)
rc=$?
# rc 3 = nothing examined. Not this hook's business: a project with no BRDs is not mid-pipeline.
[ "$rc" -eq 3 ] && exit 0
[ -n "$JSON" ] || exit 0

BLOCKING=$(printf '%s' "$JSON" | jq -r '.blocking // 0' 2>/dev/null)
[ "${BLOCKING:-0}" -gt 0 ] || exit 0

# Do not block the same set twice. The fingerprint is the sorted list of blocking question ids,
# so answering some and leaving others does re-fire (the set changed), but a session that was
# just blocked and is now trying to end the turn again is let through.
FP=$(printf '%s' "$JSON" | jq -r '[.questions[] | select(.state=="UNRAISED" or .state=="UNRECOGNISED") | .id] | sort | join(",")' 2>/dev/null)
STATE_DIR="$PROJECT_DIR/.claude"
STATE="$STATE_DIR/.interview-gate-last"
if [ -f "$STATE" ] && [ "$(cat "$STATE" 2>/dev/null)" = "$FP" ]; then
  exit 0
fi
mkdir -p "$STATE_DIR" 2>/dev/null || true
printf '%s' "$FP" > "$STATE" 2>/dev/null || true

REPORT=""
if [ -x "$QR" ]; then
  "$QR" "$PROJECT_DIR" -o "$PROJECT_DIR/docs/open-questions.html" --quiet >/dev/null 2>&1
  [ -f "$PROJECT_DIR/docs/open-questions.html" ] && REPORT="$PROJECT_DIR/docs/open-questions.html"
fi

# In auto mode — and when the user is remote — the report is the whole job. Refreshing it
# and staying silent is the correct behaviour, not a degraded one: the questions are still
# collected, still counted, still reviewable, and the run does not park against a keyboard
# nobody is sitting at. The obligation to RECORD each position as ASSUMED with an auto-mode
# consent stamp lives in the stage that writes the BRD (interview-protocol.md), because a
# Stop hook has exactly two moves — block or be quiet — and neither of them is "annotate".
if [ "$AUTO" = "1" ] || [ "$REMOTE" = "1" ]; then
  exit 0
fi

BATCH=$("$OQ" "$PROJECT_DIR" 2>/dev/null | sed -n '/PASTE THIS BATCH/,$p' | head -120)

REASON="$BLOCKING question(s) in this project have never been put to the user, and you are ending the turn without raising them. That is the failure the interview protocol exists to prevent — decisions get taken on the user's behalf and buried in a BRD field.

Before you stop: put them in the chat. Read $TOOLKIT/skills/interview-protocol.md — every question carries two named options and your recommendation; a bare question hands your analysis back to the user. Batch them, then end the turn and wait for answers.
"
[ -n "$REPORT" ] && REASON="${REASON}
Triage report written for the user to review: $REPORT — give them this path.
"
REASON="${REASON}
This project is in interview mode '$MODE'. If the user wants speed over involvement here,
tell them they can say so — bin/interview-mode.sh <project> --set assist|auto, or an
'Interview mode:' line in PROJECT.md. Do not set it yourself to get past this block;
choosing how much the user is consulted is not a choice you get to make for them.
"
REASON="${REASON}
${BATCH}"

printf '%s' "$REASON" | python3 -c '
import json, sys
print(json.dumps({"decision": "block", "reason": sys.stdin.read()}))
'
exit 0
