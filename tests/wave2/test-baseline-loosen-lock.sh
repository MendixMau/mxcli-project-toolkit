#!/usr/bin/env bash
# Usage: bash test-baseline-loosen-lock.sh [path-to-lint-gate.sh]
#   (conformance-check.sh and _common.sh are taken from the same directory)
#
# #348: re-baselining is the user's call, but `lint-gate.sh --update-baseline` took
# `--approved-in-chat` — a flag the agent whose script caused the rise could type itself — and
# `conformance-check.sh --update-baseline` accepted an OK -> STALE regression with no question.
# Now a LOOSENING write needs `loosen` typed at a terminal; tightening is unchanged.
#
# "Agent" = stdin is not a terminal (</dev/null), as in an agent's tool call. "User" = a pty
# with the answer typed into it (fixtures/baseline-loosen/at-terminal.py); skipped where Python
# has no pty (Git Bash). Lint JSON and the mxcli stub are synthetic: nothing here parses tool
# output beyond what test-lint-gate-accept.sh / test-conformance-baseline-scope.sh already cover.
set -uo pipefail
TK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="${1:-$TK/project-bin/lint-gate.sh}"
GATE="$(cd "$(dirname "$GATE")" && pwd)/$(basename "$GATE")"
CONF="$(dirname "$GATE")/conformance-check.sh"
TTY="$TK/tests/wave2/fixtures/baseline-loosen/at-terminal.py"
. "$TK/bin/lib/portable.sh"
require_py
WORK="$(mktemp -d "${TMPDIR:-/tmp}/baseline-loosen.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0; SKIP=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | head -12 | sed 's/^/       /'; }
"$PY" -c 'import pty' 2>/dev/null && HAVE_PTY=1 || HAVE_PTY=0
skip() { SKIP=$((SKIP+1)); printf '  skip %s (no pty in this Python)\n' "$1"; }

# --- lint-gate -------------------------------------------------------------------------------
# Two-tree layout (.mpr under app/), in a git repo so the "deleted baseline" case has a HEAD.
P="$WORK/lint"; mkdir -p "$P/bin" "$P/.claude" "$P/app"
cp "$GATE" "$P/bin/lint-gate.sh"; cp "$(dirname "$GATE")/_common.sh" "$P/bin/" 2>/dev/null
printf 'mpr' > "$P/app/App.mpr"; printf '#!/bin/sh\nexit 0\n' > "$P/mxcli"; chmod +x "$P/mxcli"
v() { i=0; while [ "$i" -lt "$2" ]; do
  printf '{"ruleId":"%s","severity":"warning","message":"f%s","module":"Orders","document":"D%s","documentType":"microflow","documentId":"%s%s","suggestion":"s"},' "$1" "$i" "$i" "$1" "$i"; i=$((i+1)); done; }
mk() { printf '{"violations":[%s{"ruleId":"MPR001","severity":"warning","message":"m","module":"Orders","document":"E","documentType":"entity","documentId":"x","suggestion":"s"}],"summary":{}}' "$1" > "$WORK/lint.json"; }
agent() { (cd "$P" && LINT_JSON="$WORK/lint.json" bash bin/lint-gate.sh "$@" </dev/null 2>&1); }
user()  { a="$1"; shift; (cd "$P" && LINT_JSON="$WORK/lint.json" "$PY" "$TTY" "$a" bash bin/lint-gate.sh "$@" 2>&1); }
total() { "$PY" -c 'import json,sys;print(json.load(open(sys.argv[1]))["total"])' "$P/.claude/lint-baseline.json" 2>/dev/null || echo none; }

echo "L1 first baseline: no question asked"
mk "$(v CONV009 2)"; out=$(agent --update-baseline); rc=$?
[ "$rc" -eq 0 ] && [ "$(total)" = 3 ] && ok "first baseline written by the agent (total 3)" || bad "first baseline rc=$rc total=$(total)" "$out"

echo "L2 the agent loosens with --reason --approved-in-chat: refused, baseline untouched"
mk "$(v CONV009 4)$(v SEC003 1)"
out=$(agent --update-baseline --reason "x" --approved-in-chat); rc=$?
[ "$rc" -eq 2 ] && ok "refused (rc 2)" || bad "loosening went through for the agent (rc $rc)" "$out"
[ "$(total)" = 3 ] && ok "baseline still 3" || bad "baseline moved to $(total)"
case "$out" in *"own terminal"*loosen*"--update-baseline --reason"*) ok "refusal tells the user the exact command and the word" ;;
  *) bad "refusal does not say how the user loosens it" "$out" ;; esac

echo "L3 the agent tightens: unchanged, no question"
mk "$(v CONV009 1)"; out=$(agent --update-baseline); rc=$?
[ "$rc" -eq 0 ] && [ "$(total)" = 2 ] && ok "ratchet-down written by the agent (total 2)" || bad "tightening refused rc=$rc total=$(total)" "$out"

echo "L4 the user loosens at a terminal"
mk "$(v CONV009 4)$(v SEC003 1)"
if [ "$HAVE_PTY" = 1 ]; then
  out=$(user nope --update-baseline --reason "split later"); rc=$?
  [ "$rc" -eq 2 ] && [ "$(total)" = 2 ] && ok "a wrong answer cancels (baseline still 2)" || bad "wrong answer rc=$rc total=$(total)" "$out"
  out=$(user loosen --update-baseline --reason "split later"); rc=$?
  [ "$rc" -eq 0 ] && [ "$(total)" = 6 ] && ok "\`loosen\` at the terminal writes it (total 6)" || bad "user loosen rc=$rc total=$(total)" "$out"
  tail -1 "$P/.claude/lint-acceptances.tsv" 2>/dev/null | grep -q "split later" && ok "acceptance row logged" || bad "no acceptance row"
else skip "L4 user at a terminal"; fi

echo "L5 rm the baseline + update: compared with git HEAD's, still a loosening"
if command -v git >/dev/null 2>&1; then
  mk "$(v CONV009 1)"; agent --update-baseline >/dev/null
  (cd "$P" && git init -q && git add .claude/lint-baseline.json && git -c user.email=t@t -c user.name=t commit -qm b) >/dev/null 2>&1
  rm -f "$P/.claude/lint-baseline.json"; mk "$(v CONV009 5)"
  out=$(agent --update-baseline --reason x); rc=$?
  [ "$rc" -eq 2 ] && [ ! -f "$P/.claude/lint-baseline.json" ] && ok "refused; nothing re-created" || bad "rm + update loosened silently (rc $rc, total $(total))" "$out"
else echo "  skip L5 (no git)"; fi

# --- conformance-check -----------------------------------------------------------------------
C="$WORK/conf"; mkdir -p "$C/architecture/modules/Orders"; : > "$C/Shop.mpr"
printf 'Orders.Order\nOrders.ACT_Order_Save\n' > "$C/PRESENT"
cat > "$C/mxcli" <<'EOF'
#!/usr/bin/env bash
cmd=""; while [ $# -gt 0 ]; do [ "$1" = -c ] && cmd="$2"; shift; done
name="${cmd##* }"
if grep -qx "$name" "$(dirname "$0")/PRESENT"; then echo "-- $name"; echo "create $name;"; exit 0; fi
echo "Error: $name not found"; exit 1
EOF
chmod +x "$C/mxcli"
cat > "$C/architecture/modules/Orders/coverage-ledger.md" <<'EOF'
| Pointer | Kind | Name | Row | Proof | Acceptance | Status |
|---|---|---|---|---|---|---|
| `/domainEntities/0` | entity | Order | 1.1 | exec.sh | `DESCRIBE ENTITY Orders.Order` | built |
| `/microflows/0` | microflow | ACT_Order_Save | 1.2 | exec.sh | `DESCRIBE MICROFLOW Orders.ACT_Order_Save` | built |
EOF
crun()  { ( cd "$C" && PROJECT_ROOT="$C" bash "$CONF" --quiet "$@" </dev/null ) > "$WORK/out" 2>&1; echo $?; }
curun() { a="$1"; shift; ( cd "$C" && PROJECT_ROOT="$C" "$PY" "$TTY" "$a" bash "$CONF" --quiet "$@" ) > "$WORK/out" 2>&1; echo $?; }
nok() { grep -c $'\tOK$' "$C/docs/conformance/baseline.tsv" 2>/dev/null || echo 0; }

echo "C1 first run baselines 2 OK rows"
rc=$(crun); [ "$rc" = 0 ] && [ "$(nok)" = 2 ] && ok "2 OK rows" || bad "first run rc=$rc ok=$(nok)" "$(cat "$WORK/out")"

echo "C2 the agent accepts an OK -> STALE regression: refused"
sed -i.bak '/^Orders.Order$/d' "$C/PRESENT"
rc=$(crun --update-baseline)
[ "$rc" = 2 ] && [ "$(nok)" = 2 ] && ok "refused, baseline keeps 2 OK rows" || bad "regression baselined silently (rc $rc, ok $(nok))" "$(cat "$WORK/out")"
grep -q "own terminal" "$WORK/out" && grep -q "conformance-check.sh --update-baseline" "$WORK/out" && grep -q loosen "$WORK/out" \
  && ok "refusal names the user's command" || bad "refusal does not say how the user loosens it" "$(cat "$WORK/out")"

echo "C3 the user accepts it at a terminal"
if [ "$HAVE_PTY" = 1 ]; then
  rc=$(curun loosen --update-baseline)
  [ "$rc" = 0 ] && [ "$(nok)" = 1 ] && ok "\`loosen\` writes it (1 OK row)" || bad "user loosen rc=$rc ok=$(nok)" "$(cat "$WORK/out")"
else skip "C3 user at a terminal"; fi

echo "C4 the agent re-baselines after a fix (tightening): no question"
mv "$C/PRESENT.bak" "$C/PRESENT"
rc=$(crun --update-baseline); [ "$rc" = 0 ] && [ "$(nok)" = 2 ] && ok "tightening written (2 OK rows)" || bad "tightening rc=$rc ok=$(nok)" "$(cat "$WORK/out")"

echo ""
echo "PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
[ "$FAIL" -eq 0 ]
