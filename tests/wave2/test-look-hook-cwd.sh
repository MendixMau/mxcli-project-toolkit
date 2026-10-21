#!/usr/bin/env bash
# test-look-hook-cwd.sh: the PostToolUse(Read) look hook that install-claude-permissions.sh writes
# must record a seen row whatever the cwd of the Read, and must not fail silently (#446).
#
# Field case: owed.tsv 30 rows, seen.tsv 1. The hook was `bash bin/look-ledger.sh seen || true`:
# from any cwd but the project root (a subagent in a private copy, a shell in app/javasource)
# bash exits 127 on the relative path and `|| true` returns 0, so nothing records and nothing says.
#
#   L1  hook run from <project>/app/javasource (CLAUDE_PROJECT_DIR set) writes a seen row, and
#       from the project root it still does
#   L2  hook run from a lane folder outside the project (CLAUDE_PROJECT_DIR set) writes a seen row
#   L3  bin/look-ledger.sh missing: exit 0, one hook.log line and one stderr line over two Reads
#   L4  a settings.json holding the old relative hook gets it rewritten in place, not duplicated
#
# Usage: bash tests/wave2/test-look-hook-cwd.sh [path-to-install-claude-permissions.sh]
set -uo pipefail
SUT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin/install-claude-permissions.sh}"
TK="$(cd "$(dirname "$SUT")/.." && pwd)"
. "$TK/bin/lib/portable.sh"; require_py
WORK="$(mktemp -d "${TMPDIR:-/tmp}/lookcwd.XXXXXX")"; WORK="$(cd "$WORK" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/  FAIL-detail: /'; }

P="$WORK/proj"
mkdir -p "$P/bin" "$P/.claude" "$P/app/javasource" "$P/docs/looks" "$WORK/lane"
printf '# PROJECT\n' > "$P/PROJECT.md"; : > "$P/app/App.mpr"   # two-tree layout
cp "$TK/project-bin/_common.sh" "$TK/project-bin/look-ledger.sh" "$P/bin/"
printf '{\n  "permissions": {\n    "allow": []\n  }\n}\n' > "$P/.claude/settings.json"
"$SUT" "$P" --hooks-only >/dev/null 2>&1

hook_cmds() {  # $1 settings.json -> every PostToolUse(Read) command, one per line
  "$PY" - "$1" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for g in d.get("hooks", {}).get("PostToolUse", []) or []:
    if g.get("matcher") == "Read":
        for h in g.get("hooks", []) or []:
            print(h.get("command"))
PY
}
CMD="$(hook_cmds "$P/.claude/settings.json" | grep 'look-ledger' | head -1)"
[ -n "$CMD" ] || { echo "FAIL: no look hook installed"; exit 1; }

n=0; rc=0
read_png() {  # $1 cwd, $2 CLAUDE_PROJECT_DIR ("" = unset); sets rc to the hook's exit status
  n=$((n+1)); local f="$P/docs/looks/shot-$n.png"; printf 'png' > "$f"
  printf '{"hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{"file_path":"%s"}}' "$f" \
    | ( cd "$1" && if [ -n "$2" ]; then CLAUDE_PROJECT_DIR="$2" bash -c "$CMD"; else unset CLAUDE_PROJECT_DIR; bash -c "$CMD"; fi ) 2>"$WORK/err.$n"
  rc=$?
}
seen() { local c; c="$(grep -c "shot-$1.png" "$P/.claude/loop/look/seen.tsv" 2>/dev/null)"; echo "${c:-0}"; }

read_png "$P" ""
read_png "$P/app/javasource" "$P"
{ [ "$(seen 1)" -ge 1 ] && [ "$(seen 2)" -ge 1 ]; } && ok "L1: from app/javasource, a seen row (and from the root) (rc $rc)" \
  || bad "L1: seen rows root/app-javasource: $(seen 1)/$(seen 2) (rc $rc)" "$(cat "$WORK/err.2")"
read_png "$WORK/lane" "$P"
[ "$(seen 3)" -ge 1 ] && ok "L2: from a lane folder outside the project, a seen row (rc $rc)" \
  || bad "L2: no seen row from a lane folder (rc $rc)" "$(cat "$WORK/err.3")"

mv "$P/bin/look-ledger.sh" "$WORK/look-ledger.sh.away"
read_png "$WORK/lane" "$P"; rc1=$rc; read_png "$WORK/lane" "$P"; rc2=$rc
lines="$(grep -c . "$P/.claude/loop/look/hook.log" 2>/dev/null)"; lines="${lines:-0}"
{ [ "$rc1" = 0 ] && [ "$rc2" = 0 ] && [ "$lines" = 1 ] && grep -q 'look-ledger.sh' "$WORK/err.4" && [ ! -s "$WORK/err.5" ]; } \
  && ok "L3: missing script logged once (hook.log 1 line, stderr on the first Read only), exit 0" \
  || bad "L3: rc=$rc1/$rc2 hook.log lines=$lines" "$(cat "$WORK/err.4" "$P/.claude/loop/look/hook.log" 2>&1)"
mv "$WORK/look-ledger.sh.away" "$P/bin/look-ledger.sh"

Q="$WORK/legacy"; mkdir -p "$Q/.claude"
"$PY" - "$Q/.claude/settings.json" <<'PY'
import json, sys
d = {"hooks": {"PostToolUse": [{"matcher": "Read", "hooks": [{"type": "command", "command": "bash bin/look-ledger.sh seen || true"}]}]}}
open(sys.argv[1], "w").write(json.dumps(d, indent=2) + "\n")
PY
"$SUT" "$Q" --hooks-only --check >/dev/null 2>&1; crc=$?
"$SUT" "$Q" --hooks-only >/dev/null 2>&1
cmds="$(hook_cmds "$Q/.claude/settings.json")"
"$SUT" "$Q" --hooks-only --check >/dev/null 2>&1; crc2=$?
{ [ "$crc" = 1 ] && [ "$crc2" = 0 ] && [ "$(printf '%s\n' "$cmds" | grep -c look-ledger)" = 1 ] \
    && printf '%s' "$cmds" | grep -q CLAUDE_PROJECT_DIR; } \
  && ok "L4: the old relative hook is flagged by --check and rewritten in place (one look hook)" \
  || bad "L4: check rc before/after $crc/$crc2" "$cmds"

echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
