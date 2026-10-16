#!/usr/bin/env bash
# test-progress-report.sh: pin project-bin/build-plan-status.sh --html, which writes
# architecture/progress-report.html (the replacement for architecture/build-plan.html), and the
# generator project-bin/progress-report.py behind it. Every name, path and number below is invented.
#
#   T1  no session log: the page is written, project sections render, and it says that time and
#       token data are unavailable. No Tips section.
#   T2  with a synthetic session log: Tips and tricks, Run health strip, Speed panel appear.
#   T3  hanging process detector fires (a call far past its tool's median) and names the script.
#   T4  repeat failure detector fires and names the script and the count (4).
#   T5  health strip: red, with the failing key script counts shown.
#   T6  no message text from the log is copied into the page (a canary in prompt and result text).
#   T7  "Progress report: off" in PROJECT.md writes nothing.
#   T8  an existing architecture/build-plan.html is never deleted, and gate-check and status.sh
#       do not fail because of it (checked on the surface lookup only, see the grep below).
#   T9  the 30 s self-reload is present only while a build is active (recent activity).
#
# Usage: bash tests/wave2/test-progress-report.sh /path/to/build-plan-status.sh

set -uo pipefail
SCRIPT="${1:?usage: bash tests/wave2/test-progress-report.sh /path/to/build-plan-status.sh}"
case "$SCRIPT" in /*) ;; *) SCRIPT="$PWD/$SCRIPT" ;; esac
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/progress-report.XXXXXX")"
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

mkproj() {  # dir
  mkdir -p "$1/architecture" "$1/mdlsource"
  cat > "$1/architecture/build-plan.md" <<'MD'
# Build plan

### Phase 1 - Orders

| Step | Do | Produces | Test | Depends | State | Script |
|---|---|---|---|---|---|---|
| 1 | Create entity | Order | none | none | built | mdlsource/01-orders/done-01-order.mdl |
MD
  mkdir -p "$1/mdlsource/01-orders"; : > "$1/mdlsource/01-orders/done-01-order.mdl"
}

# Synthetic session log: a main thread with two exec.sh slices, a gate-check that fails 6 times,
# one command that hangs for 700 s, and a canary string in prompt and result text.
mklog() {  # configdir projdir
  local proj="$2" slug; slug="$(printf '%s' "$(cd "$2" && pwd -P)" | sed 's/[^A-Za-z0-9]/-/g')"
  mkdir -p "$1/projects/$slug"
  "$PY" - "$1/projects/$slug/s1.jsonl" "$(cd "$proj" && pwd -P)" "$3" <<'PYEOF'
import json, sys, time, datetime, os
CR = int(os.environ.get("CTX_CR", "20000")); MODEL = os.environ.get("CTX_MODEL", "claude-sonnet-5-5")
out, cwd, base = sys.argv[1], sys.argv[2], float(sys.argv[3])
rows = []; n = [0]
def iso(t): return datetime.datetime.fromtimestamp(t, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
def asst(t, blocks, tin=100, cr=None):
    cr = CR if cr is None else cr
    n[0] += 1
    rows.append({"type": "assistant", "timestamp": iso(t), "cwd": cwd, "uuid": "a%d" % n[0], "message": {"id": "m%d" % n[0], "model": MODEL, "role": "assistant",
                 "content": blocks, "usage": {"input_tokens": tin, "output_tokens": 300, "cache_read_input_tokens": cr, "cache_creation_input_tokens": 500}}})
def res(t, tid, text, err=False):
    rows.append({"type": "user", "timestamp": iso(t), "cwd": cwd, "uuid": "u%d" % n[0], "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": tid, "content": text, "is_error": err}]}})
rows.append({"type": "user", "timestamp": iso(base), "cwd": cwd, "uuid": "u0", "message": {"role": "user", "content": "CANARY-PROMPT-TEXT please start"}})
t = base + 5; i = 0
def call(cmd, dur, err=False, text="ok"):
    global t, i
    i += 1; tid = "t%d" % i
    asst(t, [{"type": "tool_use", "id": tid, "name": "Bash", "input": {"command": cmd}}])
    res(t + dur, tid, ("Exit code 1\nCANARY-RESULT-TEXT" if err else text), err); t += dur + 4
for k in range(8): call("bash ./bin/doctor.sh", 3)
call("bash ./exec.sh slice-1", 40)
for k in range(6): call("bash ./bin/gate-check.sh . 2", 6, err=True)
call("bash ./exec.sh slice-2", 45)
call("bash ./bin/build-all.sh", 700)
call("bash ./exec.sh slice-3", 50)
for k in range(5): call("ls architecture", 1)
with open(out, "w") as f:
    for r in rows: f.write(json.dumps(r) + "\n")
PYEOF
}

echo "T1 no session log"
P1="$WORK/p1"; mkproj "$P1"; EMPTY="$WORK/emptycfg"; mkdir -p "$EMPTY/projects"
CLAUDE_CONFIG_DIR="$EMPTY" bash "$SCRIPT" "$P1" --html >/dev/null 2>&1
R1="$P1/architecture/progress-report.html"
[ -f "$R1" ] && ok "progress-report.html written" || bad "progress-report.html written"
has "$R1" "Orders" "plan content present"
has "$R1" "unavailable" "says time and token data are unavailable"
hasnt "$R1" 'id=tips' "no Tips section without a log"

echo "T2-T6 with a session log"
P2="$WORK/p2"; mkproj "$P2"; CFG="$WORK/cfg"; mklog "$CFG" "$P2" "$(( $("$PY" -c 'import time;print(int(time.time()))') - 7200 ))"
CLAUDE_CONFIG_DIR="$CFG" bash "$SCRIPT" "$P2" --html >/dev/null 2>&1
R2="$P2/architecture/progress-report.html"
has "$R2" 'id=tips' "Tips and tricks section present"
has "$R2" "Run health" "Run health strip present"
has "$R2" ">Speed<\|<b>Speed</b>" "Speed panel present"
has "$R2" "Hanging or killed commands" "hanging process tip fires"
has "$R2" "build-all.sh" "hanging tip names the script"
has "$R2" "Failing tool on repeat: gate-check.sh 2" "repeat failure tip fires and names the script"
has "$R2" "failed 6 of 6 runs" "repeat failure count is 6"
has "$R2" "p-red" "health strip is red"
has "$R2" "gate-check 0/6 passing" "health strip counts gate-check runs"
hasnt "$R2" "Waiting on the user" "an inherent tip (waiting on the user, 70% of this log) is never shown"
hasnt "$R2" "Model mix" "an inherent tip (model mix) is never shown"
[ "$(grep -o '<details class=grp' "$R2" | wc -l)" -ge 2 ] && ok "tip groups are details elements" || bad "tip groups are details elements"
[ "$(grep -c '<details class=grp open' "$R2")" -eq 0 ] && ok "every group is collapsed by default" || bad "every group is collapsed by default"
has "$R2" "<b>Health</b>" "Health group shown (it has tips)"
hasnt "$R2" "<b>Sub-agents</b>" "empty Sub-agents group hidden"
hasnt "$R2" "<b>Context</b>" "empty Context group hidden (context well under the window)"
grep -qw "RED" "$R2" && bad "the word RED is never printed" || ok "the word RED is never printed"
has "$R2" "Needs action" "severe state reads Needs action"
has "$R2" "class=side id=tips" "tips live in the side column"
hasnt "$R2" "CANARY" "no prompt or result text copied into the page"
hasnt "$R2" "http-equiv=.refresh\|setTimeout(.*location" "no self-reload when the log is two hours old" 

echo "T6b page name comes from one constant"
[ "$("$PY" "$ROOT/project-bin/progress-report.py" --print-name)" = "progress-report.html" ] && ok "--print-name gives the page name" || bad "--print-name gives the page name"

echo "T6c context window per model, never over 100 percent"
P6="$WORK/p6"; mkproj "$P6"; CFG6="$WORK/cfg6"; CTX_CR=250000 mklog "$CFG6" "$P6" "$(( $("$PY" -c 'import time;print(int(time.time()))') - 7200 ))"
CLAUDE_CONFIG_DIR="$CFG6" bash "$SCRIPT" "$P6" --html >/dev/null 2>&1
R6="$P6/architecture/progress-report.html"
has "$R6" "raised from 200" "a context above the assumed 200k window raises the window"
grep -Eq "(1[0-9][0-9]|[2-9][0-9][0-9])% (avg|peak)" "$R6" && bad "no window percentage over 100" || ok "no window percentage over 100"
has "$R6" "<b>Context</b>" "Context group shown when average context is 180k or more"
P7="$WORK/p7"; mkproj "$P7"; CFG7="$WORK/cfg7"; CTX_MODEL=mystery-model CTX_CR=250000 mklog "$CFG7" "$P7" "$(( $("$PY" -c 'import time;print(int(time.time()))') - 7200 ))"
CLAUDE_CONFIG_DIR="$CFG7" bash "$SCRIPT" "$P7" --html >/dev/null 2>&1
has "$P7/architecture/progress-report.html" "window unknown" "a model missing from the table reads window unknown"

echo "T6d footer records the inputs; title"
has "$R2" "<b>Inputs.</b> Project folder" "footer names the project folder"
has "$R2" "s1.jsonl" "footer names the session log path"
has "$R2" "<title>Progress report" "page title is Progress report"

echo "T7 off writes nothing"
P3="$WORK/p3"; mkproj "$P3"; printf '# Project\n\nProgress report: off\n' > "$P3/PROJECT.md"
CLAUDE_CONFIG_DIR="$EMPTY" bash "$SCRIPT" "$P3" --html >/dev/null 2>&1
[ ! -f "$P3/architecture/progress-report.html" ] && ok "off writes no page" || bad "off writes no page"

echo "T8 build-plan.html back-compat"
P4="$WORK/p4"; mkproj "$P4"; echo "<html>mine</html>" > "$P4/architecture/build-plan.html"
CLAUDE_CONFIG_DIR="$EMPTY" bash "$SCRIPT" "$P4" --html >/dev/null 2>&1
[ "$(cat "$P4/architecture/build-plan.html")" = "<html>mine</html>" ] && ok "user's build-plan.html left alone" || bad "user's build-plan.html left alone"
if [ -x "$ROOT/bin/gate-check.sh" ]; then
  out="$(bash "$ROOT/bin/gate-check.sh" "$P4" 4 2>&1 || true)"
  printf '%s\n' "$out" | grep "^Stage 4" | grep -q "Surface present" && ok "gate-check Stage 4 Surface accepts the older build-plan.html" || bad "gate-check Stage 4 Surface accepts the older build-plan.html"
  printf '%s' "$out" | grep -q "Traceback\|syntax error" && bad "gate-check does not crash on build-plan.html" || ok "gate-check does not crash on build-plan.html"
fi

echo "T9 self-reload only while active"
P5="$WORK/p5"; mkproj "$P5"; CFG2="$WORK/cfg2"; mklog "$CFG2" "$P5" "$(( $("$PY" -c 'import time;print(int(time.time()))') - 60 ))"
touch "$P5/architecture/build-plan.md"
CLAUDE_CONFIG_DIR="$CFG2" bash "$SCRIPT" "$P5" --html >/dev/null 2>&1
has "$P5/architecture/progress-report.html" "location.reload" "reload script present while active"
hasnt "$R2" "location.reload" "no reload script when idle"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
