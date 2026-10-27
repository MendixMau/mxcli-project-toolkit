#!/usr/bin/env bash
# Fixture for exec.sh's "lint: only what THIS script added" view (PR #581) and its carry-forward.
#
# usage: test-exec-lint-diff.sh /path/to/exec.sh
#
# run_lint_gate() is extracted from the given exec.sh and run against the real lint-gate.sh, with
# lint output fed through LINT_JSON (no mxcli, no .mpr), one call per simulated exec.
#   D1  a script adds a finding: rose, the finding is printed, LINT_RC 1
#   D2  the next exec leaves it unfixed: still rose and printed (it went silent before: "0 new")
#   D3  it is fixed: clean again
#   D4  the user accepts it (lint-gate --update-baseline --reason): the next exec is clean
#   D5  a rose exec lands in the metrics ledger as applied-lint-rose (status text exec.sh writes)
#   D7  a rise while lint-last.json cannot be read: kept as a rise, never "0 new"
#   D6  the diff cannot run (no usable Python): reported as a rise vs baseline, never as "0 new"
set -uo pipefail
EXEC="${1:?usage: test-exec-lint-diff.sh /path/to/exec.sh}"
TK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$TK/bin/lib/portable.sh"
require_py
WORK="$(mktemp -d "${TMPDIR:-/tmp}/lint-diff.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }

P="$WORK/proj"; mkdir -p "$P/bin" "$P/.claude"
cp "$TK/project-bin/lint-gate.sh" "$TK/project-bin/_common.sh" "$TK/project-bin/metrics-ledger.sh" "$P/bin/"
printf 'mpr' > "$P/App.mpr"; printf '#!/bin/sh\nexit 0\n' > "$P/mxcli"; chmod +x "$P/mxcli" "$P/bin/"*.sh
( . "$TK/bin/lib/install-lint-rules.sh"; mxtk_install_lint_rules "$TK" "$P" 0 "" ) >/dev/null 2>&1
printf '| Toolkit root | `%s` |\n' "$TK" > "$P/CLAUDE.local.md"

f() { printf '{"ruleId":"%s","severity":"warning","message":"%s","module":"Orders","document":"%s","documentType":"microflow","documentId":"id-%s","suggestion":"s"}' "$1" "$2" "$3" "$3"; }
debt="$(f CONV010 old Old_Flow)"
lint() { printf '{"violations":[%s],"summary":{}}' "$1" > "$WORK/lint.json"; }
lint "$debt"; (cd "$P" && LINT_JSON="$WORK/lint.json" bash bin/lint-gate.sh --update-baseline >/dev/null 2>&1)

fn="$WORK/run_lint_gate.sh"; sed -n '/^run_lint_gate() {/,/^}/p' "$EXEC" > "$fn"
run_exec() { (cd "$P" && PROJECT_ROOT="$P" LINT_JSON="$WORK/lint.json" "$@" bash -c \
  ". '$P/bin/_common.sh'; . '$fn'; LINT_RC=0; run_lint_gate; echo \"RESULT \$LINT_RC|\$LINT_DETAIL\"") 2>&1; }
newf="$(f MPR001 "name do_stuff" do_stuff)"

echo "D1 a script adds a finding"
lint "$debt,$newf"; out=$(run_exec)
{ printf '%s' "$out" | grep -q 'RESULT 1|lint rose' && printf '%s' "$out" | grep -q 'MPR001'; } \
  && ok "D1: rose, rc 1, MPR001 printed" || bad "D1" "$out"
echo "D2 the next exec leaves it unfixed"
out=$(run_exec)
{ printf '%s' "$out" | grep -q 'RESULT 1|lint rose' && printf '%s' "$out" | grep -q 'MPR001'; } \
  && ok "D2: the unfixed finding is still rose and printed" || bad "D2: went silent" "$out"
out=$(run_exec)
printf '%s' "$out" | grep -q 'RESULT 1|lint rose' && ok "D2: and on the exec after that" || bad "D2 third exec" "$out"
echo "D3 it is fixed"
lint "$debt"; out=$(run_exec)
printf '%s' "$out" | grep -q 'RESULT 0|' && ok "D3: fixed → clean" || bad "D3" "$out"
echo "D4 the user accepts it"
lint "$debt,$newf"; run_exec >/dev/null
(cd "$P" && LINT_JSON="$WORK/lint.json" REASON="accepted in chat" bash bin/lint-gate.sh --update-baseline --reason "accepted in chat" >/dev/null 2>&1)
out=$(run_exec)
printf '%s' "$out" | grep -q 'RESULT 0|' && ok "D4: accepted into the baseline → clean" || bad "D4" "$out"
echo "D5 metrics ledger"
(cd "$P" && bash bin/metrics-ledger.sh exec --script a.mdl --gate pass --result "⚠️ applied, LINT ROSE" --elapsed 5 --lint-rc 1 >/dev/null 2>&1)
tail -1 "$P/.claude/loop/metrics-ledger.tsv" 2>/dev/null | grep -q 'applied-lint-rose' \
  && ok "D5: a rose exec's status lands as applied-lint-rose" || bad "D5" "$(tail -2 "$P/.claude/loop/metrics-ledger.tsv" 2>/dev/null)"

echo "D6 the per-script diff cannot run"
lint "$debt,$(f MPR002 "empty flow" Empty_Flow)"
out=$(run_exec env PY=/bin/false)
printf '%s' "$out" | grep -q 'RESULT 1|lint rose' && ok "D6: no diff → still a rise (rc 1), not a silent pass" || bad "D6: silent pass" "$out"
echo "D7 a rise, but lint-last.json is gone when the diff runs"
lint "$debt,$(f MPR003 "bad name" Bad_Name)"
printf '#!/bin/sh\nrm -f "%s/.claude/loop/lint-last.json"\nexec "%s" "$@"\n' "$P" "$PY" > "$WORK/py-nolast"; chmod +x "$WORK/py-nolast"
rm -f "$P/.claude/loop/lint-prev-exec.json"
out=$(run_exec env PY="$WORK/py-nolast")
{ printf '%s' "$out" | grep -q 'RESULT 1|lint rose' && ! printf '%s' "$out" | grep -q '0 new this script'; } \
  && ok "D7: unreadable lint-last.json → still a rise (rc 1), never '0 new'" || bad "D7: downgraded to 0 new" "$out"
echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
