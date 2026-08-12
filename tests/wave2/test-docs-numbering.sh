#!/usr/bin/env bash
# Fixture for bin/check-docs-numbering.sh (the guard landed for wave-2 #9/#10).
#
# A guard is not fixed until it has been run against a case it is supposed to FAIL.
# Half of these cases are exactly that — and one of them (T1) is the real
# pre-fix skills/iterative-build-loop.md, so the guard is proven against the
# document that earned it, not only against synthetic bait.
#
# The silent-no-op trap is the point of T5 and T6: the first draft of rule A used
# `\b`, which BSD awk accepts and never matches. It printed ✅ on a file with three
# real hits. Any assertion here of the form "the guard passed" is worthless unless
# a sibling assertion proves the same guard can fail.
#
# Usage: test-docs-numbering.sh /path/to/check-docs-numbering.sh
set -uo pipefail

CHECK="${1:?usage: test-docs-numbering.sh /path/to/check-docs-numbering.sh}"
case "$CHECK" in /*) ;; *) CHECK="$PWD/$CHECK" ;; esac
TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d /tmp/ckdocs.XXXXXX)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

# A throwaway repo, because the guard resolves paths through `git rev-parse`.
R="$WORK/repo"
mkdir -p "$R/skills" "$R/bin"
cp "$CHECK" "$R/bin/check-docs-numbering.sh"
chmod +x "$R/bin/check-docs-numbering.sh"
( cd "$R" && git init -q . ) >/dev/null 2>&1

# run <file-basename> -> prints output, sets RC
run() {
  ( cd "$R" && git add -A >/dev/null 2>&1; ./bin/check-docs-numbering.sh --all 2>&1 )
}
rc_of() { ( cd "$R" && git add -A >/dev/null 2>&1; ./bin/check-docs-numbering.sh --all >/dev/null 2>&1 ); echo $?; }
reset_docs() { rm -f "$R"/skills/*.md; }

echo "== T1: the REAL pre-fix build loop is rejected =="
reset_docs
if git -C "$TOOLKIT" show 2ea198c:skills/iterative-build-loop.md > "$R/skills/iterative-build-loop.md" 2>/dev/null; then
  OUT="$(run)"; RC=$(rc_of)
  [ "$RC" -ne 0 ] && ok "pre-fix doc rejected (exit $RC)" || bad "pre-fix doc PASSED — the guard is a no-op"
  printf '%s' "$OUT" | grep -q '12-step' && ok "flagged the 12-step claim"  || bad "missed the 12-step claim"
  printf '%s' "$OUT" | grep -q '13-step' && ok "flagged the 13-step claim"  || bad "missed the 13-step claim"
  printf '%s' "$OUT" | grep -q 'gate labels' && ok "flagged the 2/4/3 gate order" || bad "missed the gate ordering"
  printf '%s' "$OUT" | grep -q '15-step' && bad "false-positived on the CORRECT 15-step claim" \
                                         || ok "left the correct 15-step claim alone"
else
  bad "[setup] could not read the baseline doc from 2ea198c"
fi

echo "== T2: the CURRENT build loop passes =="
reset_docs
cp "$TOOLKIT/skills/iterative-build-loop.md" "$R/skills/"
RC=$(rc_of)
[ "$RC" -eq 0 ] && ok "fixed doc accepted" || bad "fixed doc still rejected: $(run | head -3)"

echo "== T3: rule A — a wrong count is caught =="
reset_docs
{ printf 'The 5-step process:\n\n'; printf '1. a\n2. b\n3. c\n'; } > "$R/skills/a.md"
OUT="$(run)"; RC=$(rc_of)
[ "$RC" -ne 0 ] && ok "wrong count rejected" || bad "wrong count accepted"
printf '%s' "$OUT" | grep -q 'delete the count' && ok "says to delete the count, not fix it" \
                                                || bad "wrong remediation advice"

echo "== T4: rule A — a right count is left alone =="
reset_docs
{ printf 'The 3-step process:\n\n'; printf '1. a\n2. b\n3. c\n'; } > "$R/skills/a.md"
[ "$(rc_of)" -eq 0 ] && ok "matching count accepted" || bad "false positive on a correct count"

echo "== T5: rule A — a fenced list is still counted =="
# The bug this rule exists for lived inside a ``` block. If fencing hid the list,
# the rule would have been silent on the only file it was written for.
reset_docs
{ printf 'The 9-step loop:\n\n```\n'; printf '1. a\n2. b\n3. c\n'; printf '```\n'; } > "$R/skills/a.md"
[ "$(rc_of)" -ne 0 ] && ok "fenced list counted (rule is fence-agnostic)" || bad "fenced list invisible — the original bug survives"

echo "== T6: rule B — gates that run 2, 4, 3 with no Gate 1 =="
reset_docs
{ printf '**Gate 2 — build**\n\ntext\n\n**Gate 4 — ui**\n\ntext\n\n**Gate 3 — coverage**\n'; } > "$R/skills/a.md"
OUT="$(run)"; RC=$(rc_of)
[ "$RC" -ne 0 ] && ok "2/4/3 rejected" || bad "2/4/3 accepted"
printf '%s' "$OUT" | grep -q 'name the gates' && ok "says to name the gates, not renumber" \
                                              || bad "wrong remediation advice"

echo "== T7: rule B — contiguous gates from 1 are fine =="
reset_docs
printf '**Gate 1 — a**\n\nx\n\n**Gate 2 — b**\n\nx\n\n**Gate 3 — c**\n' > "$R/skills/a.md"
[ "$(rc_of)" -eq 0 ] && ok "1/2/3 accepted" || bad "false positive on contiguous gates"

echo "== T8: named gates are not ordinals and must not be parsed as any =="
reset_docs
printf '**Gate: SYNTAX**\n\nx\n\n**Gate: BUILD**\n\nx\n\n**Gate: UI**\n' > "$R/skills/a.md"
[ "$(rc_of)" -eq 0 ] && ok "named gates accepted" || bad "named gates rejected — the recommended fix would not pass"

echo "== T9: prose that merely contains a digit and 'step' is not a claim =="
reset_docs
printf 'See §1 step 6 and the J001 steps table.\n\n1. a\n2. b\n' > "$R/skills/a.md"
[ "$(rc_of)" -eq 0 ] && ok "no false positive on '§1 step 6' / 'J001 steps'" || bad "false positive on ordinary prose"

echo "== T10: only the checked globs are examined =="
reset_docs
mkdir -p "$R/bug-logs"
printf 'The 9-step retest:\n\n1. a\n' > "$R/bug-logs/notes.md"
[ "$(rc_of)" -eq 0 ] && ok "bug-logs/ ignored" || bad "reached outside skills/ agents/ process/"

echo ""
echo "PASS=$PASS FAIL=$FAIL   ($WORK)"
[ "$FAIL" -eq 0 ]
