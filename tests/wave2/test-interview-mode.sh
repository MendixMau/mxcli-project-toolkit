#!/bin/bash
# test-interview-mode.sh — the involvement knob, and the hook honouring it.
#
# The property that matters most here is the FAILURE DIRECTION. Every way of getting the
# mode wrong — a typo in PROJECT.md, a corrupted session file, an unset variable — must
# land on `steering`, never on `auto`. A misspelling that silently buys speed is how a
# regulated conversion ships a role-denial nobody was asked about.
#
# Usage: bash test-interview-mode.sh [path-to-interview-mode.sh]

TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/bin/interview-mode.sh}"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/imode.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT
echo "== subject: $SUBJECT"

P="$WORK/proj"; mkdir -p "$P"

# --- resolution order -------------------------------------------------------------------
[ "$(bash "$SUBJECT" "$P")" = "steering" ] \
  && ok "unset resolves to steering" \
  || bad "unset did not resolve to steering — an unconfigured project must be the loud one"

printf 'Interview mode: auto\n' > "$P/PROJECT.md"
[ "$(bash "$SUBJECT" "$P")" = "auto" ] \
  && ok "PROJECT.md sets the project default" \
  || bad "PROJECT.md 'Interview mode:' ignored"

mkdir -p "$P/.claude"; printf 'assist\n' > "$P/.claude/.interview-mode"
[ "$(bash "$SUBJECT" "$P")" = "assist" ] \
  && ok "session override beats PROJECT.md" \
  || bad "session file did not override PROJECT.md"

[ "$(CLAUDE_INTERVIEW_MODE=steering bash "$SUBJECT" "$P")" = "steering" ] \
  && ok "env beats the session file" \
  || bad "env did not win — no way to override for one command"

# --- failure direction: every bad value lands on steering ---------------------------------
[ "$(CLAUDE_INTERVIEW_MODE=atuo bash "$SUBJECT" "$P" 2>/dev/null)" = "steering" ] \
  && ok "typo in env falls back to steering" \
  || bad "a typo resolved to something other than steering"
CLAUDE_INTERVIEW_MODE=atuo bash "$SUBJECT" "$P" 2>&1 >/dev/null | grep -q 'not a mode' \
  && ok "and says so on stderr rather than failing silently" \
  || bad "bad env value was swallowed — the user thinks they set a mode and did not"

printf 'garbage\n' > "$P/.claude/.interview-mode"
[ "$(bash "$SUBJECT" "$P" 2>/dev/null)" = "steering" ] \
  && ok "corrupt session file falls back to steering" \
  || bad "corrupt session file did not fall back safely"
rm -f "$P/.claude/.interview-mode"

printf 'Interview mode: aggressive\n' > "$P/PROJECT.md"
[ "$(bash "$SUBJECT" "$P" 2>/dev/null)" = "steering" ] \
  && ok "unknown mode in PROJECT.md falls back to steering" \
  || bad "unknown PROJECT.md mode did not fall back safely"

# --- writers ------------------------------------------------------------------------------
rm -f "$P/PROJECT.md"
bash "$SUBJECT" "$P" --set auto >/dev/null 2>&1
[ "$(bash "$SUBJECT" "$P")" = "auto" ] && ok "--set writes a session override" \
                                       || bad "--set did not take effect"
bash "$SUBJECT" "$P" --set nonsense >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "--set rejects an unknown mode with exit 2" \
               || bad "--set accepted a mode that does not exist"
bash "$SUBJECT" "$P" --clear >/dev/null 2>&1
[ "$(bash "$SUBJECT" "$P")" = "steering" ] && ok "--clear reverts to the default" \
                                           || bad "--clear left the override in place"

bash "$SUBJECT" "$P" --explain 2>/dev/null | grep -q '^from:' \
  && ok "--explain reports WHERE the mode came from" \
  || bad "--explain does not say which source won — undebuggable"

[ "$(bash "$SUBJECT" "$P" --remote)" = "0" ] && ok "remote defaults off" || bad "remote defaulted on"
[ "$(CLAUDE_INTERVIEW_REMOTE=1 bash "$SUBJECT" "$P" --remote)" = "1" ] \
  && ok "remote flag readable from env" || bad "remote flag not settable"

bash "$SUBJECT" 2>/dev/null; [ "$?" -eq 2 ] && ok "no argument exits 2" || bad "no argument did not exit 2"

# --- the hook honours all of it -------------------------------------------------------------
HOOK="$WORK/hook.sh"
sed "s|__TOOLKIT_ROOT__|$TOOLKIT|g" "$TOOLKIT/claude-hooks/hooks/interview-gate.sh" > "$HOOK"
mkdir -p "$P/analysis/knowledge-base/brd"
cat > "$P/analysis/knowledge-base/brd/F001-x.brd.json" <<'JSON'
{ "id":"F001","title":"X","stage":2,
  "openQuestions":[{"id":"Q1","question":"Should discounts compound?","status":"Open"}] }
JSON
fire() { rm -f "$P/.claude/.interview-gate-last"
         printf '{"stop_hook_active":false}' | env "$@" CLAUDE_PROJECT_DIR="$P" bash "$HOOK" 2>/dev/null; }

case "$(fire CLAUDE_INTERVIEW_MODE=steering)" in
  *'"block"'*) ok "steering still blocks — the reported failure stays fixed" ;;
  *) bad "steering did not block; the knob disabled the gate entirely" ;;
esac
[ -z "$(fire CLAUDE_INTERVIEW_MODE=auto)" ] \
  && ok "auto does not block" \
  || bad "auto blocked — the mode is a lie and the user is back to being stopped"
[ -f "$P/docs/open-questions.html" ] \
  && ok "auto still writes the report (the recording is the safety net)" \
  || bad "auto skipped the report — questions now vanish with nothing to review"
[ -z "$(fire CLAUDE_INTERVIEW_REMOTE=1)" ] \
  && ok "remote does not park the run even in steering" \
  || bad "remote still blocked — a run stalls against a keyboard nobody is at"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
