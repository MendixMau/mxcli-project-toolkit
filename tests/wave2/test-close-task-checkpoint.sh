#!/usr/bin/env bash
# Fixture for #358: close-task.sh must resolve checkpoint.sh, never print it bare.
#
# usage: test-close-task-checkpoint.sh /path/to/project-bin/close-task.sh
#
# checkpoint.sh lives in the toolkit at claude-hooks/bin/ and reaches ~/.claude/bin only via
# the opt-in `bin/install-claude-hooks.sh --basic`. The old "### Then" block printed
# `checkpoint.sh --write` unconditionally, so a project without the hooks got a command that
# did not exist. Lookup order: PATH, ~/.claude/bin, $MXTK_ROOT/claude-hooks/bin.
#
# T1  found on PATH          -> prints that full path
# T2  found in ~/.claude/bin -> prints that full path (fake HOME)
# T3  found in toolkit       -> prints $MXTK_ROOT/claude-hooks/bin/checkpoint.sh
# T4  PATH beats ~/.claude/bin and toolkit
# T5  not found              -> install pointer, rest of the block still printed,
#                               exit code unchanged (0 on a clean project)
# T6  not found, writes owed -> still exit 1 (owed-write semantics kept)
# T7  paths with a space (and a ') in HOME / toolkit -> printed single-quoted, and the printed
#     command actually runs when pasted into a shell
# T8  the claude-hooks/bin/close-task.sh copy prints its sibling checkpoint.sh full path, quoted

set -uo pipefail

SUT="${1:?usage: test-close-task-checkpoint.sh /path/to/project-bin/close-task.sh}"
case "$SUT" in /*) ;; *) SUT="$PWD/$SUT" ;; esac
[ -f "$SUT" ] || { echo "no such file: $SUT" >&2; exit 2; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS $1"; }
bad() { fail=$((fail+1)); echo "  FAIL $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       | /'; }

# A project that is not a git repo, with the script installed as bin/close-task.sh (no
# toolkit next to it, so the "installed-from" fallback cannot resolve a toolkit root).
PROJ="$TMP/proj"; mkdir -p "$PROJ/bin"
cp "$SUT" "$PROJ/bin/close-task.sh"; chmod +x "$PROJ/bin/close-task.sh"

# A clean PATH: system tools only, no checkpoint.sh.
SYSPATH="/usr/bin:/bin"
mk_ckpt() { mkdir -p "$1"; printf '#!/bin/sh\nexit 0\n' > "$1/checkpoint.sh"; chmod +x "$1/checkpoint.sh"; }

EMPTYHOME="$TMP/home-empty"; mkdir -p "$EMPTYHOME"
NOTK="$TMP/no-toolkit"; mkdir -p "$NOTK"

run() { # $1=HOME $2=PATH $3=MXTK_ROOT [args...]
  local h="$1" p="$2" m="$3"; shift 3
  ( cd "$PROJ" && env -i HOME="$h" PATH="$p" MXTK_ROOT="$m" GIT_CEILING_DIRECTORIES="$TMP" \
      bash "$PROJ/bin/close-task.sh" "$@" 2>&1 )
}

echo "T1 found on PATH"
mk_ckpt "$TMP/pathbin"
out=$(run "$EMPTYHOME" "$TMP/pathbin:$SYSPATH" "$NOTK")
grep -qF "    '$TMP/pathbin/checkpoint.sh' --write" <<<"$out" && ok "T1 prints PATH hit" || bad "T1 prints PATH hit" "$(grep -n -A2 '### Then' <<<"$out")"

echo "T2 found in ~/.claude/bin"
H2="$TMP/home2"; mk_ckpt "$H2/.claude/bin"
out=$(run "$H2" "$SYSPATH" "$NOTK")
grep -qF "    '$H2/.claude/bin/checkpoint.sh' --write" <<<"$out" && ok "T2 prints ~/.claude/bin hit" || bad "T2 prints ~/.claude/bin hit" "$(grep -n -A2 '### Then' <<<"$out")"

echo "T3 found in toolkit claude-hooks/bin"
TK="$TMP/toolkit"; mk_ckpt "$TK/claude-hooks/bin"
out=$(run "$EMPTYHOME" "$SYSPATH" "$TK")
grep -qF "    '$TK/claude-hooks/bin/checkpoint.sh' --write" <<<"$out" && ok "T3 prints toolkit hit" || bad "T3 prints toolkit hit" "$(grep -n -A2 '### Then' <<<"$out")"

echo "T4 lookup order"
out=$(run "$H2" "$TMP/pathbin:$SYSPATH" "$TK")
grep -qF "    '$TMP/pathbin/checkpoint.sh' --write" <<<"$out" && ok "T4a PATH wins" || bad "T4a PATH wins" "$(grep -n -A2 '### Then' <<<"$out")"
out=$(run "$H2" "$SYSPATH" "$TK")
grep -qF "    '$H2/.claude/bin/checkpoint.sh' --write" <<<"$out" && ok "T4b ~/.claude/bin beats toolkit" || bad "T4b ~/.claude/bin beats toolkit" "$(grep -n -A2 '### Then' <<<"$out")"

echo "T5 not found"
out=$(run "$EMPTYHOME" "$SYSPATH" "$NOTK"); rc=$?
grep -qF "checkpoint.sh not installed — run '$NOTK/bin/install-claude-hooks.sh' --basic, or skip: RESUME.md is the resume source" <<<"$out" \
  && ok "T5a install pointer printed" || bad "T5a install pointer printed" "$(grep -n -A2 '### Then' <<<"$out")"
grep -qE '^ +checkpoint\.sh --write' <<<"$out" && bad "T5b no bare checkpoint.sh line" "$(grep -n 'checkpoint.sh --write' <<<"$out")" || ok "T5b no bare checkpoint.sh line"
grep -qF 'OVERWRITE docs/progress/RESUME.md' <<<"$out" && grep -qF 'Shared toolkit:' <<<"$out" \
  && ok "T5c rest of the block still printed" || bad "T5c rest of the block still printed"
[ "$rc" = 0 ] && ok "T5d exit 0 on a clean project" || bad "T5d exit 0 on a clean project (got $rc)"

echo "T6 not found, writes owed"
run "$EMPTYHOME" "$SYSPATH" "$NOTK" --add "exec 010-foo.mdl" >/dev/null
out=$(run "$EMPTYHOME" "$SYSPATH" "$NOTK"); rc=$?
[ "$rc" = 1 ] && ok "T6 exit 1 when writes owed" || bad "T6 exit 1 when writes owed (got $rc)"

echo "T7 paths with spaces"
# Run the printed line through a shell: the path must resolve to the stub we made.
runs_line() { local line; line=$(grep -m1 -E "^    '.*' --write" <<<"$1") || return 1
  ( eval "${line%%#*}" ) >/dev/null 2>&1; }
H7="$TMP/John Doe"; mk_ckpt "$H7/.claude/bin"
out=$(run "$H7" "$SYSPATH" "$NOTK")
grep -qF "    '$H7/.claude/bin/checkpoint.sh' --write" <<<"$out" && runs_line "$out" \
  && ok "T7a space in HOME: quoted and runnable" || bad "T7a space in HOME: quoted and runnable" "$(grep -n -A1 '### Then' <<<"$out")"
TK7="$TMP/my tool's kit"; mk_ckpt "$TK7/claude-hooks/bin"
out=$(run "$EMPTYHOME" "$SYSPATH" "$TK7")
grep -qF "    '$TMP/my tool'\\''s kit/claude-hooks/bin/checkpoint.sh' --write" <<<"$out" && runs_line "$out" \
  && ok "T7b space and ' in toolkit path: quoted and runnable" || bad "T7b space and ' in toolkit path: quoted and runnable" "$(grep -n -A1 '### Then' <<<"$out")"
TK7N="$TMP/no kit here"; mkdir -p "$TK7N"
out=$(run "$EMPTYHOME" "$SYSPATH" "$TK7N")
grep -qF "run '$TK7N/bin/install-claude-hooks.sh' --basic" <<<"$out" \
  && ok "T7c install hint quoted" || bad "T7c install hint quoted" "$(grep -n -A1 '### Then' <<<"$out")"

echo "T8 claude-hooks copy"
HOOKS="$(cd "$(dirname "$SUT")/.." && pwd)/claude-hooks/bin/close-task.sh"
if [ -f "$HOOKS" ]; then
  B8="$H7/.claude/bin"; cp "$HOOKS" "$B8/close-task.sh"
  out=$( cd "$PROJ" && env -i HOME="$H7" PATH="$SYSPATH" GIT_CEILING_DIRECTORIES="$TMP" bash "$B8/close-task.sh" 2>&1 )
  grep -qF "    '$B8/checkpoint.sh' --write" <<<"$out" && runs_line "$out" \
    && ok "T8 sibling path printed, quoted" || bad "T8 sibling path printed, quoted" "$(grep -n -A1 '### Then' <<<"$out")"
else
  bad "T8 claude-hooks/bin/close-task.sh not found next to $SUT"
fi

echo
echo "test-close-task-checkpoint: $pass passed, $fail failed"
[ "$fail" = 0 ]
