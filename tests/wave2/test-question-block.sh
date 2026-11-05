#!/bin/bash
# test-question-block.sh — the subagent question-block contract is stated once and wired where
# the acting agent reads it.
#
# Why: on Claude Code `AskUserQuestion` exists only in the main session; subagents never get it.
# ba-agent and architect-agent own the interview gates, so their questions came back as prose,
# the main session relayed the prose, and new users typed every answer by hand. The fix is a
# fixed block shape (interview-protocol.md §3 → "Asking from a subagent") that the subagent ends
# its report with and the main session renders. This fixture checks the three things that rot:
#   1. the canonical section exists, and its own worked example obeys the contract it states;
#   2. every copy of the block (the two stubs inline it) is byte-identical to §3's;
#   3. both interview-owning stubs and both lead-side skills point at it by its heading name.
#
# Usage: bash test-question-block.sh [path-to-interview-protocol.md]

TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/skills/interview-protocol.md}"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }
HEAD='Asking from a subagent'

echo "== subject: $SUBJECT"
[ -f "$SUBJECT" ] || { echo "  subject not found"; exit 2; }

echo "== 1: the canonical section and its example"
n=$(grep -c "^#### $HEAD" "$SUBJECT")
[ "$n" -eq 1 ] && ok "one '#### $HEAD' heading" || bad "'#### $HEAD' heading count = $n (want 1)"

# The worked example: lines between the opening ```question fence and the next ``` fence.
EX="$(awk '/^```question$/{f=1;next} f&&/^```/{exit} f' "$SUBJECT")"
[ -n "$EX" ] && ok "a \`\`\`question example block is present" || bad "no \`\`\`question example block"
printf '%s\n' "$EX" | grep -q '^Q: ' && ok "example has a Q: line" || bad "example has no Q: line"
H="$(printf '%s\n' "$EX" | sed -n 's/^header: //p')"
if [ -n "$H" ] && [ "${#H}" -le 12 ]; then ok "example header '$H' is <=12 chars (AskUserQuestion limit)"
else bad "example header '$H' missing or longer than 12 chars"; fi
OPTS="$(printf '%s\n' "$EX" | grep '^- ' | grep -v '^- Something else')"
NO=$(printf '%s\n' "$OPTS" | grep -c .)
[ "$NO" -ge 2 ] && [ "$NO" -le 4 ] && ok "example has $NO options (2-4)" || bad "example has $NO options (want 2-4)"
printf '%s\n' "$OPTS" | head -1 | grep -q '(Recommended):' && ok "first option is the recommended one" \
  || bad "first option is not marked (Recommended)"
printf '%s\n' "$EX" | grep '^- ' | tail -1 | grep -q '^- Something else' && ok "last option is Something else" \
  || bad "last option is not Something else"
BADOPT=$(printf '%s\n' "$OPTS" | grep -vc '^- [^:]*: ')
[ "$BADOPT" -eq 0 ] && ok "every option is 'label: consequence'" || bad "$BADOPT option(s) not 'label: consequence'"

SEC="$(awk -v h="^#### $HEAD" '$0~h{f=1;next} f&&/^###/{exit} f' "$SUBJECT")"
for want in 'AskUserQuestion' 'end the turn' 'request_user_input' 'Never answer a block yourself'; do
  printf '%s' "$SEC" | grep -q "$want" && ok "main-session rule names '$want'" || bad "section does not name '$want'"
done

echo "== 2: one shape — any other file that writes the block out carries §3's block byte for byte"
# The stubs carry a copy on purpose: the 2026-11-05 field run showed a ba-agent given only the
# pointer never opened §3 and improvised its own fields (id/gate/question/recommendation).
canon="$(awk '/^```question$/{f=1} f{print} f&&/^```$/{exit}' "$SUBJECT")"
for f in $(grep -rlE '^```question$' "$TOOLKIT/skills" "$TOOLKIT/agents" 2>/dev/null | grep -vF "$(basename "$SUBJECT")"); do
  copy="$(awk '/^```question$/{f=1} f{print} f&&/^```$/{exit}' "$f")"
  [ "$copy" = "$canon" ] && ok "${f#$TOOLKIT/} carries the canonical block unchanged" \
    || bad "${f#$TOOLKIT/} carries a question block that differs from §3's"
done
for f in agents/ba-agent.md agents/architect-agent.md; do
  grep -qE '^```question$' "$TOOLKIT/$f" && ok "$f inlines the shape (a pointer alone was not read)" \
    || bad "$f has no inline question block"
done

echo "== 3: wired where the acting agent reads it"
for f in agents/ba-agent.md agents/architect-agent.md; do
  grep -q "$HEAD" "$TOOLKIT/$f" && ok "$f points at '$HEAD'" || bad "$f does not point at '$HEAD'"
  grep -q 'cannot ask the user' "$TOOLKIT/$f" && ok "$f says it cannot ask the user" || bad "$f never says it cannot ask"
  grep -q 'question` blocks' "$TOOLKIT/$f" && ok "$f's report ends with question blocks" || bad "$f's report does not name question blocks"
done
for f in skills/dispatching.md skills/agent-roles.md agents/README.md; do
  grep -q "$HEAD" "$TOOLKIT/$f" && ok "$f points at '$HEAD'" || bad "$f does not point at '$HEAD'"
done

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
