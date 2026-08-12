#!/bin/bash
# test-interview-gate.sh — the Stop hook must block an unraised interview, exactly once.
#
# The hook exists because three softer layers were each observed to be declined by a live
# session (runbook prose, gate-check the agent chose not to run, agent-stub ground rules).
# Its two failure modes are opposite and both fatal:
#   - too quiet: a session ends the turn on 36 unraised questions and the user finds out later;
#   - too loud: it re-blocks on the retry and the session cannot end a turn at all, including
#     the turn in which it is asking the questions. That gets the hook uninstalled by lunchtime.
#
# Usage: bash test-interview-gate.sh [path-to-interview-gate.sh]

TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/claude-hooks/hooks/interview-gate.sh}"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/igate.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT

echo "== subject: $SUBJECT"
command -v jq >/dev/null 2>&1 || { echo "  SKIP — jq not installed"; exit 0; }

# The installed hook has __TOOLKIT_ROOT__ substituted by bin/install-claude-hooks.sh; the
# source in the repo does not. Substitute here so the test exercises what gets installed.
HOOK="$WORK/hook.sh"
sed "s|__TOOLKIT_ROOT__|$TOOLKIT|g" "$SUBJECT" > "$HOOK"; chmod +x "$HOOK"

fire() { # fire <project-dir> [stop_hook_active] -> prints hook stdout
  local proj="$1" active="${2:-false}"
  printf '{"stop_hook_active":%s}' "$active" | CLAUDE_PROJECT_DIR="$proj" bash "$HOOK" 2>/dev/null
}

# A project mid-pipeline: one BRD, one never-raised question.
P="$WORK/proj"; mkdir -p "$P/analysis/knowledge-base/brd"
cat > "$P/analysis/knowledge-base/brd/F001-x.brd.json" <<'JSON'
{ "id":"F001","title":"X","stage":2,
  "openQuestions":[{"id":"Q1","question":"Should discounts compound?","status":"Open"}] }
JSON

# --- 1. Blocks a turn that ends with questions unraised -------------------------------
out=$(fire "$P")
case "$out" in
  *'"decision"'*'"block"'*) ok "blocks the stop with decision:block" ;;
  *) bad "did NOT block — a session can end the turn on unraised questions" ;;
esac
case "$out" in
  *interview-protocol.md*) ok "points at the interview protocol" ;;
  *) bad "blocked without saying how to raise properly — the agent will paste bare questions" ;;
esac
case "$out" in
  *"Should discounts compound"*) ok "the batch is included in the reason" ;;
  *) bad "blocked without including the questions — the agent has to go find them" ;;
esac
[ -f "$P/docs/open-questions.html" ] && ok "writes docs/open-questions.html for the user" \
                                     || bad "no HTML report written — the user has nothing to review"

# --- 2. Does not block the SAME set twice ---------------------------------------------
out=$(fire "$P")
[ -z "$out" ] && ok "second stop on the same question set is allowed through" \
              || bad "re-blocked the same set — the session is now trapped and cannot end a turn"

# --- 3. A CHANGED set blocks again ----------------------------------------------------
cat > "$P/analysis/knowledge-base/brd/F002-y.brd.json" <<'JSON'
{ "id":"F002","title":"Y","stage":2,
  "openQuestions":[{"id":"Q9","question":"Which site owns pricing?","status":"Open"}] }
JSON
out=$(fire "$P")
case "$out" in
  *'"block"'*) ok "a new question re-arms the gate" ;;
  *) bad "a newly added unraised question did not block — the gate only ever fires once" ;;
esac

# --- 4. stop_hook_active suppresses ---------------------------------------------------
rm -f "$P/.claude/.interview-gate-last"
out=$(fire "$P" true)
[ -z "$out" ] && ok "stop_hook_active=true suppresses (no recursion)" \
              || bad "fired while stop_hook_active — risks a hook loop"

# --- 5. Silent on projects that are not running this pipeline -------------------------
PLAIN="$WORK/plain"; mkdir -p "$PLAIN"
out=$(fire "$PLAIN")
[ -z "$out" ] && ok "silent on a project with no BRDs" \
              || bad "fired on a non-pipeline project — this is the noise that gets it uninstalled"

# --- 6. Silent once every question has been raised ------------------------------------
ANS="$WORK/answered"; mkdir -p "$ANS/analysis/knowledge-base/brd"
cat > "$ANS/analysis/knowledge-base/brd/F001-x.brd.json" <<'JSON'
{ "id":"F001","title":"X","stage":2,
  "openQuestions":[{"id":"Q1","question":"Should discounts compound?","status":"ANSWERED",
                    "answer":"No — flat only.","raisedAtGate":2}] }
JSON
out=$(fire "$ANS")
[ -z "$out" ] && ok "silent when every question is answered" \
              || bad "blocked a project with nothing unraised"

# --- 7. Escape hatch ------------------------------------------------------------------
rm -f "$P/.claude/.interview-gate-last"
out=$(printf '{"stop_hook_active":false}' \
      | CLAUDE_INTERVIEW_GATE=0 CLAUDE_PROJECT_DIR="$P" bash "$HOOK" 2>/dev/null)
[ -z "$out" ] && ok "CLAUDE_INTERVIEW_GATE=0 disables it without a reinstall" \
              || bad "escape hatch does not work — the only way out is editing settings.json"

# --- 8. It is registered by the installer ---------------------------------------------
grep -q 'interview-gate.sh:Stop' "$TOOLKIT/bin/install-claude-hooks.sh" \
  && ok "registered in install-claude-hooks.sh as a Stop hook" \
  || bad "hook exists but nothing installs it — it will never run on any machine"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
