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
# has() looks at the output with the plain words after a rule id removed ("[SEC003 - words]" -> "[SEC003]");
# hasraw() looks at it as printed.
strip_desc() { sed -E 's/^(  \[[A-Z0-9]+) - [^]]*\]/\1]/'; }
# here-strings, not `printf | grep -q`: under pipefail an early grep exit can fail a passing check
has() { local s; s=$(strip_desc <<<"$OUT"); grep -qF -- "$1" <<<"$s"; }
hasraw() { grep -qF -- "$1" <<<"$OUT"; }
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
  case "$sc" in /*) ;; *) sc="$FX/$sc" ;; esac
  OUT=$(cd "$p" && env -u PROJECT_ROOT -u MPR_FILE MXCLI="$FX/mxcli-stub.sh" SECX_DIR="$sc" SECX_BASE="$FX/base" \
        bash "$p/bin/security-check.sh" "$@" 2>&1); RC=$?
}
last_line() { printf '%s\n' "$OUT" | tail -1; }
accept_all() {  # accept every finding the human output lists as NEW: lines "  [RULE] message"
  local p="$1" sc="$2" line r m n=0
  case "$sc" in /*) ;; *) sc="$FX/$sc" ;; esac
  printf '%s\n' "$OUT" | strip_desc | grep -E '^  \[[A-Z0-9]+\] ' | sed 's/  (NEW)$//; s/  (accepted)$//' | while IFS= read -r line; do
    r=${line#  \[}; r=${r%%\]*}; m=${line#*\] }
    (cd "$p" && env -u PROJECT_ROOT -u MPR_FILE MXCLI="$FX/mxcli-stub.sh" SECX_DIR="$sc" SECX_BASE="$FX/base" \
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
chk "E1b S1: the could-not-run message shows what mxcli printed" 'has "failed to connect: mpr file not found"'
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
chk "I2 script installed, nothing approved: one note naming the command" '[ "$(grep -c "^note: no approved access snapshot yet - run bin/security-check.sh" <<<"$OUT")" = 1 ]'
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
chk "I7 a stage query stays quiet" 'o7=$("$GCT" "$GP" 0 2>&1); ! grep -q "access check" <<<"$o7"'
OUT="$("$GCT" --closeout "$GP" 0 2>&1)"
chk "I8 --closeout carries the same line" 'has "last access check (bin/security-check.sh) was new-findings"'
GQ="$(mkproj gateq single)"; cp "$BIN_SRC/model-stamp.sh" "$GQ/bin/"; printf '# PROJECT.md\n\n## Current stage\n' > "$GQ/PROJECT.md"
run "$GQ" base >/dev/null; run "$GQ" base --approve --reason "fixture gate q" >/dev/null; accept_all "$GQ" base; run "$GQ" base
OUT="$("$GCT" --no-html "$GQ" 2>&1)"; RC_Q1=$?
chk "I9 clean and fresh: no access note (baseline for the next case)" '[ "$RC" = 0 ] && ! has "access check"'
rm -f "$GQ/bin/model-stamp.sh"
OUT="$("$GCT" --no-html "$GQ" 2>&1)"; RC_Q2=$?
chk "I10 no model fingerprint available: the note says freshness is unknown, with the date" 'has "note: last clean access check 20" && has "freshness unknown - re-run bin/security-check.sh"'
chk "I11 that note changes no exit code" '[ "$RC_Q1" = "$RC_Q2" ]'


echo "-- J review round: R1 lint rules installed"
OUT=$(cd "$P" && env -u PROJECT_ROOT -u MPR_FILE MXCLI="$FX/mxcli-stub.sh" SECX_LISTRULES="$FX/list-rules-no-starlark.txt" SECX_DIR="$FX/base" SECX_BASE="$FX/base" bash "$P/bin/security-check.sh" 2>&1); RC=$?
chk "J1 the Starlark security rules absent from --list-rules: could-not-run (4), never 0" '[ "$RC" = 4 ] && has "verdict=could-not-run"'
chk "J1b the message names the missing ids and the command that installs them" 'has "SEC004" && has "CONV006" && has "CONV007" && has "mxcli init" && ! has "SEC001 SEC003"'
OUT=$(cd "$P" && env -u PROJECT_ROOT -u MPR_FILE MXCLI="$FX/mxcli-stub.sh" SECX_DIR="$FX/base" SECX_BASE="$FX/base" bash "$P/bin/security-check.sh" 2>&1); RC=$?
chk "J1c with the rules listed (real capture) the same project is not blocked" '[ "$RC" != 4 ]'
chk "J1d the capture lists every required id (independent grep)" 'for i in SEC001 SEC003 SEC004 SEC005 SEC007 SEC010 MPR007 CONV006 CONV007; do grep -q "^  $i (" "$FX/list-rules.txt" || exit 1; done; ! grep -q "^  SEC004 (" "$FX/list-rules-no-starlark.txt"'

echo "-- K R2 row restriction on two lines; unknown lines; dump shape"
mkscen() {  # mkscen <name> <sed-script on dump.txt>: a scenario = base lint + an edited copy of the CAPTURED dump
  mkdir -p "$W/sc/$1"; cp "$FX/base/lint.txt" "$W/sc/$1/lint.txt"; sed "$2" "$FX/base/dump.txt" > "$W/sc/$1/dump.txt"
}
WH="  where '\[ToeicBuddy.Attempt_User = ''\[%CurrentUser%\]'']'"
mkscen two1 "s/^$WH\$/  where '[ToeicBuddy.Attempt_User = ''[%CurrentUser%]'']\n  and Active = true'/"
mkscen two2 "s/^$WH\$/  where '[ToeicBuddy.Attempt_User = ''[%CurrentUser%]'']\n  or true()'/"
chk "K0 the two-line scenario really has the restriction on two lines" 'grep -q "^  or true()" "$W/sc/two2/dump.txt" && grep -q "^  and Active = true" "$W/sc/two1/dump.txt"'
PK="$(mkproj k single)"
run "$PK" "$W/sc/two1" >/dev/null; run "$PK" "$W/sc/two1" --approve --reason "fixture k"; accept_all "$PK" "$W/sc/two1"; run "$PK" "$W/sc/two1"
chk "K1 two-line restriction approved, rerun clean (0)" '[ "$RC" = 0 ]'
chk "K1b the second line is in the snapshot" 'grep -q "Active = true" "$PK/docs/security/access-snapshot.txt"'
run "$PK" "$W/sc/two2"
chk "K2 only line 2 changed (widened to or true()): exit 1, access change named" '[ "$RC" = 1 ] && has "ACCESS CHANGED" && has "true()"'
mkscen unk "s/^  Rights: read\$/  Rights: read\n  Frobnicate: yes/"
run "$PK" "$W/sc/unk"
chk "K3 an unknown line inside an access rule changes the snapshot (exit 1), never vanishes" '[ "$RC" = 1 ] && has "not understood by this check" && has "Frobnicate: yes"'
chk "K3b it is recorded verbatim as an entity-raw fact" 'grep -q "^entity-raw	ToeicBuddy.Attempt	.*	  Frobnicate: yes	yes" "$PK/docs/security/access-snapshot.txt"'
mkscen shape1 's/^Access rules for ToeicBuddy.Attempt:$/Rules of ToeicBuddy.Attempt:/'
run "$PK" "$W/sc/shape1"; chk "K4 show access with neither expected first line: could-not-run (4)" '[ "$RC" = 4 ] && has "ToeicBuddy.Attempt"'
mkscen shape2 's/create or modify user role Learner/define role Learner/'
run "$PK" "$W/sc/shape2"; chk "K5 describe user role without its create or modify statement: 4" '[ "$RC" = 4 ] && has "create or modify user role"'
# K5b: the captured user-roles table with its footer count raised by one (rows no longer match)
mkdir -p "$W/basefoot"; cp "$FX/base/"* "$W/basefoot/"; sed 's/^(4 user roles)$/(5 user roles)/' "$FX/base/show-user-roles.txt" > "$W/basefoot/show-user-roles.txt"
OUT=$(cd "$PK" && env -u PROJECT_ROOT -u MPR_FILE MXCLI="$FX/mxcli-stub.sh" SECX_DIR="$FX/base" SECX_BASE="$W/basefoot" bash "$PK/bin/security-check.sh" 2>&1); RC=$?
chk "K5b a table whose rows do not match its own footer count: could-not-run (4), never an emptier snapshot" '[ "$RC" = 4 ] && has "show user roles"'
mkscen shape3 's/^## Page Access/## Pages/'
run "$PK" "$W/sc/shape3"; chk "K6 matrix without its Page Access section: 4" '[ "$RC" = 4 ] && has "Page Access"'
mkscen shape4 's/^## Microflow Access/## Microflows/'
run "$PK" "$W/sc/shape4"; chk "K7 matrix without its Microflow Access section: 4" '[ "$RC" = 4 ]'
chk "K8 the real unfiltered matrix capture has both sections (what the shape check expects)" 'grep -q "^## Page Access" "$FX/base/security-matrix-unfiltered.txt" && grep -q "^## Microflow Access" "$FX/base/security-matrix-unfiltered.txt"'
OUT=$(cd "$PK" && env -u PROJECT_ROOT -u MPR_FILE MXCLI="$FX/mxcli-stub.sh" SECX_DIR="$FX/base" SECX_BASE="$FX/base" SECX_FAILCMD="show demo users" bash "$PK/bin/security-check.sh" 2>&1); RC=$?
chk "K9 S1: a failing command shows its exit code and what mxcli printed" '[ "$RC" = 4 ] && has "(mxcli exit 1): Error: the model could not be read"'

echo "-- L R3 Windows line endings"
PL="$(mkproj l single)"
run "$PL" base >/dev/null; run "$PL" base --approve --reason "fixture l"; accept_all "$PL" base; run "$PL" base
chk "L0 baseline clean first" '[ "$RC" = 0 ]'
sed 's/$/\r/' "$PL/docs/security/access-approved.txt" > "$W/appr.crlf"; cp "$W/appr.crlf" "$PL/docs/security/access-approved.txt"
sed 's/$/\r/' "$PL/.claude/loop/security-accepted.tsv" > "$W/acc.crlf"; cp "$W/acc.crlf" "$PL/.claude/loop/security-accepted.tsv"
cp "$PL/docs/security/access-approved.txt" "$W/appr.before"
run "$PL" base
chk "L1 approved and accepted files with CRLF still give a clean result" '[ "$RC" = 0 ] && has "verdict=clean new=0 access_changes=0"'
chk "L2 the user files were not rewritten" 'cmp -s "$W/appr.before" "$PL/docs/security/access-approved.txt" && cmp -s "$W/acc.crlf" "$PL/.claude/loop/security-accepted.tsv"'
run "$PL" m3
chk "L3 a real change is still reported with CRLF files (and not hundreds of them)" '[ "$RC" = 1 ] && has "can now see ALL rows of ToeicBuddy.Attempt" && [ "$(grep -c "^  - " <<<"$OUT")" -lt 10 ]'

echo "-- M R4 approval written by --approve only"
PM="$(mkproj m single)"
run "$PM" base >/dev/null; run "$PM" base --approve --reason "fixture m"; accept_all "$PM" base; run "$PM" base
chk "M0 baseline clean" '[ "$RC" = 0 ]'
run "$PM" m3 >/dev/null; cp "$PM/docs/security/access-snapshot.txt" "$PM/docs/security/access-approved.txt"
run "$PM" m3
chk "M1 snapshot hand-copied over the approved file: exit 1, plain message" '[ "$RC" = 1 ] && has "the approved copy was not written by --approve: ask the person who approves access to run it again" && has "verdict=approval-mismatch"'
run "$PM" m3 --json
chk "M1b --json carries the same verdict" 'has "\"verdict\":\"approval-mismatch\""'
run "$PM" m3 --approve --reason "fixture m re-approved by the person"
run "$PM" m3
chk "M2 after a real --approve the approved copy is trusted again (only the lint findings remain)" '[ "$RC" = 1 ] && ! has "approval-mismatch" && has "verdict=new-findings"'
PM2="$(mkproj m2 single)"
run "$PM2" base >/dev/null; run "$PM2" base --approve --reason "fixture m2"; accept_all "$PM2" base
printf 'SEC005\tStrict mode is disabled\tadded by hand\t2026-01-01\n' >> "$PM2/.claude/loop/security-accepted.tsv"
run "$PM2" base
chk "M3 a line appended to the accepted list by hand: exit 1, plain message" '[ "$RC" = 1 ] && has "the accepted list was not written by --accept"'
run "$PM2" base --accept SEC003 "Demo users" --reason "x"
chk "M4 --accept refuses to bless a hand-edited list" '[ "$RC" = 1 ]'
PM3="$(mkproj m3 single)"
run "$PM3" base >/dev/null; run "$PM3" base --approve --reason "fixture m3"; rm -f "$PM3/docs/security/approvals.tsv"; run "$PM3" base
chk "M5 approved copy with no approvals row: exit 1" '[ "$RC" = 1 ] && has "was not written by --approve"'

echo "-- N S2 who, S3 wording, S4 --accept-file, S5 words, R5 sentence"
PN="$(mkproj n single)"; (cd "$PN" && git init -q && git config user.name "Test Approver" && git config user.email "nobody@example.com") >/dev/null 2>&1
run "$PN" base
chk "N1 first run writes the accept template, reason column EMPTY, and says so in one line" '[ "$RC" = 3 ] && [ -f "$PN/docs/security/accept-template.tsv" ] && has "accept-template.tsv" && awk -F"\t" "!/^#/ { n++; if (NF!=3 || \$3!=\"\") bad=1 } END { exit (bad || n!=16) }" "$PN/docs/security/accept-template.tsv"'
chk "N1b S5: the first-run listing puts plain words after the id" 'hasraw "[SEC003 - demo users on at production level] Demo users" && hasraw "[SEC005 - strict security mode is off]" && hasraw "[SEC010 - a role can open a page but not read its data]" && hasraw "[CONV007 - a role can read or change every row]"'
run "$PN" base --approve --reason "fixture n"
grep -v '^#' "$PN/docs/security/accept-template.tsv" | awk -F'\t' '{ print $1 "\t" $2 "\tfixture reason for " NR }' > "$W/filled.tsv"
head -3 "$PN/docs/security/accept-template.tsv" | grep -v '^#' > "$W/partial.tsv"
run "$PN" base --accept-file "$PN/docs/security/accept-template.tsv"
chk "N2 the unedited template (empty reasons) is refused, nothing accepted, bad lines named" '[ "$RC" = 2 ] && has "NOTHING was accepted" && has "line 2:" && [ ! -e "$PN/.claude/loop/security-accepted.tsv" ]'
{ cat "$W/filled.tsv"; printf 'CONV007\tno such finding text\tbecause\n'; } > "$W/mixed.tsv"
run "$PN" base --accept-file "$W/mixed.tsv"
chk "N3 one bad line (matches nothing) blocks the whole file; that line is named" '[ "$RC" = 2 ] && has "line 17:" && has "no such finding text" && [ ! -e "$PN/.claude/loop/security-accepted.tsv" ]'
printf 'CONV007\tunconstrained READ\tbecause\n' > "$W/amb.tsv"
run "$PN" base --accept-file "$W/amb.tsv"
chk "N4 an ambiguous element is refused" '[ "$RC" = 2 ] && has "matches" && has "be more specific"'
run "$PN" base --accept-file "$W/filled.tsv" --reason x
chk "N5 --reason with --accept-file is a usage error" '[ "$RC" = 2 ]'
run "$PN" base --accept-file "$W/filled.tsv"
chk "N6 the filled file accepts all 16 findings, each with its own reason and date" '[ "$RC" = 0 ] && [ "$(grep -vc "^#" "$PN/.claude/loop/security-accepted.tsv")" = 16 ] && grep -q "fixture reason for 16" "$PN/.claude/loop/security-accepted.tsv"'
run "$PN" base
chk "N7 rerun is clean (0): the accept-file decision carries a valid checksum" '[ "$RC" = 0 ] && has "verdict=clean"'
chk "N8 S2: approvals.tsv has a who column with the git user name and no e-mail address" 'grep -q "	approve	Test Approver	fixture n	" "$PN/docs/security/approvals.tsv" && grep -q "	accept	Test Approver	" "$PN/docs/security/approvals.tsv" && ! grep -q "@" "$PN/docs/security/approvals.tsv"'
chk "N9 R5: the clean output says in one sentence what it does not cover" 'has "does not cover published REST/OData services and their roles, nanoflow or workflow access, or which roles a user role may assign"'
chk "N10 S3: not-clean wording is gone; the new line is on a changed run" '! has "An agent reports this and stops"'
run "$PN" m3
chk "N11 S3: the not-clean line reads for a person" 'has "Not clean. What is wrong is listed above; a person decides whether to fix it or approve it."'
PU="$(mkproj u single)"
OUT=$(cd "$PU" && env -u PROJECT_ROOT -u MPR_FILE GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 USER=fixture-user MXCLI="$FX/mxcli-stub.sh" SECX_DIR="$FX/base" SECX_BASE="$FX/base" bash "$PU/bin/security-check.sh" --approve --reason "fixture u" 2>&1); RC=$?
chk "N12 S2: without a git user the account name is recorded" '[ "$RC" = 0 ] && grep -q "	approve	fixture-user	fixture u	" "$PU/docs/security/approvals.tsv"'

echo "-- O second review: the remedy, the template, the name"
chk "O1 M4's refusal names --approve as the way to re-confirm" 'run "$PM2" base --accept SEC003 "Demo users" --reason "x"; has "--approve"'
PO="$(mkproj o single)"
run "$PO" base >/dev/null; run "$PO" base --approve --reason "fixture o"; accept_all "$PO" base; run "$PO" base
chk "O2 baseline clean" '[ "$RC" = 0 ]'
printf 'SEC005\tStrict mode is disabled\tmerged in from the other branch\t2026-01-02\nSEC003\tDemo users are enabled at Production security level\tmerged too\t2026-01-02\n' >> "$PO/.claude/loop/security-accepted.tsv"
run "$PO" base
chk "O3 a merged accepted list (two lines appended): exit 1, approval-mismatch, message names --approve" '[ "$RC" = 1 ] && has "verdict=approval-mismatch" && has "bin/security-check.sh --approve --reason"'
run "$PO" base --accept-file "$W/filled.tsv"
chk "O4 --accept-file on the mismatched list keeps refusing (1) and names --approve" '[ "$RC" = 1 ] && has "--approve"'
run "$PO" base --approve --reason "fixture o: merged list reviewed in git"
chk "O5 --approve shows the accepted list it confirms, and exits 0" '[ "$RC" = 0 ] && has "Accepted findings you are confirming" && has "merged in from the other branch"'
chk "O6 approvals.tsv now has a fresh approve row and a fresh accept row" '[ "$(grep -c "re-confirmed by --approve" "$PO/docs/security/approvals.tsv")" = 1 ] && [ "$(grep -c "	approve	" "$PO/docs/security/approvals.tsv")" = 2 ]'
run "$PO" base
chk "O7 the next check is clean (0)" '[ "$RC" = 0 ] && has "verdict=clean"'
PT="$(mkproj t single)"
run "$PT" base >/dev/null
printf '# keep\nSEC003\tDemo users are enabled at Production security level\tmy half-written reason\n' > "$PT/docs/security/accept-template.tsv"
run "$PT" base
chk "O8 a template a person is filling in survives a second first run, and one line says so" '[ "$RC" = 3 ] && grep -q "my half-written reason" "$PT/docs/security/accept-template.tsv" && has "Kept your existing" && has "delete it to get a fresh one"'
rm -f "$PT/docs/security/accept-template.tsv"; run "$PT" base
chk "O9 with the template deleted a fresh one is written" '[ "$(grep -vc "^#" "$PT/docs/security/accept-template.tsv")" = 16 ]'
PE="$(mkproj e single)"; (cd "$PE" && git init -q && git config user.name "someone@example.com") >/dev/null 2>&1
OUT=$(cd "$PE" && env -u PROJECT_ROOT -u MPR_FILE GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 USER=fixture-user MXCLI="$FX/mxcli-stub.sh" SECX_DIR="$FX/base" SECX_BASE="$FX/base" bash "$PE/bin/security-check.sh" --approve --reason "fixture e" 2>&1); RC=$?
chk "O10 a git user.name holding an @ is not recorded; the account name is" '[ "$RC" = 0 ] && grep -q "	approve	fixture-user	" "$PE/docs/security/approvals.tsv" && ! grep -q "@" "$PE/docs/security/approvals.tsv"'

echo "-- P third review: --approve shows every accepted line, a reasonless line accepts nothing"
PR="$(mkproj r single)"; ACCR="$PR/.claude/loop/security-accepted.tsv"
run "$PR" base >/dev/null; run "$PR" base --approve --reason "fixture r"; accept_all "$PR" base; run "$PR" base
chk "P0 baseline clean" '[ "$RC" = 0 ]'
cp "$ACCR" "$W/acc.r.good"
S5=$(grep '^SEC005	' "$W/acc.r.good" | cut -f2)
grep -v '^SEC005	' "$W/acc.r.good" > "$ACCR"; printf 'SEC005\t%s\n' "$S5" >> "$ACCR"
run "$PR" base --approve --reason "fixture r: should refuse"
chk "P1 a reasonless SEC005 line: --approve refuses (1), names the line, records nothing" '[ "$RC" = 1 ] && has "REFUSED" && has "no reason, accepts nothing: [SEC005] Strict mode is disabled" && [ "$(grep -c "	approve	" "$PR/docs/security/approvals.tsv")" = 1 ]'
# P1b a reason of only spaces (and one of only a tab) is no reason either
grep -v '^SEC005	' "$W/acc.r.good" > "$ACCR"; printf 'SEC005\t%s\t   \n' "$S5" >> "$ACCR"
run "$PR" base --approve --reason "fixture r: spaces-only reason"
chk "P1b a spaces-only reason: --approve refuses (1) and names the line" '[ "$RC" = 1 ] && has "REFUSED" && has "no reason, accepts nothing: [SEC005] Strict mode is disabled"'
grep -v '^SEC005	' "$W/acc.r.good" > "$ACCR"; printf 'SEC005\t%s\n' "$S5" >> "$ACCR"
# an old --approve would have recorded this list's checksum; simulate that record by hand
printf '2026-01-01\taccept\tfixture\thand-recorded\t%s\n' "$(tr -d '\r' < "$ACCR" | cksum | awk '{print $1}')" >> "$PR/docs/security/approvals.tsv"
run "$PR" base --json
chk "P2 even with a matching checksum, the reasonless line accepts nothing: SEC005 still counts as new" 'has "\"new\":1" && has "Strict mode is disabled"'
{ cat "$W/acc.r.good"; printf 'SEC999\tjunk\tbecause\n'; } > "$ACCR"
run "$PR" base --approve --reason "fixture r: junk id"
chk "P3 a junk rule id line: --approve refuses (1) and names it" '[ "$RC" = 1 ] && has "not a security rule id: [SEC999] junk"'
{ cat "$W/acc.r.good"; printf 'SEC005\tStrict mode was disabled in an older model\tstale but reasoned\t2026-01-01\n'; } > "$ACCR"
run "$PR" base --approve --reason "fixture r: stale line shown and allowed"
chk "P4 a stale line is shown, counted, allowed (0)" '[ "$RC" = 0 ] && has "matches no current finding (stale): [SEC005] Strict mode was disabled in an older model" && has "1 stale line(s) kept"'
run "$PR" base
chk "P5 the normal check reports the stale line in one line and stays clean (0)" '[ "$RC" = 0 ] && has "1 accepted line(s) match no current finding (stale)" && has "verdict=clean"'

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
