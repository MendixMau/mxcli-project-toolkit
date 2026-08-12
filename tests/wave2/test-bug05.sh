#!/usr/bin/env bash
# Fixture for wave-2 #5: gate-check.sh must never destroy an index.html it did not write,
# and must not dirty a working tree to answer a stage query.
#
# Run against the PRE-fix script and it must fail T1/T2/T3 — that is the positive control.
# A suite that has only ever seen the fix cannot show that it discriminates.
set -uo pipefail

GATE="${1:?usage: test-bug05.sh /path/to/gate-check.sh}"
PREFIX_GATE="${2:-/tmp/wave2/gate-check-PREFIX.sh}"
WORK="$(mktemp -d /tmp/bug05.XXXXXX)"
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

mkproj() {
  d="$WORK/$1"; mkdir -p "$d"
  printf 'Toolkit commit: none\n' > "$d/PROJECT.md"
  echo "$d"
}

echo "== T1: refuses to destroy a hand-written index.html =="
P="$(mkproj t1)"
printf '<!DOCTYPE html><h1>Real landing page</h1>\n' > "$P/index.html"
BEFORE="$(cat "$P/index.html")"
"$GATE" "$P" >/dev/null 2>&1
AFTER="$(cat "$P/index.html")"
[ "$BEFORE" = "$AFTER" ] && ok "hand-written page survived" || bad "hand-written page DESTROYED"

echo "== T2: a stage query writes nothing at all =="
P="$(mkproj t2)"
"$GATE" "$P" >/dev/null 2>&1              # seed a real board
[ -f "$P/index.html" ] && ok "informational run does write a board" || bad "no board written"
SEED="$(cat "$P/index.html" 2>/dev/null)"
rm -f "$P/index.html"
"$GATE" "$P" 0 >/dev/null 2>&1
[ ! -f "$P/index.html" ] && ok "stage query left no board" || bad "stage query wrote a board"

echo "== T3: rewrites its OWN board, and says so only when it changed =="
P="$(mkproj t3)"
"$GATE" "$P" >/dev/null 2>&1
OUT2="$("$GATE" "$P" 2>&1)"
# Must discriminate against the pre-fix script, which prints "index.html regenerated at"
# unconditionally. Grepping only for the NEW wording would pass on the old script.
if printf '%s' "$OUT2" | grep -qE 'index\.html (updated|regenerated)'; then
  bad "announced a write when nothing changed"
else
  ok "silent when the board is unchanged"
fi
printf 'x\n' >> "$P/index.html"   # our sentinel is still present, so it may rewrite
OUT3="$("$GATE" "$P" 2>&1)"
printf '%s' "$OUT3" | grep -q 'index.html updated' \
  && ok "announced the rewrite of its own drifted board" \
  || bad "silently declined to repair its own board"

echo "== T4: --no-html suppresses, --html forces =="
# Exit status is part of the assertion. The pre-fix script also "writes nothing" for
# --no-html, but only because it treats the flag as a project path and dies. A test that
# checks the file alone passes on the bug.
P="$(mkproj t4)"
"$GATE" --no-html "$P" >/dev/null 2>&1; RC=$?
if [ "$RC" -eq 0 ] && [ ! -f "$P/index.html" ]; then
  ok "--no-html recognised (exit 0) and wrote nothing"
else
  bad "--no-html not recognised (exit $RC) or still wrote"
fi
"$GATE" --html "$P" 0 >/dev/null 2>&1
[ -f "$P/index.html" ] && ok "--html forced a board on a stage query" || bad "--html did not force"

echo "== T5: a path containing spaces still works =="
P="$(mkproj 'has space')"
"$GATE" "$P" >/dev/null 2>&1
[ -f "$P/index.html" ] && ok "space-in-path project handled" || bad "space-in-path project broke"

echo "== T6: unknown option is rejected AS AN OPTION =="
# The pre-fix script also exits 2 here — but as "unknown stage", having swallowed --bogus
# as the project directory. Exit code alone cannot tell the two apart; the message can.
ERR="$("$GATE" --bogus "$WORK/t1" 2>&1 >/dev/null)"; RC=$?
if [ "$RC" -eq 2 ] && printf '%s' "$ERR" | grep -qi "unknown option"; then
  ok "unknown option rejected as an option"
else
  bad "not rejected as an option (exit $RC): $(printf '%s' "$ERR" | head -1)"
fi

echo "== T7: adopts a LEGACY board written before the sentinel existed =="
# Migration case. Every board on disk today predates the sentinel; refusing them all would
# break every wired repo on first run.
P="$(mkproj t7)"
"$PREFIX_GATE" "$P" >/dev/null 2>&1   # a genuine pre-fix board, no sentinel
if [ -f "$P/index.html" ] && ! grep -qF 'generated-by: mxcli-project-toolkit' "$P/index.html"; then
  OUT="$("$GATE" "$P" 2>&1)"
  if printf '%s' "$OUT" | grep -q 'Refusing to overwrite'; then
    bad "refused its own legacy board — would break every existing project"
  elif grep -qF 'generated-by: mxcli-project-toolkit' "$P/index.html"; then
    ok "legacy board adopted and stamped with the sentinel"
  else
    bad "legacy board neither refused nor adopted"
  fi
else
  bad "could not stage a legacy board (pre-fix script did not write one)"
fi

echo "== T8: a page that merely mentions the toolkit is still refused =="
P="$(mkproj t8)"
printf '<h1>Notes</h1><p>Re-run bin/gate-check.sh when you get a chance.</p>\n' > "$P/index.html"
BEFORE="$(cat "$P/index.html")"
"$GATE" "$P" >/dev/null 2>&1
[ "$BEFORE" = "$(cat "$P/index.html")" ] \
  && ok "near-miss page survived (adoption needs both markers)" \
  || bad "adoption heuristic too loose — destroyed a near-miss page"

echo ""
echo "PASS=$PASS FAIL=$FAIL   ($WORK)"
[ "$FAIL" -eq 0 ]
