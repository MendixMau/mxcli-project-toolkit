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

# --- aliases: the words the docs used to teach ----------------------------------------------
# CLAUDE.md, the runbook and intake Q9 told users to write `Interview mode: unattended`. The
# script knew only steering|assist|auto, so a project that opted in exactly as documented was
# silently run as steering. `unattended` = auto and `attended` = steering, in every source;
# stdout stays the canonical name so every consumer (interview-gate.sh) keeps working.
A="$WORK/alias"; mkdir -p "$A/.claude"
# alias_case <label> <expected> <cmd...>: stdout must be canonical AND stderr must name the alias.
alias_case() {
  _lbl="$1"; _want="$2"; shift 2
  _out=$("$@" 2>"$WORK/alias.err"); _err=$(cat "$WORK/alias.err")
  [ "$_out" = "$_want" ] && ok "$_lbl resolves to $_want" \
                         || bad "$_lbl resolved to '$_out', want '$_want'"
  case "$_err" in *"read as '$_want' (alias)"*) ok "$_lbl prints the alias note" ;;
    *) bad "$_lbl printed no alias note (stderr: $_err)" ;; esac
}
alias_case "env unattended" auto     env CLAUDE_INTERVIEW_MODE=unattended bash "$SUBJECT" "$A"
alias_case "env attended"   steering env CLAUDE_INTERVIEW_MODE=attended bash "$SUBJECT" "$A"
printf 'unattended\n' > "$A/.claude/.interview-mode"
alias_case "file unattended" auto     bash "$SUBJECT" "$A"
printf 'attended\n' > "$A/.claude/.interview-mode"
alias_case "file attended"   steering bash "$SUBJECT" "$A"
rm -f "$A/.claude/.interview-mode"
# Same parse rules as the canonical values: list bullet, bold key, any case.
printf -- '- **Interview mode:** Unattended\n' > "$A/PROJECT.md"
alias_case "PROJECT.md bold key, capitalised unattended" auto bash "$SUBJECT" "$A"
printf 'Interview mode: attended\n' > "$A/PROJECT.md"
alias_case "PROJECT.md attended" steering bash "$SUBJECT" "$A"
rm -f "$A/PROJECT.md"
bash "$SUBJECT" "$A" --set unattended >/dev/null 2>"$WORK/alias.err"
[ "$(tr -d '[:space:]' < "$A/.claude/.interview-mode" 2>/dev/null)" = "auto" ] \
  && ok "--set unattended stores the canonical 'auto'" \
  || bad "--set unattended did not store 'auto'"
grep -q "read as 'auto' (alias)" "$WORK/alias.err" \
  && ok "--set unattended prints the alias note" || bad "--set unattended printed no alias note"
bash "$SUBJECT" "$A" --set attended >/dev/null 2>"$WORK/alias.err"
[ "$(bash "$SUBJECT" "$A" 2>/dev/null)" = "steering" ] \
  && ok "--set attended resolves to steering" || bad "--set attended did not resolve to steering"
grep -q "read as 'steering' (alias)" "$WORK/alias.err" \
  && ok "--set attended prints the alias note" || bad "--set attended printed no alias note"
rm -f "$A/.claude/.interview-mode"
# Typos keep the old rule; canonical values stay quiet.
[ "$(CLAUDE_INTERVIEW_MODE=unatended bash "$SUBJECT" "$A" 2>/dev/null)" = "steering" ] \
  && ok "typo 'unatended' still falls back to steering" \
  || bad "a misspelled alias resolved to something other than steering"
printf 'Interview mode: unattend\n' > "$A/PROJECT.md"
[ "$(bash "$SUBJECT" "$A" 2>/dev/null)" = "steering" ] \
  && ok "typo 'unattend' in PROJECT.md still falls back to steering" \
  || bad "a misspelled PROJECT.md alias did not fall back to steering"
# PROJECT.md is human-written and gets annotated. The rule (review of #335, 2026-10-14):
#   - a value that is exactly one mode or alias (bold/backticks stripped, trailing '.' allowed)
#     is used;
#   - trailing text after `steering`/`attended` is a harmless note: steering is the loudest mode;
#   - trailing text after `assist`/`auto`/`unattended` falls back to steering, with a stderr line
#     saying a quieter mode must stand alone on the line.
# Two hedge WORD LISTS were tried first and both leaked ("auto / steering", "auto (pending
# sign-off)", "(maybe)", "(tentative)" …). A quieter mode never resolves from an annotated line,
# so no list of hedge words is needed and none can leak. Env, file and --set stay exact.
md_case() {  # md_case <label> <expected> <PROJECT.md line>
  printf '%s\n' "$3" > "$A/PROJECT.md"
  _got=$(bash "$SUBJECT" "$A" 2>/dev/null)
  [ "$_got" = "$2" ] && ok "PROJECT.md $1 resolves to $2" \
                     || bad "PROJECT.md $1 resolved to '$_got', want '$2'"
}
# stand-alone values resolve
md_case "bare bold value"                   auto     '- **Interview mode:** **auto**'
md_case "bare backticked value"             auto     'Interview mode: `auto`'
md_case "value with a trailing full stop"   auto     'Interview mode: auto.'
md_case "bare capitalised alias"            auto     'Interview mode: Unattended'
md_case "bare backticked assist"            assist   'Interview mode: `assist`'
# a note after steering is fine
md_case "steering + note"                   steering 'Interview mode: steering (default, user asked)'
printf 'Interview mode: steering (default, user asked)\n' > "$A/PROJECT.md"
[ -z "$(bash "$SUBJECT" "$A" 2>&1 >/dev/null)" ] \
  && ok "steering + note prints nothing on stderr" \
  || bad "steering + note printed something on stderr"
md_case "attended + note"                   steering 'Interview mode: attended (default)'
# BEHAVIOUR CHANGE vs 12838b4: a quieter mode with ANY note is not taken. Plain notes too —
# telling a plain note from a hedge is the word list that did not converge.
md_case "auto + plain note (now steering)"      steering 'Interview mode: auto (user asked 2026-10-14)'
md_case "bold auto + dash note (now steering)"  steering '- **Interview mode:** **auto** — fast POC'
md_case "alias + comma note (now steering)"     steering 'Interview mode: Unattended, per user'
md_case "assist + note (now steering)"          steering 'Interview mode: `assist` until Stage 3'
# every hedge from both reviews
md_case "hedge: auto?"                      steering 'Interview mode: auto?'
md_case "hedge: auto? + note"               steering 'Interview mode: auto? (to confirm with user)'
md_case "hedge: unattended? ask user"       steering 'Interview mode: unattended? ask user'
md_case "hedge: auto | steering"            steering 'Interview mode: auto | steering'
md_case "hedge: auto / steering"            steering 'Interview mode: auto / steering'
md_case "hedge: auto or steering"           steering 'Interview mode: auto or steering'
md_case "hedge: auto (proposed…)"           steering 'Interview mode: auto (proposed, not confirmed)'
md_case "hedge: auto TBD"                   steering 'Interview mode: auto TBD'
md_case "hedge: auto (pending sign-off)"    steering 'Interview mode: auto (pending sign-off)'
md_case "hedge: auto (maybe)"               steering 'Interview mode: auto (maybe)'
md_case "hedge: auto (tentative)"           steering 'Interview mode: auto (tentative)'
md_case "hedge: auto (draft)"               steering 'Interview mode: auto (draft)'
md_case "hedge: auto — awaiting user"       steering 'Interview mode: auto — awaiting user'
md_case "hedge: recommended"                steering '- **Interview mode:** auto (recommended by triage)'
printf 'Interview mode: auto (pending sign-off)\n' > "$A/PROJECT.md"
_err=$(bash "$SUBJECT" "$A" 2>&1 >/dev/null)
case "$_err" in *"must stand alone on the line"*) ok "auto + note says on stderr it must stand alone" ;;
  *) bad "auto + note gave no stand-alone message (stderr: $_err)" ;; esac
[ "$(printf '%s\n' "$_err" | grep -c .)" = "1" ] \
  && ok "and says it in exactly one line" || bad "stand-alone fallback printed $(printf '%s\n' "$_err" | grep -c .) lines"
bash "$SUBJECT" "$A" --explain 2>/dev/null | grep -q 'fallback (quieter mode with trailing text)' \
  && ok "--explain names the stand-alone fallback" \
  || bad "--explain does not name the stand-alone fallback"
# typos and empties
md_case "typo first word + note"            steering 'Interview mode: atuo (user asked)'
md_case "a word that merely starts with a mode" steering 'Interview mode: auto-ish'
md_case "empty value"                       steering 'Interview mode:'
md_case "empty bold value"                  steering '- **Interview mode:** '
# Machine-written sources stay exact: trailing text there is corruption, not annotation.
printf 'auto extra\n' > "$A/.claude/.interview-mode"; rm -f "$A/PROJECT.md"
[ "$(bash "$SUBJECT" "$A" 2>/dev/null)" = "steering" ] \
  && ok "session file with trailing text is still rejected (exact match)" \
  || bad "session file with trailing text was accepted"
rm -f "$A/.claude/.interview-mode"
[ "$(CLAUDE_INTERVIEW_MODE='auto please' bash "$SUBJECT" "$A" 2>/dev/null)" = "steering" ] \
  && ok "env value with trailing text is still rejected (exact match)" \
  || bad "env value with trailing text was accepted"
bash "$SUBJECT" "$A" --set 'auto please' >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "--set with trailing text is still rejected" \
               || bad "--set accepted a value with trailing text"
printf 'Interview mode: auto\n' > "$A/PROJECT.md"
[ -z "$(bash "$SUBJECT" "$A" 2>&1 >/dev/null)" ] \
  && ok "a canonical value prints no alias note" \
  || bad "a canonical value printed something on stderr"
[ -z "$(CLAUDE_INTERVIEW_MODE=assist bash "$SUBJECT" "$A" 2>&1 >/dev/null)" ] \
  && ok "canonical env value prints no alias note" \
  || bad "canonical env value printed something on stderr"
rm -f "$A/PROJECT.md"

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
[ -f "$P/analysis/brd-report.html" ] \
  && ok "auto still writes the report (the recording is the safety net)" \
  || bad "auto skipped the report — questions now vanish with nothing to review"
[ -z "$(fire CLAUDE_INTERVIEW_MODE=unattended)" ] \
  && ok "the hook reads 'unattended' as auto and does not block" \
  || bad "the hook blocked on 'unattended' — the documented opt-in is ignored"
[ -z "$(fire CLAUDE_INTERVIEW_REMOTE=1)" ] \
  && ok "remote does not park the run even in steering" \
  || bad "remote still blocked — a run stalls against a keyboard nobody is at"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
