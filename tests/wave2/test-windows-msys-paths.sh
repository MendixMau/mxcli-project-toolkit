#!/usr/bin/env bash
# test-windows-msys-paths.sh: Git Bash hands native Windows Python MSYS paths (/c/work/proj) that it cannot
# open, and Claude Code on Windows keeps its logs under a C--work-proj folder with JSON-escaped backslashes
# in "cwd". Two instruments broke: brd-report.sh (ENOENT on the BRD files) and progress-report.py (no session
# log found, so no time, token or cost figures). This pins the fix on any platform:
#   1. native_path (bin/lib/portable.sh) calls cygpath -m on MINGW/MSYS and is a no-op elsewhere.
#   2. brd-report.sh routes the project dir and --html through it.
#   3. progress-report.py's pure path functions take a `win` flag, so Windows inputs are tested here.
# Usage: bash test-windows-msys-paths.sh [path-to-portable.sh]
set -u
TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
. "$TOOLKIT/bin/lib/portable.sh"
require_py
PASS=0; FAIL=0
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$3', got '$2'"; fi; }

echo "== native_path =="
STUB="$TMP/stub"; mkdir -p "$STUB"
printf '#!/bin/sh\necho "MINGW64_NT-10.0"\n' > "$STUB/uname"
printf '#!/bin/sh\n[ "$1" = "-m" ] || exit 9\nshift; [ "$1" = "--" ] && shift\necho "$1" >> "$CYG_LOG"\necho "C:/mapped$1"\n' > "$STUB/cygpath"
chmod +x "$STUB/uname" "$STUB/cygpath"
export CYG_LOG="$TMP/cyg.log"; : > "$CYG_LOG"
check "MINGW: runs cygpath -m" "$(PATH="$STUB:$PATH" native_path /c/work/proj)" "C:/mapped/c/work/proj"
check "Linux or macOS: unchanged" "$(native_path /c/work/proj)" "/c/work/proj"
printf '#!/bin/sh\nexit 1\n' > "$STUB/cygpath"
check "MINGW without a working cygpath: unchanged" "$(PATH="$STUB:$PATH" native_path /c/work/proj)" "/c/work/proj"

echo "== brd-report.sh converts the project dir =="
P="$TMP/proj"; mkdir -p "$P/analysis/src/knowledge-base/brd"
cat > "$P/analysis/src/knowledge-base/brd/F001-a.brd.json" <<'J'
{"id": "F001", "title": "Order Registration", "provenance": "documents", "modules": ["Orders"],
 "domainEntities": [{"name": "Order", "persistent": true, "attributes": [{"name": "Code"}]}]}
J
printf '#!/bin/sh\n[ "$1" = "-m" ] && shift; [ "$1" = "--" ] && shift\necho "$1" >> "$CYG_LOG"\necho "$1"\n' > "$STUB/cygpath"
: > "$CYG_LOG"
OUT="$(PATH="$STUB:$PATH" bash "$TOOLKIT/bin/brd-report.sh" "$P" --json 2>&1)"; RC=$?
check "renders under a MINGW-like shell" "$RC" "0"
case "$(cat "$CYG_LOG")" in *"$P"*) ok "  cygpath was asked about the project dir" ;; *) bad "  cygpath was asked about the project dir" "$(cat "$CYG_LOG")" ;; esac
: > "$CYG_LOG"
bash "$TOOLKIT/bin/brd-report.sh" "$P" --json >/dev/null 2>&1
check "no conversion off Windows" "$(wc -c < "$CYG_LOG" | tr -d ' ')" "0"

echo "== progress-report.py path functions, Windows inputs =="
"$PY" - "$TOOLKIT/project-bin/progress-report.py" <<'PYEOF'
import importlib.util, json, os, sys, tempfile
sp = importlib.util.spec_from_file_location("pr", sys.argv[1]); pr = importlib.util.module_from_spec(sp); sp.loader.exec_module(pr)
n = [0, 0]
def check(name, got, want):
    n[0 if got == want else 1] += 1
    print(("  ok   " if got == want else "  FAIL ") + name + ("" if got == want else "\n     expected %r, got %r" % (want, got)))

check("msys path becomes a drive path on Windows", pr.fix_msys("/c/work/proj", True), "C:/work/proj")
check("  a bare drive", pr.fix_msys("/c", True), "C:/")
check("  /tmp style path is not a drive (left alone)", pr.fix_msys("/tmp/x/y", True), "/tmp/x/y")
check("  unchanged off Windows", pr.fix_msys("/c/work/proj", False), "/c/work/proj")
check("  a real drive path is unchanged", pr.fix_msys("C:\\work\\proj", True), "C:\\work\\proj")
check("slug of a Windows path", pr.slug("C:\\work\\demo-app"), "C--work-demo-app")
check("slug of the mixed form is the same", pr.slug("C:/work/demo-app"), "C--work-demo-app")
check("JSON-escaped cwd is unescaped", pr.unescape_json_str("C:\\\\work\\\\demo"), "C:\\work\\demo")
roots = pr.root_forms("C:/work/demo", True)
check("cwd in backslash form is under the root", pr.under("C:\\work\\demo\\sub", roots, True), True)
check("cwd in forward form is under the root", pr.under("C:/work/demo", roots, True), True)
check("drive letter case is ignored on Windows", pr.under("c:\\WORK\\Demo", roots, True), True)
check("case matters off Windows", pr.under("c:/work/demo", ["C:/work/demo"], False), False)
check("a sibling with the same prefix is not under", pr.under("C:\\work\\demo-other", roots, True), False)
nd = pr.needle_for(roots, True)
check("needle matches the JSON-escaped backslash form", bool(nd.search(b'{"cwd":"C:\\\\work\\\\demo\\\\x"}')), True)
check("needle matches the forward-slash form", bool(nd.search(b'cd C:/work/demo && ls')), True)
check("touches: Windows file_path", pr.touches("Edit", {"file_path": "C:\\work\\demo\\a.txt"}, None, roots, True), True)
check("touches: Windows cwd", pr.touches("Bash", {"command": "ls"}, "C:\\work\\demo", roots, True), True)
check("touches: other folder", pr.touches("Bash", {"command": "ls"}, "C:\\work\\x", roots, True), False)

# find_sessions with a fake logs dir holding C--work-demo and a log whose cwd is JSON-escaped
tmp = tempfile.mkdtemp()
logs = os.path.join(tmp, "projects"); d = os.path.join(logs, "C--work-demo"); os.makedirs(d)
other = os.path.join(logs, "C--elsewhere"); os.makedirs(other)
rec = lambda cwd: json.dumps({"type": "user", "cwd": cwd, "timestamp": "2026-10-01T10:00:00.000Z"}) + "\n"
open(os.path.join(d, "s1.jsonl"), "w").write(rec("C:\\work\\demo"))          # written as C:\\work\\demo
open(os.path.join(d, "s2.jsonl"), "w").write(rec("C:/work/demo/sub"))         # forward slashes
open(os.path.join(d, "s3.jsonl"), "w").write(rec("C:\\work\\demo-other"))     # same folder, other project
open(os.path.join(other, "s4.jsonl"), "w").write(rec("C:\\elsewhere"))
cache = os.path.join(tmp, "cache.txt")
for label, proj in (("drive path", "C:\\work\\demo"), ("msys path", "/c/work/demo"), ("lower-case drive", "c:/WORK/demo")):
    got, _ = pr.find_sessions(proj, logs, cache, True)
    names = sorted(os.path.basename(x) for x in got)
    check("find_sessions (%s) finds the project's logs only" % label, names, ["s1.jsonl", "s2.jsonl"])
    if os.path.exists(cache): os.remove(cache)
sys.exit(1 if n[1] else 0)
PYEOF
RC=$?
[ "$RC" -eq 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "  FAIL path-function section"; }
echo ""
echo "pass: $PASS, fail: $FAIL (path-function section counted as one)"
[ "$FAIL" -eq 0 ]
