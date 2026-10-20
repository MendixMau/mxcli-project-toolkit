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
#   P6  one plan view (#474): every row appears once, inside its phase card with Produces, Depends on, Scripts and
#       Claims; the now phase renders open; views A and B stay as their own section.
#   P6b an older progress-report.py without --phase-detail (a partial sync) still renders, with the short row tables.
#   P6c the page's own scripts, run in node against a DOM shim: the now phase is open on load, opening phase 1
#       closes phase 2, a #phase-3 link on load wins over the default, and restored state wins over the default.
#   P7  top bar and header (#479): one group of section links (Stages, Build, Pages), no stage chips; the bar stays
#       sticky and phone-safe; every #stage-N card anchor stays; the header states the current stage; exactly one
#       id=stamp, every other volatile line marked data-stamp, every id on the page unique; the autoreload's
#       live controls sit on the id=stamp line; no "replaces the former build-plan.html" in the header.
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

echo "P6 one plan view: rows once, in the phase cards; the now phase starts open; views A and B stay"
[ "$(grep -c "<td>3</td>" "$R")" = 1 ] && ok "row 3 appears once" || bad "row 3 appears once"
[ "$(grep -c ">done 2026-10-12</td>" "$R")" = 1 ] && ok "row 2 state appears once" || bad "row 2 state appears once"
hasnt "$R" "Full plan tables" "the duplicate plan-tables block is gone"
has "$R" "<details class='card ph now' id='phase-2' open>" "the now phase renders open"
hasnt "$R" "<details class='card ph' id='phase-1'[^>]* open" "other phases start closed"
has "$R" "<th>Produces / Proves</th><th>Depends on</th><th>State</th><th>Scripts</th>" "cards carry the full row columns"
has "$R" "<h2>A\\. Script folders" "view A stays"
has "$R" "<h2>B\\. Modules" "view B stays"
has "$R" "href='#plan-tables'" "the jump link still points at views A and B"
has "$R" "addEventListener(.\\?'toggle" "accordion toggle handler present in the script"
[ "$(grep -o "addEventListener(.\\?'toggle" "$R" | wc -l)" = 1 ] && ok "accordion handler is not duplicated" || bad "accordion handler is not duplicated"

echo "P6b an older progress-report.py without --phase-detail still renders the page, with the short row tables"
OLD="$WORK/oldbin"; mkdir -p "$OLD"
cp "$SCRIPT" "$ROOT/project-bin/_common.sh" "$OLD/"
# The generator as it was before #474: no --phase-detail option (the attribute defaults to empty).
sed 's/ap\.add_argument("--phase-detail", help="[^"]*")/ap.set_defaults(phase_detail=None)/' "$ROOT/project-bin/progress-report.py" > "$OLD/progress-report.py"
if grep -q -- '--phase-detail' "$OLD/progress-report.py"; then bad "old-generator copy still names --phase-detail"
else
  "$PY" "$OLD/progress-report.py" "$P1" --no-log --out "$WORK/old-direct.html" --phase-detail /dev/null >/dev/null 2>&1 \
    && bad "control: the old-generator copy should reject --phase-detail" || ok "control: the old-generator copy rejects --phase-detail"
  P6B="$WORK/p6b"; mkproj "$P6B" "**Stage 5 - Build**, in progress - gates passed: P, 0, 1, 2, 3, 4"
  cp "$P1/architecture/build-plan.md" "$P6B/architecture/"
  CLAUDE_CONFIG_DIR="$EMPTY" bash "$OLD/build-plan-status.sh" "$P6B" --html >"$WORK/p6b.out" 2>&1
  R6B="$P6B/architecture/progress-report.html"
  [ -f "$R6B" ] && ok "page written by the older generator" || bad "page written by the older generator ($(tail -n 1 "$WORK/p6b.out"))"
  has "$R6B" "<th>#</th><th>Kind</th><th>Row</th><th>State</th>" "phase cards fall back to the short row table"
  hasnt "$R6B" "unrecognized arguments" "no argparse error on the page"
fi

echo "P6c accordion and load order, run in node against a DOM shim"
if command -v node >/dev/null 2>&1; then
P6="$WORK/p6"; mkproj "$P6" "**Stage 5 - Build**, in progress - gates passed: P, 0, 1, 2, 3, 4"
cp "$P1/architecture/build-plan.md" "$P6/architecture/"
printf '\n### Phase 3 - Reports\n\n| # | Kind | Step | Produces | Depends on | State |\n|---|---|---|---|---|---|\n| 4 | BUILD | report page | 04-report.mdl | 3 | not built |\n' >> "$P6/architecture/build-plan.md"
mkdir -p "$P6/.claude/loop"   # recent activity, so the page carries its autoreload (state save/restore) script
printf 'ts\tscript\tgate\tresult\telapsed_s\tmxbuild_errors\tlint_rc\tlint_total\trestored\tscore\n%s\t02-billing.mdl\tpass\tapplied\t40\t0\t0\t\t0\t90.0\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$P6/.claude/loop/metrics-ledger.tsv"
CLAUDE_CONFIG_DIR="$EMPTY" bash "$SCRIPT" "$P6" --html >/dev/null 2>&1
node - "$P6/architecture/progress-report.html" <<'JSEOF' && ok "node: now phase open on load; opening phase 1 closes phase 2; #phase-3 beats the default; saved state beats the default" || bad "accordion and load order (node)"
const fs = require("fs"), assert = require("assert");
const h = fs.readFileSync(process.argv[2], "utf8");
const main = h.match(/<script>([\s\S]*?)<\/script>/)[1];
const reload = h.match(/<script id=autoreload>([\s\S]*?)<\/script>/)[1];
const cards = [...h.matchAll(/<details class='card ph[^']*' id='(phase-[^']+)'( open)?>/g)].map(m => [m[1], !!m[2]]);
assert.deepStrictEqual(cards.map(c => c[0]), ["phase-1", "phase-2", "phase-3"]);
// One page load: details elements whose open setter queues a coalesced 'toggle' (as browsers do, also for the
// open attribute at parse time), the page's two scripts run in order, then the queued toggles are dispatched.
function load(hash, store) {
  const pending = [], caps = [], els = {};
  const queue = e => { if (!pending.includes(e)) pending.push(e); };
  for (const [id, open] of cards) {
    const e = {id, tagName: "DETAILS", _o: open, classList: {contains: c => c === "ph"}, closest: s => s === "details" ? e : null};
    Object.defineProperty(e, "open", {get() { return this._o; }, set(v) { v = !!v; if (v !== this._o) { this._o = v; queue(this); } }});
    els[id] = e; if (open) queue(e);
  }
  const all = Object.values(els);
  const doc = {documentElement: {style: {}, scrollTop: 0}, getElementById: id => els[id] || null,
    querySelectorAll: s => s === "details.ph[open]" ? all.filter(e => e.open) : s === "details[id]" ? all : [],
    addEventListener: (n, f, cap) => { if (n === "toggle") caps.push(f); }};
  const win = {pageYOffset: 0, addEventListener: () => {}, scrollTo: () => {}};
  const ss = {getItem: k => k in store ? store[k] : null, setItem: (k, v) => { store[k] = String(v); }, removeItem: k => { delete store[k]; }};
  const run = src => new Function("window", "document", "history", "location", "sessionStorage", "setTimeout", src)(
    win, doc, {}, {hash, pathname: "/r.html", reload() {}}, ss, () => {});
  run(main); run(reload);
  const flush = () => { while (pending.length) { const t = pending.shift(); caps.forEach(f => f({target: t})); } };
  flush();
  return {els, flush, open: () => all.filter(e => e.open).map(e => e.id)};
}
let p = load("", {});
assert.deepStrictEqual(p.open(), ["phase-2"], "the now phase is open on load");
p.els["phase-1"].open = true; p.flush();
assert.deepStrictEqual(p.open(), ["phase-1"], "opening phase 1 closes phase 2");
assert.deepStrictEqual(load("#phase-3", {}).open(), ["phase-3"], "#phase-3 on load wins over the default");
const saved = {"pr-view:/r.html": JSON.stringify({y: 0, d: {"phase-1": true, "phase-2": false, "phase-3": false}})};
assert.deepStrictEqual(load("", saved).open(), ["phase-1"], "restored state wins over the default");
JSEOF
else ok "SKIP: node not available for the accordion behaviour test"; fi

echo "P7 top bar, unique stamp id, header wording (#479)"
P7="$WORK/p7"; mkproj "$P7" "**Stage 5 - Build**, in progress - gates passed: P, 0, 1, 2, 3, 4"
cp "$P1/architecture/build-plan.md" "$P7/architecture/"
mkdir -p "$P7/.claude/loop"   # recent activity, so the page carries the autoreload script and its live controls
printf 'ts\tscript\tgate\tresult\telapsed_s\tmxbuild_errors\tlint_rc\tlint_total\trestored\tscore\n%s\t02-billing.mdl\tpass\tapplied\t40\t0\t0\t\t0\t90.0\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$P7/.claude/loop/metrics-ledger.tsv"
CLAUDE_CONFIG_DIR="$EMPTY" bash "$SCRIPT" "$P7" --html >/dev/null 2>&1
R7="$P7/architecture/progress-report.html"
[ "$(grep -c 'id=stamp' "$R7")" -le 1 ] && ok "grep -c 'id=stamp' is at most 1 ($(grep -c 'id=stamp' "$R7"))" || bad "id=stamp appears $(grep -c 'id=stamp' "$R7") times"
"$PY" - "$R7" "$ROOT/project-bin/progress-report.py" <<'PYEOF7' && ok "one nav group with Stages, sticky and phone-safe; stage anchors kept; current stage in the header; ids unique; volatile lines marked; autoreload controls on the stamp line" || bad "top bar / stamp / header (P7)"
import re, sys, collections
h = open(sys.argv[1], encoding="utf-8").read(); gen = open(sys.argv[2], encoding="utf-8").read()
nav = re.search(r"<nav class=snav[^>]*>(.*?)</nav>", h).group(1)
links = re.findall(r"<a href='([^']+)'[^>]*>([^<]+)</a>", nav)
assert [t for _, t in links] == ["Stages", "Build", "Pages"], links            # no Tips without a session log
assert not re.search(r"href='#stage-", nav) and "<b>" not in nav, nav           # the chip group is gone
assert "id=stages" in h and h.index("id=stages") < h.index("id='stage-P'"), "Stages target sits above the stage cards"
for s_ in ["P", "0", "1", "2", "3", "4", "5", "6"]: assert "id='stage-%s'" % s_ in h, s_
assert ".snav{position:sticky;top:0" in gen and ".snav{padding:6px 12px;flex-wrap:nowrap;overflow-x:auto" in gen
head = h[h.index("<header>"):h.index("</header>")]
assert re.search(r"Current stage: <a href='#stage-5'>Stage 5: [^<]+</a>", head), "current stage in the header"
assert "replaces the former build-plan.html" not in head
ids = re.findall(r"""\bid=['"]?([\w:.-]+)""", h)
dup = [i for i, c in collections.Counter(ids).items() if c > 1]; assert not dup, dup
lines = h.split("\n")
st = [l for l in lines if "id=stamp" in l]; assert len(st) == 1 and "Last updated" in st[0], st
for marker in ("Last updated", "session log last event", "Last build step", "Latest model score", "Plan read", "Rebuild: project-bin"):
    for l in lines:
        if marker in l and "<script" not in l: assert "data-stamp" in l or "id=stamp" in l, marker
assert "id=livetxt" in st[0] and "id=livebtn" in st[0], "autoreload's live controls ride on the stamp line"
PYEOF7
hasnt "$R7" "replaces the former build-plan.html" "the old build-plan.html wording is gone from the page header"
# --refresh still leaves an unchanged page alone: the volatile lines are found by id=stamp or data-stamp
SUM7="$(cksum < "$R7")"; sleep 1
CLAUDE_CONFIG_DIR="$EMPTY" bash "$SCRIPT" "$P7" --refresh >/dev/null 2>&1
[ "$(cksum < "$R7")" = "$SUM7" ] && ok "--refresh leaves the page byte-identical when only stamp lines would change" || bad "--refresh rewrote an unchanged page"

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
