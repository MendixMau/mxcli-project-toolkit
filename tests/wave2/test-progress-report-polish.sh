#!/usr/bin/env bash
# test-progress-report-polish.sh: pin three polish fixes to the progress report, on invented demo projects.
#
#   P1  a build-plan.md row whose State is "done <date>" counts as built everywhere: the Stage 5 card
#       ("N of M rows built"), the plan header ("N built"), the phase badge and the per-phase count agree, and
#       nothing is reported as a State cell the page cannot read. "not built" is still checked first.
#   P2  a gate-check placeholder failure on a stage AFTER the current one reads PENDING, not FAIL; the same failure
#       on the current stage stays FAIL.
#   P2b only a placeholder FAIL is relabelled: a real FAIL on a later stage stays FAIL, and every FAIL stays FAIL
#       when the current stage cannot be read from PROJECT.md.
#   P5  every State the build-plan skill lists (built / partial / not built / blocked) and the spellings the card
#       counts (complete, verified, in progress, ...) are read the same way by the card, the plan header and the
#       phase badge; a genuinely unreadable value is still reported as unreadable.
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
has "$R" "<b class=st-built>2 built</b>, <b class=st-progress>0 partial</b>, <b class=st-todo>1 not built</b>" "plan header agrees: 2 built, 1 not built"
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

echo "P2b only placeholder FAILs relabel; unknown current stage keeps FAIL"
P2B="$WORK/p2b"; mkproj "$P2B" "**Stage P - Kickoff**, in progress - gates passed: none"
cat > "$P2B/index.html" <<'HTML'
<table>
<tr><td>P</td><td>Kickoff</td><td>FAIL</td><td>'Confirmed by:' still holds the shipped placeholder: "[user] on [date]"</td></tr>
<tr><td>0</td><td>Triage</td><td>FAIL</td><td>decision table has no rows</td></tr>
<tr><td>1</td><td>Intake</td><td>FAIL</td><td>'Confirmed by:' still holds the shipped placeholder: "[user] on [date]"</td></tr>
</table>
HTML
CLAUDE_CONFIG_DIR="$EMPTY" bash "$SCRIPT" "$P2B" --html >/dev/null 2>&1
stage_line() {  # report stage -> status word shown on the gate-check line
  "$PY" - "$1" "$2" <<'PY'
import re, sys
h = open(sys.argv[1], encoding="utf-8").read()
i = h.index("id='stage-%s'" % sys.argv[2]); j = h.find("class='card stage", i + 10)
print(re.search(r"Gate-check page: <b>(\w+)</b>", h[i:j if j > 0 else len(h)]).group(1))
PY
}
R2B="$P2B/architecture/progress-report.html"
[ "$(stage_line "$R2B" 0)" = FAIL ] && ok "non-placeholder FAIL on a later stage stays FAIL" || bad "non-placeholder FAIL on a later stage stays FAIL"
[ "$(stage_line "$R2B" 1)" = PENDING ] && ok "placeholder FAIL on a later stage still reads PENDING" || bad "placeholder FAIL on a later stage still reads PENDING"
P2C="$WORK/p2c"; mkdir -p "$P2C/architecture"; printf '# PROJECT.md\n\nno stage line here\n' > "$P2C/PROJECT.md"
cp "$P2/index.html" "$P2C/index.html"
CLAUDE_CONFIG_DIR="$EMPTY" bash "$SCRIPT" "$P2C" --html >/dev/null 2>&1
R2C="$P2C/architecture/progress-report.html"
[ "$(stage_line "$R2C" 0)" = FAIL ] && ok "unknown current stage: placeholder FAIL stays FAIL" || bad "unknown current stage: placeholder FAIL stays FAIL"

echo "P5 every listed State is read the same by card, plan header and phase badge"
P5="$WORK/p5"; mkproj "$P5" "**Stage 5 - Build**, in progress - gates passed: P, 0, 1, 2, 3, 4"
cat > "$P5/architecture/build-plan.md" <<'MD'
# Build plan

### Phase 1 - Alpha

| # | Kind | Step | Produces | Depends on | State |
|---|---|---|---|---|---|
| 1 | BUILD | one | 01-a.mdl | - | built |
| 2 | BUILD | two | 02-a.mdl | 1 | complete |
| 3 | BUILD | three | 03-a.mdl | 2 | verified |

### Phase 2 - Beta

| # | Kind | Step | Produces | Depends on | State |
|---|---|---|---|---|---|
| 4 | BUILD | four | 04-b.mdl | - | partial |
| 5 | BUILD | five | 05-b.mdl | 4 | blocked |
| 6 | BUILD | six | 06-b.mdl | 4 | not built |

### Phase 3 - Gamma

| # | Kind | Step | Produces | Depends on | State |
|---|---|---|---|---|---|
| 7 | BUILD | seven | 07-c.mdl | - | blocked (waiting on an answer) |
| 8 | BUILD | eight | 08-c.mdl | - | not built |
MD
CLAUDE_CONFIG_DIR="$EMPTY" bash "$SCRIPT" "$P5" --html >/dev/null 2>&1
R5="$P5/architecture/progress-report.html"
has "$R5" "3 of 8 rows built, 1 partial" "card: 3 of 8 built, 1 partial"
has "$R5" "<b class=st-built>3 built</b>, <b class=st-progress>1 partial</b>, <b class=st-todo>4 not built</b> (2 of them blocked)" "plan header: 3 built, 1 partial, 4 not built of which 2 blocked"
hasnt "$R5" "cannot read" "no listed State is called unreadable"
hasnt "$R5" 'st-unknown">unknown' "no phase is labelled unknown"
has "$R5" 'st-built">built</span>' "Phase 1 badge: built"
has "$R5" 'st-progress">in progress</span>' "Phase 2 badge: in progress"
has "$R5" 'st-todo">not built</span>' "Phase 3 badge: not built (blocked counts as not built)"
has "$R5" "3 of 3 rows built" "Phase 1 shows 3 of 3 built"
sed 's/| not built |$/| whenever it suits |/' "$P5/architecture/build-plan.md" > "$P5/architecture/bp2.md" && mv "$P5/architecture/bp2.md" "$P5/architecture/build-plan.md"
CLAUDE_CONFIG_DIR="$EMPTY" bash "$SCRIPT" "$P5" --html >/dev/null 2>&1
has "$R5" "2 with a State cell this page cannot read" "a genuinely unreadable State is still reported as unreadable"

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
