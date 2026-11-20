#!/usr/bin/env bash
# test-fixture-denylist-isolation.sh — fixtures that scaffold through init-project.sh, run ALONE (the
# scoped way CLAUDE.md "Testing this toolkit" asks for), leave no .leakguard-deny in the toolkit root.
#
# Usage: bash tests/wave2/test-fixture-denylist-isolation.sh [path-to-init-project.sh] [fixture ...]
#   (the toolkit is the one holding that init-project.sh; fixtures default to the four that leaked)
#
# WHY: init-project.sh writes each project's name into $TOOLKIT_ROOT/.leakguard-deny unless
# MXTK_LEAKGUARD_DENYFILE points elsewhere. run-all.sh exports it for every fixture, but a fixture
# run on its own got no such cover: test-mode-contract.sh wrote `\bhand\b`, test-ci-gates.sh `\bc6\b`,
# test-must-haves-advisory.sh `\bold\b`/`\bmid\b`/`\bfresh\b`, and the pre-commit leak guard then
# flagged nearly every file for whoever committed next in that clone (2026-11-19, several sessions).
#
# The fixtures run in a COPY of the toolkit (tracked + untracked, gitignored files excluded), so a
# leaking fixture pollutes the copy and never the developer's real clone. The fixtures' own pass/fail
# is not this test's business and is only reported; the one assertion is the denylist, before vs after.
set -uo pipefail

SUBJECT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin/init-project.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
TK="$(cd "$(dirname "$SUBJECT")/.." && pwd)"
shift 2>/dev/null || true
FIXTURES=("$@")
[ "${#FIXTURES[@]}" -gt 0 ] || FIXTURES=(test-mode-contract.sh test-ci-gates.sh test-gitignore-crlf.sh test-must-haves-advisory.sh)

WORK="$(mktemp -d "${TMPDIR:-/tmp}/deny-iso.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }

COPY="$WORK/tk"; mkdir -p "$COPY"
( cd "$TK" && git ls-files -co --exclude-standard -z | tar --null -T - -cf - 2>/dev/null ) | ( cd "$COPY" && tar xf - ) \
  || { echo "could not copy $TK"; exit 2; }
( cd "$COPY" && git init -q . && git add . >/dev/null 2>&1 && git -c user.name=t -c user.email=t@t commit -qm copy ) >/dev/null 2>&1
[ ! -e "$COPY/.leakguard-deny" ] || { echo "copy already holds a denylist"; exit 2; }

# The cover run-all.sh gives is exactly what must not be inherited here.
unset MXTK_LEAKGUARD_DENYFILE
export MXTK_NO_GUIDE=1

for fx in "${FIXTURES[@]}"; do
  f="$COPY/tests/wave2/$fx"
  [ -f "$f" ] || { bad "$fx: not in the toolkit"; continue; }
  arg=""
  case "$fx" in test-must-haves-advisory.sh) arg="$COPY/bin/sync-project.sh" ;; esac
  before="$(cat "$COPY/.leakguard-deny" 2>/dev/null)"
  ( cd "$WORK" && HOME="$WORK/home" bash "$f" $arg </dev/null >"$WORK/$fx.out" 2>&1 ); rc=$?
  after="$(cat "$COPY/.leakguard-deny" 2>/dev/null)"
  if [ "$before" = "$after" ] && [ ! -e "$COPY/.leakguard-deny" ]; then
    ok "$fx leaves no .leakguard-deny in the toolkit root (fixture rc=$rc)"
  else
    bad "$fx wrote to the toolkit's .leakguard-deny: $(printf '%s' "$after" | grep -v '^#' | tr '\n' ' ')"
    rm -f "$COPY/.leakguard-deny"
  fi
done

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
