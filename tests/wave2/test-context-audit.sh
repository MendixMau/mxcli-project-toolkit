#!/usr/bin/env bash
# test-context-audit.sh — bin/context-audit.sh against a captured, scrubbed transcript tree.
#   usage: bash tests/wave2/test-context-audit.sh bin/context-audit.sh
# The fixture (tests/wave2/fixtures/context-audit/, see CAPTURE.md) is a real 2026-09-30
# capture; every number asserted here is what that capture actually contains.
set -u
SUT="${1:?usage: $0 bin/context-audit.sh}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIX="$HERE/fixtures/context-audit"
PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); echo "  ok    $*"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL  $*"; }
has()  { if grep -qE -- "$2" "$1"; then ok "$3"; else fail "$3 — expected /$2/"; fi; }
hasnt(){ if grep -qE -- "$2" "$1"; then fail "$3 — unexpected /$2/"; else ok "$3"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

echo "context-audit — $SUT"
CLAUDE_CONFIG_DIR="$FIX" bash "$SUT" --top 40 > "$T/out" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "exit 0" || fail "exit $rc"
has   "$T/out" "1 session\(s\), 1 subagent run\(s\)" "counts the session and its subagent"
has   "$T/out" "subagent runs +1 +52,503" "start context of the subagent = its first call's input + cache"
has   "$T/out" "sessions +1 +109,374" "start context of the session"
# paging is not re-reading; the same part again is (Read defaults: offset 1, limit 2000)
has   "$T/out" "toolkit:skills/conversion-runbook.md +6 +1 +[0-9,]+ +[0-9,]+ +2$" "runbook: 6 paged reads, 2 of them repeats"
has   "$T/out" "toolkit:skills/query-the-model.md +2 +1 +[0-9,]+ +[0-9,]+ +1$" "no-limit read == limit-2000 read: 1 re-read"
has   "$T/out" "toolkit:skills/learned-mdl-preflight.md +1 +1 +9,846" "size of one full read"
# shell reads: cd + relative path, VAR= prefixes, git show REV:path
has   "$T/out" "toolkit:bin/token-burn.sh" "git show REV:path after cd resolves into the toolkit"
has   "$T/out" "toolkit:bin/doctor.sh" "git show REV:path with no cd resolves against the record cwd"
# instruction files and masking
has   "$T/out" "toolkit:CLAUDE.md +2 +6,326" "auto-loaded instruction file, per run"
has   "$T/out" "project-1/\*/CLAUDE.local.md" "project paths masked by default"
hasnt "$T/out" "/srv/example/proj" "no real project path when masked"
has   "$T/out" "1 compaction\(s\), 1 automatic; context when it fired: median 183,892" "compaction and its size"
CLAUDE_CONFIG_DIR="$FIX" bash "$SUT" --names > "$T/names" 2>&1
has   "$T/names" "/srv/example/proj/CLAUDE.local.md" "--names shows real paths"
CLAUDE_CONFIG_DIR="$T/none" bash "$SUT" > "$T/na" 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "no transcript tree: exit 0" || fail "no transcript tree: exit $rc"
has   "$T/na" "^NOT AVAILABLE" "no transcript tree: says NOT AVAILABLE, not zero"

echo; echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
