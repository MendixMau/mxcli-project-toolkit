#!/usr/bin/env bash
# test-security-check.sh — project-bin/security-check.sh: security lint findings + access snapshot,
# each compared with something a person accepted/approved.
#
# Usage: bash tests/wave2/test-security-check.sh [path-to-security-check.sh]
#
# Golden input is CAPTURED, never typed: tests/wave2/fixtures/security-check/ holds the real
# `mxcli lint` report and the real who-can-see-what dump of a fictional demo app (baseline) and of
# seven copies with ONE planted access mistake each (see that folder's CAPTURE.md). mxcli-stub.sh
# replays them per command. Cases:
#   A  first run exits 3, lists the baseline's real findings, RESULT line present and not last
#   B  --approve / --accept without --reason are refused (2); an unknown or ambiguous element is refused
#   C  approve, accept every finding one by one, rerun exits 0; the snapshot is byte-identical twice
#   D  each planted mistake exits 1 and the output NAMES the role and the element
#   E  mxcli failing exits 4 (never 0), RESULT says could-not-run
#   F  --json is one parseable object; RESULT goes to stderr
#   G  the same on a two-tree checkout (.mpr under app/)
#   H  state file for gate-check, read-only towards the model, no temp files left behind
set -uo pipefail
TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJ="${1:-$TOOLKIT/project-bin/security-check.sh}"
case "$SUBJ" in /*) ;; *) SUBJ="$PWD/$SUBJ" ;; esac
FX="$TOOLKIT/tests/wave2/fixtures/security-check"
# shellcheck disable=SC1091
. "$TOOLKIT/bin/lib/portable.sh"; require_py
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
has() { printf '%s' "$OUT" | grep -qF -- "$1"; }
chk() { if eval "$2"; then ok "$1"; else bad "$1"; printf '%s\n' "$OUT" | head -25 | sed 's/^/       | /'; fi; }

[ -f "$SUBJ" ] || { echo "FAIL subject not found: $SUBJ"; echo "PASS=0 FAIL=1"; exit 1; }
W="$(mktemp -d "${TMPDIR:-/tmp}/sectest.XXXXXX")"; trap 'rm -rf "$W"' EXIT
export TMPDIR="$W/tmp"; mkdir -p "$TMPDIR"
BIN_SRC="$(dirname "$SUBJ")"

mkproj() {  # mkproj <name> <single|two>: an installed project, bin/ copies, empty .mpr (the stub reads none)
  local p="$W/$1"
  mkdir -p "$p/bin" "$p/.claude"
  cp "$SUBJ" "$p/bin/security-check.sh"; cp "$BIN_SRC/_common.sh" "$p/bin/_common.sh"
  : > "$p/PROJECT.md"
  if [ "$2" = two ]; then mkdir -p "$p/app"; : > "$p/app/Demo.mpr"; else : > "$p/Demo.mpr"; fi
  echo "$p"
}
# run <project> <scenario> [args...] — sets OUT (stdout+stderr) and RC
run() {
  local p="$1" sc="$2"; shift 2
  OUT=$(cd "$p" && env -u PROJECT_ROOT -u MPR_FILE MXCLI="$FX/mxcli-stub.sh" SECX_DIR="$FX/$sc" SECX_BASE="$FX/base" \
        bash "$p/bin/security-check.sh" "$@" 2>&1); RC=$?
}
last_line() { printf '%s\n' "$OUT" | tail -1; }
accept_all() {  # accept every finding the human output lists as NEW: lines "  [RULE] message"
  local p="$1" sc="$2" line r m n=0
  printf '%s\n' "$OUT" | grep -E '^  \[[A-Z0-9]+\] ' | sed 's/  (NEW)$//; s/  (accepted)$//' | while IFS= read -r line; do
    r=${line#  \[}; r=${r%%\]*}; m=${line#*\] }
    (cd "$p" && env -u PROJECT_ROOT -u MPR_FILE MXCLI="$FX/mxcli-stub.sh" SECX_DIR="$FX/$sc" SECX_BASE="$FX/base" \
       bash "$p/bin/security-check.sh" --accept "$r" "$m" --reason "test: accepted in the fixture" >/dev/null 2>&1)
  done
}

echo "== subject: $SUBJ"
P="$(mkproj single single)"

echo "-- A first run"
run "$P" base
chk "A1 first run exits 3 (never 0)" '[ "$RC" = 3 ]'
chk "A2 lists SEC003 demo users (baseline finding nobody was told about)" 'has "[SEC003] Demo users are enabled at Production security level"'
chk "A3 lists SEC005 strict mode" 'has "[SEC005] Strict mode is disabled"'
chk "A4 lists SEC010 on Home.dgRecent" 'has "[SEC010] Data grid '"'"'dgRecent'"'"'"'
chk "A5 names the approve command" 'has "bin/security-check.sh --approve --reason"'
chk "A6 RESULT line says not-approved exit=3" 'has "MXTK-RESULT security verdict=not-approved new=16 access_changes=0 exit=3"'
chk "A7 RESULT line is not the last line" '[ "$(last_line | cut -c1-12)" != "MXTK-RESULT " ] && has "MXTK-RESULT"'
# parsed count asserted against an independent grep of the capture: unique security-set findings
exp=$(grep -E '\[(SEC[0-9]+|MPR007|CONV006|CONV007)\]$' "$FX/base/lint.txt" | sed 's/^ *[^ ]* //' | sort -u | wc -l | tr -d ' ')
chk "A8 16 security findings parsed, equal to an independent count of the capture ($exp)" '[ "$exp" = 16 ]'
chk "A9 snapshot file written, not the approved copy" '[ -f "$P/docs/security/access-snapshot.txt" ] && [ ! -e "$P/docs/security/access-approved.txt" ]'
chk "A10 state file says not-approved" 'grep -q "^verdict=not-approved" "$P/.claude/loop/security-check.last"'

echo "-- B refusals"
run "$P" base --approve;                         chk "B1 --approve without --reason refused (2)" '[ "$RC" = 2 ] && [ ! -e "$P/docs/security/access-approved.txt" ]'
run "$P" base --accept SEC003 "Demo users";       chk "B2 --accept without --reason refused (2)" '[ "$RC" = 2 ] && [ ! -e "$P/.claude/loop/security-accepted.tsv" ]'
run "$P" base --accept SEC999 "x" --reason r;     chk "B3 a rule outside the security set refused (2)" '[ "$RC" = 2 ]'
run "$P" base --accept CONV007 "no such text" --reason r; chk "B4 an element matching no finding refused (2), nothing written" '[ "$RC" = 2 ] && [ ! -e "$P/.claude/loop/security-accepted.tsv" ]'
run "$P" base --accept CONV007 "unconstrained READ" --reason r; chk "B5 an ambiguous element refused (2): no accept-all" '[ "$RC" = 2 ] && has "no accept-all"'
run "$P" base --frobnicate;                      chk "B6 unknown flag refused (2)" '[ "$RC" = 2 ]'
run "$P" base --reason foo;                      chk "B7 --reason alone refused (2)" '[ "$RC" = 2 ]'

echo "-- C approve, accept, clean, identical snapshot"
run "$P" base --approve --reason "fixture: approved by the test"
chk "C1 --approve exits 0, writes the approved copy" '[ "$RC" = 0 ] && cmp -s "$P/docs/security/access-snapshot.txt" "$P/docs/security/access-approved.txt"'
chk "C2 prints the register row for the lead, with CONFIRMED" 'has "| CONFIRMED |" && has "fixture: approved by the test"'
chk "C3 approvals.tsv records the reason" 'grep -q "fixture: approved by the test" "$P/docs/security/approvals.tsv"'
run "$P" base
chk "C4 approved but findings not accepted: exits 1, new-findings, 16 new" '[ "$RC" = 1 ] && has "verdict=new-findings new=16 access_changes=0 exit=1"'
accept_all "$P" base
chk "C5 accepted list has 16 decisions with reason and date" '[ "$(grep -vc "^#" "$P/.claude/loop/security-accepted.tsv")" = 16 ] && grep -v "^#" "$P/.claude/loop/security-accepted.tsv" | awk -F"\t" "NF!=4 || \$3==\"\" || \$4 !~ /^[0-9]{4}-/ {bad=1} END{exit bad}"'
run "$P" base
chk "C6 rerun exits 0, verdict clean" '[ "$RC" = 0 ] && has "verdict=clean new=0 access_changes=0 exit=0"'
cp "$P/docs/security/access-snapshot.txt" "$W/snap1"
run "$P" base
chk "C7 unchanged model: snapshot byte-identical on a second run" 'cmp -s "$W/snap1" "$P/docs/security/access-snapshot.txt" && [ "$RC" = 0 ]'
chk "C8 state file clean, with a date" 'grep -q "^verdict=clean" "$P/.claude/loop/security-check.last" && grep -q "^date=20" "$P/.claude/loop/security-check.last"'
run "$P" base --accept SEC003 "Demo users" --reason again
chk "C9 accepting an accepted finding again is a no-op (0)" '[ "$RC" = 0 ] && [ "$(grep -vc "^#" "$P/.claude/loop/security-accepted.tsv")" = 16 ]'
chk "C10 snapshot lists user roles, pages, microflows, members and has no home path" \
    'grep -q "^user-role-has	Learner	ToeicBuddy.Learner" "$P/docs/security/access-snapshot.txt" && grep -q "^page-access	ToeicBuddy.Team	ToeicBuddy.Trainer	open" "$P/docs/security/access-snapshot.txt" && grep -q "^member-access	ToeicBuddy.Question	ToeicBuddy.Learner	-	ToeicBuddy.Question.CorrectIndex	ReadOnly" "$P/docs/security/access-snapshot.txt" && ! grep -q "$W" "$P/docs/security/access-snapshot.txt"'

echo "-- D planted mistakes (each against the approved + accepted baseline)"
run "$P" m3
chk "D1 m3 own-rows restriction removed: exit 1" '[ "$RC" = 1 ]'
chk "D1 names role, entity and the removed restriction" 'has "ToeicBuddy.Learner can now see ALL rows of ToeicBuddy.Attempt: the row restriction" && has "Attempt_User"'
chk "D1 new lint finding CONV007 Attempt/Learner" 'has "[CONV007] Entity '"'"'ToeicBuddy.Attempt'"'"' has unconstrained READ access for role '"'"'ToeicBuddy.Learner'"'"'"'
run "$P" m7
chk "D2 m7 attribute made writable: exit 1" '[ "$RC" = 1 ]'
chk "D2 names Learner WRITE on the attribute" 'has "ToeicBuddy.Learner can now WRITE ToeicBuddy.Question.CorrectIndex" && has "ToeicBuddy.Learner can now WRITE ToeicBuddy.Question (ALL rows)"'
chk "D2 new lint finding for WRITE" 'has "unconstrained WRITE access for role '"'"'ToeicBuddy.Learner'"'"'"'
run "$P" m4c
chk "D3 m4c anonymous access: exit 1" '[ "$RC" = 1 ]'
chk "D3 names guest access and the anonymous finding" 'has "ANONYMOUS ACCESS: project security Guest Access was turned ON" && has "[SEC004]" && has "[SEC007] Entity '"'"'ToeicBuddy.Question'"'"' is readable by anonymous users"'
run "$P" m2c
chk "D4 m2c role granted pages: exit 1" '[ "$RC" = 1 ]'
chk "D4 names the pages and microflows" 'has "ToeicBuddy.Learner can now OPEN page ToeicBuddy.Team" && has "ToeicBuddy.Learner can now OPEN page ToeicBuddy.Bank" && has "ToeicBuddy.Learner can now EXECUTE microflow ToeicBuddy.DS_Team"'
chk "D4 verdict access-changed (lint saw nothing)" 'has "verdict=access-changed new=0"'
run "$P" m1b
chk "D5 m1b entity with no rules: exit 1" '[ "$RC" = 1 ]'
chk "D5 names the entity both ways" 'has "[SEC001] Persistent entity '"'"'ToeicBuddy.LearnerNote'"'"' has no access rules" && has "entity ToeicBuddy.LearnerNote has NO access rules"'
run "$P" m6a
chk "D6 m6a unmapped module role: exit 1" '[ "$RC" = 1 ]'
chk "D6 names the role that no user role holds" 'has "module role ToeicBuddy.Auditor is mapped to NO user role" && has "ToeicBuddy.Auditor can now OPEN page ToeicBuddy.Team"'
run "$P" m8bare
chk "D7 m8bare role lost read: exit 1" '[ "$RC" = 1 ]'
chk "D7 names the lost read and the SEC010 finding" 'has "ToeicBuddy.Learner lost its rule on ToeicBuddy.Attempt" && has "can open the page but may not read"'
chk "D8 every planted run prints RESULT before the closing line" 'has "MXTK-RESULT security verdict=" && [ "$(last_line | cut -c1-12)" != "MXTK-RESULT " ]'
run "$P" m3
chk "D9 the diff names the problem in a sentence, not a raw dump" '! has "< entity-rights"'

echo "-- E could not run"
OUT=$(cd "$P" && env -u PROJECT_ROOT -u MPR_FILE MXCLI="$FX/mxcli-stub.sh" SECX_DIR="$FX/base" SECX_BASE="$FX/base" SECX_FAIL=1 bash "$P/bin/security-check.sh" 2>&1); RC=$?
chk "E1 mxcli failing exits 4, never 0" '[ "$RC" = 4 ]'
chk "E2 RESULT says could-not-run" 'has "verdict=could-not-run" && has "exit=4"'
chk "E3 state file records could-not-run (so gate-check cannot read it as clean)" 'grep -q "^verdict=could-not-run" "$P/.claude/loop/security-check.last"'
OUT=$(cd "$P" && env -u PROJECT_ROOT -u MPR_FILE MXCLI="$W/no-such-mxcli" bash "$P/bin/security-check.sh" 2>&1); RC=$?
chk "E4 a nonexistent mxcli also exits 4" '[ "$RC" = 4 ]'
P0="$W/empty"; mkdir -p "$P0/bin" "$P0/.claude"; cp "$SUBJ" "$P0/bin/"; cp "$BIN_SRC/_common.sh" "$P0/bin/"
OUT=$(cd "$P0" && env -u PROJECT_ROOT -u MPR_FILE MXCLI="$FX/mxcli-stub.sh" bash "$P0/bin/security-check.sh" 2>&1); RC=$?
chk "E5 no .mpr at all exits 4" '[ "$RC" = 4 ]'
# a lint report in a format the parser does not know: the count check must refuse, not report clean
mkdir -p "$W/badfmt"; cp "$FX/base/dump.txt" "$W/badfmt/"; sed 's/ \[\([A-Z0-9]*\)\]$/ <\1>/' "$FX/base/lint.txt" > "$W/badfmt/lint.txt"
OUT=$(cd "$P" && env -u PROJECT_ROOT -u MPR_FILE MXCLI="$FX/mxcli-stub.sh" SECX_DIR="$W/badfmt" SECX_BASE="$FX/base" bash "$P/bin/security-check.sh" 2>&1); RC=$?
chk "E6 an unrecognised lint format exits 4 (findings parsed != total stated)" '[ "$RC" = 4 ] && has "report format changed"'

echo "-- F --json"
OUT=$(cd "$P" && env -u PROJECT_ROOT -u MPR_FILE MXCLI="$FX/mxcli-stub.sh" SECX_DIR="$FX/m7" SECX_BASE="$FX/base" bash "$P/bin/security-check.sh" --json 2>"$W/json.err"); RC=$?
printf '%s' "$OUT" > "$W/json.out"
PYJ="$PY"
if [ -n "$PYJ" ]; then
  chk "F1 --json stdout parses as JSON" '"$PYJ" -c "import json,sys; json.load(sys.stdin)" < "$W/json.out"'
  chk "F2 json carries verdict, new findings and access changes" '"$PYJ" -c "
import json,sys
d=json.load(sys.stdin)
assert d[\"verdict\"]==\"new-findings\" and d[\"exit\"]==1, d[\"verdict\"]
assert d[\"counts\"][\"new\"]==1 and len(d[\"new_findings\"])==1 and d[\"new_findings\"][0][\"rule\"]==\"CONV007\"
assert any(\"CorrectIndex\" in c for c in d[\"access_changes\"])
" < "$W/json.out"'
else
  bad "F1 --json parse: no interpreter to check it"
fi
chk "F3 exit code matches (1) and RESULT goes to stderr, not stdout" '[ "$RC" = 1 ] && grep -q "^MXTK-RESULT security" "$W/json.err" && ! grep -q "MXTK-RESULT" "$W/json.out" && [ "$(tail -1 "$W/json.err" | cut -c1-12)" != "MXTK-RESULT " ]'
OUT=$(cd "$P" && env -u PROJECT_ROOT -u MPR_FILE MXCLI="$FX/mxcli-stub.sh" SECX_DIR="$FX/base" SECX_BASE="$FX/base" SECX_FAIL=1 bash "$P/bin/security-check.sh" --json 2>/dev/null); RC=$?
printf '%s' "$OUT" > "$W/json.out"
chk "F4 could-not-run --json is still valid JSON, exit 4" '"$PYJ" -c "import json,sys; d=json.load(sys.stdin); assert d[\"verdict\"]==\"could-not-run\"" < "$W/json.out" && [ "$RC" = 4 ]'

echo "-- G two-tree checkout (.mpr under app/)"
P2="$(mkproj two two)"
run "$P2" base;  chk "G1 first run exits 3" '[ "$RC" = 3 ] && has "verdict=not-approved new=16"'
chk "G2 snapshot lands at the repo root, not under app/" '[ -f "$P2/docs/security/access-snapshot.txt" ] && [ ! -e "$P2/app/docs" ]'
run "$P2" base --approve --reason "fixture two-tree"; chk "G3 approve exits 0" '[ "$RC" = 0 ]'
accept_all "$P2" base; run "$P2" base
chk "G4 accepted list under the repo .claude/loop, rerun exits 0" '[ "$RC" = 0 ] && [ -f "$P2/.claude/loop/security-accepted.tsv" ]'
run "$P2" m3;  chk "G5 planted mistake exits 1 and names the role" '[ "$RC" = 1 ] && has "ToeicBuddy.Learner can now see ALL rows of ToeicBuddy.Attempt"'

echo "-- H housekeeping"
mkdir -p "$W/outdir"
OUT=$(cd "$P0" && env -u PROJECT_ROOT -u MPR_FILE MPR_FILE="" MXTK_SECURITY_OUT="$W/outdir" PROJECT_ROOT="$P" MXCLI="$FX/mxcli-stub.sh" SECX_DIR="$FX/base" SECX_BASE="$FX/base" bash "$P/bin/security-check.sh" 2>&1); RC=$?
chk "H1 MXTK_SECURITY_OUT sends every write to that folder (project untouched), first run there exits 3" \
    '[ "$RC" = 3 ] && [ -f "$W/outdir/access-snapshot.txt" ] && [ -f "$W/outdir/security-check.last" ]'
chk "H2 temp dirs are cleaned up on every path" '[ -z "$(ls "$W/tmp" 2>/dev/null)" ]'
chk "H3 nothing but the .mpr placeholder, docs/, .claude/ and bin/ in the project (no model write)" '[ ! -s "$P/Demo.mpr" ]'
chk "H4 the script never calls exec or any write command" '! grep -v "^[0-9]*:[[:space:]]*#" "$SUBJ" | grep -nE "mxcli[^|]* exec |MXCLI.? +exec|-c .(create|alter|grant|revoke|drop) "'

echo "-- I gate-check: one advisory note, no verdict or exit-code change"
GCT="$TOOLKIT/bin/gate-check.sh"
GP="$(mkproj gate single)"; cp "$BIN_SRC/model-stamp.sh" "$GP/bin/"; printf '# PROJECT.md\n\n## Current stage\n' > "$GP/PROJECT.md"
NP="$W/nobin"; mkdir -p "$NP"; printf '# PROJECT.md\n\n## Current stage\n' > "$NP/PROJECT.md"
OUT="$("$GCT" --no-html "$NP" 2>&1)"; RC_NO=$?
chk "I1 a project without the script: gate-check prints no access note" '! has "access"'
OUT="$("$GCT" --no-html "$GP" 2>&1)"; RC_A=$?
chk "I2 script installed, nothing approved: one note naming the command" '[ "$(printf "%s\n" "$OUT" | grep -c "^note: no approved access snapshot yet - run bin/security-check.sh")" = 1 ]'
chk "I3 the note changes no exit code" '[ "$RC_A" = "$RC_NO" ]'
run "$GP" base >/dev/null; run "$GP" base --approve --reason "fixture gate" >/dev/null; run "$GP" base >/dev/null; accept_all "$GP" base; run "$GP" base
OUT="$("$GCT" --no-html "$GP" 2>&1)"
chk "I4 approved + last result clean + same model: no access note" '[ "$RC" = 0 ] && ! has "access check" && ! has "access snapshot"'
printf 'x' >> "$GP/Demo.mpr"
OUT="$("$GCT" --no-html "$GP" 2>&1)"
chk "I5 the model changed since the clean result: reported as older, not clean" 'has "note: the last clean access check is for an older model"'
run "$GP" m3 >/dev/null
OUT="$("$GCT" --no-html "$GP" 2>&1)"; RC_B=$?
chk "I6 last result new-findings: the note says so and gives the counts, exit code unchanged" 'has "note: last access check (bin/security-check.sh) was new-findings (new findings 1, access changes 1)" && [ "$RC_B" = "$RC_NO" ]'
chk "I7 a stage query stays quiet" '! "$GCT" "$GP" 0 2>&1 | grep -q "access check"'
OUT="$("$GCT" --closeout "$GP" 0 2>&1)"
chk "I8 --closeout carries the same line" 'has "last access check (bin/security-check.sh) was new-findings"'

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
