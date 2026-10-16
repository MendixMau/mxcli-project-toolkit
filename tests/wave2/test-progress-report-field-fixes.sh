#!/usr/bin/env bash
# test-progress-report-field-fixes.sh: pin the field-test fixes to project-bin/progress-report.py found on two real
# projects. Every name, path and number below is invented. The generator is run directly with --out outside the project.
#
#   F1  one source of truth for stage state: PROJECT.md (stage line + sign-off rows) beats a stale gate-check page;
#       the card says "Gate-check page is N ... old, re-run gate-check"; "6 of 8" agrees with the list P,0,1,2,3,4
#       (the "· manual: 5" tail of the stage line must not swallow the last stage).
#   F2  the progress report never lists itself as a stage artifact (not even when --out is outside the project).
#   F3  a build-plan.json older than build-plan.md is not trusted: rows are counted from the md State column by prefix
#       ("not built" is not built, "built (...)" and "done ..." are built, "partial" is partial) and the page says so.
#   F4  no log in the project's own slug: found in another slug by path mention (5 or more) and clipped to the stretch
#       that mentions it; a session whose cwd is elsewhere and that never mentions the project is ignored. With no log at
#       all the time ledger and BUILD-LOG feed the page, labelled, and the banner says how to pass --session-log.
#   F5  stage boundaries use the same truth: log events after the Stage 4 sign-off count toward Stage 5 even when the
#       gate-check page is stale.
#   F6  Build progress: stacked phase bars, headline "N of M rows built, K partial", the phase being built now is marked,
#       last build step with time ago; the section is linked from the Stage 5 card; the report itself is never linked.
#
# Usage: bash tests/wave2/test-progress-report-field-fixes.sh

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GEN="$ROOT/project-bin/progress-report.py"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/pr-fixes.XXXXXX")"
trap '[ -n "${KEEP:-}" ] || rm -rf "$WORK"' EXIT
# shellcheck disable=SC1091
. "$ROOT/bin/lib/portable.sh"
PY="$(resolve_py 2>/dev/null || true)"
if [ -z "$PY" ]; then echo "SKIP: no Python 3 found"; echo "PASS=0 FAIL=0"; exit 0; fi
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }
has() { grep -q -- "$2" "$1" && ok "$3" || bad "$3"; }
hasnt() { grep -q -- "$2" "$1" && bad "$3" || ok "$3"; }

# A project whose gate-check page and plan JSON are stale, and whose PROJECT.md says stage 4 passed (signed off at a
# known time). Prints the sign-off epoch.
mkproj() {  # dir
  "$PY" - "$1" <<'PYEOF'
import os, sys, time, datetime
d = sys.argv[1]
for sub in ("architecture", "docs", "docs/progress", ".claude/loop", "analysis"): os.makedirs(os.path.join(d, sub), exist_ok=True)
open(os.path.join(d, "PROJECT.md"), "w").write("""# PROJECT.md

## Current stage

**Stage 5 - Build**, in progress - gates passed: P, 0, 1, 2, 3, 4 · manual: 5 (derived by gate-check)

Entry mode: requirements-driven

## Decisions

| Stage | Decision | Status | Notes |
|---|---|---|---|
| 3 | Stage 3 sign-off: architecture | CONFIRMED 2026-10-09 | ok |
| 4 | Stage 4 sign-off: build plan | CONFIRMED 2026-10-10 12:00 | ok |

## Notes
""")
rows = "".join("<tr><td>%s</td><td>t</td><td>%s</td><td>detail</td></tr>" % (s, st) for s, st in (("P", "PASS"), ("0", "PASS"), ("1", "PASS"), ("2", "PASS"), ("3", "PASS"), ("4", "PENDING")))
open(os.path.join(d, "index.html"), "w").write("<table>%s</table>" % rows)
open(os.path.join(d, "architecture", "build-plan.json"), "w").write('{"schema":1,"generatedAt":"2026-10-01T00:00:00Z","phases":[{"id":"1","name":"Orders","steps":[{"number":"1","kind":"BUILD","step":"a","state":"not built"},{"number":"2","kind":"BUILD","step":"b","state":"not built"}]}]}')
open(os.path.join(d, "architecture", "build-plan.md"), "w").write("""# Build plan

### Phase 1 - Orders

| # | Kind | Step | State |
|---|---|---|---|
| 1 | BRIEF | brief | built |
| 2 | BUILD | order entity | built (2026-10-12; mxbuild clean) |
| 3 | BUILD | order page | partial (page missing a column) |
| 4 | PROVE | tests | not built |

### Phase 2 - Billing

| # | Kind | Step | State |
|---|---|---|---|
| 5 | BUILD | invoice | not built |
| 6 | BUILD | credit note | done 2026-10-12 |
| 7 | BUILD | reminders | not built (waits for Q-3) |
""")
open(os.path.join(d, "docs", "BUILD-LOG.md"), "w").write("""| when | script | gate | result | detail |
|---|---|---|---|---|
| 2026-10-12T10:00:00+0000 | `01-orders.mdl` | pass | applied | ok |
| 2026-10-12T10:02:00+0000 | `02-billing.mdl` | pass | applied | ok |
""")
open(os.path.join(d, "docs", "progress", "TIME-LEDGER.md"), "w").write("""# Build time

| Phase | Start | Minutes | Subagent tokens | Exec runs | Notes |
|---|---|---|---|---|---|
| 1 orders | 2026-10-12 10:00 | 55 | 136k | ~25 | x |
""")
old = time.time() - 3 * 86400
for f in ("index.html", "architecture/build-plan.json"): os.utime(os.path.join(d, f), (old, old))
PYEOF
}

# Session log in another folder's slug (cwd elsewhere). $3 = how many times to mention the project path.
mklog() {  # configdir projdir mentions
  local slug="-tmp-elsewhere"
  mkdir -p "$1/projects/$slug"
  "$PY" - "$1/projects/$slug/s1.jsonl" "$2" "$3" <<'PYEOF'
import json, sys, datetime
out, proj, mentions = sys.argv[1], sys.argv[2], int(sys.argv[3])
so = datetime.datetime(2026, 10, 10, 12, 0).timestamp()
rows = []; n = [0]
def iso(t): return datetime.datetime.fromtimestamp(t, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
def asst(t, cmd=None, tin=5000):
    n[0] += 1
    blk = [{"type": "tool_use", "id": "t%d" % n[0], "name": "Bash", "input": {"command": cmd}}] if cmd else [{"type": "text", "text": "x"}]
    rows.append({"type": "assistant", "timestamp": iso(t), "cwd": "/tmp/elsewhere", "uuid": "a%d" % n[0], "message": {"id": "m%d" % n[0], "model": "claude-sonnet-5-5", "role": "assistant", "content": blk,
                 "usage": {"input_tokens": tin, "output_tokens": 500, "cache_read_input_tokens": 1000, "cache_creation_input_tokens": 100}}})
# before the sign-off: Stage 4 work; after it: build work (exec.sh); one event far away that the clip must drop
for k in range(mentions):
    t = so - 1500 + k * 600
    asst(t, "ls %s/architecture" % proj if mentions else None, tin=5000 + k)
import os
asst(so - 600, ("ls %s" % proj) if os.environ.get("NOEARLY") else ("bash %s/bin/exec.sh 01" % proj))
asst(so + 300, "bash exec.sh 02"); asst(so + 900, "bash exec.sh 03")
asst(so + 3 * 86400, "ls")
open(out, "w").write("".join(json.dumps(r) + "\n" for r in rows))
PYEOF
}

# Text of one stage card from the page (everything between its id and the next card).
card() {  # file stage
  "$PY" - "$1" "$2" <<'PYEOF'
import re, sys
h = open(sys.argv[1], encoding="utf-8").read(); i = h.index("id='stage-%s'" % sys.argv[2]); j = h.find("class='card stage", i + 10)
print(re.sub(r"<[^>]+>", " ", h[i:j if j > 0 else i + 6000]))
PYEOF
}

echo "F1 PROJECT.md wins over a stale gate-check page"
P1="$WORK/proj1"; mkproj "$P1"; EMPTY="$WORK/emptycfg"; mkdir -p "$EMPTY/projects"
OUT1="$WORK/out1/report.html"
CLAUDE_CONFIG_DIR="$EMPTY" "$PY" "$GEN" "$P1" --out "$OUT1" >/dev/null 2>&1
[ -f "$OUT1" ] && ok "page written with --out outside the project" || bad "page written with --out outside the project"
has "$OUT1" "6 of 8 gates passed" "counter is 6 of 8, as many as the passed list P,0,1,2,3,4"
card "$OUT1" 4 | grep -q "passed" && ok "Stage 4 card says passed" || bad "Stage 4 card says passed"
card "$OUT1" 4 | grep -qE "Gate-check page is [0-9]+ (days|hours) old, re-run gate-check" && ok "Stage 4 card carries the amber stale-page note" || bad "Stage 4 card carries the amber stale-page note"
card "$OUT1" 3 | grep -q "re-run gate-check" && bad "a stage the page lists as PASS gets no stale note" || ok "a stage the page lists as PASS gets no stale note"
has "$OUT1" "this page counts P, 0, 1, 2, 3, 4" "the disagreement note names the counted list"

echo "F2 the report never lists itself"
P2="$WORK/proj2"; mkproj "$P2"; : > "$P2/architecture/progress-report.html"
CLAUDE_CONFIG_DIR="$EMPTY" "$PY" "$GEN" "$P2" --out "$WORK/out2/elsewhere.html" >/dev/null 2>&1
hasnt "$WORK/out2/elsewhere.html" "class='chip [^']*' href='[^']*progress-report" "no chip links the report (existing file)"
rm -f "$P2/architecture/progress-report.html"
CLAUDE_CONFIG_DIR="$EMPTY" "$PY" "$GEN" "$P2" --out "$WORK/out2/elsewhere2.html" >/dev/null 2>&1
hasnt "$WORK/out2/elsewhere2.html" "class='chip [^']*' href='[^']*elsewhere2" "no chip links the page being written"

echo "F3 stale plan JSON: counted from build-plan.md"
has "$OUT1" "3 of 7 rows built, 1 partial" "headline: 3 of 7 rows built, 1 partial (built, built (...), done; not built is not built)"
has "$OUT1" "plan JSON was stale, counted from build-plan.md" "the page says the JSON was stale"
hasnt "$OUT1" "0 of 2 rows built" "never the stale JSON's 0 built"
has "$OUT1" "built 3" "legend: built 3"
has "$OUT1" "partial 1" "legend: partial 1"
has "$OUT1" "not built 3" "legend: not built 3 (a 'not built (waits for Q-3)' row stays not built)"
FRESH="$WORK/proj3"; mkproj "$FRESH"; touch "$FRESH/architecture/build-plan.json"
rm -f "$FRESH/docs/BUILD-LOG.md"
CLAUDE_CONFIG_DIR="$EMPTY" "$PY" "$GEN" "$FRESH" --out "$WORK/out3/r.html" >/dev/null 2>&1
has "$WORK/out3/r.html" "0 of 2 rows built" "a JSON newer than the md is used as it is"
hasnt "$WORK/out3/r.html" "plan JSON was stale" "no stale note when the JSON is current"

echo "F4 session log discovery and ledger fallback"
P1R="$(cd "$P1" && pwd -P)"
CFG="$WORK/cfg"; mklog "$CFG" "$P1R" 7
CLAUDE_CONFIG_DIR="$CFG" "$PY" "$GEN" "$P1" --out "$WORK/out4/r.html" >/dev/null 2>&1
has "$WORK/out4/r.html" "found by path mention" "a log in another slug is found by path mention (7 mentions)"
hasnt "$WORK/out4/r.html" "Time, token and cost data from a session log are unavailable" "no unavailable banner when a log is found"
hasnt "$WORK/out4/r.html" "13 Oct" "events three days after the last mention are clipped out"
CFG2="$WORK/cfg2"; mklog "$CFG2" "$P1R" 3
CLAUDE_CONFIG_DIR="$CFG2" "$PY" "$GEN" "$P1" --out "$WORK/out4/r2.html" >/dev/null 2>&1
has "$WORK/out4/r2.html" "Time, token and cost data from a session log are unavailable" "3 mentions is not enough: no log"
has "$WORK/out4/r2.html" "docs/progress/TIME-LEDGER.md" "fallback names the time ledger as its source"
has "$WORK/out4/r2.html" "docs/BUILD-LOG.md" "fallback names BUILD-LOG as its source"
has "$WORK/out4/r2.html" "Time and effort from the project ledgers" "ledger card shown"
has "$WORK/out4/r2.html" "136k" "ledger phase row shown (tokens)"
has "$WORK/out4/r2.html" "session-log &lt;path&gt;" "banner says how to pass --session-log"
CLAUDE_CONFIG_DIR="$CFG2" "$PY" "$GEN" "$P1" --out "$WORK/out4/r3.html" --session-log "$CFG2/projects/-tmp-elsewhere/s1.jsonl" >/dev/null 2>&1
hasnt "$WORK/out4/r3.html" "found by path mention" "--session-log replaces discovery"

echo "F5 Stage 4 to 5 boundary follows PROJECT.md, not the stale gate page"
S5="$(card "$OUT1" 5)"
S5L="$(card "$WORK/out4/r.html" 5)"
printf '%s' "$S5L" | grep -E "New tokens" | grep -qv "none" && ok "Stage 5 shows tokens from the events after the sign-off" || bad "Stage 5 shows tokens from the events after the sign-off"
printf '%s' "$S5L" | grep -E "Wall time" | grep -q "none" && bad "Stage 5 wall time is not none" || ok "Stage 5 wall time is not none"
"$PY" - "$WORK/out4/r.html" <<'PYEOF' && ok "Stage 5 window starts at the first exec.sh (11:50), earlier than the 12:00 sign-off" || bad "Stage 5 window starts at 11:50"
import re, sys
h = open(sys.argv[1], encoding="utf-8").read()
t = re.sub(r"<[^>]+>", " ", h)
m = re.search(r"Stage 5\s+(\d\d:\d\d) to", t)
assert m and m.group(1) == "11:50", "Stage 5 window row: %r" % (m and m.group(1))
PYEOF

CFG3="$WORK/cfg3"; NOEARLY=1 mklog "$CFG3" "$P1R" 7
CLAUDE_CONFIG_DIR="$CFG3" "$PY" "$GEN" "$P1" --out "$WORK/out4/r4.html" >/dev/null 2>&1
"$PY" - "$WORK/out4/r4.html" <<'PYEOF' && ok "no exec.sh before it: Stage 5 starts at the 12:00 sign-off row of PROJECT.md" || bad "Stage 5 starts at the sign-off row"
import re, sys
t = re.sub(r"<[^>]+>", " ", open(sys.argv[1], encoding="utf-8").read())
m = re.search(r"Stage 5\s+(\d\d:\d\d) to", t)
assert m and m.group(1) == "12:00", m and m.group(1)
PYEOF
card "$WORK/out4/r4.html" 5 | grep -E "New tokens" | grep -qv "none" && ok "events after the sign-off count toward Stage 5 (gate page stale)" || bad "events after the sign-off count toward Stage 5"

echo "F6 Build progress"
has "$OUT1" "id=build-detail>Build progress" "section is titled Build progress"
has "$OUT1" "href='#build-detail'" "Stage 5 card links to it"
has "$OUT1" "class='stack3'" "stacked bars"
has "$OUT1" "class='card ph now'" "the phase being built now is marked"
has "$OUT1" "building now" "and says so"
has "$OUT1" "Last build step:" "last build step shown"
has "$OUT1" "ago at" "with how long ago"
hasnt "$OUT1" "href='[^']*progress-report" "the report never links itself"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
