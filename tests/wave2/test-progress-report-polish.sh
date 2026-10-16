#!/usr/bin/env bash
# test-progress-report-polish.sh: pin three polish fixes to the progress report, on invented demo projects.
#
#   P1  a build-plan.md row whose State is "done <date>" counts as built everywhere: the Stage 5 card
#       ("N of M rows built"), the plan header ("N built"), the phase badge and the per-phase count agree, and
#       nothing is reported as a State cell the page cannot read. "not built" is still checked first.
#   P2  a gate-check placeholder failure on a stage AFTER the current one reads PENDING, not FAIL; the same failure
#       on the current stage stays FAIL.
#   P3  no session log: one calm line (not the orange box), the regenerate hint inside "How this was measured";
#       with --no-log the page never claims it looked in folders or logs.
#
# Usage: bash tests/wave2/test-progress-report-polish.sh

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/project-bin/build-plan-status.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/pr-polish.XXXXXX")"
trap '[ -n "${KEEP:-}" ] || rm -rf "$WORK"' EXIT
. "$ROOT/bin/lib/portable.sh"
PY="$(resolve_py 2>/dev/null || true)"
if [ -z "$PY" ]; then echo "SKIP: no Python 3 found"; echo "PASS=0 FAIL=0"; exit 0; fi
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }
has() { grep -q -- "$2" "$1" && ok "$3" || bad "$3"; }
hasnt() { grep -q -- "$2" "$1" && bad "$3" || ok "$3"; }

mkproj() {  # dir stage-line
  mkdir -p "$1/architecture"
  printf '# PROJECT.md\n\n## Current stage\n\n%s\n\nEntry mode: requirements-driven\n\n## Decisions\n\n| Stage | Decision | Status | Notes |\n|---|---|---|---|\n' "$2" > "$1/PROJECT.md"
}

echo "P1 'done <date>' counts as built everywhere"
P1="$WORK/p1"; mkproj "$P1" "**Stage 5 - Build**, in progress - gates passed: P, 0, 1, 2, 3, 4"
cat > "$P1/architecture/build-plan.md" <<'MD'
# Build plan

### Phase 1 - Orders

| # | Kind | Step | Produces | Depends on | State |
|---|---|---|---|---|---|
| 1 | BUILD | orders domain | 01-orders.mdl | - | built (2026-10-01) |

### Phase 2 - Billing

| # | Kind | Step | Produces | Depends on | State |
|---|---|---|---|---|---|
| 2 | BUILD | billing domain | 02-billing.mdl | 1 | done 2026-10-12 |
| 3 | BUILD | invoice page | 03-invoice.mdl | 2 | not built |
MD
EMPTY="$WORK/cfg"; mkdir -p "$EMPTY/projects"
CLAUDE_CONFIG_DIR="$EMPTY" bash "$SCRIPT" "$P1" --html >/dev/null 2>&1
R="$P1/architecture/progress-report.html"
[ -f "$R" ] && ok "report written" || bad "report written"
has "$R" "2 of 3 rows built" "Stage 5 card counts the done row as built (2 of 3)"
has "$R" "<b class=st-built>2 built</b>, <b class=st-todo>1 not built</b>" "plan header agrees: 2 built, 1 not built"
hasnt "$R" "cannot read" "no State cell is called unreadable"
has "$R" "1 of 2 rows built" "Phase 2 shows 1 of 2 built"
hasnt "$R" 'st-unknown">unknown' "no phase is labelled unknown"

echo "P2 placeholder failure on a later stage is pending"
P2="$WORK/p2"; mkproj "$P2" "**Stage P - Kickoff**, in progress - gates passed: none"
cat > "$P2/index.html" <<'HTML'
<table>
<tr><td>P</td><td>Kickoff</td><td>FAIL</td><td>'Confirmed by:' still holds the shipped placeholder: "[user] on [date]"</td></tr>
<tr><td>0</td><td>Triage</td><td>FAIL</td><td>'Confirmed by:' still holds the shipped placeholder: "[user] on [date]"</td></tr>
</table>
HTML
CLAUDE_CONFIG_DIR="$EMPTY" bash "$SCRIPT" "$P2" --html >/dev/null 2>&1
R2="$P2/architecture/progress-report.html"
"$PY" - "$R2" <<'PY' && ok "stage 0 (later) reads PENDING, stage P (current) stays FAIL" || bad "stage 0 (later) reads PENDING, stage P (current) stays FAIL"
import re, sys
h = open(sys.argv[1], encoding="utf-8").read()
def line(s):
    i = h.index("id='stage-%s'" % s); j = h.find("class='card stage", i + 10)
    m = re.search(r"Gate-check page: <b>(\w+)</b>", h[i:j if j > 0 else len(h)]); return m.group(1)
assert line("0") == "PENDING", line("0")
assert line("P") == "FAIL", line("P")
PY

echo "P3 no-log line is calm and honest"
has "$R" "class=nolog" "one calm line"
hasnt "$R" "class='card note-card'" "no big banner box"
hasnt "$R" "Time, token and cost data from a session log are unavailable" "old banner text is gone"
"$PY" - "$R" <<'PY' && ok "hint sits inside the collapsed How this was measured block, line is outside it" || bad "hint sits inside the collapsed How this was measured block, line is outside it"
import re, sys
h = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"<details class=how id=how>.*?</details>", h, re.S); assert m
assert "No session log" in m.group(0)
assert "class=nolog" not in m.group(0)
PY
P4="$WORK/p4"; mkproj "$P4" "**Stage P - Kickoff**, in progress - gates passed: none"
R4="$WORK/r4.html"; "$PY" "$ROOT/project-bin/progress-report.py" "$P4" --no-log --out "$R4" >/dev/null 2>&1
has "$R4" "class=nolog" "--no-log: the calm line is shown"
has "$R4" "Session logs were not read" "--no-log says the logs were not read"
hasnt "$R4" "Looked in" "--no-log never claims it looked in folders"
hasnt "$R4" "then regenerate: <code>project-bin" "--no-log gives no regenerate hint for a log it never read"
P3="$WORK/p3"; mkproj "$P3" "**Stage P - Kickoff**, in progress - gates passed: none"
CLAUDE_CONFIG_DIR="$EMPTY" bash "$SCRIPT" "$P3" --html >/dev/null 2>&1
R3="$P3/architecture/progress-report.html"
has "$R3" "class=nolog" "without --no-log the calm line is also shown"
has "$R3" "Looked in" "without --no-log the looked-in counts live inside the details"
has "$R3" "then regenerate: <code>project-bin/build-plan-status.sh" "regenerate hint present inside the details"

echo "P4 test-moments wording (the table is defined in the generator)"
GENPY="$ROOT/project-bin/progress-report.py"
has "$GENPY" "per-flow unit tests chosen at CAC-5" "unit tests run for the flows chosen at CAC-5"
hasnt "$GENPY" "switched on" "the old 'switched on' wording is gone"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
