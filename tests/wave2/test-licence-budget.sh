#!/usr/bin/env bash
# Fixture for project-bin/licence-budget.py: gate before a long or parallel suite on a trial runtime.
#   L1 young runtime, short batch, seats free -> GO, exit 0
#   L2 runtime up 110 min, 30 min batch       -> NO-GO time, exit 1
#   L3 no run-local.json (app not running)    -> exit 2, never a pass
# A fake admin API answers runtime_statistics on a spare port; no real app is touched.
set -uo pipefail
TK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUT="${1:-$TK/project-bin/licence-budget.py}"
PASS=0; FAIL=0
ok() { echo "  ok   $1"; PASS=$((PASS+1)); }; bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }
T="$(mktemp -d)"; trap 'kill $SRV 2>/dev/null; rm -rf "$T"' EXIT
PORT=47311
python3 - "$PORT" >/dev/null 2>&1 <<'PY' &
import sys, json, http.server
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(s):
        s.rfile.read(int(s.headers.get("Content-Length", 0)))
        b = json.dumps({"feedback": {"sessions": {"named_user_sessions": 1, "anonymous_sessions": 0}}}).encode()
        s.send_response(200); s.send_header("Content-Length", str(len(b))); s.end_headers(); s.wfile.write(b)
    def log_message(*a): pass
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
SRV=$!; sleep 1
mk() { # $1 = minutes up
  rm -rf "$T/p"; mkdir -p "$T/p/.mxcli"
  echo "{\"adminPort\": $PORT, \"adminPass\": \"x\"}" > "$T/p/.mxcli/run-local.json"
  ts="$(date -v-"$1"M '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -d "$1 minutes ago" '+%Y-%m-%d %H:%M:%S')"
  printf 'Initializing license subsystem\nhas concurrent user restrictions: true\n%s.000 INFO - Core: Mendix Runtime successfully started\n' "$ts" > "$T/p/.mxcli/runtime.log"
}
mk 5;   out="$(python3 "$SUT" "$T/p" --runs 1 --minutes 30 2>&1)"; rc=$?
[ $rc -eq 0 ] && echo "$out" | grep -q '^GO' && ok "L1 GO" || bad "L1 rc=$rc: $out"
mk 110; out="$(python3 "$SUT" "$T/p" --runs 1 --minutes 30 2>&1)"; rc=$?
[ $rc -eq 1 ] && echo "$out" | grep -q 'NO-GO time' && ok "L2 NO-GO time" || bad "L2 rc=$rc: $out"
rm -rf "$T/p"; mkdir -p "$T/p/.mxcli"; out="$(python3 "$SUT" "$T/p" --runs 1 2>&1)"; rc=$?
[ $rc -eq 2 ] && ok "L3 cannot measure is exit 2" || bad "L3 rc=$rc: $out"
echo "SCORE: $PASS/$((PASS+FAIL))"; [ "$FAIL" -eq 0 ]
