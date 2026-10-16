#!/usr/bin/env bash
# test-look-ledger-hook-repair.sh: a project whose .claude/settings.json has no
# `look-ledger.sh seen` hook must be DETECTED (doctor.sh) and REPAIRED (sync-project.sh), and the
# repaired hook must actually write a seen row when a screenshot is opened.
#
# Field case: a lab project's ledger read "0 of 31 pages seen" while 22 had screenshots. Its
# settings.json held only what `mxcli init` writes: install-claude-permissions.sh had never run
# there (no sidecar, no exec.sh allow-list either), the only later caller (sync-project.sh) only
# printed a warning, and doctor.sh looked at the allow-list but never at the hooks.
#
#   H1  fixture reproduces the gap (hooks-only --check exits 1, names the look hook)
#   H2  doctor.sh warns and names the fix
#   H3  sync-project.sh --dry-run says it would add the hooks and writes nothing
#   H4  sync-project.sh adds both hooks, keeps the allow-list the project had, and is idempotent
#   H5  --hooks-only on a project that has a full install does not prune or add allow entries
#   H6  end to end: a Read hook payload for a fresh screenshot writes a seen.tsv row
#
# Usage: bash tests/wave2/test-look-ledger-hook-repair.sh
export MXTK_LEAKGUARD_DENYFILE="${TMPDIR:-/tmp}/mxtk-fixture-denylist.$$"
export MXTK_SYNC_SKIP_CLONE_CHECK=1
set -uo pipefail
TK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d /tmp/lookhook.XXXXXX)"
trap 'rm -f "$MXTK_LEAKGUARD_DENYFILE"; rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/  FAIL-detail: /'; }

P="$WORK/proj"
MXTK_NO_GUIDE=1 "$TK/bin/init-project.sh" "$P" >/dev/null 2>&1
# What `mxcli init` writes and nothing else: no toolkit hooks, no wrapper allow-list, no sidecar.
mkdir -p "$P/.claude"
cat > "$P/.claude/settings.json" <<'JSON'
{
  "env": {"MXCLI_QUIET": "1"},
  "hooks": {"SessionStart": [{"hooks": [{"command": "sh .claude/bootstrap-mxcli.sh || true", "type": "command"}]}]},
  "permissions": {"allow": ["Bash(mxcli:*)", "Bash(./mxcli:*)"]}
}
JSON
rm -f "$P/.claude/.mxtk-permissions-added.json" "$P/.claude/settings.local.json"

# H1
out="$("$TK/bin/install-claude-permissions.sh" "$P" --hooks-only --check 2>&1)"; rc=$?
{ [ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'look-ledger.sh seen'; } \
  && ok "H1: gap reproduced, hooks-only --check exits 1 and names the look-ledger hook" \
  || bad "H1: rc=$rc" "$out"

# H2
out="$(bash "$TK/bin/doctor.sh" "$P" 2>&1)"
{ printf '%s' "$out" | grep -q 'no hook for' && printf '%s' "$out" | grep -q 'look-ledger seen' \
    && printf '%s' "$out" | grep -q -- '--hooks-only'; } \
  && ok "H2: doctor warns about the missing hooks and names the fix" \
  || bad "H2: doctor did not flag the missing hook" "$(printf '%s' "$out" | grep -i 'hook\|permission' | head)"

# H3
before="$(md5 -q "$P/.claude/settings.json" 2>/dev/null || md5sum "$P/.claude/settings.json" | cut -d' ' -f1)"
out="$("$TK/bin/sync-project.sh" "$P" --dry-run 2>&1)"
after="$(md5 -q "$P/.claude/settings.json" 2>/dev/null || md5sum "$P/.claude/settings.json" | cut -d' ' -f1)"
{ printf '%s' "$out" | grep -q 'Would add: Claude Code hooks' && [ "$before" = "$after" ]; } \
  && ok "H3: --dry-run says it would add the hooks and leaves settings.json alone" \
  || bad "H3: dry-run output or write wrong" "$out"

# H4
out="$("$TK/bin/sync-project.sh" "$P" 2>&1)"
S="$P/.claude/settings.json"
grep -qF 'bash bin/look-ledger.sh seen || true' "$S" && grep -qF 'bash bin/session-check.sh || true' "$S" \
  && printf '%s' "$out" | grep -q 'Added: Claude Code hooks' \
  && ok "H4: sync-project.sh added both hooks" || bad "H4: hooks not added" "$out"
grep -qF 'sh .claude/bootstrap-mxcli.sh' "$S" && grep -qF '"Bash(./mxcli:*)"' "$S" \
  && ok "H4: the project's own hook and allow entries are kept" || bad "H4: existing entries lost"
sum1="$(cat "$S")"
"$TK/bin/sync-project.sh" "$P" >/dev/null 2>&1
[ "$sum1" = "$(cat "$S")" ] && ok "H4: a second sync changes nothing" || bad "H4: second sync rewrote settings.json"
out="$(bash "$TK/bin/doctor.sh" "$P" 2>&1)"
printf '%s' "$out" | grep -q 'hooks are in .claude/settings.json' \
  && ok "H4: doctor now passes the hook check" || bad "H4: doctor still flags the hook"

# H5: a project with a full install, then a custom allow-list edit; hooks-only must not prune it
Q="$WORK/full"; cp -R "$P" "$Q"
python3 - "$Q/.claude/settings.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["hooks"].pop("PostToolUse",None)
d["permissions"]["allow"].append("Bash(my-own-tool:*)"); json.dump(d,open(p,"w"),indent=2)
PY
"$TK/bin/install-claude-permissions.sh" "$Q" >/dev/null 2>&1
python3 - "$Q/.claude/settings.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["hooks"].pop("PostToolUse",None); json.dump(d,open(p,"w"),indent=2)
PY
allow_before="$(python3 -c 'import json,sys;print(sorted(json.load(open(sys.argv[1]))["permissions"]["allow"]))' "$Q/.claude/settings.json")"
"$TK/bin/install-claude-permissions.sh" "$Q" --hooks-only >/dev/null 2>&1
allow_after="$(python3 -c 'import json,sys;print(sorted(json.load(open(sys.argv[1]))["permissions"]["allow"]))' "$Q/.claude/settings.json")"
{ [ "$allow_before" = "$allow_after" ] && grep -qF 'look-ledger.sh seen' "$Q/.claude/settings.json"; } \
  && ok "H5: --hooks-only restored the hook and left the allow-list as it was" \
  || bad "H5: allow-list changed or hook missing" "$allow_before
$allow_after"

# H6: the hook command as written in settings.json, fed a Read payload for a fresh screenshot
cmd="$(python3 - "$S" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
for g in d["hooks"]["PostToolUse"]:
    if g.get("matcher")=="Read":
        print(g["hooks"][0]["command"])
PY
)"
mkdir -p "$P/mdlsource" "$P/docs/looks"; : > "$P/App.mpr"   # the ledger finds its root by the model file
printf 'CREATE PAGE Orders.Order_Overview { }\n' > "$P/mdlsource/10-pages.mdl"
touch -t 202001010000 "$P/mdlsource/10-pages.mdl"
( cd "$P" && bash bin/look-ledger.sh owe "$P/mdlsource/10-pages.mdl" >/dev/null 2>&1 )
touch -t 202001010000 "$P/mdlsource/10-pages.mdl"; sleep 1
printf 'png' > "$P/docs/looks/order-overview.png"
printf '{"hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{"file_path":"%s"},"tool_response":{}}' \
  "$P/docs/looks/order-overview.png" | ( cd "$P" && bash -c "$cmd" )
n="$(grep -c 'order-overview.png' "$P/.claude/loop/look/seen.tsv" 2>/dev/null)"
[ "${n:-0}" -ge 1 ] && ok "H6: opening a screenshot through the installed hook wrote a seen row" \
                    || bad "H6: seen.tsv has no row" "$(cat "$P/.claude/loop/look/seen.tsv" 2>&1)"

echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]
