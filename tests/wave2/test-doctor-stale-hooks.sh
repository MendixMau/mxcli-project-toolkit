#!/usr/bin/env bash
# test-doctor-stale-hooks.sh: bin/doctor.sh warns (never fails) when a hook COPY installed in
# ~/.claude/hooks calls a toolkit script that no longer exists (bin/questions-report.sh was retired
# in v1.0), and tells the user to re-run bin/install-claude-hooks.sh --full. Fake HOME, no real hooks touched.
# Usage: bash tests/wave2/test-doctor-stale-hooks.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/doctor-stale-hooks.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
export MXTK_NO_GUIDE=1 MXTK_LEAKGUARD_DENYFILE="$WORK/deny"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }
has() { grep -q -- "$2" "$1"; }

mkhook() {  # mkhook <home> <script the hook calls>
  mkdir -p "$1/.claude/hooks"
  cat > "$1/.claude/hooks/interview-gate.sh" <<HOOK
#!/bin/bash
TOOLKIT="$ROOT"
QR="\$TOOLKIT/bin/$2"
[ -x "\$QR" ] || exit 0
HOOK
}

# 1. stale copy: calls bin/questions-report.sh, which is gone
H1="$WORK/home-stale"; mkdir -p "$H1"; mkhook "$H1" questions-report.sh
[ ! -e "$ROOT/bin/questions-report.sh" ] && ok "precondition: bin/questions-report.sh does not exist" || bad "precondition: bin/questions-report.sh does not exist"
HOME="$H1" bash "$ROOT/bin/doctor.sh" --quick >"$WORK/stale.out" 2>&1
has "$WORK/stale.out" "WARN  installed hook interview-gate.sh calls a toolkit script that no longer exists: questions-report.sh" \
  && ok "stale copy: doctor warns and names the missing script" || bad "stale copy: doctor warns and names the missing script"
has "$WORK/stale.out" "install-claude-hooks.sh --full" && ok "stale copy: the warning says to re-run install-claude-hooks.sh --full" || bad "stale copy: re-run hint"
grep -E "FAIL .*(hook|questions-report)" "$WORK/stale.out" >/dev/null && bad "stale copy: it is a warning, not a failure" || ok "stale copy: it is a warning, not a failure"

# 2. current copy: calls a script that exists
H2="$WORK/home-fresh"; mkdir -p "$H2"; mkhook "$H2" brd-report.sh
HOME="$H2" bash "$ROOT/bin/doctor.sh" --quick >"$WORK/fresh.out" 2>&1
has "$WORK/fresh.out" "installed hook .* no longer exists" && bad "current copy: no warning" || ok "current copy: no warning"
has "$WORK/fresh.out" "installed hooks only call toolkit scripts that exist" && ok "current copy: doctor says ok" || bad "current copy: doctor says ok"

# 3. no hooks installed: the section is silent
H3="$WORK/home-none"; mkdir -p "$H3"
HOME="$H3" bash "$ROOT/bin/doctor.sh" --quick >"$WORK/none.out" 2>&1
has "$WORK/none.out" "Installed Claude hooks" && bad "no hooks: section not shown" || ok "no hooks: section not shown"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
