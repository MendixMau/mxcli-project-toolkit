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
#   F4  no log in the project's own slug: found in another slug when 25% of its tool calls and at least 20 operate on the
#       project path, counted only between those calls; a session that merely mentions the project is ignored. With no log at
#       all the time ledger and BUILD-LOG feed the page, labelled, and the banner says how to pass --session-log.
#   F5  stage boundaries use the same truth: log events after the Stage 4 sign-off count toward Stage 5 even when the
#       gate-check page is stale.
#   F6  Build progress: stacked phase bars, headline "N of M rows built, K partial", the phase being built now is marked,
#       last build step with time ago; the section is linked from the Stage 5 card; the report itself is never linked.
#   F7  "building now" is the phase of the last build step (folder, script name, else highest active phase).
#   F8  discovery counts tool calls on the project (25% and 20), never text mentions; progress-report.py sessions out.
#   F9  a date-only Stage 4 sign-off puts the switch at the first build activity on or after the date, marked inferred.
#   F10 an existing-project fixture: the metrics ledger (UTC) is the primary source of build activity, with no session log.
#   F11 a project set up by an older toolkit and updated with bin/sync-project.sh renders and leaves build-plan.html alone.
#   F12 the Stage 4 to 5 switch is one function: the windows table, the chart band and the sub-agent tables agree, and a
#       sub-agent that names a plan phase and starts within 30 minutes before it counts to Stage 5.
#   F15 the discovery cache records the project's real path and the attribution rules: a copied project, or a changed
#       threshold, reads it as cold; the copy does not list the original's sessions.
#   F16 files skipped by the 300-file cap are recorded as "no": a cached run never reads more files than the uncached one.
#   F17 with exec log rows the Stage 4 to 5 switch follows the log; an earlier exec.sh call in the session log is ignored.
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

# Session log in another folder's slug (cwd elsewhere). $3 = tool calls that operate on the project (Read of a file
# under it); env FILL = other tool calls on something else interleaved with them, TEXT = assistant text messages that
# only mention the path, REPORTRUN = a call that runs progress-report.py. All times are around the 12:00 sign-off.
mklog() {  # configdir projdir touching [sessionname]
  local slug="-tmp-elsewhere"
  mkdir -p "$1/projects/$slug"
  "$PY" - "$1/projects/$slug/${4:-s1}.jsonl" "$2" "$3" <<'PYEOF2'
import json, os, sys, datetime
out, proj, touching = sys.argv[1], sys.argv[2], int(sys.argv[3])
so = datetime.datetime(2026, 10, 10, 12, 0).timestamp()
rows = []; n = [0]
def iso(t): return datetime.datetime.fromtimestamp(t, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
def asst(t, name=None, inp=None, text=None, tin=5000):
    n[0] += 1
    blk = [{"type": "tool_use", "id": "t%d" % n[0], "name": name, "input": inp}] if name else [{"type": "text", "text": text or "x"}]
    rows.append({"type": "assistant", "timestamp": iso(t), "cwd": "/tmp/elsewhere", "uuid": "a%d" % n[0], "message": {"id": "m%d" % n[0], "model": "claude-sonnet-5-5", "role": "assistant", "content": blk,
                 "usage": {"input_tokens": tin, "output_tokens": 500, "cache_read_input_tokens": 1000, "cache_creation_input_tokens": 100}}})
fill = int(os.environ.get("FILL", "0")); total = touching
for k in range(touching):
    t = so - 2400 + k * 50
    asst(t, "Read", {"file_path": "%s/architecture/f%d.md" % (proj, k)}, tin=5000 + k)
    for j in range(fill // max(1, touching) + (1 if k < fill % max(1, touching) else 0)):
        asst(t + 10 + j, "Bash", {"command": "ls /tmp"})
for k in range(int(os.environ.get("TEXT", "0"))):
    asst(so - 2400 + k * 20, text="the project at %s/architecture is described in" % proj)
if os.environ.get("REPORTRUN"): asst(so - 100, "Bash", {"command": "%s/project-bin/progress-report.py %s" % (proj, proj)})
asst(so - 600, "Bash", {"command": ("ls %s" % proj) if os.environ.get("NOEARLY") else ("bash %s/bin/exec.sh 01" % proj)})
asst(so + 300, "Bash", {"command": "cd %s && bash exec.sh 02" % proj}); asst(so + 900, "Bash", {"command": "cd %s && bash exec.sh 03" % proj})
asst(so + 3 * 86400, "Bash", {"command": "ls"})
open(out, "w").write("".join(json.dumps(r, separators=(",", ":")) + "\n" for r in rows))
PYEOF2
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
CFG="$WORK/cfg"; mklog "$CFG" "$P1R" 25
CLAUDE_CONFIG_DIR="$CFG" "$PY" "$GEN" "$P1" --out "$WORK/out4/r.html" >/dev/null 2>&1
has "$WORK/out4/r.html" "Sessions from other folders (1)" "a log in another slug qualifies by tool calls on the project (28 of 28)"
hasnt "$WORK/out4/r.html" "Time, token and cost data from a session log are unavailable" "no unavailable banner when a log is found"
hasnt "$WORK/out4/r.html" "13 Oct" "events three days after the last mention are clipped out"
CFG2="$WORK/cfg2"; mklog "$CFG2" "$P1R" 10
CLAUDE_CONFIG_DIR="$CFG2" "$PY" "$GEN" "$P1" --out "$WORK/out4/r2.html" >/dev/null 2>&1
has "$WORK/out4/r2.html" "Time, token and cost data from a session log are unavailable" "13 tool calls on the project are not enough (20 needed): no log"
has "$WORK/out4/r2.html" "docs/progress/TIME-LEDGER.md" "fallback names the time ledger as its source"
has "$WORK/out4/r2.html" "docs/BUILD-LOG.md" "fallback names BUILD-LOG as its source"
has "$WORK/out4/r2.html" "Time and effort from the project ledgers" "ledger card shown"
has "$WORK/out4/r2.html" "136k" "ledger phase row shown (tokens)"
has "$WORK/out4/r2.html" "session-log &lt;path&gt;" "banner says how to pass --session-log"
CLAUDE_CONFIG_DIR="$CFG2" "$PY" "$GEN" "$P1" --out "$WORK/out4/r3.html" --session-log "$CFG2/projects/-tmp-elsewhere/s1.jsonl" >/dev/null 2>&1
hasnt "$WORK/out4/r3.html" "Sessions from other folders" "--session-log replaces discovery"

echo "F5 Stage 4 to 5 boundary follows PROJECT.md, not the stale gate page"
S5="$(card "$OUT1" 5)"
S5L="$(card "$WORK/out4/r.html" 5)"
printf '%s' "$S5L" | grep -E "New tokens" | grep -qv "none" && ok "Stage 5 shows tokens from the events after the sign-off" || bad "Stage 5 shows tokens from the events after the sign-off"
printf '%s' "$S5L" | grep -E "Wall time" | grep -q "none" && bad "Stage 5 wall time is not none" || ok "Stage 5 wall time is not none"
"$PY" - "$WORK/out4/r.html" <<'PYEOF' && ok "ledger rows exist: the session's exec.sh at 11:50 is ignored, Stage 5 starts at the timed 12:00 sign-off" || bad "Stage 5 window starts at 12:00, not 11:50"
import re, sys
h = open(sys.argv[1], encoding="utf-8").read()
t = re.sub(r"<[^>]+>", " ", h)
m = re.search(r"Stage 5\s+(\d\d:\d\d) to", t)
assert m and m.group(1) == "12:00", "Stage 5 window row: %r" % (m and m.group(1))
PYEOF

CFG3="$WORK/cfg3"; NOEARLY=1 mklog "$CFG3" "$P1R" 25
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

echo "F7 building now = the phase the last build step belongs to"
has "$OUT1" "class='card ph now' id='phase-2'" "last step 02-billing.mdl: Phase 2 (Billing) is marked, although Phase 1 has the partial row"
has "$OUT1" "class='card ph' id='phase-1'" "the earlier phase with a partial row is not marked now"
P7="$WORK/proj7"; mkproj "$P7"
printf '%s\n' '| 2026-10-12T10:09:00+0000 | `01-orders-fixes.mdl` | pass | applied | ok |' '| 2026-10-12T10:10:00+0000 | `05-billing.mdl` | pass | blocked | stop |' >> "$P7/docs/BUILD-LOG.md"
CLAUDE_CONFIG_DIR="$EMPTY" "$PY" "$GEN" "$P7" --out "$WORK/out7/r.html" >/dev/null 2>&1
has "$WORK/out7/r.html" "class='card ph now' id='phase-1'" "script name matched to the plan phase name (orders), a later blocked step does not count"
P7B="$WORK/proj7b"; mkproj "$P7B"
printf '%s\n' '| 2026-10-12T10:09:00+0000 | `apps/x/mdlsource/2-whatever/04.mdl` | pass | applied | ok |' >> "$P7B/docs/BUILD-LOG.md"
CLAUDE_CONFIG_DIR="$EMPTY" "$PY" "$GEN" "$P7B" --out "$WORK/out7/b.html" >/dev/null 2>&1
has "$WORK/out7/b.html" "class='card ph now' id='phase-2'" "mdlsource/2-whatever/ folder number picks Phase 2"
P7C="$WORK/proj7c"; mkproj "$P7C"
printf '%s\n' '| 2026-10-12T10:09:00+0000 | `99.mdl` | pass | applied | ok |' >> "$P7C/docs/BUILD-LOG.md"
CLAUDE_CONFIG_DIR="$EMPTY" "$PY" "$GEN" "$P7C" --out "$WORK/out7/c.html" >/dev/null 2>&1
has "$WORK/out7/c.html" "class='card ph now' id='phase-2'" "no match: the highest phase with a built or partial row"

echo "F8 discovery counts tool calls on the project, not mentions"
cnt() { grep -c "$2" "$1"; }
CFG8="$WORK/cfg8"; mklog "$CFG8" "$P1R" 25
CLAUDE_CONFIG_DIR="$CFG8" "$PY" "$GEN" "$P1" --out "$WORK/out8/a.html" >/dev/null 2>&1
has "$WORK/out8/a.html" "<summary>How this was measured</summary>" "the sessions used are listed in one collapsed How this was measured block"
has "$WORK/out8/a.html" "<code>s1</code></td><td>2026-10-10</td><td class=n>100%</td>" "list row: short id, date, share of tool calls on the project"
CFG8B="$WORK/cfg8b"; FILL=150 mklog "$CFG8B" "$P1R" 25
CLAUDE_CONFIG_DIR="$CFG8B" "$PY" "$GEN" "$P1" --out "$WORK/out8/b.html" >/dev/null 2>&1
has "$WORK/out8/b.html" "Time, token and cost data from a session log are unavailable" "28 of 178 calls (16%) is under the 25% share: not used"
CFG8C="$WORK/cfg8c"; TEXT=60 mklog "$CFG8C" "$P1R" 10
CLAUDE_CONFIG_DIR="$CFG8C" "$PY" "$GEN" "$P1" --out "$WORK/out8/c.html" >/dev/null 2>&1
has "$WORK/out8/c.html" "Time, token and cost data from a session log are unavailable" "60 text mentions do not attribute a session"
CFG8D="$WORK/cfg8d"; REPORTRUN=1 mklog "$CFG8D" "$P1R" 25
CLAUDE_CONFIG_DIR="$CFG8D" "$PY" "$GEN" "$P1" --out "$WORK/out8/d.html" >/dev/null 2>&1
has "$WORK/out8/d.html" "Time, token and cost data from a session log are unavailable" "a session that runs progress-report.py is excluded"
CFG8E="$WORK/cfg8e"; mklog "$CFG8E" "$P1R" 25 s1; FILL=100 mklog "$CFG8E" "$P1R" 25 s2
CLAUDE_CONFIG_DIR="$CFG8E" "$PY" "$GEN" "$P1" --out "$WORK/out8/e.html" >/dev/null 2>&1
has "$WORK/out8/e.html" "<code>s1</code>" "two sessions: the qualifying one is listed"
hasnt "$WORK/out8/e.html" "<code>s2</code>" "the other (28 of 128 calls, 22%) is not listed"

echo "F9 date-only sign-off: switch is the first build activity on or after the date"
P9="$WORK/proj9"; mkproj "$P9"; rm -f "$P9/docs/BUILD-LOG.md" "$P9/docs/progress/TIME-LEDGER.md"
sed -i.bak 's/CONFIRMED 2026-10-10 12:00/CONFIRMED (delegated) 2026-10-10/' "$P9/PROJECT.md"; rm -f "$P9/PROJECT.md.bak"
P9R="$(cd "$P9" && pwd -P)"; CFG9="$WORK/cfg9"; mkdir -p "$CFG9/projects/-tmp-elsewhere"
"$PY" - "$CFG9/projects/-tmp-elsewhere/s9.jsonl" "$P9R" <<'PYEOF3'
import json, sys, datetime
out, proj = sys.argv[1], sys.argv[2]
rows = []; n = [0]
def at(d, h, m): return datetime.datetime(2026, 10, d, h, m).timestamp()
def iso(t): return datetime.datetime.fromtimestamp(t, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
def call(t, name, inp):
    n[0] += 1
    rows.append({"type": "assistant", "timestamp": iso(t), "cwd": "/tmp/elsewhere", "uuid": "a%d" % n[0], "message": {"id": "m%d" % n[0], "model": "claude-sonnet-5-5", "role": "assistant",
      "content": [{"type": "tool_use", "id": "t%d" % n[0], "name": name, "input": inp}], "usage": {"input_tokens": 4000, "output_tokens": 300, "cache_read_input_tokens": 500, "cache_creation_input_tokens": 50}}})
for k in range(15): call(at(9, 20, 0) + k * 60, "Read", {"file_path": proj + "/architecture/p%d.md" % k})    # evening before: planning
call(at(9, 23, 0), "Bash", {"command": "cd %s && bash exec.sh 00" % proj})                                   # exec.sh BEFORE the date: ignored
for k in range(12): call(at(10, 8, 0) + k * 120, "Read", {"file_path": proj + "/docs/q%d.md" % k})          # that day, planning
call(at(10, 9, 20), "Write", {"file_path": proj + "/mdlsource/1/01-orders.mdl", "content": "x"})              # first build activity on the date
call(at(10, 9, 30), "Bash", {"command": "cd %s && bash exec.sh 01" % proj})
for k in range(5): call(at(10, 9, 40) + k * 60, "Read", {"file_path": proj + "/docs/r%d.md" % k})
open(out, "w").write("".join(json.dumps(r, separators=(",", ":")) + "\n" for r in rows))
PYEOF3
CLAUDE_CONFIG_DIR="$CFG9" "$PY" "$GEN" "$P9" --out "$WORK/out9/r.html" >/dev/null 2>&1
"$PY" - "$WORK/out9/r.html" <<'PYEOF4' && ok "Stage 5 starts at 09:20 (first mdlsource write on the date), not midnight and not the earlier exec.sh" || bad "Stage 5 starts at 09:20"
import re, sys
t = re.sub(r"<[^>]+>", " ", open(sys.argv[1], encoding="utf-8").read())
m = re.search(r"Stage 5\s+(\d\d:\d\d) to", t)
assert m and m.group(1) == "09:20", m and m.group(1)
PYEOF4
has "$WORK/out9/r.html" "Stage switch inferred" "the collapsed block notes the switch is inferred"
hasnt "$OUT1" "Stage switch inferred" "no inferred note when the sign-off row has a time"
hasnt "$WORK/out4/r.html" "Stage switch inferred" "no inferred note with a timed row (log)"

echo "F10 an existing project: exec log (metrics ledger) is the primary source for build activity"
# Neutral names. Stale plan JSON, PROJECT.md newer than the gate page, a date-only sign-off, BRDs in the usual folder, no
# session log, and a metrics ledger in UTC across two phases with a failed, a restored and a blocked run.
P10="$WORK/proj10"; mkproj "$P10"
rm -f "$P10/docs/BUILD-LOG.md" "$P10/docs/progress/TIME-LEDGER.md"
sed -i.bak 's/CONFIRMED 2026-10-10 12:00/CONFIRMED (delegated) 2026-10-10/' "$P10/PROJECT.md"; rm -f "$P10/PROJECT.md.bak"
mkdir -p "$P10/analysis/knowledge-base/brd"; printf '# BRD-01 Orders\n' > "$P10/analysis/knowledge-base/brd/BRD-01-orders.md"; printf '# BRD-02 Billing\n' > "$P10/analysis/knowledge-base/brd/BRD-02-billing.md"
printf '%s\n' \
 'ts	script	gate	result	elapsed_s	mxbuild_errors	lint_rc	lint_total	restored	score	security	quality	architecture	performance	naming	design	other	violations	model_commit' \
 '2026-10-08T10:00:00Z	00-scaffold.mdl	pass	applied	10	0	0		0	90.0	90	90	90	90	90	90	90	0	aaa1111' \
 '2026-10-10T12:00:00Z	01-orders.mdl	pass	applied	30	0	0		0	91.5	90	90	90	90	90	90	90	0	aaa2222' \
 '2026-10-10T12:10:00Z	02-orders-fix.mdl	fail	rolled-back	20	3	0		1									' \
 '2026-10-10T12:20:00Z	02-orders-fix.mdl	pass	applied	25	0	0		0	92.5	90	90	90	90	90	90	90	0	aaa3333' \
 '2026-10-10T12:30:00Z	03-billing.mdl	not-run	blocked	2	?			0									' \
 '2026-10-10T12:40:00Z	03-billing.mdl	pass	applied	40	0	0		0	93.5	90	90	90	90	90	90	90	0	aaa4444' \
 '2026-10-10T12:50:00Z	04-billing.mdl	pass	applied	45	0	0		0	94.5	90	90	90	90	90	90	90	0	aaa5555' > "$P10/.claude/loop/metrics-ledger.tsv"
touch "$P10/PROJECT.md"; CLAUDE_CONFIG_DIR="$EMPTY" "$PY" "$GEN" "$P10" --out "$WORK/out10/r.html" >/dev/null 2>&1
O10="$WORK/out10/r.html"
has "$O10" "6 of 8 gates passed" "stage state from PROJECT.md (P,0,1,2,3,4), the gate page is stale"
has "$O10" "3 of 7 rows built, 1 partial" "plan counts 3 built, 1 partial from build-plan.md (the JSON is stale)"
has "$O10" "not built 3" "3 not built"
has "$O10" "class='card ph now' id='phase-2'" "building now: 04-billing.mdl is in Phase 2 (Billing)"
has "$O10" "class='card ph' id='phase-1'" "Phase 1 is not marked now"
"$PY" - "$O10" <<'PYEOF5' && ok "build line: 7 build runs, 5 passed, 2 failed or blocked (12% of build time), last run, latest model score" || bad "build line"
import re, sys
t = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", open(sys.argv[1], encoding="utf-8").read()))
assert "7 build runs, 5 passed, 2 failed or blocked (about 12% of build time). Last build step: 04-billing.mdl (applied)" in t, re.findall(r"\d+ build runs.{0,120}", t)
assert re.search(r"Latest model score 94\.5", t), "score"
PYEOF5
"$PY" - "$O10" <<'PYEOF6' && ok "runs per phase sit inside the phase cards: 3 runs in Phase 1, 3 in Phase 2, no table" || bad "runs per phase"
import re, sys
h = open(sys.argv[1], encoding="utf-8").read()
for ph in ("1", "2"):
    i = h.index("id='phase-%s'" % ph); j = h.index("</summary>", i)
    assert "&middot; 3 runs" in h[i:j], "phase %s: %r" % (ph, re.sub(r"<[^>]+>", " ", h[i:j])[:200])
assert "Applied</th>" not in h, "no per-phase runs table"
PYEOF6
has "$O10" "04-billing.mdl" "last build step is the newest ledger row"
"$PY" - "$O10" <<'PYEOF7' && ok "timestamps are local time and the switch is the first ledger row on or after the date" || bad "local time and switch"
import re, sys, datetime
t = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", open(sys.argv[1], encoding="utf-8").read()))
utc = datetime.datetime(2026, 10, 10, 12, 0, tzinfo=datetime.timezone.utc).astimezone().strftime("%H:%M")
assert ("the switch to Stage 5 is %s, the earliest build activity on or after it (source: .claude/loop/metrics-ledger.tsv)" % utc) in t, re.findall(r"Stage switch.{0,200}", t)
m = re.search(r"Stage 5\s+(\d\d:\d\d)", t)
first = datetime.datetime(2026, 10, 10, 12, 0, tzinfo=datetime.timezone.utc).astimezone().strftime("%H:%M")
assert "04-billing.mdl (applied), " in t
PYEOF7
hasnt "$O10" "id=build-facts" "no extra card for build facts"
card "$O10" 5 | grep -q "Exec runs" && bad "Stage 5 card gets no extra rows" || ok "Stage 5 card gets no extra rows"
hasnt "$O10" "href='[^']*progress-report" "the report never links itself"
P10B="$WORK/proj10b"; cp -R "$P10" "$P10B"
printf '%s\n' '2026-10-10T13:00:00Z	01-misc-tweak.mdl	pass	applied	5	0	0		0									' >> "$P10B/.claude/loop/metrics-ledger.tsv"
CLAUDE_CONFIG_DIR="$EMPTY" "$PY" "$GEN" "$P10B" --out "$WORK/out10/b.html" >/dev/null 2>&1
has "$WORK/out10/b.html" "class='card ph now' id='phase-1'" "a numbered script with no name match takes the phase of the nearest lower matched script (01-misc-tweak is Phase 1)"
card "$O10" 2 | grep -qi "brd" && ok "Stage 2 card lists the BRDs under analysis/knowledge-base/brd/" || bad "Stage 2 card lists the BRDs"

echo "F11 a project set up by an older toolkit, then bin/sync-project.sh"
export MXTK_LEAKGUARD_DENYFILE="$WORK/denylist"; export MXTK_SYNC_SKIP_CLONE_CHECK=1
P11="$WORK/proj11"; mkdir -p "$P11"; : > "$P11/Fixture.mpr"
MXTK_NO_GUIDE=1 "$ROOT/bin/init-project.sh" "$P11" >/dev/null 2>&1
ADD="$(git -C "$ROOT" log --diff-filter=A --format=%h -- project-bin/progress-report.py 2>/dev/null | tail -1)"
if [ -n "$ADD" ] && git -C "$ROOT" show "$ADD^:project-bin/build-plan-status.sh" > "$WORK/old-bps.sh" 2>/dev/null; then
  cp "$WORK/old-bps.sh" "$P11/bin/build-plan-status.sh"; chmod +x "$P11/bin/build-plan-status.sh"; rm -f "$P11/bin/progress-report.py"
  mkdir -p "$P11/architecture"; printf '<html>old build-plan page</html>\n' > "$P11/architecture/build-plan.html"; OLDSUM="$(cksum < "$P11/architecture/build-plan.html")"
  cp "$P10/architecture/build-plan.md" "$P11/architecture/build-plan.md"
  "$ROOT/bin/sync-project.sh" "$P11" >"$WORK/sync11.out" 2>&1; RC=$?
  [ "$RC" -eq 0 ] && ok "sync-project.sh exits 0 on the older project" || { bad "sync-project.sh exit $RC"; tail -5 "$WORK/sync11.out"; }
  [ -f "$P11/bin/progress-report.py" ] && ok "sync installed bin/progress-report.py" || bad "sync installed bin/progress-report.py"
  cmp -s "$P11/bin/build-plan-status.sh" "$ROOT/project-bin/build-plan-status.sh" && ok "the older unedited build-plan-status.sh was refreshed" || bad "older build-plan-status.sh refreshed"
  CLAUDE_CONFIG_DIR="$EMPTY" "$P11/bin/build-plan-status.sh" "$P11" --html >"$WORK/bps11.out" 2>&1; RC=$?
  [ "$RC" -eq 0 ] && ok "build-plan-status.sh --html runs without error" || { bad "build-plan-status.sh --html exit $RC"; tail -5 "$WORK/bps11.out"; }
  hasnt "$WORK/bps11.out" "Traceback\|not written\|WARN" "no error or warning in its output"
  [ -s "$P11/architecture/progress-report.html" ] && ok "architecture/progress-report.html written" || bad "architecture/progress-report.html written"
  has "$P11/architecture/progress-report.html" "replaces the former build-plan.html" "the page says it replaces build-plan.html"
  [ "$(cksum < "$P11/architecture/build-plan.html")" = "$OLDSUM" ] && ok "the old build-plan.html is left exactly as it was (documented)" || bad "old build-plan.html untouched"
  hasnt "$P11/architecture/progress-report.html" "href='[^']*progress-report" "the report never links itself"
else
  ok "SKIP: toolkit git history not available for the older-toolkit fixture"
fi

echo "F12 one stage switch for every per-stage view"
# Ledger: first row 09:00 local. Sign-off row 12:00 (later). Gate-check run at 09:50 must not move the switch.
P12="$WORK/proj12"; mkproj "$P12"; rm -f "$P12/docs/BUILD-LOG.md" "$P12/docs/progress/TIME-LEDGER.md"; P12R="$(cd "$P12" && pwd -P)"
CFG12="$WORK/cfg12"; mkdir -p "$CFG12/projects/-p12"
"$PY" - "$CFG12/projects/-p12/m.jsonl" "$P12R" "$P12R/.claude/loop/metrics-ledger.tsv" <<'PYEOF8'
import json, os, sys, datetime
out, proj, ledger = sys.argv[1:4]
def at(h, m): return datetime.datetime(2026, 10, 10, h, m).timestamp()
def iso(t): return datetime.datetime.fromtimestamp(t, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
n = [0]
def rec(rows, t, blocks, tin=1000):
    n[0] += 1
    rows.append({"type": "assistant", "timestamp": iso(t), "cwd": proj, "uuid": "u%d" % n[0], "message": {"id": "m%d" % n[0], "model": "claude-sonnet-5-5", "role": "assistant", "content": blocks,
                 "usage": {"input_tokens": tin, "output_tokens": 100, "cache_read_input_tokens": 100, "cache_creation_input_tokens": 10}}})
main = []
rec(main, at(6, 55), [{"type": "tool_use", "id": "g0", "name": "Bash", "input": {"command": "bash bin/gate-check.sh 0"}}])
rec(main, at(7, 5), [{"type": "tool_use", "id": "a4", "name": "Agent", "input": {"description": "Stage 4 build plan", "prompt": "x", "subagent_type": "general-purpose"}}])
rec(main, at(9, 50), [{"type": "tool_use", "id": "g1", "name": "Bash", "input": {"command": "bash bin/gate-check.sh 4"}}])
rec(main, at(10, 30), [{"type": "text", "text": "x"}])
open(out, "w").write("".join(json.dumps(r, separators=(",", ":")) + "\n" for r in main))
sd = out[:-6] + "/subagents"; os.makedirs(sd, exist_ok=True)
for i, (h, m, desc) in enumerate([(7, 5, "Stage 4 build plan"), (7, 30, "Phase 1 old planning notes"), (8, 45, "Phase 0 walking skeleton"), (9, 20, "Author Phase 4")]):
    rows = []; rec(rows, at(h, m), [{"type": "text", "text": "x"}]); rec(rows, at(h, m) + 60, [{"type": "text", "text": "x"}])
    open("%s/agent-%d.jsonl" % (sd, i), "w").write("".join(json.dumps(r, separators=(",", ":")) + "\n" for r in rows)); json.dump({"description": desc}, open("%s/agent-%d.meta.json" % (sd, i), "w"))
utc = lambda t: datetime.datetime.fromtimestamp(t, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
open(ledger, "w").write("ts\tscript\tgate\tresult\telapsed_s\tmxbuild_errors\tlint_rc\tlint_total\trestored\tscore\n%s\t00-first.mdl\tnot-run\tblocked\t2\t?\t\t\t0\t\n%s\t01-orders.mdl\tpass\tapplied\t40\t0\t0\t\t0\t90.0\n" % (utc(at(9, 0)), utc(at(9, 20))))
PYEOF8
CLAUDE_CONFIG_DIR="$EMPTY" "$PY" "$GEN" "$P12" --out "$WORK/out12/r.html" --session-log "$CFG12/projects/-p12/m.jsonl" >/dev/null 2>&1
"$PY" - "$WORK/out12/r.html" <<'PYEOF9' && ok "windows table, chart band and sub-agent tables all use the 09:00 switch (earliest ledger row; gate-check at 09:50 and the 12:00 sign-off do not move it)" || bad "one stage switch for every view"
import re, sys
h = open(sys.argv[1], encoding="utf-8").read()
t = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", h))
m4 = re.search(r"Stage 4 (\d\d:\d\d) to (\d\d:\d\d)", t); m5 = re.search(r"Stage 5 (\d\d:\d\d) to", t)
assert m4 and m5 and m4.group(2) == "09:00" and m5.group(1) == "09:00", "windows table: %r %r" % (m4 and m4.groups(), m5 and m5.group(1))
def agents(stage):
    i = h.find("id='agents-%s'" % stage)
    if i < 0: return ""
    return re.sub(r"<[^>]+>", " ", h[i:h.index("</details>", i)])
a4, a5 = agents("4"), agents("5")
assert "Stage 4 build plan" in a4 and "Phase 1 old planning notes" in a4 and "Phase 0" not in a4 and "Author Phase 4" not in a4, "stage 4 agents: " + a4[:300]
assert "Phase 0 walking skeleton" in a5 and "Author Phase 4" in a5 and "Stage 4 build plan" not in a5, "stage 5 agents: " + a5[:300]
rects = [(float(x), float(w), st) for st, x, w in re.findall(r"<title>Stage (\w+)</title><rect x='([\d.]+)' y='6' width='([\d.]+)'", h)]
r5 = [r for r in rects if r[2] == "5"]
assert r5, "chart band has a Stage 5 rect"
x0 = rects[0][0]; xe = rects[-1][0] + rects[-1][1]
frac = (r5[0][0] - x0) / (xe - x0)
import datetime
t0 = datetime.datetime(2026, 10, 10, 6, 55).timestamp(); t1 = datetime.datetime(2026, 10, 10, 10, 30).timestamp(); sw = datetime.datetime(2026, 10, 10, 9, 0).timestamp()
exp = (sw - t0) / (t1 - t0)
assert abs(frac - exp) < 0.02, "band at %.3f, switch at %.3f" % (frac, exp)
PYEOF9

echo "F13 a cached discovery run does not reopen session files"
P13="$WORK/proj13"; mkproj "$P13"; P13R="$(cd "$P13" && pwd -P)"
CFG13="$WORK/cfg13"; mklog "$CFG13" "$P13R" 25
rm -f "$P13/.claude/progress-report-sessions.txt"
CLAUDE_CONFIG_DIR="$CFG13" PROGRESS_REPORT_DEBUG=1 "$PY" "$GEN" "$P13" --out "$WORK/out13/a.html" >"$WORK/out13.cold" 2>&1
CLAUDE_CONFIG_DIR="$CFG13" PROGRESS_REPORT_DEBUG=1 "$PY" "$GEN" "$P13" --out "$WORK/out13/b.html" >"$WORK/out13.warm" 2>&1
[ -s "$P13/.claude/progress-report-sessions.txt" ] && ok "discovery cache written to .claude/progress-report-sessions.txt" || bad "discovery cache written"
grep -q "discovery cold" "$WORK/out13.cold" && grep -q "opened .*s1.jsonl" "$WORK/out13.cold" && ok "cold run reads the session file" || bad "cold run reads the session file"
grep -q "discovery warm, 0 file(s) read" "$WORK/out13.warm" && ok "warm run reads no file during discovery" || bad "warm run reads no file during discovery"
grep -q "opened .*s1.jsonl" "$WORK/out13.warm" && bad "warm run reopened the session file" || ok "warm run does not reopen the session file"
has "$WORK/out13/b.html" "Sessions from other folders (1)" "a warm run lists the same sessions"
touch "$CFG13/projects/-tmp-elsewhere/s1.jsonl"; echo >> "$CFG13/projects/-tmp-elsewhere/s1.jsonl"
CLAUDE_CONFIG_DIR="$CFG13" PROGRESS_REPORT_DEBUG=1 "$PY" "$GEN" "$P13" --out "$WORK/out13/c.html" >"$WORK/out13.chg" 2>&1
grep -q "opened .*s1.jsonl" "$WORK/out13.chg" && ok "a changed session file is read again" || bad "a changed session file is read again"

echo "F15 the cache is tied to the project path and the attribution rules"
P15="$WORK/proj15"; mkproj "$P15"; P15R="$(cd "$P15" && pwd -P)"
CFG15="$WORK/cfg15"; mklog "$CFG15" "$P15R" 25
CLAUDE_CONFIG_DIR="$CFG15" PROGRESS_REPORT_DEBUG=1 "$PY" "$GEN" "$P15" --out "$WORK/out15/a.html" >"$WORK/out15.a" 2>&1
has "$WORK/out15/a.html" "Sessions from other folders (1)" "the original project lists the session"
head -1 "$P15/.claude/progress-report-sessions.txt" | grep -q "root=$P15R" && head -1 "$P15/.claude/progress-report-sessions.txt" | grep -q "rules=share=0.25;calls=20" && ok "cache header holds the project path and the 25% / 20 calls rules" || bad "cache header holds path and rules"
P15B="$WORK/proj15-copy"; cp -R "$P15" "$P15B"
CLAUDE_CONFIG_DIR="$CFG15" PROGRESS_REPORT_DEBUG=1 "$PY" "$GEN" "$P15B" --out "$WORK/out15/b.html" >"$WORK/out15.b" 2>&1
grep -q "discovery cold" "$WORK/out15.b" && ok "a copied project with its cache starts cold" || bad "a copied project starts cold"
hasnt "$WORK/out15/b.html" "Sessions from other folders (1)" "the copy does not show the original project's sessions"
CLAUDE_CONFIG_DIR="$CFG15" PROGRESS_REPORT_DEBUG=1 "$PY" "$GEN" "$P15" --out "$WORK/out15/c.html" >"$WORK/out15.c" 2>&1
grep -q "discovery warm" "$WORK/out15.c" && ok "the original's own cache is still warm" || bad "the original's cache is warm"
sed -i.bak '1s/rules=[^\t]*/rules=share=0.10;calls=5/' "$P15/.claude/progress-report-sessions.txt"; rm -f "$P15/.claude/progress-report-sessions.txt.bak"
CLAUDE_CONFIG_DIR="$CFG15" PROGRESS_REPORT_DEBUG=1 "$PY" "$GEN" "$P15" --out "$WORK/out15/d.html" >"$WORK/out15.d" 2>&1
grep -q "discovery cold" "$WORK/out15.d" && ok "a cache written under other thresholds is rebuilt" || bad "other thresholds rebuild the cache"

echo "F16 a cached run reads no more files than the uncached one (cap)"
P16="$WORK/proj16"; mkproj "$P16"; P16R="$(cd "$P16" && pwd -P)"
CFG16="$WORK/cfg16"; for n in 1 2 3 4 5; do mklog "$CFG16" "$P16R" 3 "n$n"; done
PROGRESS_REPORT_SCAN_MAX_FILES=2 CLAUDE_CONFIG_DIR="$CFG16" PROGRESS_REPORT_DEBUG=1 "$PY" "$GEN" "$P16" --out "$WORK/out16/a.html" >"$WORK/out16.cold" 2>&1
PROGRESS_REPORT_SCAN_MAX_FILES=2 CLAUDE_CONFIG_DIR="$CFG16" PROGRESS_REPORT_DEBUG=1 "$PY" "$GEN" "$P16" --out "$WORK/out16/b.html" >"$WORK/out16.warm" 2>&1
RC="$(sed -n 's/.*discovery cold, \([0-9]*\) file(s) read.*/\1/p' "$WORK/out16.cold")"; RW="$(sed -n 's/.*discovery warm, \([0-9]*\) file(s) read.*/\1/p' "$WORK/out16.warm")"
[ "$RC" = "2" ] && ok "cold run with a cap of 2 reads 2 files" || bad "cold run reads 2 files (got '$RC')"
[ -n "$RW" ] && [ "$RW" -le "$RC" ] && ok "the cached run read $RW file(s), not more than the uncached $RC" || bad "cached run reads no more than uncached (cold '$RC', warm '$RW')"
grep -c $'^no\t' "$P16/.claude/progress-report-sessions.txt" | grep -q "^[3-9]" && ok "files past the cap are recorded as no" || bad "files past the cap recorded as no"

echo "F17 the exec log decides the switch; session-log signals are ignored when it has rows"
P17="$WORK/proj17"; mkproj "$P17"
sed -i.bak 's/CONFIRMED 2026-10-10 12:00/CONFIRMED (delegated) 2026-10-10/' "$P17/PROJECT.md"; rm -f "$P17/PROJECT.md.bak"
P17R="$(cd "$P17" && pwd -P)"; CFG17="$WORK/cfg17"; mklog "$CFG17" "$P17R" 25 s17
TZ=UTC CLAUDE_CONFIG_DIR="$EMPTY" "$PY" "$GEN" "$P17" --out "$WORK/out17/r.html" --session-log "$CFG17/projects/-tmp-elsewhere/s17.jsonl" >/dev/null 2>&1
"$PY" - "$WORK/out17/r.html" <<'PYEOF17' && ok "log has an exec.sh call at 11:50 on the 10th; the switch stays at the first BUILD-LOG row (12 Oct 10:00)" || bad "switch follows the ledger, not the session log"
import re, sys
t = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", open(sys.argv[1], encoding="utf-8").read()))
assert "Stage 5 is 12 Oct 10:00" in t, "switch not at the first ledger row"
assert "first exec.sh call in the session log" not in t, "session signal named as the source"
PYEOF17
P17B="$WORK/proj17b"; mkproj "$P17B"; rm -f "$P17B/docs/BUILD-LOG.md"
sed -i.bak 's/CONFIRMED 2026-10-10 12:00/CONFIRMED (delegated) 2026-10-10/' "$P17B/PROJECT.md"; rm -f "$P17B/PROJECT.md.bak"
TZ=UTC CLAUDE_CONFIG_DIR="$EMPTY" "$PY" "$GEN" "$P17B" --out "$WORK/out17/b.html" --session-log "$CFG17/projects/-tmp-elsewhere/s17.jsonl" >/dev/null 2>&1
"$PY" - "$WORK/out17/b.html" <<'PYEOF17B' && ok "control: with no ledger rows the session's exec.sh call (on the 10th) still sets the switch" || bad "control: no ledger, session log decides"
import re, sys
t = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", open(sys.argv[1], encoding="utf-8").read()))
assert "Stage 5 is 10 Oct" in t and "12 Oct" not in t.split("Detected starts")[1][:30], "session log should set the switch on the 10th"
PYEOF17B

echo "F14 autoreload keeps the view, waits for idle and can be paused"
P14="$WORK/proj14"; mkproj "$P14"; mkdir -p "$P14/.claude/loop"
NOWU="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'ts\tscript\tgate\tresult\telapsed_s\tmxbuild_errors\tlint_rc\tlint_total\trestored\tscore\n%s\t01-orders.mdl\tpass\tapplied\t40\t0\t0\t\t0\t90.0\n' "$NOWU" > "$P14/.claude/loop/metrics-ledger.tsv"
CLAUDE_CONFIG_DIR="$EMPTY" "$PY" "$GEN" "$P14" --out "$WORK/out14/r.html" >/dev/null 2>&1
has "$WORK/out14/r.html" "history.scrollRestoration='manual'" "scrollRestoration is set to manual"
has "$WORK/out14/r.html" "sessionStorage" "scroll position and open details go to sessionStorage"
has "$WORK/out14/r.html" "id=livebtn" "Pause control present"
has "$WORK/out14/r.html" "Live &middot; refreshes every 30 s" "live indicator present"
if command -v node >/dev/null 2>&1; then
node - "$WORK/out14/r.html" <<'JSEOF' && ok "node: state saved and restored, no reload within 20 s of input, Pause stops it" || bad "autoreload behaviour (node)"
const fs = require("fs");
const h = fs.readFileSync(process.argv[2], "utf8");
const src = h.match(/<script id=autoreload>([\s\S]*?)<\/script>/)[1];
let now = 1e12, timers = [], reloads = 0, store = {}, scrolls = [];
const det = [{id: "a", tagName: "DETAILS", open: true}, {id: "b", tagName: "DETAILS", open: false}];
const listeners = {};
const btn = {textContent: "", addEventListener: (n, f) => { btn.f = f; }};
const txt = {textContent: ""};
const win = {pageYOffset: 640, addEventListener: (n, f) => { listeners[n] = f; }, scrollTo: (x, y) => scrolls.push(y)};
const doc = {documentElement: {style: {}, scrollTop: 0},
  getElementById: id => id === "livebtn" ? btn : id === "livetxt" ? txt : det.find(d => d.id === id) || null,
  querySelectorAll: () => det, addEventListener: () => {}};
const hist = {};
const loc = {pathname: "/r.html", reload: () => { reloads++; }};
const ss = {getItem: k => k in store ? store[k] : null, setItem: (k, v) => { store[k] = String(v); }, removeItem: k => { delete store[k]; }};
const Date2 = {now: () => now};
const fn = new Function("window", "document", "history", "location", "sessionStorage", "setTimeout", "Date", src.replace(/last=\d+/, "last=" + (now / 1000)));
fn(win, doc, hist, loc, ss, (f, ms) => timers.push({f, ms}), Date2);
const assert = require("assert");
assert.strictEqual(hist.scrollRestoration, "manual");
assert.strictEqual(timers.length, 1); assert.strictEqual(timers[0].ms, 30000);
// user interacted 5 s ago: the tick re-arms and does not reload
listeners.scroll(); now += 5000; timers.shift().f(); assert.strictEqual(reloads, 0); assert.strictEqual(timers.length, 1);
// 25 s after the last input: reload, with state saved
now += 25000; timers.shift().f(); assert.strictEqual(reloads, 1);
const saved = JSON.parse(store["pr-view:/r.html"]); assert.strictEqual(saved.y, 640); assert.deepStrictEqual(saved.d, {a: true, b: false});
// a new page load restores it
det[0].open = false; det[1].open = true; scrolls = [];
fn(win, doc, hist, loc, ss, (f, ms) => timers.push({f, ms}), Date2);
assert.strictEqual(det[0].open, true); assert.strictEqual(det[1].open, false); assert.strictEqual(scrolls[0], 640);
// Pause stops reloads
timers = []; fn(win, doc, hist, loc, ss, (f, ms) => timers.push({f, ms}), Date2);
btn.f({preventDefault() {}}); assert.strictEqual(txt.textContent, "Paused");
now += 60000; reloads = 0; timers.shift().f(); assert.strictEqual(reloads, 0);
JSEOF
else ok "SKIP: node not available for the autoreload behaviour test"; fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
