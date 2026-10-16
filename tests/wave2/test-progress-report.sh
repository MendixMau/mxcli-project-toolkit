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
#   T10 a plain (non-workflow) sub-agent renders, context percentages never pass 100, window_for exists.
#   T11 calm severity: red only for a key script failing every run (3 or more) or a hang over 30 min.
#   T12 repeat-failure tip ignores cd and sleep; inherent waits (AskUserQuestion) are not slow steps.
#   T13 context windows are 200k or 1M only; "window reached" only at 98% of the real window.
#   T14 --session-log overrides discovery and is recorded in the footer; --help lists it and the rates file.
#   T15 --open matches this project's exact file URL (osascript stubbed); a generator crash leaves one WARN.
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
HANG = int(os.environ.get("HANG_S", "700")); CALLS = json.loads(os.environ.get("CALLS_JSON", "null"))
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
def call(cmd, dur, err=False, text="ok", name="Bash"):
    global t, i
    i += 1; tid = "t%d" % i
    asst(t, [{"type": "tool_use", "id": tid, "name": name, "input": ({"command": cmd} if name == "Bash" else {"questions": []})}])
    res(t + dur, tid, ("Exit code 1\nCANARY-RESULT-TEXT" if err else text), err); t += dur + 4
if CALLS is not None:
    for c_ in CALLS: call(c_[0], c_[1], bool(c_[2]))
else:
    for k in range(8): call("bash ./bin/doctor.sh", 3)
    call("bash ./exec.sh slice-1", 40)
    for k in range(6): call("bash ./bin/gate-check.sh . 2", 15, err=True)
    call("bash ./exec.sh slice-2", 45)
    call("bash ./bin/import-data.sh", HANG)
    call("bash ./exec.sh slice-3", 50)
    for k in range(5): call("ls architecture", 1)
    for k in range(4): call("cd /tmp/no-such-dir", 1, err=True)
    for k in range(3): call("sleep 1", 1, err=True)
    for k in range(4): call("./bin/convert-data.py", 80)
    call("", 420, name="AskUserQuestion")
for pre in [x for x in os.environ.get("COMPACT_PRE", "").split(",") if x]:
    rows.append({"type": "system", "subtype": "compact_boundary", "timestamp": iso(t), "cwd": cwd, "uuid": "c%s" % pre, "compactMetadata": {"trigger": "auto", "preTokens": int(pre), "postTokens": 30000}})
if os.environ.get("CTX_BETA"): rows.append({"type": "system", "timestamp": iso(t), "cwd": cwd, "uuid": "b1", "params": {"betas": ["claude-code-20250219", "context-1m-2025-08-07"]}})
with open(out, "w") as f:
    for r in rows: f.write(json.dumps(r) + "\n")
if CALLS is None:   # one ordinary sub-agent (not a workflow agent), with a context above 200k
    sd = out[:-6] + "/subagents"; os.makedirs(sd, exist_ok=True)
    rows = []; n[0] = 100
    asst(base + 100, [{"type": "text", "text": "x"}], cr=230000); asst(base + 160, [{"type": "text", "text": "x"}], cr=235000)
    with open(sd + "/agent-aaa.jsonl", "w") as f:
        for r in rows: f.write(json.dumps(r) + "\n")
    json.dump({"description": "Plain helper agent"}, open(sd + "/agent-aaa.meta.json", "w"))
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
has "$R2" "<b>Speed</b>" "Speed group present (it has a tip: convert-data.py is slow on every run)"
has "$R2" "Slow on every run: convert-data.py" "slow non-toolkit script is a Speed tip"
hasnt "$R2" "<li>AskUserQuestion" "an interview (AskUserQuestion) is not among the slowest calls"
hasnt "$R2" "<b>Speed</b> <span class=muted>0" "no Speed 0"
has "$R2" "Hanging or killed commands" "hanging process tip fires"
has "$R2" "import-data.sh" "hanging tip names the script"
has "$R2" "Failing tool on repeat: gate-check.sh 2" "repeat failure tip fires and names the script"
has "$R2" "failed 6 of 6 runs" "repeat failure count is 6"
has "$R2" "pill p-red" "health strip is red (gate-check fails on every run)"
has "$R2" "gate-check 0/6 passing" "health strip counts gate-check runs"
hasnt "$R2" "Waiting on the user" "an inherent tip (waiting on the user, 70% of this log) is never shown"
hasnt "$R2" "Model mix" "an inherent tip (model mix) is never shown"
[ "$(grep -o '<details class=grp' "$R2" | wc -l)" -ge 2 ] && ok "tip groups are details elements" || bad "tip groups are details elements"
[ "$(grep -c '<details class=grp open' "$R2")" -eq 0 ] && ok "every group is collapsed by default" || bad "every group is collapsed by default"
has "$R2" "<b>Health</b>" "Health group shown (it has tips)"
hasnt "$R2" "<b>Sub-agents</b> <span class=muted>0" "no empty group printed with a count of 0"
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
has "$R6" "inferred" "a context above 200k with no marker is labelled inferred"
grep -Eq "(10[1-9]|1[1-9][0-9]|[2-9][0-9][0-9])% (avg|peak)" "$R6" && bad "no window percentage over 100" || ok "no window percentage over 100"
has "$R6" "<b>Context</b>" "Context group shown when average context is 180k or more"
P7="$WORK/p7"; mkproj "$P7"; CFG7="$WORK/cfg7"; CTX_MODEL=mystery-model CTX_CR=250000 mklog "$CFG7" "$P7" "$(( $("$PY" -c 'import time;print(int(time.time()))') - 7200 ))"
CLAUDE_CONFIG_DIR="$CFG7" bash "$SCRIPT" "$P7" --html >/dev/null 2>&1
has "$P7/architecture/progress-report.html" "window unknown" "a model missing from the table reads window unknown"

echo "T10 plain sub-agent (window_for), percentages capped"
has "$R2" "Plain helper agent" "plain sub-agent listed"
has "$R2" "pill p-red" "page still rendered around it"
grep -Eq '\((10[1-9]|1[1-9][0-9]|[2-9][0-9][0-9])%\)|NameError' "$R2" && bad "no percentage over 100 in the sub-agent table" || ok "no percentage over 100 in the sub-agent table"
"$PY" - "$ROOT/project-bin" <<'PYEOF' && ok "window_for caps and steps 200k to 1M" || bad "window_for caps and steps 200k to 1M"
import sys, importlib.util
sp = importlib.util.spec_from_file_location("pr", sys.argv[1] + "/progress-report.py"); m = importlib.util.module_from_spec(sp); sp.loader.exec_module(m)
assert m.window_for("claude-sonnet-5-5") == 200000 and m.window_for("claude-sonnet-5-5", 230000) == 1000000
assert m.window_for("mystery") is None and m.window_for("claude-x", 5000000) is None
assert m.ctx_pct(5000000, 200000) == 100.0 and m.ctx_pct(1, None) is None
assert m.KNOWN_WINDOWS == (200000, 1000000) and sorted(w for _, w in m.WINDOWS) == [200000, 1000000]
PYEOF

echo "T11 calm severity"
run_sev() {  # name calls_json
  local d="$WORK/sev-$1" cfg="$WORK/cfg-$1"; mkproj "$d"
  CALLS_JSON="$2" mklog "$cfg" "$d" "$(( $("$PY" -c 'import time;print(int(time.time()))') - 7200 ))"
  CLAUDE_CONFIG_DIR="$cfg" bash "$SCRIPT" "$d" --html >/dev/null 2>&1
  RP="$d/architecture/progress-report.html"
}
Q='["ls",1,0],["ls",1,0],["ls",1,0],["ls",1,0],["ls",1,0]'
run_sev d12 '[["bash ./bin/doctor.sh",3,0],["bash ./bin/doctor.sh",3,1],'"$Q"']'
has "$RP" "doctor 1/2 passing" "doctor 1 of 2 counted"
has "$RP" "pill p-amber" "doctor failing 1 of 2 is amber"
hasnt "$RP" "pill p-red" "doctor failing 1 of 2 is not red"
hasnt "$RP" "Needs action" "no Needs action wording for amber"
has "$RP" "Worth a look" "amber reads Worth a look"
run_sev d22 '[["bash ./bin/doctor.sh",3,1],["bash ./bin/doctor.sh",3,1],'"$Q"']'
hasnt "$RP" "pill p-red" "a key script failing all 2 runs is not red (needs 3 runs)"
run_sev d33 '[["bash ./bin/doctor.sh",3,1],["bash ./bin/doctor.sh",3,1],["bash ./bin/doctor.sh",3,1],'"$Q"']'
has "$RP" "pill p-red" "a key script failing all 3 runs is red"
has "$RP" "Needs action" "red reads Needs action"
run_sev d11 '[["bash ./bin/doctor.sh",3,1],'"$Q"']'
hasnt "$RP" "pill p-red" "a key script with a single failing run is not red"
run_sev h400 '[["bash ./bin/import-data.sh",400,0],'"$Q"']'
hasnt "$RP" "pill p-red\|pill p-amber" "a 400 s hang leaves the strip green"
run_sev h700 '[["bash ./bin/import-data.sh",700,0],'"$Q"']'
has "$RP" "pill p-amber" "a hang over 10 minutes is amber"
hasnt "$RP" "pill p-red" "a 700 s hang is not red"
run_sev h1900 '[["bash ./bin/import-data.sh",1900,0],'"$Q"']'
has "$RP" "pill p-red" "a hang over 30 minutes is red"
run_sev hmany '[["bash ./bin/import-data.sh",400,0],["bash ./bin/import-data.sh",400,0],["bash ./bin/import-data.sh",400,0],'"$Q"']'
hasnt "$RP" "pill p-red" "three 400 s hangs are not red: duration counts, not count"

echo "T12 repeat failures ignore builtins; interviews are not slow steps"
hasnt "$R2" "cd x[0-9]" "cd is never a repeat-failure tip"
hasnt "$R2" "sleep x[0-9]" "sleep is never a repeat-failure tip"
has "$R2" "Failing tool on repeat: gate-check.sh 2" "the real failing script is still named"

echo "T13 context windows"
hasnt "$R6" "500" "no invented 500k window"
mkproj "$WORK/p13"; CTX_CR=199000 mklog "$WORK/cfg13" "$WORK/p13" "$(( $("$PY" -c 'import time;print(int(time.time()))') - 7200 ))"
CLAUDE_CONFIG_DIR="$WORK/cfg13" bash "$SCRIPT" "$WORK/p13" --html >/dev/null 2>&1
has "$WORK/p13/architecture/progress-report.html" "Context: the window was reached" "199k of 200k reads window reached"
has "$WORK/p13/architecture/progress-report.html" "200.0k window, 100% avg\|200.0k window, 99% avg" "and the numbers say so"

echo "T16 context window from the log: marker, else 200k, never 1M from a peak when compacted; inherent hangs; layout"
run_ctx() {  # name env...
  local n="$1"; shift; local d="$WORK/c-$n"; mkproj "$d"
  ( export "$@"; mklog "$WORK/cfgc-$n" "$d" "$(( $("$PY" -c 'import time;print(int(time.time()))') - 7200 ))" )
  CLAUDE_CONFIG_DIR="$WORK/cfgc-$n" bash "$SCRIPT" "$d" --html >/dev/null 2>&1
  RC_="$d/architecture/progress-report.html"
}
run_ctx comp CTX_CR=230000 COMPACT_PRE=226800,217200
has "$RC_" "inferred: no 1M marker" "200k+ usage with auto compactions: window labelled inferred"
hasnt "$RC_" "1.00M" "200k+ usage with auto compactions near 220k is never 1M"
has "$RC_" "Context: " "a Context tip fires when compactions happened"
grep -Eq "(10[1-9]|1[1-9][0-9]|[2-9][0-9][0-9])% (avg|peak)" "$RC_" && bad "percentages capped at 100 (compacted log)" || ok "percentages capped at 100 (compacted log)"
run_ctx beta CTX_CR=250000 CTX_BETA=1
has "$RC_" "1.00M window" "a context-1m beta in the log gives a 1M window"
hasnt "$RC_" "inferred" "a window read from the log is not labelled inferred"
run_ctx m1m CTX_CR=250000 CTX_MODEL='claude-opus-5-5[1m]'
has "$RC_" "1.00M window" "a [1m] model id gives a 1M window"
run_ctx plain CTX_CR=20000
hasnt "$RC_" "inferred" "a plain 200k log is not inferred"
hasnt "$RC_" "<b>Context</b>" "no context flag under 180k average without compaction"
# inherent scripts never hang: a 40 min gate-check and a 15 min build leave health green and no hang tip
run_sev inh '[["bash ./bin/gate-check.sh . 2",2400,0],["bash ./bin/build-all.sh",900,0],'"$Q"']'
hasnt "$RP" "Hanging or killed" "gate-check and build hangs never produce a hang tip"
hasnt "$RP" "pill p-red\|pill p-amber" "inherent scripts never change Run health colour"
# tips name real scripts only, and drop tips that lose under a minute
run_sev tok '[["JH run x",1,1],["JH run x",1,1],["JH run x",1,1],["./bin/tiny.sh",2,1],["./bin/tiny.sh",2,1],["./bin/tiny.sh",2,1],'"$Q"']'
hasnt "$RP" "JH x" "a non-script token is never named in a tip"
hasnt "$RP" "Failing tool on repeat: tiny.sh" "a repeat failure losing 6 s is not shown"
# layout: header wraps with nowrap count; the aside is not moved above the content
has "$R2" "\.hd{display:flex;flex-wrap:wrap" "stage header box wraps"
has "$R2" "\.hd \.sub{white-space:nowrap" "gates-passed text stays on one line"
hasnt "$R2" "order:-1" "tips are not moved above the title on a phone"

echo "T14 --session-log"
P14="$WORK/p14"; mkproj "$P14"; mklog "$WORK/cfg14" "$P14" "$(( $("$PY" -c 'import time;print(int(time.time()))') - 7200 ))"
LOGF="$(ls "$WORK"/cfg14/projects/*/s1.jsonl)"
mkdir -p "$WORK/elsewhere"; cp "$LOGF" "$WORK/elsewhere/s9.jsonl"; cp -R "${LOGF%.jsonl}" "$WORK/elsewhere/s9"
EMPTY14="$WORK/cfg14empty"; mkdir -p "$EMPTY14/projects"
CLAUDE_CONFIG_DIR="$EMPTY14" bash "$SCRIPT" "$P14" --html >/dev/null 2>&1
hasnt "$P14/architecture/progress-report.html" 'id=tips' "no log discovered without the option"
CLAUDE_CONFIG_DIR="$EMPTY14" bash "$SCRIPT" "$P14" --html --session-log "$WORK/elsewhere/s9.jsonl" >/dev/null 2>&1
has "$P14/architecture/progress-report.html" 'id=tips' "--session-log file is used"
has "$P14/architecture/progress-report.html" "Plain helper agent" "its subagents folder is read too"
has "$P14/architecture/progress-report.html" "elsewhere/s9.jsonl" "footer names the chosen log"
has "$P14/architecture/progress-report.html" "chosen with --session-log" "footer says it was chosen"
has "$P14/architecture/progress-report.html" "Rates file:" "footer names the rates file"
CLAUDE_CONFIG_DIR="$EMPTY14" bash "$SCRIPT" "$P14" --html --session-log "$WORK/elsewhere" >/dev/null 2>&1
has "$P14/architecture/progress-report.html" 'id=tips' "--session-log folder is used"
HELP="$("$PY" "$ROOT/project-bin/progress-report.py" --help 2>&1)"
printf '%s' "$HELP" | grep -q -- "--session-log" && ok "--help lists --session-log" || bad "--help lists --session-log"
printf '%s' "$HELP" | grep -q "progress-report-rates.txt" && ok "--help lists the rates file path" || bad "--help lists the rates file path"

echo "T15 --open exact URL; a crash leaves a WARN"
P15="$WORK/p15 with space"; mkproj "$P15"; STUB="$WORK/stub"; mkdir -p "$STUB"
printf '#!/bin/sh\ncat > "%s/osa.txt" <<EOF2\n$2\nEOF2\necho none\n' "$WORK" > "$STUB/osascript"  # portability-ok: macOS stubs for the --open test
printf '#!/bin/sh\necho Darwin\n' > "$STUB/uname"; printf '#!/bin/sh\nexit 0\n' > "$STUB/pgrep"; printf '#!/bin/sh\necho "$@" > "%s/open.txt"\n' "$WORK" > "$STUB/open"  # portability-ok: macOS stubs for the --open test
chmod +x "$STUB"/*
PATH="$STUB:$PATH" CLAUDE_CONFIG_DIR="$EMPTY" bash "$SCRIPT" "$P15" --open >/dev/null 2>&1
ABS="$(cd "$P15" && pwd -P)/architecture/progress-report.html"
has "$WORK/osa.txt" "file://.*p15%20with%20space/architecture/progress-report.html" "AppleScript matches this project's percent-encoded file URL"
hasnt "$WORK/osa.txt" "contains" "AppleScript no longer matches any tab that merely contains the name"
has "$WORK/open.txt" "progress-report.html" "no matching tab: the file is opened once"
# a crash: unattended refresh prints one WARN and still exits 0
P16="$WORK/p16"; mkproj "$P16"; CRASH="$WORK/crash"; mkdir -p "$CRASH"
cp "$ROOT/project-bin/build-plan-status.sh" "$CRASH/"; printf 'raise SystemExit("boom")\n' > "$CRASH/progress-report.py"
OUTW="$(CLAUDE_CONFIG_DIR="$EMPTY" bash "$CRASH/build-plan-status.sh" "$P16" --refresh 2>&1 >/dev/null)"; RC=$?
[ "$RC" -eq 0 ] && ok "a generator crash does not fail the step" || bad "a generator crash does not fail the step"
printf '%s' "$OUTW" | grep -q "^WARN: progress-report.html not updated" && [ "$(printf '%s\n' "$OUTW" | wc -l)" -eq 1 ] && ok "one visible WARN line" || bad "one visible WARN line ($OUTW)"

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

echo "T16 narrow-width CSS (phone)"
GEN="$ROOT/project-bin/progress-report.py"
grep -q "@media(max-width:520px){code,pre,.stage dd" "$GEN" && ok "narrow rules wrap code and values" || bad "narrow rules wrap code and values"
grep -q "\.stage dl{grid-template-columns:minmax(0,1fr)}" "$GEN" && ok "stage label/value rows stack on phones" || bad "stage label/value rows stack on phones"
grep -q "\.hd \.sub{white-space:normal" "$GEN" && ok "gates label wraps below the header text" || bad "gates label wraps below the header text"
grep -q "\.snav{padding:6px 12px;flex-wrap:nowrap;overflow-x:auto" "$GEN" && ok "stage nav scrolls inside its own container" || bad "stage nav scrolls inside its own container"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
