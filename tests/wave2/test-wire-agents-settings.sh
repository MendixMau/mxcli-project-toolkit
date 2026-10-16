#!/usr/bin/env bash
# test-wire-agents-settings.sh - a re-wire (wire-agents.sh, run by sync-project.sh when --check
# fails) must not lose .claude/settings.json content to `mxcli init` (issue #419).
#
# Fixture: a stub mxcli whose `init` overwrites settings.json with a stock file (as the real one
# does) and adds one new entry. The project file holds a profile entry, a user entry, the
# `mxcli exec` deny rule and a hook. All must survive; the new mxcli entry must also arrive.
#
# usage: bash test-wire-agents-settings.sh [path-to-wire-agents.sh]
set -uo pipefail
TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/bin/wire-agents.sh}"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL - $1"; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/wasettings.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT
echo "== subject: $SUBJECT"

P="$WORK/proj"; mkdir -p "$P/.claude"; : > "$P/Fixture.mpr"
cat > "$P/mxcli" <<'MXCLI'
#!/bin/sh
case "$1" in
  init)
    mkdir -p .claude
    printf '{"permissions":{"allow":["Bash(./mxcli *)","Bash(mxcli-new-thing)"]}}\n' > .claude/settings.json
    for f in AGENTS.md CLAUDE.md .github/copilot-instructions.md .cursorrules .windsurfrules .aider.conf.yml; do
      mkdir -p "$(dirname "$f")"; [ -f "$f" ] || printf '# stub\n' > "$f"
    done ;;
esac
exit 0
MXCLI
chmod +x "$P/mxcli"
cat > "$P/.claude/settings.json" <<'JSON'
{
  "permissions": {
    "allow": ["Bash(./mxcli *)", "Bash(git status)", "Edit(/docs/**)"],
    "deny": ["Bash(./mxcli exec*)", "Bash(rm -rf *)"]
  },
  "hooks": {"PostToolUse": [{"matcher": "Read", "hooks": [{"type": "command", "command": "echo für"}]}]}
}
JSON

bash "$SUBJECT" "$P" >/dev/null 2>&1
S="$P/.claude/settings.json"
has() { grep -qF -- "$1" "$S"; }
has 'Edit(/docs/**)'          && ok "profile entry survives re-wire"        || bad "profile entry lost"
has 'Bash(git status)'        && ok "user entry survives re-wire"           || bad "user entry lost"
has 'Bash(./mxcli exec*)'     && ok "mxcli exec deny rule survives"         || bad "mxcli exec deny rule lost"
has '"matcher": "Read"'       && ok "user hook survives"                    || bad "user hook lost"
has 'mxcli-new-thing'         && ok "entry new in mxcli init is also added" || bad "new mxcli entry not added"
n1="$(cksum < "$S")"; bash "$SUBJECT" "$P" >/dev/null 2>&1
[ "$n1" = "$(cksum < "$S")" ] && ok "second re-wire changes nothing" || bad "second re-wire changed the file"

# --- failure paths: the result must never be worse than before the re-wire --------------------
ORIG='{ "permissions": { "allow": ["Bash(git status)"] }, "keep": "für" }'
mkproj() {  # $1 dir, $2 init exit code
  mkdir -p "$1/.claude"; : > "$1/Fixture.mpr"
  sed "s/^exit 0\$/exit $2/" "$P/mxcli" > "$1/mxcli"; chmod +x "$1/mxcli"
  printf '%s\n' "$ORIG" > "$1/.claude/settings.json"; cp "$1/.claude/settings.json" "$1/orig"
}
# 1. mxcli init writes its stock file then exits 3
F="$WORK/fail"; mkproj "$F" 3
bash "$SUBJECT" "$F" >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] && cmp -s "$F/orig" "$F/.claude/settings.json" \
  && ok "failing mxcli init: snapshot restored byte for byte" || bad "failing mxcli init left stock file (rc=$rc)"
# 2. no python on PATH
N="$WORK/nopy"; mkproj "$N" 0
BIN="$WORK/bin"; mkdir -p "$BIN"
for c in bash sh cp cat mkdir rm mv date dirname basename grep sed awk tr sort uniq head tail wc cksum shasum md5 md5sum cmp env mktemp ls find xargs chmod touch printf tee readlink pwd id uname git diff; do
  w="$(command -v "$c" 2>/dev/null)" && [ -x "$w" ] && ln -sf "$w" "$BIN/$c"
done
PATH="$BIN" bash "$SUBJECT" "$N" >"$WORK/nopy.out" 2>&1
cmp -s "$N/orig" "$N/.claude/settings.json" \
  && ok "no python: snapshot restored byte for byte" || bad "no python left a changed settings.json"  # portability-ok: test name, not an interpreter call
grep -q "WARN" "$WORK/nopy.out" && ok "no python: WARN printed" || bad "no python: no WARN"

# 3/4. python3 passes the version probe (-c) but the merge fails; the second one truncates the
# target first. Both must restore byte for byte, warn, stamp, and exit 0.
REALPY="$(command -v python3)"  # portability-ok: finds the real interpreter to wrap
for mode in fail truncate; do
  M="$WORK/merge-$mode"; mkproj "$M" 0
  FB="$WORK/fakepy-$mode"; mkdir -p "$FB"
  cat > "$FB/python3" <<FAKE  # portability-ok: deliberate fake interpreter simulating a broken one
#!/bin/sh
[ "\$1" = "-c" ] && exec "$REALPY" "\$@"
[ "$mode" = "truncate" ] && : > "\$3"
exit 1
FAKE
  chmod +x "$FB/python3"  # portability-ok: deliberate fake interpreter
  PATH="$FB:$PATH" bash "$SUBJECT" "$M" >"$WORK/merge-$mode.out" 2>&1; rc=$?
  cmp -s "$M/orig" "$M/.claude/settings.json" \
    && ok "failed merge ($mode): snapshot restored byte for byte" || bad "failed merge ($mode): settings.json differs"
  grep -q "WARN" "$WORK/merge-$mode.out" && ok "failed merge ($mode): WARN printed" || bad "failed merge ($mode): no WARN"
  grep -q "mxtk:wiring:start" "$M/AGENTS.md" && ok "failed merge ($mode): stamped" || bad "failed merge ($mode): not stamped"
  [ "$rc" -eq 0 ] && ok "failed merge ($mode): rc 0" || bad "failed merge ($mode): rc $rc"
done

echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ]
