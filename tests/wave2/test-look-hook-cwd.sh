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
#   L5  old and new hook side by side (and a second new copy): one look hook remains
#   L6  no .claude/ under the root to log into: stderr says so without claiming "logged once"
#   L7  doctor.sh flags ANY look hook not in the root-resolving form, not only the exact old string
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

D2="$WORK/dup"; mkdir -p "$D2/.claude"
"$PY" - "$D2/.claude/settings.json" "$CMD" <<'PY'
import json, sys
new = {"type": "command", "command": sys.argv[2]}
old = {"type": "command", "command": "bash bin/look-ledger.sh seen || true"}
d = {"hooks": {"PostToolUse": [{"matcher": "Read", "hooks": [old, new]}, {"matcher": "Read", "hooks": [dict(new)]}]}}
open(sys.argv[1], "w").write(json.dumps(d, indent=2) + "\n")
PY
"$SUT" "$D2" --hooks-only --check >/dev/null 2>&1; drc=$?
"$SUT" "$D2" --hooks-only >/dev/null 2>&1
dc="$(hook_cmds "$D2/.claude/settings.json" | grep -c look-ledger)"
{ [ "$drc" = 1 ] && [ "$dc" = 1 ] && hook_cmds "$D2/.claude/settings.json" | grep -q CLAUDE_PROJECT_DIR; } \
  && ok "L5: old + new + a second copy: --check flags it, install leaves one look hook" || bad "L5: check rc $drc, look hooks after install: $dc"

mkdir -p "$WORK/bare"
read_png "$WORK/lane" "$WORK/bare"
{ [ "$rc" = 0 ] && grep -q 'no bin/look-ledger.sh' "$WORK/err.$n" && ! grep -q 'logged once' "$WORK/err.$n"; } \
  && ok "L6: nothing to log into: stderr names the problem, no 'logged once' claim" || bad "L6" "$(cat "$WORK/err.$n")"

DL="$(grep -F "grep -F 'look-ledger.sh seen'" "$TK/bin/doctor.sh" | head -1)"
printf '{\n  "hooks": {"PostToolUse": [{"matcher": "Read", "hooks": [{"type": "command", "command": "bash ./bin/look-ledger.sh seen 2>/dev/null"}]}]}\n}\n' > "$WORK/hand.json"
gap="$( [ -n "$DL" ] && PSET="$WORK/hand.json" HOOK_GAP="" bash -c "$DL"'; printf %s "$HOOK_GAP"')"
gap2="$( [ -n "$DL" ] && PSET="$P/.claude/settings.json" HOOK_GAP="" bash -c "$DL"'; printf %s "$HOOK_GAP"')"
{ printf '%s' "$gap" | grep -q 'project root' && [ -z "$gap2" ]; } \
  && ok "L7: doctor flags a hand-written relative look hook, not the installed one" || bad "L7: doctor gap '$gap' / '$gap2'"

echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
