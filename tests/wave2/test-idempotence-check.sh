#!/usr/bin/env bash
# Fixture for project-bin/idempotence-check.sh: grading `mxcli diff` output as idempotent / not.
#
# usage: bash tests/wave2/test-idempotence-check.sh [/path/to/idempotence-check.sh]
#
# Golden input is captured, never written: fixtures/idempotence-diff/ holds 45 verbatim mxcli v0.28.0
# diff outputs (provenance: CAPTURE.txt) with the verdict an independent second-exec-and-hash arm gave
# each. The parser must reproduce all 45 -- including the trap that a Refused diff ends in the SAME
# "exec would write nothing" Summary an idempotent one gets. Positive control: grading by Summary
# alone (or by exit code) fails every REFUSED row.
set -uo pipefail
TOOLKIT="$(cd "$(dirname "$0")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/project-bin/idempotence-check.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
FX="$TOOLKIT/tests/wave2/fixtures/idempotence-diff"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/idem-t.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; return 0; }
echo "== subject: $SUBJECT"

# A. every capture graded as the independent arm graded it
nbad=0; n=0
while IFS=$'\t' read -r f want; do
  [ -n "$f" ] || continue
  n=$((n+1))
  out="$(bash "$SUBJECT" --parse "$FX/$f" 2>&1)"; rc=$?
  case "$want" in IDEMPOTENT) wrc=0 ;; *) wrc=1 ;; esac
  if [ "$rc" -ne "$wrc" ]; then nbad=$((nbad+1)); bad "A $f: want rc $wrc ($want), got $rc: $(printf '%s' "$out" | head -1)"; continue; fi
  case "$want" in
    REFUSED) printf '%s' "$out" | grep -q 'FAIL (REFUSED)' || { nbad=$((nbad+1)); bad "A $f: not named REFUSED"; } ;;
    CHANGES) printf '%s' "$out" | grep -q 'FAIL (CHANGES)' || { nbad=$((nbad+1)); bad "A $f: not named CHANGES"; } ;;
  esac
done < "$FX/expected.tsv"
[ "$nbad" -eq 0 ] && ok "A all $n captures graded as the second-exec arm graded them"
[ "$n" -eq 45 ] || bad "A expected 45 captures, found $n"

# B. the #667 silent duplication names the menu change
out="$(bash "$SUBJECT" --parse "$FX/S1-nav-insert-667.diff" 2>&1)"
printf '%s' "$out" | grep -q '5 -> 6 items' && ok "B #667 duplicate menu item is shown (5 -> 6 items)" || bad "B no '5 -> 6 items' in output"

# C. not graded PASS on silence: empty input, a bare warning, a Summary without counts
: > "$WORK/empty"; bash "$SUBJECT" --parse "$WORK/empty" >/dev/null 2>&1; [ $? -eq 2 ] && ok "C empty output -> exit 2, not PASS" || bad "C empty output was not UNPARSEABLE"
head -1 "$FX/042-mf-supplier-save.diff" > "$WORK/warnonly"; bash "$SUBJECT" --parse "$WORK/warnonly" >/dev/null 2>&1; [ $? -eq 2 ] && ok "C warning-only output -> exit 2" || bad "C warning-only was not UNPARSEABLE"
printf 'Summary: exec would write nothing\n' > "$WORK/nocount"; bash "$SUBJECT" --parse "$WORK/nocount" >/dev/null 2>&1; [ $? -eq 2 ] && ok "C Summary without counts -> exit 2" || bad "C count-less Summary graded"

# D. Windows/Git Bash shapes of a real capture: CRLF and ANSI colour must not change the grade
sed 's/$/\r/' "$FX/050-request-list.diff" > "$WORK/crlf"; bash "$SUBJECT" --parse "$WORK/crlf" >/dev/null 2>&1; [ $? -eq 1 ] && ok "D CRLF refused capture -> exit 1" || bad "D CRLF capture mis-graded"
sed "s/^Summary/$(printf '\033')[1mSummary$(printf '\033')[0m/" "$FX/042-mf-supplier-save.diff" > "$WORK/ansi"
bash "$SUBJECT" --parse "$WORK/ansi" >/dev/null 2>&1; rc=$?
# an ANSI prefix hides the 'Summary:' anchor: it must come out UNPARSEABLE or PASS, never silently FAIL-open to PASS on a refusal
[ "$rc" -eq 0 ] || [ "$rc" -eq 2 ] && ok "D ANSI-wrapped idempotent capture -> exit $rc" || bad "D ANSI capture exit $rc"
sed "s/^Refused/$(printf '\033')[31mRefused/" "$FX/050-request-list.diff" > "$WORK/ansir"
bash "$SUBJECT" --parse "$WORK/ansir" >/dev/null 2>&1; [ $? -eq 1 ] && ok "D ANSI-coloured Refused still FAIL" || bad "D coloured Refused mis-graded"

# E. wrapper path with a stub mxcli: rc!=0 -> exit 2; a replayed real capture -> its verdict
P="$WORK/proj"; mkdir -p "$P/bin"; printf 'x\n' > "$P/App.mpr"; printf 'create or modify x;\n' > "$P/s.mdl"
cp "$TOOLKIT/project-bin/_common.sh" "$P/bin/"; cp "$SUBJECT" "$P/bin/idempotence-check.sh"
printf '#!/usr/bin/env bash\ncat "%s"\nexit 0\n' "$FX/050-request-list.diff" > "$P/mxcli"; chmod +x "$P/mxcli" "$P/bin/"*.sh
(cd "$P" && bash bin/idempotence-check.sh --mpr "$P/App.mpr" s.mdl) >/dev/null 2>&1; [ $? -eq 1 ] && ok "E exit-0 mxcli printing Refused -> FAIL (exit code is not the verdict)" || bad "E Refused with rc 0 not failed"
printf '#!/usr/bin/env bash\ncat "%s"\nexit 0\n' "$FX/042-mf-supplier-save.diff" > "$P/mxcli"
(cd "$P" && bash bin/idempotence-check.sh --mpr "$P/App.mpr" s.mdl) >/dev/null 2>&1; [ $? -eq 0 ] && ok "E idempotent capture via wrapper -> PASS" || bad "E idempotent wrapper run"
printf '#!/usr/bin/env bash\necho boom >&2\nexit 3\n' > "$P/mxcli"
(cd "$P" && bash bin/idempotence-check.sh --mpr "$P/App.mpr" s.mdl) >/dev/null 2>&1; [ $? -eq 2 ] && ok "E mxcli diff crash -> exit 2" || bad "E crash not exit 2"

# F. a modified page prints as a unified diff header; it is named in the output (field-run capture)
out="$(bash "$SUBJECT" --parse "$FX/fieldrun-050-page-modified.diff" 2>&1)"
printf '%s' "$out" | grep -q 'changed: Page.Purchasing.Request_List' && ok "F modified page named from its '--- X (current)' header" || bad "F page change not named"

echo "== $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
