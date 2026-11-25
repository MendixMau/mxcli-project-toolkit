#!/usr/bin/env bash
# test-report-clarity.sh: the progress report says honestly how fresh it is, opens once on any OS, shows no
# absolute path, and explains its words without repeating zeros. Issue 841 part D (D2, D3, D7, D8).
#
#   D2  the stamp carries the epoch it was written; the page script turns it into "Updated N min ago" and, past 5 min,
#       says "No update for N"; the live wording says the page updates after each build step; no "refreshes every 30 s"
#       claim; nothing says a step is running.
#   D3  build-plan-status.sh --refresh opens the page once per project (.claude/.report-shown), only under
#       `Progress report: auto`, and not from the temp folder, over SSH or under `Interview mode: auto`: macOS, Linux with a
#       display, WSL and Git Bash each pick their opener (platform override, stub openers on PATH); not twice; not with CI
#       set; not with MXTK_NO_REPORT_OPEN (environment or toolkit.env); not without a display; an explicit --open still
#       opens past the sentinel; a failing opener neither fails the run nor leaves the sentinel unwritten.
#   D7  the rendered page holds neither the project's own absolute root nor the running user's home (POSIX or C:\Users
#       spelling), nor a session-log folder name carrying the user name; an app route such as /Users/123/orders or
#       /home/dashboard is content and survives; an href is never rewritten.
#   D8  a "What do these words mean?" block lists the words the page uses; a finished stage with no time, tokens or
#       decisions prints none of those lines; the "No Claude Code session log" sentence appears once.
#
# NO real browser is ever started: every opener is a stub on PATH that appends to a log.
# Usage: bash tests/wave2/test-report-clarity.sh /path/to/build-plan-status.sh
set -uo pipefail
SCRIPT="${1:?usage: bash tests/wave2/test-report-clarity.sh /path/to/build-plan-status.sh}"
case "$SCRIPT" in /*) ;; *) SCRIPT="$PWD/$SCRIPT" ;; esac
GEN="$(dirname "$SCRIPT")/progress-report.py"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/report-clarity.XXXXXX")"
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
EMPTY="$WORK/emptycfg"; mkdir -p "$EMPTY"

mkproj() {  # dir: a stage-5 project with a plan, a gate page whose detail carries absolute paths, a log of its own
  local d="$1"; mkdir -p "$d/architecture" "$d/mdlsource" "$d/.claude" "$d/docs"
  cat > "$d/PROJECT.md" <<'MD'
# PROJECT.md

## Current stage

**Stage 5 - Build**, in progress - gates passed: P, 0, 1, 2, 3, 4 · manual: 5 (derived by gate-check)

Entry mode: requirements-driven

Progress report: auto
MD
  cat > "$d/architecture/build-plan.md" <<'MD'
# Build plan

### Phase 1 - Orders

| # | Kind | Step | State |
|---|---|---|---|
| 1 | BRIEF | brief | built |
| 2 | BUILD | order entity | built |
| 3 | PROVE | tests | not built |
MD
  local abs; abs="$(cd "$d" && pwd -P)"
  printf '<table><tr><td>P</td><td>t</td><td>PASS</td><td>ok</td></tr><tr><td>0</td><td>t</td><td>FAIL</td><td>unanswered in %s/triage.md</td></tr><tr><td>1</td><td>t</td><td>FAIL</td><td>GET /Users/123/orders fails</td></tr><tr><td>2</td><td>t</td><td>FAIL</td><td>route /home/dashboard opens</td></tr><tr><td>3</td><td>t</td><td>FAIL</td><td>see /home/fixture-user/secret/x.md</td></tr></table>' "$abs" > "$d/index.html"
}

# ── D2 ───────────────────────────────────────────────────────────────────────
echo "D2 freshness is relative, ticks in the browser, and says nothing it cannot know"
P2="$WORK/p2"; mkproj "$P2"; printf 'ts\tscript\tgate\tresult\telapsed_s\n' > /dev/null
# a build that is active: a ledger row from now, so the page carries the live controls
mkdir -p "$P2/.claude/loop"; NOWU="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'ts\tscript\tgate\tresult\telapsed_s\tmxbuild_errors\tlint_rc\tlint_total\trestored\tscore\n%s\t01.mdl\tpass\tapplied\t40\t0\t0\t\t0\t90.0\n' "$NOWU" > "$P2/.claude/loop/metrics-ledger.tsv"
R2="$WORK/r2.html"; CLAUDE_CONFIG_DIR="$EMPTY" "$PY" "$GEN" "$P2" --out "$R2" >/dev/null 2>&1
T="$(grep -o "id=stamp data-stamp data-t='[0-9]*'" "$R2" | grep -o "[0-9]*'" | tr -d "'")"
NOWE="$("$PY" -c 'import time;print(int(time.time()))')"
[ -n "$T" ] && [ "$(( NOWE - T ))" -ge 0 ] && [ "$(( NOWE - T ))" -lt 120 ] && ok "the stamp embeds the generation epoch (age $(( NOWE - T )) s)" || bad "the stamp embeds the generation epoch"
has "$R2" "data-clock='" "the clock time stays on the page (data-clock, shown as the title)"
has "$R2" "id=agelabel" "the age script is present"
has "$R2" "Updates after each build step" "the live wording says the page updates after each build step"
hasnt "$R2" "refreshes every 30 s" "no 'refreshes every 30 s' claim"
hasnt "$R2" "is running" "nothing on the page says a step is running"
has "$R2" "<span id=livetxt>Updates after each build step</span>" "without JavaScript the live line says nothing about re-checking"
has "$R2" "id=fresh hidden" "the stale notice exists, hidden until the page is old"
if command -v node >/dev/null 2>&1; then
  node - "$R2" <<'JSEOF' && ok "node: 'Updated N min ago', ticking text, 'No update for N' only past 5 min" || bad "age script behaviour (node)"
const fs = require("fs"), assert = require("assert");
const h = fs.readFileSync(process.argv[2], "utf8");
const src = h.match(/<script id=agelabel>([\s\S]*?)<\/script>/)[1];
function run(ageS, actAgeS) {
  const nowMs = 1.9e12;
  const attrs = {"data-t": String(nowMs / 1000 - ageS), "data-act": String(nowMs / 1000 - actAgeS), "data-clock": "CLOCK-TEXT"};
  const s = {textContent: "Last updated X", title: "", getAttribute: k => attrs[k]};
  const f = {textContent: "", hidden: true, appendChild() {}};
  const lv = {textContent: "Updates after each build step"};
  const els = {stamp: s, fresh: f, livetxt: lv};
  const D = {now: () => nowMs};
  new Function("document", "Date", "setInterval", "window", src)({getElementById: id => els[id] || null, createElement: () => ({})}, D, () => 0, {});
  return {s, f, lv};
}
let r = run(10, 10); assert.strictEqual(r.s.textContent, "Updated just now"); assert.strictEqual(r.f.hidden, true);
r = run(240, 240); assert.strictEqual(r.s.textContent, "Updated 4 min ago"); assert.strictEqual(r.f.hidden, true); assert.ok(r.s.title.includes("CLOCK-TEXT"));
r = run(720, 720); assert.strictEqual(r.s.textContent, "Updated 12 min ago"); assert.strictEqual(r.f.hidden, false); assert.ok(r.f.textContent.startsWith("No update for 12 min"));
assert.ok(r.lv.textContent.startsWith("Not re-checking"), "stopped polling is said, not hidden behind 'Live'");
r = run(720, 610); assert.ok(!r.lv.textContent.startsWith("Not re-checking"), "polling still runs up to 30 s past the 10 min mark");
r = run(7200, 7200); assert.strictEqual(r.s.textContent, "Updated 2 h ago");
assert.ok(!/running/.test(r.f.textContent));
JSEOF
else ok "SKIP: node not available for the age script"; fi

# ── D3 ───────────────────────────────────────────────────────────────────────
echo "D3 the page opens once per project, on any OS, never in CI or headless"
STUB="$WORK/stub"; mkdir -p "$STUB"; LOG="$WORK/open.log"
for s in open xdg-open explorer.exe wslview; do printf '#!/bin/sh\necho "%s $*" >> "%s"\nexit ${STUB_RC:-0}\n' "$s" "$LOG" > "$STUB/$s"; done
printf '#!/bin/sh\necho "cmd.exe $*" >> "%s"\nexit 0\n' "$LOG" > "$STUB/cmd.exe"
printf '#!/bin/sh\nprintf "C:\\\\win\\\\%%s" "$(basename "$2")"\n' > "$STUB/cygpath"
printf '#!/bin/sh\nprintf "\\\\\\\\wsl\\\\%%s" "$(basename "$2")"\n' > "$STUB/wslpath"
chmod +x "$STUB"/*
newproj() { local d="$WORK/$1"; mkproj "$d"; printf '%s' "$d"; }
refresh() {  # dir, then env assignments: run --refresh with a clean environment plus the stubs; waits for a background opener
  local d="$1"; shift
  : > "$LOG"
  env -i HOME="$WORK/home" PATH="$STUB:/usr/bin:/bin" CLAUDE_CONFIG_DIR="$EMPTY" MXTK_REPORT_OPEN_TMP=1 "$@" bash "$SCRIPT" "$d" --refresh >/dev/null 2>&1; RC=$?
  sleep 0.6
}
opens() { grep -c . "$LOG" 2>/dev/null | head -1; }
mkdir -p "$WORK/home"
# guard: inside this fixture's clean environment every opener name resolves to a stub, never to a real browser launcher
GUARD_OK=1
for n in open xdg-open cmd.exe explorer.exe wslview; do
  r="$(env -i PATH="$STUB:/usr/bin:/bin" sh -c "command -v $n")"; [ "$r" = "$STUB/$n" ] || GUARD_OK=0
done
[ "$GUARD_OK" = 1 ] && ok "guard: open, xdg-open, cmd.exe, explorer.exe and wslview all resolve to stubs in the fixture's PATH" || bad "guard: a real opener is reachable from the fixture's PATH"
A="$(newproj a)"; refresh "$A" MXTK_PLATFORM=linux DISPLAY=:0
[ "$(opens)" = 1 ] && grep -q "xdg-open .*progress-report.html" "$LOG" && ok "linux with a display: xdg-open called once on the page" || bad "linux open ($(cat "$LOG"))"
[ -e "$A/.claude/.report-shown" ] && ok "the sentinel is written when an opener was started" || bad "sentinel written"
rm -f "$A/architecture/progress-report.html"; refresh "$A" MXTK_PLATFORM=linux DISPLAY=:0
[ "$(opens)" = 0 ] && [ -f "$A/architecture/progress-report.html" ] && ok "second write of the page: no second open" || bad "second open ($(opens))"
refresh "$A" MXTK_PLATFORM=linux DISPLAY=:0 CI=1; [ "$(opens)" = 0 ] && ok "(control) sentinel present: still nothing" || bad control
A2="$(newproj a2)"; refresh "$A2" MXTK_PLATFORM=linux DISPLAY=:0 CI=true
[ "$(opens)" = 0 ] && [ ! -e "$A2/.claude/.report-shown" ] && ok "CI set: no open, no sentinel" || bad "CI guard"
A3="$(newproj a3)"; refresh "$A3" MXTK_PLATFORM=linux
[ "$(opens)" = 0 ] && [ ! -e "$A3/.claude/.report-shown" ] && ok "linux without a display: no open, no sentinel (a later run on a desktop still opens)" || bad "headless guard"
refresh "$A3" MXTK_PLATFORM=linux DISPLAY=:0 STUB_RC=0; rm -f "$A3/architecture/progress-report.html"; refresh "$A3" MXTK_PLATFORM=linux DISPLAY=:0
[ "$(opens)" = 1 ] && ok "the same project opens once a display exists" || bad "later open ($(opens))"
A4="$(newproj a4)"; refresh "$A4" MXTK_PLATFORM=linux DISPLAY=:0 MXTK_NO_REPORT_OPEN=1
[ "$(opens)" = 0 ] && [ ! -e "$A4/.claude/.report-shown" ] && ok "MXTK_NO_REPORT_OPEN=1 in the environment: opt-out" || bad "env opt-out"
A5="$(newproj a5)"; printf 'MXTK_NO_REPORT_OPEN=1\n' > "$A5/.claude/toolkit.env"; refresh "$A5" MXTK_PLATFORM=linux DISPLAY=:0
[ "$(opens)" = 0 ] && ok "MXTK_NO_REPORT_OPEN=1 in .claude/toolkit.env: opt-out" || bad "toolkit.env opt-out"
A6="$(newproj a6)"; printf '# P\n\nProgress report: off\n' > "$A6/PROJECT.md"; refresh "$A6" MXTK_PLATFORM=linux DISPLAY=:0
[ "$(opens)" = 0 ] && [ ! -f "$A6/architecture/progress-report.html" ] && ok "Progress report: off writes no page and opens nothing" || bad "setting off"
X1="$(newproj ask)"; printf '# P\n\nProgress report: ask\n' > "$X1/PROJECT.md"; refresh "$X1" MXTK_PLATFORM=linux DISPLAY=:0
[ "$(opens)" = 0 ] && [ -f "$X1/architecture/progress-report.html" ] && [ ! -e "$X1/.claude/.report-shown" ] && ok "Progress report: ask writes the page and opens nothing by itself" || bad "ask opens ($(opens))"
X2="$(newproj dflt)"; printf '# P\n\nNo setting line here\n' > "$X2/PROJECT.md"; refresh "$X2" MXTK_PLATFORM=linux DISPLAY=:0
[ "$(opens)" = 0 ] && ok "no Progress report line (default ask): nothing opens" || bad "default opens"
X3="$(newproj tmpdir)"; : > "$LOG"; env -i HOME="$WORK/home" PATH="$STUB:/usr/bin:/bin" CLAUDE_CONFIG_DIR="$EMPTY" MXTK_PLATFORM=linux DISPLAY=:0 TMPDIR="$WORK" bash "$SCRIPT" "$X3" --refresh >/dev/null 2>&1; sleep 0.4
[ "$(opens)" = 0 ] && [ ! -e "$X3/.claude/.report-shown" ] && ok "a project in the temp folder never opens by itself (a fixture or scratch run is safe by default)" || bad "temp-folder rule"
# the temp-folder test, on the rule itself: macOS per-user temp, Git Bash /tmp, and normal folders that merely contain "tmp"
for r in /tmp/x/proj /var/folders/ab/cd/T/x/proj /private/var/folders/ab/cd/T/x/proj /var/tmp/x /c/Users/u/AppData/Local/Temp/x/proj /mnt/c/Users/u/AppData/Local/Temp/x/proj; do
  [ "$(env -u CI -u GITHUB_ACTIONS -u MXTK_NO_REPORT_OPEN -u SSH_CONNECTION -u SSH_TTY -u SSH_CLIENT bash -c 'ROOT="$1"; TMPDIR=""; MXTK_REPORT_OPEN_TMP=""; eval "$(sed -n "/^report_auto_ok() {/,/^}/p" "$2")"; report_pm_value() { case "$1" in "Progress report") _pmv=auto ;; *) _pmv= ;; esac; }; report_auto_ok && echo open || echo skip' _ "$r" "$SCRIPT")" = skip ] && ok "temp rule: $r never auto-opens" || bad "temp rule $r"
done
for r in /home/u/tmp/proj /home/u/my-tmp/proj /home/u/work/tmpfiles/proj /Users/u/tmp /home/u/proj-temp /mnt/c/Users/u/proj /mnt/c/Users/u/AppData/Local/proj; do
  [ "$(env -u CI -u GITHUB_ACTIONS -u MXTK_NO_REPORT_OPEN -u SSH_CONNECTION -u SSH_TTY -u SSH_CLIENT bash -c 'ROOT="$1"; TMPDIR=""; MXTK_REPORT_OPEN_TMP=""; eval "$(sed -n "/^report_auto_ok() {/,/^}/p" "$2")"; report_pm_value() { case "$1" in "Progress report") _pmv=auto ;; *) _pmv= ;; esac; }; report_auto_ok && echo open || echo skip' _ "$r" "$SCRIPT")" = open ] && ok "temp rule: $r (a normal folder that merely contains tmp) is not treated as temp" || bad "temp rule misfires on $r"
done
X4="$(newproj ssh)"; refresh "$X4" MXTK_PLATFORM=linux DISPLAY=:0 SSH_CONNECTION="1 2 3 4"
[ "$(opens)" = 0 ] && ok "over SSH: no automatic open" || bad "ssh opens"
X5="$(newproj unatt)"; printf '\nInterview mode: auto\n' >> "$X5/PROJECT.md"; refresh "$X5" MXTK_PLATFORM=linux DISPLAY=:0
[ "$(opens)" = 0 ] && ok "Interview mode: auto: no automatic open" || bad "interview auto opens"
X6="$(newproj ro)"; rm -rf "$X6/.claude"; : > "$X6/.claude"; refresh "$X6" MXTK_PLATFORM=linux DISPLAY=:0
[ "$(opens)" = 0 ] && ok "a .claude that cannot hold the sentinel: no open (it would reopen every run)" || bad "unwritable sentinel opens"
X7="$(newproj claim)"; mkdir -p "$X7/.claude"; CLAIMS="$WORK/claims"; : > "$CLAIMS"
for i in 1 2 3 4 5 6 7 8; do ( bash -c 'ROOT="$1"; REPORT_SENTINEL="$1/.claude/.report-shown"; eval "$(sed -n "/^report_claim()/,/^}/p" "$2")"; report_claim && echo won' _ "$X7" "$SCRIPT" >> "$CLAIMS" ) & done; wait
[ "$(grep -c won "$CLAIMS")" = 1 ] && ok "eight parallel claims of the sentinel: exactly one wins" || bad "parallel claim ($(grep -c won "$CLAIMS"))"
M="$(newproj mac)"; refresh "$M" MXTK_PLATFORM=macos
[ "$(opens)" = 1 ] && grep -q "^open .*progress-report.html" "$LOG" && ok "macOS branch: open" || bad "macos ($(cat "$LOG"))"
W="$(newproj win)"; refresh "$W" MXTK_PLATFORM=windows
[ "$(opens)" = 1 ] && grep -q 'cmd.exe /c start  C:\\win\\progress-report.html' "$LOG" && ok "Git Bash branch: cmd.exe /c start with the Windows path" || bad "windows ($(cat "$LOG"))"
L="$(newproj wsl)"; refresh "$L" MXTK_PLATFORM=linux WSL_DISTRO_NAME=Test
[ "$(opens)" = 1 ] && grep -q '^wslview ' "$LOG" && ok "WSL branch: wslview" || bad "wsl wslview ($(cat "$LOG"))"
L2="$(newproj wsl2)"; mv "$STUB/wslview" "$STUB/wslview.off"; refresh "$L2" MXTK_PLATFORM=linux WSL_DISTRO_NAME=Test; mv "$STUB/wslview.off" "$STUB/wslview"
[ "$(opens)" = 1 ] && grep -q 'explorer.exe .*wsl.*progress-report.html' "$LOG" && ok "WSL without wslview: explorer.exe with a wslpath-converted path" || bad "wsl explorer ($(cat "$LOG"))"
F="$(newproj fail)"; refresh "$F" MXTK_PLATFORM=linux DISPLAY=:0 STUB_RC=1
[ "$RC" = 0 ] && [ -e "$F/.claude/.report-shown" ] && ok "a failing opener: the run still exits 0 and the attempt is recorded" || bad "failing opener (rc=$RC)"
: > "$LOG"; env -i HOME="$WORK/home" PATH="$STUB:/usr/bin:/bin" CLAUDE_CONFIG_DIR="$EMPTY" MXTK_PLATFORM=linux DISPLAY=:0 CI=1 MXTK_NO_REPORT_OPEN=1 bash "$SCRIPT" "$A" --open >/dev/null 2>&1; sleep 0.6
[ "$(opens)" = 1 ] && ok "an explicit --open ignores the sentinel, CI and the opt-out" || bad "explicit open ($(opens))"
: > "$LOG"; env -i HOME="$WORK/home" PATH="$STUB:/usr/bin:/bin" CLAUDE_CONFIG_DIR="$EMPTY" MXTK_PLATFORM=linux bash "$SCRIPT" "$A" --open >/dev/null 2>&1
[ "$(opens)" = 0 ] && ok "an explicit --open with no display opens nothing and does not fail" || bad "explicit headless"

# ── D7 / D8 ──────────────────────────────────────────────────────────────────
echo "D7 no absolute paths; D8 words explained, zeros gone, one no-log paragraph"
P7="$WORK/p7"; mkproj "$P7"; ABS="$(cd "$P7" && pwd -P)"
R7="$WORK/r7.html"; CLAUDE_CONFIG_DIR="$EMPTY" "$PY" "$GEN" "$P7" --out "$R7" >/dev/null 2>&1
hasnt "$R7" "$ABS" "the project's own absolute root is not on the page"
hasnt "$R7" "$P7" "nor the unresolved spelling of it"
CLAUDE_CONFIG_DIR="$EMPTY" HOME=/home/fixture-user "$PY" "$GEN" "$P7" --out "$R7" >/dev/null 2>&1
hasnt "$R7" "/home/fixture-user" "the running user's home is gone"
has "$R7" "see ~/secret/x.md" "... and shown as ~/"
has "$R7" "GET /Users/123/orders fails" "an app route /Users/123/orders is content and survives"
has "$R7" "route /home/dashboard opens" "an app route /home/dashboard survives"
has "$R7" "in triage.md\|unanswered in triage.md" "the project root became a relative path"
CLAUDE_CONFIG_DIR="$EMPTY" HOME='C:\Users\fixtureuser' "$PY" "$GEN" "$P7" --out "$WORK/r7w.html" >/dev/null 2>&1
grep -qF 'fixtureuser' "$WORK/r7w.html" && bad "a C:\\Users home spelling is not on the page" || ok "a C:\\Users home spelling is not on the page"
"$PY" - "$GEN" <<'PYEOF' && ok "scrub: the home and toolkit slugs in a session-log folder name are masked; href values are never rewritten" || bad "scrub unit cases"
import importlib.util, os, sys
os.environ["HOME"] = "/home/fixture-user"
spec = importlib.util.spec_from_file_location("pr", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
t = m.scrub_paths("<code>/home/fixture-user/.claude/projects/-home-fixture-user-other/s.jsonl</code> <a href='/home/fixture-user/x'>l</a> /tmp/zz/proj/a.md", "/tmp/zz/proj")
assert "fixture-user" not in t.replace("href='/home/fixture-user/x'", ""), t
assert "-~-other" in t and "~/.claude/projects" in t, t
assert "href='/home/fixture-user/x'" in t, t
assert "a.md" in t and "/tmp/zz/proj" not in t, t
PYEOF
has "$R7" "<details class=gloss" "the word block is present"
for term in "<dt>Gate</dt>" "<dt>Row</dt>" "<dt>Kind: BRIEF, BUILD, PROVE</dt>" "<dt>Owed and missing</dt>" "<dt>Bar capped at 95%</dt>"; do has "$R7" "$term" "defined: $term"; done
hasnt "$R7" "<dt>Compaction</dt>" "a word the page does not use is not defined"
[ "$(grep -o 'No Claude Code session log was found' "$R7" | wc -l | tr -d ' ')" = 1 ] && ok "the no-session-log sentence appears once" || bad "no-log sentence count $(grep -o 'No Claude Code session log was found' "$R7" | wc -l)"
hasnt "$R7" "0 confirmed" "no all-zero decisions line"
hasnt "$R7" "0 more files" "no '0 more files'"
# with a session log: a finished stage with no time, tokens or decisions prints none of those lines
"$PY" - "$EMPTY" "$ABS" <<'PYEOF'
import json, sys, os, time, re
cfg, proj = sys.argv[1], sys.argv[2]
slug = re.sub(r"[^A-Za-z0-9]", "-", proj); d = os.path.join(cfg, "projects", slug); os.makedirs(d, exist_ok=True)
now = time.time(); rows = []
import datetime
iso = lambda t: datetime.datetime.fromtimestamp(t, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
for k in range(6):
    rows.append({"type": "assistant", "timestamp": iso(now - 600 + k * 30), "cwd": proj, "uuid": "a%d" % k, "message": {"id": "m%d" % k, "model": "claude-sonnet-5-5", "role": "assistant",
      "content": [{"type": "tool_use", "id": "t%d" % k, "name": "Bash", "input": {"command": "bash %s/bin/exec.sh 01.mdl" % proj}}], "usage": {"input_tokens": 100, "output_tokens": 50, "cache_read_input_tokens": 1000, "cache_creation_input_tokens": 10}}})
open(os.path.join(d, "s1.jsonl"), "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
PYEOF
R8="$WORK/r8.html"; CLAUDE_CONFIG_DIR="$EMPTY" "$PY" "$GEN" "$P7" --out "$R8" >/dev/null 2>&1
SLUG="$(printf '%s' "$ABS" | sed 's/[^A-Za-z0-9]/-/g')"
hasnt "$R8" "$SLUG" "the session-log folder name (the project's path with dashes) is masked"
has "$R8" "projects/-project/s1.jsonl" "... as -project"
"$PY" - "$R8" <<'PYEOF' && ok "log present: finished stages show only what has content; the stage with data keeps its lines" || bad "zero lines (log present)"
import re, sys
h = open(sys.argv[1], encoding="utf-8").read()
cards = re.findall(r"<div class='card stage (\w+)' id='stage-(\w+)'>(.*?)(?=<div class='card stage |</div></section>)", h, re.S)
assert len(cards) >= 7, len(cards)
passed = [c for c in cards if c[0] == "passed"]; assert passed, "no passed card"
empty = [c for c in passed if "<dt>Wall time</dt>" not in c[2]]
assert empty, "no passed card without time data"
for st, sid, body in empty:
    for bad_ in ("Wall time", "New tokens", "Main context", "Sub-agents", "none (0s", "0 confirmed", "no html artifact yet", "Token breakdown"):
        assert bad_ not in body, (sid, bad_)
assert any("<dt>Wall time</dt>" in c[2] for c in cards), "a stage with data keeps its Wall time line"
PYEOF
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
