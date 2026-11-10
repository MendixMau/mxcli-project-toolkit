#!/usr/bin/env bash
# Usage: bash test-conformance-probe-speed.sh [path-to-conformance-check.sh]
#
# Fixture for project-bin/conformance-check.sh's run_guarded: a probe returns when mxcli does,
# and a probe that hangs is still killed at the deadline.
#
# The defect (#686 speed audit): run_guarded is called as `out="$(run_guarded ...)"`, and its
# watchdog subshell inherited that command substitution's pipe as stdout. Killing the watchdog
# left its `sleep 1` holding the pipe, so `$(…)` waited for it: every probe cost ~1 s however
# fast mxcli answered (22 stub rows: 22.6 s on master, 2.7 s with the watchdog writing nowhere).
#   Case 1 — 12 fast rows finish in under 8 s (master: >= 12 s, one second per probe).
#   Case 2 — a hanging probe with MXTK_CONFORMANCE_TIMEOUT_S=2 is scored TIMEOUT, the run ends
#            in under 10 s (master ignores the knob and waits 25 s), and the hung process is dead.
#
# The ledger and the mxcli stub are SYNTHETIC, as in test-conformance-baseline-scope.sh: nothing
# here exercises the DESCRIBE-output parser (the field-proof "captured golden input" rule governs
# parsers); the assertions are about wall-clock and process lifetime.

set -uo pipefail

SUT="${1:-}"
[ -z "$SUT" ] && SUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/project-bin/conformance-check.sh"
if [ ! -f "$SUT" ]; then
  echo "SKIP: subject not found at $SUT"
  echo "SCORE: 0/0 — nothing to test"
  exit 0
fi
SUT="$(cd "$(dirname "$SUT")" && pwd)/$(basename "$SUT")"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/conf-speed.XXXXXX")"
cleanup() { [ -f "$WORK/proj/HUNG" ] && kill -9 "$(cat "$WORK/proj/HUNG")" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT
P="$WORK/proj"
mkdir -p "$P/architecture/modules/Orders"
: > "$P/Shop.mpr"
# PRESENT lists what the stub model holds; a name listed in HANG makes the stub hang (and record
# its pid in HUNG, so the test can check the deadline kill reached it).
: > "$P/PRESENT"; : > "$P/HANG"
cat > "$P/mxcli" <<'EOF'
#!/usr/bin/env bash
cmd=""; while [ $# -gt 0 ]; do [ "$1" = -c ] && cmd="$2"; shift; done
name="${cmd##* }"; d="$(dirname "$0")"
if grep -qx "$name" "$d/HANG"; then echo $$ > "$d/HUNG"; exec sleep 60; fi
if grep -qx "$name" "$d/PRESENT"; then echo "-- $name"; echo "create $name;"; exit 0; fi
echo "Error: $name not found"; exit 1
EOF
chmod +x "$P/mxcli"
{ printf '| Pointer | Kind | Name | Row | Proof | Acceptance | Status |\n|---|---|---|---|---|---|---|\n'
  for i in 0 1 2 3 4 5 6 7 8 9 10 11; do
    printf '| `/domainEntities/%s` | entity | E%s | 1.%s | exec.sh | `DESCRIBE ENTITY Orders.E%s` | built |\n' "$i" "$i" "$i" "$i"
    echo "Orders.E$i" >> "$P/PRESENT"
  done
} > "$P/architecture/modules/Orders/coverage-ledger.md"
run() { ( cd "$P" && PROJECT_ROOT="$P" bash "$SUT" --quiet "$@" ) > "$WORK/out" 2>&1; echo $?; }
out() { tr '\n' ' ' < "$WORK/out" | cut -c1-300; }

# --- 1. fast probes return as soon as mxcli does ---------------------------------------------
SECONDS=0
rc="$(run)"
t=$SECONDS
[ "$rc" = 0 ] && grep -Eq 'OK +12' "$WORK/out" && ok "1a: 12 rows measured OK (rc 0)" \
  || bad "1a: 12-row pass did not score 12 OK (rc=$rc)" "$(out)"
[ "$t" -lt 8 ] && ok "1b: 12 probes took ${t}s (< 8 s; one second per probe was the defect)" \
  || bad "1b: 12 probes took ${t}s — each probe waits for the watchdog's sleep again"

# --- 2. a hanging probe is still killed at the deadline ---------------------------------------
echo "Orders.E5" > "$P/HANG"; rm -rf "$P/docs"
SECONDS=0
rc="$(MXTK_CONFORMANCE_TIMEOUT_S=2 run)"
t=$SECONDS
grep -Eq 'TIMEOUT +1 ' "$WORK/out" && ok "2a: the hanging probe is scored TIMEOUT (1 row)" \
  || bad "2a: no 'TIMEOUT 1' line (rc=$rc)" "$(out)"
[ "$t" -lt 10 ] && ok "2b: the run ended in ${t}s with a 2 s deadline (< 10 s)" \
  || bad "2b: the run took ${t}s — MXTK_CONFORMANCE_TIMEOUT_S not honoured or the deadline did not fire"
if [ -f "$P/HUNG" ] && ! kill -0 "$(cat "$P/HUNG")" 2>/dev/null; then
  ok "2c: the hung mxcli process was killed"
else
  bad "2c: the hung mxcli process is still alive (or never started)" "pid=$(cat "$P/HUNG" 2>/dev/null)"
fi

echo
echo "SCORE: $PASS/$((PASS+FAIL))"
[ "$FAIL" -eq 0 ]
