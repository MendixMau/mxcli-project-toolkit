#!/usr/bin/env bash
# test-status-session-cwd.sh — bin/status.sh warns, in one line, when it runs outside the project.
#
# Usage: bash tests/wave2/test-status-session-cwd.sh bin/status.sh
#
# Field (#447, a migration project, 2026-10-17): the lead session was launched in a sibling
# folder. Claude Code finds .claude/agents/ by walking UP from the launch folder, so no project
# agent loaded and a whole Stage 5 build ran on general-purpose agents; nothing said why.
# status.sh runs in the session's cwd, so it can.
#
#   A  from a sibling folder, --brief prints exactly one CWD line, first, naming the project root
#   B  the full screen prints it too
#   C  from the project root: no CWD line (--brief and full)
#   D  from a folder below the root (mdlsource/, and app/ which holds its own .mpr): no CWD line
#   E  from a sibling that is another project, the line names that project (_common.sh's walk)
set -u
SUT="${1:?usage: test-status-session-cwd.sh /path/to/bin/status.sh}"
SUT="$(cd "$(dirname "$SUT")" && pwd)/$(basename "$SUT")"
W="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/statuscwd.XXXXXX")" && pwd -P)" || exit 2
trap 'rm -rf "$W"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }

P="$W/proj"; S="$W/sibling"; O="$W/other"
mkdir -p "$P/.claude/agents" "$P/mdlsource" "$P/app" "$S" "$O/.claude"
printf '# PROJECT\n\n## Current stage\n\n**Stage 5 — Build**\n' > "$P/PROJECT.md"
printf -- '---\nname: mdl-agent\ndescription: drafts MDL\n---\n' > "$P/.claude/agents/mdl-agent.md"
: > "$P/app/App.mpr"
printf '# PROJECT\n' > "$O/PROJECT.md"

run() { ( cd "$1" && CLAUDE_CONFIG_DIR="$W/none" bash "$SUT" "$P" ${2:-} 2>/dev/null ); }
echo "== status.sh session cwd (#447) =="

b="$(run "$S" --brief)"
n="$(printf '%s\n' "$b" | grep -c '^CWD ')"
[ "$n" = 1 ] && ok "A sibling --brief: one CWD line" || bad "A sibling --brief: one CWD line (got $n)" "$b"
case "$(printf '%s\n' "$b" | head -1)" in
  "CWD     session cwd $S is not the project root"*": project agents and CLAUDE.md will not load; restart the session in $P")
    ok "A the CWD line is first and names the root to restart in" ;;
  *) bad "A the CWD line is first and names the root to restart in" "$(printf '%s\n' "$b" | head -2)" ;; esac
f="$(run "$S")"
printf '%s\n' "$f" | grep -q "^CWD       session cwd $S is not the project root" && ok "B sibling full screen: CWD line" \
  || bad "B sibling full screen: CWD line" "$(printf '%s\n' "$f" | head -6)"

for d in "$P" "$P/mdlsource" "$P/app"; do
  for m in --brief ""; do
    o="$(run "$d" $m)"
    case "$o" in *CWD*) bad "C/D ${d#"$W"/} ${m:-full}: no CWD line" "$(printf '%s\n' "$o" | head -3)" ;;
      "") bad "C/D ${d#"$W"/} ${m:-full}: status.sh printed nothing" ;;
      *) ok "C/D ${d#"$W"/} ${m:-full}: no CWD line" ;; esac
  done
done

b="$(run "$O" --brief)"
printf '%s\n' "$b" | grep -qF "CWD     session cwd $O is not the project root (it belongs to $O):" \
  && ok "E another project's folder: the line names it" || bad "E another project's folder: the line names it" "$(printf '%s\n' "$b" | head -1)"

echo "-- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
