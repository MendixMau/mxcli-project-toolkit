#!/usr/bin/env bash
# test-token-burn.sh — pin bin/token-burn.sh against a CAPTURED (then scrubbed) Claude Code
# transcript: tests/wave2/fixtures/token-burn/CAPTURE.md says what was captured, how it was
# scrubbed, and the expected sums computed independently of the instrument.
#
#   T1  no transcript tree → NOT AVAILABLE in brief, screen and json (available:false), exit 0
#   T2  --json: per-model arrays to the token; 52 records dedupe to 22 messages; 1 synthetic
#       skipped; 2 files; subagent headline 59858
#   T3  the two-tree layout: records whose cwd is <root>/app count — moving them out of the
#       project drops the message count from 22 to 21
#   T4  --brief: the exact "Tokens this stage:" line for stage 2
#   T5  screen: synthetic count, stage-2 row, current-stage line, no UNMAPPED
#   T6  no PROJECT.md → every day UNMAPPED; brief prints the project total and says why
#   T7  a foreign slug dir only → NOT AVAILABLE with the --scan-all hint; --scan-all finds it
#   T8  the ancestor slug dir (session launched in the parent) is read by default
#
#   tests/wave2/test-token-burn.sh /path/to/token-burn.sh

set -uo pipefail

SUT="${1:?usage: test-token-burn.sh /path/to/token-burn.sh}"
case "$SUT" in /*) ;; *) SUT="$PWD/$SUT" ;; esac
TOOLKIT="$(cd "$(dirname "$SUT")/.." && pwd)"
FIX="$TOOLKIT/tests/wave2/fixtures/token-burn"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/tb.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
has()   { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing '$3' in: $2" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1" "unexpected '$3'" ;; *) ok "$1" ;; esac; }

[ -f "$FIX/transcripts/s-1.jsonl" ] || { echo "fixture missing"; exit 2; }

slug() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }

P="$WORK/proj"; mkdir -p "$P/app"
cp "$FIX/PROJECT.md" "$P/PROJECT.md"

# install the fixture transcripts under a slug dir, rewriting the scrubbed root to $P
install_tree() {   # $1 = config dir, $2 = slug dir name
  local d="$1/projects/$2"
  mkdir -p "$d/s-1/subagents"
  sed "s#/srv/example/proj#$P#g" "$FIX/transcripts/s-1.jsonl" > "$d/s-1.jsonl"
  sed "s#/srv/example/proj#$P#g" "$FIX/transcripts/s-1/subagents/agent-1.jsonl" > "$d/s-1/subagents/agent-1.jsonl"
}

CFG="$WORK/claude"; install_tree "$CFG" "$(slug "$P")"

# --- T1: no tree --------------------------------------------------------------------------
OUT="$(CLAUDE_CONFIG_DIR="$WORK/nowhere" bash "$SUT" "$P" --brief 2>&1)"; RC=$?
has "T1 brief NOT AVAILABLE" "$OUT" "Tokens this stage: NOT AVAILABLE"
[ "$RC" = 0 ] && ok "T1 brief exit 0" || bad "T1 brief exit 0" "rc=$RC"
OUT="$(CLAUDE_CONFIG_DIR="$WORK/nowhere" bash "$SUT" "$P" 2>&1)"; RC=$?
has "T1 screen NOT AVAILABLE" "$OUT" "NOT AVAILABLE"
[ "$RC" = 0 ] && ok "T1 screen exit 0" || bad "T1 screen exit 0" "rc=$RC"
OUT="$(CLAUDE_CONFIG_DIR="$WORK/nowhere" bash "$SUT" "$P" --json 2>&1)"
has "T1 json available:false" "$OUT" '"available": false'

# --- T2: json, exact sums ------------------------------------------------------------------
# the instrument pretty-prints (indent=1, one list element per line); fold the whitespace so a
# per-model array can be pinned as one literal (no python here — check-portability)
J="$(CLAUDE_CONFIG_DIR="$CFG" bash "$SUT" "$P" --json 2>&1 | tr -d '\n' | tr -s ' ' | sed 's/\[ /[/g; s/ \]/]/g')"
has "T2 fable-5-1 array" "$J" '"claude-fable-5-1": [288, 31365, 2607781, 15524, 9]'
has "T2 sonnet-5 array"  "$J" '"claude-sonnet-5": [26, 59772, 998476, 60, 13]'
has "T2 22 messages"     "$J" '"messages": 22'
has "T2 52 records (dedupe)" "$J" '"records": 52'
has "T2 1 synthetic"     "$J" '"synthetic_skipped": 1'
has "T2 2 files"         "$J" '"files": 2'
has "T2 subagent headline" "$J" '"subagents": 59858'
has "T2 main headline"   "$J" '"main": 47177'
has "T2 current stage"   "$J" '"current_stage": "2"'

# --- T3: two-tree cwd counts ----------------------------------------------------------------
CFG3="$WORK/claude3"; d3="$CFG3/projects/$(slug "$P")"; mkdir -p "$d3/s-1/subagents"
sed "s#/srv/example/proj/app#$WORK/elsewhere#g; s#/srv/example/proj#$P#g" "$FIX/transcripts/s-1.jsonl" > "$d3/s-1.jsonl"
sed "s#/srv/example/proj#$P#g" "$FIX/transcripts/s-1/subagents/agent-1.jsonl" > "$d3/s-1/subagents/agent-1.jsonl"
J3="$(CLAUDE_CONFIG_DIR="$CFG3" bash "$SUT" "$P" --json 2>&1)"
has "T3 app/ records counted (22 -> 21 once moved out of the root)" "$J3" '"messages": 21'

# --- T4: brief -----------------------------------------------------------------------------
B="$(CLAUDE_CONFIG_DIR="$CFG" bash "$SUT" "$P" --brief 2>&1)"
[ "$B" = "Tokens this stage: 69k (sonnet-5 87% · fable-5-1 13% · 1438k cache-read · 2 days · stage 2)" ] \
  && ok "T4 brief line exact" || bad "T4 brief line exact" "$B"

# --- T5: screen -----------------------------------------------------------------------------
S="$(CLAUDE_CONFIG_DIR="$CFG" bash "$SUT" "$P" 2>&1)"
has "T5 synthetic skipped" "$S" "1 synthetic skipped"
has "T5 22 messages from 52 records" "$S" "22 messages (from 52 records"
has "T5 current stage line" "$S" "register says current stage 2"
has "T5 subagent share" "$S" "subagents (Agent tool): 60k of headline (56%)"
# the caveat line legitimately explains what UNMAPPED means; no day or stage row may carry it
hasnt "T5 no UNMAPPED row" "$(echo "$S" | grep -v '^  caveat:')" "UNMAPPED"
echo "$S" | grep -Eq '^ *2 +2 +69k +1438k +17 ' && ok "T5 stage-2 row" || bad "T5 stage-2 row" "$(echo "$S" | grep -E '^ *2 ' | head -3)"
echo "$S" | grep -Eq '^ *1 +1 +39k +2168k +5 ' && ok "T5 stage-1 row" || bad "T5 stage-1 row" "$(echo "$S" | grep -E '^ *1 ' | head -3)"

# --- T6: no PROJECT.md ----------------------------------------------------------------------
P6="$WORK/proj6"; mkdir -p "$P6/app"
CFG6="$WORK/claude6"; d="$CFG6/projects/$(slug "$P6")"; mkdir -p "$d/s-1/subagents"
sed "s#/srv/example/proj#$P6#g" "$FIX/transcripts/s-1.jsonl" > "$d/s-1.jsonl"
sed "s#/srv/example/proj#$P6#g" "$FIX/transcripts/s-1/subagents/agent-1.jsonl" > "$d/s-1/subagents/agent-1.jsonl"
S6="$(CLAUDE_CONFIG_DIR="$CFG6" bash "$SUT" "$P6" 2>&1)"
has "T6 screen UNMAPPED" "$S6" "UNMAPPED"
B6="$(CLAUDE_CONFIG_DIR="$CFG6" bash "$SUT" "$P6" --brief 2>&1)"
has "T6 brief falls back to the project total" "$B6" "Tokens this stage: 107k ("
has "T6 brief says why" "$B6" "no Current stage line in PROJECT.md"

# --- T7: foreign slug only ------------------------------------------------------------------
CFG7="$WORK/claude7"; install_tree "$CFG7" "-somewhere-else-entirely"
B7="$(CLAUDE_CONFIG_DIR="$CFG7" bash "$SUT" "$P" --brief 2>&1)"; RC=$?
has "T7 NOT AVAILABLE with hint" "$B7" "try --scan-all"
[ "$RC" = 0 ] && ok "T7 exit 0" || bad "T7 exit 0" "rc=$RC"
J7="$(CLAUDE_CONFIG_DIR="$CFG7" bash "$SUT" "$P" --json --scan-all 2>&1)"
has "T7 --scan-all finds 22" "$J7" '"messages": 22'

# --- T8: ancestor slug dir ------------------------------------------------------------------
CFG8="$WORK/claude8"; install_tree "$CFG8" "$(slug "$WORK")"
J8="$(CLAUDE_CONFIG_DIR="$CFG8" bash "$SUT" "$P" --json 2>&1)"
has "T8 ancestor dir read by default" "$J8" '"messages": 22'

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
