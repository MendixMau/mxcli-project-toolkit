#!/usr/bin/env bash
# Fixture for wave-2 #9, #10, #11, #13 — skills/iterative-build-loop.md.
#
#   #13 (HIGH) the copy-paste exec.sh template branched on
#       [[ -f "$ERRORS_FILE" && -s "$ERRORS_FILE" ]]. --write-errors writes the file
#       ALWAYS ({"problems":[]} on success, which is non-empty), so a CLEAN build took
#       the restore branch, printed "0 error(s) found — restoring snapshot", exited 1
#       and rolled back good work. project-bin/exec.sh had the correct CE_COUNT test;
#       the fix never reached the document people paste from.
#   #9  the loop was called 12-step, 13-step and 15-step; the list had 15 items.
#   #10 gates ran 2 -> 4 -> 3, no Gate 1 ever existed, and the pre-exec `mxcli check`
#       it was implicitly numbered around was in no step and in no script.
#   #11 a Studio Pro handoff table row said no handoff was needed.
#   Root cause of #9-#11: the loop was wrapped in bare ``` fences, so it rendered as a
#       code block and no markdown tool — or reader — ever counted it.
#
# Run against the pre-fix doc and T1-T7 must FAIL. Usage:
#   test-bug09-13.sh /path/to/iterative-build-loop.md
set -uo pipefail

DOC="${1:?usage: test-bug09-13.sh /path/to/iterative-build-loop.md}"
case "$DOC" in /*) ;; *) DOC="$PWD/$DOC" ;; esac
[ -f "$DOC" ] || { echo "no such file: $DOC"; exit 2; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

echo "== T1: #13 no pasteable gate branches on the errors FILE instead of the COUNT =="
# Extract every fenced bash block, then look for the fatal test. Any block that both
# restores a snapshot and decides on -s "$ERRORS_FILE" rolls back clean builds.
BLOCKS="$(awk '/^```bash/ {inb=1; next} /^```$/ {inb=0} inb' "$DOC")"
if printf '%s' "$BLOCKS" | grep -qE '\-s "\$ERRORS_FILE"'; then
  bad "a bash block still gates on the errors file being non-empty — clean builds roll back"
else
  ok "no bash block gates on the errors file's size"
fi
if printf '%s' "$BLOCKS" | grep -q 'restoring snapshot'; then
  # Allowed only if the same block tests the parsed count first.
  printf '%s' "$BLOCKS" | grep -qE 'CE_COUNT.*(= "0"|-eq 0)' \
    && ok "a restoring block tests the parsed CE count" \
    || bad "a block restores a snapshot without ever testing the parsed CE count"
else
  ok "no bash block in this doc restores a snapshot at all"
fi

echo "== T2: #13 the doc points at project-bin/exec.sh instead of shipping a copy =="
grep -q 'project-bin/exec.sh' "$DOC" && ok "points at project-bin/exec.sh" \
                                     || bad "no pointer to the authoritative script"
# The stale-copy tell: fcf5ad0 removed this line from the real script; the embedded
# copy kept it for a day and would have reinstalled the behaviour on every paste.
# Inside a bash block only — the prose that explains the deletion quotes the line.
printf '%s' "$BLOCKS" | grep -q 'Please close the project in Studio Pro' \
  && bad "a pasteable block still ends with the pre-fcf5ad0 'please restart SP' line" \
  || ok "no pasteable pre-fcf5ad0 SP-restart ending"
BASHLINES=$(printf '%s' "$BLOCKS" | grep -c 'mxbuild' || true)
[ "${BASHLINES:-0}" -lt 5 ] && ok "no full mxbuild gate re-implemented inline ($BASHLINES mxbuild lines)" \
                            || bad "a full inline gate is still pasteable ($BASHLINES mxbuild lines)"

echo "== T3: #9 no step count in prose, and the loop is a real list =="
if grep -qE '[0-9]+-[Ss]teps?' "$DOC"; then
  bad "a step count survives in prose: $(grep -oE '[0-9]+-[Ss]teps?' "$DOC" | sort -u | tr '\n' ' ')"
else
  ok "no '<N>-step' claim left to drift"
fi
# The loop must render as an ordered list: its items at column 0, not inside a fence.
LOOPSTART=$(grep -n '^## The Build Loop' "$DOC" | head -1 | cut -d: -f1)
if [ -n "$LOOPSTART" ]; then
  ok "the loop heading no longer states a count"
  SEG=$(awk -v s="$LOOPSTART" 'NR>s && NR<s+130' "$DOC")
  FENCED=$(printf '%s\n' "$SEG" | awk '/^```/ {f=!f; next} f && /^[0-9]+\./ {n++} END {print n+0}')
  ITEMS=$(printf '%s\n' "$SEG" | awk '/^```/ {f=!f; next} !f && /^[0-9]+\./ {n++} END {print n+0}')
  [ "$FENCED" -eq 0 ] && ok "no loop step is inside a code fence" \
                      || bad "$FENCED loop steps still fenced — invisible to every markdown tool"
  [ "$ITEMS" -ge 10 ] && ok "the loop is a real ordered list ($ITEMS items)" \
                      || bad "only $ITEMS top-level list items found under the heading"
else
  bad "no '## The Build Loop' heading (still '## The 12-Step Build Loop'?)"
fi

echo "== T4: #10 gates are named, and the ordinals are gone =="
if grep -qE '\*\*Gate [0-9]' "$DOC"; then
  bad "bold gate ordinals survive: $(grep -oE '\*\*Gate [0-9]+' "$DOC" | sort -u | tr '\n' ' ')"
else
  ok "no bold gate ordinals"
fi
for g in SYNTAX BUILD UI COVERAGE; do
  grep -q "Gate: $g" "$DOC" && ok "Gate: $g named" || bad "Gate: $g missing"
done
grep -qi 'never a Gate 1' "$DOC" && ok "records that Gate 1 never existed" \
                                 || bad "the missing Gate 1 is not explained anywhere"

echo "== T5: #10 the pre-exec syntax gate is a step, not just prose =="
grep -q 'Gate: SYNTAX' "$DOC" && grep -q 'mxcli check --references' "$DOC" \
  && ok "mxcli check --references is named in the loop" \
  || bad "the pre-exec check is still unenforced prose"
grep -q 'before the snapshot' "$DOC" \
  && ok "it is stated to run before the snapshot (prevention, not rollback)" \
  || bad "no statement that it runs before the model is touched"

echo "== T6: #11 the non-handoff row is gone, the note stays =="
if grep -qE '^\| Cross-module associations \|' "$DOC"; then
  bad "the 'no handoff needed' row is still in the handoff table"
else
  ok "row deleted"
fi
grep -q 'No Studio Pro handoff needed' "$DOC" \
  && ok "the adjacent note is kept" \
  || bad "the note was deleted too — anyone holding an old checklist loses the correction"

echo "== T7: the build-log contract is documented where the loop is read =="
grep -q 'BUILD-LOG.md' "$DOC" && ok "the build log is named in the loop" || bad "build log not mentioned"
grep -qi 'ISO-8601' "$DOC" && ok "the ISO-8601 stamp is stated" || bad "no statement of the timestamp format"
grep -q 'not-run' "$DOC" && ok "the gate verdict vocabulary is stated" || bad "gate verdicts undocumented"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
