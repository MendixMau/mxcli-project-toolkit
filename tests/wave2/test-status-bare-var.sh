#!/usr/bin/env bash
# test-status-bare-var.sh — bin/status.sh --brief must print NEXT, not abort, when its NEXT line
# carries a variable followed by an em-dash (#467).
#
# Usage: bash tests/wave2/test-status-bare-var.sh bin/status.sh
#
# The defect: "$LAST_FAIL— fix…" — in a single-byte locale bash reads the em-dash's first byte as
# part of the variable NAME, and set -u aborts with "LAST_FAIL<byte>: unbound variable" (macOS
# bash 3.2 did it under en_US.UTF-8 too). bash 5 in a UTF-8 locale never shows it, which is why
# it shipped. So the runs below use an ISO-8859-1 locale: the first one `locale -a` lists, or a
# compiled one via LOCPATH (localedef -i en_US -f ISO-8859-1 "$LOCPATH/en_US.ISO-8859-1").
# No such locale: T1/T2 SKIP (stated, not silent) and T3 still runs.
#
#   T1  latest BUILD-LOG row a fail   -> NEXT "last gate FAILED for: 010-a.mdl — …", no abort
#   T2  latest row a pass, not done-  -> NEXT "gate-passed but not done-: 010-a.mdl — …", no abort
#   T3  static guard, any machine: bin/check-portability.sh (same toolkit) flags a bare name
#       before an em-dash and an ellipsis, passes the braced form, a comment line, a positional
#       $1 and a `# portability-ok:` line, and the shipped status.sh/constants-audit.sh are clean
#
# GOLDEN INPUT: PROJECT.md is the real bin/init-project.sh scaffold; the BUILD-LOG row shape is
# project-bin/exec.sh log_build()'s. gate-check.sh is stubbed silent in the toolkit copy so the
# NEXT ladder reaches the two rules under test instead of stopping at a scaffold finding.
export MXTK_LEAKGUARD_DENYFILE="${TMPDIR:-/tmp}/mxtk-fixture-denylist.$$"
export MXTK_NO_GUIDE=1 MXTK_SYNC_SKIP_CLONE_CHECK=1
set -uo pipefail
SUT="${1:?usage: test-status-bare-var.sh /path/to/bin/status.sh}"
case "$SUT" in /*) ;; *) SUT="$PWD/$SUT" ;; esac
SRC="$(cd "$(dirname "$SUT")/.." && pwd)"

W="$(mktemp -d "${TMPDIR:-/tmp}/statusbv.XXXXXX")" || exit 2
trap 'rm -rf "$W"; rm -f "$MXTK_LEAKGUARD_DENYFILE"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/  FAIL-detail: /'; }

echo "== T3 check-portability.sh bare-\$NAME rule (#467) =="
PORT="$SRC/bin/check-portability.sh"
mkdir -p "$W/lint/bad" "$W/lint/good"
# Non-ASCII written as octal escapes so this fixture file itself stays clean under the rule.
EM="$(printf '\342\200\224')"; EL="$(printf '\342\200\246')"
printf '#!/usr/bin/env bash\necho "failed: $X%s fix"\n' "$EM" > "$W/lint/bad/a.sh"
printf '#!/usr/bin/env bash\ns="$s%s"\n' "$EL" > "$W/lint/bad/b.sh"
printf '#!/usr/bin/env bash\necho "${X}%s ok"\n# $X%s in a comment\necho "$1%s"\necho "$X%s" # portability-ok: test\n' \
  "$EM" "$EM" "$EM" "$EM" > "$W/lint/good/c.sh"
out="$(bash "$PORT" "$W/lint/bad" 2>&1)"; rc=$?
n="$(printf '%s\n' "$out" | grep -c 'bare \$NAME followed by a non-ASCII')"
if [ "$rc" -eq 1 ] && [ "$n" -eq 2 ]; then ok "T3a em-dash and ellipsis after a bare name: 2 of 2 flagged"; else bad "T3a want rc 1, 2 hits; got rc $rc, $n" "$out"; fi
out="$(bash "$PORT" "$W/lint/good" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "T3b braced, comment, \$1 and portability-ok: not flagged"; else bad "T3b want rc 0, got $rc" "$out"; fi
mkdir -p "$W/lint/shipped"; cp "$SUT" "$W/lint/shipped/status.sh"
cp "$SRC/project-bin/constants-audit.sh" "$W/lint/shipped/"
out="$(bash "$PORT" "$W/lint/shipped" 2>&1)"
if grep -q 'bare \$NAME' <<<"$out"; then bad "T3c shipped scripts carry a bare name before non-ASCII" "$out"; else ok "T3c status.sh and constants-audit.sh: 0 bare names before non-ASCII"; fi

LOC="$(locale -a 2>/dev/null | grep -iE '^en_US\.ISO-?8859-?1$' | head -1)"
[ -z "$LOC" ] && [ -n "${LOCPATH:-}" ] && [ -d "$LOCPATH/en_US.ISO-8859-1" ] && LOC=en_US.ISO-8859-1
done_() { echo "-- $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]; exit $?; }
if [ -z "$LOC" ]; then echo "  SKIP T1-T2: no ISO-8859-1 locale (see header to compile one)"; done_; fi
# The locale must actually reproduce the trap, or a pass below proves nothing.
if LC_ALL="$LOC" bash -uc "X=a; : \"\$X$EM\"" 2>/dev/null; then
  echo "  SKIP T1-T2: bash under $LOC does not read the byte as a name character here"; done_
fi

mkdir -p "$W/tk"
(cd "$SRC" && tar --exclude=.git --exclude=node_modules -cf - .) | (cd "$W/tk" && tar -xf -)
cp "$SUT" "$W/tk/bin/status.sh"
mkproj() {  # mkproj <gate-cell>
  local d="$W/proj-$1"; mkdir -p "$d/mdlsource" "$d/docs"; : > "$d/Fixture.mpr"
  "$W/tk/bin/init-project.sh" "$d" >/dev/null 2>&1
  { echo "| when (ISO-8601 local) | script | gate | result | detail |"; echo "|---|---|---|---|---|"; } > "$d/docs/BUILD-LOG.md"
  echo "-- a" > "$d/mdlsource/010-a.mdl"
  echo "| 2026-10-13T10:00:00+0200 | \`010-a.mdl\` | $1 | x | 010-a.mdl |" >> "$d/docs/BUILD-LOG.md"
  echo "$d"
}
PF="$(mkproj fail)"; PP="$(mkproj pass)"
printf '#!/usr/bin/env bash\nexit 0\n' > "$W/tk/bin/gate-check.sh"

echo "== bin/status.sh --brief under $LOC (#467) =="
check() {  # check <name> <proj> <expected NEXT prefix>
  local out; out="$(LC_ALL="$LOC" bash "$W/tk/bin/status.sh" "$2" --brief 2>&1)"
  case "$out" in *"unbound variable"*) bad "$1: aborted" "$out"; return ;; esac
  if grep -q "^NEXT    $3" <<<"$out"; then ok "$1"; else bad "$1: NEXT not printed" "$out"; fi
}
check "T1 failed row: NEXT names the script, no abort"      "$PF" 'last gate FAILED for: 010-a.mdl '
check "T2 gate-pass, not done-: NEXT names it, no abort"     "$PP" 'gate-passed but not done-: 010-a.mdl '

done_
